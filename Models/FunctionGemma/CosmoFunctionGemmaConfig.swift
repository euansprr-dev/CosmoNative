// CosmoOS/Models/FunctionGemma/CosmoFunctionGemmaConfig.swift
// Auto-generated configuration for fine-tuned FunctionGemma model

import Foundation

/// Configuration for the CosmoOS fine-tuned FunctionGemma model
public struct CosmoFunctionGemmaConfig {
    /// Base model identifier
    public static let baseModel = "lmstudio-community/functiongemma-270m-it-MLX-bf16"

    /// Path to LoRA adapter weights
    public static let adapterPath = "Models/FunctionGemma/adapters/cosmo-v1"

    /// LoRA configuration
    public static let loraRank = 8
    public static let loraAlpha = 16
    public static let loraLayers = 8

    /// Target latency in milliseconds
    public static let targetLatencyMs = 300

    /// Expected RAM usage in MB
    public static let expectedRamMB = 550

    /// Training metadata
    public static let trainingIterations = 300
    public static let trainingDate = "2025-12-21T18:23:27.105699"
}
