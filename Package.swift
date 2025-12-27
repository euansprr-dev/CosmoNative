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
        // MLX Swift - Apple's ML framework for Apple Silicon
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.21.0"),
        // MLX Swift LM - LLM, VLM, and Embeddings (Qwen, etc.)
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main"),
        // WhisperKit - On-device ASR for Apple Silicon
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.15.0"),
    ],
    targets: [
        .executableTarget(
            name: "CosmoOS",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Supabase", package: "supabase-swift"),
                // MLX for local ML inference
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                // LLM and Embeddings support (Qwen, nomic, etc.)
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
                // WhisperKit for ASR
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: ".",
            exclude: [
                "Tests",
                "Daemon/main.swift",  // XPC service entry point (Xcode only)
                "Daemon/DaemonTypes.swift",  // Duplicate types for XPC target (Xcode only)
                "Daemon/Info.plist",  // XPC service Info.plist
            ],
            resources: [
                // Runtime-compiled Metal shaders (SwiftPM resource bundle)
                .process("Canvas/Shaders.metal"),
            ],
            swiftSettings: [
                // Use minimal concurrency checking to allow the app to compile
                // while Foundation Models integration is stabilized
                .unsafeFlags(["-Xfrontend", "-strict-concurrency=targeted"])
            ]
        ),
        .testTarget(
            name: "CosmoOSTests",
            dependencies: ["CosmoOS"],
            path: "Tests/CosmoOSTests"
        )
    ]
)
