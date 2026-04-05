// CosmoOS/Data/Models/Codex/CodexOutlineModel.swift
// User-composed outline with codex element tags per slide.
// Also contains supporting types for idea research, chat, and recommendations.

import Foundation

struct CodexOutlineModel: Codable, Sendable, Equatable {
    let arcShape: String?
    var slides: [CodexOutlineSlide]
}

struct CodexOutlineSlide: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var position: Int
    var speechAct: String?
    var readerDeltas: [String]
    var frame: String?
    var distance: String?
    var techniques: [String]
    var transition: String?
    var note: String?
}

struct IdeaResearchResult: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let snippet: String
    let source: String
    let url: String?
    let proofType: String?
    var isIncluded: Bool
}

struct IdeaChatMessage: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let role: String
    let content: String
    let timestamp: String
    let actionCards: [ChatActionCard]?
}

struct ChatActionCard: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let type: String
    let title: String
    let targetUUID: String?
    var isActioned: Bool
}

struct ArcRecommendation: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let arcName: String
    let explanation: String
    let prioritizes: [String]
    let tradesOff: [String]
    let matchingBlueprintTitles: [String]
    let confidence: Double
}

struct DetectedElements: Codable, Sendable, Equatable {
    let motivations: [String]
    let proofTypes: [String]
    let speechActs: [String]
    let signals: [String]
}

struct BlueprintRecommendation: Codable, Sendable, Equatable {
    let title: String
    let explanation: String
}
