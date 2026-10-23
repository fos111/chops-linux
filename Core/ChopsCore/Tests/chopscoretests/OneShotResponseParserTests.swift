import Foundation
import XCTest

@testable import chopscore

/// Parser tests for the one-shot reply formats (plan T08).
///
/// The expectations here mirror the frozen macOS `OneShotResponseParser` /
/// `OneShotPrompts` exactly; the transports share this parser for both Claude and Codex.
final class OneShotResponseParserTests: XCTestCase {

    // MARK: - Format 2: summary + fenced full file

    func testSummaryPlusFencedFullFileIsSplit() {
        let text = """
        Renamed the heading.

        ```markdown
        ---
        name: a-one
        ---

        # A One
        ```
        """
        let result = OneShotResponseParser.parse(text, originalContent: "---\nname: a-one\n---\n")
        XCTAssertEqual(result.summary, "Renamed the heading.")
        XCTAssertEqual(result.newContent, "---\nname: a-one\n---\n\n# A One\n")
    }

    func testFenceWithoutLanguageHintIsAccepted() {
        let text = "Summary.\n\n```\nbody\n```"
        let result = OneShotResponseParser.parse(text, originalContent: nil)
        XCTAssertEqual(result.summary, "Summary.")
        XCTAssertEqual(result.newContent, "body\n")
    }

    func testInnerFencedExampleSurvivesBecauseTheLastFenceCloses() {
        let text = """
        Added a code example.

        ```markdown
        # Title

        ```bash
        chops --help
        ```
        ```
        """
        let result = OneShotResponseParser.parse(text, originalContent: nil)
        XCTAssertEqual(result.summary, "Added a code example.")
        XCTAssertEqual(result.newContent, "# Title\n\n```bash\nchops --help\n```\n")
    }

    func testUnclosedFenceTakesEverythingAfterTheOpening() {
        let text = "Summary.\n\n```markdown\nunterminated body\n"
        let result = OneShotResponseParser.parse(text, originalContent: nil)
        XCTAssertEqual(result.summary, "Summary.")
        XCTAssertEqual(result.newContent, "unterminated body\n")
    }

    func testProseWithoutFenceReturnsTrimmedTextAsSummaryAndNoContent() {
        let result = OneShotResponseParser.parse("  Just an answer.  \n", originalContent: "orig")
        XCTAssertEqual(result.summary, "Just an answer.")
        XCTAssertNil(result.newContent)
    }

    // MARK: - Format 1: structured-edits JSON (tried first)

    func testStructuredEditsJSONAppliesToOriginalContent() throws {
        let text = """
        {"summary":"Tightened the intro.","edits":[{"find":"old line","replace":"new line"}]}
        """
        let result = OneShotResponseParser.parse(text, originalContent: "keep\nold line\nkeep\n")
        XCTAssertEqual(result.summary, "Tightened the intro.")
        XCTAssertEqual(result.newContent, "keep\nnew line\nkeep\n")
    }

    func testStructuredEditsJSONInsideFencesAppliesToOriginalContent() {
        let text = """
        ```json
        {"summary":"Two edits.","edits":[{"find":"A","replace":"B"},{"find":"C","replace":"D"}]}
        ```
        """
        let result = OneShotResponseParser.parse(text, originalContent: "A C")
        XCTAssertEqual(result.summary, "Two edits.")
        XCTAssertEqual(result.newContent, "B D")
    }

    func testStructuredEditsWithEmptyEditsHasNoContent() {
        let text = #"{"summary":"Just an answer.","edits":[]}"#
        let result = OneShotResponseParser.parse(text, originalContent: "orig")
        XCTAssertEqual(result.summary, "Just an answer.")
        XCTAssertNil(result.newContent)
    }

    func testStructuredEditsWithoutOriginalContentHasNoContent() {
        let text = #"{"summary":"Wants an edit.","edits":[{"find":"a","replace":"b"}]}"#
        let result = OneShotResponseParser.parse(text, originalContent: nil)
        XCTAssertEqual(result.summary, "Wants an edit.")
        XCTAssertNil(result.newContent)
    }

    func testStructuredEditsMissingFindKeepsSummaryAndDropsContent() {
        let text = #"{"summary":"Wants an edit.","edits":[{"find":"absent","replace":"b"}]}"#
        let result = OneShotResponseParser.parse(text, originalContent: "original")
        XCTAssertEqual(result.summary, "Wants an edit.")
        XCTAssertNil(result.newContent)
    }

    func testStructuredEditsNonUniqueFindKeepsSummaryAndDropsContent() {
        let text = #"{"summary":"Wants an edit.","edits":[{"find":"dup","replace":"b"}]}"#
        let result = OneShotResponseParser.parse(text, originalContent: "dup and dup")
        XCTAssertEqual(result.summary, "Wants an edit.")
        XCTAssertNil(result.newContent)
    }

    // MARK: - Prompt assembly

    func testDefaultSystemPromptNamesTheFile() {
        let prompt = OneShotPrompts.defaultSystemPrompt(filePath: "/home/user/.claude/skills/a-one.md")
        XCTAssertTrue(prompt.contains("You are helping the user edit a-one.md"))
        XCTAssertTrue(prompt.contains("Reply format"))

        let generic = OneShotPrompts.defaultSystemPrompt(filePath: nil)
        XCTAssertTrue(generic.contains("You are helping the user edit the file"))
    }

    func testUserMessageWrapsTheFileAndTheRequest() {
        let message = OneShotPrompts.userMessage(
            userRequest: "Rename the heading.",
            filePath: "/tmp/a-one.md",
            fileContent: "# A One"
        )
        XCTAssertEqual(message, """
        Current contents of a-one.md:
        ```
        # A One
        ```

        User's request:
        Rename the heading.
        """)
    }

    func testUserMessageWithoutFileIsRequestOnly() {
        let message = OneShotPrompts.userMessage(userRequest: "Hi", filePath: nil, fileContent: nil)
        XCTAssertEqual(message, "User's request:\nHi")
    }

    func testUserMessageMarksAnEmptyFile() {
        let message = OneShotPrompts.userMessage(userRequest: "Write it", filePath: "/tmp/new.md", fileContent: "")
        XCTAssertTrue(message.contains("(empty file)"))
    }
}
