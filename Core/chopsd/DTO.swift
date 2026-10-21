// chopsd REST/WS payloads (plan T11).
//
// The fixed UI↔chopsd contract in `.omo/plans/debian-linux-port.md` is the source of
// truth: these types serialize the `chopscore` records without rendering Markdown
// (the server always ships raw file content; the Tauri front-end renders it).

import Foundation
import Vapor
import chopscore

// MARK: - Skills

/// One skill/agent/rule row as the UI consumes it.
struct SkillDTO: Content {
    var id: Int64
    var filePath: String
    var resolvedPath: String
    var name: String
    var description: String
    var content: String
    var frontmatter: [String: String]
    var isDirectory: Bool
    var isGlobal: Bool
    var isFavorite: Bool
    var fileModifiedDate: Date
    var fileSize: Int
    var toolSources: [String]
    var installedPaths: [String]
    var kind: String
    var collections: [CollectionRefDTO]
    var remoteServerID: String?
    var remotePath: String?

    init(skill: Skill) {
        self.id = skill.id ?? 0
        self.filePath = skill.filePath
        self.resolvedPath = skill.resolvedPath
        self.name = skill.name
        self.description = skill.skillDescription
        self.content = skill.content
        self.frontmatter = Self.decodeFrontmatter(skill.frontmatterData)
        self.isDirectory = skill.isDirectory
        self.isGlobal = skill.isGlobal
        self.isFavorite = skill.isFavorite
        self.fileModifiedDate = skill.fileModifiedDate
        self.fileSize = skill.fileSize
        self.toolSources = skill.toolSourcesRaw
            .split(separator: ",")
            .map(String.init)
            .filter { !$0.isEmpty }
        self.installedPaths = Self.decodeInstalledPaths(
            skill.installedPathsData,
            fallback: skill.filePath
        )
        self.kind = skill.kind
        self.collections = skill.collections.compactMap { collection in
            guard let id = collection.id else { return nil }
            return CollectionRefDTO(
                id: id,
                name: collection.name,
                icon: collection.icon,
                sortOrder: collection.sortOrder
            )
        }
        self.remoteServerID = skill.remoteServerID
        self.remotePath = skill.remotePath
    }

    private static func decodeFrontmatter(_ data: Data?) -> [String: String] {
        guard let data,
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func decodeInstalledPaths(_ data: Data?, fallback: String) -> [String] {
        guard let data,
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return [fallback]
        }
        return decoded
    }
}

/// Editor save body: the complete Markdown file (front-end keeps it raw).
struct SkillUpdateRequest: Content {
    var content: String
}

/// Template-create body (macOS `NewSkillSheet` fields).
struct SkillCreateRequest: Content {
    var name: String
    var tool: String
    var kind: String?
}

// MARK: - Tools

struct ToolDTO: Content {
    var id: String
    var displayName: String
    var isInstalled: Bool
    var listable: Bool
    var supportsSkills: Bool
    var supportsAgents: Bool
    var supportsRules: Bool
    var globalPaths: [String]
    var globalAgentPaths: [String]
    var globalRulePaths: [String]
}

// MARK: - Collections

struct CollectionRefDTO: Content {
    var id: Int64
    var name: String
    var icon: String
    var sortOrder: Int
}

struct CollectionDTO: Content {
    var id: Int64
    var name: String
    var icon: String
    var sortOrder: Int
    var skillCount: Int

    init(collection: SkillCollection, skillCount: Int) {
        self.id = collection.id ?? 0
        self.name = collection.name
        self.icon = collection.icon
        self.sortOrder = collection.sortOrder
        self.skillCount = skillCount
    }
}

struct CollectionDetailDTO: Content {
    var collection: CollectionDTO
    var skills: [SkillDTO]
}

struct CollectionCreateRequest: Content {
    var name: String
    var icon: String?
    var sortOrder: Int?
}

struct CollectionMembershipRequest: Content {
    var skillId: Int64
}

// MARK: - Assist

