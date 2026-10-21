// Settings persistence for chopsd (plan T11).
//
// macOS keeps `ChopsSettings` in UserDefaults. The Linux sidecar owns a real file so
// the Tauri front-end and the daemon can share it:
//
//     ${XDG_CONFIG_HOME:-$HOME/.config}/chops/settings.json
//
// There is no legacy migration and no silent fallback: a corrupt settings file fails
// startup loudly (repo rule: root-cause fixes only).

import Foundation

/// User-editable preferences persisted between chopsd runs.
struct ChopsdSettings: Codable, Sendable, Equatable {
    /// Source-of-truth root (macOS `ChopsSettings.sotDir` parity).
    var sotDir: String
    /// Extra directories scanned for project-level and custom skills.
    var scanRoots: [String]
    /// macOS parity flag; the Linux scanner has no plugin tree yet, so this is stored
    /// for the settings UI and future parity work.
    var includePluginSkills: Bool
    /// `system`, `light`, or `dark` (Tauri follows `prefers-color-scheme` by default).
    var theme: String

    static func defaults(homeDirectory: URL) -> ChopsdSettings {
        ChopsdSettings(
            sotDir: homeDirectory.appendingPathComponent(".chops", isDirectory: true).path,
            scanRoots: [],
            includePluginSkills: false,
            theme: "system"
        )
    }
}

/// Resolves the XDG paths chopsd owns.
enum ChopsdPaths {
    static func homeDirectory(environment: [String: String]) -> URL {
        if let home = environment["HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home, isDirectory: true).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    }

    /// `$XDG_CONFIG_HOME`, or `$HOME/.config` when unset/empty.
    static func configDirectory(environment: [String: String]) -> URL {
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg, isDirectory: true).standardizedFileURL
        }
        return homeDirectory(environment: environment)
            .appendingPathComponent(".config", isDirectory: true)
            .standardizedFileURL
    }

    /// `${XDG_CONFIG_HOME:-$HOME/.config}/chops/settings.json`.
    static func settingsURL(environment: [String: String]) -> URL {
        configDirectory(environment: environment)
            .appendingPathComponent("chops", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
    }
}

/// Thread-safe settings file access.
///
/// The file is written atomically with sorted keys so diffs are stable, and reads
/// always return the defaults when the file does not exist yet (first launch).
final class SettingsStore: @unchecked Sendable {
    let fileURL: URL
    private let defaults: ChopsdSettings
    private let lock = NSLock()

    init(fileURL: URL, homeDirectory: URL) {
        self.fileURL = fileURL
        self.defaults = ChopsdSettings.defaults(homeDirectory: homeDirectory)
    }

    func load() throws -> ChopsdSettings {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return defaults
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(ChopsdSettings.self, from: data)
    }

    @discardableResult
    func save(_ settings: ChopsdSettings) throws -> ChopsdSettings {
        lock.lock()
        defer { lock.unlock() }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: .atomic)
        return settings
    }

    /// Normalizes a user-supplied settings value: absolute, standardized scan roots,
    /// a known theme, and no empty roots.
    static func normalized(_ settings: ChopsdSettings, homeDirectory: URL) throws -> ChopsdSettings {
        var normalized = settings
        if normalized.sotDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized.sotDir = ChopsdSettings.defaults(homeDirectory: homeDirectory).sotDir
        }
        normalized.scanRoots = Array(
            Set(
                normalized.scanRoots
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .map { path -> String in
                        let expanded = (path as NSString).expandingTildeInPath
                        return URL(fileURLWithPath: expanded, isDirectory: true)
                            .standardizedFileURL.path
                    }
            )
        ).sorted()
        if !["system", "light", "dark"].contains(normalized.theme) {
            throw SettingsError.invalidTheme(normalized.theme)
        }
        return normalized
    }
}

enum SettingsError: Error, LocalizedError {
    case invalidTheme(String)

    var errorDescription: String? {
        switch self {
        case .invalidTheme(let theme):
            return "Invalid theme '\(theme)'; expected system, light, or dark."
        }
    }
}
