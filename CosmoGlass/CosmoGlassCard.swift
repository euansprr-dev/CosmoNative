// CosmoOS/CosmoGlass/CosmoGlassCard.swift
// Glass card models for the notification-style overlay
// Supports search results, clarification, proactive suggestions, research, and tasks

import Foundation
import SwiftUI

// MARK: - Glass Card Types

enum CosmoGlassCardType: String, Codable {
    case searchResults = "search_results"
    case clarification = "clarification"
    case proactive = "proactive"
    case research = "research"
    case taskList = "task_list"
    case notification = "notification"
    case aiResponse = "ai_response"  // Gemini AI response card
}

// MARK: - Glass Card Actions

enum CosmoGlassCardAction: String, Codable {
    case openEntity = "open_entity"
    case placeOnCanvas = "place_on_canvas"
    case insertIntoEditor = "insert_into_editor"
    case scheduleTask = "schedule_task"
    case snooze = "snooze"
    case dismiss = "dismiss"
    case proceed = "proceed"
    case cancel = "cancel"
}

// MARK: - Entity Reference (for results)

struct CosmoGlassEntityRef: Identifiable, Codable, Equatable {
    let id: String  // UUID
    let entityType: String
    let entityId: Int64
    let title: String
    let preview: String?
    let index: Int  // For "second one" references

    init(id: String = UUID().uuidString, entityType: String, entityId: Int64, title: String, preview: String? = nil, index: Int = 0) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.title = title
        self.preview = preview
        self.index = index
    }
}

// MARK: - Clarification Option

struct CosmoGlassClarificationOption: Identifiable, Codable {
    let id: String
    let label: String
    let action: String
    let parameters: [String: String]

    init(id: String = UUID().uuidString, label: String, action: String, parameters: [String: String] = [:]) {
        self.id = id
        self.label = label
        self.action = action
        self.parameters = parameters
    }
}

// MARK: - Research Finding (for research cards)

struct CosmoGlassResearchFinding: Identifiable, Codable {
    let id: String
    let title: String
    let snippet: String?
    let source: String?
    let url: String?

    init(id: String = UUID().uuidString, title: String, snippet: String? = nil, source: String? = nil, url: String? = nil) {
        self.id = id
        self.title = title
        self.snippet = snippet
        self.source = source
        self.url = url
    }
}

// MARK: - Glass Card

struct CosmoGlassCard: Identifiable {
    let id: String
    let type: CosmoGlassCardType
    let title: String
    var message: String?  // Mutable for streaming updates
    let timestamp: Date

    // For search results
    var entities: [CosmoGlassEntityRef]

    // For clarification
    var clarificationQuestion: String?
    var clarificationOptions: [CosmoGlassClarificationOption]

    // For research
    var researchQuery: String?
    var researchFindings: [CosmoGlassResearchFinding]
    var researchProgress: Double
    var isResearchComplete: Bool

    // For proactive/notification
    var entityType: String?
    var entityId: Int64?
    var priority: CosmoGlassCardPriority

    // Auto-dismiss timer (seconds, 0 = manual dismiss only)
    var autoDismissAfter: TimeInterval

    init(
        id: String = UUID().uuidString,
        type: CosmoGlassCardType,
        title: String,
        message: String? = nil,
        entities: [CosmoGlassEntityRef] = [],
        clarificationQuestion: String? = nil,
        clarificationOptions: [CosmoGlassClarificationOption] = [],
        researchQuery: String? = nil,
        researchFindings: [CosmoGlassResearchFinding] = [],
        researchProgress: Double = 0,
        isResearchComplete: Bool = false,
        entityType: String? = nil,
        entityId: Int64? = nil,
        priority: CosmoGlassCardPriority = .medium,
        autoDismissAfter: TimeInterval = 0
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.message = message
        self.timestamp = Date()
        self.entities = entities
        self.clarificationQuestion = clarificationQuestion
        self.clarificationOptions = clarificationOptions
        self.researchQuery = researchQuery
        self.researchFindings = researchFindings
        self.researchProgress = researchProgress
        self.isResearchComplete = isResearchComplete
        self.entityType = entityType
        self.entityId = entityId
        self.priority = priority
        self.autoDismissAfter = autoDismissAfter
    }

    // MARK: - Factory Methods

    static func searchResults(title: String, entities: [CosmoGlassEntityRef]) -> CosmoGlassCard {
        CosmoGlassCard(
            type: .searchResults,
            title: title,
            entities: entities,
            autoDismissAfter: 30
        )
    }

    static func clarification(question: String, options: [CosmoGlassClarificationOption]) -> CosmoGlassCard {
        CosmoGlassCard(
            type: .clarification,
            title: "Clarification Needed",
            clarificationQuestion: question,
            clarificationOptions: options
        )
    }

    static func research(query: String) -> CosmoGlassCard {
        CosmoGlassCard(
            type: .research,
            title: "Researching...",
            researchQuery: query,
            researchProgress: 0,
            isResearchComplete: false
        )
    }

