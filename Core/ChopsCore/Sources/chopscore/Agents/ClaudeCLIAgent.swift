import Foundation

/// One-shot transport for Claude Code.
///
/// Port of the frozen macOS `ClaudeCLIAgent` (`Chops/Services/Agents/Claude/ClaudeCLIAgent.swift`).
/// Each `prompt()` is a single `claude --print --output-format json` invocation: send the
/// system prompt + current file content + user request, wait for the response, parse out a
/// fenced code block (or a structured-edits JSON envelope) as the proposed new file content,
/// and build a `PendingWrite` for the diff-review flow to gate.
///
/// Chops owns the disk write — Claude never touches the file.
public actor ClaudeCLIAgent: AgentSession {

    // MARK: - AgentSession state

    public private(set) var responseText: String = ""
    public private(set) var thoughtText: String = ""
    public private(set) var currentActivity: String? = nil
    public private(set) var pendingWrites: [PendingWrite] = []
    public private(set) var deferredContent: [String: String] = [:]
    public private(set) var isConnected: Bool = false
    public private(set) var isConnecting: Bool = false
    public private(set) var isProcessing: Bool = false
    public private(set) var turnStartedAt: Date? = nil
    public private(set) var activities: [AgentActivity] = []
    public private(set) var lastError: String? = nil
    public private(set) var isBypassMode: Bool = false  // unused in one-shot mode

    // MARK: - Private

    private let configuration: AgentEnvironment
    private var workingDirectory: URL?
    private var sessionSystemPrompt: String?
    private var currentProcess: AgentProcessHandle?
    private var promptWasCancelled = false

    public init(configuration: AgentEnvironment) {
        self.configuration = configuration
    }

    // MARK: - Lifecycle

    public func startConnect(workingDirectory: URL, systemPrompt: String?) {
        self.workingDirectory = workingDirectory
        self.sessionSystemPrompt = systemPrompt
        self.lastError = nil
        guard configuration.binaryURL(for: .claude) != nil else {
            lastError = AgentError.binaryNotInstalled(
                toolName: "Claude Code",
                installURL: AgentID.claude.installURL
            ).localizedDescription
            isConnected = false
            return
        }
        isConnected = true
    }

    public func disconnect() async {
        currentProcess?.terminate()
        currentProcess = nil
        isConnected = false
        isProcessing = false
        turnStartedAt = nil
        responseText = ""
        thoughtText = ""
        currentActivity = nil
        activities = []
        pendingWrites = []
        deferredContent = [:]
        lastError = nil
        workingDirectory = nil
        sessionSystemPrompt = nil
    }

    // MARK: - Per-turn

    public func prompt(_ text: String) async throws {
        guard let bin = configuration.binaryURL(for: .claude),
              let wd = workingDirectory else {
            throw AgentError.noSession
        }

        responseText = ""
        thoughtText = ""
        pendingWrites = []
        currentActivity = nil
        activities = []
        turnStartedAt = Date()
        isProcessing = true
        promptWasCancelled = false

        let activityId = UUID()
        activities.append(AgentActivity(
            id: activityId,
            kind: .thinking,
            title: "Thinking with Claude…",
            status: .running
        ))
        currentActivity = "Thinking with Claude…"

        defer {
            isProcessing = false
            turnStartedAt = nil
            currentActivity = nil
        }

        let (filePath, fileContent) = primaryFile()
        let userMessage = OneShotPrompts.userMessage(
            userRequest: text,
            filePath: filePath,
            fileContent: fileContent
        )
        let systemPrompt = sessionSystemPrompt ?? OneShotPrompts.defaultSystemPrompt(filePath: filePath)

        do {
            let result = try await runClaudeOneshot(
                bin: bin,
                workingDir: wd,
                systemPrompt: systemPrompt,
                userMessage: userMessage
            )

            let parsed = OneShotResponseParser.parse(result, originalContent: fileContent)
            responseText = parsed.summary

            guard let newContent = parsed.newContent,
                  let filePath, let fileContent,
                  newContent != fileContent else {
                if responseText.isEmpty {
                    responseText = result.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let i = activities.firstIndex(where: { $0.id == activityId }) {
                    activities[i].status = .done
                    activities[i].title = "Replied"
                }
                return
            }

            let resolvedPath = URL(fileURLWithPath: filePath).resolvingSymlinksInPath().path
            pendingWrites.append(PendingWrite(
                path: filePath,
                content: newContent,
                originalText: fileContent,
                originalData: fileContent.data(using: .utf8),
                existedBefore: FileManager.default.fileExists(atPath: resolvedPath),
                agentDidWrite: false
            ))

            if let i = activities.firstIndex(where: { $0.id == activityId }) {
                activities[i].status = .done
                activities[i].title = "Proposed edit ready"
            }
        } catch is CancellationError {
            if let i = activities.firstIndex(where: { $0.id == activityId }) {
                activities[i].status = .failed
                activities[i].title = "Cancelled"
            }
            throw CancellationError()
        } catch {
            if let i = activities.firstIndex(where: { $0.id == activityId }) {
                activities[i].status = .failed
                activities[i].title = "Failed"
                activities[i].detail = error.localizedDescription
            }
            throw error
        }
    }

    public func cancelPrompt() {
        promptWasCancelled = true
        currentProcess?.terminate()
    }

    // MARK: - Writes (no-ops in one-shot mode — we own disk writes)

    public func clearPendingWrites() {
        pendingWrites = []
        deferredContent = [:]
    }

    public func primeDeferredContent(for path: String, content: String) {
        // Single-file flows store both the literal and resolved-symlink path so callers
        // can look up by either. ComposePanel only ever primes the file currently in
        // the editor, so primaryFile() picks it up reliably.
        deferredContent[path] = content
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        if resolved != path { deferredContent[resolved] = content }
    }

    nonisolated public func conversationalText(from text: String) -> String { text }

    // MARK: - Internals

    private func primaryFile() -> (path: String?, content: String?) {
        if let entry = deferredContent.first {
            return (entry.key, entry.value)
        }
        return (nil, nil)
    }

    /// Exact argv the frozen macOS transport builds. Kept as a static function so tests
    /// can pin the CLI shape without launching anything.
    static func arguments(systemPrompt: String, userMessage: String) -> [String] {
        // `--settings` overrides ~/.claude/settings.json for THIS session only. We force
        // effortLevel="low" so the user's global "high" doesn't make every Chops turn burn
        // 5+ minutes on extended thinking for trivial markdown edits.
        let sessionSettings = #"{"effortLevel":"low","permissions":{"dangerouslySkipPermissions":false},"includeCoAuthoredBy":false}"#
        // Do NOT pass `--add-dir` — it's variadic and silently consumes the positional
        // prompt arg that follows. `--tools ""` disables tool use so Claude cannot write
        // behind Chops' diff review; `--` keeps the prompt out of that variadic option.
        return [
            "-p",
            "--output-format", "json",
            "--system-prompt", systemPrompt,
            "--model", "sonnet",
            "--settings", sessionSettings,
            "--tools", "",
            "--",
            userMessage,
        ]
    }

    /// Child environment: the frozen transport's Claude SDK markers, with any inherited
    /// `CLAUDECODE` entry removed so the CLI does not think it is running inside itself.
    static func childEnvironment(from base: [String: String]) -> [String: String] {
        var env = base
        env.removeValue(forKey: "CLAUDECODE")
        env["CLAUDE_CODE_ENTRYPOINT"] = "sdk-swift"
        env["CLAUDE_AGENT_SDK_VERSION"] = "0.2.121"
        return env
    }

    private func runClaudeOneshot(
        bin: URL,
        workingDir: URL,
        systemPrompt: String,
        userMessage: String
    ) async throws -> String {
        let invocation = AgentProcessRunner.Invocation(
            executableURL: bin,
            arguments: Self.arguments(systemPrompt: systemPrompt, userMessage: userMessage),
            environment: Self.childEnvironment(from: configuration.environment),
            workingDirectory: workingDir
        )

        let handle = AgentProcessHandle()
        currentProcess = handle
        defer { currentProcess = nil }

        let run = try await AgentProcessRunner.run(invocation, handle: handle)

        if Task.isCancelled || promptWasCancelled { throw CancellationError() }

        if let s = String(data: run.stdout, encoding: .utf8) {
            configuration.log("Claude stdout (\(run.stdout.count)B): \(s.prefix(2000))")
        }
        if let s = String(data: run.stderr, encoding: .utf8), !s.isEmpty {
            configuration.log("Claude stderr: \(s.prefix(2000))")
        }
        configuration.log("Claude exit=\(run.status)")

        if run.status != 0 {
            let errText = String(data: run.stderr, encoding: .utf8) ?? ""
            let trimmed = errText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AgentError.launchFailed(
                "Claude exited with code \(run.status)" +
                (trimmed.isEmpty ? "" : ":\n\(trimmed.suffix(800))")
            )
        }

        struct PrintResult: Decodable {
            let result: String?
            let is_error: Bool?
            let total_cost_usd: Double?
        }

        let envelope: PrintResult
        do {
            envelope = try JSONDecoder().decode(PrintResult.self, from: run.stdout)
        } catch {
            let preview = String(data: run.stdout.prefix(400), encoding: .utf8) ?? "<non-utf8>"
            throw AgentError.launchFailed("Couldn't parse Claude's reply. First 400 bytes:\n\(preview)")
        }
        if envelope.is_error == true {
            throw AgentError.launchFailed(envelope.result ?? "Claude reported an error")
        }
        return envelope.result ?? ""
    }
}
