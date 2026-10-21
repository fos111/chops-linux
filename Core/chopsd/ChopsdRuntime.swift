// ChopsdRuntime — the sidecar's shared state and filesystem authority (plan T11).
//
// One actor owns the GRDB store, the settings file, the inotify watcher, the agent
// transports, the registry client, and the SSH client. Every route hops onto this
// actor, so rescans and writes are serialized and the REST surface can never race the
// watcher's rescan.
//
// Write policy (fixed contract): chopsd is the only process allowed to touch skill
// files. Every write path is checked against the configured scan roots plus the
// fixture/production home (`isWriteAllowed`) unless it is an explicit remote-server
// write routed through SSH.

import Foundation
import Vapor
import chopscore

actor ChopsdRuntime {
    let homeDirectory: URL
    let configHomeDirectory: URL
    let store: ChopsStore
    let settingsStore: SettingsStore
    let hub: EventHub
    let agentEnvironment: AgentEnvironment
    let registry: SkillRegistry
    let ssh: SSHService
    let environment: [String: String]

    private(set) var settings: ChopsdSettings
    private var watcher: FileWatcherInotify?
    private var rescanTask: Task<Void, Never>?
    private var rescanGeneration: UInt64 = 0

    init(environment: [String: String]) throws {
        let home = ChopsdPaths.homeDirectory(environment: environment)
        let configHome = ChopsdPaths.configDirectory(environment: environment)
        let settingsURL = ChopsdPaths.settingsURL(environment: environment)

        self.environment = environment
        self.homeDirectory = home
        self.configHomeDirectory = configHome
        self.store = try ChopsStore(databaseURL: StoreLocation.databaseURL(environment: environment))
        let settingsStore = SettingsStore(fileURL: settingsURL, homeDirectory: home)
        self.settingsStore = settingsStore
        self.settings = try SettingsStore.normalized(
            try settingsStore.load(),
            homeDirectory: home
        )
        self.hub = EventHub()
        self.agentEnvironment = AgentEnvironment(
            homeDirectory: home,
            environment: environment,
            // T10's bridge: one-shot transport stdout/stderr/exit diagnostics flow
            // through the structured agent logger (debug level, gated by
            // CHOPS_AGENT_DEBUG) instead of being dropped.
            log: AgentLog.structured
        )
        self.registry = SkillRegistry(
            endpoints: Self.registryEndpoints(environment: environment),
            homeDirectory: home
        )
        self.ssh = SSHService(homeDirectory: home, environment: environment)
    }

    // MARK: - Lifecycle

    /// Initial scan + watcher wiring. Runs before the HTTP server starts listening so
    /// the first `/api/skills` request already sees the fixture/library inventory.
    func start() throws {
        try scanNow(reason: "startup", broadcast: false)
        configureWatcher()
    }

    func stop() {
        rescanTask?.cancel()
        rescanTask = nil
        watcher?.stopAll()
        watcher = nil
    }

    // MARK: - Scan pipeline

    /// Scans every configured root and reconciles the GRDB rows with the filesystem.
    /// Local rows that disappeared are removed; remote rows are owned by browse/sync.
    @discardableResult
    func scanNow(reason: String, broadcast: Bool) throws -> Int {
        let scanner = SkillScanner(
            homeDirectory: homeDirectory,
            configHomeDirectory: configHomeDirectory
        )
        let report = scanner.scanAll(customPaths: settings.scanRoots)
        try apply(report)

        if broadcast {
            hub.broadcast(.rescan(reason: reason, count: report.skills.count))
        }
        AppLogger.scanning.info(
            "Scan complete",
            metadata: [
                "reason": "\(reason)",
                "skills": "\(report.skills.count)",
                "unparsable": "\(report.unparsablePaths.count)",
            ]
        )
        return report.skills.count
    }

    private func apply(_ report: ScanReport) throws {
        let existing = try store.fetchSkills()
        var localByResolvedPath: [String: Skill] = [:]
        for row in existing where row.remoteServerID == nil {
            localByResolvedPath[row.resolvedPath] = row
        }

        var seen = Set<String>()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        for scanned in report.skills {
            seen.insert(scanned.resolvedPath)
            let frontmatterData = try encoder.encode(scanned.frontmatter)
            let installedPathsData = try encoder.encode(scanned.installedPaths)
            let toolSourcesRAW = scanned.toolSources.map(\.rawValue).sorted().joined(separator: ",")

            if var row = localByResolvedPath[scanned.resolvedPath] {
                row.filePath = scanned.filePath
                row.isDirectory = scanned.isDirectory
                row.name = scanned.name
                row.skillDescription = scanned.skillDescription
                row.content = scanned.content
                row.frontmatterData = frontmatterData
                row.fileModifiedDate = scanned.modifiedDate
                row.fileSize = scanned.fileSize
                row.isGlobal = scanned.isGlobal
                row.toolSourcesRaw = toolSourcesRAW
                row.installedPathsData = installedPathsData
                row.kind = scanned.kind.rawValue
                try store.updateSkill(row)
            } else {
                let row = Skill(
                    filePath: scanned.filePath,
                    resolvedPath: scanned.resolvedPath,
                    isDirectory: scanned.isDirectory,
                    name: scanned.name,
                    skillDescription: scanned.skillDescription,
                    content: scanned.content,
                    frontmatterData: frontmatterData,
                    fileModifiedDate: scanned.modifiedDate,
                    fileSize: scanned.fileSize,
                    isGlobal: scanned.isGlobal,
                    toolSourcesRaw: toolSourcesRAW,
                    installedPathsData: installedPathsData,
                    kind: scanned.kind.rawValue
                )
                try store.insertSkill(row)
            }
        }

        // macOS `removeDeletedSkills` parity for the local library.
        for row in existing
        where row.remoteServerID == nil && !seen.contains(row.resolvedPath) {
            if let id = row.id {
                _ = try store.deleteSkill(id: id)
            }
        }
    }

    // MARK: - Watcher

    private func configureWatcher() {
        watcher?.stopAll()
        let directories = watchDirectories()
        guard !directories.isEmpty else {
            watcher = nil
            AppLogger.fileIO.warning("No scan directories exist to watch")
            return
        }

        let hub = self.hub
        let callback: FileWatcherInotify.EventHandler = { [weak self] event in
            hub.broadcast(.fileChanged(path: event.path, kind: event.kind.rawValue))
            guard let self else { return }
            Task {
                await self.handleWatchEvent(event)
            }
        }

        let newWatcher = FileWatcherInotify(callback: callback)
        newWatcher.watchDirectories(directories)
        watcher = newWatcher
    }

    /// Every existing tool directory plus the configured custom roots, recursively.
    /// inotify watches are per-directory, so nested skill folders need explicit entries.
    private func watchDirectories() -> [String] {
        var roots = Set<String>()

        for tool in ToolSource.allCases where tool != .custom {
            let candidates =
                tool.globalPaths(homeDirectory: homeDirectory, configHomeDirectory: configHomeDirectory)
                + tool.globalAgentPaths(homeDirectory: homeDirectory)
                + tool.globalRulePaths(homeDirectory: homeDirectory)
            for path in candidates {
                roots.formUnion(Self.recursiveDirectories(path))
            }
        }
        for root in settings.scanRoots {
            roots.formUnion(Self.recursiveDirectories(root))
        }
        return roots.sorted()
    }

    static func recursiveDirectories(_ path: String, limit: Int = 500) -> [String] {
        let base = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: base.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return []
        }

        var result = [base.path]
        let baseDepth = base.pathComponents.count
        guard let enumerator = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return result
        }

        for case let url as URL in enumerator {
            guard result.count < limit else { break }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            guard url.pathComponents.count - baseDepth <= 8 else {
                enumerator.skipDescendants()
                continue
            }
            result.append(url.standardizedFileURL.path)
        }
        return result
    }

    func handleWatchEvent(_ event: FileWatchEvent) {
        let rewatch = event.isDirectory
            && (event.kind == .created || event.kind == .renamedTo)
        scheduleRescan(reason: "file-changed", rewatch: rewatch)
    }

    /// Debounced rescan. Rapid watcher bursts (editor temp file + rename + write) fold
    /// into a single scan; stale generations are discarded.
    func scheduleRescan(reason: String, rewatch: Bool = false) {
        rescanGeneration &+= 1
        let generation = rescanGeneration
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.rescanIfCurrent(generation: generation, reason: reason, rewatch: rewatch)
        }
    }

    private func rescanIfCurrent(generation: UInt64, reason: String, rewatch: Bool) {
        guard generation == rescanGeneration else { return }
        do {
            try scanNow(reason: reason, broadcast: true)
        } catch {
            AppLogger.scanning.error(
                "Rescan failed",
                metadata: ["error": "\(error.localizedDescription)"]
            )
        }
        if rewatch {
            configureWatcher()
        }
    }

    // MARK: - Write guard

    /// Roots chopsd may write below: the user home, the XDG config home (where
    /// Amp/OpenCode skills live), and every configured scan root.
    var writeRoots: [String] {
        [homeDirectory.path, configHomeDirectory.path] + settings.scanRoots
    }

    func isWriteAllowed(_ path: String) -> Bool {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL
        let exists = FileManager.default.fileExists(atPath: standardized.path)
        let candidate: String
        if exists {
            candidate = standardized.resolvingSymlinksInPath().path
        } else {
            let parent = standardized.deletingLastPathComponent().resolvingSymlinksInPath()
            candidate = parent.appendingPathComponent(standardized.lastPathComponent).path
        }

        return writeRoots.contains { root in
            let rootPath = URL(fileURLWithPath: root, isDirectory: true)
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .path
            return candidate == rootPath || candidate.hasPrefix(rootPath + "/")
        }
    }

    func writeFile(_ content: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Tools

    func tools() -> [ToolDTO] {
        ToolSource.allCases.filter(\.listable).map { tool in
            ToolDTO(
                id: tool.rawValue,
                displayName: tool.displayName,
                isInstalled: tool.isInstalled(
                    homeDirectory: homeDirectory,
                    configHomeDirectory: configHomeDirectory
                ),
                listable: tool.listable,
                supportsSkills: Self.supportsSkills(tool),
                supportsAgents: !tool.globalAgentPaths(homeDirectory: homeDirectory).isEmpty,
                supportsRules: !tool.globalRulePaths(homeDirectory: homeDirectory).isEmpty,
                globalPaths: tool.globalPaths(
                    homeDirectory: homeDirectory,
                    configHomeDirectory: configHomeDirectory
                ),
                globalAgentPaths: tool.globalAgentPaths(homeDirectory: homeDirectory),
                globalRulePaths: tool.globalRulePaths(homeDirectory: homeDirectory)
            )
        }
    }

    private static func supportsSkills(_ tool: ToolSource) -> Bool {
        switch tool {
        case .aider, .windsurf, .claudeDesktop, .custom:
            return false
        default:
            return true
        }
    }

    // MARK: - Settings

    func settingsResponse() -> SettingsResponse {
        SettingsResponse(
            sotDir: settings.sotDir,
            scanRoots: settings.scanRoots,
            includePluginSkills: settings.includePluginSkills,
            theme: settings.theme,
            homeDirectory: homeDirectory.path,
            settingsPath: settingsStore.fileURL.path,
            databasePath: store.databaseURL.path
        )
    }

    func updateSettings(_ request: SettingsUpdateRequest) throws -> SettingsResponse {
        var candidate = settings
        if let sotDir = request.sotDir {
            candidate.sotDir = sotDir
        }
        if let scanRoots = request.scanRoots {
            candidate.scanRoots = scanRoots
        }
        if let includePluginSkills = request.includePluginSkills {
            candidate.includePluginSkills = includePluginSkills
        }
        if let theme = request.theme {
            candidate.theme = theme
        }

        let normalized = try SettingsStore.normalized(candidate, homeDirectory: homeDirectory)
        try settingsStore.save(normalized)
        settings = normalized

        // New scan roots change both the library and what must be watched.
        try scanNow(reason: "settings", broadcast: true)
        configureWatcher()
        return settingsResponse()
    }

    // MARK: - Registry endpoints

    static func registryEndpoints(environment: [String: String]) -> SkillRegistry.Endpoints {
        var endpoints = SkillRegistry.Endpoints.production

        if let base = environment["CHOPS_REGISTRY_BASE_URL"], !base.isEmpty, let url = URL(string: base) {
            endpoints.skills = url
            endpoints.wwwSkills = url
        }
        if let base = environment["CHOPS_GITHUB_RAW_BASE_URL"], !base.isEmpty, let url = URL(string: base) {
            endpoints.rawGitHub = url
        }
        if let base = environment["CHOPS_GITHUB_API_BASE_URL"], !base.isEmpty, let url = URL(string: base) {
            endpoints.apiGitHub = url
        }
        return endpoints
    }
}