    static func proactive(title: String, message: String, entityType: String? = nil, entityId: Int64? = nil, priority: CosmoGlassCardPriority = .medium) -> CosmoGlassCard {
        CosmoGlassCard(
            type: .proactive,
            title: title,
            message: message,
            entityType: entityType,
            entityId: entityId,
            priority: priority,
            autoDismissAfter: 60
        )
    }

    static func notification(title: String, message: String, entityType: String, entityId: Int64) -> CosmoGlassCard {
        CosmoGlassCard(
            type: .notification,
            title: title,
            message: message,
            entityType: entityType,
            entityId: entityId,
            priority: .high,
            autoDismissAfter: 15
        )
    }

    /// AI response card for Gemini synthesis results
    /// Shows concise, expert-level responses like a creative partner
    static func aiResponse(query: String, response: String, sourceCount: Int = 0) -> CosmoGlassCard {
        return CosmoGlassCard(
            type: .aiResponse,
            title: "Cosmo",
            message: response,
            priority: .high,
            autoDismissAfter: 0  // Manual dismiss - user should read it
        )
    }

    /// Streaming AI response card - starts empty and fills as content streams in
    static func streamingAIResponse(query: String) -> CosmoGlassCard {
        return CosmoGlassCard(
            id: "streaming-ai-response",  // Fixed ID for updates
            type: .aiResponse,
            title: "Cosmo",
            message: "",  // Starts empty
            priority: .high,
            autoDismissAfter: 0
        )
    }
}

// MARK: - Parsed Entity Reference

/// A parsed entity reference from Gemini's response
/// Matches patterns like [Source: Connection Name] or [Swipe File: Hook Title]
struct ParsedEntityReference: Identifiable, Equatable {
    let id = UUID()
    let entityType: String    // "connection", "swipe_file", "idea", "research", etc.
    let title: String         // The referenced title
    let range: Range<String.Index>  // Position in the original text

    /// Parse all entity references from a response string
    static func parseAll(from text: String) -> [ParsedEntityReference] {
        var references: [ParsedEntityReference] = []

        // Pattern: [Source: title] or [Swipe File: title] or [Connection: title]
        let patterns: [(regex: String, entityType: String)] = [
            (#"\[Source:\s*([^\]]+)\]"#, "unknown"),        // Generic source
            (#"\[Swipe File:\s*([^\]]+)\]"#, "swipe_file"),
            (#"\[Connection:\s*([^\]]+)\]"#, "connection"),
            (#"\[Idea:\s*([^\]]+)\]"#, "idea"),
            (#"\[Research:\s*([^\]]+)\]"#, "research"),
            (#"\[Content:\s*([^\]]+)\]"#, "content"),
        ]

        for (pattern, entityType) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let nsRange = NSRange(text.startIndex..., in: text)
                let matches = regex.matches(in: text, options: [], range: nsRange)

                for match in matches {
                    if let titleRange = Range(match.range(at: 1), in: text),
                       let fullRange = Range(match.range(at: 0), in: text) {
                        let title = String(text[titleRange]).trimmingCharacters(in: .whitespaces)
                        references.append(ParsedEntityReference(
                            entityType: entityType,
                            title: title,
                            range: fullRange
                        ))
                    }
                }
            }
        }

        return references.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }
}

// MARK: - Card Priority

enum CosmoGlassCardPriority: String, Codable, Comparable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"

    static func < (lhs: CosmoGlassCardPriority, rhs: CosmoGlassCardPriority) -> Bool {
        let order: [CosmoGlassCardPriority] = [.low, .medium, .high, .critical]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }
}

// MARK: - Glass Selection Context

struct GlassSelectionContext: Equatable {
    var activeCardId: String?
    var lastResultEntities: [CosmoGlassEntityRef]
    var selectedIndex: Int?
    var timestamp: Date

    init(activeCardId: String? = nil, lastResultEntities: [CosmoGlassEntityRef] = [], selectedIndex: Int? = nil) {
        self.activeCardId = activeCardId
        self.lastResultEntities = lastResultEntities
        self.selectedIndex = selectedIndex
        self.timestamp = Date()
    }

    /// Check if context is still valid (within 5 minutes)
    var isValid: Bool {
        Date().timeIntervalSince(timestamp) < 300
    }

    /// Get entity by ordinal reference ("first", "second", etc.)
    func entity(at ordinal: Int) -> CosmoGlassEntityRef? {
        guard ordinal > 0, ordinal <= lastResultEntities.count else { return nil }
        return lastResultEntities[ordinal - 1]
    }

    /// Get selected entity
    var selectedEntity: CosmoGlassEntityRef? {
        guard let idx = selectedIndex, idx >= 0, idx < lastResultEntities.count else { return nil }
        return lastResultEntities[idx]
    }
}
