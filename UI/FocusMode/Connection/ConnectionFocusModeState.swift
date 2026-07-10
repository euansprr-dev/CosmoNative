// CosmoOS/UI/FocusMode/Connection/ConnectionFocusModeState.swift
// Data models and state for Connection Focus Mode
// 11 structured sections with items, ghost suggestions, and connected sources
// December 2025 - Complete rewrite following PRD spec
// April 2026 - V2 "The Crucible": concept type, station positions, live insights
// June 2026 - Workspace revamp: collaborator removed (now the /concept inline
//             assistant skill), ForgeMode replaced by ConnectionViewMode

import SwiftUI
import Foundation

// MARK: - Concept Framework Type (V2)

/// The shape of the framework being crystallized. Shown in the masthead and
/// surfaced to the /concept skill through the editable surface's Type line.
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

// MARK: - Codable CGPoint

/// CGPoint is already Codable on Foundation but we give it a stable Equatable-friendly
/// representation so Dictionary<_, CGPoint> round-trips cleanly through JSON.
struct CodablePoint: Codable, Equatable {
    let x: Double
    let y: Double
    init(_ point: CGPoint) { self.x = point.x; self.y = point.y }
    init(x: Double, y: Double) { self.x = x; self.y = y }
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

/// Codable wrapper for CGSize so resizable blocks can persist their size.
struct CodableSize: Codable, Equatable {
    let width: Double
    let height: Double
    init(_ size: CGSize) { self.width = size.width; self.height = size.height }
    init(width: Double, height: Double) { self.width = width; self.height = height }
    var cgSize: CGSize { CGSize(width: width, height: height) }
}

// MARK: - Connection Section Type

/// The 11 section types for a Connection atom.
/// V2 added `.claims`, `.evidence`, `.openQuestions` to support Inquiry crystallization
/// where verbatim captures are routed by `ExtractKind` into matching sections.
enum ConnectionSectionType: String, Codable, CaseIterable, Sendable {
    case goal               // What is the desired outcome?
    case problems           // What pain points does this solve?
    case claims             // Load-bearing assertions (V2)
    case evidence           // Supporting evidence with sources (V2)
    case benefits           // What are the positive outcomes?
    case examples           // Real-world applications
    case beliefsObjections  // Counterarguments, alternative views
    case process            // Step-by-step implementation
    case openQuestions      // Unresolved questions for further inquiry (V2)
    case conceptName        // Your unique name for this idea
    case references         // Sources and cross-Connection web

    var displayName: String {
        switch self {
        case .goal: return "Goal"
        case .problems: return "Problems"
        case .claims: return "Claims"
        case .evidence: return "Evidence"
        case .benefits: return "Benefits"
        case .examples: return "Examples"
        case .beliefsObjections: return "Beliefs & Objections"
        case .process: return "Process"
        case .openQuestions: return "Open Questions"
        case .conceptName: return "Concept Name"
        case .references: return "References"
        }
    }

    var icon: String {
        switch self {
        case .goal: return "target"
        case .problems: return "exclamationmark.triangle.fill"
        case .claims: return "exclamationmark.bubble.fill"
        case .evidence: return "checkmark.seal.fill"
        case .benefits: return "checkmark.circle.fill"
        case .examples: return "pin.fill"
        case .beliefsObjections: return "bubble.left.and.bubble.right.fill"
        case .process: return "list.number"
        case .openQuestions: return "questionmark.diamond.fill"
        case .conceptName: return "lightbulb.fill"
        case .references: return "book.fill"
        }
    }

    var promptQuestion: String {
        switch self {
        case .goal: return "What is the desired outcome?"
        case .problems: return "What pain points does this solve?"
        case .claims: return "What are you claiming to be true?"
        case .evidence: return "What evidence supports the claims?"
        case .benefits: return "What are the positive outcomes?"
        case .examples: return "What are real-world applications?"
        case .beliefsObjections: return "What are common views or counterarguments?"
        case .process: return "What are the implementation steps?"
        case .openQuestions: return "What's still unresolved?"
        case .conceptName: return "What is your unique name for this idea?"
        case .references: return "What sources support this?"
        }
    }

