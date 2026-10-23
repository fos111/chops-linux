// AgentLogger — Linux port of `Chops/Services/Agents/AgentLogger.swift` (plan T10).
//
// macOS writes agent diagnostics to both `os.log` and a dated file under
// Application Support, with verbose payload logging behind the "AgentDebugLogging"
// UserDefaults key. Linux has neither unified logging nor an app sandbox, so the
// port keeps the same façade (`info`/`debug`/`error`/`debugLogJSON`) and emits the
// same information as structured JSON lines on stdout through swift-log.
//
// `debugEnabled` is stored in memory and seeded from `CHOPS_AGENT_DEBUG`; there is
// no UserDefaults on Linux. Agent transports themselves are unchanged: they still
// accept the injected `AgentLogSink`, and `AgentLog.structured` bridges that seam
// to this logger.

import Foundation
import Logging

public final class AgentLogger: @unchecked Sendable {
    public static let shared = AgentLogger()

    private let lock = NSLock()
    private var logger: Logger
    private var debugLoggingEnabled: Bool

    /// - Parameters:
    ///   - logger: swift-log logger to emit through. Defaults to the `Agent`
    ///     AppLogger category (`md.chops.Agent`).
    ///   - debugEnabled: overrides the `CHOPS_AGENT_DEBUG` seed. `nil` reads the
    ///     environment, mirroring the macOS default-off preference.
    public init(logger: Logger? = nil, debugEnabled: Bool? = nil) {
        self.logger = logger ?? AppLogger.logger(category: "Agent")
        // `debugEnabled` is this façade's gate (macOS parity); the handler itself
        // must accept debug records or Logger would filter them before they arrive.
        self.logger.logLevel = .debug
        self.debugLoggingEnabled = debugEnabled ?? Self.environmentDebugFlag()
    }

    /// Enable verbose debug logging (send/receive payloads).
    public var debugEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return debugLoggingEnabled
        }
        set {
            lock.lock()
            let wasEnabled = debugLoggingEnabled
            debugLoggingEnabled = newValue
            lock.unlock()
            if newValue && !wasEnabled {
                info("Debug logging enabled")
            }
        }
    }

    public func info(_ message: String) {
        logger.info("\(message)", metadata: Self.structuredMetadata)
    }

    public func debug(_ message: String) {
        guard debugEnabled else { return }
        logger.debug("\(message)", metadata: Self.structuredMetadata)
    }

    public func error(_ message: String) {
        logger.error("\(message)", metadata: Self.structuredMetadata)
    }

    public enum Direction: Sendable {
        case send
        case receive
    }

    /// Log a JSON-encodable value in debug mode. Centralises encoding so callers
    /// never duplicate it (identical to the macOS implementation).
    public func debugLogJSON<T: Encodable>(_ value: T, direction: Direction) {
        guard debugEnabled else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else { return }
        switch direction {
        case .send:    debug(">>> SEND: \(string)")
        case .receive: debug("<<< RECV: \(string)")
        }
    }

    private static let structuredMetadata: Logger.Metadata = [
        "channel": "agent",
        "category": "Agent",
    ]

    private static func environmentDebugFlag() -> Bool {
        guard let raw = ProcessInfo.processInfo.environment["CHOPS_AGENT_DEBUG"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else {
            return false
        }
        return ["1", "true", "yes", "on"].contains(raw)
    }
}
