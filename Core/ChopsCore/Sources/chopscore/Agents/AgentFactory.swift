import Foundation

/// Returns the right transport for a given agent ID.
///
/// Port of the frozen macOS `AgentFactory` (`Chops/Services/Agents/AgentFactory.swift`).
/// The macOS factory builds a default-configured instance; the Linux factory requires an
/// explicit `AgentEnvironment` so no caller can accidentally resolve the real `$HOME` or
/// the host's `claude`/`codex` binaries (tests inject the fixture environment instead).
public enum AgentFactory {
    public static func make(for agentId: AgentID, configuration: AgentEnvironment) -> any AgentSession {
        switch agentId {
        case .claude: return ClaudeCLIAgent(configuration: configuration)
        case .codex:  return CodexCLIAgent(configuration: configuration)
        }
    }
}
