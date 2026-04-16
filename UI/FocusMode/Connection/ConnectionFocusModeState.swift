// CosmoOS/UI/FocusMode/Connection/ConnectionFocusModeState.swift
// Data models and state for Connection Focus Mode
// 8 structured sections with items, ghost suggestions, and connected sources
// December 2025 - Complete rewrite following PRD spec
// April 2026 - V2 "The Crucible": concept type, station positions, live insights, collaborator messages, modes

import SwiftUI
import Foundation

// MARK: - Concept Framework Type (V2)

/// The shape of the framework being crystallized. Influences collaborator tone and masthead subtitle.
enum ConceptFrameworkType: String, Codable, CaseIterable {
    case mentalModel
    case framework
    case principle
    case doctrine
    case heuristic
    case lawOfNature

    var displayName: String {
        switch self {
        case .mentalModel: return "Mental Model"
        case .framework: return "Framework"
        case .principle: return "Principle"
        case .doctrine: return "Doctrine"
        case .heuristic: return "Heuristic"
        case .lawOfNature: return "Law of Nature"
        }
    }

    /// Shapes the Cosmo collaborator's voice.
    var collaboratorTone: String {
        switch self {
        case .mentalModel: return "Socratic and probing — help the user see the shape of their own thought"
        case .framework: return "Rigorous and structural — press for coherent parts and clear ordering"
        case .principle: return "Categorical and canonical — press for universality and counter-examples"
        case .doctrine: return "Assertive and confident — help the user state claims boldly"
        case .heuristic: return "Pragmatic and field-tested — press for 'when does this fail?'"
        case .lawOfNature: return "Empirical and precise — press for mechanism and prediction"
        }
    }
}

// MARK: - Forge Mode (V2)

/// Viewing mode within the focus mode. State of interaction, not of data.
enum ForgeMode: String, Codable {
    case forge       // Default: spatial stations workshop
    case manuscript  // Flattened serif reading flow
    case chalkboard  // Dark mood overlay for loose sketching
}

// MARK: - Live Insight (V2)

/// An AI-generated observation about the current state of the framework.
struct LiveInsight: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: Kind
    let message: String
    let relatedSections: [ConnectionSectionType]
    let createdAt: Date

    enum Kind: String, Codable {
        case tension        // Sections contradict each other
        case gap            // Missing dimension
        case echo           // Resembles a known framework
        case strength       // What's working
        case contradiction  // Internal logical issue

        var glyph: String {
            switch self {
            case .tension: return "bolt.horizontal"
            case .gap: return "circle.dotted"
            case .echo: return "arrow.triangle.turn.up.right.diamond"
            case .strength: return "checkmark.seal"
            case .contradiction: return "exclamationmark.triangle"
            }
        }

        var label: String {
            switch self {
            case .tension: return "tension"
            case .gap: return "gap"
            case .echo: return "echo"
            case .strength: return "strength"
            case .contradiction: return "contradiction"
            }
        }
    }

    init(
        id: UUID = UUID(),
        kind: Kind,
        message: String,
        relatedSections: [ConnectionSectionType] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.relatedSections = relatedSections
        self.createdAt = createdAt
    }
}

// MARK: - Collaborator Message (V2)

/// A single message in the Concept Collaborator conversation.
struct CollaboratorMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: Role
    let text: String
    /// If present, the assistant is suggesting content for a specific section.
    let crystallizeTarget: ConnectionSectionType?
    /// The text that would be inserted if the user taps "Crystallize into [SECTION]".
    let crystallizeContent: String?
    let createdAt: Date

    enum Role: String, Codable {
        case user
        case assistant
    }

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        crystallizeTarget: ConnectionSectionType? = nil,
        crystallizeContent: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.crystallizeTarget = crystallizeTarget
        self.crystallizeContent = crystallizeContent
        self.createdAt = createdAt
    }
}

// MARK: - Codable CGPoint

/// CGPoint is already Codable on Foundation but we give it a stable Equatable-friendly
/// representation so Dictionary<_, CGPoint> round-trips cleanly through JSON.
private struct CodablePoint: Codable, Equatable {
    let x: Double
    let y: Double
    init(_ point: CGPoint) { self.x = point.x; self.y = point.y }
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

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

