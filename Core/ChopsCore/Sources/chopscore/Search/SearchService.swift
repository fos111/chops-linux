import Foundation

/// Portable port of the frozen macOS `SearchService`
/// (`Chops/Services/SearchService.swift`).
///
/// macOS searches the SwiftData store through a `ModelContext`; on Linux the records
/// live in GRDB (plan T05), so this searches an in-memory `[Skill]` collection. The
/// matching rule is identical: an empty query returns nothing, otherwise name,
/// description, or content must contain the query (localized, case-insensitive).
/// Result order follows the input order — `ChopsStore.fetchSkills()` already returns
/// the name-NOCASE order the macOS sidebar uses.
public enum SearchService {
    public static func search(query: String, in skills: [Skill]) -> [Skill] {
        guard !query.isEmpty else { return [] }

        return skills.filter { skill in
            skill.name.localizedCaseInsensitiveContains(query) ||
            skill.skillDescription.localizedCaseInsensitiveContains(query) ||
            skill.content.localizedCaseInsensitiveContains(query)
        }
    }

    /// Convenience over the GRDB-backed store: reads every record, then searches
    /// in memory. Throws only if the database read fails.
    public static func search(query: String, in store: ChopsStore) throws -> [Skill] {
        search(query: query, in: try store.fetchSkills())
    }
}
