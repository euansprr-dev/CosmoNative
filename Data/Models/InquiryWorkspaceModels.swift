// CosmoOS/Data/Models/InquiryWorkspaceModels.swift
// Inquiry Workspace primitives: Deep Dive, Inquiry Session, Question, Extract, Lexicon Entry.
// All persist as Atoms via metadata/structured JSON. See plan §3.

import Foundation

// MARK: - Shared enums

/// Maturity ladder for a Deep Dive (spark → exploring → developing → mature → evolving).
enum DeepDiveMaturity: String, Codable, CaseIterable, Sendable {
    case spark
    case exploring
    case developing
    case mature
    case evolving

    var displayName: String {
        switch self {
        case .spark: return "Spark"
        case .exploring: return "Exploring"
        case .developing: return "Developing"
        case .mature: return "Mature"
        case .evolving: return "Evolving"
        }
    }
}

/// Lifecycle for an Inquiry Session.
enum InquirySessionStatus: String, Codable, CaseIterable, Sendable {
    case active
    case paused
    case crystallized
    case archived
}

/// Layout mode for the 3-pane Inquiry Workspace (Cmd+1..5).
enum InquiryLayoutMode: String, Codable, CaseIterable, Sendable {
    case research
    case read
    case write
    case map
    case review

    var displayName: String {
        switch self {
        case .research: return "Research"
        case .read: return "Read"
        case .write: return "Write"
        case .map: return "Map"
        case .review: return "Review"
        }
    }
}

/// Lifecycle for a Question.
enum QuestionStatus: String, Codable, CaseIterable, Sendable {
    case open
    case researching
    case partiallyAnswered
    case answered
    case promoted
    case archived

    var displayName: String {
        switch self {
        case .open: return "Open"
        case .researching: return "Researching"
        case .partiallyAnswered: return "Partially Answered"
        case .answered: return "Answered"
        case .promoted: return "Promoted"
        case .archived: return "Archived"
        }
    }
}

/// Confidence in current working answer for a Question.
enum QuestionConfidence: String, Codable, CaseIterable, Sendable {
    case tentative
    case workingAnswer
    case confident
}

/// Kind of an Extract — the unit of meaning.
enum ExtractKind: String, Codable, CaseIterable, Sendable {
    case quote
    case highlight
    case claim
    case principle
    case example
    case objection
    case question
    case term
    case practice
    case outputIdea
    case reference
    case note
    case sourceSnippet
    case aiInsight

    var displayName: String {
        switch self {
        case .quote: return "Quote"
        case .highlight: return "Highlight"
        case .claim: return "Claim"
        case .principle: return "Principle"
        case .example: return "Example"
        case .objection: return "Objection"
        case .question: return "Question"
        case .term: return "Term"
        case .practice: return "Practice"
        case .outputIdea: return "Output Idea"
        case .reference: return "Reference"
        case .note: return "Note"
        case .sourceSnippet: return "Source Snippet"
        case .aiInsight: return "AI Insight"
        }
    }

    var iconName: String {
        switch self {
        case .quote: return "quote.opening"
        case .highlight: return "highlighter"
        case .claim: return "exclamationmark.bubble"
        case .principle: return "scope"
        case .example: return "lightbulb"
        case .objection: return "questionmark.diamond"
        case .question: return "questionmark.bubble"
        case .term: return "character.book.closed"
        case .practice: return "figure.mind.and.body"
        case .outputIdea: return "paperplane"
        case .reference: return "link"
        case .note: return "note.text"
        case .sourceSnippet: return "doc.plaintext"
        case .aiInsight: return "sparkles"
        }
    }
}

/// Lifecycle for an Extract.
enum ExtractStatus: String, Codable, CaseIterable, Sendable {
    case temporary
    case committed
    case ignored
    case promoted
}

/// Maturity ladder for a Lexicon Entry.
enum LexiconMaturity: String, Codable, CaseIterable, Sendable {
    case mention
    case term
    case entry
    case promotedToConnection
    case promotedToDeepDive

    var displayName: String {
        switch self {
        case .mention: return "Mention"
        case .term: return "Term"
        case .entry: return "Entry"
        case .promotedToConnection: return "Connection"
        case .promotedToDeepDive: return "Deep Dive"
        }
    }
}

// MARK: - Deep Dive

/// Metadata for `.deepDive` atoms.
struct DeepDiveMetadata: Codable, Sendable {
    var aliases: [String]?                   // Telegram routing shortcuts (["bw", "breath"])
    var parentThinkspaceUUIDs: [String]?     // Primary first
    var topicAliases: [String]?              // Alternate phrasings (semantic match)
    var maturity: DeepDiveMaturity?
    var lastInquiryAt: String?               // ISO8601
    var relatedDeepDiveUUIDs: [String]?
    var domainTagUUID: String?               // Optional clientProfile/domain affinity
    var coverGlyph: String?                  // SF symbol or symbolic identifier

