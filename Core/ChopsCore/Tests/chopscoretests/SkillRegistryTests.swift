import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

@testable import chopscore

/// Registry client tests (plan T09) against the committed local mock registry.
///
/// `scripts/linux/mock-registry.py` is started on 127.0.0.1:47116 by every test and
/// serves the same endpoint shapes as skills.sh + raw.githubusercontent.com +
/// api.github.com. The real hosts are never contacted.
final class SkillRegistryTests: XCTestCase {
    private var server: MockRegistryServer!
    private var endpoints: SkillRegistry.Endpoints!
    private var scratch: URL!
    private var home: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = try StoreTestSupport.makeTemporaryDirectory(prefix: "chopscore-registry")
        home = scratch.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        server = try MockRegistryServer.start()
        endpoints = .local(baseURL: server.baseURL)
    }

    override func tearDownWithError() throws {
        server?.stop()
        server = nil
        endpoints = nil
        if let scratch {
            try? FileManager.default.removeItem(at: scratch)
        }
        scratch = nil
        home = nil
        try super.tearDownWithError()
    }

    private func registry(using endpoints: SkillRegistry.Endpoints? = nil) -> SkillRegistry {
        SkillRegistry(
            endpoints: endpoints ?? self.endpoints!,
            httpClient: URLSessionRegistryHTTPClient(),
            homeDirectory: home
        )
    }

    private func skill(_ id: String, name: String, source: String = "acme/skills") -> SkillRegistry.RegistrySkill {
        SkillRegistry.RegistrySkill(skillId: id, name: name, installs: 1, source: source)
    }

    // MARK: - Search

    func testSearchDecodesCannedSkillsShResponse() async throws {
        let skills = try await registry().search(query: "pdf")

        let pdf = try XCTUnwrap(skills.first)
        XCTAssertEqual(skills.count, 1)
        XCTAssertEqual(pdf.skillId, "pdf-tools")
        XCTAssertEqual(pdf.name, "PDF Tools")
        XCTAssertEqual(pdf.installs, 12_500)
        XCTAssertEqual(pdf.source, "acme/skills")
        XCTAssertEqual(pdf.isOfficial, true)
        XCTAssertEqual(pdf.id, "acme/skills/pdf-tools")
        XCTAssertEqual(pdf.formattedInstalls, "12.5K")
    }

    func testSearchUsesFrozenEndpointShapeAndLimit() async throws {
        _ = try await registry().search(query: "web-audit")

        let requests = try await server.recordedRequests()
        let search = try XCTUnwrap(requests.first { $0.path == "/api/search" })
        XCTAssertEqual(search.query, "q=web-audit&limit=30")
    }

    func testSearchSkipsNetworkForQueriesShorterThanTwoCharacters() async throws {
        let skills = try await registry().search(query: "a")

        XCTAssertTrue(skills.isEmpty)
        let requests = try await server.recordedRequests()
        XCTAssertTrue(requests.filter { $0.path == "/api/search" }.isEmpty)
    }

    func testSearchThrowsSearchFailedOnNon200() async throws {
        var broken = endpoints!
        broken.skills = server.baseURL.appendingPathComponent("missing")

        do {
            _ = try await registry(using: broken).search(query: "pdf")
            XCTFail("expected searchFailed")
        } catch let error as SkillRegistry.RegistryError {
            XCTAssertEqual(error, .searchFailed)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - Trending

    func testFetchTrendingParsesRSCPayloadAndDeduplicates() async throws {
        let skills = try await registry().fetchTrending()

        XCTAssertEqual(skills.map(\.id), ["acme/skills/pdf-tools", "acme/skills/web-audit"])
        XCTAssertEqual(skills[0].installs, 12_500, "first occurrence wins during dedupe")
        XCTAssertEqual(skills[1].name, "Web Audit")
    }

    func testFetchTrendingSendsFrozenUserAgent() async throws {
        _ = try await registry().fetchTrending()

        let requests = try await server.recordedRequests()
        let trending = try XCTUnwrap(requests.first { $0.path == "/trending" })
        XCTAssertEqual(trending.userAgent, SkillRegistry.trendingUserAgent)
    }

    func testFetchTrendingIsCachedForTheSession() async throws {
        let registry = registry()
        _ = try await registry.fetchTrending()
        _ = try await registry.fetchTrending()

        let trendingRequests = try await server.requestCount(path: "/trending")
        XCTAssertEqual(trendingRequests, 1)
    }

    // MARK: - Static helpers

    func testFilterMatchesNameSkillIdAndSource() {
        let skills = [
            skill("pdf-tools", name: "PDF Tools"),
            skill("web-audit", name: "Web Audit"),
            skill("other", name: "Other", source: "another/repo"),
        ]

        XCTAssertEqual(SkillRegistry.filter(skills, query: "pdf").map(\.id), ["acme/skills/pdf-tools"])
        XCTAssertEqual(SkillRegistry.filter(skills, query: "AUDIT").map(\.id), ["acme/skills/web-audit"])
        XCTAssertEqual(
            SkillRegistry.filter(skills, query: "acme").map(\.id),
            ["acme/skills/pdf-tools", "acme/skills/web-audit"]
        )
        XCTAssertEqual(SkillRegistry.filter(skills, query: "another").map(\.id), ["another/repo/other"])
        XCTAssertEqual(SkillRegistry.filter(skills, query: "").count, 3)
    }

    func testFormattedInstallsMatchesMacOSFormatting() {
        XCTAssertEqual(skill("a", name: "A").formattedInstalls, "1")
        XCTAssertEqual(
            SkillRegistry.RegistrySkill(skillId: "a", name: "A", installs: 999, source: "s").formattedInstalls,
            "999"
        )
        XCTAssertEqual(
            SkillRegistry.RegistrySkill(skillId: "a", name: "A", installs: 1_000, source: "s").formattedInstalls,
            "1K"
        )
        XCTAssertEqual(
            SkillRegistry.RegistrySkill(skillId: "a", name: "A", installs: 12_500, source: "s").formattedInstalls,
            "12.5K"
        )
        XCTAssertEqual(
            SkillRegistry.RegistrySkill(skillId: "a", name: "A", installs: 1_000_000, source: "s").formattedInstalls,
            "1M"
        )
        XCTAssertEqual(
            SkillRegistry.RegistrySkill(skillId: "a", name: "A", installs: 2_500_000, source: "s").formattedInstalls,
            "2.5M"
        )
    }

    // MARK: - Content resolution

    func testFetchContentUsesConventionalRawPath() async throws {
        let content = try await registry().fetchContent(skill: skill("pdf-tools", name: "PDF Tools"))

        XCTAssertTrue(content.contains("# PDF Tools"))
        XCTAssertTrue(content.contains("description: Work with PDF files"))

        let requests = try await server.recordedRequests()
        XCTAssertTrue(requests.contains { $0.path == "/repos/acme/skills" })
        XCTAssertTrue(requests.contains { $0.path == "/acme/skills/main/skills/pdf-tools/SKILL.md" })
    }

    func testFetchContentFallsBackToGitHubTreeAPI() async throws {
        let content = try await registry().fetchContent(skill: skill("tree-only", name: "Tree Only"))

        XCTAssertTrue(content.contains("# Tree Only"))

        let requests = try await server.recordedRequests()
        let tree = try XCTUnwrap(requests.first { $0.path == "/repos/acme/skills/git/trees/main" })
        XCTAssertEqual(tree.query, "recursive=1")
        XCTAssertTrue(requests.contains { $0.path == "/acme/skills/main/skills/deep/tree-only/SKILL.md" })
    }

    func testFetchContentAcceptsRootSKILLmdWhenFrontmatterMatches() async throws {
        let content = try await registry().fetchContent(skill: skill("root-skill", name: "Root Skill"))

        XCTAssertTrue(content.contains("# Root Skill"))

        let requests = try await server.recordedRequests()
        XCTAssertTrue(requests.contains { $0.path == "/acme/skills/main/SKILL.md" })
    }

    func testFetchContentThrowsSkillNotFoundWhenFrontmatterNeverMatches() async throws {
        do {
            _ = try await registry().fetchContent(skill: skill("mismatch", name: "Mismatch"))
            XCTFail("expected skillNotFound")
        } catch let error as SkillRegistry.RegistryError {
            XCTAssertEqual(error, .skillNotFound)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testFetchContentSurfacesGitHubRateLimit() async throws {
        let limited = skill("anything", name: "Anything", source: "rate-limited/repo")

        do {
            _ = try await registry().fetchContent(skill: limited)
            XCTFail("expected rateLimited")
        } catch let error as SkillRegistry.RegistryError {
            XCTAssertEqual(error, .rateLimited)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testDefaultBranchAndTreeCachesAvoidRepeatedGitHubCalls() async throws {
        let registry = registry()
        let treeOnly = skill("tree-only", name: "Tree Only")
        _ = try await registry.fetchContent(skill: treeOnly)
        _ = try await registry.fetchContent(skill: treeOnly)

        let repoRequests = try await server.requestCount(path: "/repos/acme/skills")
        let treeRequests = try await server.requestCount(path: "/repos/acme/skills/git/trees/main")
        XCTAssertEqual(repoRequests, 1)
        XCTAssertEqual(treeRequests, 1)
    }

    // MARK: - Install

    func testInstallWritesCanonicalFileAndSymlinksTargets() async throws {
        let registry = registry()
        let content = "---\nname: pdf-tools\n---\n\n# PDF Tools\n"
        let claude = SkillRegistry.InstallTarget(
            id: "claude-code",
            displayName: "Claude Code",
            globalSkillsDir: "~/.claude/skills"
        )

        try await registry.install(content: content, skillName: "PDF Tools", targets: [claude])

        let canonicalDir = home.appendingPathComponent(".agents/skills/pdf-tools", isDirectory: true)
        let canonicalFile = canonicalDir.appendingPathComponent("SKILL.md")
        XCTAssertEqual(try String(contentsOf: canonicalFile, encoding: .utf8), content)

        let link = home.appendingPathComponent(".claude/skills/pdf-tools")
        XCTAssertTrue(FileManager.default.fileExists(atPath: link.path))
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: link.path),
            canonicalDir.path
        )
    }

    func testInstallSkipsExistingTargetButAddsNewOnes() async throws {
        let registry = registry()
        let content = "---\nname: pdf-tools\n---\n"
        let claude = SkillRegistry.InstallTarget(
            id: "claude-code",
            displayName: "Claude Code",
            globalSkillsDir: "~/.claude/skills"
        )
        let codex = SkillRegistry.InstallTarget(
            id: "codex",
            displayName: "Codex",
            globalSkillsDir: "~/.codex/skills"
        )

        try await registry.install(content: content, skillName: "pdf-tools", targets: [claude])
        // Existing claude link is skipped, codex is added: not an "already installed" failure.
        try await registry.install(content: content, skillName: "pdf-tools", targets: [claude, codex])

        let codexLink = home.appendingPathComponent(".codex/skills/pdf-tools")
        XCTAssertTrue(FileManager.default.fileExists(atPath: codexLink.path))
    }

    func testInstallThrowsAlreadyExistsWhenEverythingIsInPlace() async throws {
        let registry = registry()
        let content = "---\nname: pdf-tools\n---\n"
        let claude = SkillRegistry.InstallTarget(
            id: "claude-code",
            displayName: "Claude Code",
            globalSkillsDir: "~/.claude/skills"
        )

        try await registry.install(content: content, skillName: "pdf-tools", targets: [claude])

        do {
            try await registry.install(content: content, skillName: "pdf-tools", targets: [claude])
            XCTFail("expected skillAlreadyExists")
        } catch let error as SkillRegistry.RegistryError {
            XCTAssertEqual(error, .skillAlreadyExists)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testInstallRejectsNamesThatSanitizeToNothing() async throws {
        do {
            try await registry().install(content: "x", skillName: "!!!", targets: [])
            XCTFail("expected invalidSkillName")
        } catch let error as SkillRegistry.RegistryError {
            XCTAssertEqual(error, .invalidSkillName)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
