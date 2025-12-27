// CosmoOS/UI/FocusMode/Connection/ConnectionFocusModeState.swift
// Data models and state for Connection Focus Mode
// 8 structured sections with items, ghost suggestions, and connected sources
// December 2025 - Complete rewrite following PRD spec

import SwiftUI
import Foundation

// MARK: - Connection Section Type

/// The 8 section types for a Connection atom
enum ConnectionSectionType: String, Codable, CaseIterable {
    case goal               // What is the desired outcome?
    case problems           // What pain points does this solve?
    case benefits           // What are the positive outcomes?
    case examples           // Real-world applications
    case beliefsObjections  // Common views, counterarguments
    case process            // Step-by-step implementation
    case conceptName        // Your unique name for this idea
    case references         // Sources and evidence

    var displayName: String {
        switch self {
        case .goal: return "Goal"
        case .problems: return "Problems"
        case .benefits: return "Benefits"
        case .examples: return "Examples"
        case .beliefsObjections: return "Beliefs & Objections"
        case .process: return "Process"
        case .conceptName: return "Concept Name"
        case .references: return "References"
        }
    }

    var icon: String {
        switch self {
        case .goal: return "target"
        case .problems: return "exclamationmark.triangle.fill"
        case .benefits: return "checkmark.circle.fill"
        case .examples: return "pin.fill"
        case .beliefsObjections: return "bubble.left.and.bubble.right.fill"
        case .process: return "list.number"
        case .conceptName: return "lightbulb.fill"
        case .references: return "book.fill"
        }
    }

    var promptQuestion: String {
        switch self {
        case .goal: return "What is the desired outcome?"
        case .problems: return "What pain points does this solve?"
        case .benefits: return "What are the positive outcomes?"
        case .examples: return "What are real-world applications?"
        case .beliefsObjections: return "What are common views or counterarguments?"
        case .process: return "What are the implementation steps?"
        case .conceptName: return "What is your unique name for this idea?"
        case .references: return "What sources support this?"
        }
    }

    var accentColor: Color {
        switch self {
        case .goal: return Color(hex: "#6366F1")         // Indigo
        case .problems: return Color(hex: "#EF4444")     // Red
        case .benefits: return Color(hex: "#22C55E")     // Green
        case .examples: return Color(hex: "#F59E0B")     // Amber
        case .beliefsObjections: return Color(hex: "#8B5CF6")  // Purple
        case .process: return Color(hex: "#06B6D4")      // Cyan
        case .conceptName: return Color(hex: "#F59E0B")  // Amber
        case .references: return Color(hex: "#6366F1")   // Indigo
        }
    }

    /// Default order for display
    var sortOrder: Int {
        switch self {
        case .goal: return 0
        case .problems: return 1
        case .benefits: return 2
        case .examples: return 3
        case .beliefsObjections: return 4
        case .process: return 5
        case .conceptName: return 6
        case .references: return 7
        }
    }
}

// MARK: - Connection Section

/// A section in a Connection atom containing items
struct ConnectionSection: Identifiable, Codable, Equatable {
    let id: UUID
    let type: ConnectionSectionType
    var items: [ConnectionItem]
    var isExpanded: Bool
    var showGhostSuggestions: Bool
    var ghostSuggestions: [GhostSuggestion]

    init(
        id: UUID = UUID(),
        type: ConnectionSectionType,
        items: [ConnectionItem] = [],
        isExpanded: Bool = true,
        showGhostSuggestions: Bool = true,
        ghostSuggestions: [GhostSuggestion] = []
    ) {
        self.id = id
        self.type = type
        self.items = items
        self.isExpanded = isExpanded
        self.showGhostSuggestions = showGhostSuggestions
        self.ghostSuggestions = ghostSuggestions
    }

    var itemCount: Int {
        items.count
    }

    var hasContent: Bool {
        !items.isEmpty || !ghostSuggestions.isEmpty
    }

    mutating func addItem(_ item: ConnectionItem) {
        items.append(item)
    }

    mutating func removeItem(id: UUID) {
        items.removeAll { $0.id == id }
    }

    mutating func updateItem(_ item: ConnectionItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        }
    }

    mutating func acceptGhostSuggestion(_ suggestion: GhostSuggestion) {
        let item = ConnectionItem(
            content: suggestion.content,
            sourceAtomUUID: suggestion.sourceAtomUUID,
            sourceSnippet: suggestion.sourceSnippet
        )
        items.append(item)
        ghostSuggestions.removeAll { $0.id == suggestion.id }
    }

    mutating func dismissGhostSuggestion(_ id: UUID) {
        ghostSuggestions.removeAll { $0.id == id }
    }
}

// MARK: - Connection Item

/// An individual item within a Connection section
struct ConnectionItem: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    var sourceAtomUUID: String?     // If pulled from another atom
    var sourceSnippet: String?      // Original text from source
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        content: String,
        sourceAtomUUID: String? = nil,
        sourceSnippet: String? = nil
    ) {
        self.id = id
        self.content = content
        self.sourceAtomUUID = sourceAtomUUID
        self.sourceSnippet = sourceSnippet
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var hasSource: Bool {
        sourceAtomUUID != nil
    }
}

// MARK: - Ghost Suggestion

/// A suggested item from AI analysis of connected atoms
struct GhostSuggestion: Identifiable, Codable, Equatable {
    let id: UUID
    let content: String
    let sourceAtomUUID: String
    let sourceAtomTitle: String
    let sourceSnippet: String
    let targetSectionType: ConnectionSectionType
    let confidence: Double  // 0.0 to 1.0
    let createdAt: Date

