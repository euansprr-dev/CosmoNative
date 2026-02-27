// CosmoOS/AI/CollisionResult.swift
// Data model for trisociative collisions — three-way bridging connections
// between maximally distant ideas in the knowledge graph.

import Foundation

/// A collision represents a non-obvious bridging concept connecting three
/// semantically distant atoms — engineered serendipity.
struct CollisionResult: Codable, Identifiable, Sendable {
    let id: String
    let atomAUUID: String
    let atomBUUID: String
    let atomCUUID: String
    var atomATitle: String
    var atomBTitle: String
    var atomCTitle: String
    var bridgingConcept: String
    var bridgingExplanation: String
    var noveltyScore: Double // 0-1
    var userRating: CollisionRating?
    var createdAt: String // ISO8601

    enum CollisionRating: String, Codable, Sendable {
        case positive, negative, neutral
    }

    init(
        id: String = UUID().uuidString,
        atomAUUID: String,
        atomBUUID: String,
        atomCUUID: String,
        atomATitle: String,
        atomBTitle: String,
        atomCTitle: String,
        bridgingConcept: String,
        bridgingExplanation: String,
        noveltyScore: Double,
        userRating: CollisionRating? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.atomAUUID = atomAUUID
        self.atomBUUID = atomBUUID
        self.atomCUUID = atomCUUID
        self.atomATitle = atomATitle
        self.atomBTitle = atomBTitle
        self.atomCTitle = atomCTitle
        self.bridgingConcept = bridgingConcept
        self.bridgingExplanation = bridgingExplanation
        self.noveltyScore = noveltyScore
        self.userRating = userRating
        self.createdAt = createdAt
    }
}
