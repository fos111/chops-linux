import Foundation
import XCTest

@testable import chopscore

/// One-shot agent transport tests for the Linux port (plan T08).
///
/// Every test drives the committed stub binaries via injected `PATH` (fixtures dir first)
/// and an injected `AgentEnvironment`; no live API calls and no real `claude`/`codex`
/// binaries are ever reachable, and the real `$HOME` is never touched.
final class AgentTransportTests: AgentTransportTestSupport.TransportTestCase {

    // MARK: - Binary resolution (PATH injection)

    func testPrependedFixturePathResolvesTheCommittedStubs() throws {
        let config = configuration

        let claude = try XCTUnwrap(config.binaryURL(for: .claude))
        let codex = try XCTUnwrap(config.binaryURL(for: .codex))

        let stubBin = scratch.appendingPathComponent("stub-bin", isDirectory: true)
        XCTAssertEqual(claude.standardizedFileURL, stubBin.appendingPathComponent("claude").standardizedFileURL)
        XCTAssertEqual(codex.standardizedFileURL, stubBin.appendingPathComponent("codex").standardizedFileURL)

        // The resolved binaries ARE the committed fixtures, not host installs.
        XCTAssertEqual(claude.resolvingSymlinksInPath().path, AgentTransportTestSupport.stubURL("fake-claude").path)
        XCTAssertEqual(codex.resolvingSymlinksInPath().path, AgentTransportTestSupport.stubURL("fake-codex").path)

        print("== T08 stub resolution ==")
        print("PATH[0] .......... \(agentPathHead())")
        print("claude ........... \(claude.path) -> \(claude.resolvingSymlinksInPath().path)")
        print("codex ............ \(codex.path) -> \(codex.resolvingSymlinksInPath().path)")
    }

    func testAgentFactoryReturnsTheMatchingTransport() throws {
        let config = configuration
        XCTAssertTrue(AgentFactory.make(for: .claude, configuration: config) is ClaudeCLIAgent)
        XCTAssertTrue(AgentFactory.make(for: .codex, configuration: config) is CodexCLIAgent)
    }

    // MARK: - Claude stub roundtrip

    func testClaudeStubRoundtripParsesSummaryAndFencedFileIntoPendingWrite() async throws {
        let skillURL = skillPath(".claude/skills/a-one.md")
        let original = try contents(of: skillURL)
        let config = configuration

        let agent = ClaudeCLIAgent(configuration: config)
        await agent.startConnect(workingDirectory: home, systemPrompt: nil)
        let connected = await agent.isConnected
        XCTAssertTrue(connected, "stub binary must be discoverable through the injected PATH")
        await agent.primeDeferredContent(for: skillURL.path, content: original)

        try await agent.prompt("Rename the heading and restate the closing note.")

        let summary = await agent.responseText
        let writes = await agent.pendingWrites
        let activities = await agent.activities
        let processing = await agent.isProcessing

        print("== T08 claude stub roundtrip ==")
        print("summary .......... \(summary)")
        print("pendingWrites .... \(writes.count)")
        print("write.path ....... \(writes.first?.path ?? "nil")")
        print("--- proposed content (stub-edited) ---")
        print(writes.first?.content ?? "nil")
        print("--- agent log ---")
        print(recorder.transcript)

        XCTAssertEqual(summary, "Renamed the example heading and rewrote the fixture skill body as requested.")
        XCTAssertFalse(processing)

        let write = try XCTUnwrap(writes.first)
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(write.path, skillURL.path)
        XCTAssertEqual(write.originalText, original)
        XCTAssertEqual(write.originalData, original.data(using: .utf8))
        XCTAssertTrue(write.existedBefore)
        XCTAssertFalse(write.agentDidWrite)
        XCTAssertFalse(write.pendingId.isEmpty)
        XCTAssertEqual(
            write.content,
            """
            ---
            name: a-one
            description: skill a (stub-edited)
            ---

            # A One (stub-edit)

            Updated body emitted by linux/fixtures/fake-claude.
            """ + "\n"
        )
        XCTAssertTrue(write.content.contains("fake-claude"), "stub marker proves no live API call")

        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activities.first?.kind, .thinking)
        XCTAssertEqual(activities.first?.status, .done)
        XCTAssertEqual(activities.first?.title, "Proposed edit ready")

