import Foundation

@testable import chopscore

/// One row of the plan T06 per-fixture parse table.
///
/// The table deliberately hard-codes the tool/kind each fixture belongs to: path tables
/// and installation detection are the scanner task (T07), so parsing tests supply the
/// tool source explicitly, exactly like `SkillParser.parse(fileURL:toolSource:)` requires.
struct FixtureParseCase {
    let relativePath: String
    let tool: ToolSource
    let kind: WizardTemplateType
    let expectedName: String
    let expectedDescription: String
    /// `z-bad.md` has `name:` with no value: macOS parsing yields an empty name and the
    /// file has no skill identity. Tests assert it is tolerated, never a crash.
    let expectsUnparsed: Bool
    /// `dup-a-md` is a symlink to `a-one.md`.
    let isSymlinkDuplicate: Bool
}

enum ParserFixtureSupport {
    static var fixtureHome: URL { StoreTestSupport.fixtureHome }

    static func url(for relativePath: String) -> URL {
        fixtureHome.appendingPathComponent(relativePath)
    }

    /// Every parse-relevant file in `linux/fixtures/home`, in stable path order.
    static let cases: [FixtureParseCase] = [
        FixtureParseCase(
            relativePath: ".claude/agents/reviewer.md",
            tool: .claude,
            kind: .agent,
            expectedName: "reviewer",
            expectedDescription: "review agent",
            expectsUnparsed: false,
            isSymlinkDuplicate: false
        ),
        FixtureParseCase(
            relativePath: ".claude/skills/a-one.md",
            tool: .claude,
            kind: .skill,
            expectedName: "a-one",
            expectedDescription: "skill a",
            expectsUnparsed: false,
            isSymlinkDuplicate: false
        ),
        FixtureParseCase(
            relativePath: ".claude/skills/b-two.md",
            tool: .claude,
            kind: .skill,
            expectedName: "b-two",
            expectedDescription: "skill b",
            expectsUnparsed: false,
            isSymlinkDuplicate: false
        ),
        FixtureParseCase(
            relativePath: ".claude/skills/dup-a-md",
            tool: .claude,
            kind: .skill,
            expectedName: "a-one",
            expectedDescription: "skill a",
            expectsUnparsed: false,
            isSymlinkDuplicate: true
        ),
        FixtureParseCase(
            relativePath: ".claude/skills/sub/x-eight.md",
            tool: .claude,
            kind: .skill,
            expectedName: "x-eight",
            expectedDescription: "skill x",
            expectsUnparsed: false,
            isSymlinkDuplicate: false
        ),
        FixtureParseCase(
            relativePath: ".claude/skills/z-bad.md",
            tool: .claude,
            kind: .skill,
            expectedName: "",
            expectedDescription: "malformed on purpose (name has no value)",
            expectsUnparsed: true,
            isSymlinkDuplicate: false
        ),
        FixtureParseCase(
            relativePath: ".codex/skills/c-three.md",
            tool: .codex,
            kind: .skill,
            expectedName: "c-three",
            expectedDescription: "skill c",
            expectsUnparsed: false,
            isSymlinkDuplicate: false
        ),
        FixtureParseCase(
            relativePath: ".config/amp/skills/m-six.md",
            tool: .amp,
            kind: .skill,
            expectedName: "m-six",
            expectedDescription: "skill m",
            expectsUnparsed: false,
            isSymlinkDuplicate: false
        ),
        FixtureParseCase(
            relativePath: ".config/opencode/skills/o-five.md",
            tool: .opencode,
            kind: .skill,
            expectedName: "o-five",
            expectedDescription: "skill o",
            expectsUnparsed: false,
            isSymlinkDuplicate: false
        ),
        FixtureParseCase(
            relativePath: ".cursor/rules/rule-one.mdc",
            tool: .cursor,
            kind: .rule,
            expectedName: "rule-one",
            expectedDescription: "cursor rule one",
            expectsUnparsed: false,
            isSymlinkDuplicate: false
        ),
    ]

    static func pad(_ value: String, to width: Int) -> String {
        let count = value.count
        guard count < width else { return value }
        return value + String(repeating: " ", count: width - count)
    }

    static func parseState(_ parsed: ParsedSkill) -> String {
        parsed.hasName ? "parsed" : "unparsed"
    }
}
