// CosmoOS/Data/Models/AtomExtensions.swift
// Convenience extensions for typed Atom access
// Replaces legacy AtomWrappers with direct Atom extensions

import Foundation

// MARK: - Content Atom Extensions

extension Atom {
    /// Content-specific accessors (when type == .content)
    var contentMetadata: ContentMetadata? {
        metadataValue(as: ContentMetadata.self)
    }

    var status: String {
        contentMetadata?.status ?? taskMetadata?.status ?? projectMetadata?.status ?? "draft"
    }

    var contentType: String? {
        contentMetadata?.contentType
    }

    var scheduledAt: String? {
        contentMetadata?.scheduledAt
    }

    var lastOpenedAt: String? {
        contentMetadata?.lastOpenedAt
    }

    /// Factory for Content atoms
    static func new(title: String, body: String) -> Atom {
        Atom.new(type: .content, title: title, body: body)
    }
}

// MARK: - Idea Atom Factory

extension Atom {
    /// Factory for Idea atoms with content
    static func new(title: String, content: String) -> Atom {
        Atom.new(type: .idea, title: title, body: content)
    }

    /// Connection ID from links (if linked to a connection)
    var connectionId: Int64? {
        // Check for connection link in links list
        linksList.first { $0.type == AtomLinkType.connection.rawValue }.flatMap { _ in
            // Would need to resolve UUID to ID - not directly possible without DB lookup
            nil
        }
    }
}

// MARK: - Task Atom Factory

extension Atom {
    /// Factory for Task atoms
    static func new(title: String, status: String) -> Atom {
        var meta = TaskMetadata()
        meta.status = status
        let metadataJson = try? String(data: JSONEncoder().encode(meta), encoding: .utf8)
        return Atom.new(type: .task, title: title, metadata: metadataJson)
    }
}

// MARK: - Idea Atom Extensions

extension Atom {
    var ideaMetadata: IdeaMetadata? {
        metadataValue(as: IdeaMetadata.self)
    }

    var tagsList: [String] {
        ideaMetadata?.tags ?? contentMetadata?.tags ?? researchMetadata?.tags ?? []
    }

    /// Legacy: tags as comma-separated string
    var tags: String? {
        let list = tagsList
        return list.isEmpty ? nil : list.joined(separator: ", ")
    }

    var isPinned: Bool {
        ideaMetadata?.isPinned ?? false
    }

    var pinnedAt: String? {
        ideaMetadata?.pinnedAt
    }

    /// Legacy: `content` property for ideas (returns body)
    var content: String {
        get { body ?? "" }
        set { body = newValue }
    }
}

// MARK: - Task Atom Extensions

extension Atom {
    var taskMetadata: TaskMetadata? {
        metadataValue(as: TaskMetadata.self)
    }

    var priority: String {
        taskMetadata?.priority ?? projectMetadata?.priority ?? ideaMetadata?.priority ?? "normal"
    }

    var dueDate: String? {
        taskMetadata?.dueDate
    }

    var startTime: String? {
        taskMetadata?.startTime
    }

    var endTime: String? {
        taskMetadata?.endTime
    }

    var durationMinutes: Int? {
        taskMetadata?.durationMinutes
    }

    var focusDate: String? {
        taskMetadata?.focusDate
    }

    var isUnscheduled: Bool {
        taskMetadata?.isUnscheduled ?? false
    }

    var isCompleted: Bool {
        taskMetadata?.isCompleted ?? false
    }

    var completedAt: String? {
        taskMetadata?.completedAt
    }

    var color: String? {
        taskMetadata?.color ?? projectMetadata?.color
    }

    /// Task description/notes
    var description: String? {
        get { taskMetadata?.description ?? body }
        set { updateTaskMetadata { $0.description = newValue } }
    }

    /// Helper to update task metadata
    private mutating func updateTaskMetadata(_ update: (inout TaskMetadata) -> Void) {
        var meta = taskMetadata ?? TaskMetadata()
        update(&meta)
        if let encoded = try? JSONEncoder().encode(meta),
           let jsonString = String(data: encoded, encoding: .utf8) {
            self.metadata = jsonString
        }
    }

    /// Task checklist (JSON string of ChecklistItem array)
    var checklist: String? {
        taskMetadata?.checklist
    }

    /// Task recurrence (JSON string of recurrence pattern)
    var recurrence: String? {
        taskMetadata?.recurrence
    }
}

