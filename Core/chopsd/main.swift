// chopsd — Chops Linux sidecar service (application entry point).
//
// Final form (Batch 2): Vapor server bound to 127.0.0.1:47115 (env override
// CHOPSD_PORT), SQLite store under ${XDG_DATA_HOME:-$HOME/.local/share}/Chops,
// settings under ${XDG_CONFIG_HOME:-$HOME/.config}/chops — see the fixed
// UI↔chopsd contract in .omo/plans/debian-linux-port.md.
//
// Scaffold only: the executable must build and exit cleanly until the HTTP
// service is ported in Batch 2.

import chopscore

print("chopsd scaffold (ChopsCore \(ChopsCore.version)) — Vapor wiring lands in Batch 2")
