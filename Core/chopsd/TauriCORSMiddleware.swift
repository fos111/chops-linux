// CORS for the Tauri webview (plan T14's HTTP seam with chopsd).
//
// The macOS app never needed CORS because it talks to chopsd from native code. The
// Tauri front-end is a browser document served from `tauri://localhost` (Linux) or
// `http://tauri.localhost` (Windows) and fetches `http://127.0.0.1:47115`, so every
// REST call is cross-origin.
//
// Vapor's built-in `CORSMiddleware` can take an origin list, but it only emits
// `Vary: Origin` for `.originBased`, answers preflights with `200`, and only treats
// an OPTIONS request as a preflight when `Access-Control-Request-Method` is present.
// The fixed contract here is explicit: reflect a matching Origin, always send
// `Vary: Origin`, and answer OPTIONS with `204`. The allowlist is deliberately tiny.

import Vapor

struct TauriCORSMiddleware: AsyncMiddleware {
    static let allowedOrigins: Set<String> = [
        "tauri://localhost",
        "http://tauri.localhost",
        "http://localhost:5173",
        "http://127.0.0.1:5173",
    ]

    static let allowedMethods = "GET, POST, PUT, DELETE, OPTIONS"
    static let allowedHeaders = "Content-Type, Authorization"

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // `/ws` is a WebSocket upgrade, not a CORS request. Let the 101 through
        // untouched so the event stream keeps working.
        if request.url.path == "/ws" || isWebSocketUpgrade(request) {
            return try await next.respond(to: request)
        }

        let origin = request.headers[.origin].first
        let allowedOrigin = origin.flatMap { Self.allowedOrigins.contains($0) ? $0 : nil }

        let response: Response
        if request.method == .OPTIONS {
            response = Response(status: .noContent)
        } else {
            response = try await next.respond(to: request)
        }

        if origin != nil {
            response.headers.add(name: .vary, value: "Origin")
        }
        if let allowedOrigin {
            response.headers.replaceOrAdd(name: .accessControlAllowOrigin, value: allowedOrigin)
            response.headers.replaceOrAdd(name: .accessControlAllowMethods, value: Self.allowedMethods)
            response.headers.replaceOrAdd(name: .accessControlAllowHeaders, value: Self.allowedHeaders)
        }
        return response
    }

    private func isWebSocketUpgrade(_ request: Request) -> Bool {
        request.headers[.upgrade].contains { $0.lowercased() == "websocket" }
    }
}
