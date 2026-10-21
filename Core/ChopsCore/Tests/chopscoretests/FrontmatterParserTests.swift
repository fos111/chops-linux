import Foundation
import XCTest

@testable import chopscore

/// Port-parity tests for the frozen `Chops/Utilities/FrontmatterParser.swift`.
final class FrontmatterParserTests: XCTestCase {
    // MARK: - Standard documents

    func testParsesFixtureSkillFrontmatter() throws {
        let url = ParserFixtureSupport.url(for: ".claude/skills/a-one.md")
        let text = try String(contentsOf: url, encoding: .utf8)

        let parsed = FrontmatterParser.parse(text)

        XCTAssertEqual(parsed.frontmatter, ["name": "a-one", "description": "skill a"])
        XCTAssertEqual(parsed.name, "a-one")
        XCTAssertEqual(parsed.description, "skill a")
        XCTAssertTrue(parsed.hasName)
        XCTAssertTrue(parsed.content.hasPrefix("# a-one"))
        XCTAssertTrue(parsed.content.contains("Fixture skill one"))
        XCTAssertFalse(parsed.content.hasPrefix("---"))
    }

    func testParsesValueContainingColon() {
        let parsed = FrontmatterParser.parse("---\ndescription: use: this exact text\n---\nbody")

        XCTAssertEqual(parsed.frontmatter["description"], "use: this exact text")
        XCTAssertEqual(parsed.description, "use: this exact text")
        XCTAssertEqual(parsed.content, "body")
    }

    func testTrimsKeyAndValueWhitespace() {
        let parsed = FrontmatterParser.parse("---\n   name   :   spaced name   \n---\n")

        XCTAssertEqual(parsed.frontmatter["name"], "spaced name")
        XCTAssertEqual(parsed.name, "spaced name")
    }

    func testIgnoresLinesWithoutColonAndEmptyKeys() {
        let parsed = FrontmatterParser.parse("---\nplain text\n: no key\nname: kept\n---\nbody")

        XCTAssertEqual(parsed.frontmatter, ["name": "kept"])
    }

    func testDuplicateKeysKeepLastValue() {
        let parsed = FrontmatterParser.parse("---\nname: first\nname: second\n---\n")

        XCTAssertEqual(parsed.frontmatter["name"], "second")
        XCTAssertEqual(parsed.name, "second")
    }

    func testContentIsTrimmedOfWhitespaceAndNewlines() {
        let parsed = FrontmatterParser.parse("---\nname: x\n---\n\n\n  # body  \n\n")

        XCTAssertEqual(parsed.content, "# body")
    }

    func testEmptyContentAfterClosingDelimiter() {
        let parsed = FrontmatterParser.parse("---\nname: x\n---")

        XCTAssertEqual(parsed.name, "x")
        XCTAssertEqual(parsed.content, "")
    }

    // MARK: - No frontmatter

    func testDelimiterMustBeOnFirstLine() {
        let text = "\n---\nname: x\n---\nbody"

        let parsed = FrontmatterParser.parse(text)

        XCTAssertTrue(parsed.frontmatter.isEmpty)
        XCTAssertEqual(parsed.name, "")
        // The no-frontmatter path returns the original text untouched (no trimming).
        XCTAssertEqual(parsed.content, text)
    }

    func testUnterminatedFrontmatterReturnsWholeText() {
        let text = "---\nname: x\nno closing delimiter"

        let parsed = FrontmatterParser.parse(text)

        XCTAssertTrue(parsed.frontmatter.isEmpty)
        XCTAssertEqual(parsed.name, "")
        XCTAssertEqual(parsed.content, text)
    }

    func testPlainTextWithoutFrontmatterIsReturnedUntrimmed() {
        let text = "  just a document  \n"

        let parsed = FrontmatterParser.parse(text)

        XCTAssertEqual(parsed.frontmatter, [:])
        XCTAssertEqual(parsed.content, text)
        XCTAssertEqual(parsed.description, "")
    }

    func testDelimiterMayCarrySurroundingSpaces() {
        let parsed = FrontmatterParser.parse("  ---  \nname: x\n  ---  \nbody")

        XCTAssertEqual(parsed.name, "x")
        XCTAssertEqual(parsed.content, "body")
    }

    // MARK: - Malformed fixture (z-bad)

    func testMalformedEmptyNameValueIsToleratedWithoutCrash() throws {
        let url = ParserFixtureSupport.url(for: ".claude/skills/z-bad.md")
        let text = try String(contentsOf: url, encoding: .utf8)

        let parsed = FrontmatterParser.parse(text)

        XCTAssertEqual(parsed.frontmatter["name"], "")
        XCTAssertEqual(parsed.name, "")
        XCTAssertFalse(parsed.hasName)
        XCTAssertEqual(parsed.description, "malformed on purpose (name has no value)")
        // The body is still available; only the identity is missing.
        XCTAssertTrue(parsed.content.hasPrefix("# z-bad"))
    }

    // MARK: - Symlink duplicate

    func testSymlinkDuplicateYieldsIdenticalParsedMetadata() throws {
        let original = ParserFixtureSupport.url(for: ".claude/skills/a-one.md")
        let duplicate = ParserFixtureSupport.url(for: ".claude/skills/dup-a-md")

        let attributes = try FileManager.default.attributesOfItem(atPath: duplicate.path)
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeSymbolicLink)

        let originalText = try String(contentsOf: original, encoding: .utf8)
        let duplicateText = try String(contentsOf: duplicate, encoding: .utf8)

        let originalParsed = FrontmatterParser.parse(originalText)
        let duplicateParsed = FrontmatterParser.parse(duplicateText)

        XCTAssertEqual(originalParsed, duplicateParsed)
        XCTAssertEqual(
            duplicate.resolvingSymlinksInPath().path,
            original.resolvingSymlinksInPath().path,
            "Symlink duplicate must resolve to the canonical fixture path"
        )
    }
}
