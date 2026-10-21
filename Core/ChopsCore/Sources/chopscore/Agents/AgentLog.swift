import Foundation

/// Logging seam for the agent transports.
///
/// The transports only need "emit a diagnostic line"; callers inject a sink and tests
/// capture it to assert exactly which binary produced which stdout/stderr. T10 adds the
/// swift-log bridge (`AgentLog.structured`) on top of the original seam: the production
/// default stays silent so constructing an `AgentEnvironment` never emits output on its
/// own, while `chopsd` (T11) and callers that want diagnostics opt in explicitly.
public typealias AgentLogSink = @Sendable (String) -> Void

public enum AgentLog {
    /// Default sink: keep the core library quiet. Callers opt in via `structured`.
    public static let disabled: AgentLogSink = { _ in }

    /// Convenience sink for local command-line use.
    public static let standardError: AgentLogSink = { message in
        FileHandle.standardError.write(Data(("[agent] " + message + "\n").utf8))
    }

    /// swift-log sink: transport diagnostics flow through `AgentLogger.shared` and are
    /// emitted as structured JSON lines (debug level, so `CHOPS_AGENT_DEBUG` gates them).
    public static let structured: AgentLogSink = { message in
        AgentLogger.shared.debug(message)
    }

    /// swift-log sink bound to a specific `AgentLogger` (tests inject a capturing one).
    public static func structured(using logger: AgentLogger) -> AgentLogSink {
        { message in logger.debug(message) }
    }
}
