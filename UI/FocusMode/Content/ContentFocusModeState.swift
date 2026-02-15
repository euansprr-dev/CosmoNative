// CosmoOS/UI/FocusMode/Content/ContentFocusModeState.swift
// State model for Content Focus Mode - brainstorm, draft, polish workflow
// February 2026

import SwiftUI
import Foundation

// MARK: - Content Step

/// The three phases of the content creation workflow
enum ContentStep: String, Codable, CaseIterable {
    case brainstorm
    case draft
    case polish

    var label: String {
        switch self {
        case .brainstorm: return "Brainstorm"
        case .draft: return "Draft"
        case .polish: return "Polish"
        }
    }

    var icon: String {
        switch self {
        case .brainstorm: return "lightbulb.max.fill"
        case .draft: return "doc.text.fill"
        case .polish: return "sparkles"
        }
    }

    var stepNumber: Int {
        switch self {
        case .brainstorm: return 1
        case .draft: return 2
        case .polish: return 3
        }
    }
}

// MARK: - Outline Item

/// A single item in the content outline with title/reasoning separation.
/// Title is short and scannable; reasoning holds full AI detail, shooting notes, examples.
struct OutlineItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var reasoning: String
    var estimatedSeconds: Int?
    var sortOrder: Int
    var isCompleted: Bool

    /// Backward-compatible alias — maps .text to title for existing callers.
    var text: String {
        get { title }
        set { title = newValue }
    }

    init(id: UUID = UUID(), title: String, reasoning: String = "", estimatedSeconds: Int? = nil, sortOrder: Int, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.reasoning = reasoning
        self.estimatedSeconds = estimatedSeconds
        self.sortOrder = sortOrder
        self.isCompleted = isCompleted
    }

    // MARK: - Backward-Compatible Decoding

    enum CodingKeys: String, CodingKey {
        case id, title, reasoning, estimatedSeconds, sortOrder, isCompleted
        case text // legacy key
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        estimatedSeconds = try container.decodeIfPresent(Int.self, forKey: .estimatedSeconds)

        // New format: title + reasoning
        if let t = try container.decodeIfPresent(String.self, forKey: .title) {
            title = t
            reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning) ?? ""
        } else if let legacyText = try container.decodeIfPresent(String.self, forKey: .text) {
            // Legacy format: single "text" field — migrate to title, leave reasoning empty
            title = legacyText
            reasoning = ""
        } else {
            title = ""
            reasoning = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(reasoning, forKey: .reasoning)
        try container.encodeIfPresent(estimatedSeconds, forKey: .estimatedSeconds)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(isCompleted, forKey: .isCompleted)
    }
}

// MARK: - Related Content Tier

enum RelatedContentTier: String, Codable, Sendable, CaseIterable {
    case primary    // Same format + niche research — gold badge
    case secondary  // Same niche content — silver badge
    case tertiary   // Broad semantic match — gray badge

    var label: String {
        switch self {
        case .primary: return "TOP MATCHES"
        case .secondary: return "SAME NICHE"
        case .tertiary: return "RELATED"
        }
    }

    var accentColor: Color {
        switch self {
        case .primary: return Color(hex: "#FFD700")   // Gold
        case .secondary: return Color(hex: "#C0C0C0") // Silver
        case .tertiary: return Color.white.opacity(0.3)
        }
    }
}

// MARK: - Related Atom Reference

/// A lightweight reference to a related atom found via search
struct RelatedAtomRef: Identifiable, Codable, Equatable {
    let id: UUID
    let atomUUID: String
    let title: String
    let type: AtomType
    let relevanceScore: Double
    let preview: String
    var tier: RelatedContentTier

    init(
        id: UUID = UUID(),
        atomUUID: String,
        title: String,
        type: AtomType,
        relevanceScore: Double,
        preview: String,
        tier: RelatedContentTier = .tertiary
    ) {
        self.id = id
        self.atomUUID = atomUUID
        self.title = title
        self.type = type
        self.relevanceScore = relevanceScore
        self.preview = preview
        self.tier = tier
    }
}

// MARK: - NSRange Wrapper

/// Codable wrapper for NSRange since NSRange is not natively Codable
struct NSRangeWrapper: Codable, Equatable {
    let location: Int
    let length: Int

    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }

    init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    init(_ range: NSRange) {
        self.location = range.location
        self.length = range.length
    }
}

// MARK: - Polish Analysis

/// Results from the writing analyzer - readability scores and sentence statistics
struct PolishAnalysis: Codable, Equatable {
    var fleschReadingEase: Double
    var fleschKincaidGrade: Double
    var averageSentenceLength: Double
    var averageWordLength: Double
    var sentenceCount: Int
    var wordCount: Int
    var paragraphCount: Int
    var longSentenceRanges: [NSRangeWrapper]
    var passiveVoiceRanges: [NSRangeWrapper]
    var adverbRanges: [NSRangeWrapper]

