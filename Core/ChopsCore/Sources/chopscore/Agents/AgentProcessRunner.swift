import Foundation

/// One-shot subprocess execution for the agent transports.
///
/// Linux notes:
/// - The frozen macOS implementation drains `Pipe`s from detached tasks. On Linux we
///   redirect stdout/stderr to temporary files instead, then read them after the child
///   exits. That is deadlock-free (no pipe buffer can fill) and keeps `Process` and its
///   file handles inside a single thread, which Swift 6 strict concurrency requires.
/// - `AgentProcessHandle` lets `cancelPrompt()` terminate an in-flight child from
///   outside the actor without sharing an unsendable `Process`.
public enum AgentProcessRunner {
    public struct Invocation: Sendable {
        public var executableURL: URL
        public var arguments: [String]
        public var environment: [String: String]
        public var workingDirectory: URL

        public init(
            executableURL: URL,
            arguments: [String],
            environment: [String: String],
            workingDirectory: URL
        ) {
            self.executableURL = executableURL
            self.arguments = arguments
            self.environment = environment
            self.workingDirectory = workingDirectory
        }
    }

    public struct Result: Sendable {
        public var status: Int32
        public var stdout: Data
        public var stderr: Data

        public init(status: Int32, stdout: Data, stderr: Data) {
            self.status = status
            self.stdout = stdout
            self.stderr = stderr
        }
    }

    /// Runs the invocation to completion on a background queue and returns the captured
    /// streams. Cancelling the surrounding task terminates the child.
    public static func run(_ invocation: Invocation, handle: AgentProcessHandle) async throws -> Result {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        continuation.resume(returning: try runBlocking(invocation, handle: handle))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            handle.terminate()
        }
    }

    // MARK: - Internals

    private static func runBlocking(
        _ invocation: Invocation,
        handle: AgentProcessHandle
    ) throws -> Result {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("chops-agent-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }

        let stdoutURL = scratch.appendingPathComponent("stdout")
        let stderrURL = scratch.appendingPathComponent("stderr")
        guard fm.createFile(atPath: stdoutURL.path, contents: nil),
              fm.createFile(atPath: stderrURL.path, contents: nil) else {
            throw AgentError.launchFailed("Could not create agent capture files in \(scratch.path)")
        }

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        let proc = Process()
        proc.executableURL = invocation.executableURL
        proc.arguments = invocation.arguments
        proc.environment = invocation.environment
        proc.currentDirectoryURL = invocation.workingDirectory
        proc.standardOutput = stdoutHandle
        proc.standardError = stderrHandle

        do {
            try proc.run()
        } catch {
            throw AgentError.launchFailed(error.localizedDescription)
        }

        // A cancel that raced the launch marks the handle terminated; kill the child
        // immediately so this turn cannot run to completion after cancellation.
        if !handle.attach(proc) {
            proc.terminate()
        }
        proc.waitUntilExit()
        handle.detach()

        // Flush our duplicate descriptors before reading the files back.
        try? stdoutHandle.close()
        try? stderrHandle.close()

        return Result(
            status: proc.terminationStatus,
            stdout: (try? Data(contentsOf: stdoutURL)) ?? Data(),
            stderr: (try? Data(contentsOf: stderrURL)) ?? Data()
        )
    }
}

/// Sendable cancellation handle for an in-flight `Process`.
///
/// `Process` is not `Sendable`; the handle owns it behind a lock and only exposes
/// `terminate()`, which is exactly what `cancelPrompt()` needs.
public final class AgentProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var terminated = false

    public init() {}

    /// Registers the running process. Returns `false` when cancellation already
    /// happened before registration; the caller must terminate the process itself.
    func attach(_ process: Process) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !terminated else { return false }
        self.process = process
        return true
    }

    func detach() {
        lock.lock()
        process = nil
        lock.unlock()
    }

    /// Terminates the child if one is running, and poisons the handle so a late attach
    /// is rejected. Safe to call repeatedly.
    public func terminate() {
        lock.lock()
        terminated = true
        let running = process
        lock.unlock()
        running?.terminate()
    }
}
