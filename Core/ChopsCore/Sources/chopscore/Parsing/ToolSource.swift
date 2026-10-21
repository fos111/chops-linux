import Foundation

/// Portable port of the frozen macOS `ToolSource` enum
/// (`Chops/Models/ToolSource.swift`), limited to what the parsers need.
///
/// The raw values are kept byte-for-byte identical so `skills.tool_sources_raw`
/// (see `Records.swift`, ported from the SwiftData schema) round-trips against the
/// macOS values. Filesystem path tables (`globalPaths`, `globalAgentPaths`,
/// `globalRulePaths`, `isInstalled`) are intentionally **not** ported here: those
/// belong to the Linux scanner/tool-source tables task (plan T07) and are added as
/// an extension in a separate file.
public enum ToolSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case agents
    case augment
    case claude
    case cursor
    case windsurf
    case codex
    case copilot
    case aider
    case amp
    case hermes
    case openclaw
    case opencode
    case pi
    case antigravity
    case claudeDesktop
    case custom

    public var id: String { rawValue }

    /// Port of the macOS `listable` property: whether the tool appears in the sidebar
    /// tools list. Not used by parsing itself, but part of the frozen enum's contract
    /// and needed by the later UI-facing layers.
    public var listable: Bool {
        switch self {
        case .custom, .claudeDesktop, .aider:
            return false
        default:
            return true
        }
    }

    /// Port of the macOS `displayName` property (UI labels, log lines).
    public var displayName: String {
        switch self {
        case .augment: "Auggie"
        case .claude: "Claude Code"
        case .cursor: "Cursor"
        case .windsurf: "Windsurf"
        case .codex: "Codex"
        case .copilot: "Copilot"
        case .aider: "Aider"
        case .amp: "Amp"
        case .hermes: "Hermes"
        case .openclaw: "OpenClaw"
        case .opencode: "OpenCode"
        case .pi: "Pi"
        case .agents: "Global"
        case .antigravity: "Antigravity"
        case .claudeDesktop: "Claude Desktop"
        case .custom: "Custom"
        }
    }

    /// How `SkillParser` interprets a file for this tool.
    ///
    /// Mirrors the frozen `SkillParser.parse(fileURL:toolSource:)` switch:
    /// - Claude family + Cursor: frontmatter only (`.mdc` through `MDCParser`).
    /// - Every other tool: frontmatter first, then an `# Heading` fallback.
    enum ParseStrategy: Sendable {
        case frontmatterOnly
        case frontmatterThenHeading
    }

    var parseStrategy: ParseStrategy {
        switch self {
        case .claude, .claudeDesktop, .cursor:
            return .frontmatterOnly
        case .codex, .amp, .windsurf, .copilot, .aider, .hermes, .openclaw, .opencode, .pi,
             .agents, .augment, .antigravity, .custom:
            return .frontmatterThenHeading
        }
    }

    /// True for the tools whose frozen `SkillParser` branch routes `.mdc` strings to
    /// `MDCParser` (which itself delegates to `FrontmatterParser`).
    var routesMDCThroughMDCParser: Bool {
        switch self {
        case .claude, .claudeDesktop, .cursor:
            return true
        default:
            return false
        }
    }
}
