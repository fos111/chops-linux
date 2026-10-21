// WebSocket fan-out for chopd's `/ws` channel (plan T11).
//
// The Tauri front-end keeps one socket open and reacts to three event families from
// the fixed contract: `rescan`, `file-changed`, and `assist-status`. Payloads are
// encoded once per broadcast and sent to every connected client.

import Foundation
import Vapor

/// Every outbound WS frame. Optional members are omitted by the encoder so each event
/// family carries only the fields it needs.
struct WSEvent: Encodable, Sendable {
    var type: String
    var timestamp: String
    var path: String?
    var kind: String?
    var reason: String?
    var count: Int?
    var pendingId: String?
    var status: String?
    var message: String?
    var skillId: Int64?

    static func fileChanged(path: String, kind: String, timestamp: String = WSEvent.now()) -> WSEvent {
        WSEvent(type: "file-changed", timestamp: timestamp, path: path, kind: kind)
    }

    static func rescan(reason: String, count: Int, timestamp: String = WSEvent.now()) -> WSEvent {
        WSEvent(type: "rescan", timestamp: timestamp, reason: reason, count: count)
    }

    static func assistStatus(
        pendingId: String?,
        status: String,
        message: String?,
        skillId: Int64?
    ) -> WSEvent {
        WSEvent(
            type: "assist-status",
            timestamp: WSEvent.now(),
            pendingId: pendingId,
            status: status,
            message: message,
            skillId: skillId
        )
    }

    static func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    func encode() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Thread-safe registry of connected WebSocket clients.
final class EventHub: @unchecked Sendable {
    private let lock = NSLock()
    private var clients: [UUID: WebSocket] = [:]

    var clientCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return clients.count
    }

    func add(_ socket: WebSocket) -> UUID {
        let id = UUID()
        lock.lock()
        clients[id] = socket
        lock.unlock()
        return id
    }

    func remove(_ id: UUID) {
        lock.lock()
        clients[id] = nil
        lock.unlock()
    }

    func broadcast(_ event: WSEvent) {
        guard let text = event.encode() else { return }
        lock.lock()
        let sockets = Array(clients.values)
        lock.unlock()
        for socket in sockets {
            socket.send(text)
        }
    }
}
