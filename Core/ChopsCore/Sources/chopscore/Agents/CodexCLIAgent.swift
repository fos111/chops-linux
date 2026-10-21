import Foundation

/// One-shot transport for OpenAI Codex.
///
/// Port of the frozen macOS `CodexCLIAgent` (`Chops/Services/Agents/Codex/CodexCLIAgent.swift`).
/// Each `prompt()` is a single `codex exec --skip-git-repo-check --sandbox read-only
/// --ephemeral --color never --output-last-message <tmp> "<user message>"` invocation.
/// The final agent message is read from the temp file (stdout interleaves status lines,
/// "tokens used", colourised banners, etc.). Codex never touches the target file; Chops
/// owns the disk write the same way the Claude transport does.
public actor CodexCLIAgent: AgentSession {

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
        guard configuration.binaryURL(for: .codex) != nil else {
            lastError = AgentError.binaryNotInstalled(
                toolName: "Codex",
                installURL: AgentID.codex.installURL
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
        guard let bin = configuration.binaryURL(for: .codex),
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
            title: "Thinking with Codex…",
            status: .running
        ))
        currentActivity = "Thinking with Codex…"

        defer {
            isProcessing = false
            turnStartedAt = nil
            currentActivity = nil
        }

        let (filePath, fileContent) = primaryFile()
        // Codex doesn't accept a separate system prompt flag, so we splice it into the
        // user message — same shape that worked end-to-end in CLI smoke tests.
        let systemPrompt = sessionSystemPrompt ?? OneShotPrompts.defaultSystemPrompt(filePath: filePath)
        let userBody = OneShotPrompts.userMessage(
            userRequest: text,
            filePath: filePath,
            fileContent: fileContent
        )
        let combined = Self.combinedMessage(systemPrompt: systemPrompt, userBody: userBody)

        do {
            let result = try await runCodexOneshot(
                bin: bin,
                workingDir: wd,
                userMessage: combined
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
    /// can pin the CLI shape (and the temp-file path) without launching anything.
    static func arguments(lastMessagePath: String, userMessage: String) -> [String] {
        // `--output-last-message` is the cleanest way to get just the final agent reply.
        [
            "exec",
            "--skip-git-repo-check",
            "--sandbox", "read-only",
            "--ephemeral",
            "--color", "never",
            "--output-last-message", lastMessagePath,
            userMessage,
        ]
    }

    /// Codex has no system-prompt flag; the frozen transport splices it ahead of the user
    /// body with this exact separator.
    static func combinedMessage(systemPrompt: String, userBody: String) -> String {
        "\(systemPrompt)\n\n---\n\n\(userBody)"
    }

    /// Name shape of the temp file handed to `--output-last-message`. Tests assert the
    /// stub received a path of this shape and that the transport cleaned it up.
    static let lastMessageFilePrefix = "chops-codex-"

    private func runCodexOneshot(
        bin: URL,
        workingDir: URL,
        userMessage: String
    ) async throws -> String {
        let lastMsgURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Self.lastMessageFilePrefix)\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: lastMsgURL) }

        let invocation = AgentProcessRunner.Invocation(
            executableURL: bin,
            arguments: Self.arguments(lastMessagePath: lastMsgURL.path, userMessage: userMessage),
            environment: configuration.environment,
            workingDirectory: workingDir
        )

        let handle = AgentProcessHandle()
        currentProcess = handle
        defer { currentProcess = nil }

        let run = try await AgentProcessRunner.run(invocation, handle: handle)

        if Task.isCancelled || promptWasCancelled { throw CancellationError() }

        if let s = String(data: run.stdout, encoding: .utf8) {
            configuration.log("Codex stdout (\(run.stdout.count)B): \(s.prefix(2000))")
        }
        if let s = String(data: run.stderr, encoding: .utf8), !s.isEmpty {
            configuration.log("Codex stderr: \(s.prefix(2000))")
        }
        configuration.log("Codex exit=\(run.status)")

        if run.status != 0 {
            let errText = String(data: run.stderr, encoding: .utf8) ?? ""
            let trimmed = errText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AgentError.launchFailed(
                "Codex exited with code \(run.status)" +
                (trimmed.isEmpty ? "" : ":\n\(trimmed.suffix(800))")
            )
        }

        guard let lastMsg = try? String(contentsOf: lastMsgURL, encoding: .utf8),
              !lastMsg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let preview = String(data: run.stdout.prefix(400), encoding: .utf8) ?? "<non-utf8>"
            throw AgentError.launchFailed("Codex returned no final message. First 400 bytes of stdout:\n\(preview)")
        }
        return lastMsg
    }
}
