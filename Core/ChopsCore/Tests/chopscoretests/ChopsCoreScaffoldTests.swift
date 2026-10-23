import XCTest
@testable import chopscore

/// Scaffold smoke test for the Linux port (plan task T03).
/// Batch 1 replaces this with fixture-driven unit tests; every fixture home is a
/// tmp copy of `linux/fixtures/home` — never the real `$HOME`.
final class ChopsCoreScaffoldTests: XCTestCase {
    func testScaffoldCompilesAndLinks() {
        XCTAssertEqual(ChopsCore.version, "0.1.0-dev")
    }
}
