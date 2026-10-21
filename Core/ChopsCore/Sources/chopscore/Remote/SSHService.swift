import Foundation

/// Port of the frozen macOS `SSHError` (`Chops/Services/SSHService.swift`).
public enum SSHError: Error, LocalizedError, Equatable, Sendable {
    case connectionFailed(String)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): "SSH connection failed: \(msg)"
        case .commandFailed(let msg): "SSH command failed: \(msg)"
        }
    }
}

/// Captured result of one `ssh` invocation.
public struct SSHCommandResult: Sendable, Equatable {
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32

    public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

/// Seam for the actual subprocess launch.
///
/// The production implementation (`SSHProcessRunner`) shells out to the resolved
/// `ssh` binary. Tests inject a recording runner so every command/quoting rule is
/// exercised without a live server.
public protocol SSHRunning: Sendable {
    func run(
        executablePath: String,
        arguments: [String],
        standardInput: String?
    ) async throws -> SSHCommandResult
}

/// Linux implementation of the frozen `run(args:stdin:)` helper.
///
/// Differences from macOS are confined to stream plumbing: child stdout/stderr are
/// redirected to temporary files and read after exit (deadlock-free for large
/// outputs), and stdin is fed from a temporary file instead of a pipe. The observable
/// contract — executable, argv, stdin bytes, exit status, captured text — is identical.
public struct SSHProcessRunner: SSHRunning {
    public init() {}

