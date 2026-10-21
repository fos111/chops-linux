import Foundation
import GRDB
import XCTest

@testable import chopscore

/// Typed CRUD roundtrips + constraint enforcement (plan T05).
final class StoreCRUDTests: StoreTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000) // whole seconds: TEXT roundtrip-exact
    private let otherDate = Date(timeIntervalSince1970: 1_710_000_000)

    // MARK: - Schema

    func testSchemaContainsEveryMirroredTable() throws {
        let store = try StoreTestSupport.store(in: try scratch)
        XCTAssertEqual(
            try store.tableNames(),
            [
                "pending_writes",
                "remote_servers",
                "skill_collection_membership",
                "skill_collections",
                "skills",
            ]
        )
    }

    // MARK: - Skills

    private func makeSkill(
        filePath: String = "/fixture/home/.claude/skills/a-one.md",
        resolvedPath: String = "",
        name: String = "a-one"
    ) -> Skill {
        Skill(
            filePath: filePath,
            resolvedPath: resolvedPath,
            isDirectory: false,
            name: name,
            skillDescription: "skill a",
            content: "---\nname: a-one\n---\nbody",
            frontmatterData: Data([0x7B, 0x7D]),
            isFavorite: false,
            lastOpened: nil,
            fileModifiedDate: fixedDate,
            fileSize: 42,
            isGlobal: true,
            remotePath: nil,
            toolSourcesRaw: "claude",
            installedPathsData: Data([0x2F, 0x61]),
            kind: "skill"
        )
    }

    func testSkillRoundtripPreservesEveryColumn() throws {
        let store = try StoreTestSupport.store(in: try scratch)
        let skill = makeSkill()

        let inserted = try store.insertSkill(skill)
        let id = try XCTUnwrap(inserted.id)

        let fetched = try XCTUnwrap(try store.fetchSkill(id: id))
        XCTAssertEqual(fetched.resolvedPath, skill.filePath) // resolvedPath defaulted to filePath
        XCTAssertEqual(fetched.filePath, skill.filePath)
        XCTAssertEqual(fetched.isDirectory, false)
        XCTAssertEqual(fetched.name, "a-one")
        XCTAssertEqual(fetched.skillDescription, "skill a")
        XCTAssertEqual(fetched.content, skill.content)
        XCTAssertEqual(fetched.frontmatterData, Data([0x7B, 0x7D]))
        XCTAssertEqual(fetched.collections, [])
        XCTAssertEqual(fetched.isFavorite, false)
        XCTAssertNil(fetched.lastOpened)
        XCTAssertEqual(fetched.fileModifiedDate, fixedDate)
        XCTAssertEqual(fetched.fileSize, 42)
        XCTAssertEqual(fetched.isGlobal, true)
        XCTAssertNil(fetched.remoteServerID)
        XCTAssertNil(fetched.remotePath)
        XCTAssertEqual(fetched.toolSourcesRaw, "claude")
        XCTAssertEqual(fetched.installedPathsData, Data([0x2F, 0x61]))
        XCTAssertEqual(fetched.kind, "skill")

        let byPath = try XCTUnwrap(try store.fetchSkill(resolvedPath: skill.filePath))
        XCTAssertEqual(byPath.id, id)
        XCTAssertEqual(try store.fetchSkills().count, 1)
    }

    func testSkillUpdateRoundtripThenDelete() throws {
        let store = try StoreTestSupport.store(in: try scratch)
        var skill = try store.insertSkill(makeSkill())
        let id = try XCTUnwrap(skill.id)

        skill.name = "a-one-renamed"
        skill.content = "updated"
        skill.isFavorite = true
        skill.lastOpened = otherDate
        skill.fileSize = 99
        try store.updateSkill(skill)

        let fetched = try XCTUnwrap(try store.fetchSkill(id: id))
        XCTAssertEqual(fetched.name, "a-one-renamed")
        XCTAssertEqual(fetched.content, "updated")
        XCTAssertEqual(fetched.isFavorite, true)
        XCTAssertEqual(fetched.lastOpened, otherDate)
        XCTAssertEqual(fetched.fileSize, 99)

        XCTAssertTrue(try store.deleteSkill(id: id))
        XCTAssertNil(try store.fetchSkill(id: id))
        XCTAssertFalse(try store.deleteSkill(id: id))
    }

    func testSkillUpdateWithoutPrimaryKeyThrows() throws {
        let store = try StoreTestSupport.store(in: try scratch)
        XCTAssertThrowsError(try store.updateSkill(makeSkill())) { error in
            XCTAssertEqual(error as? StoreError, .missingPrimaryKey("skills.id"))
        }
    }

    func testSkillsUniqueResolvedPathConstraint() throws {
        let store = try StoreTestSupport.store(in: try scratch)
        _ = try store.insertSkill(makeSkill(filePath: "/fixture/a.md"))

        XCTAssertThrowsError(
            try store.insertSkill(makeSkill(filePath: "/fixture/b.md", resolvedPath: "/fixture/a.md"))
        ) { error in
            guard let dbError = error as? DatabaseError else {
                return XCTFail("expected GRDB DatabaseError, got \(error)")
            }
            XCTAssertEqual(dbError.extendedResultCode, DatabaseError.SQLITE_CONSTRAINT_UNIQUE)
            XCTAssertTrue(
                dbError.message?.contains("UNIQUE constraint failed: skills.resolved_path") == true,
                "unexpected message: \(dbError.message ?? "nil")"
            )
        }
        XCTAssertEqual(try store.fetchSkills().count, 1)
    }

    func testSkillForeignKeyRequiresExistingRemoteServer() throws {
        let store = try StoreTestSupport.store(in: try scratch)
        var skill = makeSkill()
        skill.remoteServerID = "missing-server"

        XCTAssertThrowsError(try store.insertSkill(skill)) { error in
            guard let dbError = error as? DatabaseError else {
                return XCTFail("expected GRDB DatabaseError, got \(error)")
            }
            XCTAssertEqual(dbError.extendedResultCode, DatabaseError.SQLITE_CONSTRAINT_FOREIGNKEY)
        }
    }

    // MARK: - Collections

    func testCollectionRoundtripAndUniqueNameConstraint() throws {
        let store = try StoreTestSupport.store(in: try scratch)

        var collection = try store.insertCollection(
            SkillCollection(name: "team", icon: "star", sortOrder: 3)
        )
        let id = try XCTUnwrap(collection.id)
        XCTAssertEqual(try store.fetchCollection(id: id), collection)
        XCTAssertEqual(try store.fetchCollection(name: "team"), collection)
        XCTAssertEqual(try store.fetchCollections(), [collection])

        collection.name = "team-renamed"
        collection.icon = "bolt"
        collection.sortOrder = 1
        try store.updateCollection(collection)
        XCTAssertEqual(try store.fetchCollection(id: id), collection)

        XCTAssertThrowsError(try store.insertCollection(SkillCollection(name: "team-renamed"))) { error in
            guard let dbError = error as? DatabaseError else {
                return XCTFail("expected GRDB DatabaseError, got \(error)")
            }
            XCTAssertEqual(dbError.extendedResultCode, DatabaseError.SQLITE_CONSTRAINT_UNIQUE)
            XCTAssertTrue(
                dbError.message?.contains("UNIQUE constraint failed: skill_collections.name") == true
            )
        }

        XCTAssertTrue(try store.deleteCollection(id: id))
        XCTAssertNil(try store.fetchCollection(id: id))
    }

    func testMembershipRoundtripAndCascade() throws {
        let store = try StoreTestSupport.store(in: try scratch)
        let alpha = try store.insertCollection(SkillCollection(name: "alpha", sortOrder: 0))
        let beta = try store.insertCollection(SkillCollection(name: "beta", sortOrder: 1))
        let alphaID = try XCTUnwrap(alpha.id)
        let betaID = try XCTUnwrap(beta.id)

        let inserted = try store.insertSkill(makeSkill())
        let skillID = try XCTUnwrap(inserted.id)

        try store.addSkill(skillID, toCollection: betaID)
        try store.addSkill(skillID, toCollection: alphaID)
        try store.addSkill(skillID, toCollection: alphaID) // INSERT OR IGNORE: idempotent
        XCTAssertEqual(try store.collectionIDs(forSkillID: skillID), [alphaID, betaID].sorted())

        let fetched = try XCTUnwrap(try store.fetchSkill(id: skillID))
        XCTAssertEqual(fetched.collections.map(\.name), ["alpha", "beta"]) // sort_order ordering
        XCTAssertEqual(try store.fetchSkills(inCollection: alphaID).map(\.id), [skillID])

        XCTAssertTrue(try store.removeSkill(skillID, fromCollection: betaID))
        XCTAssertFalse(try store.removeSkill(skillID, fromCollection: betaID))
        XCTAssertEqual(try store.collectionIDs(forSkillID: skillID), [alphaID])

        // Deleting a collection removes membership but keeps the skill.
        XCTAssertTrue(try store.deleteCollection(id: alphaID))
        XCTAssertEqual(try store.collectionIDs(forSkillID: skillID), [])
        XCTAssertNotNil(try store.fetchSkill(id: skillID))
    }

    func testInsertSkillPersistsCollectionsWithIDs() throws {
        let store = try StoreTestSupport.store(in: try scratch)
        let collection = try store.insertCollection(SkillCollection(name: "seeded"))
        var skill = makeSkill()
        skill.collections = [collection]

        let inserted = try store.insertSkill(skill)
        XCTAssertEqual(inserted.collections.map(\.name), ["seeded"])
    }

    func testReplaceCollectionsForSkill() throws {
        let store = try StoreTestSupport.store(in: try scratch)
        let first = try store.insertCollection(SkillCollection(name: "first"))
        let second = try store.insertCollection(SkillCollection(name: "second"))
        let skill = try store.insertSkill(makeSkill())
        let skillID = try XCTUnwrap(skill.id)

        try store.replaceCollections(forSkillID: skillID, withCollectionIDs: [try XCTUnwrap(first.id)])
        XCTAssertEqual(try store.collectionIDs(forSkillID: skillID), [try XCTUnwrap(first.id)])

        try store.replaceCollections(
            forSkillID: skillID,
            withCollectionIDs: [try XCTUnwrap(first.id), try XCTUnwrap(second.id)]
        )
        XCTAssertEqual(
            try store.collectionIDs(forSkillID: skillID),
            [try XCTUnwrap(first.id), try XCTUnwrap(second.id)].sorted()
        )
    }

    // MARK: - Remote servers

    func testRemoteServerRoundtripUpdateAndCascadeDelete() throws {
        let store = try StoreTestSupport.store(in: try scratch)
        let server = RemoteServer(
            label: "builder",
            host: "builder.internal",
            port: 2222,
            username: "chops",
            skillsBasePath: "/home/chops/.claude/skills",
            sshKeyPath: "/home/chops/.ssh/id_ed25519"
        )

        let inserted = try store.insertRemoteServer(server)
        XCTAssertEqual(inserted.id, server.id)
        XCTAssertEqual(try store.fetchRemoteServer(id: server.id), server)
        XCTAssertEqual(try store.fetchRemoteServers(), [server])

        var updated = server
        updated.label = "builder-renamed"
        updated.lastSyncDate = fixedDate
        updated.lastSyncError = "timeout"
        try store.updateRemoteServer(updated)
        XCTAssertEqual(try store.fetchRemoteServer(id: server.id), updated)

        var skill = makeSkill()
        skill.remoteServerID = server.id
        skill.remotePath = "/home/chops/.claude/skills/a-one.md"
        let remoteSkill = try store.insertSkill(skill)
        XCTAssertEqual(try store.fetchSkills(remoteServerID: server.id).map(\.id), [remoteSkill.id])

        XCTAssertTrue(try store.deleteRemoteServer(id: server.id))
        XCTAssertNil(try store.fetchRemoteServer(id: server.id))
        XCTAssertNil(try store.fetchSkill(id: try XCTUnwrap(remoteSkill.id))) // cascade
    }

    // MARK: - Pending writes

    func testPendingWriteRoundtripAndDelete() throws {
        let store = try StoreTestSupport.store(in: try scratch)
        let write = PendingWrite(
            path: "/fixture/home/.claude/skills/a-one.md",
            content: "new file content",
            originalText: "old file content",
            originalData: Data([0x01, 0x02, 0x03]),
            existedBefore: true,
            agentDidWrite: true,
            createdAt: fixedDate
        )

        let inserted = try store.insertPendingWrite(write)
        XCTAssertEqual(inserted, write)
        XCTAssertEqual(try store.fetchPendingWrite(id: write.pendingId), write)
        XCTAssertEqual(try store.fetchPendingWrites(), [write])

        XCTAssertTrue(try store.deletePendingWrite(id: write.pendingId))
        XCTAssertFalse(try store.deletePendingWrite(id: write.pendingId))
        XCTAssertTrue(try store.fetchPendingWrites().isEmpty)

        _ = try store.insertPendingWrite(write)
        try store.deleteAllPendingWrites()
        XCTAssertTrue(try store.fetchPendingWrites().isEmpty)
    }

    func testPendingWriteDefaultsForNilOptionals() throws {
        let store = try StoreTestSupport.store(in: try scratch)
        let write = PendingWrite(
            path: "/fixture/new.md",
            content: "brand new",
            existedBefore: false,
            createdAt: fixedDate
        )

        let fetched = try XCTUnwrap(try store.insertPendingWrite(write))
        XCTAssertNil(fetched.originalText)
        XCTAssertNil(fetched.originalData)
        XCTAssertFalse(fetched.existedBefore)
        XCTAssertFalse(fetched.agentDidWrite)
    }

    // MARK: - Fixture home copy

    /// Opens the store against a copy of `linux/fixtures/home` under a temp XDG root,
    /// then (when requested by QA) exports the fixture database for `sqlite3 .schema`.
    func testFixtureHomeCopyUsesXdgStorePath() throws {
        let fixtureCopy = try StoreTestSupport.copyFixtureHome(into: try scratch)
        let xdgDataHome = try scratch.appendingPathComponent("xdg-data", isDirectory: true)

        let environment = [
            "XDG_DATA_HOME": xdgDataHome.path,
            "HOME": fixtureCopy.path,
        ]
        let expectedURL = try StoreLocation.databaseURL(environment: environment)
        let scratchPath = try scratch.path
        XCTAssertEqual(expectedURL.path, xdgDataHome.appendingPathComponent("Chops/chops.db").path)
        XCTAssertTrue(expectedURL.path.hasPrefix(scratchPath), "store must live inside the fixture scratch root")

        var store: ChopsStore? = try ChopsStore.openDefault(environment: environment)
        let collected = try XCTUnwrap(store)
        XCTAssertEqual(collected.databaseURL.path, expectedURL.path)

        _ = try collected.insertCollection(SkillCollection(name: "fixture"))
        _ = try collected.insertSkill(
            makeSkill(
                filePath: fixtureCopy.appendingPathComponent(".claude/skills/a-one.md").path
            )
        )
        _ = try collected.insertPendingWrite(
            PendingWrite(path: "/fixture/pending.md", content: "pending", createdAt: fixedDate)
        )
        XCTAssertEqual(try collected.tableNames().count, 5)
        store = nil // close the connection before exporting the file

        // Fixture home itself is read-only in tests: the copy still has its files.
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixtureCopy.appendingPathComponent(".claude/skills/a-one.md").path
            )
        )

        if let exportPath = ProcessInfo.processInfo.environment["CHOPS_T05_EVIDENCE_DB"],
           !exportPath.isEmpty {
            let exportURL = URL(fileURLWithPath: exportPath)
            try FileManager.default.createDirectory(
                at: exportURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: exportURL)
            try FileManager.default.copyItem(at: expectedURL, to: exportURL)
            print("T05 fixture database exported to \(exportURL.path)")
        }
    }
}
