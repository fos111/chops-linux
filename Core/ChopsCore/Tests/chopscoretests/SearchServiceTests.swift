import Foundation
import XCTest

@testable import chopscore

/// Port-parity tests for the frozen `Chops/Services/SearchService.swift`.
/// Matching happens in memory over the GRDB records introduced in plan T05.
final class SearchServiceTests: StoreTestCase {
    private func makeSkill(
        path: String,
        name: String,
        description: String,
        content: String
    ) -> Skill {
        Skill(
            filePath: path,
            name: name,
            skillDescription: description,
            content: content,
            fileModifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
            fileSize: content.utf8.count
        )
    }

    // MARK: - Matching semantics

    func testEmptyQueryReturnsNoResults() {
        let skills = [makeSkill(path: "/a.md", name: "a-one", description: "skill a", content: "# a-one")]

        XCTAssertEqual(SearchService.search(query: "", in: skills), [])
    }

    func testMatchesNameCaseInsensitively() {
        let skill = makeSkill(path: "/a.md", name: "A-One", description: "skill a", content: "# A-One")

        XCTAssertEqual(SearchService.search(query: "a-ONE", in: [skill]).map(\.name), ["A-One"])
    }

    func testMatchesDescription() {
        let skill = makeSkill(path: "/a.md", name: "a-one", description: "Handles Deployments", content: "# a-one")

        XCTAssertEqual(SearchService.search(query: "deploy", in: [skill]).count, 1)
    }

    func testMatchesContentAcrossNewlines() {
        let skill = makeSkill(
            path: "/a.md",
            name: "a-one",
            description: "skill a",
            content: "# a-one\n\nFixture skill one — exercises the scan."
        )

        XCTAssertEqual(SearchService.search(query: "fixture skill one", in: [skill]).count, 1)
    }

    func testReturnsEmptyWhenNothingMatches() {
        let skills = [
            makeSkill(path: "/a.md", name: "a-one", description: "skill a", content: "# a-one"),
            makeSkill(path: "/b.md", name: "b-two", description: "skill b", content: "# b-two"),
        ]

        XCTAssertEqual(SearchService.search(query: "no-such-token", in: skills), [])
    }

    func testQueryIsLiteralNotAnSQLWildcard() {
        let underscore = makeSkill(path: "/c.md", name: "c_three", description: "skill c", content: "# c_three")
        let plain = makeSkill(path: "/a.md", name: "a-one", description: "skill a", content: "# a-one")

        XCTAssertEqual(SearchService.search(query: "_", in: [plain, underscore]).map(\.name), ["c_three"])
    }

    func testPreservesInputOrder() {
        let b = makeSkill(path: "/b.md", name: "b-two", description: "skill b", content: "# b-two")
        let a = makeSkill(path: "/a.md", name: "a-one", description: "skill a", content: "# a-one")

        XCTAssertEqual(SearchService.search(query: "skill", in: [b, a]).map(\.name), ["b-two", "a-one"])
    }

    // MARK: - Over GRDB records

    func testSearchesGRDBRecordsInStoreOrder() throws {
        let store = try StoreTestSupport.store(in: try scratch)
        let fixtures: [(name: String, description: String, content: String)] = [
            ("b-two", "skill b", "# b-two\nFixture skill two"),
            ("a-one", "skill a", "# a-one\nFixture skill one"),
            ("c-three", "skill c", "# c-three\nCodex fixture"),
        ]
        for fixture in fixtures {
            try store.insertSkill(
                makeSkill(
                    path: "/fixture/home/.claude/skills/\(fixture.name).md",
                    name: fixture.name,
                    description: fixture.description,
                    content: fixture.content
                )
            )
        }

        let all = try store.fetchSkills()
        XCTAssertEqual(all.map(\.name), ["a-one", "b-two", "c-three"])

        let matches = try SearchService.search(query: "fixture", in: store)
        XCTAssertEqual(matches.map(\.name), ["a-one", "b-two", "c-three"])

        let codexOnly = try SearchService.search(query: "CODEX", in: store)
        XCTAssertEqual(codexOnly.map(\.name), ["c-three"])

        XCTAssertEqual(try SearchService.search(query: "", in: store), [])
    }

    func testSearchDoesNotFilterOnKindOrTool() throws {
        let store = try StoreTestSupport.store(in: try scratch)
        var agent = makeSkill(path: "/agent.md", name: "reviewer", description: "review agent", content: "# reviewer")
        agent.kind = "agent"
        agent.toolSourcesRaw = "claude"
        try store.insertSkill(agent)

        var rule = makeSkill(path: "/rule.mdc", name: "rule-one", description: "cursor rule", content: "# rule-one")
        rule.kind = "rule"
        rule.toolSourcesRaw = "cursor"
        try store.insertSkill(rule)

        XCTAssertEqual(try SearchService.search(query: "review", in: store).map(\.name), ["reviewer"])
        XCTAssertEqual(try SearchService.search(query: "rule", in: store).map(\.name), ["rule-one"])
    }
}
