// AppLogger — Linux port of `Chops/Services/AppLogger.swift` (plan T10).
//
// macOS exposes four `os.Logger` categories (`scanning`, `fileIO`, `ui`, `settings`)
// under the app's bundle identifier. The port keeps the exact same call sites —
// `AppLogger.fileIO.warning("...")` — but each category is a swift-log `Logger`
// backed by `JSONLineLogHandler`, so Linux emits structured JSON lines on stdout
// instead of unified-log records.

import Foundation
import Logging

public enum AppLogger {
    /// Mirrors the macOS subsystem. Linux has no bundle identifier, so the value is
    /// fixed unless `CHOPS_LOG_SUBSYSTEM` overrides it (QA and chopsd deployments).
    public static let subsystem: String = {
        if let override = ProcessInfo.processInfo.environment["CHOPS_LOG_SUBSYSTEM"],
           !override.isEmpty {
            return override
        }
        return "md.chops"
    }()

    /// Set during startup to raise/lower the whole process. Default matches
    /// `os.Logger`'s default level (info).
    public static let defaultLevel: Logger.Level = {
        guard let raw = ProcessInfo.processInfo.environment["CHOPS_LOG_LEVEL"]?.lowercased(),
              let level = Logger.Level(rawValue: raw) else {
            return .info
        }
        return level
    }()

    public static let scanning = logger(category: "scanning")
    public static let fileIO = logger(category: "fileIO")
    public static let ui = logger(category: "ui")
    public static let settings = logger(category: "settings")

    /// Builds a category logger. `output` is injectable so tests capture the JSON
    /// lines without touching stdout or process-global swift-log state.
    public static func logger(
        category: String,
        output: LogOutput = .shared,
        level: Logger.Level? = nil
    ) -> Logger {
        let subsystem = self.subsystem
        let resolvedLevel = level ?? defaultLevel
        return Logger(label: "\(subsystem).\(category)") { label in
            JSONLineLogHandler(
                label: label,
                output: output,
                level: resolvedLevel,
                metadata: [
                    "subsystem": "\(subsystem)",
                    "category": "\(category)",
                ]
            )
        }
    }
}