    var accentColor: Color {
        switch self {
        case .goal: return Color(hex: "#6366F1")          // Indigo
        case .problems: return Color(hex: "#EF4444")      // Red
        case .claims: return Color(hex: "#2D6A4F")        // Forest green (accent)
        case .evidence: return Color(hex: "#22C55E")      // Green (supports claims)
        case .benefits: return Color(hex: "#22C55E")      // Green
        case .examples: return Color(hex: "#F59E0B")      // Amber
        case .beliefsObjections: return Color(hex: "#8B5CF6")  // Purple
        case .process: return Color(hex: "#06B6D4")       // Cyan
        case .openQuestions: return Color(hex: "#818CF8") // Lavender (a known "question" tint in CosmoOS)
        case .conceptName: return Color(hex: "#F59E0B")   // Amber
        case .references: return Color(hex: "#6366F1")    // Indigo
        }
    }

    /// Three-letter abbreviation for dense layouts (canvas block, station dots).
    var abbreviation: String {
        switch self {
        case .goal: return "GOL"
        case .problems: return "PRB"
        case .claims: return "CLM"
        case .evidence: return "EVD"
        case .benefits: return "BEN"
        case .examples: return "EX"
        case .beliefsObjections: return "BEL"
        case .process: return "PRC"
        case .openQuestions: return "Q?"
        case .conceptName: return "CN"
        case .references: return "REF"
        }
    }

    /// Default order for display. Claims+evidence sit between problems and benefits
    /// (statement → support → outcome). Open questions sit between process and the
    /// closing meta sections (conceptName / references).
    var sortOrder: Int {
        switch self {
        case .goal: return 0
        case .problems: return 1
        case .claims: return 2
        case .evidence: return 3
        case .benefits: return 4
        case .examples: return 5
        case .beliefsObjections: return 6
        case .process: return 7
        case .openQuestions: return 8
        case .conceptName: return 9
        case .references: return 10
        }
    }

    /// V2 section types added in the Inquiry crystallization redesign.
    static let v2AddedTypes: Set<ConnectionSectionType> = [.claims, .evidence, .openQuestions]
}

// MARK: - Connection Section

/// A section in a Connection atom containing items
struct ConnectionSection: Identifiable, Codable, Equatable {
    let id: UUID
    let type: ConnectionSectionType
    var items: [ConnectionItem]
    var isExpanded: Bool

    init(
        id: UUID = UUID(),
        type: ConnectionSectionType,
        items: [ConnectionItem] = [],
        isExpanded: Bool = true
    ) {
        self.id = id
        self.type = type
        self.items = items
        self.isExpanded = isExpanded
    }

    var itemCount: Int {
        items.count
    }

