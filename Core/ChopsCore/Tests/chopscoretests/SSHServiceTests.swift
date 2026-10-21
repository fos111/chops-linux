import Foundation
import XCTest

@testable import chopscore

/// Static unit tests for the ported SSH service (plan T09).
///
/// Every test injects a recording `SSHRunning`, so no `ssh` binary is launched and no
/// live server is required. The frozen argv/quoting rules are asserted byte-for-byte.
final class SSHServiceTests: XCTestCase {
    private var scratch: URL!
    private var home: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = try StoreTestSupport.makeTemporaryDirectory(prefix: "chopscore-ssh")
        home = scratch.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratch {
            try? FileManager.default.removeItem(at: scratch)
        }
        scratch = nil
        home = nil
        try super.tearDownWithError()
    }

    private func service(
        environment: [String: String] = [:],
        runner: RecordingSSHRunner
    ) -> SSHService {
        SSHService(homeDirectory: home, environment: environment, runner: runner)
    }

    private func server(
        port: Int = 22,
        host: String = "example.com",
        username: String = "chops",
        skillsBasePath: String = "~/.claude/skills",
        sshKeyPath: String? = nil
    ) -> RemoteServer {
        RemoteServer(
            label: "test",
            host: host,
            port: port,
            username: username,
            skillsBasePath: skillsBasePath,
            sshKeyPath: sshKeyPath
        )
    }

    // MARK: - ssh path resolution

    func testSSHPathUsesChopsSSHPathWhenSet() {
        let svc = service(environment: ["CHOPS_SSH_PATH": "/opt/chops/bin/ssh"], runner: RecordingSSHRunner())
        XCTAssertEqual(svc.sshPath, "/opt/chops/bin/ssh")
    }

    func testSSHPathDefaultsToUsrBinSSH() {
        let svc = service(environment: [:], runner: RecordingSSHRunner())
        XCTAssertEqual(svc.sshPath, "/usr/bin/ssh")
        XCTAssertEqual(SSHService.defaultSSHPath, "/usr/bin/ssh")
    }

    func testEmptyChopsSSHPathFallsBackToDefault() {
        let svc = service(environment: ["CHOPS_SSH_PATH": ""], runner: RecordingSSHRunner())
        XCTAssertEqual(svc.sshPath, "/usr/bin/ssh")
    }

    func testResolvedPathIsTheExecutableLaunched() async throws {
        let runner = RecordingSSHRunner(stubs: [.init(stdout: "", stderr: "", exitCode: 0)])
        let svc = service(environment: ["CHOPS_SSH_PATH": "/custom/ssh"], runner: runner)

        try await svc.testConnection(server())

        XCTAssertEqual(runner.invocations.map(\.executablePath), ["/custom/ssh"])
    }

    // MARK: - base arguments / known_hosts

    func testBaseArgumentsMatchFrozenMacOSOrderAndValues() {
        let svc = service(runner: RecordingSSHRunner())
        XCTAssertEqual(
            svc.baseArguments(for: server()),
            [
                "-p", "22",
                "-o", "ConnectTimeout=10",
                "-o", "BatchMode=yes",
                "-o", "StrictHostKeyChecking=accept-new",
                "chops@example.com",
            ]
        )
    }

    func testCustomPortAndDestination() {
        let svc = service(runner: RecordingSSHRunner())
        let args = svc.baseArguments(for: server(port: 2222, host: "10.0.0.5", username: "root"))
        XCTAssertEqual(Array(args.prefix(2)), ["-p", "2222"])
        XCTAssertEqual(args.last, "root@10.0.0.5")
    }

    func testExplicitKeyPathExpandsTildeAgainstInjectedHome() {
        let svc = service(runner: RecordingSSHRunner())
        let args = svc.baseArguments(for: server(sshKeyPath: "~/.ssh/chops_ed25519"))
        XCTAssertEqual(Array(args.suffix(3)), ["-i", "\(home.path)/.ssh/chops_ed25519", "chops@example.com"])
    }

    func testAbsoluteExplicitKeyPathIsUsedVerbatim() {
        let svc = service(runner: RecordingSSHRunner())
        let args = svc.baseArguments(for: server(sshKeyPath: "/etc/ssh/id_custom"))
        XCTAssertTrue(args.contains("/etc/ssh/id_custom"))
    }

    func testAutoDiscoveredDefaultKeyPrefersEd25519() throws {
        let sshDir = home.appendingPathComponent(".ssh", isDirectory: true)
        try FileManager.default.createDirectory(at: sshDir, withIntermediateDirectories: true)
        for name in ["id_rsa", "id_ed25519", "id_ecdsa"] {
            try Data("key".utf8).write(to: sshDir.appendingPathComponent(name))
        }

        let svc = service(runner: RecordingSSHRunner())
        let args = svc.baseArguments(for: server())
        XCTAssertTrue(args.contains("\(home.path)/.ssh/id_ed25519"))
        XCTAssertFalse(args.contains("\(home.path)/.ssh/id_rsa"))
        XCTAssertFalse(args.contains("\(home.path)/.ssh/id_ecdsa"))
    }

    func testAutoDiscoveryFallsThroughToRsaWhenEd25519Missing() throws {
        let sshDir = home.appendingPathComponent(".ssh", isDirectory: true)
        try FileManager.default.createDirectory(at: sshDir, withIntermediateDirectories: true)
        try Data("key".utf8).write(to: sshDir.appendingPathComponent("id_rsa"))

        let svc = service(runner: RecordingSSHRunner())
        let args = svc.baseArguments(for: server())
        XCTAssertTrue(args.contains("\(home.path)/.ssh/id_rsa"))
    }

    func testNoKeyFlagWhenNoDefaultKeyExists() {
        let svc = service(runner: RecordingSSHRunner())
        let args = svc.baseArguments(for: server())
        XCTAssertFalse(args.contains("-i"))
    }

    // MARK: - quoting

    func testShellEscapeSingleQuotesApostrophes() {
        XCTAssertEqual(SSHService.shellEscape("/home/me/SKILL.md"), "'/home/me/SKILL.md'")
        XCTAssertEqual(SSHService.shellEscape("/home/me/My Skills/SKILL.md"), "'/home/me/My Skills/SKILL.md'")
        XCTAssertEqual(SSHService.shellEscape("it's"), "'it'\\''s'")
    }

    func testShellQuotePathExpandsTildeAndProtectsDoubleQuotes() {
        XCTAssertEqual(SSHService.shellQuotePath("~/.claude/skills"), "\"$HOME/.claude/skills\"")
        XCTAssertEqual(SSHService.shellQuotePath("~"), "\"$HOME\"")
        XCTAssertEqual(SSHService.shellQuotePath("/tmp/a b"), "\"/tmp/a b\"")
        XCTAssertEqual(SSHService.shellQuotePath("/tmp/a\"b"), "\"/tmp/a\\\"b\"")
    }

    func testFindCommandMatchesFrozenShape() {
        XCTAssertEqual(
            SSHService.findCommand(for: server()),
            "find \"$HOME/.claude/skills\" -name 'SKILL.md' -type f 2>/dev/null"
        )
    }

    // MARK: - testConnection

    func testTestConnectionRunsEchoOK() async throws {
        let runner = RecordingSSHRunner(stubs: [.init(stdout: "ok\n", stderr: "", exitCode: 0)])
        try await service(runner: runner).testConnection(server())

        XCTAssertEqual(runner.invocations.count, 1)
        XCTAssertEqual(Array(runner.invocations[0].arguments.suffix(2)), ["echo", "ok"])
        XCTAssertNil(runner.invocations[0].standardInput)
    }

    func testTestConnectionThrowsConnectionFailedWithStderr() async {
        let runner = RecordingSSHRunner(stubs: [.init(stdout: "", stderr: "Permission denied (publickey).", exitCode: 255)])
        do {
            try await service(runner: runner).testConnection(server())
            XCTFail("expected connectionFailed")
        } catch let error as SSHError {
            XCTAssertEqual(error, .connectionFailed("Permission denied (publickey)."))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - findSkills

    func testFindSkillsBuildsFrozenFindAndCatCommands() async throws {
        let runner = RecordingSSHRunner(stubs: [
            .init(
                stdout: "/home/me/.claude/skills/a-one/SKILL.md\n/home/me/.claude/skills/b-two/SKILL.md\n",
                stderr: "",
                exitCode: 0
            ),
            .init(
                stdout: """
                ---CHOPS_DELIM:/home/me/.claude/skills/a-one/SKILL.md---
                name: a-one
                # A One
                ---CHOPS_DELIM:/home/me/.claude/skills/b-two/SKILL.md---
                name: b-two
                # B Two
                """,
                stderr: "",
                exitCode: 0
            ),
        ])

        let skills = try await service(runner: runner).findSkills(server())

        XCTAssertEqual(runner.invocations.count, 2)
        XCTAssertEqual(
            runner.invocations[0].arguments.last,
            "find \"$HOME/.claude/skills\" -name 'SKILL.md' -type f 2>/dev/null"
        )
        XCTAssertEqual(
            runner.invocations[1].arguments.last,
            "echo '---CHOPS_DELIM:/home/me/.claude/skills/a-one/SKILL.md---' && cat '/home/me/.claude/skills/a-one/SKILL.md'"
                + " && echo '---CHOPS_DELIM:/home/me/.claude/skills/b-two/SKILL.md---' && cat '/home/me/.claude/skills/b-two/SKILL.md'"
        )
        XCTAssertEqual(skills.count, 2)
        XCTAssertEqual(skills[0].path, "/home/me/.claude/skills/a-one/SKILL.md")
        XCTAssertEqual(skills[0].content, "name: a-one\n# A One")
        XCTAssertEqual(skills[1].path, "/home/me/.claude/skills/b-two/SKILL.md")
        XCTAssertEqual(skills[1].content, "name: b-two\n# B Two")
    }

    func testFindSkillsReturnsEmptyWithoutSecondCallWhenFindFindsNothing() async throws {
        let runner = RecordingSSHRunner(stubs: [.init(stdout: "", stderr: "", exitCode: 0)])

        let skills = try await service(runner: runner).findSkills(server())

        XCTAssertEqual(skills.count, 0)
        XCTAssertEqual(runner.invocations.count, 1)
    }

    func testFindSkillsThrowsConnectionFailedOnNonZeroExit() async {
        let runner = RecordingSSHRunner(stubs: [
            .init(stdout: "", stderr: "ssh: connect to host example.com port 22: Connection refused", exitCode: 255),
        ])
        do {
            _ = try await service(runner: runner).findSkills(server())
            XCTFail("expected connectionFailed")
        } catch let error as SSHError {
            XCTAssertEqual(
                error,
                .connectionFailed("ssh: connect to host example.com port 22: Connection refused")
            )
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testFindSkillsUsesGenericMessageForEmptyStderr() async {
        let runner = RecordingSSHRunner(stubs: [.init(stdout: "", stderr: "", exitCode: 7)])
        do {
            _ = try await service(runner: runner).findSkills(server())
            XCTFail("expected connectionFailed")
        } catch let error as SSHError {
            XCTAssertEqual(error, .connectionFailed("Connection failed (exit code 7)"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - readFile / writeFile

    func testReadFileQuotesThePath() async throws {
        let runner = RecordingSSHRunner(stubs: [.init(stdout: "contents", stderr: "", exitCode: 0)])
        let content = try await service(runner: runner).readFile(server(), path: "/home/me/My Skills/SKILL.md")

        XCTAssertEqual(content, "contents")
        XCTAssertEqual(runner.invocations[0].arguments.last, "cat '/home/me/My Skills/SKILL.md'")
    }

    func testReadFileThrowsCommandFailed() async {
        let runner = RecordingSSHRunner(stubs: [.init(stdout: "", stderr: "No such file", exitCode: 1)])
        do {
            _ = try await service(runner: runner).readFile(server(), path: "/missing.md")
            XCTFail("expected commandFailed")
        } catch let error as SSHError {
            XCTAssertEqual(error, .commandFailed("No such file"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testWriteFileMirrorsMkdirAndStdinRules() async throws {
        let runner = RecordingSSHRunner(stubs: [.init(stdout: "", stderr: "", exitCode: 0)])
        try await service(runner: runner).writeFile(
            server(),
            path: "/home/me/.claude/skills/new/SKILL.md",
            content: "---\nname: new\n---\n"
        )

        XCTAssertEqual(
            runner.invocations[0].arguments.last,
            "mkdir -p \"$(dirname '/home/me/.claude/skills/new/SKILL.md')\" && cat > '/home/me/.claude/skills/new/SKILL.md'"
        )
        XCTAssertEqual(runner.invocations[0].standardInput, "---\nname: new\n---\n")
    }

    func testWriteFileThrowsCommandFailed() async {
        let runner = RecordingSSHRunner(stubs: [.init(stdout: "", stderr: "Permission denied", exitCode: 1)])
        do {
            try await service(runner: runner).writeFile(server(), path: "/root/SKILL.md", content: "x")
            XCTFail("expected commandFailed")
        } catch let error as SSHError {
            XCTAssertEqual(error, .commandFailed("Permission denied"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - delimiter parser

    func testParseDelimitedOutputIgnoresPreambleAndKeepsLastBlock() {
        let output = """
        banner line
        ---CHOPS_DELIM:/a/SKILL.md---
        body a
        ---CHOPS_DELIM:/b/SKILL.md---
        body b
        still b
        """
        let parsed = SSHService.parseDelimitedOutput(output)

        XCTAssertEqual(parsed.map(\.path), ["/a/SKILL.md", "/b/SKILL.md"])
        XCTAssertEqual(parsed[0].content, "body a")
        XCTAssertEqual(parsed[1].content, "body b\nstill b")
    }

    func testParseDelimitedOutputWithoutDelimitersIsEmpty() {
        XCTAssertTrue(SSHService.parseDelimitedOutput("just text\nno delimiters").isEmpty)
        XCTAssertTrue(SSHService.parseDelimitedOutput("").isEmpty)
    }

    // MARK: - live opt-in

    /// Live end-to-end is out of automated QA. The module compiles and unit-skips
    /// unless an operator explicitly exports `CHOPS_TEST_SSH_TARGET=user@host`.
    func testLiveSSHConnectionIsSkippedWithoutConfiguredTarget() async throws {
        guard let target = ProcessInfo.processInfo.environment["CHOPS_TEST_SSH_TARGET"],
              let at = target.firstIndex(of: "@"),
              at != target.startIndex,
              target.index(after: at) != target.endIndex else {
            throw XCTSkip(
                "No live SSH server configured (set CHOPS_TEST_SSH_TARGET=user@host); live e2e is out of automated QA."
            )
        }

        let username = String(target[target.startIndex..<at])
        let host = String(target[target.index(after: at)...])
        let liveServer = RemoteServer(
            label: "live",
            host: host,
            username: username,
            skillsBasePath: "~/.claude/skills"
        )
        try await SSHService().testConnection(liveServer)
    }
}

// MARK: - Test doubles

struct SSHInvocation: Sendable, Equatable {
    let executablePath: String
    let arguments: [String]
    let standardInput: String?
}

final class RecordingSSHRunner: SSHRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [SSHInvocation] = []
    private var stubs: [SSHCommandResult]
    private let failure: SSHError?

    init(stubs: [SSHCommandResult] = [], failure: SSHError? = nil) {
        self.stubs = stubs
        self.failure = failure
    }

    var invocations: [SSHInvocation] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func run(
        executablePath: String,
        arguments: [String],
        standardInput: String?
    ) async throws -> SSHCommandResult {
        let (failure, stub) = lock.withLock { () -> (SSHError?, SSHCommandResult) in
            recorded.append(
                SSHInvocation(executablePath: executablePath, arguments: arguments, standardInput: standardInput)
            )
            let failure = self.failure
            let stub = stubs.isEmpty ? SSHCommandResult(stdout: "", stderr: "", exitCode: 0) : stubs.removeFirst()
            return (failure, stub)
        }

        if let failure { throw failure }
        return stub
    }
}
