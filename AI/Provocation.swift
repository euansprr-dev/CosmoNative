// CosmoOS/AI/Provocation.swift
// Data model for AI-generated intellectual provocations
// February 2026 — WP7 Provocation Layer

import SwiftUI

struct Provocation: Codable, Identifiable, Sendable {
    let id: String
    let type: ProvocationType
    let severity: Double
    let sourceAtomUUIDs: [String]
    let description: String
    let evidenceQuotes: [String]
    let suggestedResolution: String?
    var status: ProvocationStatus
    let confidence: Double
    let createdAt: String

    enum ProvocationType: String, Codable, Sendable, CaseIterable {
        case contradiction
        case assumption
        case missingEvidence
        case staleReasoning

        var color: Color {
            switch self {
            case .contradiction: return Color(hex: "FF5F57")
            case .assumption: return Color(hex: "FFBD2E")
            case .missingEvidence: return Color(hex: "5B9BD5")
            case .staleReasoning: return Color(hex: "A0A0A0")
            }
        }

        var icon: String {
            switch self {
            case .contradiction: return "arrow.triangle.2.circlepath"
            case .assumption: return "questionmark.diamond"
            case .missingEvidence: return "doc.questionmark"
            case .staleReasoning: return "clock.arrow.circlepath"
            }
        }

        var label: String {
            switch self {
            case .contradiction: return "Contradiction"
            case .assumption: return "Assumption"
            case .missingEvidence: return "Missing Evidence"
            case .staleReasoning: return "Stale Reasoning"
            }
        }
    }

    enum ProvocationStatus: String, Codable, Sendable {
        case active, dismissed, resolved
    }
}
