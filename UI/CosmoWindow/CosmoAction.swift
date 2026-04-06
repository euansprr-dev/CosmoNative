// CosmoOS/UI/CosmoWindow/CosmoWindowAction.swift
// Action definitions that Cosmo can execute on each view
// February 2026

import SwiftUI

// MARK: - Cosmo Action

/// A context-specific action that Cosmo can perform on the current view.
/// Each `CosmoContextProvider` exposes a list of these, and the AI can invoke them
/// based on the user's message.
struct CosmoWindowAction: Identifiable, @unchecked Sendable {
    let id: String
    let name: String
    let description: String
    let modelTier: ActionModelTier
    let handler: @Sendable (String) async throws -> String

    init(
        id: String,
        name: String,
        description: String,
        modelTier: ActionModelTier = .balanced,
        handler: @escaping @Sendable (String) async throws -> String
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.modelTier = modelTier
        self.handler = handler
    }
}

// MARK: - Action Model Tier

/// Routes actions to the appropriate model based on complexity and speed requirements.
enum ActionModelTier: String, Codable, Sendable {
    case local      // Gemma (Ollama) -- spatial/structural manipulation, fast
    case fast       // Haiku 4.5 -- simple data retrieval, filtering
    case balanced   // Sonnet 4.5 -- synthesis, summarization, analysis
    case creative   // Opus 4.6 -- creative writing, strategic analysis

    /// Maps to the existing AgentModelTier for routing through the agent system.
    var agentModelTier: AgentModelTier {
        switch self {
        case .local: return .router
        case .fast: return .router
        case .balanced: return .agent
        case .creative: return .reasoner
        }
    }
}
