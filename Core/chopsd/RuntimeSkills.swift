// Skill reads, editor writes, template creation, and the assist accept/reject gate.
//
// The contract's write rule is explicit: an editor PUT writes the full file directly
// (macOS parity, no diff gate), while an agent turn never touches disk — it inserts a
// `pending_writes` row and only `POST /api/assist/{pendingId}/accept` writes the fenced
// content. Reject deletes the row and discards the proposal.

import Foundation
import Vapor
import chopscore

extension ChopsdRuntime {
    // MARK: - Reads

    func skills(tool: String?, query: String?) throws -> [SkillDTO] {
        var rows = try store.fetchSkills()

        if let tool, !tool.isEmpty {
            let wanted = Set(
                tool.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            )
            rows = rows.filter { row in
                let rowTools = row.toolSourcesRaw
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                return !wanted.isDisjoint(with: rowTools)
            }
        }

        if let query, !query.isEmpty {
            rows = SearchService.search(query: query, in: rows)
        }

        return rows.map(SkillDTO.init(skill:))
    }

    func skill(id: Int64) throws -> SkillDTO {
        guard let row = try store.fetchSkill(id: id) else {
            throw Abort(.notFound, reason: "No skill with id \(id).")
        }
        return SkillDTO(skill: row)
    }

    // MARK: - Editor save (direct write, macOS parity)

    func updateSkill(id: Int64, content: String) async throws -> SkillDTO {
        guard var row = try store.fetchSkill(id: id) else {
            throw Abort(.notFound, reason: "No skill with id \(id).")
        }

        if let serverID = row.remoteServerID, let remotePath = row.remotePath {
            guard let server = try store.fetchRemoteServer(id: serverID) else {
                throw Abort(.failedDependency, reason: "Remote server \(serverID) is not configured.")
            }
            do {
                try await ssh.writeFile(server, path: remotePath, content: content)
            } catch {
                var failedServer = server
                failedServer.lastSyncError = error.localizedDescription
                try store.updateRemoteServer(failedServer)
                throw Abort(.badGateway, reason: "SSH write failed: \(error.localizedDescription)")
            }
            var syncedServer = server
            syncedServer.lastSyncDate = .now
            syncedServer.lastSyncError = nil
            try store.updateRemoteServer(syncedServer)

            applyParsedContent(content, to: &row)
            try store.updateSkill(row)
            hub.broadcast(.rescan(reason: "remote-save", count: try store.fetchSkills().count))
            return SkillDTO(skill: row)
        }

        guard isWriteAllowed(row.filePath) else {
            throw Abort(.forbidden, reason: "Refusing to write outside the configured scan roots: \(row.filePath)")
        }

        try writeFile(content, to: row.filePath)

        // Rescan is the source of truth for name/description/frontmatter changes.
        _ = try scanNow(reason: "skill-save", broadcast: true)
        guard let updated = try store.fetchSkill(resolvedPath: row.resolvedPath) else {
            throw Abort(
                .unprocessableEntity,
                reason: "Saved file is no longer a parseable skill: \(row.filePath)"
            )
        }
        return SkillDTO(skill: updated)
    }

    // MARK: - Template creation (macOS NewSkillSheet parity)

    func createSkill(_ request: SkillCreateRequest) throws -> SkillDTO {
        let kind = ItemKind(rawValue: request.kind ?? ItemKind.skill.rawValue) ?? .skill
        guard let tool = ToolSource(rawValue: request.tool) else {
            throw Abort(.badRequest, reason: "Unknown tool '\(request.tool)'.")
        }

        let sanitized = Self.sanitizeSkillName(request.name)
        guard !sanitized.isEmpty else {
            throw Abort(.badRequest, reason: "Invalid name.")
        }

        let basePath: String
        let fileName: String
        switch kind {
        case .agent:
            guard let directory = tool.globalAgentPaths(homeDirectory: homeDirectory).first else {
                throw Abort(.badRequest, reason: "\(tool.displayName) doesn't support agents.")
            }
            basePath = "\(directory)/\(sanitized)"
            fileName = "\(sanitized).md"
        case .rule:
            guard let directory = tool.globalRulePaths(homeDirectory: homeDirectory).first else {
                throw Abort(.badRequest, reason: "\(tool.displayName) doesn't support rules.")
            }
            basePath = directory
            fileName = "\(sanitized).md"
        case .skill:
            guard let directory = tool
                .globalPaths(homeDirectory: homeDirectory, configHomeDirectory: configHomeDirectory)
                .first else {
                throw Abort(.badRequest, reason: "\(tool.displayName) doesn't support skills.")
            }
            basePath = "\(directory)/\(sanitized)"
            fileName = "SKILL.md"
        }

        let filePath = "\(basePath)/\(fileName)"
        guard isWriteAllowed(filePath) else {
            throw Abort(.forbidden, reason: "Refusing to create outside the configured scan roots: \(filePath)")
        }
        guard !FileManager.default.fileExists(atPath: filePath) else {
            throw Abort(.conflict, reason: "A \(kind.singularName.lowercased()) with this name already exists.")
        }

        let boilerplate = TemplateManager.boilerplate(
            kind: Self.wizardType(for: kind),
            name: request.name,
            skillID: sanitized,
            tool: tool
        )
        try writeFile(boilerplate, to: filePath)

        // macOS "Global" skills are canonical under ~/.agents/skills and symlinked from
        // every installed agent's skills directory.
        if kind == .skill && tool == .agents {
            try linkGlobalSkill(named: sanitized, canonicalDirectory: basePath)
        }

        _ = try scanNow(reason: "skill-create", broadcast: true)
        let resolved = URL(fileURLWithPath: filePath).resolvingSymlinksInPath().path
        guard let created = try store.fetchSkill(resolvedPath: resolved) else {
            throw Abort(.internalServerError, reason: "Created file was not discovered by the scanner: \(filePath)")
        }
        return SkillDTO(skill: created)
    }