    init(
        aliases: [String]? = nil,
        parentThinkspaceUUIDs: [String]? = nil,
        topicAliases: [String]? = nil,
        maturity: DeepDiveMaturity? = .spark,
        lastInquiryAt: String? = nil,
        relatedDeepDiveUUIDs: [String]? = nil,
        domainTagUUID: String? = nil,
        coverGlyph: String? = nil
    ) {
        self.aliases = aliases
        self.parentThinkspaceUUIDs = parentThinkspaceUUIDs
        self.topicAliases = topicAliases
        self.maturity = maturity
        self.lastInquiryAt = lastInquiryAt
        self.relatedDeepDiveUUIDs = relatedDeepDiveUUIDs
        self.domainTagUUID = domainTagUUID
        self.coverGlyph = coverGlyph
    }
}

/// Reference to an Extract used as evidence inside Current Understanding model updates.
struct ExtractRef: Codable, Sendable, Hashable {
    var extractUUID: String
    var snippet: String?
}

/// A core principle inside Current Understanding.
struct UnderstandingPrinciple: Codable, Sendable, Identifiable {
    var id: String
    var text: String
    var sourceUUIDs: [String]
    var lastUpdated: String?

    init(id: String = UUID().uuidString, text: String, sourceUUIDs: [String] = [], lastUpdated: String? = nil) {
        self.id = id
        self.text = text
        self.sourceUUIDs = sourceUUIDs
        self.lastUpdated = lastUpdated
    }
}

/// A user-authored stance.
struct UnderstandingBelief: Codable, Sendable, Identifiable {
    var id: String
    var text: String
    init(id: String = UUID().uuidString, text: String) {
        self.id = id
        self.text = text
    }
}

/// A user-noted uncertainty.
struct UnderstandingUncertainty: Codable, Sendable, Identifiable {
    var id: String
    var text: String
    init(id: String = UUID().uuidString, text: String) {
        self.id = id
        self.text = text
    }
}

/// A logged update to the Current Understanding model.
struct ModelUpdate: Codable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case small
        case section
        case breakthrough
        case contradiction
    }
    enum AcceptedBy: String, Codable, Sendable {
        case user
        case aiSuggestedAccepted
    }
    var id: String
    var date: String                  // ISO8601
    var kind: Kind
    var before: String
    var after: String
    var evidence: [ExtractRef]
    var sessionUUID: String?
    var acceptedBy: AcceptedBy

    init(
        id: String = UUID().uuidString,
        date: String,
        kind: Kind,
        before: String,
        after: String,
        evidence: [ExtractRef] = [],
        sessionUUID: String? = nil,
        acceptedBy: AcceptedBy = .user
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.before = before
        self.after = after
        self.evidence = evidence
        self.sessionUUID = sessionUUID
        self.acceptedBy = acceptedBy
    }
}

/// Snapshot of Current Understanding at a point in time (for version history).
struct ModelVersion: Codable, Sendable, Identifiable {
    var id: String
    var capturedAt: String           // ISO8601
    var oneSentenceModel: String
    var corePrinciples: [UnderstandingPrinciple]
    init(
        id: String = UUID().uuidString,
        capturedAt: String,
        oneSentenceModel: String,
        corePrinciples: [UnderstandingPrinciple]
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.oneSentenceModel = oneSentenceModel
        self.corePrinciples = corePrinciples
    }
}

/// The user's living model of a Deep Dive's topic.
struct CurrentUnderstanding: Codable, Sendable {
    var oneSentenceModel: String
    var corePrinciples: [UnderstandingPrinciple]
    var whatIBelieve: [UnderstandingBelief]
    var whatImUnsureAbout: [UnderstandingUncertainty]
    var recentUpdates: [ModelUpdate]
    var openQuestionUUIDs: [String]
    var explainSimply: String
    var explainExpertly: String
    var lastUpdated: String?           // ISO8601
    var versionHistory: [ModelVersion]

    init(
        oneSentenceModel: String = "",
        corePrinciples: [UnderstandingPrinciple] = [],
        whatIBelieve: [UnderstandingBelief] = [],
        whatImUnsureAbout: [UnderstandingUncertainty] = [],
        recentUpdates: [ModelUpdate] = [],
        openQuestionUUIDs: [String] = [],
        explainSimply: String = "",
        explainExpertly: String = "",
        lastUpdated: String? = nil,
        versionHistory: [ModelVersion] = []
    ) {
        self.oneSentenceModel = oneSentenceModel
        self.corePrinciples = corePrinciples
        self.whatIBelieve = whatIBelieve
        self.whatImUnsureAbout = whatImUnsureAbout
        self.recentUpdates = recentUpdates
        self.openQuestionUUIDs = openQuestionUUIDs
        self.explainSimply = explainSimply
        self.explainExpertly = explainExpertly
        self.lastUpdated = lastUpdated
        self.versionHistory = versionHistory
    }
}

/// Lightweight V1 placeholder for Practice Protocols (V2 promotes to its own AtomType).
struct PracticeProtocol: Codable, Sendable, Identifiable {
    var id: String
    var name: String
    var protocolText: String
    var useCase: String?
    var steps: [String]
    var effects: [String]
    var notes: String?
    var relatedSourceUUIDs: [String]
    var relatedPrincipleExtractUUIDs: [String]
    var logs: [PracticeLog]

