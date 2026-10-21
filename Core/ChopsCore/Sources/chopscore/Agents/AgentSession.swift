import Foundation

/// Transport-agnostic surface for the one-shot agent transports.
///
/// Port of the frozen macOS `AgentSession` protocol
/// (`Chops/Services/Agents/AgentSession.swift`). The macOS conformers are
/// `@MainActor @Observable` because SwiftUI observes them directly; on Linux the
/// transports are plain actors consumed by an HTTP service, so the same observable
/// state is exposed through `async` accessors instead of Observation.
///
/// Implemented by:
/// - `ClaudeCLIAgent` — one-shot `claude --print` against the user's installed binary
/// - `CodexCLIAgent`  — one-shot `codex exec` against the user's installed binary
///
/// Permission flow is intentionally absent: both one-shot transports disable tool use
/// and let Chops own every disk write (the macOS conformers' permission methods are
/// no-ops for the same reason).
public protocol AgentSession: AnyObject, Sendable {
    var responseText: String { get async }
    var thoughtText: String { get async }
    var currentActivity: String? { get async }
    var pendingWrites: [PendingWrite] { get async }
    var deferredContent: [String: String] { get async }
    var isConnected: Bool { get async }
    var isConnecting: Bool { get async }
    var isProcessing: Bool { get async }
    /// When non-nil, the timestamp at which the in-flight turn started.
    var turnStartedAt: Date? { get async }
    /// Chronological feed of what the agent has done during the current turn. Reset on
    /// each new prompt.
    var activities: [AgentActivity] { get async }
    var lastError: String? { get async }
    var isBypassMode: Bool { get async }

    func startConnect(workingDirectory: URL, systemPrompt: String?) async
    func disconnect() async

    func prompt(_ text: String) async throws
    func cancelPrompt() async

    func clearPendingWrites() async
    func primeDeferredContent(for path: String, content: String) async

    /// Strip vendor-specific tags / formatting before display. Default returns text unchanged.
    func conversationalText(from text: String) -> String
}
