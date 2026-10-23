import Foundation

/// Parse result ported from the frozen macOS `ParsedSkill`
/// (`Chops/Utilities/FrontmatterParser.swift`).
public struct ParsedSkill: Equatable, Sendable {
    public var frontmatter: [String: String]
    public var content: String
    public var name: String
    public var description: String

    public init(
        frontmatter: [String: String],
        content: String,
        name: String,
        description: String
    ) {
        self.frontmatter = frontmatter
        self.content = content
        self.name = name
        self.description = description
    }

    /// True when the file yielded a usable skill name.
    ///
    /// The frozen macOS scanner falls back to the file/directory name when
    /// `parsed.name.isEmpty`; a malformed frontmatter block (for example the fixture
    /// `z-bad.md` whose `name:` has no value) therefore carries no skill identity of
    /// its own. Consumers that treat empty names as "unparsed" use this predicate
    /// instead of crashing or inventing a name at the parser layer.
    public var hasName: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Verbatim port of the frozen macOS `FrontmatterParser`
/// (`Chops/Utilities/FrontmatterParser.swift`).
///
/// Semantics kept exactly, including the quirks:
/// - The opening `---` is detected only on the first line (whitespace-trimmed).
/// - If there is no closing `---`, the whole text is returned untouched as `content`.
/// - Frontmatter lines are split on the **first** `:`, so values may contain colons.
/// - Keys and values are trimmed of `.whitespaces` only (not newlines).
/// - `content` after the closing delimiter is trimmed of `.whitespacesAndNewlines`.
/// - `name`/`description` are empty strings when absent.
public enum FrontmatterParser {
    public static func parse(_ text: String) -> ParsedSkill {
        let lines = text.components(separatedBy: "\n")

        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return ParsedSkill(frontmatter: [:], content: text, name: "", description: "")
        }

        var endIndex: Int?
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                endIndex = i
                break
            }
        }

        guard let end = endIndex else {
            return ParsedSkill(frontmatter: [:], content: text, name: "", description: "")
        }

        var frontmatter: [String: String] = [:]
        for i in 1..<end {
            let line = lines[i]
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    frontmatter[key] = value
                }
            }
        }

        let contentStartIndex = min(end + 1, lines.count)
        let contentLines = Array(lines[contentStartIndex...])
        let content = contentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedSkill(
            frontmatter: frontmatter,
            content: content,
            name: frontmatter["name"] ?? "",
            description: frontmatter["description"] ?? ""
        )
    }
}