    init(
        id: String = UUID().uuidString,
        name: String,
        protocolText: String = "",
        useCase: String? = nil,
        steps: [String] = [],
        effects: [String] = [],
        notes: String? = nil,
        relatedSourceUUIDs: [String] = [],
        relatedPrincipleExtractUUIDs: [String] = [],
        logs: [PracticeLog] = []
    ) {
        self.id = id
        self.name = name
        self.protocolText = protocolText
        self.useCase = useCase
        self.steps = steps
        self.effects = effects
        self.notes = notes
        self.relatedSourceUUIDs = relatedSourceUUIDs
        self.relatedPrincipleExtractUUIDs = relatedPrincipleExtractUUIDs
        self.logs = logs
    }
}

struct PracticeLog: Codable, Sendable, Identifiable {
    var id: String
    var date: String                 // ISO8601
    var observation: String
    var rating: Int?
    var context: String?

    init(id: String = UUID().uuidString, date: String, observation: String, rating: Int? = nil, context: String? = nil) {
        self.id = id
        self.date = date
        self.observation = observation
        self.rating = rating
        self.context = context
    }
}

/// A potential content angle surfaced during inquiry/crystallization.
struct OutputAngle: Codable, Sendable, Identifiable {
    var id: String
    var title: String
    var format: String?              // "carousel", "reel", "thread", "essay", etc.
    var rationale: String?
    var sourceExtractUUIDs: [String]
    var generatedAt: String          // ISO8601
    var promotedIdeaUUID: String?    // Set when "Send to Content Pipeline" creates an .idea atom

    init(
        id: String = UUID().uuidString,
        title: String,
        format: String? = nil,
        rationale: String? = nil,
        sourceExtractUUIDs: [String] = [],
        generatedAt: String = ISO8601DateFormatter().string(from: Date()),
        promotedIdeaUUID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.format = format
        self.rationale = rationale
        self.sourceExtractUUIDs = sourceExtractUUIDs
        self.generatedAt = generatedAt
        self.promotedIdeaUUID = promotedIdeaUUID
    }
}

/// Structured field for `.deepDive` atoms.
struct DeepDiveStructured: Codable, Sendable {
    var currentUnderstanding: CurrentUnderstanding
    var practiceProtocols: [PracticeProtocol]
    var outputAngles: [OutputAngle]

    init(
        currentUnderstanding: CurrentUnderstanding = CurrentUnderstanding(),
        practiceProtocols: [PracticeProtocol] = [],
        outputAngles: [OutputAngle] = []
    ) {
        self.currentUnderstanding = currentUnderstanding
        self.practiceProtocols = practiceProtocols
        self.outputAngles = outputAngles
    }
}

// MARK: - Inquiry Session

/// Metadata for `.inquirySession` atoms.
struct InquirySessionMetadata: Codable, Sendable {
    var parentDeepDiveUUID: String?
    var parentObjectUUID: String?            // Connection / cluster / question / inbox item
    var parentObjectType: String?            // "connection", "cluster", "question", "inboxItem"
    var mainQuestionUUID: String?            // Root Question atom
    var status: InquirySessionStatus
    var lastActiveAt: String                 // ISO8601
    var layoutMode: InquiryLayoutMode
    var crystallizedAt: String?

    init(
        parentDeepDiveUUID: String? = nil,
        parentObjectUUID: String? = nil,
        parentObjectType: String? = nil,
        mainQuestionUUID: String? = nil,
        status: InquirySessionStatus = .active,
        lastActiveAt: String = ISO8601DateFormatter().string(from: Date()),
        layoutMode: InquiryLayoutMode = .research,
        crystallizedAt: String? = nil
    ) {
        self.parentDeepDiveUUID = parentDeepDiveUUID
        self.parentObjectUUID = parentObjectUUID
        self.parentObjectType = parentObjectType
        self.mainQuestionUUID = mainQuestionUUID
        self.status = status
        self.lastActiveAt = lastActiveAt
        self.layoutMode = layoutMode
        self.crystallizedAt = crystallizedAt
    }
}

/// A research tree node (kind: question/source/extract/note/concept/ai/branch).
struct ResearchTreeNode: Codable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case question
        case source
        case extract
        case note
        case concept
        case ai
        case branch
    }

    struct Meta: Codable, Sendable {
        var label: String?
        var sourceTabId: String?
        var selectionRangeStart: Int?
        var selectionRangeEnd: Int?
        var aiSuggested: Bool
        var accepted: Bool
        init(
            label: String? = nil,
            sourceTabId: String? = nil,
            selectionRangeStart: Int? = nil,
            selectionRangeEnd: Int? = nil,
            aiSuggested: Bool = false,
            accepted: Bool = true
        ) {
            self.label = label
            self.sourceTabId = sourceTabId
            self.selectionRangeStart = selectionRangeStart
            self.selectionRangeEnd = selectionRangeEnd
            self.aiSuggested = aiSuggested
            self.accepted = accepted
        }
    }

    var id: String
    var kind: Kind
    var atomUUID: String?
    var parentNodeId: String?
    var childNodeIds: [String]
    var createdAt: String
    var branchOrder: Int
    var meta: Meta

    init(
        id: String = UUID().uuidString,
        kind: Kind,
        atomUUID: String? = nil,
        parentNodeId: String? = nil,
        childNodeIds: [String] = [],
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        branchOrder: Int = 0,
        meta: Meta = Meta()
    ) {
        self.id = id
        self.kind = kind
        self.atomUUID = atomUUID
        self.parentNodeId = parentNodeId
        self.childNodeIds = childNodeIds
        self.createdAt = createdAt
        self.branchOrder = branchOrder
        self.meta = meta
    }
}

