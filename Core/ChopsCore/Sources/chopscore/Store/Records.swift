import Foundation
import GRDB

// Typed records mirroring the frozen SwiftData schema (`Chops/Models/SchemaVersions.swift`)
// plus the agent `PendingWrite` value type. Relationship properties are exposed through
// `ChopsStore` queries (junction/fetch methods) instead of being encoded as columns.

/// Ported from `SchemaV1.Skill` (`Chops/Models/SchemaVersions.swift`).
public struct Skill: Identifiable, Hashable, Sendable {
    public var id: Int64?
    /// SwiftData `@Attribute(.unique) var resolvedPath` → `skills.resolved_path UNIQUE`.
    public var resolvedPath: String
    public var filePath: String
    public var isDirectory: Bool
    public var name: String
    public var skillDescription: String
    public var content: String
    public var frontmatterData: Data?
    /// Collections this skill belongs to (junction table `skill_collection_membership`).
    /// Populated by `ChopsStore` fetch methods; not a column on `skills`.
    public var collections: [SkillCollection]
    public var isFavorite: Bool
    public var lastOpened: Date?
    public var fileModifiedDate: Date
    public var fileSize: Int
    public var isGlobal: Bool
    /// Foreign key into `remote_servers.id` (SwiftData `remoteServer` relationship).
    public var remoteServerID: String?
    public var remotePath: String?
    public var toolSourcesRaw: String
    public var installedPathsData: Data?
    /// Raw `ItemKind` value; defaults to `skill` exactly like the SwiftData model.
    public var kind: String

    public init(
        filePath: String,
        resolvedPath: String = "",
        isDirectory: Bool = false,
        name: String = "",
        skillDescription: String = "",
        content: String = "",
        frontmatterData: Data? = nil,
        collections: [SkillCollection] = [],
        isFavorite: Bool = false,
        lastOpened: Date? = nil,
        fileModifiedDate: Date = .now,
        fileSize: Int = 0,
        isGlobal: Bool = true,
        remoteServerID: String? = nil,
        remotePath: String? = nil,
        toolSourcesRaw: String = "",
        installedPathsData: Data? = nil,
        kind: String = "skill"
    ) {
        self.id = nil
        self.resolvedPath = resolvedPath.isEmpty ? filePath : resolvedPath
        self.filePath = filePath
        self.isDirectory = isDirectory
        self.name = name
        self.skillDescription = skillDescription
        self.content = content
        self.frontmatterData = frontmatterData
        self.collections = collections
        self.isFavorite = isFavorite
        self.lastOpened = lastOpened
        self.fileModifiedDate = fileModifiedDate
        self.fileSize = fileSize
        self.isGlobal = isGlobal
        self.remoteServerID = remoteServerID
        self.remotePath = remotePath
        self.toolSourcesRaw = toolSourcesRaw
        self.installedPathsData = installedPathsData
        self.kind = kind
    }
}

extension Skill: TableRecord {
    public static let databaseTableName = "skills"
}

extension Skill: FetchableRecord {
    public init(row: Row) {
        id = row["id"]
        resolvedPath = row["resolved_path"]
        filePath = row["file_path"]
        isDirectory = row["is_directory"]
        name = row["name"]
        skillDescription = row["skill_description"]
        content = row["content"]
        frontmatterData = row["frontmatter_data"]
        collections = []
        isFavorite = row["is_favorite"]
        lastOpened = row["last_opened"]
        fileModifiedDate = row["file_modified_date"]
        fileSize = row["file_size"]
        isGlobal = row["is_global"]
        remoteServerID = row["remote_server_id"]
        remotePath = row["remote_path"]
        toolSourcesRaw = row["tool_sources_raw"]
        installedPathsData = row["installed_paths_data"]
        kind = row["kind"]
    }
}

extension Skill: MutablePersistableRecord {
    public func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["resolved_path"] = resolvedPath
        container["file_path"] = filePath
        container["is_directory"] = isDirectory
        container["name"] = name
        container["skill_description"] = skillDescription
        container["content"] = content
        container["frontmatter_data"] = frontmatterData
        container["is_favorite"] = isFavorite
        container["last_opened"] = lastOpened
        container["file_modified_date"] = fileModifiedDate
        container["file_size"] = fileSize
        container["is_global"] = isGlobal
        container["remote_server_id"] = remoteServerID
        container["remote_path"] = remotePath
        container["tool_sources_raw"] = toolSourcesRaw
        container["installed_paths_data"] = installedPathsData
        container["kind"] = kind
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Ported from `SchemaV1.SkillCollection`.
public struct SkillCollection: Identifiable, Hashable, Sendable {
    public var id: Int64?
    /// SwiftData `@Attribute(.unique) var name` → `skill_collections.name UNIQUE`.
    public var name: String
    public var icon: String
    public var sortOrder: Int

