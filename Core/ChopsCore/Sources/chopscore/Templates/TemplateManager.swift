import Foundation

/// Port of the frozen macOS `WizardTemplateType` (`Chops/Models/WizardTemplateType.swift`).
public enum WizardTemplateType: String, Codable, CaseIterable, Sendable {
    case skill
    case agent
    case rule
}

/// Portable port of the frozen macOS `TemplateManager`
/// (`Chops/Services/TemplateManager.swift`) plus the template boilerplate that the
/// macOS `NewSkillSheet` generates (`generateBoilerplate(name:skillID:tool:)`).
///
/// Prompt text and boilerplate strings are copied byte-for-byte; the tests compare them
/// against the macOS literals so the Linux side can never drift. The macOS original is
/// an `@MainActor` singleton because it runs in the UI process; here it is a plain
/// `Sendable` value used by `chopsd` and tests, with `shared` kept for call-site parity.
public struct TemplateManager: Sendable {
    public static let shared = TemplateManager()

    public init() {}

    /// Build a context-aware system prompt for a given template type.
    /// Substitutes `{{skill_name}}`, `{{skill_description}}`, `{{file_path}}`,
    /// `{{frontmatter}}`, and `{{kind}}` from the supplied skill context.
    public func systemPrompt(
        for type: WizardTemplateType,
        skillName: String,
        skillDescription: String,
        filePath: String,
        frontmatter: [String: String]
    ) -> String {
        let base = Self.systemPromptContent(for: type)
        let frontmatterText = frontmatter.isEmpty
            ? "(none)"
            : frontmatter.sorted(by: { $0.key < $1.key })
                .map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        return base
            .replacingOccurrences(of: "{{skill_name}}", with: skillName.isEmpty ? "(unnamed)" : skillName)
            .replacingOccurrences(of: "{{skill_description}}", with: skillDescription.isEmpty ? "(no description)" : skillDescription)
            .replacingOccurrences(of: "{{file_path}}", with: filePath)
            .replacingOccurrences(of: "{{frontmatter}}", with: frontmatterText)
            .replacingOccurrences(of: "{{kind}}", with: type.rawValue)
    }

    static func systemPromptContent(for type: WizardTemplateType) -> String {
        switch type {
        case .skill: Self.defaultSkillSystemPrompt
        case .agent: Self.defaultAgentSystemPrompt
        case .rule: Self.defaultRuleSystemPrompt
        }
    }

    // MARK: - New-file boilerplate (macOS `NewSkillSheet.generateBoilerplate`)

    /// Boilerplate written when the user creates a new skill/agent/rule.
    ///
    /// `name` is the display name typed by the user; `skillID` is the sanitized
    /// lowercase identifier used in frontmatter. Claude, Cursor and Global (`agents`)
    /// skills get the extra `## When to Use` section; every other tool gets the short
    /// form — exactly as the macOS sheet does.
    public static func boilerplate(
        kind: WizardTemplateType,
        name: String,
        skillID: String,
        tool: ToolSource
    ) -> String {
        switch kind {
        case .agent:
            return """
            ---
            name: \(skillID)
            description: \(name)
            ---

            # \(name)

            ## Instructions

            Add your agent instructions here.
            """
        case .rule:
            return """
            # \(name)

            Add your rule content here.
            """
        case .skill:
            switch tool {
            case .claude, .cursor, .agents:
                return """
                ---
                name: \(skillID)
                description: \(name)
                ---

                # \(name)

                ## When to Use

                - Describe when this skill should be activated

                ## Instructions

                Add your skill instructions here.
                """
            default:
                return """
                ---
                name: \(skillID)
                description: \(name)
                ---

                # \(name)

                ## Instructions

                Add your skill instructions here.
                """
            }
        }
    }

    // MARK: - Frozen macOS prompt text

    private static let defaultSkillSystemPrompt = """
    You are an expert in writing skills for AI coding assistants.

    ## File you're editing
    - Name: {{skill_name}}
    - Description: {{skill_description}}
    - Path: {{file_path}}

    ## Your task
    The user will give you their request along with the current file contents. Apply the request **minimally** — preserve every unchanged line exactly, including whitespace, blank lines, and wording. Do not refactor or "improve" anything the user didn't ask about.

    ## Reply format (STRICT)
    Reply with two things in this exact order:
    1. ONE OR TWO SENTENCES summarizing what changed (plain text, no preamble like "I'll update…").
    2. The COMPLETE updated file content inside a single fenced code block. Open with ``` on its own line, then the full file (including YAML frontmatter), then ``` on its own line.

    If the user is asking a question rather than requesting an edit, omit the code fence and just answer in prose.
    """

    private static let defaultAgentSystemPrompt = """
    You are an expert in writing agent definitions for AI coding assistants.

    ## File you're editing
    - Name: {{skill_name}}
    - Description: {{skill_description}}
    - Path: {{file_path}}

    ## Your task
    The user will give you their request along with the current file contents. Apply the request **minimally** — preserve every unchanged line exactly, including whitespace, blank lines, and wording. Do not refactor or "improve" anything the user didn't ask about.

    ## Reply format (STRICT)
    Reply with two things in this exact order:
    1. ONE OR TWO SENTENCES summarizing what changed (plain text, no preamble).
    2. The COMPLETE updated file content inside a single fenced code block. Open with ``` on its own line, then the full file (including YAML frontmatter), then ``` on its own line.

    If the user is asking a question rather than requesting an edit, omit the code fence and just answer in prose.
    """

    private static let defaultRuleSystemPrompt = """
    You are an expert in writing rules for AI coding assistants.

    ## File you're editing
    - Name: {{skill_name}}
    - Description: {{skill_description}}
    - Path: {{file_path}}

    ## Your task
    The user will give you their request along with the current file contents. Apply the request **minimally** — preserve every unchanged line exactly, including whitespace, blank lines, and wording. Do not refactor or "improve" anything the user didn't ask about.

    ## Reply format (STRICT)
    Reply with two things in this exact order:
    1. ONE OR TWO SENTENCES summarizing what changed (plain text, no preamble).
    2. The COMPLETE updated file content inside a single fenced code block. Open with ``` on its own line, then the full file (including YAML frontmatter), then ``` on its own line.

    If the user is asking a question rather than requesting an edit, omit the code fence and just answer in prose.
    """
}