/// Persisted research tree document inside `InquirySession.structured`.
struct ResearchTreeDocument: Codable, Sendable {
    var rootNodeId: String
    var nodes: [String: ResearchTreeNode]

    init(rootNodeId: String, nodes: [String: ResearchTreeNode]) {
        self.rootNodeId = rootNodeId
        self.nodes = nodes
    }

    /// Build a fresh tree with a single root question node.
    static func bootstrap(rootQuestionAtomUUID: String?) -> ResearchTreeDocument {
        let rootId = UUID().uuidString
        let root = ResearchTreeNode(
            id: rootId,
            kind: .question,
            atomUUID: rootQuestionAtomUUID,
            parentNodeId: nil,
            childNodeIds: [],
            branchOrder: 0,
            meta: ResearchTreeNode.Meta(label: "Main question", aiSuggested: false, accepted: true)
        )
        return ResearchTreeDocument(rootNodeId: rootId, nodes: [rootId: root])
    }

    /// Append a child node under the given parent. Returns the new node id.
    @discardableResult
    mutating func appendChild(parentId: String, kind: ResearchTreeNode.Kind, atomUUID: String? = nil, label: String? = nil, aiSuggested: Bool = false, accepted: Bool = true, sourceTabId: String? = nil) -> String? {
        guard var parent = nodes[parentId] else { return nil }
        let newNode = ResearchTreeNode(
            kind: kind,
            atomUUID: atomUUID,
            parentNodeId: parentId,
            childNodeIds: [],
            branchOrder: parent.childNodeIds.count,
            meta: ResearchTreeNode.Meta(label: label, sourceTabId: sourceTabId, aiSuggested: aiSuggested, accepted: accepted)
        )
        parent.childNodeIds.append(newNode.id)
        nodes[parentId] = parent
        nodes[newNode.id] = newNode
        return newNode.id
    }
}

/// A source tab within an Inquiry Session's Source Pane.
struct SourceTab: Codable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case web
        case pdf
        case youTube = "youtube"
        case internalAtom = "internal"
        case swipe
    }

    var id: String                          // tabId
    var kind: Kind
    var sourceUUID: String?                 // Atom UUID (research/note/swipe)
    var url: String?                        // For web/PDF
    var title: String
    var attachedQuestionUUID: String?       // Branch awareness
    var attachedNodeId: String?             // Research tree node it's attached to
    var scrollPosition: Double
    var lastReadAt: String                  // ISO8601
    var pinned: Bool
    var highlightCount: Int

    init(
        id: String = UUID().uuidString,
        kind: Kind,
        sourceUUID: String? = nil,
        url: String? = nil,
        title: String,
        attachedQuestionUUID: String? = nil,
        attachedNodeId: String? = nil,
        scrollPosition: Double = 0,
        lastReadAt: String = ISO8601DateFormatter().string(from: Date()),
        pinned: Bool = false,
        highlightCount: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.sourceUUID = sourceUUID
        self.url = url
        self.title = title
        self.attachedQuestionUUID = attachedQuestionUUID
        self.attachedNodeId = attachedNodeId
        self.scrollPosition = scrollPosition
        self.lastReadAt = lastReadAt
        self.pinned = pinned
        self.highlightCount = highlightCount
    }
}

/// A temporary capture during an active session — promoted to Extract/Note on commit.
struct SessionCapture: Codable, Sendable, Identifiable {
    enum Source: String, Codable, Sendable {
        case voice
        case telegram
        case type
        case selection
    }
    enum Status: String, Codable, Sendable {
        case pending
        case committed
        case discarded
    }

    var id: String                          // captureId
    var body: String
    var createdAt: String
    var source: Source
    var suggestedKind: ExtractKind?
    var attachedQuestionId: String?
    var attachedSourceTabId: String?
    var status: Status
    var promotedToAtomUUID: String?

    init(
        id: String = UUID().uuidString,
        body: String,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        source: Source = .type,
        suggestedKind: ExtractKind? = nil,
        attachedQuestionId: String? = nil,
        attachedSourceTabId: String? = nil,
        status: Status = .pending,
        promotedToAtomUUID: String? = nil
    ) {
        self.id = id
        self.body = body
        self.createdAt = createdAt
        self.source = source
        self.suggestedKind = suggestedKind
        self.attachedQuestionId = attachedQuestionId
        self.attachedSourceTabId = attachedSourceTabId
        self.status = status
        self.promotedToAtomUUID = promotedToAtomUUID
    }
}

/// One AI conversation exchange anchored to a session/branch.
struct AIInteractionRef: Codable, Sendable, Identifiable {
    var id: String
    var branchNodeId: String?
    var sourceTabId: String?
    var prompt: String
    var response: String
    var createdAt: String
    var modelTier: String?

    init(
        id: String = UUID().uuidString,
        branchNodeId: String? = nil,
        sourceTabId: String? = nil,
        prompt: String,
        response: String,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        modelTier: String? = nil
    ) {
        self.id = id
        self.branchNodeId = branchNodeId
        self.sourceTabId = sourceTabId
        self.prompt = prompt
        self.response = response
        self.createdAt = createdAt
        self.modelTier = modelTier
    }
}

