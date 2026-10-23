// chopsd — Chops Linux sidecar service (plan T11).
//
// Binds 127.0.0.1:47115 (env override CHOPSD_PORT) and serves the fixed UI↔chopsd
// REST/WS contract. Data: ${XDG_DATA_HOME:-$HOME/.local/share}/Chops/chops.db via the
// T05 GRDB store. Settings: ${XDG_CONFIG_HOME:-$HOME/.config}/chops/settings.json.

import Foundation
import Vapor
import chopscore

var environment = try Environment.detect()
try LoggingSystem.bootstrap(from: &environment)

let app = try await Application.make(environment)
do {
    let runtime = try ChopsdRuntime(environment: ProcessInfo.processInfo.environment)
    try await runtime.start()
    try configure(app, runtime: runtime)
    try await app.execute()
    await runtime.stop()
} catch {
    app.logger.report(error: error)
    FileHandle.standardError.write(
        Data("chopsd failed to start: \(error.localizedDescription)\n".utf8)
    )
    try? await app.asyncShutdown()
    throw error
}

try await app.asyncShutdown()