/// One compose turn: the front-end sends the open skill plus the editor buffer.
struct AssistRequest: Content {
    var skillId: Int64
    var prompt: String
    var agent: String?
    /// Current editor contents. Falls back to the stored skill content.
    var content: String?
}

/// The diff-review gate. `pendingId` is nil when the agent replied with prose only
/// (no file proposal), in which case `fullFile` is nil too.
struct AssistResponse: Content {
    var pendingId: String?
    var summary: String
    var fullFile: String?
    var path: String?
    var agent: String
    var skillId: Int64
}

struct AssistAcceptResponse: Content {
    var accepted: Bool
    var pendingId: String
    var path: String
    var skill: SkillDTO?
}

struct AssistRejectResponse: Content {
    var rejected: Bool
    var pendingId: String
}

// MARK: - Registry

struct RegistrySkillDTO: Content {
    var skillId: String
    var name: String
    var installs: Int
    var source: String
    var isOfficial: Bool?

    init(skill: SkillRegistry.RegistrySkill) {
        self.skillId = skill.skillId
        self.name = skill.name
        self.installs = skill.installs
        self.source = skill.source
        self.isOfficial = skill.isOfficial
    }

    func asRegistrySkill() -> SkillRegistry.RegistrySkill {
        SkillRegistry.RegistrySkill(
            skillId: skillId,
            name: name,
            installs: installs,
            source: source,
            isOfficial: isOfficial
        )
    }
}

struct RegistryInstallRequest: Content {
    var skillId: String
    var name: String
    var source: String
    var installs: Int?
    var isOfficial: Bool?
    /// Tool raw values (`claude`, `codex`, …). Omitted = every installed tool.
    var targets: [String]?
}

struct RegistryInstallResponse: Content {
    var installed: Bool
    var skillName: String
    var path: String
    var targets: [String]
    var skill: SkillDTO?
}

// MARK: - Remote servers (SSH)

struct RemoteServerDTO: Content {
    var id: String
    var label: String
    var host: String
    var port: Int
    var username: String
    var skillsBasePath: String
    var sshKeyPath: String?
    var lastSyncDate: Date?
    var lastSyncError: String?

    init(server: RemoteServer) {
        self.id = server.id
        self.label = server.label
        self.host = server.host
        self.port = server.port
        self.username = server.username
        self.skillsBasePath = server.skillsBasePath
        self.sshKeyPath = server.sshKeyPath
        self.lastSyncDate = server.lastSyncDate
        self.lastSyncError = server.lastSyncError
    }
}

struct RemoteServerRequest: Content {
    var id: String?
    var label: String
    var host: String
    var port: Int?
    var username: String
    var skillsBasePath: String
    var sshKeyPath: String?
}

struct RemoteBrowseRequest: Content {
    var serverId: String
}

struct RemoteSkillDTO: Content {
    var path: String
    var name: String
    var description: String
    var content: String
}

struct RemoteBrowseResponse: Content {
    var serverId: String
    var skills: [RemoteSkillDTO]
    var lastSyncDate: Date
}

struct RemoteInstallRequest: Content {
    var serverId: String
    var remotePath: String
    var targets: [String]?
}

// MARK: - Settings

struct SettingsDTO: Content {
    var sotDir: String
    var scanRoots: [String]
    var includePluginSkills: Bool
    var theme: String
}

/// `PUT /api/settings` accepts any subset of the mutable fields.
struct SettingsUpdateRequest: Content {
    var sotDir: String?
    var scanRoots: [String]?
    var includePluginSkills: Bool?
    var theme: String?
}

struct SettingsResponse: Content {
    var sotDir: String
    var scanRoots: [String]
    var includePluginSkills: Bool
    var theme: String
    /// Read-only locations, exposed so the settings page can display them.
    var homeDirectory: String
    var settingsPath: String
    var databasePath: String
}

// MARK: - Generic

struct DeleteResponse: Content {
    var deleted: Bool
}

struct MembershipResponse: Content {
    var added: Bool?
    var removed: Bool?
}