// MARK: - Project Atom Extensions

extension Atom {
    var projectMetadata: ProjectMetadata? {
        metadataValue(as: ProjectMetadata.self)
    }
}

// MARK: - Research Atom Extensions

extension Atom {
    var researchMetadata: ResearchMetadata? {
        get { metadataValue(as: ResearchMetadata.self) }
    }

    /// Helper to update research metadata
    private mutating func updateResearchMetadata(_ update: (inout ResearchMetadata) -> Void) {
        var meta = researchMetadata ?? ResearchMetadata()
        update(&meta)
        if let encoded = try? JSONEncoder().encode(meta),
           let jsonString = String(data: encoded, encoding: .utf8) {
            self.metadata = jsonString
        }
    }

    var url: String? {
        get { researchMetadata?.url }
        set { updateResearchMetadata { $0.url = newValue } }
    }

    var summary: String? {
        get { researchMetadata?.summary }
        set { updateResearchMetadata { $0.summary = newValue } }
    }

    var researchType: String? {
        get { researchMetadata?.researchType }
        set { updateResearchMetadata { $0.researchType = newValue } }
    }

    var processingStatus: String? {
        get { researchMetadata?.processingStatus }
        set { updateResearchMetadata { $0.processingStatus = newValue } }
    }

    var thumbnailUrl: String? {
        get { researchMetadata?.thumbnailUrl }
        set { updateResearchMetadata { $0.thumbnailUrl = newValue } }
    }

    var query: String? {
        get { researchMetadata?.query }
        set { updateResearchMetadata { $0.query = newValue } }
    }

    var findings: String? {
        get { researchMetadata?.findings }
        set { updateResearchMetadata { $0.findings = newValue } }
    }

    // Swipe file properties
    var hook: String? {
        get { researchMetadata?.hook }
        set { updateResearchMetadata { $0.hook = newValue } }
    }

    var emotionTone: String? {
        get { researchMetadata?.emotionTone }
        set { updateResearchMetadata { $0.emotionTone = newValue } }
    }

    var structureType: String? {
        get { researchMetadata?.structureType }
        set { updateResearchMetadata { $0.structureType = newValue } }
    }

    var isSwipeFile: Bool {
        get { researchMetadata?.isSwipeFile ?? false }
        set { updateResearchMetadata { $0.isSwipeFile = newValue } }
    }

    var contentSource: String? {
        get { researchMetadata?.contentSource }
        set { updateResearchMetadata { $0.contentSource = newValue } }
    }

    // Rich content from structured data
    var richContent: ResearchRichContent? {
        structuredData(as: ResearchStructured.self).flatMap { structured in
            guard let autoMetadata = structured.autoMetadata,
                  let data = autoMetadata.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(ResearchRichContent.self, from: data)
        }
    }

    var sourceType: ResearchRichContent.SourceType? {
        richContent?.sourceType
    }

    var videoId: String? {
        richContent?.videoId
    }

    var transcriptSegments: [TranscriptSegment]? {
        richContent?.transcriptSegments
    }

    var domain: String? {
        guard let urlString = url, let url = URL(string: urlString) else { return nil }
        return url.host
    }

    /// Formatted transcript from all segments
    var formattedTranscript: String? {
        guard let segments = transcriptSegments, !segments.isEmpty else { return nil }
        return segments.map { $0.text }.joined(separator: " ")
    }

