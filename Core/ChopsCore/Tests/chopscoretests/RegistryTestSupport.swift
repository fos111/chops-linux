import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

@testable import chopscore

/// Lifecycle wrapper around the committed `scripts/linux/mock-registry.py` fixture.
///
/// Every registry test starts this server on the fixed loopback port (47116), points
/// all four injectable endpoint bases at it, and stops it again. No test reaches the
/// real skills.sh / GitHub hosts.
final class MockRegistryServer: @unchecked Sendable {
    static let defaultPort = 47116

    let baseURL: URL
    private let port: Int
    private let process: Process
    private let logHandle: FileHandle
    private let logURL: URL
    private let scratch: URL

    private init(port: Int, process: Process, logHandle: FileHandle, logURL: URL, scratch: URL) {
        self.port = port
        self.baseURL = URL(string: "http://127.0.0.1:\(port)")!
        self.process = process
        self.logHandle = logHandle
        self.logURL = logURL
        self.scratch = scratch
    }

    // MARK: - Lifecycle

    static func start(port: Int = defaultPort) throws -> MockRegistryServer {
        let script = StoreTestSupport.repositoryRoot
            .appendingPathComponent("scripts/linux/mock-registry.py")
        guard FileManager.default.fileExists(atPath: script.path) else {
            throw MockRegistryError.scriptMissing(script.path)
        }

        let scratch = try StoreTestSupport.makeTemporaryDirectory(prefix: "chopscore-mock-registry")
        let logURL = scratch.appendingPathComponent("server.log")
        guard FileManager.default.createFile(atPath: logURL.path, contents: nil) else {
            throw MockRegistryError.captureFileFailed(logURL.path)
        }
        let logHandle = try FileHandle(forWritingTo: logURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path, "--port", "\(port)"]
        process.standardOutput = logHandle
        process.standardError = logHandle

        do {
            try process.run()
        } catch {
            try? logHandle.close()
            try? FileManager.default.removeItem(at: scratch)
            throw MockRegistryError.launchFailed(error.localizedDescription)
        }

        let server = MockRegistryServer(
            port: port,
            process: process,
            logHandle: logHandle,
            logURL: logURL,
            scratch: scratch
        )
        try server.waitUntilReady()
        return server
    }

    func stop() {
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()
        try? logHandle.close()
        try? FileManager.default.removeItem(at: scratch)
    }

    deinit {
        if process.isRunning {
            process.terminate()
        }
    }

    // MARK: - Diagnostics

    func logText() -> String {
        (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
    }

    func recordedRequests() async throws -> [RecordedRequest] {
        let (data, status) = try await URLSessionRegistryHTTPClient()
            .get(baseURL.appendingPathComponent("__requests"), userAgent: nil)
        guard status == 200 else {
            throw MockRegistryError.badStatus(status)
        }
        return try JSONDecoder().decode(RequestLog.self, from: data).requests
    }

    func requestCount(path: String) async throws -> Int {
        try await recordedRequests().filter { $0.path == path }.count
    }

    // MARK: - Readiness

    private func waitUntilReady() throws {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if let data = Self.getSync(healthURL, timeout: 0.5),
               let text = String(data: data, encoding: .utf8),
               text.contains("chops-mock-registry") {
                return
            }

            if !process.isRunning {
                let log = logText()
                stop()
                throw MockRegistryError.exitedDuringStartup(port: port, log: log)
            }

            Thread.sleep(forTimeInterval: 0.05)
        }

        let log = logText()
        stop()
        throw MockRegistryError.timedOut(port: port, log: log)
    }

    private var healthURL: URL {
        baseURL.appendingPathComponent("__health")
    }

    /// Blocking probe used only from test setup. The completion handler runs on
    /// URLSession's own queue, so waiting on the calling thread cannot deadlock.
    private static func getSync(_ url: URL, timeout: TimeInterval) -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let box = DataBox()
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            box.set(data)
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + timeout + 1)
        return box.get()
    }

    // MARK: - Types

    struct RecordedRequest: Codable, Sendable, Equatable {
        let method: String
        let path: String
        let query: String
        let userAgent: String
    }

    private struct RequestLog: Codable {
        let requests: [RecordedRequest]
    }

    enum MockRegistryError: Error, LocalizedError {
        case scriptMissing(String)
        case captureFileFailed(String)
        case launchFailed(String)
        case badStatus(Int)
        case exitedDuringStartup(port: Int, log: String)
        case timedOut(port: Int, log: String)

        var errorDescription: String? {
            switch self {
            case .scriptMissing(let path):
                "mock registry script missing at \(path)"
            case .captureFileFailed(let path):
                "could not create mock registry log at \(path)"
            case .launchFailed(let detail):
                "could not launch mock registry: \(detail)"
            case .badStatus(let status):
                "mock registry returned HTTP \(status)"
            case .exitedDuringStartup(let port, let log):
                "mock registry exited during startup on 127.0.0.1:\(port)\n\(log)"
            case .timedOut(let port, let log):
                "mock registry did not become ready on 127.0.0.1:\(port) (is the port in use?)\n\(log)"
            }
        }
    }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Data?

    func set(_ data: Data?) {
        lock.lock()
        value = data
        lock.unlock()
    }

    func get() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