        XCTAssertEqual(recorder.lines(containing: "Claude stdout").count, 1)
        XCTAssertEqual(recorder.lines(containing: "Claude exit=0").count, 1)
        XCTAssertTrue(recorder.lines(containing: "Claude stderr").isEmpty)
    }

    func testClaudePromptBeforeConnectThrowsNoSession() async throws {
        let agent = ClaudeCLIAgent(configuration: configuration)
        do {
            try await agent.prompt("hello")
            XCTFail("prompt without startConnect must throw .noSession")
        } catch let error as AgentError {
            XCTAssertEqual(error, .noSession)
        }
    }

    // MARK: - Codex stub roundtrip

    func testCodexStubRoundtripReadsTempLastMessageAndCleansItUp() async throws {
        let skillURL = skillPath(".codex/skills/c-three.md")
        let original = try contents(of: skillURL)
        let config = configuration

        let agent = CodexCLIAgent(configuration: config)
        await agent.startConnect(workingDirectory: home, systemPrompt: nil)
        let connected = await agent.isConnected
        XCTAssertTrue(connected)
        await agent.primeDeferredContent(for: skillURL.path, content: original)

        try await agent.prompt("Tighten the wording.")

        let summary = await agent.responseText
        let writes = await agent.pendingWrites

        print("== T08 codex stub roundtrip ==")
        print("summary .......... \(summary)")
        print("pendingWrites .... \(writes.count)")
        print("--- proposed content (stub-edited) ---")
        print(writes.first?.content ?? "nil")
        print("--- agent log ---")
        print(recorder.transcript)

        XCTAssertEqual(summary, "Tightened the fixture skill wording and restated the closing note.")
        XCTAssertEqual(writes.count, 1)

        let write = try XCTUnwrap(writes.first)
        XCTAssertEqual(write.path, skillURL.path)
        XCTAssertEqual(write.originalText, original)
        XCTAssertEqual(write.originalData, original.data(using: .utf8))
        XCTAssertTrue(write.existedBefore)
        XCTAssertFalse(write.agentDidWrite)
        XCTAssertEqual(
            write.content,
            """
            ---
            name: c-three
            description: skill c (stub-edited)
            ---

            # C Three (stub-edit)

            Updated body emitted by linux/fixtures/fake-codex.
            """ + "\n"
        )
        XCTAssertTrue(write.content.contains("fake-codex"), "stub marker proves no live API call")

        // Temp-file contract: the stub names the exact --output-last-message path it got,
        // and the transport must have removed it after reading the final message.
        let line = try XCTUnwrap(recorder.lines(containing: "wrote final message to").first)
        let tempPath = try XCTUnwrap(Self.path(after: "wrote final message to ", in: line))
        print("codex temp file .. \(tempPath) existsAfterPrompt=\(FileManager.default.fileExists(atPath: tempPath))")
        XCTAssertEqual(URL(fileURLWithPath: tempPath).lastPathComponent.hasPrefix("chops-codex-"), true)
        XCTAssertEqual(URL(fileURLWithPath: tempPath).pathExtension, "txt")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: tempPath),
            "Codex last-message temp file must be deleted after the turn"
        )
    }

    // MARK: - Exact CLI shapes (frozen macOS parity)

    func testClaudeArgumentsMatchTheMacOSCommandShape() {
        let args = ClaudeCLIAgent.arguments(systemPrompt: "SYS", userMessage: "USER")
        XCTAssertEqual(args, [
            "-p",
            "--output-format", "json",
            "--system-prompt", "SYS",
            "--model", "sonnet",
            "--settings", #"{"effortLevel":"low","permissions":{"dangerouslySkipPermissions":false},"includeCoAuthoredBy":false}"#,
            "--tools", "",
            "--",
            "USER",
        ])

        let env = ClaudeCLIAgent.childEnvironment(from: ["CLAUDECODE": "1", "OTHER": "x"])
        XCTAssertNil(env["CLAUDECODE"])
        XCTAssertEqual(env["CLAUDE_CODE_ENTRYPOINT"], "sdk-swift")
        XCTAssertEqual(env["CLAUDE_AGENT_SDK_VERSION"], "0.2.121")
        XCTAssertEqual(env["OTHER"], "x")
    }

    func testCodexArgumentsMatchTheMacOSCommandShape() {
        let args = CodexCLIAgent.arguments(lastMessagePath: "/tmp/chops-codex-x.txt", userMessage: "USER")
        XCTAssertEqual(args, [
            "exec",
            "--skip-git-repo-check",
            "--sandbox", "read-only",
            "--ephemeral",
            "--color", "never",
            "--output-last-message", "/tmp/chops-codex-x.txt",
            "USER",
        ])
        XCTAssertEqual(
            CodexCLIAgent.combinedMessage(systemPrompt: "SYS", userBody: "BODY"),
            "SYS\n\n---\n\nBODY"
        )
    }

    // MARK: - Failure path (generated scratch script, still no live binary)

    func testClaudeNonZeroExitSurfacesStderrAndFailsTheActivity() async throws {
        let binDirectory = scratch.appendingPathComponent("exit-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        let failing = binDirectory.appendingPathComponent("claude")
        try """
        #!/usr/bin/env bash
        echo "claude boom" >&2
        exit 3
        """.write(to: failing, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: failing.path)

        var environment = try XCTUnwrap(self.environment)
        environment["PATH"] = [binDirectory.path, "/usr/bin", "/bin"].joined(separator: ":")
        let agent = ClaudeCLIAgent(
            configuration: AgentEnvironment(homeDirectory: home, environment: environment)
        )
        await agent.startConnect(workingDirectory: home, systemPrompt: nil)
        await agent.primeDeferredContent(for: skillPath(".claude/skills/a-one.md").path, content: "orig")

        do {
            try await agent.prompt("trigger failure")
            XCTFail("non-zero exit must throw")
        } catch let error as AgentError {
            guard case .launchFailed(let detail) = error else {
                return XCTFail("expected .launchFailed, got \(error)")
            }
            XCTAssertTrue(detail.contains("Claude exited with code 3"), detail)
            XCTAssertTrue(detail.contains("claude boom"), detail)
        }

        let activities = await agent.activities
        XCTAssertEqual(activities.first?.status, .failed)
        XCTAssertEqual(activities.first?.title, "Failed")
        let writes = await agent.pendingWrites
        XCTAssertTrue(writes.isEmpty)
    }

    // MARK: - Helpers

    private func agentPathHead() -> String {
        (environment["PATH"] ?? "").split(separator: ":").first.map(String.init) ?? ""
    }

    /// Returns the substring after `marker` on the first line containing it.
    private static func path(after marker: String, in line: String) -> String? {
        guard let range = line.range(of: marker) else { return nil }
        let tail = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return tail.isEmpty ? nil : tail
    }
}