    public init(id: Int64? = nil, name: String, icon: String = "folder", sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.icon = icon
        self.sortOrder = sortOrder
    }
}

extension SkillCollection: TableRecord {
    public static let databaseTableName = "skill_collections"
}

extension SkillCollection: FetchableRecord {
    public init(row: Row) {
        id = row["id"]
        name = row["name"]
        icon = row["icon"]
        sortOrder = row["sort_order"]
    }
}

extension SkillCollection: MutablePersistableRecord {
    public func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["name"] = name
        container["icon"] = icon
        container["sort_order"] = sortOrder
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Ported from `SchemaV1.RemoteServer`.
public struct RemoteServer: Identifiable, Hashable, Sendable {
    /// SwiftData `@Attribute(.unique) var id: String` (UUID string).
    public var id: String
    public var label: String
    public var host: String
    public var port: Int
    public var username: String
    public var skillsBasePath: String
    public var sshKeyPath: String?
    public var lastSyncDate: Date?
    public var lastSyncError: String?

    public init(
        id: String = UUID().uuidString,
        label: String,
        host: String,
        port: Int = 22,
        username: String,
        skillsBasePath: String,
        sshKeyPath: String? = nil,
        lastSyncDate: Date? = nil,
        lastSyncError: String? = nil
    ) {
        self.id = id
        self.label = label
        self.host = host
        self.port = port
        self.username = username
        self.skillsBasePath = skillsBasePath
        self.sshKeyPath = sshKeyPath
        self.lastSyncDate = lastSyncDate
        self.lastSyncError = lastSyncError
    }
}

extension RemoteServer: TableRecord {
    public static let databaseTableName = "remote_servers"
}

extension RemoteServer: FetchableRecord {
    public init(row: Row) {
        id = row["id"]
        label = row["label"]
        host = row["host"]
        port = row["port"]
        username = row["username"]
        skillsBasePath = row["skills_base_path"]
        sshKeyPath = row["ssh_key_path"]
        lastSyncDate = row["last_sync_date"]
        lastSyncError = row["last_sync_error"]
    }
}

extension RemoteServer: PersistableRecord {
    public func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["label"] = label
        container["host"] = host
        container["port"] = port
        container["username"] = username
        container["skills_base_path"] = skillsBasePath
        container["ssh_key_path"] = sshKeyPath
        container["last_sync_date"] = lastSyncDate
        container["last_sync_error"] = lastSyncError
    }
}

/// Ported from the agent `PendingWrite` value type
/// (`Chops/Services/Agents/AgentTypes.swift`), keyed by `pendingId` so the
/// chopsd contract can accept/reject a write by id.
public struct PendingWrite: Identifiable, Hashable, Sendable {
    public var pendingId: String
    public var path: String
    public var content: String
    public var originalText: String?
    public var originalData: Data?
    public var existedBefore: Bool
    /// True when the agent itself performed the disk write; on reject the UI
    /// restores from the captured snapshot.
    public var agentDidWrite: Bool
    public var createdAt: Date

    public var id: String { pendingId }

    public init(
        pendingId: String = UUID().uuidString,
        path: String,
        content: String,
        originalText: String? = nil,
        originalData: Data? = nil,
        existedBefore: Bool = false,
        agentDidWrite: Bool = false,
        createdAt: Date = .now
    ) {
        self.pendingId = pendingId
        self.path = path
        self.content = content
        self.originalText = originalText
        self.originalData = originalData
        self.existedBefore = existedBefore
        self.agentDidWrite = agentDidWrite
        self.createdAt = createdAt
    }
}

extension PendingWrite: TableRecord {
    public static let databaseTableName = "pending_writes"
}

extension PendingWrite: FetchableRecord {
    public init(row: Row) {
        pendingId = row["pending_id"]
        path = row["path"]
        content = row["content"]
        originalText = row["original_text"]
        originalData = row["original_data"]
        existedBefore = row["existed_before"]
        agentDidWrite = row["agent_did_write"]
        createdAt = row["created_at"]
    }
}

extension PendingWrite: PersistableRecord {
    public func encode(to container: inout PersistenceContainer) throws {
        container["pending_id"] = pendingId
        container["path"] = path
        container["content"] = content
        container["original_text"] = originalText
        container["original_data"] = originalData
        container["existed_before"] = existedBefore
        container["agent_did_write"] = agentDidWrite
        container["created_at"] = createdAt
    }
}
