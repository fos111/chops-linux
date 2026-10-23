import Foundation
import XCTest

@testable import chopscore

/// Port-parity tests for the frozen `Chops/Services/SkillParser.swift` and
/// `Chops/Utilities/MDCParser.swift`, driven by the `linux/fixtures/home` suite.
final class SkillParserTests: XCTestCase {
    private var scratchDirectory: URL?

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratchDirectory = try StoreTestSupport.makeTemporaryDirectory(prefix: "chopscore-parser")
    }

    override func tearDownWithError() throws {
        if let scratchDirectory {
            try? FileManager.default.removeItem(at: scratchDirectory)
        }
        scratchDirectory = nil
        try super.tearDownWithError()
    }

    // MARK: - Per-fixture parse table (plan T06 QA)

    func testEveryFixtureParsesAsExpectedAndPrintsParseTable() {
        var rows: [String] = []
        rows.append(
            [
                ParserFixtureSupport.pad("fixture", to: 42),
                ParserFixtureSupport.pad("tool", to: 14),
                ParserFixtureSupport.pad("ext", to: 6),
                ParserFixtureSupport.pad("parser branch", to: 24),
                ParserFixtureSupport.pad("name", to: 12),
                ParserFixtureSupport.pad("state", to: 10),
                "symlink identity",
            ].joined(separator: " | ")
        )
        rows.append(String(repeating: "-", count: 42 + 14 + 6 + 24 + 12 + 10 + 20 + 18))

        for fixture in ParserFixtureSupport.cases {
            let url = ParserFixtureSupport.url(for: fixture.relativePath)

            guard let parsed = SkillParser.parse(fileURL: url, toolSource: fixture.tool) else {
                XCTFail("Fixture \(fixture.relativePath) did not parse (nil)")
                continue
            }

            XCTAssertEqual(parsed.name, fixture.expectedName, fixture.relativePath)
            XCTAssertEqual(parsed.description, fixture.expectedDescription, fixture.relativePath)
            XCTAssertEqual(!parsed.hasName, fixture.expectsUnparsed, fixture.relativePath)
            XCTAssertEqual(parsed.frontmatter["name"], fixture.expectedName, fixture.relativePath)
            XCTAssertFalse(parsed.content.isEmpty, "\(fixture.relativePath) content should not be empty")

            let branch: String
            switch fixture.tool.parseStrategy {
            case .frontmatterOnly:
                branch = url.pathExtension == "mdc" ? "MDCParser->Frontmatter" : "Frontmatter"
            case .frontmatterThenHeading:
                branch = "Frontmatter->Heading"
            }

            let symlinkIdentity: String
            if fixture.isSymlinkDuplicate {
                symlinkIdentity = "-> " + url.resolvingSymlinksInPath().lastPathComponent
            } else {
                symlinkIdentity = "-"
            }

            rows.append(
                [
                    ParserFixtureSupport.pad(fixture.relativePath, to: 42),
                    ParserFixtureSupport.pad(fixture.tool.rawValue, to: 14),
                    ParserFixtureSupport.pad(url.pathExtension.isEmpty ? "(none)" : url.pathExtension, to: 6),
                    ParserFixtureSupport.pad(branch, to: 24),
                    ParserFixtureSupport.pad(fixture.expectedName.isEmpty ? "(empty)" : fixture.expectedName, to: 12),
                    ParserFixtureSupport.pad(ParserFixtureSupport.parseState(parsed), to: 10),
                    symlinkIdentity,
                ].joined(separator: " | ")
            )
        }

        print("== T06 fixture parse table (linux/fixtures/home) ==")
        for row in rows { print(row) }

        XCTAssertEqual(ParserFixtureSupport.cases.count, 10)
    }

    func testFixtureInventoryIsComplete() throws {
        let expectedPaths = Set(ParserFixtureSupport.cases.map(\.relativePath))
        let home = ParserFixtureSupport.fixtureHome

        var found: Set<String> = []
        let enumerator = FileManager.default.enumerator(atPath: home.path)
        while let relative = enumerator?.nextObject() as? String {
            let fullPath = home.appendingPathComponent(relative).path
            var isDirectory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory)
            guard !isDirectory.boolValue else { continue }
            found.insert(relative)
        }

        XCTAssertEqual(found, expectedPaths)
    }

    // MARK: - Cursor .mdc and agents

    func testCursorMDCRuleParsesThroughMDCParser() throws {
        let url = ParserFixtureSupport.url(for: ".cursor/rules/rule-one.mdc")
        XCTAssertEqual(url.pathExtension, "mdc")

        let text = try String(contentsOf: url, encoding: .utf8)
        let viaSkillParser = try XCTUnwrap(SkillParser.parse(fileURL: url, toolSource: .cursor))
        let viaMDCParser = MDCParser.parse(text)

        XCTAssertEqual(viaSkillParser, viaMDCParser)
        XCTAssertEqual(viaSkillParser.name, "rule-one")
        XCTAssertEqual(viaSkillParser.description, "cursor rule one")
        XCTAssertTrue(viaSkillParser.content.hasPrefix("# rule-one"))
    }

    func testAgentFixtureParsesThroughFrontmatter() throws {
        let url = ParserFixtureSupport.url(for: ".claude/agents/reviewer.md")

        let parsed = try XCTUnwrap(SkillParser.parse(fileURL: url, toolSource: .claude))

        XCTAssertEqual(parsed.frontmatter, ["name": "reviewer", "description": "review agent"])
        XCTAssertEqual(parsed.name, "reviewer")
        XCTAssertEqual(parsed.description, "review agent")
        XCTAssertTrue(parsed.content.hasPrefix("# reviewer"))
    }

    // MARK: - Per-tool branching

    func testCodexUsesHeadingFallbackWithoutFrontmatter() {
        let parsed = SkillParser.parse(text: "# Heading Skill\n\nbody\n", toolSource: .codex, pathExtension: "md")

        XCTAssertEqual(parsed.frontmatter, [:])
        XCTAssertEqual(parsed.name, "Heading Skill")
        XCTAssertEqual(parsed.description, "")
        XCTAssertEqual(parsed.content, "# Heading Skill\n\nbody\n")
    }

    func testFrontmatterNameWinsOverHeading() {
        let text = "---\nname: from-frontmatter\n---\n# Heading\n"

        let parsed = SkillParser.parse(text: text, toolSource: .codex, pathExtension: "md")

        XCTAssertEqual(parsed.name, "from-frontmatter")
        XCTAssertEqual(parsed.frontmatter["name"], "from-frontmatter")
    }

    func testClaudeDoesNotUseHeadingFallback() {
        let text = "# Heading Only\n\nbody"

        let parsed = SkillParser.parse(text: text, toolSource: .claude, pathExtension: "md")

        XCTAssertEqual(parsed.name, "")
        XCTAssertFalse(parsed.hasName)
        XCTAssertEqual(parsed.content, text)
    }

    func testClaudeDesktopSharesClaudeFrontmatterOnlyBehavior() {
        let text = "# Heading Only\n\nbody"

        let parsed = SkillParser.parse(text: text, toolSource: .claudeDesktop, pathExtension: "md")

        XCTAssertEqual(parsed.name, "")
    }

    func testHeadingRequiresHashFollowedBySpace() {
        let parsed = SkillParser.parse(text: "#NoSpace\n#  Padded  \n", toolSource: .agents, pathExtension: "md")

        XCTAssertEqual(parsed.name, "Padded")
    }

    func testCodexWithoutFrontmatterOrHeadingHasEmptyName() {
        let parsed = SkillParser.parse(text: "no heading here", toolSource: .codex, pathExtension: "md")

        XCTAssertEqual(parsed.name, "")
        XCTAssertEqual(parsed.content, "no heading here")
    }

    func testExtensionComparisonIsExact() {
        // macOS compares `pathExtension == "mdc"` without lowercasing. Both branches
        // return frontmatter for a cursor file, so the observable contract is identity.
        let text = "---\nname: upper\n---\n"

        let lower = SkillParser.parse(text: text, toolSource: .cursor, pathExtension: "mdc")
        let upper = SkillParser.parse(text: text, toolSource: .cursor, pathExtension: "MDC")

        XCTAssertEqual(lower, upper)
        XCTAssertEqual(upper.name, "upper")
    }

    // MARK: - Read failures

    func testMissingFileReturnsNil() {
        let url = ParserFixtureSupport.fixtureHome.appendingPathComponent(".claude/skills/does-not-exist.md")

        XCTAssertNil(SkillParser.parse(fileURL: url, toolSource: .claude))
    }

    func testInvalidUTF8ReturnsNilWithoutCrash() throws {
        let scratch = try XCTUnwrap(scratchDirectory)
        let url = scratch.appendingPathComponent("invalid.md")
        try Data([0xFF, 0xFE, 0x00, 0xD8]).write(to: url)

        XCTAssertNil(SkillParser.parse(fileURL: url, toolSource: .claude))
    }
}
