// HTTP surface for chopsd (plan T11).
//
// Every route is a thin hop onto `ChopsdRuntime`; all business logic, write gating,
// and rescan broadcasting lives in the actor. Routes are deliberately 1:1 with the
// fixed UI↔chopsd contract so the Tauri front-end and the smoke suite exercise the
// exact same table.

import Foundation
import Vapor
import chopscore

func configure(_ app: Application, runtime: ChopsdRuntime) throws {
    app.http.server.configuration.hostname = "127.0.0.1"
    app.http.server.configuration.port = try ChopsdPort.resolve(environment: ProcessInfo.processInfo.environment)
    // Skill files are full Markdown documents; the 16 KB Vapor default would reject
    // legitimate saves.
    app.routes.defaultMaxBodySize = "16mb"

    // The Tauri webview is a cross-origin client (tauri://localhost -> 127.0.0.1).
    // Keep it before ErrorMiddleware so even error responses carry CORS headers.
    app.middleware.use(TauriCORSMiddleware(), at: .beginning)

    routes(app, runtime: runtime)
}

enum ChopsdPort {
    static let defaultPort = 47115

    static func resolve(environment: [String: String]) throws -> Int {
        guard let raw = environment["CHOPSD_PORT"], !raw.isEmpty else {
            return defaultPort
        }
        guard let port = Int(raw), (1...65535).contains(port) else {
            throw ChopsdStartupError.invalidPort(raw)
        }
        return port
    }
}

enum ChopsdStartupError: Error, LocalizedError {
    case invalidPort(String)

    var errorDescription: String? {
        switch self {
        case .invalidPort(let raw):
            return "CHOPSD_PORT must be an integer between 1 and 65535 (got '\(raw)')."
        }
    }
}

private func routes(_ app: Application, runtime: ChopsdRuntime) {
    // MARK: Tools

    app.get("api", "tools") { _ async -> [ToolDTO] in
        await runtime.tools()
    }

    // MARK: Skills

    app.get("api", "skills") { req async throws -> [SkillDTO] in
        try await runtime.skills(
            tool: req.query[String.self, at: "tool"],
            query: req.query[String.self, at: "q"]
        )
    }

    app.get("api", "skills", ":id") { req async throws -> SkillDTO in
        try await runtime.skill(id: try pathID(req))
    }

    app.put("api", "skills", ":id") { req async throws -> SkillDTO in
        let id = try pathID(req)
        let body = try req.content.decode(SkillUpdateRequest.self)
        return try await runtime.updateSkill(id: id, content: body.content)
    }

    app.post("api", "skills") { req async throws -> SkillDTO in
        try await runtime.createSkill(try req.content.decode(SkillCreateRequest.self))
    }

    // MARK: Assist (diff gate)

    app.post("api", "assist") { req async throws -> AssistResponse in
        try await runtime.assist(try req.content.decode(AssistRequest.self))
    }

    app.post("api", "assist", ":pendingId", "accept") { req async throws -> AssistAcceptResponse in
        try await runtime.acceptAssist(pendingId: try pathString(req, "pendingId"))
    }

    app.post("api", "assist", ":pendingId", "reject") { req async throws -> AssistRejectResponse in
        try await runtime.rejectAssist(pendingId: try pathString(req, "pendingId"))
    }

    // MARK: Collections

    app.get("api", "collections") { _ async throws -> [CollectionDTO] in
        try await runtime.collections()
    }

    app.post("api", "collections") { req async throws -> CollectionDTO in
        try await runtime.createCollection(try req.content.decode(CollectionCreateRequest.self))
    }

    app.get("api", "collections", ":id") { req async throws -> CollectionDetailDTO in
        try await runtime.collection(id: try pathID(req))
    }

    app.delete("api", "collections", ":id") { req async throws -> DeleteResponse in
        DeleteResponse(deleted: try await runtime.deleteCollection(id: try pathID(req)))
    }

    // Membership is the join-table half of collections CRUD; the Tauri collection
    // screens need it even though the contract table lists only the collection itself.
    app.post("api", "collections", ":id", "skills") { req async throws -> MembershipResponse in
        let collectionID = try pathID(req)
        let body = try req.content.decode(CollectionMembershipRequest.self)
        let added = try await runtime.addMembership(collectionID: collectionID, skillID: body.skillId)
        return MembershipResponse(added: added)
    }

    app.delete("api", "collections", ":id", "skills", ":skillId") { req async throws -> MembershipResponse in
        let collectionID = try pathID(req)
        guard let skillID = req.parameters.get("skillId", as: Int64.self) else {
            throw Abort(.badRequest, reason: "skillId must be an integer.")
        }
        let removed = try await runtime.removeMembership(collectionID: collectionID, skillID: skillID)
        return MembershipResponse(removed: removed)
    }

    // MARK: Registry

    app.get("api", "registry", "trending") { _ async throws -> [RegistrySkillDTO] in
        try await runtime.registryTrending()
    }

    app.get("api", "registry", "search") { req async throws -> [RegistrySkillDTO] in
        try await runtime.registrySearch(req.query[String.self, at: "q"] ?? "")
    }

    app.post("api", "registry", "install") { req async throws -> RegistryInstallResponse in
        try await runtime.installRegistry(try req.content.decode(RegistryInstallRequest.self))
    }

    // MARK: Remote servers (SSH)

    app.get("api", "remote", "servers") { _ async throws -> [RemoteServerDTO] in
        try await runtime.remoteServers()
    }

    app.post("api", "remote", "servers") { req async throws -> RemoteServerDTO in
        try await runtime.createRemoteServer(try req.content.decode(RemoteServerRequest.self))
    }

    app.put("api", "remote", "servers", ":id") { req async throws -> RemoteServerDTO in
        try await runtime.updateRemoteServer(
            id: try pathString(req, "id"),
            request: try req.content.decode(RemoteServerRequest.self)
        )
    }

    app.delete("api", "remote", "servers", ":id") { req async throws -> DeleteResponse in
        DeleteResponse(deleted: try await runtime.deleteRemoteServer(id: try pathString(req, "id")))
    }

    app.post("api", "remote", "browse") { req async throws -> RemoteBrowseResponse in
        try await runtime.browseRemote(try req.content.decode(RemoteBrowseRequest.self))
    }

    app.post("api", "remote", "install") { req async throws -> RegistryInstallResponse in
        try await runtime.installRemote(try req.content.decode(RemoteInstallRequest.self))
    }

    // MARK: Settings

    app.get("api", "settings") { _ async -> SettingsResponse in
        await runtime.settingsResponse()
    }

    app.put("api", "settings") { req async throws -> SettingsResponse in
        try await runtime.updateSettings(try req.content.decode(SettingsUpdateRequest.self))
    }

    // MARK: WebSocket events

    app.webSocket("ws") { _, socket async in
        // The contract is server → client only. Do not install an `onText` handler
        // here: Vapor's async upgrade closure is not guaranteed to run on the
        // socket's event loop, and `onText` is loop-bound.
        let clientID = runtime.hub.add(socket)
        socket.onClose.whenComplete { _ in
            runtime.hub.remove(clientID)
        }
    }
}

// MARK: - Path helpers

private func pathID(_ req: Request) throws -> Int64 {
    guard let id = req.parameters.get("id", as: Int64.self) else {
        throw Abort(.badRequest, reason: "id must be an integer.")
    }
    return id
}

private func pathString(_ req: Request, _ name: String) throws -> String {
    guard let value = req.parameters.get(name), !value.isEmpty else {
        throw Abort(.badRequest, reason: "\(name) is required.")
    }
    return value
}