    func linkGlobalSkill(named name: String, canonicalDirectory: String) throws {
        for tool in ToolSource.allCases {
            switch tool {
            case .agents, .custom, .claudeDesktop:
                continue
            default:
                break
            }
            guard tool.isInstalled(
                homeDirectory: homeDirectory,
                configHomeDirectory: configHomeDirectory
            ) else { continue }
            guard let directory = tool
                .globalPaths(homeDirectory: homeDirectory, configHomeDirectory: configHomeDirectory)
                .first else { continue }

            let linkPath = "\(directory)/\(name)"
            guard !FileManager.default.fileExists(atPath: linkPath) else { continue }
            guard isWriteAllowed(linkPath) else { continue }
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(
                atPath: linkPath,
                withDestinationPath: canonicalDirectory
            )
        }
    }

    // MARK: - Assist (agent turn → pending write)

    func assist(_ request: AssistRequest) async throws -> AssistResponse {
        guard let row = try store.fetchSkill(id: request.skillId) else {
            throw Abort(.notFound, reason: "No skill with id \(request.skillId).")
        }
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            throw Abort(.badRequest, reason: "prompt must not be empty.")
        }

        let agentID: AgentID
        if let rawAgent = request.agent, !rawAgent.isEmpty {
            guard let parsed = AgentID(rawValue: rawAgent) else {
                throw Abort(.badRequest, reason: "Unknown agent '\(rawAgent)'.")
            }
            agentID = parsed
        } else {
            agentID = .claude
        }

        let filePath = row.filePath
        let content = request.content ?? row.content
        let kind = ItemKind(rawValue: row.kind) ?? .skill
        let systemPrompt = TemplateManager.shared.systemPrompt(
            for: Self.wizardType(for: kind),
            skillName: row.name,
            skillDescription: row.skillDescription,
            filePath: filePath,
            frontmatter: Self.frontmatter(of: row)
        )

        let workingDirectory: URL
        if row.remoteServerID == nil {
            workingDirectory = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        } else {
            workingDirectory = homeDirectory
        }

        let session = AgentFactory.make(for: agentID, configuration: agentEnvironment)
        await session.startConnect(workingDirectory: workingDirectory, systemPrompt: systemPrompt)
        await session.primeDeferredContent(for: filePath, content: content)

        hub.broadcast(
            .assistStatus(
                pendingId: nil,
                status: "running",
                message: "\(agentID.displayName) is working…",
                skillId: request.skillId
            )
        )

        do {
            try await session.prompt(prompt)
        } catch {
            await session.disconnect()
            hub.broadcast(
                .assistStatus(
                    pendingId: nil,
                    status: "error",
                    message: error.localizedDescription,
                    skillId: request.skillId
                )
            )
            throw Abort(.badGateway, reason: error.localizedDescription)
        }

        let summary = await session.responseText
        let writes = await session.pendingWrites
        await session.disconnect()

        let preferredWrite = writes.first(where: { $0.path == filePath }) ?? writes.first
        guard let write = preferredWrite else {
            hub.broadcast(
                .assistStatus(
                    pendingId: nil,
                    status: "replied",
                    message: summary,
                    skillId: request.skillId
                )
            )
            return AssistResponse(
                pendingId: nil,
                summary: summary,
                fullFile: nil,
                path: nil,
                agent: agentID.rawValue,
                skillId: request.skillId
            )
        }

        let remote = row.remoteServerID != nil
        guard remote || isWriteAllowed(write.path) else {
            hub.broadcast(
                .assistStatus(
                    pendingId: nil,
                    status: "error",
                    message: "Refusing to stage a write outside the configured scan roots.",
                    skillId: request.skillId
                )
            )
            throw Abort(
                .forbidden,
                reason: "Refusing to stage a write outside the configured scan roots: \(write.path)"
            )
        }

        let originalText = write.originalText ?? content
        let pending = PendingWrite(
            pendingId: write.pendingId,
            path: write.path,
            content: write.content,
            originalText: originalText,
            originalData: originalText.data(using: .utf8),
            existedBefore: remote
                ? true
                : FileManager.default.fileExists(atPath: write.path),
            agentDidWrite: false
        )
        try store.insertPendingWrite(pending)

