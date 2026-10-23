import Foundation
import XCTest

@testable import chopscore

/// Byte-for-byte parity tests for the frozen `Chops/Services/TemplateManager.swift`
/// system prompts and the `NewSkillSheet.generateBoilerplate` template text.
final class TemplateManagerTests: XCTestCase {
    private let manager = TemplateManager()

    // MARK: - System prompts (macOS TemplateManager text)

    func testSkillSystemPromptMatchesMacOS() {
        let prompt = manager.systemPrompt(
            for: .skill,
            skillName: "a-one",
            skillDescription: "skill a",
            filePath: "/fixture/home/.claude/skills/a-one.md",
            frontmatter: ["name": "a-one", "description": "skill a"]
        )

        let expected = """
You are an expert in writing skills for AI coding assistants.

## File you're editing
- Name: a-one
- Description: skill a
- Path: /fixture/home/.claude/skills/a-one.md

## Your task
The user will give you their request along with the current file contents. Apply the request **minimally** — preserve every unchanged line exactly, including whitespace, blank lines, and wording. Do not refactor or "improve" anything the user didn't ask about.

## Reply format (STRICT)
Reply with two things in this exact order:
1. ONE OR TWO SENTENCES summarizing what changed (plain text, no preamble like "I'll update…").
2. The COMPLETE updated file content inside a single fenced code block. Open with ``` on its own line, then the full file (including YAML frontmatter), then ``` on its own line.

If the user is asking a question rather than requesting an edit, omit the code fence and just answer in prose.
"""

        XCTAssertEqual(prompt, expected)
    }

    func testAgentSystemPromptMatchesMacOS() {
        let prompt = manager.systemPrompt(
            for: .agent,
            skillName: "reviewer",
            skillDescription: "review agent",
            filePath: "/fixture/home/.claude/agents/reviewer.md",
            frontmatter: ["name": "reviewer", "description": "review agent"]
        )

        let expected = """
You are an expert in writing agent definitions for AI coding assistants.

## File you're editing
- Name: reviewer
- Description: review agent
- Path: /fixture/home/.claude/agents/reviewer.md

## Your task
The user will give you their request along with the current file contents. Apply the request **minimally** — preserve every unchanged line exactly, including whitespace, blank lines, and wording. Do not refactor or "improve" anything the user didn't ask about.

## Reply format (STRICT)
Reply with two things in this exact order:
1. ONE OR TWO SENTENCES summarizing what changed (plain text, no preamble).
2. The COMPLETE updated file content inside a single fenced code block. Open with ``` on its own line, then the full file (including YAML frontmatter), then ``` on its own line.

If the user is asking a question rather than requesting an edit, omit the code fence and just answer in prose.
"""

        XCTAssertEqual(prompt, expected)
    }

    func testRuleSystemPromptMatchesMacOS() {
        let prompt = manager.systemPrompt(
            for: .rule,
            skillName: "rule-one",
            skillDescription: "cursor rule one",
            filePath: "/fixture/home/.cursor/rules/rule-one.mdc",
            frontmatter: [:]
        )

        let expected = """
You are an expert in writing rules for AI coding assistants.

## File you're editing
- Name: rule-one
- Description: cursor rule one
- Path: /fixture/home/.cursor/rules/rule-one.mdc

## Your task
The user will give you their request along with the current file contents. Apply the request **minimally** — preserve every unchanged line exactly, including whitespace, blank lines, and wording. Do not refactor or "improve" anything the user didn't ask about.

## Reply format (STRICT)
Reply with two things in this exact order:
1. ONE OR TWO SENTENCES summarizing what changed (plain text, no preamble).
2. The COMPLETE updated file content inside a single fenced code block. Open with ``` on its own line, then the full file (including YAML frontmatter), then ``` on its own line.

If the user is asking a question rather than requesting an edit, omit the code fence and just answer in prose.
"""

        XCTAssertEqual(prompt, expected)
    }

