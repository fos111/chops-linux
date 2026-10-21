import Foundation
import XCTest

@testable import chopscore

/// Shared plumbing for the one-shot agent transport tests (plan T08).
///
/// The transports are driven by the COMMITTED stub binaries
/// (`linux/fixtures/fake-claude`, `linux/fixtures/fake-codex`) reached exclusively
/// through an injected `PATH` that begins with the fixtures directory. The stubs are
/// symlinked under their real CLI names (`claude`, `codex`) in a scratch directory so
/// the production PATH lookup resolves them without renaming the committed files.
///
/// The real `$HOME` is never read or written: every test injects a scratch home plus
/// `HOME`/`TMPDIR`/`XDG_*` pointing into that scratch directory.
enum AgentTransportTestSupport {
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // chopscoretests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // ChopsCore
            .deletingLastPathComponent() // Core
            .deletingLastPathComponent() // <repo>
    }

    static var fixturesDirectory: URL {
        repositoryRoot.appendingPathComponent("linux/fixtures", isDirectory: true)
    }

    static func stubURL(_ name: String) -> URL {
        fixturesDirectory.appendingPathComponent(name)
    }

    /// Scratch directory with `claude`/`codex` symlinks to the committed stubs.
    @discardableResult
    static func makeStubPathDirectory(in scratch: URL) throws -> URL {
        let bin = scratch.appendingPathComponent("stub-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let aliases = ["claude": "fake-claude", "codex": "fake-codex"]
        for (alias, stub) in aliases {
            let link = bin.appendingPathComponent(alias)
            if !FileManager.default.fileExists(atPath: link.path) {
                try FileManager.default.createSymbolicLink(
                    at: link,
                    withDestinationURL: stubURL(stub)
                )
            }
        }
        return bin
    }

    /// Child environment for a test: fixture dir prepended, then the stub alias dir, then
    /// system dirs (the stubs are `#!/usr/bin/env bash`, so `bash` must stay reachable).
    static func makeEnvironment(scratch: URL, home: URL) throws -> [String: String] {
        let stubBin = try makeStubPathDirectory(in: scratch)
        let tmp = scratch.appendingPathComponent("tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = [
            fixturesDirectory.path,
            stubBin.path,
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ].joined(separator: ":")
        env["HOME"] = home.path
        env["XDG_CONFIG_HOME"] = home.appendingPathComponent(".config", isDirectory: true).path
        env["XDG_DATA_HOME"] = home.appendingPathComponent(".local/share", isDirectory: true).path
        env["TMPDIR"] = tmp.path
        env.removeValue(forKey: "CLAUDECODE")
        return env
    }

    /// Base class owning a scratch directory plus a tmp copy of the fixture home.
    class TransportTestCase: XCTestCase {
        private(set) var scratch: URL!
        private(set) var home: URL!
        private(set) var environment: [String: String]!
        let recorder = AgentLogRecorder()

        override func setUpWithError() throws {
            try super.setUpWithError()
            scratch = try StoreTestSupport.makeTemporaryDirectory(prefix: "chopscore-agent")
            home = try StoreTestSupport.copyFixtureHome(into: scratch)
            environment = try AgentTransportTestSupport.makeEnvironment(scratch: scratch, home: home)
        }

        override func tearDownWithError() throws {
            if let scratch {
                try? FileManager.default.removeItem(at: scratch)
            }
            scratch = nil
            home = nil
            environment = nil
            try super.tearDownWithError()
        }

        var configuration: AgentEnvironment {
            AgentEnvironment(
                homeDirectory: home,
                environment: environment,
                log: recorder.sink
            )
        }

        /// Copies a fixture skill out of the tmp home so a test can assert on its path.
        func skillPath(_ relative: String) -> URL {
            home.appendingPathComponent(relative)
        }

        func contents(of url: URL) throws -> String {
            try String(contentsOf: url, encoding: .utf8)
        }
    }
}

/// Thread-safe collector for the injected `AgentLogSink`.
final class AgentLogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func record(_ message: String) {
        lock.lock()
        storage.append(message)
        lock.unlock()
    }

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var transcript: String { lines.joined(separator: "\n") }

    var sink: AgentLogSink { { [self] message in record(message) } }

    func lines(containing needle: String) -> [String] {
        lines.filter { $0.contains(needle) }
    }
}