        hub.broadcast(
            .assistStatus(
                pendingId: pending.pendingId,
                status: "pending",
                message: summary,
                skillId: request.skillId
            )
        )

        return AssistResponse(
            pendingId: pending.pendingId,
            summary: summary,
            fullFile: pending.content,
            path: pending.path,
            agent: agentID.rawValue,
            skillId: request.skillId
        )
    }

    func acceptAssist(pendingId: String) async throws -> AssistAcceptResponse {
        guard let pending = try store.fetchPendingWrite(id: pendingId) else {
            throw Abort(.notFound, reason: "No pending write with id \(pendingId).")
        }

        let skills = try store.fetchSkills()
        let owningSkill = skills.first {
            $0.resolvedPath == pending.path || $0.filePath == pending.path
        }

        if let owningSkill,
           let serverID = owningSkill.remoteServerID,
           let remotePath = owningSkill.remotePath {
            guard let server = try store.fetchRemoteServer(id: serverID) else {
                throw Abort(.failedDependency, reason: "Remote server \(serverID) is not configured.")
            }
            do {
                try await ssh.writeFile(server, path: remotePath, content: pending.content)
            } catch {
                var failed = server
                failed.lastSyncError = error.localizedDescription
                try store.updateRemoteServer(failed)
                throw Abort(.badGateway, reason: "SSH write failed: \(error.localizedDescription)")
            }
            var synced = server
            synced.lastSyncDate = .now
            synced.lastSyncError = nil
            try store.updateRemoteServer(synced)

            var updated = owningSkill
            applyParsedContent(pending.content, to: &updated)
            try store.updateSkill(updated)
            _ = try store.deletePendingWrite(id: pendingId)
            hub.broadcast(
                .assistStatus(
                    pendingId: pendingId,
                    status: "accepted",
                    message: nil,
                    skillId: updated.id
                )
            )
            return AssistAcceptResponse(
                accepted: true,
                pendingId: pendingId,
                path: remotePath,
                skill: SkillDTO(skill: updated)
            )
        }

        guard isWriteAllowed(pending.path) else {
            throw Abort(
                .forbidden,
                reason: "Refusing to write outside the configured scan roots: \(pending.path)"
            )
        }

        try writeFile(pending.content, to: pending.path)
        _ = try store.deletePendingWrite(id: pendingId)
        _ = try scanNow(reason: "assist-accepted", broadcast: true)

        let refreshed = try store.fetchSkills().first {
            $0.resolvedPath == pending.path || $0.filePath == pending.path
        }
        hub.broadcast(
            .assistStatus(
                pendingId: pendingId,
                status: "accepted",
                message: nil,
                skillId: refreshed?.id
            )
        )
        return AssistAcceptResponse(
            accepted: true,
            pendingId: pendingId,
            path: pending.path,
            skill: refreshed.map(SkillDTO.init(skill:))
        )
    }

    func rejectAssist(pendingId: String) throws -> AssistRejectResponse {
        guard let pending = try store.fetchPendingWrite(id: pendingId) else {
            throw Abort(.notFound, reason: "No pending write with id \(pendingId).")
        }

        // Only direct-CLI transports ever mutate disk before review; the current
        // one-shot transports do not, but restoring the snapshot keeps the contract
        // safe if such a transport is added later.
        if pending.agentDidWrite {
            if pending.existedBefore, let original = pending.originalData {
                if let text = String(data: original, encoding: .utf8) {
                    try writeFile(text, to: pending.path)
                } else {
                    try original.write(to: URL(fileURLWithPath: pending.path), options: .atomic)
                }
            } else {
                try? FileManager.default.removeItem(atPath: pending.path)
            }
        }

        _ = try store.deletePendingWrite(id: pendingId)
        hub.broadcast(
            .assistStatus(
                pendingId: pendingId,
                status: "rejected",
                message: nil,
                skillId: nil
            )
        )
        return AssistRejectResponse(rejected: true, pendingId: pendingId)
    }

    // MARK: - Shared helpers

    func applyParsedContent(_ content: String, to row: inout Skill) {
        let parsed = FrontmatterParser.parse(content)
        row.content = parsed.content
        row.skillDescription = parsed.description
        if !parsed.name.isEmpty {
            row.name = parsed.name
        }
        row.frontmatterData = try? JSONEncoder().encode(parsed.frontmatter)
        row.fileModifiedDate = .now
        row.fileSize = content.utf8.count
    }

    static func wizardType(for kind: ItemKind) -> WizardTemplateType {
        switch kind {
        case .skill: .skill
        case .agent: .agent
        case .rule: .rule
        }
    }

    static func frontmatter(of skill: Skill) -> [String: String] {
        guard let data = skill.frontmatterData,
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    /// macOS `NewSkillSheet` sanitization: lowercase, spaces to dashes, keep letters,
    /// digits, and dashes only.
    static func sanitizeSkillName(_ name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }
}
