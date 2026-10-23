import Foundation
import GRDB

/// Typed CRUD over the fresh Linux SQLite store (plan T05).
///
/// Database: `${XDG_DATA_HOME:-$HOME/.local/share}/Chops/chops.db` (see `StoreLocation`).
/// There are no migrations and no `default.store` import: `StoreSchema` creates the
/// tables when the database file is absent, and an existing database is used as-is.
///
/// All access is serialized through a `DatabaseQueue`; the store is safe to share
/// across chopsd request handlers. Records are plain value types (see `Records.swift`).
public final class ChopsStore: Sendable {
    /// Absolute path of the open SQLite file (useful for QA/logging).
    public let databaseURL: URL

    private let dbQueue: DatabaseQueue

    /// Opens (or creates) the store at `databaseURL`.
    public init(databaseURL: URL) throws {
        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.busyMode = .timeout(5)

        self.databaseURL = databaseURL
        self.dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        try dbQueue.write { db in
            try StoreSchema.create(in: db)
        }
    }

    /// Opens the default XDG store. Tests must inject a fixture environment.
    public static func openDefault(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ChopsStore {
        try ChopsStore(databaseURL: StoreLocation.databaseURL(environment: environment))
    }

    // MARK: - Introspection

    /// User table names in the store (excludes SQLite's internal tables).
    public func tableNames() throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
                ORDER BY name
                """
            )
        }
    }

    // MARK: - Skills

    /// Inserts a skill. Membership rows are written for any `collections` that already
    /// carry an `id`; collections without an id are ignored (create them first).
    @discardableResult
    public func insertSkill(_ skill: Skill) throws -> Skill {
        var record = skill
        var insertedID: Int64?
        try dbQueue.write { db in
            try record.insert(db)
            guard let skillID = record.id else {
                throw StoreError.missingPrimaryKey("skills.id")
            }
            insertedID = skillID
            for collection in skill.collections {
                guard let collectionID = collection.id else { continue }
                try Self.insertMembership(db, skillID: skillID, collectionID: collectionID)
            }
        }
        guard let id = insertedID else {
            throw StoreError.missingPrimaryKey("skills.id")
        }
        guard let fetched = try fetchSkill(id: id) else {
            throw StoreError.recordNotFound("skills.id=\(id)")
        }
        return fetched
    }

    /// Updates every column of an existing skill.
    /// Throws GRDB's `RecordError.recordNotFound` when the row is gone.
    public func updateSkill(_ skill: Skill) throws {
        guard skill.id != nil else { throw StoreError.missingPrimaryKey("skills.id") }
        try dbQueue.write { db in
            try skill.update(db)
        }
    }

    /// Inserts when `id` is nil, otherwise updates.
    @discardableResult
    public func saveSkill(_ skill: Skill) throws -> Skill {
        guard let id = skill.id else {
            return try insertSkill(skill)
        }
        try updateSkill(skill)
        guard let fetched = try fetchSkill(id: id) else {
            throw StoreError.recordNotFound("skills.id=\(id)")
        }
        return fetched
    }

    public func fetchSkill(id: Int64) throws -> Skill? {
        try dbQueue.read { db in
            guard let skill = try Skill.fetchOne(db, key: id) else { return nil }
            return try Self.attachCollections([skill], db: db).first
        }
    }

    public func fetchSkill(resolvedPath: String) throws -> Skill? {
        try dbQueue.read { db in
            guard let skill = try Skill
                .filter(Column("resolved_path") == resolvedPath)
                .fetchOne(db) else { return nil }
            return try Self.attachCollections([skill], db: db).first
        }
    }

    public func fetchSkills() throws -> [Skill] {
        try dbQueue.read { db in
            let skills = try Skill
                .order(Column("name").collating(.nocase), Column("id"))
                .fetchAll(db)
            return try Self.attachCollections(skills, db: db)
        }
    }

    public func fetchSkills(remoteServerID: String) throws -> [Skill] {
        try dbQueue.read { db in
            let skills = try Skill
                .filter(Column("remote_server_id") == remoteServerID)
                .order(Column("name").collating(.nocase), Column("id"))
                .fetchAll(db)
            return try Self.attachCollections(skills, db: db)
        }
    }

    @discardableResult
    public func deleteSkill(id: Int64) throws -> Bool {
        try dbQueue.write { db in
            try Skill.deleteOne(db, key: id)
        }
    }

    // MARK: - Skill ↔ collection membership

    public func addSkill(_ skillID: Int64, toCollection collectionID: Int64) throws {
        try dbQueue.write { db in
            try Self.insertMembership(db, skillID: skillID, collectionID: collectionID)
        }
    }

    @discardableResult
    public func removeSkill(_ skillID: Int64, fromCollection collectionID: Int64) throws -> Bool {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                DELETE FROM skill_collection_membership
                WHERE skill_id = ? AND collection_id = ?
                """,
                arguments: [skillID, collectionID]
            )
            return db.changesCount > 0
        }
    }

    /// Replaces a skill's collection membership in one transaction.
    public func replaceCollections(forSkillID skillID: Int64, withCollectionIDs collectionIDs: [Int64]) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM skill_collection_membership WHERE skill_id = ?",
                arguments: [skillID]
            )
            for collectionID in collectionIDs {
                try Self.insertMembership(db, skillID: skillID, collectionID: collectionID)
            }
        }
    }

    public func collectionIDs(forSkillID skillID: Int64) throws -> [Int64] {
        try dbQueue.read { db in
            try Int64.fetchAll(
                db,
                sql: """
                SELECT collection_id FROM skill_collection_membership
                WHERE skill_id = ? ORDER BY collection_id
                """,
                arguments: [skillID]
            )
        }
    }

    // MARK: - Collections

    @discardableResult
    public func insertCollection(_ collection: SkillCollection) throws -> SkillCollection {
        var record = collection
        var insertedID: Int64?
        try dbQueue.write { db in
            try record.insert(db)
            guard let collectionID = record.id else {
                throw StoreError.missingPrimaryKey("skill_collections.id")
            }
            insertedID = collectionID
        }
        guard let id = insertedID else {
            throw StoreError.missingPrimaryKey("skill_collections.id")
        }
        guard let fetched = try fetchCollection(id: id) else {
            throw StoreError.recordNotFound("skill_collections.id=\(id)")
        }
        return fetched
    }

    public func updateCollection(_ collection: SkillCollection) throws {
        guard collection.id != nil else { throw StoreError.missingPrimaryKey("skill_collections.id") }
        try dbQueue.write { db in
            try collection.update(db)
        }
    }

    @discardableResult
    public func saveCollection(_ collection: SkillCollection) throws -> SkillCollection {
        guard let id = collection.id else {
            return try insertCollection(collection)
        }
        try updateCollection(collection)
        guard let fetched = try fetchCollection(id: id) else {
            throw StoreError.recordNotFound("skill_collections.id=\(id)")
        }
        return fetched
    }

    public func fetchCollection(id: Int64) throws -> SkillCollection? {
        try dbQueue.read { db in
            try SkillCollection.fetchOne(db, key: id)
        }
    }

    public func fetchCollection(name: String) throws -> SkillCollection? {
        try dbQueue.read { db in
            try SkillCollection.filter(Column("name") == name).fetchOne(db)
        }
    }

    public func fetchCollections() throws -> [SkillCollection] {
        try dbQueue.read { db in
            try SkillCollection
                .order(Column("sort_order"), Column("name").collating(.nocase))
                .fetchAll(db)
        }
    }

    @discardableResult
    public func deleteCollection(id: Int64) throws -> Bool {
        try dbQueue.write { db in
            try SkillCollection.deleteOne(db, key: id)
        }
    }

    public func fetchSkills(inCollection collectionID: Int64) throws -> [Skill] {
        try dbQueue.read { db in
            let skills = try Skill.fetchAll(
                db,
                sql: """
                SELECT s.* FROM skills s
                JOIN skill_collection_membership m ON m.skill_id = s.id
                WHERE m.collection_id = ?
                ORDER BY s.name COLLATE NOCASE, s.id
                """,
                arguments: [collectionID]
            )
            return try Self.attachCollections(skills, db: db)
        }
    }

    // MARK: - Remote servers

    @discardableResult
    public func insertRemoteServer(_ server: RemoteServer) throws -> RemoteServer {
        try dbQueue.write { db in
            try server.insert(db)
        }
        guard let fetched = try fetchRemoteServer(id: server.id) else {
            throw StoreError.recordNotFound("remote_servers.id=\(server.id)")
        }
        return fetched
    }

    public func updateRemoteServer(_ server: RemoteServer) throws {
        try dbQueue.write { db in
            try server.update(db)
        }
    }

    @discardableResult
    public func saveRemoteServer(_ server: RemoteServer) throws -> RemoteServer {
        guard try fetchRemoteServer(id: server.id) != nil else {
            return try insertRemoteServer(server)
        }
        try updateRemoteServer(server)
        guard let fetched = try fetchRemoteServer(id: server.id) else {
            throw StoreError.recordNotFound("remote_servers.id=\(server.id)")
        }
        return fetched
    }

    public func fetchRemoteServer(id: String) throws -> RemoteServer? {
        try dbQueue.read { db in
            try RemoteServer.fetchOne(db, key: id)
        }
    }

    public func fetchRemoteServers() throws -> [RemoteServer] {
        try dbQueue.read { db in
            try RemoteServer.order(Column("label").collating(.nocase), Column("id")).fetchAll(db)
        }
    }

    /// Deletes a server; its skills are deleted too (`ON DELETE CASCADE`, mirroring
    /// the SwiftData `@Relationship(deleteRule: .cascade)`).
    @discardableResult
    public func deleteRemoteServer(id: String) throws -> Bool {
        try dbQueue.write { db in
            try RemoteServer.deleteOne(db, key: id)
        }
    }

    // MARK: - Pending agent writes

    @discardableResult
    public func insertPendingWrite(_ write: PendingWrite) throws -> PendingWrite {
        try dbQueue.write { db in
            try write.insert(db)
        }
        guard let fetched = try fetchPendingWrite(id: write.pendingId) else {
            throw StoreError.recordNotFound("pending_writes.pending_id=\(write.pendingId)")
        }
        return fetched
    }

    public func fetchPendingWrite(id: String) throws -> PendingWrite? {
        try dbQueue.read { db in
            try PendingWrite.fetchOne(db, key: id)
        }
    }

    public func fetchPendingWrites() throws -> [PendingWrite] {
        try dbQueue.read { db in
            try PendingWrite
                .order(Column("created_at"), Column("pending_id"))
                .fetchAll(db)
        }
    }

    @discardableResult
    public func deletePendingWrite(id: String) throws -> Bool {
        try dbQueue.write { db in
            try PendingWrite.deleteOne(db, key: id)
        }
    }

    public func deleteAllPendingWrites() throws {
        try dbQueue.write { db in
            _ = try PendingWrite.deleteAll(db)
        }
    }

    // MARK: - Helpers

    private static func insertMembership(_ db: Database, skillID: Int64, collectionID: Int64) throws {
        try db.execute(
            sql: """
            INSERT OR IGNORE INTO skill_collection_membership (skill_id, collection_id)
            VALUES (?, ?)
            """,
            arguments: [skillID, collectionID]
        )
    }

    private static func attachCollections(_ skills: [Skill], db: Database) throws -> [Skill] {
        guard !skills.isEmpty else { return skills }

        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT m.skill_id, c.id, c.name, c.icon, c.sort_order
            FROM skill_collection_membership m
            JOIN skill_collections c ON c.id = m.collection_id
            ORDER BY c.sort_order, c.name COLLATE NOCASE, c.id
            """
        )

        var collectionsBySkill: [Int64: [SkillCollection]] = [:]
        for row in rows {
            let skillID: Int64 = row["skill_id"]
            collectionsBySkill[skillID, default: []].append(
                SkillCollection(
                    id: row["id"],
                    name: row["name"],
                    icon: row["icon"],
                    sortOrder: row["sort_order"]
                )
            )
        }

        return skills.map { skill in
            var copy = skill
            if let id = skill.id {
                copy.collections = collectionsBySkill[id] ?? []
            }
            return copy
        }
    }
}

/// Errors thrown before SQLite is reached.
public enum StoreError: Error, Equatable, CustomStringConvertible {
    /// An update was attempted on a record that was never inserted.
    case missingPrimaryKey(String)
    /// A write reported success but the record could not be read back.
    case recordNotFound(String)

    public var description: String {
        switch self {
        case .missingPrimaryKey(let column):
            return "Cannot update a record without a primary key (\(column))."
        case .recordNotFound(let record):
            return "Record not found after write (\(record))."
        }
    }
}
