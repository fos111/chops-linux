import Foundation

/// Portable port of the frozen macOS `SkillParser`
/// (`Chops/Services/SkillParser.swift`).
///
/// Duplicate-resolution, directory layout and metadata collection stay in the scanner
/// (plan T07); this type only turns file contents into a `ParsedSkill`, with the same
/// per-tool branching as macOS:
/// - Claude / Claude Desktop / Cursor: frontmatter only; `.mdc` goes through `MDCParser`.
/// - All other tools: frontmatter first, then an `# Heading` fallback when the
///   frontmatter produced no name.
public enum SkillParser {
    /// Parses already-read text. `pathExtension` is compared exactly like
    /// `URL.pathExtension` (no lowercasing), matching the frozen implementation.
    public static func parse(
        text: String,
        toolSource: ToolSource,
        pathExtension: String
    ) -> ParsedSkill {
        switch toolSource.parseStrategy {
        case .frontmatterOnly:
            if toolSource.routesMDCThroughMDCParser, pathExtension == "mdc" {
                return MDCParser.parse(text)
            }
            return FrontmatterParser.parse(text)
        case .frontmatterThenHeading:
            let parsed = FrontmatterParser.parse(text)
            if !parsed.name.isEmpty { return parsed }
            return parseHeadingFormat(text)
        }
    }

    /// Reads the file as UTF-8 and parses it. Returns `nil` when the file cannot be
    /// read/decoded, exactly like the macOS original (the scanner logs and skips it).
    public static func parse(fileURL: URL, toolSource: ToolSource) -> ParsedSkill? {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }
        return parse(text: content, toolSource: toolSource, pathExtension: fileURL.pathExtension)
    }

    /// Port of the frozen `parseHeadingFormat`: the first line that starts with `# `
    /// (exactly one space) supplies the name; content stays the full original text and
    /// `description` is empty.
    static func parseHeadingFormat(_ content: String) -> ParsedSkill {
        let lines = content.components(separatedBy: "\n")
        var name = ""

        for line in lines {
            if line.hasPrefix("# ") {
                name = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        return ParsedSkill(
            frontmatter: [:],
            content: content,
            name: name,
            description: ""
        )
    }
}