/// Live emerging structure surface (background cartographer output).
struct MapFormingState: Codable, Sendable {
    struct ConceptCandidate: Codable, Sendable, Identifiable {
        var id: String
        var label: String
        var mentionCount: Int
        var existingLexiconUUID: String?
        var firstSeenAt: String
        init(id: String = UUID().uuidString, label: String, mentionCount: Int = 1, existingLexiconUUID: String? = nil, firstSeenAt: String = ISO8601DateFormatter().string(from: Date())) {
            self.id = id; self.label = label; self.mentionCount = mentionCount; self.existingLexiconUUID = existingLexiconUUID; self.firstSeenAt = firstSeenAt
        }
    }
    struct OpenLoop: Codable, Sendable, Identifiable {
        var id: String
        var description: String
        var sourceQuestionUUID: String?
        var detectedAt: String
        init(id: String = UUID().uuidString, description: String, sourceQuestionUUID: String? = nil, detectedAt: String = ISO8601DateFormatter().string(from: Date())) {
            self.id = id; self.description = description; self.sourceQuestionUUID = sourceQuestionUUID; self.detectedAt = detectedAt
        }
    }
    struct ContradictionAlert: Codable, Sendable, Identifiable {
        var id: String
        var description: String
        var leftExtractUUID: String?
        var rightExtractUUID: String?
        var detectedAt: String
        init(id: String = UUID().uuidString, description: String, leftExtractUUID: String? = nil, rightExtractUUID: String? = nil, detectedAt: String = ISO8601DateFormatter().string(from: Date())) {
            self.id = id; self.description = description; self.leftExtractUUID = leftExtractUUID; self.rightExtractUUID = rightExtractUUID; self.detectedAt = detectedAt
        }
    }
    struct BranchSuggestion: Codable, Sendable, Identifiable {
        var id: String
        var proposedQuestion: String
        var rationale: String?
        var fromNodeId: String?
        var detectedAt: String
        init(id: String = UUID().uuidString, proposedQuestion: String, rationale: String? = nil, fromNodeId: String? = nil, detectedAt: String = ISO8601DateFormatter().string(from: Date())) {
            self.id = id; self.proposedQuestion = proposedQuestion; self.rationale = rationale; self.fromNodeId = fromNodeId; self.detectedAt = detectedAt
        }
    }

    var concepts: [ConceptCandidate]
    var openLoops: [OpenLoop]
    var contradictions: [ContradictionAlert]
    var branchSuggestions: [BranchSuggestion]
    var possibleConnectionUUIDs: [String]
    var lastUpdated: String

    init(
        concepts: [ConceptCandidate] = [],
        openLoops: [OpenLoop] = [],
        contradictions: [ContradictionAlert] = [],
        branchSuggestions: [BranchSuggestion] = [],
        possibleConnectionUUIDs: [String] = [],
        lastUpdated: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.concepts = concepts
        self.openLoops = openLoops
        self.contradictions = contradictions
        self.branchSuggestions = branchSuggestions
        self.possibleConnectionUUIDs = possibleConnectionUUIDs
        self.lastUpdated = lastUpdated
    }
}

