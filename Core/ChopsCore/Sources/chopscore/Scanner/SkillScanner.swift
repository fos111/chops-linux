import Foundation

/// Port of the frozen macOS `ItemKind` (`Chops/Models/Skill.swift`).
public enum ItemKind: String, Codable, CaseIterable, Sendable {
    case skill
    case agent
    case rule

    public var displayName: String {
        switch self {
        case .skill: "Skills"
        case .agent: "Agents"
        case .rule: "Rules"
        }
    }

    public var singularName: String {
        switch self {
        case .skill: "Skill"
        case .agent: "Agent"
        case .rule: "Rule"
        }
    }
}

/// Data collected for one on-disk installation of a skill, before resolved-path
/// grouping. Mirrors the frozen `ScannedSkillData` (`Chops/Services/SkillScanner.swift`).
public struct ScannedSkillData: Sendable {
    public let fileURL: URL
    public let resolvedPath: String
    public let toolSource: ToolSource
    public let isDirectory: Bool
    public let isGlobal: Bool
    public let name: String
    public let skillDescription: String
    public let content: String
    public let frontmatter: [String: String]
    public let modDate: Date
    public let fileSize: Int
    public let kind: ItemKind
}

/// One logical skill identity after deduplication by resolved symlink path.
///
/// `installedPaths` holds every filesystem location that points at the same physical
/// file (for `dup-a-md`: both the symlink and its target). `toolSources` records every
/// tool directory that contributed an installation, so a file reachable from Claude
/// and Codex is attributed to both tools on a single row.
public struct ScannedSkill: Sendable {
    public let filePath: String
    public let resolvedPath: String
    public let toolSource: ToolSource
    public let toolSources: [ToolSource]
    public let installedPaths: [String]
    public let isDirectory: Bool
    public let isGlobal: Bool
    public let name: String
    public let skillDescription: String
    public let content: String
    public let frontmatter: [String: String]
    public let modifiedDate: Date
    public let fileSize: Int
    public let kind: ItemKind
}

/// Result of one scan: the deduplicated skill rows plus the loose files that were
/// enumerated but intentionally skipped because parsing yielded no name.
///
/// `z-bad.md` (frontmatter `name:` with no value) is the canonical tolerated case: it
/// never crashes the scan and never becomes a row, but it is reported here so callers
/// can see it was seen and tolerated.
public struct ScanReport: Sendable {
    public let skills: [ScannedSkill]
    public let unparsablePaths: [String]
}

/// Portable port of the frozen macOS `SkillScanner` collection logic
/// (`Chops/Services/SkillScanner.swift`) with an injectable home directory.
///
/// Linux adaptations required by the fixture contract:
/// - Path tables and installation detection come from `ToolSource` (Linux variants).
/// - Nested directories under a tool's skill/rule directory are traversed, so
///   `.claude/skills/sub/x-eight.md` is discovered.
/// - A loose file is only kept when its parsed frontmatter yields a name. The malformed
///   `z-bad.md` is tolerated and reported in `ScanReport.unparsablePaths` instead of
///   becoming a filename-derived row.
/// - Symlinks are filtered by their resolved extension, so `dup-a-md -> a-one.md` is
///   scanned, then folded into the `a-one.md` identity via `resolvingSymlinksInPath()`.
///
/// Persistence, remote-server scanning and the macOS-specific Claude Desktop cowork
/// plugin tree are intentionally out of this task (store application and remote sync
/// belong to chopsd).
public struct SkillScanner: Sendable {
    public let homeDirectory: URL
    public let configHomeDirectory: URL

    /// Filenames that are tool config/meta files, not skills.
    private static let ignoredFileNames: Set<String> = [
        "README.md",
        "README",
        "CLAUDE.md",
        "AGENTS.md",
        "AGENTS.override.md",
        "global_rules.md",
        "SYSTEM.md",
        "APPEND_SYSTEM.md",
        "LICENSE.md",
        "LICENSE",
        "CHANGELOG.md",
    ]