    init(
        fleschReadingEase: Double = 0,
        fleschKincaidGrade: Double = 0,
        averageSentenceLength: Double = 0,
        averageWordLength: Double = 0,
        sentenceCount: Int = 0,
        wordCount: Int = 0,
        paragraphCount: Int = 0,
        longSentenceRanges: [NSRangeWrapper] = [],
        passiveVoiceRanges: [NSRangeWrapper] = [],
        adverbRanges: [NSRangeWrapper] = []
    ) {
        self.fleschReadingEase = fleschReadingEase
        self.fleschKincaidGrade = fleschKincaidGrade
        self.averageSentenceLength = averageSentenceLength
        self.averageWordLength = averageWordLength
        self.sentenceCount = sentenceCount
        self.wordCount = wordCount
        self.paragraphCount = paragraphCount
        self.longSentenceRanges = longSentenceRanges
        self.passiveVoiceRanges = passiveVoiceRanges
        self.adverbRanges = adverbRanges
    }

    /// Human-readable readability label
    var readabilityLabel: String {
        switch fleschReadingEase {
        case 90...100: return "Very Easy"
        case 80..<90: return "Easy"
        case 70..<80: return "Fairly Easy"
        case 60..<70: return "Standard"
        case 50..<60: return "Fairly Difficult"
        case 30..<50: return "Difficult"
        default: return "Very Difficult"
        }
    }
}

// MARK: - AI Suggestion

/// An AI-generated writing suggestion
struct AISuggestion: Identifiable, Codable, Equatable {
    let id: UUID
    let originalText: String
    let suggestedText: String
    let reason: String
    var status: SuggestionStatus

    enum SuggestionStatus: String, Codable {
        case pending
        case accepted
        case dismissed
    }

    init(
        id: UUID = UUID(),
        originalText: String,
        suggestedText: String,
        reason: String,
        status: SuggestionStatus = .pending
    ) {
        self.id = id
        self.originalText = originalText
        self.suggestedText = suggestedText
        self.reason = reason
        self.status = status
    }
}

// MARK: - Content Focus Mode State

/// Complete state for a Content Focus Mode session
struct ContentFocusModeState: Codable {
    let atomUUID: String
    var currentStep: ContentStep
    var coreIdea: String
    var outline: [OutlineItem]
    var relatedAtoms: [RelatedAtomRef]
    var draftContent: String
    var polishAnalysis: PolishAnalysis?
    var aiSuggestions: [AISuggestion]
    var polishSystemPrompt: String
    var isContextPanelVisible: Bool
    var isAISuggestedOutline: Bool
    var lastModified: Date

    init(atomUUID: String) {
        self.atomUUID = atomUUID
        self.currentStep = .brainstorm
        self.coreIdea = ""
        self.outline = []
        self.relatedAtoms = []
        self.draftContent = ""
        self.polishAnalysis = nil
        self.aiSuggestions = []
        self.polishSystemPrompt = ""
        self.isContextPanelVisible = true
        self.isAISuggestedOutline = false
        self.lastModified = Date()
    }

    // MARK: - Outline Mutations

    mutating func addOutlineItem(_ title: String, reasoning: String = "", estimatedSeconds: Int? = nil) {
        let sortOrder = (outline.map(\.sortOrder).max() ?? -1) + 1
        let item = OutlineItem(title: title, reasoning: reasoning, estimatedSeconds: estimatedSeconds, sortOrder: sortOrder)
        outline.append(item)
        lastModified = Date()
    }

    mutating func updateOutlineItem(id: UUID, title: String) {
        if let idx = outline.firstIndex(where: { $0.id == id }) {
            outline[idx].title = title
            lastModified = Date()
        }
    }

    mutating func updateOutlineItemReasoning(id: UUID, reasoning: String) {
        if let idx = outline.firstIndex(where: { $0.id == id }) {
            outline[idx].reasoning = reasoning
            lastModified = Date()
        }
    }

    mutating func toggleOutlineItem(id: UUID) {
        if let idx = outline.firstIndex(where: { $0.id == id }) {
            outline[idx].isCompleted.toggle()
            lastModified = Date()
        }
    }

    mutating func removeOutlineItem(id: UUID) {
        outline.removeAll { $0.id == id }
        lastModified = Date()
    }

    mutating func moveOutlineItem(from source: IndexSet, to destination: Int) {
        outline.move(fromOffsets: source, toOffset: destination)
        for i in outline.indices {
            outline[i].sortOrder = i
        }
        lastModified = Date()
    }

    // MARK: - Related Atoms Mutations

    mutating func addRelatedAtom(_ ref: RelatedAtomRef) {
        if !relatedAtoms.contains(where: { $0.atomUUID == ref.atomUUID }) {
            relatedAtoms.append(ref)
            lastModified = Date()
        }
    }

    mutating func removeRelatedAtom(id: UUID) {
        relatedAtoms.removeAll { $0.id == id }
        lastModified = Date()
    }

    // MARK: - Suggestion Mutations

    mutating func acceptSuggestion(id: UUID) {
        if let idx = aiSuggestions.firstIndex(where: { $0.id == id }) {
            aiSuggestions[idx].status = .accepted
            // Apply the suggestion to draft content
            draftContent = draftContent.replacingOccurrences(
                of: aiSuggestions[idx].originalText,
                with: aiSuggestions[idx].suggestedText
            )
            lastModified = Date()
        }
    }