    /// Formatted duration string (e.g., "12:34")
    var formattedDuration: String? {
        guard let segments = transcriptSegments, let last = segments.last else { return nil }
        let totalSeconds = Int(last.end)  // Use end time as total duration
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Factory method to create a new Research atom
    static func new(
        title: String?,
        query: String? = nil,
        url: String? = nil,
        sourceType: ResearchRichContent.SourceType? = nil
    ) -> Atom {
        var meta = ResearchMetadata()
        meta.url = url
        meta.query = query
        if let sourceType = sourceType {
            meta.researchType = sourceType.rawValue
        }

        let metadataJson = try? String(data: JSONEncoder().encode(meta), encoding: .utf8)

        return Atom.new(
            type: .research,
            title: title,
            metadata: metadataJson
        )
    }

    /// Set rich content for research
    mutating func setRichContent(_ richContent: ResearchRichContent) {
        var structured = structuredData(as: ResearchStructured.self) ?? ResearchStructured()
        if let encoded = try? JSONEncoder().encode(richContent),
           let jsonString = String(data: encoded, encoding: .utf8) {
            structured.autoMetadata = jsonString
        }
        if let structuredEncoded = try? JSONEncoder().encode(structured),
           let structuredString = String(data: structuredEncoded, encoding: .utf8) {
            self.structured = structuredString
        }
    }

    /// Personal notes for research
    var personalNotes: String? {
        get { researchMetadata?.personalNotes }
        set { updateResearchMetadata { $0.personalNotes = newValue } }
    }

    // MARK: - Swipe File Factory Methods

    /// Create a swipe file from Instagram content
    static func swipeFromInstagram(instagramId: String, url: String, hook: String?, type: ResearchRichContent.InstagramContentType = .post) -> Atom {
        var atom = Research.new(
            title: hook ?? "Instagram",
            query: nil,
            url: url,
            sourceType: .instagram
        )
        atom.hook = hook
        atom.isSwipeFile = true
        atom.contentSource = "instagram"

        var richContent = ResearchRichContent()
        richContent.sourceType = .instagram
        richContent.instagramId = instagramId
        richContent.instagramType = type.rawValue
        atom.setRichContent(richContent)

        return atom
    }

    /// Create a swipe file from YouTube content
    static func swipeFromYouTube(videoId: String, url: String, hook: String?, isShort: Bool = false) -> Atom {
        var atom = Research.new(
            title: hook ?? "YouTube Video",
            query: nil,
            url: url,
            sourceType: isShort ? .youtubeShort : .youtube
        )
        atom.hook = hook
        atom.isSwipeFile = true
        atom.contentSource = "youtube"

        var richContent = ResearchRichContent()
        richContent.sourceType = isShort ? .youtubeShort : .youtube
        richContent.videoId = videoId
        atom.setRichContent(richContent)

        return atom
    }

    /// Create a swipe file from X/Twitter post
    static func swipeFromXPost(tweetId: String, url: String, hook: String?) -> Atom {
        var atom = Research.new(
            title: hook ?? "X Post",
            query: nil,
            url: url,
            sourceType: .twitter
        )
        atom.hook = hook
        atom.isSwipeFile = true
        atom.contentSource = "x"

        var richContent = ResearchRichContent()
        richContent.sourceType = .twitter
        richContent.tweetId = tweetId
        atom.setRichContent(richContent)

        return atom
    }

    /// Create a swipe file from Threads post
    static func swipeFromThreads(threadId: String, url: String, hook: String?) -> Atom {
        var atom = Research.new(
            title: hook ?? "Threads Post",
            query: nil,
            url: url,
            sourceType: .threads
        )
        atom.hook = hook
        atom.isSwipeFile = true
        atom.contentSource = "threads"

        var richContent = ResearchRichContent()
        richContent.sourceType = .threads
        richContent.threadsId = threadId
        atom.setRichContent(richContent)

        return atom
    }

    /// Create a swipe file from raw text
    static func swipeFromRawText(text: String, hook: String?) -> Atom {
        var atom = Research.new(
            title: hook ?? "Saved Text",
            query: nil,
            url: nil,
            sourceType: nil
        )
        atom.hook = hook
        atom.body = text
        atom.isSwipeFile = true
        atom.contentSource = "clipboard"
        atom.processingStatus = "complete"
        return atom
    }

    /// Create a new swipe file with specified source type
    static func newSwipeFile(url: String, hook: String?, sourceType: ResearchRichContent.SourceType, contentSource: SwipeContentSource) -> Atom {
        var atom = Research.new(
            title: hook ?? "Saved Content",
            query: nil,
            url: url,
            sourceType: sourceType
        )
        atom.hook = hook
        atom.isSwipeFile = true
        atom.contentSource = contentSource.rawValue

        var richContent = ResearchRichContent()
        richContent.sourceType = sourceType
        atom.setRichContent(richContent)

        return atom
    }
}

// MARK: - Connection Atom Extensions

extension Atom {
    var connectionStructured: ConnectionStructured? {
        structuredData(as: ConnectionStructured.self)
    }

    var idea: String? {
        connectionStructured?.idea
    }

    var personalBelief: String? {
        connectionStructured?.personalBelief
    }

    var goal: String? {
        connectionStructured?.goal
    }

    var problems: String? {
        connectionStructured?.problems
    }

