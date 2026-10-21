// swift-log sink for the Linux port (plan T10).
//
// macOS Chops logged through `os.Logger` (AppLogger) and `os.log` + a dated file
// (AgentLogger). Linux replaces both destinations with one machine-readable sink:
// every record is a single JSON object on one stdout line, so `journalctl`,
// `chopsd` consumers, and tests can parse it without a platform logging daemon.
//
// The handler is deliberately independent of `LoggingSystem.bootstrap`: AppLogger
// builds each `Logger` with an explicit handler factory. Library code must not
// commandeer the process-global logging factory, and tests can capture output by
// injecting a `LogOutput` instead of swapping global state.

import Foundation
import Logging

/// Thread-safe destination for encoded log lines.
///
/// Production uses `LogOutput.shared`, which writes to stdout. Tests inject their
/// own instance (or temporarily replace the shared writer) and assert the JSON.
public final class LogOutput: @unchecked Sendable {
    /// Where a `LogOutput` sends its lines. Exposed so tests and `chopsd` startup
    /// checks can prove the default really is stdout.
    public enum Destination: String, Sendable, Equatable {
        case standardOutput
        case custom
    }

    /// Process-wide default destination: one JSON object per line on stdout.
    public static let shared = LogOutput.standardOutput()

    private let lock = NSLock()
    private var writer: @Sendable (String) -> Void
    private var currentDestination: Destination

    /// Writes to stdout through `FileHandle.standardOutput`.
    public static func standardOutput() -> LogOutput {
        LogOutput(writer: standardOutputWriter, destination: .standardOutput)
    }

    /// Writes through an injected closure. The line already contains its trailing
    /// newline; implementations should write it verbatim.
    public init(writer: @escaping @Sendable (String) -> Void) {
        self.writer = writer
        self.currentDestination = .custom
    }

    private init(writer: @escaping @Sendable (String) -> Void, destination: Destination) {
        self.writer = writer
        self.currentDestination = destination
    }

    public var destination: Destination {
        lock.lock()
        defer { lock.unlock() }
        return currentDestination
    }

    /// Appends one encoded line. Writes are serialized so concurrent loggers
    /// cannot interleave halves of a JSON object.
    public func write(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        writer(line)
    }

    /// Replaces the destination (used by the QA harness and `chopsd --log-file`).
    public func setWriter(_ writer: @escaping @Sendable (String) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        self.writer = writer
        currentDestination = .custom
    }

    /// Restores the stdout destination.
    public func useStandardOutput() {
        lock.lock()
        defer { lock.unlock() }
        writer = Self.standardOutputWriter
        currentDestination = .standardOutput
    }

    private static let standardOutputWriter: @Sendable (String) -> Void = { line in
        guard let data = line.data(using: .utf8) else { return }
        FileHandle.standardOutput.write(data)
    }
}

/// swift-log `LogHandler` that emits one JSON object per line.
///
/// Record shape (all values strings so log consumers never need schema branches):
///
/// ```json
/// {"timestamp":"2026-10-21T16:00:00.123Z","level":"warning","label":"md.chops.fileIO",
///  "message":"Failed to watch: /tmp/x","source":"chopscore",
///  "metadata":{"category":"fileIO","subsystem":"md.chops"},"file":"...","function":"...","line":24}
/// ```
public struct JSONLineLogHandler: LogHandler {
    public var logLevel: Logger.Level
    public var metadata: Logger.Metadata
    public var metadataProvider: Logger.MetadataProvider?

    private let label: String
    private let output: LogOutput

    public init(
        label: String,
        output: LogOutput = .shared,
        level: Logger.Level = .info,
        metadata: Logger.Metadata = [:],
        metadataProvider: Logger.MetadataProvider? = nil
    ) {
        self.label = label
        self.output = output
        self.logLevel = level
        self.metadata = metadata
        self.metadataProvider = metadataProvider
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(event: LogEvent) {
        var merged = self.metadata
        if let metadataProvider {
            for (key, value) in metadataProvider.get() where merged[key] == nil {
                merged[key] = value
            }
        }
        if let metadata = event.metadata {
            merged.merge(metadata) { _, new in new }
        }

        let record = JSONLineLogRecord(
            timestamp: Self.iso8601Timestamp(),
            level: event.level.rawValue,
            label: label,
            message: event.message.description,
            source: event.source,
            metadata: merged.mapValues { $0.description },
            file: event.file,
            function: event.function,
            line: event.line,
            error: event.error.map { String(describing: $0) }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(record),
              let json = String(data: data, encoding: .utf8) else {
            // Encoding Foundation primitives cannot realistically fail; if it ever
            // does, dropping the record is better than crashing a file watcher.
            return
        }
        output.write(json + "\n")
    }

    private static func iso8601Timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }
}

private struct JSONLineLogRecord: Encodable {
    let timestamp: String
    let level: String
    let label: String
    let message: String
    let source: String
    let metadata: [String: String]
    let file: String
    let function: String
    let line: UInt
    let error: String?
}
