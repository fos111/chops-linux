import Foundation
import XCTest

@testable import chopscore

/// Scanner tests for the Linux port (plan T07).
///
/// Every test copies `linux/fixtures/home` into a fresh temporary directory and points
/// `SkillScanner` at that copy explicitly. The repository fixture is never modified and
/// the real `$HOME` is never scanned or written.
final class SkillScannerTests: XCTestCase {
    private var scratch: URL!
    private var home: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = try StoreTestSupport.makeTemporaryDirectory(prefix: "chopscore-scanner")
        home = try StoreTestSupport.copyFixtureHome(into: scratch)
    }

    override func tearDownWithError() throws {
        if let scratch {
            try? FileManager.default.removeItem(at: scratch)
        }
        scratch = nil
        home = nil
        try super.tearDownWithError()
    }

    private var scanner: SkillScanner {
        SkillScanner(homeDirectory: home, environment: [:])
    }

    private func relative(_ path: String) -> String {
        let prefix = home.standardizedFileURL.path + "/"
        guard path.hasPrefix(prefix) else {
            XCTFail("path \(path) is outside the injected fixture home \(home.path)")
            return path
        }
        return String(path.dropFirst(prefix.count))
    }

    // MARK: - Exact fixture inventory (plan T07 QA)

    func testFixtureHomeScanYieldsExactInventory() throws {
        let report = scanner.scanAll()
        let rows = report.skills

        print("== T07 scan inventory (tmp copy of linux/fixtures/home) ==")
        print(inventoryHeader)
        for row in rows {
            print(inventoryLine(for: row))
        }
        print("-- tolerated-unparsable --")
        for path in report.unparsablePaths {
            print(relative(path))
        }

        XCTAssertEqual(rows.count, 8, "6 skills + 1 rule + 1 agent; z-bad is tolerated, not a row")
        XCTAssertEqual(rows.filter { $0.kind == .skill }.count, 6)
        XCTAssertEqual(rows.filter { $0.kind == .agent }.count, 1)
        XCTAssertEqual(rows.filter { $0.kind == .rule }.count, 1)
        XCTAssertEqual(Set(rows.map(\.resolvedPath)).count, rows.count, "resolved paths must be unique")

        XCTAssertEqual(
            rows.filter { $0.kind == .skill }.map(\.name).sorted(),
            ["a-one", "b-two", "c-three", "m-six", "o-five", "x-eight"]
        )
        XCTAssertEqual(rows.filter { $0.kind == .rule }.map(\.name), ["rule-one"])
        XCTAssertEqual(rows.filter { $0.kind == .agent }.map(\.name), ["reviewer"])

        XCTAssertEqual(report.unparsablePaths.map(relative), [".claude/skills/z-bad.md"])
        XCTAssertFalse(rows.contains { $0.name == "z-bad" }, "malformed fixture must not become a skill row")
        XCTAssertFalse(rows.contains { $0.toolSources.isEmpty })

        try assertExpectedLocation(
            rows,
            name: "a-one",
            tool: .claude,
            kind: .skill,
            path: ".claude/skills/a-one.md",
            installedPaths: [".claude/skills/a-one.md", ".claude/skills/dup-a-md"]
        )
        try assertExpectedLocation(
            rows,
            name: "b-two",
            tool: .claude,
            kind: .skill,
            path: ".claude/skills/b-two.md"
        )
        try assertExpectedLocation(
            rows,
            name: "c-three",
            tool: .codex,
            kind: .skill,
            path: ".codex/skills/c-three.md"
        )
        try assertExpectedLocation(
            rows,
            name: "m-six",
            tool: .amp,
            kind: .skill,
            path: ".config/amp/skills/m-six.md"
        )
        try assertExpectedLocation(
            rows,
            name: "o-five",
            tool: .opencode,
            kind: .skill,
            path: ".config/opencode/skills/o-five.md"
        )
        try assertExpectedLocation(
            rows,
            name: "x-eight",
            tool: .claude,
            kind: .skill,
            path: ".claude/skills/sub/x-eight.md"
        )
        try assertExpectedLocation(
            rows,
            name: "reviewer",
            tool: .claude,
            kind: .agent,
            path: ".claude/agents/reviewer.md"
        )
        try assertExpectedLocation(
            rows,
            name: "rule-one",
            tool: .cursor,
            kind: .rule,
            path: ".cursor/rules/rule-one.mdc"
        )
    }

    // MARK: - Symlink identity

    func testDuplicateSymlinkAppearsOnceWithBothInstalledPaths() throws {
        let report = scanner.scanAll()

        let duplicates = report.skills.filter { $0.name == "a-one" }
        XCTAssertEqual(duplicates.count, 1, "a-one.md + dup-a-md must collapse into one row")
        XCTAssertFalse(report.skills.contains { $0.name == "dup-a-md" })

        let aOne = try XCTUnwrap(duplicates.first)
        XCTAssertEqual(relative(aOne.resolvedPath), ".claude/skills/a-one.md")
        XCTAssertEqual(relative(aOne.filePath), ".claude/skills/a-one.md")
        XCTAssertEqual(
            aOne.installedPaths.map(relative),
            [".claude/skills/a-one.md", ".claude/skills/dup-a-md"]
        )
        XCTAssertEqual(aOne.toolSources, [.claude])
        XCTAssertEqual(aOne.toolSource, .claude)
        XCTAssertEqual(aOne.frontmatter["name"], "a-one")
        XCTAssertEqual(aOne.skillDescription, "skill a")
    }

    func testResolvedIdentityAttributesOneRowToMultipleTools() throws {
        // Same physical file reachable from Codex as well as Claude: the dedup identity
        // is the resolved path, so attribution must include both tools on one row.
        let codexSkills = home.appendingPathComponent(".codex/skills", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            atPath: codexSkills.appendingPathComponent("dup-a-md").path,
            withDestinationPath: "../../.claude/skills/a-one.md"
        )

        let report = scanner.scanAll()
        let resolvedAOne = home.appendingPathComponent(".claude/skills/a-one.md").path
        let aOneRows = report.skills.filter { $0.resolvedPath == resolvedAOne }

        XCTAssertEqual(aOneRows.count, 1, "resolved-symlink identity must appear exactly once")
        let aOne = try XCTUnwrap(aOneRows.first)
        XCTAssertEqual(aOne.toolSources, [.claude, .codex])
        XCTAssertEqual(
            aOne.installedPaths.map(relative),
            [
                ".claude/skills/a-one.md",
                ".claude/skills/dup-a-md",
                ".codex/skills/dup-a-md",
            ]
        )
        XCTAssertEqual(report.skills.count, 8, "the extra symlink must not add a row")
    }

    // MARK: - Custom scan roots

    func testCustomScanRootFindsProjectSkillsWithoutDuplicatingGlobalOnes() throws {
        let customRoot = try XCTUnwrap(scratch)
            .appendingPathComponent("custom-root", isDirectory: true)
        let project = customRoot.appendingPathComponent("project", isDirectory: true)
        let skills = project.appendingPathComponent(".claude/skills", isDirectory: true)
        try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)
        let file = skills.appendingPathComponent("custom-one.md")
        try """
        ---
        name: custom-one
        description: project local
        ---

        # custom-one
        """.write(to: file, atomically: true, encoding: .utf8)

        let report = scanner.scanAll(customPaths: [customRoot.path])
        let customRows = report.skills.filter { $0.name == "custom-one" }

        XCTAssertEqual(customRows.count, 1)
        let custom = try XCTUnwrap(customRows.first)
        XCTAssertEqual(custom.toolSources, [.claude])
        XCTAssertFalse(custom.isGlobal)
        XCTAssertEqual(custom.filePath, file.path)
        XCTAssertEqual(report.skills.count, 9)
    }

    // MARK: - Helpers

    private func assertExpectedLocation(
        _ rows: [ScannedSkill],
        name: String,
        tool: ToolSource,
        kind: ItemKind,
        path: String,
        installedPaths: [String]? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let row = try XCTUnwrap(rows.first { $0.name == name }, "missing \(name)", file: file, line: line)
        XCTAssertEqual(row.kind, kind, name, file: file, line: line)
        XCTAssertEqual(row.toolSource, tool, name, file: file, line: line)
        XCTAssertEqual(row.toolSources, [tool], name, file: file, line: line)
        XCTAssertEqual(relative(row.resolvedPath), path, name, file: file, line: line)
        XCTAssertEqual(row.installedPaths.map(relative), installedPaths ?? [path], name, file: file, line: line)
    }

    private var inventoryHeader: String {
        [
            ParserFixtureSupport.pad("kind", to: 6),
            ParserFixtureSupport.pad("name", to: 12),
            ParserFixtureSupport.pad("tools", to: 16),
            ParserFixtureSupport.pad("path", to: 44),
            "installed paths",
        ].joined(separator: " | ")
    }

    private func inventoryLine(for row: ScannedSkill) -> String {
        [
            ParserFixtureSupport.pad(row.kind.rawValue, to: 6),
            ParserFixtureSupport.pad(row.name, to: 12),
            ParserFixtureSupport.pad(row.toolSources.map(\.rawValue).joined(separator: ","), to: 16),
            ParserFixtureSupport.pad(relative(row.filePath), to: 44),
            row.installedPaths.map(relative).joined(separator: ", "),
        ].joined(separator: " | ")
    }
}
