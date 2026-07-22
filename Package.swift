// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CosmoOS",
    platforms: [
        .macOS("26.0")  // macOS 26 Tahoe - Foundation Models with full @Generable support (November 2025)
    ],
    products: [
        .executable(name: "CosmoOS", targets: ["CosmoOS"])
    ],
    dependencies: [
        // GRDB.swift - Best-in-class SQLite wrapper
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0"),
        // Supabase Swift SDK
        .package(url: "https://github.com/supabase-community/supabase-swift", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "CosmoOS",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Supabase", package: "supabase-swift"),
            ],
            path: ".",
            exclude: [
                "Tests",
                "scripts",  // Python tooling (.venv contains C sources SPM chokes on)
                "marketing",  // Video tooling (node_modules contains C sources)
                "cosmo-cloud-agent",  // Railway worker (TS/JS + node_modules — breaks `swift test`)
                "build",  // xcodebuild artifacts
                "CosmoOS.app",  // build output bundle
            ],
            resources: [
                // Runtime-compiled Metal shaders (SwiftPM resource bundle)
                .process("Canvas/Shaders.metal"),
            ],
            swiftSettings: [
                // Match the Xcode project: Swift 5 language mode with targeted
                // concurrency checking. Tools-version 6.0 otherwise defaults to
                // the Swift 6 mode, which fails app-wide with strict-concurrency
                // errors xcodebuild does not enforce.
                .swiftLanguageMode(.v5),
                .enableUpcomingFeature("BareSlashRegexLiterals"),
                .unsafeFlags(["-Xfrontend", "-strict-concurrency=targeted"])
            ]
        ),
        .testTarget(
            name: "CosmoOSTests",
            dependencies: ["CosmoOS"],
            path: "Tests/CosmoOSTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        )
    ]
)