    func testSystemPromptUsesMacOSDefaultPlaceholders() {
        for type in WizardTemplateType.allCases {
            let prompt = manager.systemPrompt(
                for: type,
                skillName: "",
                skillDescription: "",
                filePath: "/tmp/new.md",
                frontmatter: [:]
            )

            XCTAssertTrue(prompt.contains("- Name: (unnamed)"), type.rawValue)
            XCTAssertTrue(prompt.contains("- Description: (no description)"), type.rawValue)
            XCTAssertTrue(prompt.contains("- Path: /tmp/new.md"), type.rawValue)
            XCTAssertFalse(prompt.contains("{{"), "\(type.rawValue) left an unresolved placeholder")
        }
    }

    func testKindRawValuesMatchMacOSWizardTemplateType() {
        XCTAssertEqual(WizardTemplateType.skill.rawValue, "skill")
        XCTAssertEqual(WizardTemplateType.agent.rawValue, "agent")
        XCTAssertEqual(WizardTemplateType.rule.rawValue, "rule")
    }

    // MARK: - New-file boilerplate (macOS NewSkillSheet text)

    func testSkillBoilerplateForClaudeMatchesMacOS() {
        let expected = """
---
name: my-skill
description: My Skill
---

# My Skill

## When to Use

- Describe when this skill should be activated

## Instructions

Add your skill instructions here.
"""

        XCTAssertEqual(
            TemplateManager.boilerplate(kind: .skill, name: "My Skill", skillID: "my-skill", tool: .claude),
            expected
        )
        XCTAssertFalse(expected.hasSuffix("\n"))
    }

    func testSkillBoilerplateForCursorAndGlobalMatchesClaude() {
        let claude = TemplateManager.boilerplate(kind: .skill, name: "My Skill", skillID: "my-skill", tool: .claude)

        XCTAssertEqual(
            TemplateManager.boilerplate(kind: .skill, name: "My Skill", skillID: "my-skill", tool: .cursor),
            claude
        )
        XCTAssertEqual(
            TemplateManager.boilerplate(kind: .skill, name: "My Skill", skillID: "my-skill", tool: .agents),
            claude
        )
    }

    func testSkillBoilerplateForOtherToolsOmitsWhenToUse() {
        let expected = """
---
name: my-skill
description: My Skill
---

# My Skill

## Instructions

Add your skill instructions here.
"""

        for tool in [ToolSource.codex, .amp, .opencode, .pi, .antigravity] {
            XCTAssertEqual(
                TemplateManager.boilerplate(kind: .skill, name: "My Skill", skillID: "my-skill", tool: tool),
                expected,
                tool.rawValue
            )
        }
    }

    func testAgentBoilerplateMatchesMacOS() {
        let expected = """
---
name: review-agent
description: Review Agent
---

# Review Agent

## Instructions

Add your agent instructions here.
"""

        XCTAssertEqual(
            TemplateManager.boilerplate(kind: .agent, name: "Review Agent", skillID: "review-agent", tool: .claude),
            expected
        )
    }

    func testRuleBoilerplateMatchesMacOS() {
        let expected = """
# My Rule

Add your rule content here.
"""

        XCTAssertEqual(
            TemplateManager.boilerplate(kind: .rule, name: "My Rule", skillID: "my-rule", tool: .cursor),
            expected
        )
    }

    func testSkillBoilerplateRoundTripsThroughFrontmatterParser() {
        let boilerplate = TemplateManager.boilerplate(
            kind: .skill,
            name: "My Skill",
            skillID: "my-skill",
            tool: .claude
        )

        let parsed = FrontmatterParser.parse(boilerplate)

        XCTAssertEqual(parsed.frontmatter, ["name": "my-skill", "description": "My Skill"])
        XCTAssertEqual(parsed.name, "my-skill")
        XCTAssertEqual(parsed.description, "My Skill")
        XCTAssertTrue(parsed.content.hasPrefix("# My Skill"))
        XCTAssertTrue(parsed.content.contains("## When to Use"))
    }
}
