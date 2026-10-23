import Foundation
import XCTest

@testable import chopscore

/// Linux path-table tests for the ported `ToolSource` (plan T07).
///
/// Everything is computed against explicit temporary paths; the real `$HOME` is never
/// read and the host `/usr/bin` entries are bypassed with `cliSearchPaths: []` where a
/// deterministic answer is required.
final class ToolSourceLinuxTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = try StoreTestSupport.makeTemporaryDirectory(prefix: "chopscore-toolsource")
    }

    override func tearDownWithError() throws {
        if let scratch {
            try? FileManager.default.removeItem(at: scratch)
        }
        scratch = nil
        try super.tearDownWithError()
    }

    // MARK: - Path tables

    func testGlobalSkillPathsUseInjectedHomeAndConfigHome() {
        let home = URL(fileURLWithPath: "/tmp/opencode/t07-home", isDirectory: true)
        let config = URL(fileURLWithPath: "/tmp/opencode/t07-config", isDirectory: true)

        XCTAssertEqual(
            ToolSource.claude.globalPaths(homeDirectory: home, configHomeDirectory: config),
            ["/tmp/opencode/t07-home/.claude/skills"]
        )
        XCTAssertEqual(
            ToolSource.codex.globalPaths(homeDirectory: home, configHomeDirectory: config),
            ["/tmp/opencode/t07-home/.codex/skills"]
        )
        XCTAssertEqual(
            ToolSource.opencode.globalPaths(homeDirectory: home, configHomeDirectory: config),
            ["/tmp/opencode/t07-config/opencode/skills"]
        )
        XCTAssertEqual(
            ToolSource.amp.globalPaths(homeDirectory: home, configHomeDirectory: config),
            ["/tmp/opencode/t07-config/amp/skills"]
        )
        XCTAssertEqual(
            ToolSource.agents.globalPaths(homeDirectory: home, configHomeDirectory: config),
            ["/tmp/opencode/t07-home/.agents/skills"]
        )
        XCTAssertEqual(
            ToolSource.antigravity.globalPaths(homeDirectory: home, configHomeDirectory: config),
            ["/tmp/opencode/t07-home/.gemini/antigravity/skills"]
        )
        XCTAssertEqual(
            ToolSource.claudeDesktop.globalPaths(homeDirectory: home, configHomeDirectory: config),
            []
        )
    }

    func testAgentAndRulePaths() {
        let home = URL(fileURLWithPath: "/tmp/opencode/t07-home", isDirectory: true)

        XCTAssertEqual(ToolSource.claude.globalAgentPaths(homeDirectory: home), ["/tmp/opencode/t07-home/.claude/agents"])
        XCTAssertEqual(ToolSource.cursor.globalAgentPaths(homeDirectory: home), ["/tmp/opencode/t07-home/.cursor/agents"])
        XCTAssertEqual(ToolSource.codex.globalAgentPaths(homeDirectory: home), ["/tmp/opencode/t07-home/.codex/agents"])
        XCTAssertEqual(ToolSource.claude.globalAgentPaths(homeDirectory: home).count, 1)

        XCTAssertEqual(ToolSource.cursor.globalRulePaths(homeDirectory: home), ["/tmp/opencode/t07-home/.cursor/rules"])
        XCTAssertEqual(
            ToolSource.windsurf.globalRulePaths(homeDirectory: home),
            [
                "/tmp/opencode/t07-home/.codeium/windsurf/memories",
                "/tmp/opencode/t07-home/.windsurf/rules",
            ]
        )
        XCTAssertEqual(ToolSource.claude.globalRulePaths(homeDirectory: home), [])
    }

    func testHermesAndOpenClawPathsAreExistenceGated() throws {
        let home = try XCTUnwrap(scratch)
        let config = home.appendingPathComponent(".config", isDirectory: true)

        XCTAssertEqual(
            ToolSource.hermes.globalPaths(homeDirectory: home, configHomeDirectory: config),
            []
        )
        XCTAssertEqual(
            ToolSource.openclaw.globalPaths(homeDirectory: home, configHomeDirectory: config),
            []
        )

        let hermesSkills = home.appendingPathComponent(".hermes/skills")
        let openclawSkills = home.appendingPathComponent(".openclaw/skills")
        try FileManager.default.createDirectory(at: hermesSkills, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: openclawSkills, withIntermediateDirectories: true)

        XCTAssertEqual(
            ToolSource.hermes.globalPaths(homeDirectory: home, configHomeDirectory: config),
            [hermesSkills.path]
        )
        XCTAssertEqual(
            ToolSource.openclaw.globalPaths(homeDirectory: home, configHomeDirectory: config),
            [openclawSkills.path]
        )
    }

    // MARK: - Linux remaps

    func testOpenClawNpmRootsReplaceHomebrew() {
        XCTAssertEqual(
            ToolSource.npmGlobalSkillRoots,
            [
                "/usr/local/lib/node_modules/openclaw/skills",
                "/usr/lib/node_modules/openclaw/skills",
            ]
        )
        XCTAssertFalse(ToolSource.npmGlobalSkillRoots.contains { $0.contains("/opt/homebrew") })
        XCTAssertFalse(ToolSource.npmGlobalSkillRoots.contains { $0.contains("/Applications") })
    }

    func testCliSearchPathsReplaceHomebrewWithDebianLocations() {
        let home = URL(fileURLWithPath: "/tmp/opencode/t07-home", isDirectory: true)

        XCTAssertEqual(
            ToolSource.cliSearchPaths(homeDirectory: home),
            [
                "/tmp/opencode/t07-home/.local/bin",
                "/usr/local/bin",
                "/usr/bin",
            ]
        )
    }

    func testGeneratedToolPathsNeverReferenceMacLocations() {
        let home = URL(fileURLWithPath: "/tmp/opencode/t07-home", isDirectory: true)
        let config = URL(fileURLWithPath: "/tmp/opencode/t07-config", isDirectory: true)

        for tool in ToolSource.allCases {
            let paths = tool.globalPaths(homeDirectory: home, configHomeDirectory: config)
                + tool.globalAgentPaths(homeDirectory: home)
                + tool.globalRulePaths(homeDirectory: home)
            for path in paths {
                XCTAssertFalse(path.contains("/opt/homebrew"), "\(tool.rawValue): \(path)")
                XCTAssertFalse(path.contains("/Applications"), "\(tool.rawValue): \(path)")
            }
        }
    }

    // MARK: - Installation detection

    func testFixtureHomeCountsToolDirectoriesAsInstalled() {
        let home = StoreTestSupport.fixtureHome

        for tool in [ToolSource.claude, .cursor, .codex, .amp, .opencode] {
            XCTAssertTrue(
                tool.isInstalled(
                    homeDirectory: home,
                    configHomeDirectory: home.appendingPathComponent(".config"),
                    cliSearchPaths: []
                ),
                "\(tool.rawValue) should be detected from its fixture skill directory"
            )
        }
    }

    func testEmptyHomeIsNotInstalledWithoutCLIBinaries() throws {
        let home = try XCTUnwrap(scratch)
        let config = home.appendingPathComponent(".config", isDirectory: true)

        for tool in [
            ToolSource.claude, .cursor, .codex, .amp, .opencode, .openclaw,
            .hermes, .copilot, .agents, .antigravity, .pi, .augment, .windsurf,
            .claudeDesktop,
        ] {
            XCTAssertFalse(
                tool.isInstalled(
                    homeDirectory: home,
                    configHomeDirectory: config,
                    cliSearchPaths: []
                ),
                "\(tool.rawValue) must not be installed in an empty home"
            )
        }

        // Frozen parity: Aider has no marker file and `custom` is an internal bucket.
        XCTAssertTrue(ToolSource.aider.isInstalled(homeDirectory: home, configHomeDirectory: config, cliSearchPaths: []))
        XCTAssertTrue(ToolSource.custom.isInstalled(homeDirectory: home, configHomeDirectory: config, cliSearchPaths: []))
    }

    func testClaudeDesktopUsesConfigFileInsteadOfAppBundle() throws {
        let home = try XCTUnwrap(scratch)
        let config = home.appendingPathComponent(".config", isDirectory: true)
        let configFile = config.appendingPathComponent("Claude/claude_desktop_config.json")
        try FileManager.default.createDirectory(
            at: configFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: configFile)

        XCTAssertTrue(
            ToolSource.claudeDesktop.isInstalled(
                homeDirectory: home,
                configHomeDirectory: config,
                cliSearchPaths: []
            )
        )
    }

    // MARK: - CLI resolution

    func testCliBinaryURLProbesLocalBinFirst() throws {
        let home = try XCTUnwrap(scratch)
        let binary = home.appendingPathComponent(".local/bin/chopscore-t07-probe")
        try FileManager.default.createDirectory(
            at: binary.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

        let resolved = ToolSource.cliBinaryURL("chopscore-t07-probe", homeDirectory: home)

        XCTAssertEqual(resolved?.path, binary.path)
    }

    func testCliBinaryURLProbesNewestNvmVersionFirst() throws {
        let home = try XCTUnwrap(scratch)
        let nodeRoot = home.appendingPathComponent(".nvm/versions/node")
        for version in ["v18.0.0", "v20.0.0"] {
            let binary = nodeRoot.appendingPathComponent("\(version)/bin/chopscore-t07-nvm")
            try FileManager.default.createDirectory(
                at: binary.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binary)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        }

        let resolved = ToolSource.cliBinaryURL("chopscore-t07-nvm", homeDirectory: home)

        XCTAssertEqual(resolved?.path, nodeRoot.appendingPathComponent("v20.0.0/bin/chopscore-t07-nvm").path)
    }
}