    mutating func dismissSuggestion(id: UUID) {
        if let idx = aiSuggestions.firstIndex(where: { $0.id == id }) {
            aiSuggestions[idx].status = .dismissed
            lastModified = Date()
        }
    }

    /// Map a ContentPhase to a ContentStep (returns nil for post-creation phases)
    static func stepForPhase(_ phase: ContentPhase) -> ContentStep? {
        switch phase {
        case .ideation: return .brainstorm
        case .draft: return .draft
        case .polish: return .polish
        default: return nil  // Post-creation phases
        }
    }

    /// Sorted outline items by sortOrder
    var sortedOutline: [OutlineItem] {
        outline.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Number of completed outline items
    var completedOutlineCount: Int {
        outline.filter(\.isCompleted).count
    }

    /// Pending AI suggestions
    var pendingSuggestions: [AISuggestion] {
        aiSuggestions.filter { $0.status == .pending }
    }
}

// MARK: - Atom-Based Persistence

extension ContentFocusModeState {
    /// Signal the ViewModel to write state to the atom in the database.
    /// Child views call this after mutations — the ViewModel handles the actual DB write.
    func save() {
        NotificationCenter.default.post(
            name: .contentFocusStateSaved,
            object: nil,
            userInfo: ["atomUUID": atomUUID]
        )
    }

    /// Load state from an Atom's body + metadata fields (replaces UserDefaults)
    static func from(atom: Atom) -> ContentFocusModeState? {
        guard let metadata = atom.metadata,
              let data = metadata.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Need at least a currentStep to consider this a valid focus state
        guard let stepRaw = dict["currentStep"] as? String,
              let step = ContentStep(rawValue: stepRaw) else {
            return nil
        }

        var state = ContentFocusModeState(atomUUID: atom.uuid)
        state.currentStep = step
        state.coreIdea = dict["coreIdea"] as? String ?? ""
        state.draftContent = atom.body ?? ""
        state.polishSystemPrompt = dict["polishSystemPrompt"] as? String ?? ""
        state.isContextPanelVisible = dict["isContextPanelVisible"] as? Bool ?? true
        state.isAISuggestedOutline = dict["isAISuggestedOutline"] as? Bool ?? false

        // Decode outline items
        if let outlineData = dict["outline"] {
            if let outlineJSON = try? JSONSerialization.data(withJSONObject: outlineData),
               let items = try? JSONDecoder().decode([OutlineItem].self, from: outlineJSON) {
                state.outline = items
            }
        }

        // Decode polish analysis
        if let analysisData = dict["polishAnalysis"] {
            if let analysisJSON = try? JSONSerialization.data(withJSONObject: analysisData),
               let analysis = try? JSONDecoder().decode(PolishAnalysis.self, from: analysisJSON) {
                state.polishAnalysis = analysis
            }
        }

        // Decode last modified
        if let modifiedStr = dict["lastModified"] as? String,
           let date = ISO8601DateFormatter().date(from: modifiedStr) {
            state.lastModified = date
        }

        return state
    }

    /// Encode state into atom fields for a DB write.
    /// Returns (body, metadataString) to write to the atoms table.
    func toAtomFields(existingMetadata: String?) -> (body: String?, metadata: String?) {
        // Preserve existing metadata keys
        var metadataDict: [String: Any] = [:]
        if let existing = existingMetadata,
           let data = existing.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            metadataDict = dict
        }

        // Write focus state fields
        metadataDict["currentStep"] = currentStep.rawValue
        metadataDict["coreIdea"] = coreIdea.isEmpty ? nil : coreIdea
        metadataDict["polishSystemPrompt"] = polishSystemPrompt.isEmpty ? nil : polishSystemPrompt
        metadataDict["isContextPanelVisible"] = isContextPanelVisible
        metadataDict["isAISuggestedOutline"] = isAISuggestedOutline
        metadataDict["lastModified"] = ISO8601DateFormatter().string(from: lastModified)

        // Encode outline as JSON array
        if !outline.isEmpty,
           let outlineData = try? JSONEncoder().encode(outline),
           let outlineArray = try? JSONSerialization.jsonObject(with: outlineData) {
            metadataDict["outline"] = outlineArray
        } else {
            metadataDict["outline"] = nil
        }

        // Encode polish analysis
        if let analysis = polishAnalysis,
           let analysisData = try? JSONEncoder().encode(analysis),
           let analysisDict = try? JSONSerialization.jsonObject(with: analysisData) {
            metadataDict["polishAnalysis"] = analysisDict
        }

        let metadataString: String?
        if !metadataDict.isEmpty,
           let metadataData = try? JSONSerialization.data(withJSONObject: metadataDict),
           let str = String(data: metadataData, encoding: .utf8) {
            metadataString = str
        } else {
            metadataString = nil
        }

        return (body: draftContent.isEmpty ? nil : draftContent, metadata: metadataString)
    }
}
