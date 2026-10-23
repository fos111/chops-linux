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

// MARK: - Linux path tables (plan T07)

extension ToolSource {
    /// npm-global OpenClaw skill roots on Linux.
    ///
    /// Replaces the frozen macOS Homebrew (ARM) probe at `/opt/homebrew/lib/...`.
    /// `/usr/local/lib/node_modules` is the npm prefix for a system-wide install;
    /// `/usr/lib/node_modules` is where Debian packages (and a root `npm -g`) land.
    public static let npmGlobalSkillRoots: [String] = [
        "/usr/local/lib/node_modules/openclaw/skills",
        "/usr/lib/node_modules/openclaw/skills",
    ]

    /// Directories probed when resolving a CLI binary, in order.
    ///
    /// Frozen macOS order was `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`.
    /// On Linux `/opt/homebrew/bin` has no meaning; the distro package location
    /// `/usr/bin` is added so Debian-installed `claude`/`codex` are found.
    public static func cliSearchPaths(homeDirectory: URL) -> [String] {
        [
            homeDirectory.appendingPathComponent(".local/bin", isDirectory: true).path,
            "/usr/local/bin",
            "/usr/bin",
        ]
    }

    /// Global skill directories to scan for this tool, for an explicit home.
    ///
    /// Port of the frozen macOS `globalPaths` with Linux remaps:
    /// - XDG config for Amp/OpenCode (already present upstream)
    /// - OpenClaw npm-global roots → `npmGlobalSkillRoots`
    /// - Hermes/OpenClaw keep their existence-gated probes (no empty path entries).
    public func globalPaths(homeDirectory: URL, configHomeDirectory: URL) -> [String] {
        let fm = FileManager.default
        func home(_ relative: String) -> String {
            homeDirectory.appendingPathComponent(relative, isDirectory: true).path
        }

        switch self {
        case .augment:
            return [home(".augment/skills")]
        case .claude:
            return [home(".claude/skills")]
        case .cursor:
            return [home(".cursor/skills")]
        case .windsurf:
            return []
        case .codex:
            return [home(".codex/skills")]
        case .copilot:
            return [home(".copilot/skills")]
        case .aider:
            return []
        case .amp:
            return [configHomeDirectory.appendingPathComponent("amp/skills", isDirectory: true).path]
        case .hermes:
            let skillsRoot = home(".hermes/skills")
            return fm.fileExists(atPath: skillsRoot) ? [skillsRoot] : []
        case .openclaw:
            var paths: [String] = []
            // Main skills directory.
            let skillsRoot = home(".openclaw/skills")
            if fm.fileExists(atPath: skillsRoot) {
                paths.append(skillsRoot)
            }
            // Workspace skills (search all workspace dirs), mac parity.
            let openclawDir = homeDirectory.appendingPathComponent(".openclaw", isDirectory: true)
            if let workspaces = try? fm.contentsOfDirectory(
                at: openclawDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for workspace in workspaces.sorted(by: { $0.path < $1.path }) {
                    let skillsPath = workspace.appendingPathComponent("skills", isDirectory: true)
                    if fm.fileExists(atPath: skillsPath.path) {
                        paths.append(skillsPath.path)
                    }
                }
            }
            // npm-global installs: `/usr/local/lib/...` (npm prefix) + `/usr/lib/...` (distro).
            for root in Self.npmGlobalSkillRoots where fm.fileExists(atPath: root) {
                paths.append(root)
            }
            return paths
        case .opencode:
            return [configHomeDirectory.appendingPathComponent("opencode/skills", isDirectory: true).path]
        case .pi:
            return [home(".pi/agent/skills")]
        case .agents:
            return [home(".agents/skills")]
        case .antigravity:
            return [home(".gemini/antigravity/skills")]
        case .claudeDesktop:
            return []
        case .custom:
            return []
        }
    }

    /// Global agent directories (port of `globalAgentPaths`; identical on Linux).
    public func globalAgentPaths(homeDirectory: URL) -> [String] {
        let home = homeDirectory.path
        switch self {
        case .claude:
            return ["\(home)/.claude/agents"]
        case .cursor:
            return ["\(home)/.cursor/agents"]
        case .codex:
            return ["\(home)/.codex/agents"]
        default:
            return []
        }
    }

    /// Global rule directories (port of `globalRulePaths`; identical on Linux).
    public func globalRulePaths(homeDirectory: URL) -> [String] {
        let home = homeDirectory.path
        switch self {
        case .cursor:
            return ["\(home)/.cursor/rules"]
        case .windsurf:
            return ["\(home)/.codeium/windsurf/memories", "\(home)/.windsurf/rules"]
        default:
            return []
        }
    }

