// Collection CRUD + membership (fixed UI↔chopsd contract).
//
// GRDB backs both the collection table and the `skill_collection_membership` junction;
// deleting a collection cascades its membership rows (schema FK), while deleting a
// skill never deletes the collection.

import Foundation
import Vapor
import chopscore

extension ChopsdRuntime {
    func collections() throws -> [CollectionDTO] {
        try store.fetchCollections().compactMap { collection in
            guard let id = collection.id else { return nil }
            let count = try store.fetchSkills(inCollection: id).count
            return CollectionDTO(collection: collection, skillCount: count)
        }
    }

    func collection(id: Int64) throws -> CollectionDetailDTO {
        guard let collection = try store.fetchCollection(id: id) else {
            throw Abort(.notFound, reason: "No collection with id \(id).")
        }
        let skills = try store.fetchSkills(inCollection: id).map(SkillDTO.init(skill:))
        let count = skills.count
        return CollectionDetailDTO(
            collection: CollectionDTO(collection: collection, skillCount: count),
            skills: skills
        )
    }

    func createCollection(_ request: CollectionCreateRequest) throws -> CollectionDTO {
        let name = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw Abort(.badRequest, reason: "name must not be empty.")
        }
        if try store.fetchCollection(name: name) != nil {
            throw Abort(.conflict, reason: "A collection named '\(name)' already exists.")
        }
        let collection = try store.insertCollection(
            SkillCollection(
                name: name,
                icon: request.icon ?? "folder",
                sortOrder: request.sortOrder ?? 0
            )
        )
        return CollectionDTO(collection: collection, skillCount: 0)
    }

    func deleteCollection(id: Int64) throws -> Bool {
        guard try store.fetchCollection(id: id) != nil else {
            throw Abort(.notFound, reason: "No collection with id \(id).")
        }
        return try store.deleteCollection(id: id)
    }

    func addMembership(collectionID: Int64, skillID: Int64) throws -> Bool {
        guard try store.fetchCollection(id: collectionID) != nil else {
            throw Abort(.notFound, reason: "No collection with id \(collectionID).")
        }
        guard try store.fetchSkill(id: skillID) != nil else {
            throw Abort(.notFound, reason: "No skill with id \(skillID).")
        }
        try store.addSkill(skillID, toCollection: collectionID)
        return true
    }

    func removeMembership(collectionID: Int64, skillID: Int64) throws -> Bool {
        guard try store.fetchCollection(id: collectionID) != nil else {
            throw Abort(.notFound, reason: "No collection with id \(collectionID).")
        }
        return try store.removeSkill(skillID, fromCollection: collectionID)
    }
}
