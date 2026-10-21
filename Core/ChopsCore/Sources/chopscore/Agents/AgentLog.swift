import Foundation

/// Minimal logging seam for the agent transports.
///
/// The full structured logging sink (swift-log, per plan task T10) is deliberately not
/// ported here. The transports only need "emit a diagnostic line"; callers inject a
/// sink, tests capture it to assert exactly which binary produced which stdout/stderr,
/// and the production default is silent until T10 wires a real sink.
public typealias AgentLogSink = @Sendable (String) -> Void

public enum AgentLog {
    /// Default sink: keep the core library quiet. chopsd installs its own sink in T10/T11.
    public static let disabled: AgentLogSink = { _ in }

    /// Convenience sink for local command-line use (chopsd may replace it with swift-log).
    public static let standardError: AgentLogSink = { message in
        FileHandle.standardError.write(Data(("[agent] " + message + "\n").utf8))
    }
}
