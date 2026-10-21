import Foundation

/// Everything the transports need from the host: where `$HOME` is for fallback binary
/// discovery, which environment to hand the child process, optional explicit binary
/// overrides, and a log sink.
///
/// Tests inject a scratch `homeDirectory` plus an environment whose `PATH` begins at
/// `linux/fixtures` so the committed stub binaries are the only ones reachable. This
/// type never resolves the real user home unless a caller asks for `.system()`.
public struct AgentEnvironment: Sendable {
    /// Home directory used for the Linux CLI search table (`ToolSource.cliSearchPaths`).
    public var homeDirectory: URL

    /// Full environment for the spawned child. The transports pass this through
    /// verbatim (Claude adds/removes its own SDK markers).
    public var environment: [String: String]

    /// Explicit binary paths that win over PATH and the CLI search table.
    public var binaryOverrides: [AgentID: URL]

    /// Diagnostic sink. `AgentLog.disabled` by default; T10 installs the real sink.
    public var log: AgentLogSink

    public init(
        homeDirectory: URL,
        environment: [String: String],
        binaryOverrides: [AgentID: URL] = [:],
        log: @escaping AgentLogSink = AgentLog.disabled
    ) {
        self.homeDirectory = homeDirectory
        self.environment = environment
        self.binaryOverrides = binaryOverrides
        self.log = log
    }

    /// Host defaults. chopsd constructs this from the real process environment; tests
    /// must construct the initializer above so the real `$HOME` is never touched.
    public static func system(log: @escaping AgentLogSink = AgentLog.disabled) -> AgentEnvironment {
        AgentEnvironment(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            environment: ProcessInfo.processInfo.environment,
            log: log
        )
    }

    /// Resolve the CLI binary for an agent.
    ///
    /// Order:
    /// 1. explicit override (tests / settings)
    /// 2. `PATH` lookup, left-to-right — this is what lets `chopsd` inherit the user's
    ///    shell path and what makes stub PATH injection authoritative in tests
    /// 3. the frozen `ToolSource` search table adapted for Linux in T07
    ///    (`~/.local/bin`, `/usr/local/bin`, `/usr/bin`, nvm, `~/.codex/bin/codex`)
    public func binaryURL(for agent: AgentID) -> URL? {
        if let override = binaryOverrides[agent] {
            return override
        }
        if let onPath = Self.pathBinary(agent.rawValue, environment: environment) {
            return onPath
        }
        return agent.toolSource.cliBinaryURL(homeDirectory: homeDirectory)
    }

    /// POSIX `PATH` lookup. Empty components (which would mean "current directory") are
    /// skipped rather than treated as search roots.
    static func pathBinary(_ name: String, environment: [String: String]) -> URL? {
        guard let path = environment["PATH"] else { return nil }
        for directory in path.split(separator: ":", omittingEmptySubsequences: true) {
            let candidate = URL(fileURLWithPath: String(directory), isDirectory: true)
                .appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