    /// Whether the tool looks installed for an explicit home.
    ///
    /// Port of the frozen `isInstalled` with the macOS app-bundle probes replaced by
    /// CLI/config-file existence:
    /// - Cursor/Windsurf: `argv.json` config (no `/Applications/*.app` on Linux).
    /// - OpenCode/Augment/Antigravity: XDG/CLI config instead of an app bundle.
    /// - Claude Desktop: `$XDG_CONFIG_HOME/Claude/claude_desktop_config.json`.
    /// - Any existing global skill/agent/rule directory implies a real setup, which
    ///   keeps the synthetic fixture home self-contained.
    ///
    /// `cliSearchPaths` is injectable so tests never depend on host binaries.
    public func isInstalled(
        homeDirectory: URL,
        configHomeDirectory: URL,
        cliSearchPaths: [String]? = nil
    ) -> Bool {
        let fm = FileManager.default
        func home(_ relative: String) -> String {
            homeDirectory.appendingPathComponent(relative).path
        }
        func exists(_ path: String) -> Bool { fm.fileExists(atPath: path) }
        func cli(_ name: String) -> Bool {
            Self.cliBinaryURL(
                name,
                homeDirectory: homeDirectory,
                searchPaths: cliSearchPaths
            ) != nil
        }
        func hasGlobalLocation() -> Bool {
            (globalPaths(homeDirectory: homeDirectory, configHomeDirectory: configHomeDirectory)
                + globalAgentPaths(homeDirectory: homeDirectory)
                + globalRulePaths(homeDirectory: homeDirectory))
                .contains(where: exists)
        }

        switch self {
        case .claude:
            return exists(home(".claude/settings.json"))
                || exists(home(".claude/CLAUDE.md"))
                || exists(home(".claude/plugins/installed_plugins.json"))
                || cli("claude")
                || hasGlobalLocation()
        case .cursor:
            return exists(home(".cursor/argv.json"))
                || cli("cursor")
                || hasGlobalLocation()
        case .windsurf:
            return exists(home(".codeium/windsurf/argv.json"))
                || cli("windsurf")
                || hasGlobalLocation()
        case .codex:
            return exists(home(".codex/config.toml"))
                || exists(home(".codex/auth.json"))
                || cli("codex")
                || hasGlobalLocation()
        case .amp:
            return exists(configHomeDirectory.appendingPathComponent("amp/config.json").path)
                || exists(configHomeDirectory.appendingPathComponent("amp/settings.json").path)
                || cli("amp")
                || hasGlobalLocation()
        case .pi:
            return cli("pi") || hasGlobalLocation()
        case .copilot:
            return exists(home(".copilot"))
                || cli("copilot")
                || hasGlobalLocation()
        case .agents:
            return hasGlobalLocation()
        case .antigravity:
            return exists(home(".antigravity"))
                || exists(home(".gemini/antigravity"))
                || cli("antigravity")
                || hasGlobalLocation()
        case .opencode:
            return exists(configHomeDirectory.appendingPathComponent("opencode/opencode.json").path)
                || exists(configHomeDirectory.appendingPathComponent("opencode/opencode.jsonc").path)
                || exists(home(".local/share/opencode"))
                || cli("opencode")
                || hasGlobalLocation()
        case .augment:
            return exists(home(".augment/settings.json"))
                || cli("augment")
                || hasGlobalLocation()
        case .claudeDesktop:
            // No macOS app bundle on Linux: the desktop client's config file is the
            // installation signal (Claude Desktop is config-compatible via XDG).
            return exists(
                configHomeDirectory.appendingPathComponent("Claude/claude_desktop_config.json").path
            )
        case .openclaw:
            return exists(home(".openclaw"))
                || cli("openclaw")
                || Self.npmGlobalSkillRoots.contains(where: exists)
                || hasGlobalLocation()
        case .hermes:
            return exists(home(".hermes"))
                || cli("hermes")
                || hasGlobalLocation()
        case .aider, .custom:
            // Frozen macOS behavior: Aider has no marker file and is always listable;
            // `custom` is an internal bucket rather than an installed tool.
            return true
        }
    }

    /// Resolve an executable name to an absolute URL for an explicit home.
    ///
    /// Probe order: caller-supplied `extraPaths`, then `~/.local/bin`, `/usr/local/bin`,
    /// `/usr/bin` (see `cliSearchPaths`), then nvm node versions newest-first.
    /// `searchPaths` replaces the Linux default directory list (used by tests).
    public static func cliBinaryURL(
        _ name: String,
        homeDirectory: URL,
        extraPaths: [String] = [],
        searchPaths: [String]? = nil
    ) -> URL? {
        let fm = FileManager.default
        var paths = extraPaths
        let directories = searchPaths ?? cliSearchPaths(homeDirectory: homeDirectory)
        paths.append(contentsOf: directories.map { "\($0)/\(name)" })
        for path in paths where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let nvmDir = homeDirectory.appendingPathComponent(".nvm/versions/node").path
        if let nodeDirs = try? fm.contentsOfDirectory(atPath: nvmDir) {
            for nodeDir in nodeDirs.sorted().reversed() {
                let candidate = "\(nvmDir)/\(nodeDir)/bin/\(name)"
                if fm.isExecutableFile(atPath: candidate) {
                    return URL(fileURLWithPath: candidate)
                }
            }
        }
        return nil
    }

    /// Resolved binary URL for the tools driven directly via subprocess.
    /// Currently Claude and Codex (mac parity); used by the T08 transports.
    public func cliBinaryURL(homeDirectory: URL) -> URL? {
        switch self {
        case .claude:
            return Self.cliBinaryURL("claude", homeDirectory: homeDirectory)
        case .codex:
            return Self.cliBinaryURL(
                "codex",
                homeDirectory: homeDirectory,
                extraPaths: [homeDirectory.appendingPathComponent(".codex/bin/codex").path]
            )
        default:
            return nil
        }
    }
}