    var benefit: String? {
        connectionStructured?.benefit
    }

    var beliefsObjections: String? {
        connectionStructured?.beliefsObjections
    }

    var example: String? {
        connectionStructured?.example
    }

    var process: String? {
        connectionStructured?.process
    }

    var notes: String? {
        connectionStructured?.notes
    }

    var extractionConfidence: Double? {
        connectionStructured?.extractionConfidence
    }

    /// Combined text for semantic search
    var combinedText: String {
        [title, idea, personalBelief, goal, problems, benefit, example, process, notes, body]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Set mental model for connection
    mutating func setMentalModel(_ model: ConnectionMentalModel) {
        if let encoded = try? JSONEncoder().encode(model),
           let jsonString = String(data: encoded, encoding: .utf8) {
            self.structured = jsonString
        }
    }

    /// Get linked knowledge items
    var linkedKnowledgeItems: [LinkedKnowledgeItem] {
        guard let json = mentalModel?.linkedKnowledge,
              let data = json.data(using: .utf8),
              let items = try? JSONDecoder().decode([LinkedKnowledgeItem].self, from: data) else {
            return []
        }
        return items
    }

    /// Get references from mental model
    var references: [ConnectionReference] {
        guard let json = mentalModel?.referencesData,
              let data = json.data(using: .utf8),
              let refs = try? JSONDecoder().decode([ConnectionReference].self, from: data) else {
            return []
        }
        return refs
    }

    /// Add a reference
    mutating func addReference(_ ref: ConnectionReference) {
        var refs = references
        refs.append(ref)
        setReferences(refs)
    }

    /// Set all references
    mutating func setReferences(_ refs: [ConnectionReference]) {
        guard var model = mentalModel ?? ConnectionMentalModel() as ConnectionMentalModel? else { return }
        if let encoded = try? JSONEncoder().encode(refs),
           let json = String(data: encoded, encoding: .utf8) {
            model.referencesData = json
            setMentalModel(model)
        }
    }
}

// MARK: - Legacy Wrapper Type Aliases
// These provide drop-in compatibility for existing code

typealias ContentWrapper = Atom
typealias IdeaWrapper = Atom
typealias TaskWrapper = Atom
typealias ProjectWrapper = Atom
typealias ResearchWrapper = Atom
typealias ConnectionWrapper = Atom
typealias UncommittedItemWrapper = Atom
typealias JournalEntryWrapper = Atom
typealias CalendarEventWrapper = Atom
typealias ScheduleBlockWrapper = Atom

// MARK: - Direct Model Type Aliases
// These allow using simple names like "Idea" instead of "Atom"
// Note: Several types are NOT aliased to avoid conflicts:
// - Task: conflicts with Swift's Task concurrency type
// - JournalEntry: defined in CosmoCore.swift
// - ScheduleBlock: defined in Scheduler/Shared/ScheduleBlock.swift
// - CalendarEvent: would conflict with metadata types
// - Content: conflicts with SwiftUI's ViewModifier.Content
// - Connection: may conflict with other Connection types
// - Project: may conflict with other Project types

typealias Idea = Atom
typealias CosmoTask = Atom
typealias Research = Atom
typealias Connection = Atom
typealias UncommittedItem = Atom
typealias Project = Atom
typealias CosmoContent = Atom

// MARK: - ConnectionMentalModel (structured data for connections)

struct ConnectionMentalModel: Codable, Sendable, Equatable {
    var idea: String?
    var personalBelief: String?
    var goal: String?
    var problem: String?     // Singular for compatibility
    var problems: String?    // Plural alias
    var benefit: String?     // Singular for compatibility
    var benefits: String?    // Plural alias
    var beliefsObjections: String?
    var example: String?
    var process: String?
    var notes: String?
    var referencesData: String?
    var sourceText: String?
    var extractionConfidence: Double?
    var linkedKnowledge: String?
    var linkedKnowledgeUpdatedAt: String?
    var conceptName: String?

    /// Alias for idea (legacy compatibility) - computed, not encoded
    var coreIdea: String? {
        get { idea }
        set { idea = newValue }
    }

