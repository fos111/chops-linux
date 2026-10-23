// Registry browsing/install and SSH remote-server management.
//
// Both network clients are injectable through the environment:
//   CHOPS_REGISTRY_BASE_URL   skills.sh search + www/trending
//   CHOPS_GITHUB_RAW_BASE_URL raw.githubusercontent.com
//   CHOPS_GITHUB_API_BASE_URL api.github.com
// QA points all three at `scripts/linux/mock-registry.py` (127.0.0.1:47116), so the
// smoke suite never reaches the real network.

import Foundation
import Vapor
import chopscore

extension ChopsdRuntime {
    // MARK: - Registry

    func registryTrending() async throws -> [RegistrySkillDTO] {
        do {
            return try await registry.fetchTrending().map(RegistrySkillDTO.init(skill:))
        } catch {
            throw Abort(.badGateway, reason: "Registry trending failed: \(error.localizedDescription)")
        }
    }

    func registrySearch(_ query: String) async throws -> [RegistrySkillDTO] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        do {
            return try await registry.search(query: trimmed).map(RegistrySkillDTO.init(skill:))
        } catch {
            throw Abort(.badGateway, reason: "Registry search failed: \(error.localizedDescription)")
        }
    }

    func installRegistry(_ request: RegistryInstallRequest) async throws -> RegistryInstallResponse {
        let skill = SkillRegistry.RegistrySkill(
            skillId: request.skillId,
            name: request.name,
            installs: request.installs ?? 0,
            source: request.source,
            isOfficial: request.isOfficial
        )
        let content: String
        do {
            content = try await registry.fetchContent(skill: skill)
        } catch {
            throw Abort(.badGateway, reason: "Could not fetch skill content: \(error.localizedDescription)")
        }
        let skillName = FrontmatterParser.parse(content).name.isEmpty
            ? skill.name
            : FrontmatterParser.parse(content).name
        return try await installContent(content, skillName: skillName, requestedTargets: request.targets)
    }

    // MARK: - Remote servers

    func remoteServers() throws -> [RemoteServerDTO] {
        try store.fetchRemoteServers().map(RemoteServerDTO.init(server:))
    }

    func createRemoteServer(_ request: RemoteServerRequest) throws -> RemoteServerDTO {
        let server = try validatedRemoteServer(
            RemoteServer(
                id: request.id ?? UUID().uuidString,
                label: request.label,
                host: request.host,
                port: request.port ?? 22,
                username: request.username,
                skillsBasePath: request.skillsBasePath,
                sshKeyPath: request.sshKeyPath
            )
        )
        guard try store.fetchRemoteServer(id: server.id) == nil else {
            throw Abort(.conflict, reason: "A remote server with id \(server.id) already exists.")
        }
        return RemoteServerDTO(server: try store.insertRemoteServer(server))
    }

    func updateRemoteServer(id: String, request: RemoteServerRequest) throws -> RemoteServerDTO {
        guard let existing = try store.fetchRemoteServer(id: id) else {
            throw Abort(.notFound, reason: "No remote server with id \(id).")
        }
        var updated = existing
        updated.label = request.label
        updated.host = request.host
        updated.port = request.port ?? existing.port
        updated.username = request.username
        updated.skillsBasePath = request.skillsBasePath
        updated.sshKeyPath = request.sshKeyPath
        try store.updateRemoteServer(try validatedRemoteServer(updated))
        return RemoteServerDTO(server: try store.fetchRemoteServer(id: id) ?? updated)
    }

    func deleteRemoteServer(id: String) throws -> Bool {
        guard try store.fetchRemoteServer(id: id) != nil else {
            throw Abort(.notFound, reason: "No remote server with id \(id).")
        }
        return try store.deleteRemoteServer(id: id)
    }

    /// Lists the remote SKILL.md files and syncs them into the local store as
    /// `remote://` rows (macOS `scanRemoteServer` parity).
    func browseRemote(_ request: RemoteBrowseRequest) async throws -> RemoteBrowseResponse {
        guard let server = try store.fetchRemoteServer(id: request.serverId) else {
            throw Abort(.notFound, reason: "No remote server with id \(request.serverId).")
        }

        let files: [(path: String, content: String)]
        do {
            files = try await ssh.findSkills(server)
        } catch {
            var failed = server
            failed.lastSyncError = error.localizedDescription
            try store.updateRemoteServer(failed)
            throw Abort(.badGateway, reason: "SSH browse failed: \(error.localizedDescription)")
        }

        let tool = Self.inferredRemoteToolSource(server)
        let existing = try store.fetchSkills(remoteServerID: server.id)
        var existingByPath: [String: Skill] = [:]
        for row in existing {
            existingByPath[row.resolvedPath] = row
        }

        var synced: [RemoteSkillDTO] = []
        var seen = Set<String>()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        for file in files.sorted(by: { $0.path < $1.path }) {
            let resolvedPath = "remote://\(server.id)/\(file.path)"
            seen.insert(resolvedPath)

            let parsed = FrontmatterParser.parse(file.content)
            let name = parsed.name.isEmpty
                ? Self.remoteSkillName(from: file.path)
                : parsed.name
            let frontmatterData = try encoder.encode(parsed.frontmatter)
            let installedPathsData = try encoder.encode([resolvedPath])

            if var row = existingByPath[resolvedPath] {
                row.filePath = resolvedPath
                row.name = name
                row.skillDescription = parsed.description
                row.content = parsed.content
                row.frontmatterData = frontmatterData
                row.fileModifiedDate = .now
                row.fileSize = file.content.utf8.count
                row.remoteServerID = server.id
                row.remotePath = file.path
                row.toolSourcesRaw = tool.rawValue
                row.installedPathsData = installedPathsData
                try store.updateSkill(row)
            } else {
                try store.insertSkill(
                    Skill(
                        filePath: resolvedPath,
                        resolvedPath: resolvedPath,
                        isDirectory: true,
                        name: name,
                        skillDescription: parsed.description,
                        content: parsed.content,
                        frontmatterData: frontmatterData,
                        fileModifiedDate: .now,
                        fileSize: file.content.utf8.count,
                        isGlobal: true,
                        remoteServerID: server.id,
                        remotePath: file.path,
                        toolSourcesRaw: tool.rawValue,
                        installedPathsData: installedPathsData,
                        kind: ItemKind.skill.rawValue
                    )
                )
            }

            synced.append(
                RemoteSkillDTO(
                    path: file.path,
                    name: name,
                    description: parsed.description,
                    content: parsed.content
                )
            )
        }

        // Drop rows for files that disappeared remotely.
        for row in existing where !seen.contains(row.resolvedPath) {
            if let id = row.id {
                _ = try store.deleteSkill(id: id)
            }
        }

        var updated = server
        updated.lastSyncDate = .now
        updated.lastSyncError = nil
        try store.updateRemoteServer(updated)

        return RemoteBrowseResponse(
            serverId: server.id,
            skills: synced,
            lastSyncDate: updated.lastSyncDate ?? .now
        )
    }

    /// Reads one remote skill and installs it into the selected local tool roots.
    func installRemote(_ request: RemoteInstallRequest) async throws -> RegistryInstallResponse {
        guard let server = try store.fetchRemoteServer(id: request.serverId) else {
            throw Abort(.notFound, reason: "No remote server with id \(request.serverId).")
        }
        let content: String
        do {
            content = try await ssh.readFile(server, path: request.remotePath)
        } catch {
            throw Abort(.badGateway, reason: "SSH read failed: \(error.localizedDescription)")
        }
        let parsedName = FrontmatterParser.parse(content).name
        let skillName = parsedName.isEmpty
            ? Self.remoteSkillName(from: request.remotePath)
            : parsedName
        return try await installContent(content, skillName: skillName, requestedTargets: request.targets)
    }

    // MARK: - Install helper

    func installContent(
        _ content: String,
        skillName: String,
        requestedTargets: [String]?
    ) async throws -> RegistryInstallResponse {
        let targets = try resolveInstallTargets(requestedTargets)
        guard !targets.isEmpty else {
            throw Abort(.badRequest, reason: "No installed tool can receive this skill.")
        }

        let sanitized = Self.sanitizeRegistryName(skillName)
        guard !sanitized.isEmpty else {
            throw Abort(.badRequest, reason: "Invalid skill name '\(skillName)'.")
        }

        let canonicalDirectory = homeDirectory
            .appendingPathComponent(".agents/skills", isDirectory: true)
            .appendingPathComponent(sanitized, isDirectory: true)
        let canonicalFile = canonicalDirectory.appendingPathComponent("SKILL.md").path

        guard isWriteAllowed(canonicalFile) else {
            throw Abort(.forbidden, reason: "Refusing to install outside the home directory: \(canonicalFile)")
        }
        for target in targets {
            let link = "\(target.globalSkillsDir)/\(sanitized)"
            guard isWriteAllowed(link) else {
                throw Abort(.forbidden, reason: "Refusing to install outside the configured scan roots: \(link)")
            }
        }

        do {
            try await registry.install(content: content, skillName: sanitized, targets: targets)
        } catch SkillRegistry.RegistryError.skillAlreadyExists {
            throw Abort(.conflict, reason: "Already installed for all selected targets.")
        } catch {
            throw Abort(.internalServerError, reason: "Install failed: \(error.localizedDescription)")
        }

        _ = try scanNow(reason: "registry-install", broadcast: true)
        let installed = try store.fetchSkill(resolvedPath: canonicalFile)

        return RegistryInstallResponse(
            installed: true,
            skillName: sanitized,
            path: canonicalFile,
            targets: targets.map(\.id),
            skill: installed.map(SkillDTO.init(skill:))
        )
    }

    func resolveInstallTargets(_ requested: [String]?) throws -> [SkillRegistry.InstallTarget] {
        var tools: [ToolSource] = []
        if let requested, !requested.isEmpty {
            for raw in requested {
                guard let tool = ToolSource(rawValue: raw) else {
                    throw Abort(.badRequest, reason: "Unknown tool '\(raw)'.")
                }
                tools.append(tool)
            }
        } else {
            tools = ToolSource.allCases.filter { tool in
                tool.listable && tool.isInstalled(
                    homeDirectory: homeDirectory,
                    configHomeDirectory: configHomeDirectory
                )
            }
        }

        var seen = Set<String>()
        var targets: [SkillRegistry.InstallTarget] = []
        for tool in tools {
            switch tool {
            case .agents, .custom, .claudeDesktop:
                continue
            default:
                break
            }
            guard tool.isInstalled(
                homeDirectory: homeDirectory,
                configHomeDirectory: configHomeDirectory
            ) else {
                if requested != nil {
                    throw Abort(.badRequest, reason: "\(tool.displayName) is not installed.")
                }
                continue
            }
            guard let directory = tool
                .globalPaths(homeDirectory: homeDirectory, configHomeDirectory: configHomeDirectory)
                .first else {
                if requested != nil {
                    throw Abort(.badRequest, reason: "\(tool.displayName) has no global skills directory.")
                }
                continue
            }
            guard seen.insert(tool.rawValue).inserted else { continue }
            targets.append(
                SkillRegistry.InstallTarget(
                    id: tool.rawValue,
                    displayName: tool.displayName,
                    globalSkillsDir: directory,
                    skillFileName: "SKILL.md"
                )
            )
        }
        return targets
    }

    // MARK: - Helpers

    static func sanitizeRegistryName(_ name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." || $0 == "_" }
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
    }

    static func remoteSkillName(from path: String) -> String {
        let components = path.components(separatedBy: "/")
        if let index = components.lastIndex(of: "SKILL.md"), index > 0 {
            return components[index - 1]
        }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    static func inferredRemoteToolSource(_ server: RemoteServer) -> ToolSource {
        let path = server.skillsBasePath.lowercased()
        if path.contains("hermes") { return .hermes }
        if path.contains("openclaw") { return .openclaw }
        return .openclaw
    }

    func validatedRemoteServer(_ server: RemoteServer) throws -> RemoteServer {
        var validated = server
        validated.label = server.label.trimmingCharacters(in: .whitespacesAndNewlines)
        validated.host = server.host.trimmingCharacters(in: .whitespacesAndNewlines)
        validated.username = server.username.trimmingCharacters(in: .whitespacesAndNewlines)
        validated.skillsBasePath = server.skillsBasePath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !validated.label.isEmpty,
              !validated.host.isEmpty,
              !validated.username.isEmpty,
              !validated.skillsBasePath.isEmpty else {
            throw Abort(.badRequest, reason: "label, host, username, and skillsBasePath are required.")
        }
        guard (1...65535).contains(validated.port) else {
            throw Abort(.badRequest, reason: "port must be between 1 and 65535.")
        }
        return validated
    }
}
