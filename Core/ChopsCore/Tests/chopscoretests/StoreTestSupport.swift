import Foundation
import XCTest

@testable import chopscore

/// Shared plumbing for store tests (plan T05).
///
/// Every test writes into a fresh temporary directory. `linux/fixtures/home` is only
/// ever **copied**, never modified, and the real `$HOME` is never resolved or touched.
enum StoreTestSupport {
    /// Repository root derived from this file's path:
    /// `<repo>/Core/ChopsCore/Tests/chopscoretests/StoreTestSupport.swift`.
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // chopscoretests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // ChopsCore
            .deletingLastPathComponent() // Core
            .deletingLastPathComponent() // <repo>
    }

    static var fixtureHome: URL {
        repositoryRoot.appendingPathComponent("linux/fixtures/home", isDirectory: true)
    }

    static func makeTemporaryDirectory(prefix: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Copies `linux/fixtures/home` into `parent` and returns the copy.
    static func copyFixtureHome(into parent: URL) throws -> URL {
        let destination = parent.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.copyItem(at: fixtureHome, to: destination)
        return destination
    }

    static func store(in directory: URL) throws -> ChopsStore {
        try ChopsStore(databaseURL: directory.appendingPathComponent("Chops/chops.db"))
    }
}

/// Base class that owns a temporary scratch directory for one test.
class StoreTestCase: XCTestCase {
    private var scratchDirectory: URL?

    var scratch: URL {
        get throws {
            guard let scratchDirectory else {
                throw XCTSkip("scratch directory unavailable")
            }
            return scratchDirectory
        }
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratchDirectory = try StoreTestSupport.makeTemporaryDirectory(prefix: "chopscore-store")
    }

    override func tearDownWithError() throws {
        if let scratchDirectory {
            try? FileManager.default.removeItem(at: scratchDirectory)
        }
        scratchDirectory = nil
        try super.tearDownWithError()
    }
}