    init(
        id: UUID = UUID(),
        content: String,
        sourceAtomUUID: String,
        sourceAtomTitle: String,
        sourceSnippet: String,
        targetSectionType: ConnectionSectionType,
        confidence: Double
    ) {
        self.id = id
        self.content = content
        self.sourceAtomUUID = sourceAtomUUID
        self.sourceAtomTitle = sourceAtomTitle
        self.sourceSnippet = sourceSnippet
        self.targetSectionType = targetSectionType
        self.confidence = min(max(confidence, 0), 1)
        self.createdAt = Date()
    }

    /// Formatted confidence percentage
    var confidencePercent: Int {
        Int(confidence * 100)
    }

    /// Whether this suggestion should be shown (confidence > 60%)
    var shouldShow: Bool {
        confidence >= 0.6
    }
}

// MARK: - Connected Source

/// A source atom referenced by items in this Connection
struct ConnectedSource: Identifiable, Equatable {
    let atomUUID: String
    let atomType: AtomType
    let atomTitle: String
    let connectionStrength: Int  // How many items reference this

    var id: String { atomUUID }
}

// MARK: - Connection Focus Mode State

/// Complete state for a Connection Focus Mode session
struct ConnectionFocusModeState: Codable {
    let atomUUID: String
    var sections: [ConnectionSection]
    var viewportState: CanvasViewportState
    var floatingPanelIDs: [UUID]
    var isGeneratingGhosts: Bool
    var lastModified: Date

    init(atomUUID: String) {
        self.atomUUID = atomUUID
        // Initialize with all 8 sections
        self.sections = ConnectionSectionType.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { ConnectionSection(type: $0) }
        self.viewportState = CanvasViewportState()
        self.floatingPanelIDs = []
        self.isGeneratingGhosts = false
        self.lastModified = Date()
    }

    // MARK: - Section Access

    func section(for type: ConnectionSectionType) -> ConnectionSection? {
        sections.first { $0.type == type }
    }

    mutating func updateSection(_ section: ConnectionSection) {
        if let index = sections.firstIndex(where: { $0.id == section.id }) {
            sections[index] = section
            lastModified = Date()
        }
    }

    // MARK: - Item Management

    mutating func addItem(_ item: ConnectionItem, toSection type: ConnectionSectionType) {
        if let index = sections.firstIndex(where: { $0.type == type }) {
            sections[index].addItem(item)
            lastModified = Date()
        }
    }

    mutating func removeItem(id: UUID, fromSection type: ConnectionSectionType) {
        if let index = sections.firstIndex(where: { $0.type == type }) {
            sections[index].removeItem(id: id)
            lastModified = Date()
        }
    }

    // MARK: - Ghost Suggestions

    mutating func setGhostSuggestions(_ suggestions: [GhostSuggestion], forSection type: ConnectionSectionType) {
        if let index = sections.firstIndex(where: { $0.type == type }) {
            sections[index].ghostSuggestions = suggestions.filter { $0.shouldShow }
            lastModified = Date()
        }
    }

    mutating func acceptGhost(_ id: UUID, inSection type: ConnectionSectionType) {
        if let sectionIndex = sections.firstIndex(where: { $0.type == type }),
           let suggestion = sections[sectionIndex].ghostSuggestions.first(where: { $0.id == id }) {
            sections[sectionIndex].acceptGhostSuggestion(suggestion)
            lastModified = Date()
        }
    }

    mutating func dismissGhost(_ id: UUID, inSection type: ConnectionSectionType) {
        if let index = sections.firstIndex(where: { $0.type == type }) {
            sections[index].dismissGhostSuggestion(id)
            lastModified = Date()
        }
    }

    // MARK: - Connected Sources

    var connectedSources: [ConnectedSource] {
        var sourceReferences: [String: (type: AtomType?, title: String?, count: Int)] = [:]

        for section in sections {
            for item in section.items {
                if let sourceUUID = item.sourceAtomUUID {
                    if var existing = sourceReferences[sourceUUID] {
                        existing.count += 1
                        sourceReferences[sourceUUID] = existing
                    } else {
                        sourceReferences[sourceUUID] = (type: nil, title: nil, count: 1)
                    }
                }
            }
        }

        // Note: In real implementation, would fetch atom types and titles
        return sourceReferences.map { uuid, info in
            ConnectedSource(
                atomUUID: uuid,
                atomType: info.type ?? .research,
                atomTitle: info.title ?? "Source",
                connectionStrength: info.count
            )
        }.sorted { $0.connectionStrength > $1.connectionStrength }
    }

    // MARK: - Stats

    var totalItemCount: Int {
        sections.reduce(0) { $0 + $1.itemCount }
    }

    var totalGhostCount: Int {
        sections.reduce(0) { $0 + $1.ghostSuggestions.count }
    }

    var completedSectionCount: Int {
        sections.filter { !$0.items.isEmpty }.count
    }
}

// MARK: - Persistence

extension ConnectionFocusModeState {
    static func persistenceKey(atomUUID: String) -> String {
        "connectionFocusMode_\(atomUUID)"
    }

    func save() {
        let key = Self.persistenceKey(atomUUID: atomUUID)
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    static func load(atomUUID: String) -> ConnectionFocusModeState? {
        let key = persistenceKey(atomUUID: atomUUID)
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(ConnectionFocusModeState.self, from: data) else {
            return nil
        }
        return state
    }
}

// MARK: - Section Structured Data

/// Helper to convert Connection sections to/from Atom.structured JSON
struct ConnectionStructuredData: Codable {
    var sections: [ConnectionSection]

    init(sections: [ConnectionSection]) {
        self.sections = sections
    }

    func toJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func fromJSON(_ json: String) -> ConnectionStructuredData? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ConnectionStructuredData.self, from: data)
    }
}