/// Crystallization output (Phase 5). Persisted in InquirySession.structured.crystallizationResult.
struct CrystallizationOutput: Codable, Sendable {
    struct LexiconCandidate: Codable, Sendable, Identifiable {
        var id: String
        var term: String
        var definition: String
        var mentionCount: Int
        var sourceUUIDs: [String]
        var accepted: Bool
        init(id: String = UUID().uuidString, term: String, definition: String, mentionCount: Int = 0, sourceUUIDs: [String] = [], accepted: Bool = false) {
            self.id = id; self.term = term; self.definition = definition; self.mentionCount = mentionCount; self.sourceUUIDs = sourceUUIDs; self.accepted = accepted
        }
    }
    struct QuestionCandidate: Codable, Sendable, Identifiable {
        var id: String
        var text: String
        var rationale: String?
        var parentBranchNodeId: String?
        var accepted: Bool
        init(id: String = UUID().uuidString, text: String, rationale: String? = nil, parentBranchNodeId: String? = nil, accepted: Bool = false) {
            self.id = id; self.text = text; self.rationale = rationale; self.parentBranchNodeId = parentBranchNodeId; self.accepted = accepted
        }
    }
    struct ConnectionCandidate: Codable, Sendable, Identifiable {
        var id: String
        var name: String
        var rationale: String?
        var clusterExtractUUIDs: [String]
        var seededLexiconCandidateIds: [String]
        var accepted: Bool
        init(id: String = UUID().uuidString, name: String, rationale: String? = nil, clusterExtractUUIDs: [String] = [], seededLexiconCandidateIds: [String] = [], accepted: Bool = false) {
            self.id = id; self.name = name; self.rationale = rationale; self.clusterExtractUUIDs = clusterExtractUUIDs; self.seededLexiconCandidateIds = seededLexiconCandidateIds; self.accepted = accepted
        }
    }
    struct ModelUpdateProposal: Codable, Sendable, Identifiable {
        var id: String
        var kind: ModelUpdate.Kind
        var before: String
        var after: String
        var rationale: String?
        var evidence: [ExtractRef]
        var accepted: Bool
        init(id: String = UUID().uuidString, kind: ModelUpdate.Kind, before: String, after: String, rationale: String? = nil, evidence: [ExtractRef] = [], accepted: Bool = false) {
            self.id = id; self.kind = kind; self.before = before; self.after = after; self.rationale = rationale; self.evidence = evidence; self.accepted = accepted
        }
    }
    struct ContradictionAlert: Codable, Sendable, Identifiable {
        var id: String
        var description: String
        var leftExtractUUID: String?
        var rightExtractUUID: String?
        init(id: String = UUID().uuidString, description: String, leftExtractUUID: String? = nil, rightExtractUUID: String? = nil) {
            self.id = id; self.description = description; self.leftExtractUUID = leftExtractUUID; self.rightExtractUUID = rightExtractUUID
        }
    }
    struct OpenLoop: Codable, Sendable, Identifiable {
        var id: String
        var description: String
        var suggestedNextStep: String?
        init(id: String = UUID().uuidString, description: String, suggestedNextStep: String? = nil) {
            self.id = id; self.description = description; self.suggestedNextStep = suggestedNextStep
        }
    }
    struct OutputCandidate: Codable, Sendable, Identifiable {
        var id: String
        var title: String
        var format: String
        var rationale: String?
        var sourceExtractUUIDs: [String]
        var accepted: Bool
        var promotedIdeaUUID: String?
        init(id: String = UUID().uuidString, title: String, format: String, rationale: String? = nil, sourceExtractUUIDs: [String] = [], accepted: Bool = false, promotedIdeaUUID: String? = nil) {
            self.id = id; self.title = title; self.format = format; self.rationale = rationale; self.sourceExtractUUIDs = sourceExtractUUIDs; self.accepted = accepted; self.promotedIdeaUUID = promotedIdeaUUID
        }
    }
    struct ThinkspaceMapProposal: Codable, Sendable, Identifiable {
        enum Kind: String, Codable, Sendable {
            case addPortal
            case addObject
            case createCluster
            case linkConcepts
            case placeNearConcept
            case updateCluster
            case connectDeepDives
            case createRelationship
        }
        var id: String
        var thinkspaceUUID: String
        var thinkspaceName: String?
        var kind: Kind
        var rationale: String
        var clusterName: String?
        var clusterMemberAtomUUIDs: [String]
        var sourceAtomUUID: String?
        var targetAtomUUID: String?
        var relationshipType: String?
        var suggestedX: Double?
        var suggestedY: Double?
        var confidence: Double
        var accepted: Bool
        init(
            id: String = UUID().uuidString,
            thinkspaceUUID: String,
            thinkspaceName: String? = nil,
            kind: Kind,
            rationale: String,
            clusterName: String? = nil,
            clusterMemberAtomUUIDs: [String] = [],
            sourceAtomUUID: String? = nil,
            targetAtomUUID: String? = nil,
            relationshipType: String? = nil,
            suggestedX: Double? = nil,
            suggestedY: Double? = nil,
            confidence: Double = 0.5,
            accepted: Bool = false
        ) {
            self.id = id
            self.thinkspaceUUID = thinkspaceUUID
            self.thinkspaceName = thinkspaceName
            self.kind = kind
            self.rationale = rationale
            self.clusterName = clusterName
            self.clusterMemberAtomUUIDs = clusterMemberAtomUUIDs
            self.sourceAtomUUID = sourceAtomUUID
            self.targetAtomUUID = targetAtomUUID
            self.relationshipType = relationshipType
            self.suggestedX = suggestedX
            self.suggestedY = suggestedY
            self.confidence = confidence
            self.accepted = accepted
        }
    }
    struct PromotionSuggestion: Codable, Sendable, Identifiable {
        enum Kind: String, Codable, Sendable {
            case lexiconToConnection
            case lexiconToDeepDive
            case branchToDeepDive
            case extractToPractice
        }
        var id: String
        var kind: Kind
        var sourceAtomUUID: String?
        var rationale: String?
        var accepted: Bool
        init(id: String = UUID().uuidString, kind: Kind, sourceAtomUUID: String? = nil, rationale: String? = nil, accepted: Bool = false) {
            self.id = id; self.kind = kind; self.sourceAtomUUID = sourceAtomUUID; self.rationale = rationale; self.accepted = accepted
        }
    }
    struct RejectedItem: Codable, Sendable, Identifiable {
        var id: String
        var section: String
        var snapshot: String
        var reason: String?
        init(id: String = UUID().uuidString, section: String, snapshot: String, reason: String? = nil) {
            self.id = id; self.section = section; self.snapshot = snapshot; self.reason = reason
        }
    }

    var summary: String
    var lexiconCandidates: [LexiconCandidate]
    var newQuestions: [QuestionCandidate]
    var possibleConnections: [ConnectionCandidate]
    var modelUpdates: [ModelUpdateProposal]
    var contradictions: [ContradictionAlert]
    var openLoops: [OpenLoop]
    var outputCandidates: [OutputCandidate]
    var thinkspaceMapProposals: [ThinkspaceMapProposal]
    var promotionSuggestions: [PromotionSuggestion]
    var rejected: [RejectedItem]
    var generatedAt: String