    /// Three-letter abbreviation for dense layouts (canvas block, station dots).
    var abbreviation: String {
        switch self {
        case .goal: return "GOL"
        case .problems: return "PRB"
        case .benefits: return "BEN"
        case .examples: return "EX"
        case .beliefsObjections: return "BEL"
        case .process: return "PRC"
        case .conceptName: return "CN"
        case .references: return "REF"
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
    var document: RichDocument?
    var plainText: String?
    var sourceAtomUUID: String?     // If pulled from another atom
    var sourceSnippet: String?      // Original text from source
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        content: String,
        document: RichDocument? = nil,
        plainText: String? = nil,
        sourceAtomUUID: String? = nil,
        sourceSnippet: String? = nil
    ) {
        self.id = id
        self.content = content
        self.document = document ?? RichDocument.migrateLegacy(content)
        self.plainText = plainText ?? content
        self.sourceAtomUUID = sourceAtomUUID
        self.sourceSnippet = sourceSnippet
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var hasSource: Bool {
        sourceAtomUUID != nil
    }

    var resolvedDocument: RichDocument {
        // Prefer content/plainText when the document's text doesn't match —
        // the document may be stale from CosmoDocumentEditor's 150ms serialization debounce
        if let doc = document {
            let docText = doc.plainText
            let authoritative = plainText ?? content
            if docText == authoritative {
                return doc
            }
            // Document is stale — rebuild from authoritative plain text
            return RichDocument.migrateLegacy(authoritative)
        }
        return RichDocument.migrateLegacy(plainText ?? content)
    }

    var resolvedPlainText: String {
        plainText ?? document?.plainText ?? content
    }

    mutating func applyDocument(_ document: RichDocument) {
        self.document = document
        self.plainText = document.plainText
        self.content = document.plainText
        self.updatedAt = Date()
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

    // MARK: - V2 "The Crucible" fields (additive, backward-compatible)

    /// The shape of this framework — influences masthead subtitle and collaborator tone.
    var conceptType: ConceptFrameworkType = .mentalModel

    /// User-defined free positions for stations on the canvas.
    /// Empty = use the default 2x4 grid. Keyed by section type raw value
    /// because JSON dictionary keys must be strings.
    private var stationPositionsRaw: [String: CodablePoint] = [:]

    /// Current viewing mode. Default is `.forge`.
    var forgeMode: ForgeMode = .forge

    /// Rolling AI observations. Capped at 20 most recent.
    var liveInsights: [LiveInsight] = []

    /// Concept Collaborator conversation history. Capped at 50 most recent.
    var collaboratorMessages: [CollaboratorMessage] = []

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
        self.conceptType = .mentalModel
        self.stationPositionsRaw = [:]
        self.forgeMode = .forge
        self.liveInsights = []
        self.collaboratorMessages = []
    }

    // MARK: - V2 accessors

    /// Typed view of station positions. Empty = use default grid.
    var stationPositions: [ConnectionSectionType: CGPoint] {
        get {
            var out: [ConnectionSectionType: CGPoint] = [:]
            for (key, value) in stationPositionsRaw {
                if let type = ConnectionSectionType(rawValue: key) {
                    out[type] = value.cgPoint
                }
            }
            return out
        }
        set {
            var raw: [String: CodablePoint] = [:]
            for (key, value) in newValue {
                raw[key.rawValue] = CodablePoint(value)
            }
            stationPositionsRaw = raw
            lastModified = Date()
        }
    }

    mutating func setStationPosition(_ type: ConnectionSectionType, to point: CGPoint) {
        stationPositionsRaw[type.rawValue] = CodablePoint(point)
        lastModified = Date()
    }

    mutating func clearStationPositions() {
        stationPositionsRaw.removeAll()
        lastModified = Date()
    }

    mutating func appendCollaboratorMessage(_ message: CollaboratorMessage) {
        collaboratorMessages.append(message)
        if collaboratorMessages.count > 50 {
            collaboratorMessages.removeFirst(collaboratorMessages.count - 50)
        }
        lastModified = Date()
    }

    mutating func setLiveInsights(_ insights: [LiveInsight]) {
        liveInsights = Array(insights.prefix(20))
        lastModified = Date()
    }

    // MARK: - Codable (explicit to accept V1 JSON without V2 keys)

    private enum CodingKeys: String, CodingKey {
        case atomUUID, sections, viewportState, floatingPanelIDs, isGeneratingGhosts, lastModified
        case conceptType, stationPositionsRaw, forgeMode, liveInsights, collaboratorMessages
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.atomUUID = try c.decode(String.self, forKey: .atomUUID)
        self.sections = try c.decode([ConnectionSection].self, forKey: .sections)
        self.viewportState = try c.decode(CanvasViewportState.self, forKey: .viewportState)
        self.floatingPanelIDs = try c.decode([UUID].self, forKey: .floatingPanelIDs)
        self.isGeneratingGhosts = try c.decode(Bool.self, forKey: .isGeneratingGhosts)
        self.lastModified = try c.decode(Date.self, forKey: .lastModified)
        // V2 fields — tolerate absence from V1 persisted JSON.
        self.conceptType = try c.decodeIfPresent(ConceptFrameworkType.self, forKey: .conceptType) ?? .mentalModel
        self.stationPositionsRaw = try c.decodeIfPresent([String: CodablePoint].self, forKey: .stationPositionsRaw) ?? [:]
        self.forgeMode = try c.decodeIfPresent(ForgeMode.self, forKey: .forgeMode) ?? .forge
        self.liveInsights = try c.decodeIfPresent([LiveInsight].self, forKey: .liveInsights) ?? []
        self.collaboratorMessages = try c.decodeIfPresent([CollaboratorMessage].self, forKey: .collaboratorMessages) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(atomUUID, forKey: .atomUUID)
        try c.encode(sections, forKey: .sections)
        try c.encode(viewportState, forKey: .viewportState)
        try c.encode(floatingPanelIDs, forKey: .floatingPanelIDs)
        try c.encode(isGeneratingGhosts, forKey: .isGeneratingGhosts)
        try c.encode(lastModified, forKey: .lastModified)
        try c.encode(conceptType, forKey: .conceptType)
        try c.encode(stationPositionsRaw, forKey: .stationPositionsRaw)
        try c.encode(forgeMode, forKey: .forgeMode)
        try c.encode(liveInsights, forKey: .liveInsights)
        try c.encode(collaboratorMessages, forKey: .collaboratorMessages)
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

    mutating func updateItem(_ item: ConnectionItem, inSection type: ConnectionSectionType) {
        if let index = sections.firstIndex(where: { $0.type == type }) {
            sections[index].updateItem(item)
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

    var flattenedBodyText: String {
        sections
            .filter { !$0.items.isEmpty }
            .map { section in
                let lines = section.items
                    .map { "• \($0.resolvedPlainText)" }
                    .joined(separator: "\n")
                return "\(section.type.displayName)\n\(lines)"
            }
            .joined(separator: "\n\n")
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
