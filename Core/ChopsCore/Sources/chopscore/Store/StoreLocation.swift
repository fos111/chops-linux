import Foundation

/// Errors raised while resolving the on-disk store location.
public enum StoreLocationError: Error, Equatable, CustomStringConvertible {
    /// Neither `XDG_DATA_HOME` nor `HOME` is set in the supplied environment.
    case homeDirectoryUnavailable

    public var description: String {
        switch self {
        case .homeDirectoryUnavailable:
            return "Cannot locate the Chops data directory: neither XDG_DATA_HOME nor HOME is set."
        }
    }
}

/// Resolves the Linux store paths (plan T05).
///
/// The macOS app keeps its SwiftData store in `~/Library/Application Support/Chops`.
/// On Linux the sidecar uses the XDG base directory:
///
///     ${XDG_DATA_HOME:-$HOME/.local/share}/Chops/chops.db
///
/// There is deliberately no legacy `default.store` migration: the Linux database is
/// created fresh (work plan Must-NOT-Have #4). Callers may inject the environment
/// (`environment:`); tests always pass a synthetic fixture environment so the real
/// user home is never resolved or touched.
public enum StoreLocation {
    /// Directory name under the XDG data home.
    public static let appDirectoryName = "Chops"

    /// SQLite database file name.
    public static let databaseFileName = "chops.db"

    /// `$XDG_DATA_HOME`, or `$HOME/.local/share` when unset/empty.
    public static func dataDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        if let xdgDataHome = environment["XDG_DATA_HOME"], !xdgDataHome.isEmpty {
            return URL(fileURLWithPath: xdgDataHome, isDirectory: true)
        }
        guard let home = environment["HOME"], !home.isEmpty else {
            throw StoreLocationError.homeDirectoryUnavailable
        }
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
    }

    /// `${XDG_DATA_HOME:-$HOME/.local/share}/Chops/chops.db`.
    public static func databaseURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        try dataDirectory(environment: environment)
            .appendingPathComponent(appDirectoryName, isDirectory: true)
            .appendingPathComponent(databaseFileName, isDirectory: false)
    }
}