    init(
        summary: String = "",
        lexiconCandidates: [LexiconCandidate] = [],
        newQuestions: [QuestionCandidate] = [],
        possibleConnections: [ConnectionCandidate] = [],
        modelUpdates: [ModelUpdateProposal] = [],
        contradictions: [ContradictionAlert] = [],
        openLoops: [OpenLoop] = [],
        outputCandidates: [OutputCandidate] = [],
        thinkspaceMapProposals: [ThinkspaceMapProposal] = [],
        promotionSuggestions: [PromotionSuggestion] = [],
        rejected: [RejectedItem] = [],
        generatedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.summary = summary
        self.lexiconCandidates = lexiconCandidates
        self.newQuestions = newQuestions
        self.possibleConnections = possibleConnections
        self.modelUpdates = modelUpdates
        self.contradictions = contradictions
        self.openLoops = openLoops
        self.outputCandidates = outputCandidates
        self.thinkspaceMapProposals = thinkspaceMapProposals
        self.promotionSuggestions = promotionSuggestions
        self.rejected = rejected
        self.generatedAt = generatedAt
    }
}

/// Structured field for `.inquirySession` atoms.
struct InquirySessionStructured: Codable, Sendable {
    var researchTree: ResearchTreeDocument
    var sourceTabs: [SourceTab]
    var sessionCaptures: [SessionCapture]
    var aiInteractions: [AIInteractionRef]
    var mapForming: MapFormingState
    var crystallizationResult: CrystallizationOutput?

    init(
        researchTree: ResearchTreeDocument,
        sourceTabs: [SourceTab] = [],
        sessionCaptures: [SessionCapture] = [],
        aiInteractions: [AIInteractionRef] = [],
        mapForming: MapFormingState = MapFormingState(),
        crystallizationResult: CrystallizationOutput? = nil
    ) {
        self.researchTree = researchTree
        self.sourceTabs = sourceTabs
        self.sessionCaptures = sessionCaptures
        self.aiInteractions = aiInteractions
        self.mapForming = mapForming
        self.crystallizationResult = crystallizationResult
    }
}

// MARK: - Question

/// One historical answer version in a Question's evolution log.
struct AnswerVersion: Codable, Sendable, Identifiable {
    var id: String
    var date: String                 // ISO8601
    var text: String
    var confidence: QuestionConfidence?
    init(id: String = UUID().uuidString, date: String, text: String, confidence: QuestionConfidence? = nil) {
        self.id = id; self.date = date; self.text = text; self.confidence = confidence
    }
}

/// Lightweight reference to a source (atom) used in answering a question.
struct SourceRef: Codable, Sendable, Identifiable {
    var id: String { sourceUUID }
    var sourceUUID: String
    var note: String?
    init(sourceUUID: String, note: String? = nil) {
        self.sourceUUID = sourceUUID; self.note = note
    }
}

/// Metadata for `.question` atoms.
struct QuestionMetadata: Codable, Sendable {
    var parentDeepDiveUUID: String?
    var parentQuestionUUID: String?     // For branches
    var originSessionUUID: String?      // Where it was born
    var originExtractUUID: String?      // If deepened from a highlight
    var status: QuestionStatus
    var priority: Int?
    var confidence: QuestionConfidence?

    init(
        parentDeepDiveUUID: String? = nil,
        parentQuestionUUID: String? = nil,
        originSessionUUID: String? = nil,
        originExtractUUID: String? = nil,
        status: QuestionStatus = .open,
        priority: Int? = nil,
        confidence: QuestionConfidence? = nil
    ) {
        self.parentDeepDiveUUID = parentDeepDiveUUID
        self.parentQuestionUUID = parentQuestionUUID
        self.originSessionUUID = originSessionUUID
        self.originExtractUUID = originExtractUUID
        self.status = status
        self.priority = priority
        self.confidence = confidence
    }
}

/// Structured field for `.question` atoms.
struct QuestionStructured: Codable, Sendable {
    var relatedConceptUUIDs: [String]
    var createdOutputUUIDs: [String]
    var sources: [SourceRef]
    var answerVersionHistory: [AnswerVersion]

    init(
        relatedConceptUUIDs: [String] = [],
        createdOutputUUIDs: [String] = [],
        sources: [SourceRef] = [],
        answerVersionHistory: [AnswerVersion] = []
    ) {
        self.relatedConceptUUIDs = relatedConceptUUIDs
        self.createdOutputUUIDs = createdOutputUUIDs
        self.sources = sources
        self.answerVersionHistory = answerVersionHistory
    }
}

// MARK: - Extract

/// Anchored selection range inside a source.
struct ExtractTextRange: Codable, Sendable, Equatable {
    var start: Int
    var end: Int
    /// Optional context fields for resilient re-anchoring after source changes
    var prefix: String?
    var suffix: String?
    init(start: Int, end: Int, prefix: String? = nil, suffix: String? = nil) {
        self.start = start; self.end = end; self.prefix = prefix; self.suffix = suffix
    }
}

/// Metadata for `.extract` atoms.
struct ExtractMetadata: Codable, Sendable {
    var kind: ExtractKind
    var sourceUUID: String?
    var selectionRange: ExtractTextRange?
    var parentSessionUUID: String?
    var parentQuestionUUID: String?
    var parentDeepDiveUUID: String?
    var parentBranchNodeId: String?
    var sourceTabId: String?
    var userNote: String?
    var suggestedDestinationUUID: String?
    var status: ExtractStatus
    var committedAt: String?
    var promotedToUUID: String?
    var originType: String?              // "highlight" | "deepen" | "ai" | "telegram" | "voice" | "manual"
    var citation: String?                // Display chip e.g. "Buteyko Paper · 2007 · Author"

