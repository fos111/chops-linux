// swift-tools-version:6.0
// Chops → Debian/Linux port (additive-only). See .omo/plans/debian-linux-port.md.
//
// The macOS app under Chops/** and its XcodeGen project (project.yml) remain frozen.
// This manifest introduces the Linux-only SwiftPM layer:
//   chopscore        — portable core (data layer, parsers, scanner, transports)
//   chopsd           — localhost sidecar HTTP service (Vapor; wired up in Batch 2)
//   chopscoretests   — unit tests for chopscore (fixtures: linux/fixtures/home)
//
// External dependencies land task-by-task with the code that needs them.

import PackageDescription

let package = Package(
    name: "chops",
    products: [
        .library(name: "ChopsCore", targets: ["chopscore"]),
        .executable(name: "chopsd", targets: ["chopsd"]),
    ],
    dependencies: [
        // GRDB 7 — the SQLite layer that replaces SwiftData on Linux (T05).
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        // swift-log — structured JSON logging sinks replace os.Logger (T10).
        // Stack pinned by the work plan: from "1.6.0".
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    ],
    targets: [
        // Portable core. Batch 1 ports the frozen macOS logic here field-for-field
        // (GRDB store, parsers/templates/search, scanner + Linux tool-path tables,
        // one-shot agent transports, SSH/registry, file watcher + logging).
        .target(
            name: "chopscore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Core/ChopsCore/Sources/chopscore"
        ),
        // chopsd — binds 127.0.0.1:47115 (env override CHOPSD_PORT); serves the
        // fixed UI↔chopsd REST/WS contract from the work plan.
        .executableTarget(
            name: "chopsd",
            dependencies: ["chopscore"],
            path: "Core/chopsd"
        ),
        // All tests run against HOME pointed at a tmp copy of linux/fixtures/home —
        // never the real $HOME.
        .testTarget(
            name: "chopscoretests",
            dependencies: [
                "chopscore",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Core/ChopsCore/Tests/chopscoretests"
        ),
    ]
)
