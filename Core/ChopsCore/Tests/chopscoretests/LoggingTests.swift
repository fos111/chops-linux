import Foundation
import XCTest
@testable import chopscore

/// Plan T10 logging QA: AppLogger/AgentLogger must emit one parseable JSON object per
/// stdout record, with structured metadata. Tests inject a `LogOutput` and never touch
/// process-global swift-log state, so they are order-independent.
final class LoggingTests: XCTestCase {
    // MARK: - AppLogger

    func testAppLoggerEmitsOneJSONLinePerRecord() throws {
        let capture = LineCapture()
        let output = LogOutput { line in capture.append(line) }
        let logger = AppLogger.logger(category: "fileIO", output: output)

        logger.warning(
            "Failed to watch: /tmp/opencode/missing",
            metadata: ["path": "/tmp/opencode/missing"]
        )

        XCTAssertEqual(capture.lines.count, 1)
        let line = try XCTUnwrap(capture.lines.first)
        XCTAssertTrue(line.hasSuffix("\n"), "every JSON record ends with a newline")
        XCTAssertFalse(line.dropLast().contains("\n"), "one record == one line")

        let json = try decode(line)
        XCTAssertEqual(json["level"] as? String, "warning")
        XCTAssertEqual(json["message"] as? String, "Failed to watch: /tmp/opencode/missing")
        XCTAssertEqual(json["label"] as? String, "md.chops.fileIO")
        let source = try XCTUnwrap(json["source"] as? String)
        XCTAssertFalse(source.isEmpty)

        let metadata = try XCTUnwrap(json["metadata"] as? [String: Any])
        XCTAssertEqual(metadata["category"] as? String, "fileIO")
        XCTAssertEqual(metadata["subsystem"] as? String, "md.chops")
        XCTAssertEqual(metadata["path"] as? String, "/tmp/opencode/missing")
        print("[t10][applogger] " + line.trimmingCharacters(in: .whitespacesAndNewlines))

        let timestamp = try XCTUnwrap(json["timestamp"] as? String)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertNotNil(formatter.date(from: timestamp), "timestamp is ISO-8601 with fraction")
    }

    func testEachAppLoggerCategoryKeepsItsOwnLabelAndMetadata() throws {
        let capture = LineCapture()
        let output = LogOutput { line in capture.append(line) }

        AppLogger.logger(category: "scanning", output: output).info("scan")
        AppLogger.logger(category: "settings", output: output).info("settings")

        XCTAssertEqual(capture.lines.count, 2)
        let records = try capture.lines.map(decode)
        XCTAssertEqual(records.map { $0["label"] as? String }, ["md.chops.scanning", "md.chops.settings"])
        let categories = records.compactMap { ($0["metadata"] as? [String: Any])?["category"] as? String }
        XCTAssertEqual(categories, ["scanning", "settings"])
    }

    func testDefaultDestinationIsStandardOutput() {
        XCTAssertEqual(LogOutput.shared.destination, .standardOutput)
        XCTAssertFalse(AppLogger.subsystem.isEmpty)
    }

    // MARK: - AgentLogger

    func testAgentLoggerHonoursDebugFlagAndEmitsStructuredMetadata() throws {
        let capture = LineCapture()
        let output = LogOutput { line in capture.append(line) }
        let logger = AgentLogger(
            logger: AppLogger.logger(category: "Agent", output: output),
            debugEnabled: false
        )

        logger.info("agent started")
        logger.debug("suppressed payload")
        logger.error("agent failed")

        XCTAssertEqual(capture.lines.count, 2, "debug is gated off by default")
        let records = try capture.lines.map(decode)
        XCTAssertEqual(records[0]["level"] as? String, "info")
        XCTAssertEqual(records[1]["level"] as? String, "error")
        for record in records {
            let metadata = try XCTUnwrap(record["metadata"] as? [String: Any])
            XCTAssertEqual(metadata["channel"] as? String, "agent")
            XCTAssertEqual(metadata["category"] as? String, "Agent")
        }

        logger.debugEnabled = true
        logger.debug("visible payload")
        struct Payload: Encodable {
            let action: String
            let bytes: Int
        }
        logger.debugLogJSON(Payload(action: "send", bytes: 12), direction: .send)

        let afterEnable = try capture.lines.suffix(3).map(decode)
        XCTAssertEqual(afterEnable[0]["level"] as? String, "info")
        XCTAssertEqual(afterEnable[0]["message"] as? String, "Debug logging enabled")
        XCTAssertEqual(afterEnable[1]["level"] as? String, "debug")
        XCTAssertEqual(afterEnable[1]["message"] as? String, "visible payload")
        XCTAssertEqual(afterEnable[2]["message"] as? String, #">>> SEND: {"action":"send","bytes":12}"#)
        for line in capture.lines {
            print("[t10][agentlogger] " + line.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    func testExplicitDebugFlagOverride() {
        let output = LogOutput { _ in }
        XCTAssertFalse(AgentLogger(logger: AppLogger.logger(category: "Agent", output: output), debugEnabled: false).debugEnabled)
        XCTAssertTrue(AgentLogger(logger: AppLogger.logger(category: "Agent", output: output), debugEnabled: true).debugEnabled)
    }

    // MARK: - AgentLog seam reconciliation

    func testAgentLogStructuredSinkRoutesThroughAgentLogger() throws {
        let capture = LineCapture()
        let output = LogOutput { line in capture.append(line) }
        let logger = AgentLogger(
            logger: AppLogger.logger(category: "Agent", output: output),
            debugEnabled: true
        )

        let sink = AgentLog.structured(using: logger)
        sink("resolved binary: /tmp/opencode/fake-claude")

        XCTAssertEqual(capture.lines.count, 1)
        let record = try decode(try XCTUnwrap(capture.lines.first))
        XCTAssertEqual(record["level"] as? String, "debug")
        XCTAssertEqual(record["message"] as? String, "resolved binary: /tmp/opencode/fake-claude")
        let metadata = try XCTUnwrap(record["metadata"] as? [String: Any])
        XCTAssertEqual(metadata["channel"] as? String, "agent")
        let emitted = try XCTUnwrap(capture.lines.first)
        print("[t10][agentlog-seam] " + emitted.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testDefaultAgentLogSinkStaysSilent() {
        let capture = LineCapture()
        _ = LogOutput { line in capture.append(line) }
        AgentLog.disabled("never emitted")
        XCTAssertTrue(capture.lines.isEmpty)
    }

    // MARK: - Helpers

    private func decode(_ line: String) throws -> [String: Any] {
        let data = Data(line.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }
}

private final class LineCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ line: String) {
        lock.lock()
        storage.append(line)
        lock.unlock()
    }

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
