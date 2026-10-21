import Foundation
import XCTest

@testable import chopscore

/// Store path resolution (plan T05): `${XDG_DATA_HOME:-$HOME/.local/share}/Chops/chops.db`.
/// These tests only compute paths from an explicit environment dictionary — they never
/// resolve or open the real user home.
final class StoreLocationTests: XCTestCase {
    func testDatabaseURLUsesXDGDataHomeWhenSet() throws {
        let url = try StoreLocation.databaseURL(
            environment: [
                "XDG_DATA_HOME": "/tmp/opencode/fixture-xdg",
                "HOME": "/tmp/opencode/unused-home",
            ]
        )
        XCTAssertEqual(url.path, "/tmp/opencode/fixture-xdg/Chops/chops.db")
    }

    func testDatabaseURLFallsBackToHomeLocalShare() throws {
        let url = try StoreLocation.databaseURL(
            environment: ["HOME": "/tmp/opencode/fixture-home"]
        )
        XCTAssertEqual(url.path, "/tmp/opencode/fixture-home/.local/share/Chops/chops.db")
        XCTAssertEqual(url.lastPathComponent, StoreLocation.databaseFileName)
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, StoreLocation.appDirectoryName)
    }

    func testEmptyXDGDataHomeFallsBackToHome() throws {
        let dataDirectory = try StoreLocation.dataDirectory(
            environment: ["XDG_DATA_HOME": "", "HOME": "/tmp/opencode/fixture-home"]
        )
        XCTAssertEqual(dataDirectory.path, "/tmp/opencode/fixture-home/.local/share")
    }

    func testMissingHomeAndXDGThrows() {
        XCTAssertThrowsError(try StoreLocation.databaseURL(environment: [:])) { error in
            XCTAssertEqual(error as? StoreLocationError, .homeDirectoryUnavailable)
        }
    }

    func testOpenDefaultUsesInjectedEnvironment() throws {
        let scratch = try StoreTestSupport.makeTemporaryDirectory(prefix: "chopscore-location")
        addTeardownBlock { try? FileManager.default.removeItem(at: scratch) }

        let environment = [
            "XDG_DATA_HOME": scratch.appendingPathComponent("xdg-data").path,
            "HOME": scratch.appendingPathComponent("home").path,
        ]
        let expected = scratch.appendingPathComponent("xdg-data/Chops/chops.db")

        let store = try ChopsStore.openDefault(environment: environment)
        XCTAssertEqual(store.databaseURL.path, expected.path)
        XCTAssertTrue(store.databaseURL.path.hasPrefix(scratch.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path))
    }
}
