import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Seam for registry HTTP traffic.
///
/// Production uses `URLSessionRegistryHTTPClient`. Tests point the injectable
/// `SkillRegistry.Endpoints` at `scripts/linux/mock-registry.py` (127.0.0.1:47116),
/// so the suite never touches the real network.
public protocol RegistryHTTPClient: Sendable {
    func get(_ url: URL, userAgent: String?) async throws -> (data: Data, statusCode: Int)
}

/// URLSession-backed client. Uses a completion-handler task wrapped in a continuation
/// so it works identically on Darwin and swift-corelibs-foundation (Linux).
public struct URLSessionRegistryHTTPClient: RegistryHTTPClient {
    public init() {}

    public func get(_ url: URL, userAgent: String?) async throws -> (data: Data, statusCode: Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60
        if let userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }

        return try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                continuation.resume(returning: (data ?? Data(), http.statusCode))
            }.resume()
        }
    }
}

/// Port of the frozen macOS `SkillRegistry` (`Chops/Services/SkillRegistry.swift`).
///
/// Linux shape changes (no behavior change):
/// - `@Observable`/`shared` become an actor (the macOS class is UI-observed; chopsd
///   consumes this asynchronously). Session caches live in actor-isolated storage.
/// - All four network bases are injectable (`Endpoints`), so tests and chopsd can point
///   at a local mirror. Defaults are the real skills.sh + GitHub hosts.
/// - The macOS `AgentTarget` model is represented by the minimal `InstallTarget`, since
///   tool detection belongs to `ToolSource` on Linux and not to the registry client.
public actor SkillRegistry {
    /// Frozen macOS cache keys and the exact user agent sent while reading their HTML.
    public static let trendingUserAgent = "Chops/macOS (+https://github.com/Shpigford/chops)"

    public struct Endpoints: Sendable, Equatable {
        public var skills: URL
        public var wwwSkills: URL
        public var rawGitHub: URL
        public var apiGitHub: URL

        public init(skills: URL, wwwSkills: URL, rawGitHub: URL, apiGitHub: URL) {
            self.skills = skills
            self.wwwSkills = wwwSkills
            self.rawGitHub = rawGitHub
            self.apiGitHub = apiGitHub
        }

        /// The frozen production hosts.
        public static let production = Endpoints(
            skills: URL(string: "https://skills.sh")!,
            wwwSkills: URL(string: "https://www.skills.sh")!,
            rawGitHub: URL(string: "https://raw.githubusercontent.com")!,
            apiGitHub: URL(string: "https://api.github.com")!
        )

        /// All four bases on one host — used by the local mock registry fixture.
        public static func local(baseURL: URL) -> Endpoints {
            Endpoints(skills: baseURL, wwwSkills: baseURL, rawGitHub: baseURL, apiGitHub: baseURL)
        }
    }

    // MARK: - Search

    public struct SearchResponse: Codable, Sendable {
        public let skills: [RegistrySkill]
        public let count: Int

        public init(skills: [RegistrySkill], count: Int) {
            self.skills = skills
            self.count = count
        }
    }

    public struct RegistrySkill: Identifiable, Codable, Hashable, Sendable {
        public let skillId: String
        public let name: String
        public let installs: Int
        public let source: String
        public let isOfficial: Bool?

        public init(
            skillId: String,
            name: String,
            installs: Int,
            source: String,
            isOfficial: Bool? = nil
        ) {
            self.skillId = skillId
            self.name = name
            self.installs = installs
            self.source = source
            self.isOfficial = isOfficial
        }

        // Derived rather than decoded: the search API sends an `id` field equal to
        // "<source>/<skillId>", but the trending payload omits it. Computing it keeps
        // both sources Identifiable without a fragile optional.
        public var id: String { "\(source)/\(skillId)" }

        public var formattedInstalls: String {
            if installs >= 1_000_000 {
                return "\(String(format: "%.1f", Double(installs) / 1_000_000).replacingOccurrences(of: ".0", with: ""))M"
            } else if installs >= 1_000 {
                return "\(String(format: "%.1f", Double(installs) / 1_000).replacingOccurrences(of: ".0", with: ""))K"
            }
            return "\(installs)"
        }
    }

    // MARK: - Install

    /// Minimal replacement for the macOS `AgentTarget` slice the registry needs:
    /// where a tool keeps its global skills and under what name. Tilde paths are
    /// expanded against the injected `homeDirectory`.
    public struct InstallTarget: Identifiable, Hashable, Sendable {
        public let id: String
        public let displayName: String
        public let globalSkillsDir: String
        public let skillFileName: String

        public init(
            id: String,
            displayName: String,
            globalSkillsDir: String,
            skillFileName: String = "SKILL.md"
        ) {
            self.id = id
            self.displayName = displayName
            self.globalSkillsDir = globalSkillsDir
            self.skillFileName = skillFileName
        }
    }

    public enum RegistryError: Error, LocalizedError, Equatable, Sendable {
        case searchFailed
        case trendingFailed
        case treeFetchFailed
        case rateLimited
        case skillNotFound
        case invalidSkillName
        case skillAlreadyExists

        public var errorDescription: String? {
            switch self {
            case .searchFailed: "Search request failed"
            case .trendingFailed: "Could not load trending skills from skills.sh"
            case .treeFetchFailed: "Could not fetch repository contents"
            case .rateLimited: "GitHub API rate limit reached — try again in a few minutes"
            case .skillNotFound: "File not found in repository"
            case .invalidSkillName: "Invalid name"
            case .skillAlreadyExists: "Already installed for all selected targets"
            }
        }
    }

    // MARK: - State

    public let endpoints: Endpoints
    private let http: any RegistryHTTPClient
    private let homeDirectory: URL

    // Cache repo metadata to avoid repeated GitHub API calls.
    private var treeCache: [String: [String]] = [:] // source@branch -> [SKILL.md paths]
    private var branchCache: [String: String] = [:] // source -> default branch

    // Popular/trending skills, scraped from skills.sh. Cached in memory for the session.
    private var trendingCache: [RegistrySkill]?

    public init(
        endpoints: Endpoints = .production,
        httpClient: any RegistryHTTPClient = URLSessionRegistryHTTPClient(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.endpoints = endpoints
        self.http = httpClient
        self.homeDirectory = homeDirectory
    }

    // MARK: - Search

    public func search(query: String) async throws -> [RegistrySkill] {
        guard query.count >= 2 else { return [] }

        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = Self.url(endpoints.skills, "api/search?q=\(encoded)&limit=30")

        let (data, status) = try await http.get(url, userAgent: nil)
        guard status == 200 else {
            throw RegistryError.searchFailed
        }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.skills
    }

    // MARK: - Trending / Browse

    /// Fetches the most-installed skills by scraping skills.sh's server-rendered
    /// trending page (no public JSON API exists for this). The result — ~600 skills
    /// ranked by install count — is cached for the session and powers instant local
    /// browse + filtering, which is both faster and broader than the fuzzy search API.
    public func fetchTrending() async throws -> [RegistrySkill] {
        if let cached = trendingCache { return cached }

        let url = Self.url(endpoints.wwwSkills, "trending")
        let (data, status) = try await http.get(url, userAgent: Self.trendingUserAgent)
        guard status == 200, let html = String(data: data, encoding: .utf8) else {
            throw RegistryError.trendingFailed
        }

        let skills = Self.parseTrending(html: html)
        guard !skills.isEmpty else { throw RegistryError.trendingFailed }
        trendingCache = skills
        return skills
    }

    /// Extracts skill objects from the Next.js RSC payload embedded in the trending HTML.
    /// The payload lives inside JS string literals, so JSON quotes arrive as `\"`; we
    /// unescape, then pull out every flat `{…"skillId":…}` object and hand it to
    /// JSONDecoder, which tolerates extra keys and any key order. Page order is
    /// install-count descending, which we preserve.
    public static func parseTrending(html: String) -> [RegistrySkill] {
        let unescaped = html.replacingOccurrences(of: "\\\"", with: "\"")
        let pattern = #/\{[^{}]*"skillId":[^{}]*\}/#

        let decoder = JSONDecoder()
        var seen = Set<String>()
        var result: [RegistrySkill] = []
        for match in unescaped.matches(of: pattern) {
            let json = String(match.output)
            guard let skill = try? decoder.decode(RegistrySkill.self, from: Data(json.utf8)) else { continue }
            if seen.insert(skill.id).inserted {
                result.append(skill)
            }
        }
        return result
    }

    /// Case-insensitive substring match across name, skillId, and source.
    public static func filter(_ skills: [RegistrySkill], query: String) -> [RegistrySkill] {
        guard !query.isEmpty else { return skills }
        return skills.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.skillId.localizedCaseInsensitiveContains(query)
                || $0.source.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: - Content Resolution

    public func fetchContent(skill: RegistrySkill) async throws -> String {
        let branch = try await getDefaultBranch(source: skill.source)

        if let content = try await fetchContentAtConventionalPaths(skill: skill, branch: branch) {
            return content
        }

        return try await fetchContentViaTreeAPI(skill: skill, branch: branch)
    }

    private func fetchContentAtConventionalPaths(skill: RegistrySkill, branch: String) async throws -> String? {
        let pathPatterns = [
            "skills/\(skill.skillId)/SKILL.md",
            "skills/.curated/\(skill.skillId)/SKILL.md",
            "skills/.experimental/\(skill.skillId)/SKILL.md",
            "\(skill.skillId)/SKILL.md",
            "SKILL.md",
        ]

        for path in pathPatterns {
            let rawURL = Self.url(endpoints.rawGitHub, "\(skill.source)/\(branch)/\(path)")
            guard let (data, status) = try? await http.get(rawURL, userAgent: nil),
                  status == 200,
                  let content = String(data: data, encoding: .utf8) else {
                continue
            }

            if path == "SKILL.md" {
                let name = Self.parseFrontmatterName(from: content)
                if name != skill.skillId && name != skill.name { continue }
            }

            return content
        }

        return nil
    }

    private func fetchContentViaTreeAPI(skill: RegistrySkill, branch: String) async throws -> String {
        let paths = try await getSkillPaths(source: skill.source, branch: branch)

        for path in paths {
            let rawURL = Self.url(endpoints.rawGitHub, "\(skill.source)/\(branch)/\(path)")
            guard let (data, status) = try? await http.get(rawURL, userAgent: nil),
                  status == 200,
                  let content = String(data: data, encoding: .utf8) else {
                continue
            }

            let frontmatterName = Self.parseFrontmatterName(from: content)
            if frontmatterName == skill.skillId || frontmatterName == skill.name {
                return content
            }
        }

        throw RegistryError.skillNotFound
    }

    private func getDefaultBranch(source: String) async throws -> String {
        if let cached = branchCache[source] {
            return cached
        }

        let url = Self.url(endpoints.apiGitHub, "repos/\(source)")
        let (data, status) = try await http.get(url, userAgent: nil)
        if status == 403 {
            throw RegistryError.rateLimited
        }
        guard status == 200 else {
            throw RegistryError.treeFetchFailed
        }

        struct RepoResponse: Codable {
            let default_branch: String
        }

        let repo = try JSONDecoder().decode(RepoResponse.self, from: data)
        branchCache[source] = repo.default_branch
        return repo.default_branch
    }

    private func getSkillPaths(source: String, branch: String) async throws -> [String] {
        let cacheKey = "\(source)@\(branch)"
        if let cached = treeCache[cacheKey] {
            return cached
        }

        let url = Self.url(endpoints.apiGitHub, "repos/\(source)/git/trees/\(branch)?recursive=1")
        let (data, status) = try await http.get(url, userAgent: nil)
        if status == 403 {
            throw RegistryError.rateLimited
        }
        guard status == 200 else {
            throw RegistryError.treeFetchFailed
        }

        struct TreeResponse: Codable {
            struct TreeEntry: Codable {
                let path: String
                let type: String
            }
            let tree: [TreeEntry]
        }

        let tree = try JSONDecoder().decode(TreeResponse.self, from: data)
        let skillPaths = tree.tree
            .filter { $0.type == "blob" && ($0.path == "SKILL.md" || $0.path.hasSuffix("/SKILL.md")) }
            .map(\.path)

        treeCache[cacheKey] = skillPaths
        return skillPaths
    }

    static func parseFrontmatterName(from content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { break }
            if trimmed.hasPrefix("name:") {
                return trimmed
                    .dropFirst(5)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return nil
    }

    // MARK: - Install

    public func install(content: String, skillName: String, targets: [InstallTarget]) throws {
        let sanitized = skillName
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." || $0 == "_" }
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))

        guard !sanitized.isEmpty else {
            throw RegistryError.invalidSkillName
        }

        let fm = FileManager.default
        let home = homeDirectory.path

        // Canonical location — matches the official skills CLI behavior.
        let canonicalDir = "\(home)/.agents/skills/\(sanitized)"
        let canonicalFile = "\(canonicalDir)/SKILL.md"
        let canonicalAlreadyExisted = fm.fileExists(atPath: canonicalFile)

        // Write real file to canonical location if not already there.
        if !canonicalAlreadyExisted {
            try fm.createDirectory(atPath: canonicalDir, withIntermediateDirectories: true)
            try content.write(toFile: canonicalFile, atomically: true, encoding: .utf8)
        }

        // Symlink from each agent's skills dir to the canonical location.
        var newLinks = 0
        for target in targets {
            let agentDir = "\(expandTilde(target.globalSkillsDir))/\(sanitized)"

            // Skip if already installed (real file or symlink).
            if fm.fileExists(atPath: agentDir) { continue }

            // Create parent dir if needed.
            try fm.createDirectory(atPath: expandTilde(target.globalSkillsDir), withIntermediateDirectories: true)

            // Create symlink to canonical dir.
            try fm.createSymbolicLink(atPath: agentDir, withDestinationPath: canonicalDir)
            newLinks += 1
        }

        if newLinks == 0 && canonicalAlreadyExisted {
            throw RegistryError.skillAlreadyExists
        }
    }

    // MARK: - Internals

    private func expandTilde(_ path: String) -> String {
        if path.hasPrefix("~/") {
            return homeDirectory.path + path.dropFirst(1)
        }
        if path == "~" {
            return homeDirectory.path
        }
        return path
    }

    private static func url(_ base: URL, _ relativePath: String) -> URL {
        var baseString = base.absoluteString
        while baseString.hasSuffix("/") { baseString.removeLast() }
        return URL(string: baseString + "/" + relativePath)!
    }
}