    public func run(
        executablePath: String,
        arguments: [String],
        standardInput: String?
    ) async throws -> SSHCommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try runBlocking(
                        executablePath: executablePath,
                        arguments: arguments,
                        standardInput: standardInput
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runBlocking(
        executablePath: String,
        arguments: [String],
        standardInput: String?
    ) throws -> SSHCommandResult {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("chops-ssh-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }

        let stdoutURL = scratch.appendingPathComponent("stdout")
        let stderrURL = scratch.appendingPathComponent("stderr")
        guard fm.createFile(atPath: stdoutURL.path, contents: nil),
              fm.createFile(atPath: stderrURL.path, contents: nil) else {
            throw SSHError.connectionFailed("Could not create SSH capture files in \(scratch.path)")
        }

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        var stdinHandle: FileHandle?
        if let standardInput {
            let stdinURL = scratch.appendingPathComponent("stdin")
            try Data(standardInput.utf8).write(to: stdinURL)
            stdinHandle = try FileHandle(forReadingFrom: stdinURL)
        }
        defer { try? stdinHandle?.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        if let stdinHandle {
            process.standardInput = stdinHandle
        }

        do {
            try process.run()
        } catch {
            throw SSHError.connectionFailed(error.localizedDescription)
        }
        process.waitUntilExit()

        // Flush our duplicate descriptors before reading the capture files back.
        try? stdoutHandle.close()
        try? stderrHandle.close()

        let stdoutData = (try? Data(contentsOf: stdoutURL)) ?? Data()
        let stderrData = (try? Data(contentsOf: stderrURL)) ?? Data()
        return SSHCommandResult(
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }
}

/// Port of the frozen macOS `SSHService`.
///
/// Linux changes (all deliberate, all injected rather than hard-coded):
/// - `ssh` executable: `CHOPS_SSH_PATH` when set and non-empty, else `/usr/bin/ssh`.
/// - `homeDirectory` / environment / runner are initializer parameters, so tests never
///   touch the real `$HOME` or a live SSH server.
///
/// The command and quoting rules are byte-for-byte the frozen originals: `-p`, the
/// three `-o` options (`ConnectTimeout=10`, `BatchMode=yes`,
/// `StrictHostKeyChecking=accept-new`), explicit or auto-discovered `-i` key path,
/// `find ... -name 'SKILL.md' -type f`, `echo '---CHOPS_DELIM:<path>---' && cat '<path>'`,
/// `mkdir -p "$(dirname '<path>')" && cat > '<path>'`, and the same delimiter parser.
public struct SSHService: Sendable {
    /// Environment variable that overrides the ssh binary path on Linux.
    public static let sshPathEnvironmentKey = "CHOPS_SSH_PATH"
    /// Plan-mandated default; `/usr/bin/ssh` exists on Debian trixie.
    public static let defaultSSHPath = "/usr/bin/ssh"

    public let homeDirectory: URL
    public let environment: [String: String]
    private let runner: any SSHRunning

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        runner: any SSHRunning = SSHProcessRunner()
    ) {
        self.homeDirectory = homeDirectory
        self.environment = environment
        self.runner = runner
    }

    /// `CHOPS_SSH_PATH` when set/non-empty, else `/usr/bin/ssh`.
    public static func resolveSSHPath(environment: [String: String]) -> String {
        if let override = environment[sshPathEnvironmentKey], !override.isEmpty {
            return override
        }
        return defaultSSHPath
    }

    public var sshPath: String {
        Self.resolveSSHPath(environment: environment)
    }

    // MARK: - Public API (frozen signatures, async)

    public func testConnection(_ server: RemoteServer) async throws {
        let result = try await run(arguments: baseArguments(for: server) + ["echo", "ok"])
        if result.exitCode != 0 {
            throw SSHError.connectionFailed(result.stderr)
        }
    }

    public func findSkills(_ server: RemoteServer) async throws -> [(path: String, content: String)] {
        let findCommand = Self.findCommand(for: server)

        let found = try await run(arguments: baseArguments(for: server) + [findCommand])
        if found.exitCode != 0 {
            throw SSHError.connectionFailed(
                found.stderr.isEmpty ? "Connection failed (exit code \(found.exitCode))" : found.stderr
            )
        }

        let paths = found.stdout.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        if paths.isEmpty { return [] }

        // Read all files in a single SSH call, exactly like the frozen implementation.
        let combined = Self.catCommand(for: paths)
        let content = try await run(arguments: baseArguments(for: server) + [combined]).stdout

        return Self.parseDelimitedOutput(content)
    }

    public func readFile(_ server: RemoteServer, path: String) async throws -> String {
        let result = try await run(
            arguments: baseArguments(for: server) + ["cat \(Self.shellEscape(path))"]
        )
        if result.exitCode != 0 {
            throw SSHError.commandFailed(result.stderr)
        }
        return result.stdout
    }

    public func writeFile(_ server: RemoteServer, path: String, content: String) async throws {
        // Ensure parent directory exists, then write via stdin.
        let escaped = Self.shellEscape(path)
        let mkdirCommand = "mkdir -p \"$(dirname \(escaped))\" && cat > \(escaped)"
        let result = try await run(
            arguments: baseArguments(for: server) + [mkdirCommand],
            stdin: content
        )
        if result.exitCode != 0 {
            throw SSHError.commandFailed(result.stderr)
        }
    }

    // MARK: - Command construction (frozen rules)

    func baseArguments(for server: RemoteServer) -> [String] {
        var args = [
            "-p", "\(server.port)",
            "-o", "ConnectTimeout=10",
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new",
        ]

        if let keyPath = server.sshKeyPath, !keyPath.isEmpty {
            // User-specified key path (expand ~ if present).
            args += ["-i", Self.expandTilde(keyPath, homeDirectory: homeDirectory)]
        } else {
            // Auto-discover common default key names.
            for name in ["id_ed25519", "id_rsa", "id_ecdsa"] {
                let path = "\(homeDirectory.path)/.ssh/\(name)"
                if FileManager.default.fileExists(atPath: path) {
                    args += ["-i", path]
                    break
                }
            }
        }

        args.append(server.sshDestination)
        return args
    }

    /// Escapes a string for safe use inside single quotes in a shell command.
    static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escapes a path for the remote shell, handling tilde expansion.
    /// Uses double quotes so `$HOME` expands while spaces are preserved.
    static func shellQuotePath(_ path: String) -> String {
        var expanded = path
        if expanded.hasPrefix("~/") {
            expanded = "$HOME/" + expanded.dropFirst(2)
        } else if expanded == "~" {
            expanded = "$HOME"
        }
        // Double-quote: preserves $HOME expansion, protects spaces and globs.
        let escaped = expanded.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func findCommand(for server: RemoteServer) -> String {
        "find \(shellQuotePath(server.skillsBasePath)) -name 'SKILL.md' -type f 2>/dev/null"
    }

    static func catCommand(for paths: [String]) -> String {
        paths
            .map { "echo '---CHOPS_DELIM:\($0)---' && cat \(shellEscape($0))" }
            .joined(separator: " && ")
    }

    static func parseDelimitedOutput(_ output: String) -> [(path: String, content: String)] {
        var results: [(path: String, content: String)] = []
        let lines = output.components(separatedBy: "\n")
        var currentPath: String?
        var currentLines: [String] = []

        for line in lines {
            if line.hasPrefix("---CHOPS_DELIM:") && line.hasSuffix("---") {
                // Save previous block.
                if let path = currentPath {
                    results.append((path: path, content: currentLines.joined(separator: "\n")))
                }
                // Extract path from delimiter.
                let start = line.index(line.startIndex, offsetBy: 15)
                let end = line.index(line.endIndex, offsetBy: -3)
                currentPath = String(line[start..<end])
                currentLines = []
            } else {
                currentLines.append(line)
            }
        }

        // Save last block.
        if let path = currentPath {
            results.append((path: path, content: currentLines.joined(separator: "\n")))
        }

        return results
    }

    // MARK: - Internals

    private func run(arguments: [String], stdin: String? = nil) async throws -> SSHCommandResult {
        try await runner.run(
            executablePath: sshPath,
            arguments: arguments,
            standardInput: stdin
        )
    }

    private static func expandTilde(_ path: String, homeDirectory: URL) -> String {
        path.hasPrefix("~/") ? homeDirectory.path + path.dropFirst(1) : path
    }
}

extension RemoteServer {
    /// Port of the frozen `RemoteServer.sshDestination`
    /// (`Chops/Models/RemoteServer.swift`).
    public var sshDestination: String {
        "\(username)@\(host)"
    }
}
