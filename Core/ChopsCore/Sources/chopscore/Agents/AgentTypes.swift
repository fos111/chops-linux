import Foundation

/// Stable identifier for the supported coding agents. Ported from the frozen macOS
/// `AgentID` (`Chops/Models/AgentConfiguration.swift`); only the enum is portable —
/// the `@Observable` preference store that wraps it stays in the macOS app.
public enum AgentID: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case codex

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    public var description: String {
        switch self {
        case .claude: "Anthropic's Claude Code, driven via a one-shot `claude --print` invocation."
        case .codex: "OpenAI Codex, driven via a one-shot `codex exec` invocation."
        }
    }

    /// Where the user can install the binary if it isn't already on disk.
    public var installURL: URL {
        switch self {
        case .claude: URL(string: "https://claude.ai/download")!
        case .codex: URL(string: "https://github.com/openai/codex/releases")!
        }
    }

    /// `ToolSource` we look at to detect the binary on disk.
    public var toolSource: ToolSource {
        switch self {
        case .claude: .claude
        case .codex: .codex
        }
    }
}

// MARK: - Activity feed

/// One step in the agent's chronological activity feed for a turn. Ported verbatim from
/// the frozen `AgentActivity` (`Chops/Services/Agents/AgentTypes.swift`); the Linux
/// transport emits one `.thinking` entry per prompt and resolves it to `.done`/`.failed`.
public struct AgentActivity: Identifiable, Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case thinking
        case toolCall(name: String)
        case toolInputDraft(name: String, charCount: Int)
        case toolResult(name: String)
        case info
    }

    public enum Status: Sendable, Equatable {
        case running
        case done       // tool ran successfully (read-only / non-mutating)
        case applied    // mutating tool (Write/Edit/MultiEdit) successfully changed disk
        case failed
    }

    /// Optional rich payload so a UI can show what each step actually did when expanded.
    public struct Payload: Sendable, Equatable {
        public var filePath: String?
        public var originalText: String?
        public var proposedText: String?
        public var existedBefore: Bool?
        public var rawInput: String?      // pretty-printed JSON of tool input
        public var resultText: String?    // tool_result content (truncated)

        public init(
            filePath: String? = nil,
            originalText: String? = nil,
            proposedText: String? = nil,
            existedBefore: Bool? = nil,
            rawInput: String? = nil,
            resultText: String? = nil
        ) {
            self.filePath = filePath
            self.originalText = originalText
            self.proposedText = proposedText
            self.existedBefore = existedBefore
            self.rawInput = rawInput
            self.resultText = resultText
        }
    }

    public let id: UUID
    public var kind: Kind
    public var title: String
    public var detail: String?
    public var startedAt: Date
    public var status: Status
    public var payload: Payload

    public init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        detail: String? = nil,
        startedAt: Date = Date(),
        status: Status = .running,
        payload: Payload = Payload()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.startedAt = startedAt
        self.status = status
        self.payload = payload
    }
}

// MARK: - Errors

/// Ported from the frozen `AgentError`. The permission-specific cases and types are not
/// ported: the one-shot transports never ask for tool permission (they disable tools and
/// let Chops own every disk write), so those values had no Linux caller.
public enum AgentError: Error, LocalizedError, Equatable {
    case noSession
    case binaryNotInstalled(toolName: String, installURL: URL)
    case agentTooOld(toolName: String, found: String, minimum: String)
    case launchFailed(String)
    case processExitedDuringConnect(String)
    case connectTimedOut(stage: String)

    public var errorDescription: String? {
        switch self {
        case .noSession:
            "No active agent session."
        case .binaryNotInstalled(let name, _):
            "\(name) isn't installed."
        case .agentTooOld(let name, let found, let minimum):
            "\(name) v\(found) is too old. Update to v\(minimum) or newer."
        case .launchFailed(let detail):
            "Failed to launch agent: \(detail)"
        case .processExitedDuringConnect(let detail):
            "Agent exited before initializing.\n\n\(detail)"
        case .connectTimedOut(let stage):
            "Connection timed out (\(stage))."
        }
    }
}

// MARK: - Helpers

/// Ported from the frozen `AgentDataDecoding`.
public enum AgentDataDecoding {
    /// Best-effort decode of bytes to a Swift String. Tries UTF-8 then UTF-16.
    public static func text(from data: Data?) -> String? {
        guard let data else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
    }
}