    init(
        idea: String? = nil,
        personalBelief: String? = nil,
        goal: String? = nil,
        problem: String? = nil,
        problems: String? = nil,
        benefit: String? = nil,
        benefits: String? = nil,
        beliefsObjections: String? = nil,
        example: String? = nil,
        process: String? = nil,
        notes: String? = nil,
        referencesData: String? = nil,
        sourceText: String? = nil,
        extractionConfidence: Double? = nil,
        linkedKnowledge: String? = nil,
        linkedKnowledgeUpdatedAt: String? = nil,
        conceptName: String? = nil
    ) {
        self.idea = idea
        self.personalBelief = personalBelief
        self.goal = goal
        self.problem = problem ?? problems
        self.problems = problems ?? problem
        self.benefit = benefit ?? benefits
        self.benefits = benefits ?? benefit
        self.beliefsObjections = beliefsObjections
        self.example = example
        self.process = process
        self.notes = notes
        self.referencesData = referencesData
        self.sourceText = sourceText
        self.extractionConfidence = extractionConfidence
        self.linkedKnowledge = linkedKnowledge
        self.linkedKnowledgeUpdatedAt = linkedKnowledgeUpdatedAt
        self.conceptName = conceptName
    }
}

// MARK: - LinkedKnowledgeItem (for knowledge linking UI)

struct LinkedKnowledgeItem: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let type: String
    let relevance: Double
    var entityType: String?
    var entityId: Int64?
    var relevanceScore: Double?
    var explanation: String?

    init(id: String = UUID().uuidString, title: String, type: String, relevance: Double = 0.5) {
        self.id = id
        self.title = title
        self.type = type
        self.relevance = relevance
    }

    /// Full initializer for KnowledgeLinker
    init(entityType: String, entityId: Int64, title: String, relevanceScore: Double, explanation: String?) {
        self.id = UUID().uuidString
        self.title = title
        self.type = entityType
        self.relevance = relevanceScore
        self.entityType = entityType
        self.entityId = entityId
        self.relevanceScore = relevanceScore
        self.explanation = explanation
    }
}

// MARK: - ConnectionReference (for connection references)

struct ConnectionReference: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var url: String?
    var author: String?
    var notes: String?
    var entityType: String?
    var entityId: Int64?

    init(id: String = UUID().uuidString, title: String, url: String? = nil, author: String? = nil, notes: String? = nil, entityType: String? = nil, entityId: Int64? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.author = author
        self.notes = notes
        self.entityType = entityType
        self.entityId = entityId
    }
}

extension Atom {
    /// Get the mental model from a Connection atom
    var mentalModel: ConnectionMentalModel? {
        structuredData(as: ConnectionMentalModel.self)
    }

    /// Get or create mental model (never nil)
    var mentalModelOrNew: ConnectionMentalModel {
        mentalModel ?? ConnectionMentalModel()
    }

    /// Create a copy with updated mental model
    func withMentalModel(_ model: ConnectionMentalModel) -> Atom {
        withStructured(model)
    }
}

// MARK: - UncommittedItem Extensions

extension Atom {
    var uncommittedMetadata: UncommittedItemMetadata? {
        metadataValue(as: UncommittedItemMetadata.self)
    }

    var rawText: String {
        title ?? body ?? ""
    }

    var inferredProject: String? {
        uncommittedMetadata?.inferredProject
    }

    var inferredProjectConfidence: Double? {
        uncommittedMetadata?.inferredProjectConfidence
    }

    var inferredType: String? {
        uncommittedMetadata?.inferredType
    }

    var assignmentStatusEnum: AssignmentStatus {
        guard let status = uncommittedMetadata?.assignmentStatus,
              let enumValue = AssignmentStatus(rawValue: status) else {
            return .unassigned
        }
        return enumValue
    }

    var captureMethod: String? {
        uncommittedMetadata?.captureMethod
    }

    var isArchived: Bool {
        uncommittedMetadata?.isArchived ?? false
    }

    var expiresAt: String? {
        uncommittedMetadata?.expiresAt
    }

    var projectId: Int64? {
        // Get from links if available
        if link(ofType: .project) != nil {
            // Would need to resolve UUID to ID - for now return nil
            return nil
        }
        return nil
    }
}

// MARK: - Wrapper Initializer Compatibility

extension Atom {
    /// Legacy compatibility: Initialize "wrapper" from atom
    /// Usage: ContentWrapper(atom: someAtom) -> returns the same atom
    init(atom: Atom) {
        self = atom
    }

    /// Legacy compatibility: Access the underlying atom
    /// Usage: wrapper.atom -> returns self
    var atom: Atom {
        self
    }
}
