import Foundation

/// Parser for Cursor `.mdc` rule files.
///
/// Ported from the frozen macOS `MDCParser` (`Chops/Utilities/MDCParser.swift`):
/// MDC files use the same frontmatter format as `SKILL.md`, so this is a named
/// delegation to `FrontmatterParser` — kept as a separate type so `.mdc` handling
/// stays explicit and macOS-identical.
public enum MDCParser {
    public static func parse(_ text: String) -> ParsedSkill {
        FrontmatterParser.parse(text)
    }
}