    var hasContent: Bool {
        !items.isEmpty
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
    var linkedConnectionUUID: String?   // First-class link to another Connection page
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        content: String,
        document: RichDocument? = nil,
        plainText: String? = nil,
        sourceAtomUUID: String? = nil,
        sourceSnippet: String? = nil,
        linkedConnectionUUID: String? = nil
    ) {
        self.id = id
        self.content = content
        self.document = document ?? RichDocument.migrateLegacy(content)
        self.plainText = plainText ?? content
        self.sourceAtomUUID = sourceAtomUUID
        self.sourceSnippet = sourceSnippet
        self.linkedConnectionUUID = linkedConnectionUUID
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var hasSource: Bool {
        sourceAtomUUID != nil
    }

    /// True when this item is a hyperlink row to another Connection page.
    var isConnectionLink: Bool {
        linkedConnectionUUID != nil
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
    static let currentLayoutVersion = 2

    let atomUUID: String
    var sections: [ConnectionSection]
    var viewportState: CanvasViewportState
    var floatingPanelIDs: [UUID]
    var lastModified: Date

    // MARK: - V2 "The Crucible" fields (additive, backward-compatible)

    /// The shape of this framework — influences masthead subtitle and collaborator tone.
    var conceptType: ConceptFrameworkType = .mentalModel

    /// User-defined free positions for stations on the canvas.
    /// Empty = use the default 2x4 grid. Keyed by section type raw value
    /// because JSON dictionary keys must be strings.
    private var stationPositionsRaw: [String: CodablePoint] = [:]

    /// V3 unified canvas positions keyed by stable block id:
    /// - `"masthead"`, `"collaborator"`, `"insights"`, `"crystal"`, `"usage"`
    /// - `"station:<ConnectionSectionType.rawValue>"`
    /// - `"source:<atomUUID>"`
    /// Atom blocks (user-added) store their position in `FocusFloatingBlock.positionX/Y`
    /// via atom metadata, not here.
    private var canvasPositionsRaw: [String: CodablePoint] = [:]

    /// V3 unified canvas sizes for resizable blocks. Keyed same as `canvasPositionsRaw`.
    /// Non-resizable blocks use their intrinsic size and don't appear here.
    private var canvasSizesRaw: [String: CodableSize] = [:]

    /// V3 Phase 3: block ids hidden from the Connection canvas. Only intrinsic
    /// panels can be hidden (collaborator, insights, crystal, usage). `⌘⇧R`
    /// clears this set alongside positions/sizes.
    private var hiddenPanelsRaw: [String] = []

    /// Governs persisted layout migrations for the connection workspace.
    private var layoutVersion: Int = Self.currentLayoutVersion

    /// Current center-column view mode. Persisted under the legacy
    /// `forgeMode` key; old `forge`/`chalkboard` values map to `.board`.
    var viewMode: ConnectionViewMode = .board

    /// Rolling AI observations. Capped at 20 most recent.
    var liveInsights: [LiveInsight] = []

    init(atomUUID: String) {
        self.atomUUID = atomUUID
        // Initialize with all current sections.
        self.sections = ConnectionSectionType.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { ConnectionSection(type: $0) }
        self.viewportState = CanvasViewportState()
        self.floatingPanelIDs = []
        self.lastModified = Date()
        self.conceptType = .mentalModel
        self.stationPositionsRaw = [:]
        self.canvasPositionsRaw = [:]
        self.canvasSizesRaw = [:]
        self.hiddenPanelsRaw = []
        self.layoutVersion = Self.currentLayoutVersion
        self.viewMode = .board
        self.liveInsights = []
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

    // MARK: - V3 unified canvas positions

    /// Typed view of all canvas positions keyed by stable block id.
    var canvasPositions: [String: CGPoint] {
        get {
            var out: [String: CGPoint] = [:]
            for (key, value) in canvasPositionsRaw {
                out[key] = value.cgPoint
            }
            return out
        }
        set {
            var raw: [String: CodablePoint] = [:]
            for (key, value) in newValue {
                raw[key] = CodablePoint(value)
            }
            canvasPositionsRaw = raw
            lastModified = Date()
        }
    }

    mutating func setCanvasPosition(_ id: String, to point: CGPoint) {
        canvasPositionsRaw[id] = CodablePoint(point)
        lastModified = Date()
    }

    func canvasPosition(_ id: String) -> CGPoint? {
        canvasPositionsRaw[id]?.cgPoint
    }

    mutating func clearCanvasPositions() {
        canvasPositionsRaw.removeAll()
        canvasSizesRaw.removeAll()
        hiddenPanelsRaw.removeAll()
        lastModified = Date()
    }

    // MARK: - V3 Phase 3: hidden panels

    var hiddenPanels: Set<String> {
        get { Set(hiddenPanelsRaw) }
        set {
            hiddenPanelsRaw = Array(newValue)
            lastModified = Date()
        }
    }

    mutating func hidePanel(_ id: String) {
        if !hiddenPanelsRaw.contains(id) {
            hiddenPanelsRaw.append(id)
            lastModified = Date()
        }
    }

    mutating func showPanel(_ id: String) {
        if let idx = hiddenPanelsRaw.firstIndex(of: id) {
            hiddenPanelsRaw.remove(at: idx)
            lastModified = Date()
        }
    }

    func isPanelHidden(_ id: String) -> Bool {
        hiddenPanelsRaw.contains(id)
    }

    /// Typed view of canvas sizes for resizable blocks.
    var canvasSizes: [String: CGSize] {
        get {
            var out: [String: CGSize] = [:]
            for (key, value) in canvasSizesRaw {
                out[key] = value.cgSize
            }
            return out
        }
        set {
            var raw: [String: CodableSize] = [:]
            for (key, value) in newValue {
                raw[key] = CodableSize(value)
            }
            canvasSizesRaw = raw
            lastModified = Date()
        }
    }

    mutating func setCanvasSize(_ id: String, to size: CGSize) {
        canvasSizesRaw[id] = CodableSize(size)
        lastModified = Date()
    }

    func canvasSize(_ id: String) -> CGSize? {
        canvasSizesRaw[id]?.cgSize
    }

    mutating func setLiveInsights(_ insights: [LiveInsight]) {
        liveInsights = Array(insights.prefix(20))
        lastModified = Date()
    }

    // MARK: - Codable (explicit to accept V1/V2 JSON without newer keys —
    // legacy collaborator keys in old blobs are simply ignored)

    private enum CodingKeys: String, CodingKey {
        case atomUUID, sections, viewportState, floatingPanelIDs, lastModified
        case conceptType, stationPositionsRaw, forgeMode, liveInsights
        case canvasPositionsRaw, canvasSizesRaw, hiddenPanelsRaw, layoutVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.atomUUID = try c.decode(String.self, forKey: .atomUUID)
        let decodedSections = try c.decode([ConnectionSection].self, forKey: .sections)
        self.sections = Self.backfillingMissingSections(decodedSections)
        self.viewportState = try c.decode(CanvasViewportState.self, forKey: .viewportState)
        self.floatingPanelIDs = try c.decode([UUID].self, forKey: .floatingPanelIDs)
        self.lastModified = try c.decode(Date.self, forKey: .lastModified)
        // V2 fields — tolerate absence from V1 persisted JSON.
        self.conceptType = try c.decodeIfPresent(ConceptFrameworkType.self, forKey: .conceptType) ?? .mentalModel
        self.stationPositionsRaw = try c.decodeIfPresent([String: CodablePoint].self, forKey: .stationPositionsRaw) ?? [:]
        // Tolerant view-mode decode: V2 stored ForgeMode (forge/manuscript/chalkboard).
        let storedMode = try c.decodeIfPresent(String.self, forKey: .forgeMode) ?? ""
        self.viewMode = ConnectionViewMode(legacyRawValue: storedMode)
        self.liveInsights = try c.decodeIfPresent([LiveInsight].self, forKey: .liveInsights) ?? []
        self.layoutVersion = try c.decodeIfPresent(Int.self, forKey: .layoutVersion) ?? 0
        // V3 fields — migrate from V2 stationPositionsRaw when canvasPositionsRaw is empty.
        let decodedCanvasPositions = try c.decodeIfPresent([String: CodablePoint].self, forKey: .canvasPositionsRaw) ?? [:]
        if decodedCanvasPositions.isEmpty && !self.stationPositionsRaw.isEmpty {
            var migrated: [String: CodablePoint] = [:]
            for (key, value) in self.stationPositionsRaw {
                migrated["station:\(key)"] = value
            }
            self.canvasPositionsRaw = migrated
        } else {
            self.canvasPositionsRaw = decodedCanvasPositions
        }
        self.canvasSizesRaw = try c.decodeIfPresent([String: CodableSize].self, forKey: .canvasSizesRaw) ?? [:]
        self.hiddenPanelsRaw = try c.decodeIfPresent([String].self, forKey: .hiddenPanelsRaw) ?? []
        if layoutVersion < Self.currentLayoutVersion {
            self.stationPositionsRaw.removeAll()
            self.canvasPositionsRaw.removeAll()
            self.canvasSizesRaw.removeAll()
            self.hiddenPanelsRaw.removeAll()
            self.layoutVersion = Self.currentLayoutVersion
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(atomUUID, forKey: .atomUUID)
        try c.encode(sections, forKey: .sections)
        try c.encode(viewportState, forKey: .viewportState)
        try c.encode(floatingPanelIDs, forKey: .floatingPanelIDs)
        try c.encode(lastModified, forKey: .lastModified)
        try c.encode(conceptType, forKey: .conceptType)
        try c.encode(stationPositionsRaw, forKey: .stationPositionsRaw)
        try c.encode(viewMode.rawValue, forKey: .forgeMode)
        try c.encode(liveInsights, forKey: .liveInsights)
        try c.encode(canvasPositionsRaw, forKey: .canvasPositionsRaw)
        try c.encode(canvasSizesRaw, forKey: .canvasSizesRaw)
        try c.encode(hiddenPanelsRaw, forKey: .hiddenPanelsRaw)
        try c.encode(Self.currentLayoutVersion, forKey: .layoutVersion)
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

    static func backfillingMissingSections(_ decodedSections: [ConnectionSection]) -> [ConnectionSection] {
        var sectionsByType = Dictionary(uniqueKeysWithValues: decodedSections.map { ($0.type, $0) })
        for type in ConnectionSectionType.allCases where sectionsByType[type] == nil {
            sectionsByType[type] = ConnectionSection(type: type)
        }
        return ConnectionSectionType.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { sectionsByType[$0] }
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
        self.sections = ConnectionFocusModeState.backfillingMissingSections(sections)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSections = try c.decodeIfPresent([ConnectionSection].self, forKey: .sections) ?? []
        self.sections = ConnectionFocusModeState.backfillingMissingSections(decodedSections)
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
