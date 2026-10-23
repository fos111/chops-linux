import GRDB

/// Schema for the Linux store (plan T05).
///
/// Ported field-for-field from the frozen SwiftData models in
/// `Chops/Models/SchemaVersions.swift`:
///
/// - `skills` ← `SchemaV1.Skill` (with `UNIQUE(resolved_path)`)
/// - `skill_collections` ← `SchemaV1.SkillCollection` (with `UNIQUE(name)`)
/// - `remote_servers` ← `SchemaV1.RemoteServer` (with `UNIQUE(id)`)
/// - `pending_writes` ← `PendingWrite` (`Chops/Services/Agents/AgentTypes.swift`)
///
/// Relationships become foreign keys instead of SwiftData implicit join rows:
/// skills → remote_servers (`ON DELETE CASCADE`, mirroring the model's cascade rule)
/// and the many-to-many skill ↔ collection membership table.
///
/// This is a **fresh-only** schema: every statement is `IF NOT EXISTS`, and there is
/// no version table, no migration stages, and no `default.store` import. A database
/// is either absent (and created here) or already current. Anything else is a
/// programming error we cannot paper over — the store is recreated, not migrated.
enum StoreSchema {
    static let statements = [
        // Order matters: remote_servers is referenced by skills.
        """
        CREATE TABLE IF NOT EXISTS remote_servers (
            id TEXT PRIMARY KEY NOT NULL,
            label TEXT NOT NULL,
            host TEXT NOT NULL,
            port INTEGER NOT NULL DEFAULT 22,
            username TEXT NOT NULL,
            skills_base_path TEXT NOT NULL,
            ssh_key_path TEXT,
            last_sync_date DATETIME,
            last_sync_error TEXT
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS skills (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            resolved_path TEXT NOT NULL UNIQUE,
            file_path TEXT NOT NULL,
            is_directory INTEGER NOT NULL DEFAULT 0,
            name TEXT NOT NULL DEFAULT '',
            skill_description TEXT NOT NULL DEFAULT '',
            content TEXT NOT NULL DEFAULT '',
            frontmatter_data BLOB,
            is_favorite INTEGER NOT NULL DEFAULT 0,
            last_opened DATETIME,
            file_modified_date DATETIME NOT NULL,
            file_size INTEGER NOT NULL DEFAULT 0,
            is_global INTEGER NOT NULL DEFAULT 1,
            remote_server_id TEXT REFERENCES remote_servers(id) ON DELETE CASCADE,
            remote_path TEXT,
            tool_sources_raw TEXT NOT NULL DEFAULT '',
            installed_paths_data BLOB,
            kind TEXT NOT NULL DEFAULT 'skill'
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS skill_collections (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            icon TEXT NOT NULL DEFAULT 'folder',
            sort_order INTEGER NOT NULL DEFAULT 0
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS skill_collection_membership (
            skill_id INTEGER NOT NULL REFERENCES skills(id) ON DELETE CASCADE,
            collection_id INTEGER NOT NULL REFERENCES skill_collections(id) ON DELETE CASCADE,
            PRIMARY KEY (skill_id, collection_id)
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS pending_writes (
            pending_id TEXT PRIMARY KEY NOT NULL,
            path TEXT NOT NULL,
            content TEXT NOT NULL,
            original_text TEXT,
            original_data BLOB,
            existed_before INTEGER NOT NULL,
            agent_did_write INTEGER NOT NULL DEFAULT 0,
            created_at DATETIME NOT NULL
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_skills_remote_server ON skills(remote_server_id)",
        "CREATE INDEX IF NOT EXISTS idx_membership_collection ON skill_collection_membership(collection_id)",
    ]

    /// Creates the fresh-only schema. Idempotent; never alters existing tables.
    static func create(in db: Database) throws {
        for statement in statements {
            try db.execute(sql: statement)
        }
    }
}