    /// Project-level paths to probe inside each project directory (mac parity).
    private static let projectProbes: [(subpath: String, tool: ToolSource, kind: ItemKind)] = [
        (".claude/skills", .claude, .skill),
        (".claude/agents", .claude, .agent),
        (".cursor/skills", .cursor, .skill),
        (".cursor/rules", .cursor, .rule),
        (".cursor/agents", .cursor, .agent),
        (".codex/skills", .codex, .skill),
        (".codex/agents", .codex, .agent),
        (".windsurf/rules", .windsurf, .rule),
        (".github", .copilot, .skill),
        (".github/agents", .copilot, .agent),
        (".config/amp/skills", .amp, .skill),
        (".opencode/skills", .opencode, .skill),
        (".hermes/skills", .hermes, .skill),
    ]

    /// - Parameters:
    ///   - homeDirectory: the user home to scan. Defaults to the real home for
    ///     production; tests must pass a temporary copy of `linux/fixtures/home`.
    ///   - configHomeDirectory: overrides `XDG_CONFIG_HOME`. When nil, the environment
    ///     is consulted, then `~/.config` is used (same rule as the frozen source).
    ///   - environment: injectable environment used only for `XDG_CONFIG_HOME`.
    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        configHomeDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        let standardizedHome = homeDirectory.standardizedFileURL
        self.homeDirectory = standardizedHome
        if let configHomeDirectory {
            self.configHomeDirectory = configHomeDirectory.standardizedFileURL
        } else if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            self.configHomeDirectory = URL(fileURLWithPath: xdg, isDirectory: true).standardizedFileURL
        } else {
            self.configHomeDirectory = standardizedHome.appendingPathComponent(".config", isDirectory: true)
        }
    }

    /// Collect and deduplicate every skill reachable from the tool path tables.
    ///
    /// - Parameter customPaths: extra directories configured by the user
    ///   (settings "scan roots"). Claude plugin trees are not part of the Linux scan.
    public func scanAll(customPaths: [String] = []) -> ScanReport {
        var installations: [ScannedSkillData] = []
        var unparsablePaths: [String] = []

        for tool in ToolSource.allCases where tool != .custom {
            guard tool.isInstalled(
                homeDirectory: homeDirectory,
                configHomeDirectory: configHomeDirectory
            ) else { continue }

            for path in tool.globalPaths(
                homeDirectory: homeDirectory,
                configHomeDirectory: configHomeDirectory
            ) {
                collectFromDirectory(
                    URL(fileURLWithPath: path, isDirectory: true),
                    toolSource: tool,
                    isGlobal: true,
                    kind: .skill,
                    ancestors: [],
                    into: &installations,
                    unparsable: &unparsablePaths
                )
            }
            for path in tool.globalAgentPaths(homeDirectory: homeDirectory) {
                collectFromDirectory(
                    URL(fileURLWithPath: path, isDirectory: true),
                    toolSource: tool,
                    isGlobal: true,
                    kind: .agent,
                    ancestors: [],
                    into: &installations,
                    unparsable: &unparsablePaths
                )
            }
            for path in tool.globalRulePaths(homeDirectory: homeDirectory) {
                collectFromDirectory(
                    URL(fileURLWithPath: path, isDirectory: true),
                    toolSource: tool,
                    isGlobal: true,
                    kind: .rule,
                    ancestors: [],
                    into: &installations,
                    unparsable: &unparsablePaths
                )
            }
        }

        for path in customPaths {
            collectFromCustomDirectory(
                URL(fileURLWithPath: path, isDirectory: true),
                into: &installations,
                unparsable: &unparsablePaths
            )
        }

        return ScanReport(
            skills: Self.groupByResolvedPath(installations),
            unparsablePaths: Array(Set(unparsablePaths)).sorted()
        )
    }

    // MARK: - Resolved-path grouping

    /// Fold installations that share a resolved symlink path into one `ScannedSkill`.
    ///
    /// Deterministic: the primary installation is the lexicographically first file
    /// path, installed paths are unique and sorted, and tool sources follow
    /// `ToolSource.allCases` order exactly like the frozen `applyResults`.
    public static func groupByResolvedPath(_ installations: [ScannedSkillData]) -> [ScannedSkill] {
        let grouped = Dictionary(grouping: installations, by: \.resolvedPath)

        return grouped.values.compactMap { group -> ScannedSkill? in
            guard let primary = group.sorted(by: { $0.fileURL.path < $1.fileURL.path }).first else {
                return nil
            }
            let installedPaths = Array(Set(group.map(\.fileURL.path))).sorted()
            let toolSources = ToolSource.allCases.filter { tool in
                group.contains { $0.toolSource == tool }
            }

            return ScannedSkill(
                filePath: primary.fileURL.path,
                resolvedPath: primary.resolvedPath,
                toolSource: primary.toolSource,
                toolSources: toolSources,
                installedPaths: installedPaths,
                isDirectory: primary.isDirectory,
                isGlobal: primary.isGlobal,
                name: primary.name,
                skillDescription: primary.skillDescription,
                content: primary.content,
                frontmatter: primary.frontmatter,
                modifiedDate: primary.modDate,
                fileSize: primary.fileSize,
                kind: primary.kind
            )
        }
        .sorted { $0.resolvedPath < $1.resolvedPath }
    }

    // MARK: - Global tool directories

    private func collectFromDirectory(
        _ directory: URL,
        toolSource: ToolSource,
        isGlobal: Bool,
        kind: ItemKind,
        ancestors: Set<String>,
        into results: inout [ScannedSkillData],
        unparsable: inout [String]
    ) {
        let fm = FileManager.default

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
            return
        }

        // Enumerate through the resolved directory so symlinked directories are traversed.
        let resolvedDirectory = directory.resolvingSymlinksInPath()
        guard !ancestors.contains(resolvedDirectory.path) else { return }
        let nextAncestors = ancestors.union([resolvedDirectory.path])

        guard let contents = try? fm.contentsOfDirectory(
            at: resolvedDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let originalBase = directory.path
        let resolvedBase = resolvedDirectory.path

        for rawItem in contents.sorted(by: { $0.path < $1.path }) {
            guard !Task.isCancelled else { return }

            // Remap to the canonical path for storage; use rawItem for filesystem operations.
            let item = Self.remap(rawItem, originalBase: originalBase, resolvedBase: resolvedBase)

            var itemIsDir: ObjCBool = false
            _ = fm.fileExists(atPath: rawItem.path, isDirectory: &itemIsDir)

            if itemIsDir.boolValue {
                let rawSkillFile = rawItem.appendingPathComponent("SKILL.md")
                let rawAgentsFile = rawItem.appendingPathComponent("AGENTS.md")
                let skillFile = item.appendingPathComponent("SKILL.md")
                let agentsFile = item.appendingPathComponent("AGENTS.md")

                if fm.fileExists(atPath: rawSkillFile.path) {
                    if let data = collectSkillData(
                        at: skillFile,
                        toolSource: toolSource,
                        isDirectory: true,
                        isGlobal: isGlobal,
                        kind: kind,
                        unparsable: &unparsable
                    ) {
                        results.append(data)
                    }
                } else if fm.fileExists(atPath: rawAgentsFile.path) {
                    if let data = collectSkillData(
                        at: agentsFile,
                        toolSource: toolSource,
                        isDirectory: true,
                        isGlobal: isGlobal,
                        kind: kind,
                        unparsable: &unparsable
                    ) {
                        results.append(data)
                    }
                } else if kind == .agent, let agentFile = preferredAgentFile(in: rawItem) {
                    let remappedAgentFile = item.appendingPathComponent(agentFile.lastPathComponent)
                    if let data = collectSkillData(
                        at: remappedAgentFile,
                        toolSource: toolSource,
                        isDirectory: true,
                        isGlobal: isGlobal,
                        kind: kind,
                        unparsable: &unparsable
                    ) {
                        results.append(data)
                    }
                } else {
                    // Linux adaptation: keep descending so nested skill files
                    // (`.claude/skills/sub/x-eight.md`) are discovered. The macOS source
                    // only did this for Hermes; the fixture contract requires nesting
                    // under any skill directory.
                    collectFromDirectory(
                        item,
                        toolSource: toolSource,
                        isGlobal: isGlobal,
                        kind: kind,
                        ancestors: nextAncestors,
                        into: &results,
                        unparsable: &unparsable
                    )
                }
            } else {
                // Symlinks are classified by the extension of their resolved target:
                // `dup-a-md -> a-one.md` is a markdown skill even though the link name
                // itself has no extension.
                let pathExtension = effectivePathExtension(for: rawItem, displayItem: item)
                guard ["md", "mdc", "toml"].contains(pathExtension) else { continue }
                guard !Self.shouldIgnoreLooseMarkdownFile(named: item.lastPathComponent) else { continue }

                if let data = collectSkillData(
                    at: item,
                    toolSource: toolSource,
                    isDirectory: false,
                    isGlobal: isGlobal,
                    kind: kind,
                    unparsable: &unparsable
                ) {
                    results.append(data)
                }
            }
        }
    }

    // MARK: - Custom scan roots (mac parity)

    private func collectFromCustomDirectory(
        _ directory: URL,
        into results: inout [ScannedSkillData],
        unparsable: inout [String]
    ) {
        let fm = FileManager.default

        collectDirectSkillsFromCustomDirectory(directory, into: &results, unparsable: &unparsable)

        guard let projects = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for project in projects.sorted(by: { $0.path < $1.path }) {
            guard !Task.isCancelled else { return }

            var isDir: ObjCBool = false
            _ = fm.fileExists(atPath: project.path, isDirectory: &isDir)
            guard isDir.boolValue else { continue }

            for probe in Self.projectProbes {
                let probePath = project.appendingPathComponent(probe.subpath, isDirectory: true)
                guard fm.fileExists(atPath: probePath.path) else { continue }

                if probe.tool == .copilot && probe.kind == .skill {
                    let file = probePath.appendingPathComponent("copilot-instructions.md")
                    if fm.fileExists(atPath: file.path) {
                        if let data = collectSkillData(
                            at: file,
                            toolSource: .copilot,
                            isDirectory: false,
                            isGlobal: false,
                            kind: probe.kind,
                            unparsable: &unparsable
                        ) {
                            results.append(data)
                        }
                    }
                } else {
                    collectFromDirectory(
                        probePath,
                        toolSource: probe.tool,
                        isGlobal: false,
                        kind: probe.kind,
                        ancestors: [],
                        into: &results,
                        unparsable: &unparsable
                    )
                }
            }
        }
    }

    private func collectDirectSkillsFromCustomDirectory(
        _ directory: URL,
        into results: inout [ScannedSkillData],
        unparsable: inout [String]
    ) {
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in contents.sorted(by: { $0.path < $1.path }) {
            guard !Task.isCancelled else { return }

            var isDirectory: ObjCBool = false
            _ = fm.fileExists(atPath: item.path, isDirectory: &isDirectory)

            if isDirectory.boolValue {
                let skillFile = item.appendingPathComponent("SKILL.md")
                guard fm.fileExists(atPath: skillFile.path) else { continue }
                if let data = collectSkillData(
                    at: skillFile,
                    toolSource: .custom,
                    isDirectory: true,
                    isGlobal: false,
                    kind: .skill,
                    unparsable: &unparsable
                ) {
                    results.append(data)
                }
            } else {
                let pathExtension = effectivePathExtension(for: item, displayItem: item)
                guard ["md", "mdc", "toml"].contains(pathExtension) else { continue }
                guard !Self.shouldIgnoreLooseMarkdownFile(named: item.lastPathComponent) else { continue }
                if let data = collectSkillData(
                    at: item,
                    toolSource: .custom,
                    isDirectory: false,
                    isGlobal: false,
                    kind: .skill,
                    unparsable: &unparsable
                ) {
                    results.append(data)
                }
            }
        }
    }

    // MARK: - Single-file collection

    private func collectSkillData(
        at fileURL: URL,
        toolSource: ToolSource,
        isDirectory: Bool,
        isGlobal: Bool,
        kind: ItemKind,
        unparsable: inout [String]
    ) -> ScannedSkillData? {
        let fm = FileManager.default

        // Resolve symlinks for the actual read — fileURL may be a remapped canonical
        // path that does not physically exist when a parent directory is a symlink.
        let physicalURL = fileURL.resolvingSymlinksInPath()
        guard let parsed = SkillParser.parse(fileURL: physicalURL, toolSource: toolSource) else {
            unparsable.append(physicalURL.path)
            return nil
        }

        let name: String
        if !parsed.name.isEmpty {
            name = parsed.name
        } else if isDirectory {
            // Directory skills fall back to the containing folder, mac parity.
            name = fileURL.deletingLastPathComponent().lastPathComponent
        } else {
            // Loose file without a parseable name (`z-bad.md`) is tolerated, never a row.
            unparsable.append(fileURL.path)
            return nil
        }

        let attrs = try? fm.attributesOfItem(atPath: physicalURL.path)
        let modDate = (attrs?[.modificationDate] as? Date) ?? .now
        let fileSize = (attrs?[.size] as? Int) ?? 0

        return ScannedSkillData(
            fileURL: fileURL,
            resolvedPath: physicalURL.path,
            toolSource: toolSource,
            isDirectory: isDirectory,
            isGlobal: isGlobal,
            name: name,
            skillDescription: parsed.description,
            content: parsed.content,
            frontmatter: parsed.frontmatter,
            modDate: modDate,
            fileSize: fileSize,
            kind: kind
        )
    }

    // MARK: - Helpers

    private static func remap(_ rawItem: URL, originalBase: String, resolvedBase: String) -> URL {
        if originalBase != resolvedBase, rawItem.path.hasPrefix(resolvedBase + "/") {
            let suffix = String(rawItem.path.dropFirst(resolvedBase.count))
            return URL(fileURLWithPath: originalBase + suffix)
        }
        return rawItem
    }

    private func effectivePathExtension(for rawItem: URL, displayItem: URL) -> String {
        let isSymlink = (try? rawItem.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
        guard isSymlink else { return displayItem.pathExtension }
        return rawItem.resolvingSymlinksInPath().pathExtension
    }

    private static func shouldIgnoreLooseMarkdownFile(named fileName: String) -> Bool {
        ignoredFileNames.contains(fileName)
    }

    private func preferredAgentFile(in directory: URL) -> URL? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let candidates = contents
            .sorted(by: { $0.path < $1.path })
            .filter { item in
                var isDir: ObjCBool = false
                _ = fm.fileExists(atPath: item.path, isDirectory: &isDir)
                guard !isDir.boolValue else { return false }
                guard ["md", "mdc", "toml"].contains(item.pathExtension) else { return false }
                return !Self.shouldIgnoreLooseMarkdownFile(named: item.lastPathComponent)
            }

        let directoryName = directory.lastPathComponent.lowercased()
        if let matchingFile = candidates.first(where: {
            $0.deletingPathExtension().lastPathComponent.lowercased() == directoryName
        }) {
            return matchingFile
        }

        if candidates.count == 1 {
            return candidates[0]
        }

        return nil
    }
}