    init(
        kind: ExtractKind,
        sourceUUID: String? = nil,
        selectionRange: ExtractTextRange? = nil,
        parentSessionUUID: String? = nil,
        parentQuestionUUID: String? = nil,
        parentDeepDiveUUID: String? = nil,
        parentBranchNodeId: String? = nil,
        sourceTabId: String? = nil,
        userNote: String? = nil,
        suggestedDestinationUUID: String? = nil,
        status: ExtractStatus = .committed,
        committedAt: String? = ISO8601DateFormatter().string(from: Date()),
        promotedToUUID: String? = nil,
        originType: String? = nil,
        citation: String? = nil
    ) {
        self.kind = kind
        self.sourceUUID = sourceUUID
        self.selectionRange = selectionRange
        self.parentSessionUUID = parentSessionUUID
        self.parentQuestionUUID = parentQuestionUUID
        self.parentDeepDiveUUID = parentDeepDiveUUID
        self.parentBranchNodeId = parentBranchNodeId
        self.sourceTabId = sourceTabId
        self.userNote = userNote
        self.suggestedDestinationUUID = suggestedDestinationUUID
        self.status = status
        self.committedAt = committedAt
        self.promotedToUUID = promotedToUUID
        self.originType = originType
        self.citation = citation
    }
}

/// Structured field for `.extract` atoms.
struct ExtractStructured: Codable, Sendable {
    var aiTags: [String]
    var relatedExtractUUIDs: [String]
    init(aiTags: [String] = [], relatedExtractUUIDs: [String] = []) {
        self.aiTags = aiTags; self.relatedExtractUUIDs = relatedExtractUUIDs
    }
}

// MARK: - Lexicon Entry

/// Metadata for `.lexiconEntry` atoms.
struct LexiconMetadata: Codable, Sendable {
    var parentDeepDiveUUID: String
    var aliases: [String]
    var maturity: LexiconMaturity
    var mentionCount: Int
    var firstSeenAt: String              // ISO8601
    var lastSeenAt: String
    var promotedToUUID: String?

    init(
        parentDeepDiveUUID: String,
        aliases: [String] = [],
        maturity: LexiconMaturity = .mention,
        mentionCount: Int = 1,
        firstSeenAt: String = ISO8601DateFormatter().string(from: Date()),
        lastSeenAt: String = ISO8601DateFormatter().string(from: Date()),
        promotedToUUID: String? = nil
    ) {
        self.parentDeepDiveUUID = parentDeepDiveUUID
        self.aliases = aliases
        self.maturity = maturity
        self.mentionCount = mentionCount
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.promotedToUUID = promotedToUUID
    }
}

/// Structured field for `.lexiconEntry` atoms.
struct LexiconStructured: Codable, Sendable {
    var relatedQuestionUUIDs: [String]
    var relatedSourceUUIDs: [String]
    var relatedExtractUUIDs: [String]
    var contradictionUUIDs: [String]

    init(
        relatedQuestionUUIDs: [String] = [],
        relatedSourceUUIDs: [String] = [],
        relatedExtractUUIDs: [String] = [],
        contradictionUUIDs: [String] = []
    ) {
        self.relatedQuestionUUIDs = relatedQuestionUUIDs
        self.relatedSourceUUIDs = relatedSourceUUIDs
        self.relatedExtractUUIDs = relatedExtractUUIDs
        self.contradictionUUIDs = contradictionUUIDs
    }
}

// MARK: - Atom convenience accessors

extension Atom {
    var deepDiveMetadata: DeepDiveMetadata? { metadataValue(as: DeepDiveMetadata.self) }
    var deepDiveStructured: DeepDiveStructured? { structuredData(as: DeepDiveStructured.self) }

    var inquirySessionMetadata: InquirySessionMetadata? { metadataValue(as: InquirySessionMetadata.self) }
    var inquirySessionStructured: InquirySessionStructured? { structuredData(as: InquirySessionStructured.self) }

    var questionMetadata: QuestionMetadata? { metadataValue(as: QuestionMetadata.self) }
    var questionStructured: QuestionStructured? { structuredData(as: QuestionStructured.self) }

    var extractMetadata: ExtractMetadata? { metadataValue(as: ExtractMetadata.self) }
    var extractStructured: ExtractStructured? { structuredData(as: ExtractStructured.self) }

    var lexiconMetadata: LexiconMetadata? { metadataValue(as: LexiconMetadata.self) }
    var lexiconStructured: LexiconStructured? { structuredData(as: LexiconStructured.self) }
}

// MARK: - Telegram alias matching helpers

extension DeepDiveMetadata {
    /// Returns true if `term` (case-insensitive) matches any alias or topic alias.
    func matchesAlias(_ term: String) -> Bool {
        let normalized = term.lowercased()
        if let aliases, aliases.contains(where: { $0.lowercased() == normalized }) { return true }
        if let topicAliases, topicAliases.contains(where: { $0.lowercased() == normalized }) { return true }
        return false
    }
}
