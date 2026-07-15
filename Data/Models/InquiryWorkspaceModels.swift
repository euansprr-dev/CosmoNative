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
/// Legacy: the new Inquiry shell uses `InquiryPhase` (Explore / Crystallize) and treats
/// `.read/.write/.map/.review` as historical. Persistence still uses this enum so existing
/// sessions decode cleanly.
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

/// Two-phase mode for the redesigned Inquiry Workspace.
/// - `.explore` covers research / reading / map (contextual).
/// - `.crystallize` opens the review + write outputs as a modal sheet.
enum InquiryPhase: String, Codable, CaseIterable, Sendable {
    case explore
    case crystallize

    var displayName: String {
        switch self {
        case .explore: return "Explore"
        case .crystallize: return "Crystallize"
        }
    }

    /// Derive a phase from the legacy layout mode (so existing sessions resume correctly).
    init(layoutMode: InquiryLayoutMode) {
        switch layoutMode {
        case .review:
            self = .crystallize
        default:
            self = .explore
        }
    }

    /// Persisted layout mode for this phase.
    var persistedLayoutMode: InquiryLayoutMode {
        switch self {
        case .explore: return .research
        case .crystallize: return .review
        }
    }
}

/// A short, debounce-regenerated synthesis of "what we currently understand" about the
/// active question. Persists inside `InquirySessionStructured.currentUnderstandingDraft`.
struct LiveUnderstandingDraft: Codable, Sendable, Equatable {
    var text: String
    var generatedAt: String        // ISO8601
    var contextSignature: String   // stable hash of (activeQuestionUUID + claim/evidence/source counts)
    var modelTier: String?

    init(text: String, generatedAt: String = ISO8601.string(from: Date()), contextSignature: String, modelTier: String? = nil) {
        self.text = text
        self.generatedAt = generatedAt
        self.contextSignature = contextSignature
        self.modelTier = modelTier
    }
}

/// Transient AI reply card that floats above the dock. Never persisted.
struct EphemeralAIReplyCard: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case reply
        case summary
        case challenge
        case routing
    }

    var id: String
    var kind: Kind
    var text: String
    var createdAt: Date

    init(id: String = UUID().uuidString, kind: Kind, text: String, createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
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
enum ExtractKind: String, Codable, CaseIterable, Sendable, Hashable {
    case quote
    case highlight
    case claim
    case speculativeClaim
    case evidence
    case counterevidence
    case mechanism
    case assumption
    case sourceQualityNote
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
    case goal
    case problem
    case benefit

    var displayName: String {
        switch self {
        case .quote: return "Quote"
        case .highlight: return "Highlight"
        case .claim: return "Claim"
        case .speculativeClaim: return "Speculative Claim"
        case .evidence: return "Evidence"
        case .counterevidence: return "Counterevidence"
        case .mechanism: return "Mechanism"
        case .assumption: return "Assumption"
        case .sourceQualityNote: return "Source Quality Note"
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
        case .goal: return "Goal"
        case .problem: return "Problem"
        case .benefit: return "Benefit"
        }
    }

    var iconName: String {
        switch self {
        case .quote: return "quote.opening"
        case .highlight: return "highlighter"
        case .claim: return "exclamationmark.bubble"
        case .speculativeClaim: return "exclamationmark.bubble"
        case .evidence: return "checkmark.seal"
        case .counterevidence: return "exclamationmark.triangle"
        case .mechanism: return "gearshape.2"
        case .assumption: return "building.columns"
        case .sourceQualityNote: return "shield.lefthalf.filled"
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
        case .goal: return "target"
        case .problem: return "exclamationmark.octagon"
        case .benefit: return "gift"
        }
    }

    var isClaimLike: Bool {
        self == .claim || self == .speculativeClaim
    }

    var isEvidenceLike: Bool {
        self == .evidence || self == .counterevidence
    }

    var isEpistemic: Bool {
        switch self {
        case .claim, .speculativeClaim, .evidence, .counterevidence, .mechanism, .assumption, .sourceQualityNote:
            return true
        default:
            return false
        }
    }

    /// Kinds offered in user-facing "change kind" correction menus, in display order.
    static let correctionOptions: [ExtractKind] = [
        .goal, .problem, .claim, .speculativeClaim, .evidence, .counterevidence,
        .mechanism, .example, .benefit, .question, .term, .practice, .reference, .note
    ]
}

/// Lifecycle for an Extract.
enum ExtractStatus: String, Codable, CaseIterable, Sendable {
    case temporary
    case committed
    case ignored
    case promoted
}

enum InquiryNodeType: String, Codable, CaseIterable, Sendable {
    case topic
    case rootQuestion
    case branchQuestion
    case claim
    case evidenceQualityInvestigation
    case sourceSearchTask
    case evidence
    case counterevidence
    case lexiconTerm
    case deepDiveCandidate

    var displayName: String {
        switch self {
        case .topic: return "Topic"
        case .rootQuestion: return "Root Question"
        case .branchQuestion: return "Branch Question"
        case .claim: return "Claim"
        case .evidenceQualityInvestigation: return "Evidence Audit"
        case .sourceSearchTask: return "Source Search"
        case .evidence: return "Evidence"
        case .counterevidence: return "Counterevidence"
        case .lexiconTerm: return "Term"
        case .deepDiveCandidate: return "Deep Dive Candidate"
        }
    }
}

enum InquiryRelationshipType: String, Codable, CaseIterable, Sendable {
    case childOf = "child_of"
    case siblingOf = "sibling_of"
    case rootUnderTopic = "root_under_topic"
    case evidenceAuditForClaim = "evidence_audit_for_claim"
    case sourceSearchForQuestion = "source_search_for_question"
    case sourceSearchForClaim = "source_search_for_claim"
    case consequenceOf = "consequence_of"
    case prerequisiteFor = "prerequisite_for"
    case mechanismFor = "mechanism_for"
    case definitionOfTerm = "definition_of_term"
    case crossLinkedTo = "cross_linked_to"
    case promotedToDeepDive = "promoted_to_deep_dive"
    case relatedTo = "related_to"

    var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ")
    }
}

enum InquiryOperationalTaskType: String, Codable, CaseIterable, Sendable {
    case evidenceAudit
    case sourceSearch
}

enum InquiryPlacementConfidence: String, Codable, CaseIterable, Sendable {
    case high
    case medium
    case low

    var displayName: String { rawValue.capitalized }
}

enum InquiryTreeNodeVisibility: String, Codable, CaseIterable, Sendable {
    case solidNode
    case satellite
    case inspectorOnly
    case hidden
}

struct InquiryPlacementDecision: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var nodeType: InquiryNodeType
    var parentQuestionUUID: String?
    var parentBranchNodeId: String?
    var relationshipType: InquiryRelationshipType
    var confidence: InquiryPlacementConfidence
    var explanation: String
    var requiresApproval: Bool
    var appearsInBranchMap: Bool

    init(
        id: String = UUID().uuidString,
        nodeType: InquiryNodeType,
        parentQuestionUUID: String? = nil,
        parentBranchNodeId: String? = nil,
        relationshipType: InquiryRelationshipType,
        confidence: InquiryPlacementConfidence,
        explanation: String,
        requiresApproval: Bool = true,
        appearsInBranchMap: Bool
    ) {
        self.id = id
        self.nodeType = nodeType
        self.parentQuestionUUID = parentQuestionUUID
        self.parentBranchNodeId = parentBranchNodeId
        self.relationshipType = relationshipType
        self.confidence = confidence
        self.explanation = explanation
        self.requiresApproval = requiresApproval
        self.appearsInBranchMap = appearsInBranchMap
    }
}

struct InquiryOperationalTask: Codable, Sendable, Identifiable, Hashable {
    enum Status: String, Codable, Sendable {
        case open
        case inProgress
        case completed
        case archived
    }

    var id: String
    var type: InquiryOperationalTaskType
    var title: String
    var detail: String?
    var attachedQuestionUUID: String?
    var attachedClaimExtractUUID: String?
    var sourceUUID: String?
    var sourceTabId: String?
    var relationshipType: InquiryRelationshipType
    var originExtractUUID: String?
    var createdAt: String
    var status: Status

    init(
        id: String = UUID().uuidString,
        type: InquiryOperationalTaskType,
        title: String,
        detail: String? = nil,
        attachedQuestionUUID: String? = nil,
        attachedClaimExtractUUID: String? = nil,
        sourceUUID: String? = nil,
        sourceTabId: String? = nil,
        relationshipType: InquiryRelationshipType,
        originExtractUUID: String? = nil,
        createdAt: String = ISO8601.string(from: Date()),
        status: Status = .open
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.detail = detail
        self.attachedQuestionUUID = attachedQuestionUUID
        self.attachedClaimExtractUUID = attachedClaimExtractUUID
        self.sourceUUID = sourceUUID
        self.sourceTabId = sourceTabId
        self.relationshipType = relationshipType
        self.originExtractUUID = originExtractUUID
        self.createdAt = createdAt
        self.status = status
    }
}

enum InquirySourceProvider: String, Codable, CaseIterable, Sendable, Hashable {
    case local
    case openAlex
    case crossref
    case semanticScholar
    case pubMed
    case arxiv
    case youtube
    case podcast
    case web
    case googleBooks
    case openLibrary
    case internetArchive

    var displayName: String {
        switch self {
        case .local: return "Local"
        case .openAlex: return "OpenAlex"
        case .crossref: return "Crossref"
        case .semanticScholar: return "Semantic Scholar"
        case .pubMed: return "PubMed"
        case .arxiv: return "arXiv"
        case .youtube: return "YouTube"
        case .podcast: return "Podcasts"
        case .web: return "Web"
        case .googleBooks: return "Google Books"
        case .openLibrary: return "Open Library"
        case .internetArchive: return "Internet Archive"
        }
    }
}

enum InquirySourceKind: String, Codable, CaseIterable, Sendable, Hashable {
    case paper
    case review
    case metaAnalysis
    case video
    case web
    case book
    case localResearch
    case localNote
    case unknown

    var displayName: String {
        switch self {
        case .paper: return "Paper"
        case .review: return "Review"
        case .metaAnalysis: return "Meta-analysis"
        case .video: return "Video"
        case .web: return "Web"
        case .book: return "Book"
        case .localResearch: return "Your library"
        case .localNote: return "Local note"
        case .unknown: return "Source"
        }
    }

    var iconName: String {
        switch self {
        case .paper, .review, .metaAnalysis: return "doc.text"
        case .video: return "play.rectangle"
        case .web: return "globe"
        case .book: return "book.closed"
        case .localResearch, .localNote: return "archivebox"
        case .unknown: return "link"
        }
    }
}

enum InquiryEvidenceRole: String, Codable, CaseIterable, Sendable, Hashable {
    case foundational
    case recent
    case review
    case metaAnalysis
    case mechanism
    case counterevidence
    case practicalGuide
    case videoExplainer
    case localLibrary
    case webContext
    case primaryText
    case book
    case lecture
    case philosophicalContext
    case traditionGuide

    var displayName: String {
        switch self {
        case .foundational: return "Foundational"
        case .recent: return "Recent"
        case .review: return "Review"
        case .metaAnalysis: return "Meta"
        case .mechanism: return "Mechanism"
        case .counterevidence: return "Counter"
        case .practicalGuide: return "Practice"
        case .videoExplainer: return "Video"
        case .localLibrary: return "Library"
        case .webContext: return "Context"
        case .primaryText: return "Primary"
        case .book: return "Book"
        case .lecture: return "Lecture"
        case .philosophicalContext: return "Philosophy"
        case .traditionGuide: return "Tradition"
        }
    }
}

enum InquiryResearchIntent: String, Codable, CaseIterable, Sendable, Hashable {
    case conceptExploration
    case philosophicalOrientation
    case practiceTechnique
    case historicalLineage
    case clinicalEvidence
    case mechanismScience
    case sourceSurvey

    var displayName: String {
        switch self {
        case .conceptExploration: return "Concept"
        case .philosophicalOrientation: return "Philosophy"
        case .practiceTechnique: return "Practice"
        case .historicalLineage: return "Lineage"
        case .clinicalEvidence: return "Evidence"
        case .mechanismScience: return "Mechanism"
        case .sourceSurvey: return "Survey"
        }
    }
}

enum InquirySourceLane: String, Codable, CaseIterable, Sendable, Hashable {
    case localLibrary
    case primaryText
    case deepRead
    case teacherLecture
    case practiceGuide
    case scholarlyContext
    case clinicalEvidence
    case webResource

    var displayName: String {
        switch self {
        case .localLibrary: return "Your library"
        case .primaryText: return "Primary text"
        case .deepRead: return "Deep read"
        case .teacherLecture: return "Lecture"
        case .practiceGuide: return "Practice"
        case .scholarlyContext: return "Scholarship"
        case .clinicalEvidence: return "Clinical"
        case .webResource: return "Resource"
        }
    }

    var iconName: String {
        switch self {
        case .localLibrary: return "archivebox"
        case .primaryText: return "scroll"
        case .deepRead: return "book.closed"
        case .teacherLecture: return "play.rectangle"
        case .practiceGuide: return "figure.mind.and.body"
        case .scholarlyContext: return "graduationcap"
        case .clinicalEvidence: return "cross.case"
        case .webResource: return "globe"
        }
    }
}

enum InquirySourceImportStatus: String, Codable, CaseIterable, Sendable, Hashable {
    case candidate
    case queued
    case imported
    case dismissed
}

enum InquirySourceSearchMode: String, Codable, CaseIterable, Sendable, Hashable {
    case quick
    case deepScout

    var displayName: String {
        switch self {
        case .quick: return "Quick"
        case .deepScout: return "Deep Scout"
        }
    }

    var iconName: String {
        switch self {
        case .quick: return "scope"
        case .deepScout: return "sparkle.magnifyingglass"
        }
    }
}

struct InquiryProviderStatus: Codable, Sendable, Identifiable, Hashable {
    enum State: String, Codable, Sendable, Hashable {
        case idle
        case loading
        case succeeded
        case failed
        case missingKey
        case rateLimited
    }

    var id: String { provider.rawValue }
    var provider: InquirySourceProvider
    var state: State
    var message: String?
    var count: Int

    init(
        provider: InquirySourceProvider,
        state: State = .idle,
        message: String? = nil,
        count: Int = 0
    ) {
        self.provider = provider
        self.state = state
        self.message = message
        self.count = count
    }
}

struct InquirySourceCandidate: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var provider: InquirySourceProvider
    var sourceKind: InquirySourceKind
    var title: String
    var subtitle: String?
    var authors: [String]
    var publishedDate: String?
    var url: String?
    var doi: String?
    var abstract: String?
    var evidenceRole: InquiryEvidenceRole
    var reason: String
    var score: Double
    var qualitySignals: [String]
    var branchQuestionUUID: String?
    var branchNodeId: String?
    var importedSourceUUID: String?
    var importStatus: InquirySourceImportStatus
    var generatedAt: String
    var researchIntent: InquiryResearchIntent?
    var sourceLane: InquirySourceLane?

    init(
        id: String = UUID().uuidString,
        provider: InquirySourceProvider,
        sourceKind: InquirySourceKind,
        title: String,
        subtitle: String? = nil,
        authors: [String] = [],
        publishedDate: String? = nil,
        url: String? = nil,
        doi: String? = nil,
        abstract: String? = nil,
        evidenceRole: InquiryEvidenceRole,
        reason: String,
        score: Double = 0,
        qualitySignals: [String] = [],
        branchQuestionUUID: String? = nil,
        branchNodeId: String? = nil,
        importedSourceUUID: String? = nil,
        importStatus: InquirySourceImportStatus = .candidate,
        generatedAt: String = ISO8601.string(from: Date()),
        researchIntent: InquiryResearchIntent? = nil,
        sourceLane: InquirySourceLane? = nil
    ) {
        self.id = id
        self.provider = provider
        self.sourceKind = sourceKind
        self.title = title
        self.subtitle = subtitle
        self.authors = authors
        self.publishedDate = publishedDate
        self.url = url
        self.doi = doi
        self.abstract = abstract
        self.evidenceRole = evidenceRole
        self.reason = reason
        self.score = score
        self.qualitySignals = qualitySignals
        self.branchQuestionUUID = branchQuestionUUID
        self.branchNodeId = branchNodeId
        self.importedSourceUUID = importedSourceUUID
        self.importStatus = importStatus
        self.generatedAt = generatedAt
        self.researchIntent = researchIntent
        self.sourceLane = sourceLane
    }
}

struct InquiryRecommendationBatch: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var questionUUID: String?
    var branchNodeId: String
    var query: String
    var searchMode: InquirySourceSearchMode
    var generatedAt: String
    var providerStatuses: [InquiryProviderStatus]
    var scoutSteps: [String]
    var candidates: [InquirySourceCandidate]
    var queuedCandidateIds: [String]
    var dismissedCandidateIds: [String]
    var importedCandidateIds: [String]

    init(
        id: String = UUID().uuidString,
        questionUUID: String?,
        branchNodeId: String,
        query: String,
        searchMode: InquirySourceSearchMode = .quick,
        generatedAt: String = ISO8601.string(from: Date()),
        providerStatuses: [InquiryProviderStatus] = [],
        scoutSteps: [String] = [],
        candidates: [InquirySourceCandidate] = [],
        queuedCandidateIds: [String] = [],
        dismissedCandidateIds: [String] = [],
        importedCandidateIds: [String] = []
    ) {
        self.id = id
        self.questionUUID = questionUUID
        self.branchNodeId = branchNodeId
        self.query = query
        self.searchMode = searchMode
        self.generatedAt = generatedAt
        self.providerStatuses = providerStatuses
        self.scoutSteps = scoutSteps
        self.candidates = candidates
        self.queuedCandidateIds = queuedCandidateIds
        self.dismissedCandidateIds = dismissedCandidateIds
        self.importedCandidateIds = importedCandidateIds
    }

    enum CodingKeys: String, CodingKey {
        case id
        case questionUUID
        case branchNodeId
        case query
        case searchMode
        case generatedAt
        case providerStatuses
        case scoutSteps
        case candidates
        case queuedCandidateIds
        case dismissedCandidateIds
        case importedCandidateIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        questionUUID = try container.decodeIfPresent(String.self, forKey: .questionUUID)
        branchNodeId = try container.decode(String.self, forKey: .branchNodeId)
        query = try container.decode(String.self, forKey: .query)
        searchMode = try container.decodeIfPresent(InquirySourceSearchMode.self, forKey: .searchMode) ?? .quick
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ISO8601.string(from: Date())
        providerStatuses = try container.decodeIfPresent([InquiryProviderStatus].self, forKey: .providerStatuses) ?? []
        scoutSteps = try container.decodeIfPresent([String].self, forKey: .scoutSteps) ?? []
        candidates = try container.decodeIfPresent([InquirySourceCandidate].self, forKey: .candidates) ?? []
        queuedCandidateIds = try container.decodeIfPresent([String].self, forKey: .queuedCandidateIds) ?? []
        dismissedCandidateIds = try container.decodeIfPresent([String].self, forKey: .dismissedCandidateIds) ?? []
        importedCandidateIds = try container.decodeIfPresent([String].self, forKey: .importedCandidateIds) ?? []
    }
}

struct InquiryRouteReceipt: Codable, Sendable, Identifiable, Hashable {
    enum Kind: String, Codable, Sendable, Hashable {
        case noteSaved
        case extractSaved
        case branchCreated
        case sourceOpened
        case sourceQueued
        case sourceImported
        case sourceRefreshed
        case aiAsked
    }

    var id: String
    var kind: Kind
    var message: String
    var detail: String?
    var questionUUID: String?
    var branchNodeId: String?
    var sourceUUID: String?
    var extractUUID: String?
    var candidateId: String?
    var createdAt: String

    init(
        id: String = UUID().uuidString,
        kind: Kind,
        message: String,
        detail: String? = nil,
        questionUUID: String? = nil,
        branchNodeId: String? = nil,
        sourceUUID: String? = nil,
        extractUUID: String? = nil,
        candidateId: String? = nil,
        createdAt: String = ISO8601.string(from: Date())
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.detail = detail
        self.questionUUID = questionUUID
        self.branchNodeId = branchNodeId
        self.sourceUUID = sourceUUID
        self.extractUUID = extractUUID
        self.candidateId = candidateId
        self.createdAt = createdAt
    }
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
        case .promotedToConnection: return "Concept"
        case .promotedToDeepDive: return "Deep Dive"
        }
    }
}

// MARK: - Deep Dive

/// Metadata for `.deepDive` atoms.
struct DeepDiveMetadata: Codable, Sendable {
    var aliases: [String]?                   // Telegram routing shortcuts (["bw", "breath"])
    var parentThinkspaceUUIDs: [String]?     // Primary first
    var primaryThinkspaceUUID: String?       // One-to-one Thinkspace profile home (migration-safe)
    var topicAliases: [String]?              // Alternate phrasings (semantic match)
    var maturity: DeepDiveMaturity?
    var lastInquiryAt: String?               // ISO8601
    var relatedDeepDiveUUIDs: [String]?
    var domainTagUUID: String?               // Optional clientProfile/domain affinity
    var coverGlyph: String?                  // SF symbol or symbolic identifier
    var bodyMigratedAt: String?              // ISO8601 — appended-blob → narrativeHistory migration marker

    init(
        aliases: [String]? = nil,
        parentThinkspaceUUIDs: [String]? = nil,
        primaryThinkspaceUUID: String? = nil,
        topicAliases: [String]? = nil,
        maturity: DeepDiveMaturity? = .spark,
        lastInquiryAt: String? = nil,
        relatedDeepDiveUUIDs: [String]? = nil,
        domainTagUUID: String? = nil,
        coverGlyph: String? = nil,
        bodyMigratedAt: String? = nil
    ) {
        self.aliases = aliases
        self.parentThinkspaceUUIDs = parentThinkspaceUUIDs
        self.primaryThinkspaceUUID = primaryThinkspaceUUID
        self.topicAliases = topicAliases
        self.maturity = maturity
        self.lastInquiryAt = lastInquiryAt
        self.relatedDeepDiveUUIDs = relatedDeepDiveUUIDs
        self.domainTagUUID = domainTagUUID
        self.coverGlyph = coverGlyph
        self.bodyMigratedAt = bodyMigratedAt
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

/// A full-narrative revision of the understanding, with session provenance.
/// Replaces the old raw-markdown "_Appended from Inquiry Session_" body appends.
struct UnderstandingNarrativeRevision: Codable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case crystallization
        case canvasOp
        case migration
        case manual
    }
    var id: String
    var date: String                  // ISO8601
    var text: String
    var sessionUUID: String?
    var originOperationId: String?    // canvas-op / crystallization id; idempotency key
    var kind: Kind?

    init(
        id: String = UUID().uuidString,
        date: String,
        text: String,
        sessionUUID: String? = nil,
        originOperationId: String? = nil,
        kind: Kind? = nil
    ) {
        self.id = id
        self.date = date
        self.text = text
        self.sessionUUID = sessionUUID
        self.originOperationId = originOperationId
        self.kind = kind
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
    var narrative: String?             // Latest multi-paragraph synthesis
    var narrativeHistory: [UnderstandingNarrativeRevision]?  // Newest last

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
        versionHistory: [ModelVersion] = [],
        narrative: String? = nil,
        narrativeHistory: [UnderstandingNarrativeRevision]? = nil
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
        self.narrative = narrative
        self.narrativeHistory = narrativeHistory
    }

    /// Records a narrative revision exactly once per origin operation.
    /// Returns false when a revision with the same originOperationId already exists.
    @discardableResult
    mutating func recordNarrativeRevision(_ revision: UnderstandingNarrativeRevision) -> Bool {
        if let originId = revision.originOperationId,
           narrativeHistory?.contains(where: { $0.originOperationId == originId }) == true {
            return false
        }
        narrativeHistory = (narrativeHistory ?? []) + [revision]
        narrative = revision.text
        lastUpdated = revision.date
        return true
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
        generatedAt: String = ISO8601.string(from: Date()),
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
        lastActiveAt: String = ISO8601.string(from: Date()),
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
        var nodeType: InquiryNodeType?
        var relationshipType: InquiryRelationshipType?
        var visibility: InquiryTreeNodeVisibility?
        var isPlaceholder: Bool?
        var placementDecisionId: String?
        var linkedExtractUUIDs: [String]?
        init(
            label: String? = nil,
            sourceTabId: String? = nil,
            selectionRangeStart: Int? = nil,
            selectionRangeEnd: Int? = nil,
            aiSuggested: Bool = false,
            accepted: Bool = true,
            nodeType: InquiryNodeType? = nil,
            relationshipType: InquiryRelationshipType? = nil,
            visibility: InquiryTreeNodeVisibility? = nil,
            isPlaceholder: Bool? = nil,
            placementDecisionId: String? = nil,
            linkedExtractUUIDs: [String]? = nil
        ) {
            self.label = label
            self.sourceTabId = sourceTabId
            self.selectionRangeStart = selectionRangeStart
            self.selectionRangeEnd = selectionRangeEnd
            self.aiSuggested = aiSuggested
            self.accepted = accepted
            self.nodeType = nodeType
            self.relationshipType = relationshipType
            self.visibility = visibility
            self.isPlaceholder = isPlaceholder
            self.placementDecisionId = placementDecisionId
            self.linkedExtractUUIDs = linkedExtractUUIDs
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
        createdAt: String = ISO8601.string(from: Date()),
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
            meta: ResearchTreeNode.Meta(
                label: rootQuestionAtomUUID == nil ? "What are you trying to understand?" : "Main question",
                aiSuggested: false,
                accepted: true,
                nodeType: .rootQuestion,
                relationshipType: .rootUnderTopic,
                visibility: .solidNode,
                isPlaceholder: rootQuestionAtomUUID == nil
            )
        )
        return ResearchTreeDocument(rootNodeId: rootId, nodes: [rootId: root])
    }

    var rootQuestionNodeIds: [String] {
        nodes.values
            .filter { $0.kind == .question && $0.parentNodeId == nil && $0.meta.visibility != .hidden }
            .sorted { $0.branchOrder < $1.branchOrder }
            .map(\.id)
    }

    /// Normalizes a question title for duplicate detection.
    static func normalizedQuestionKey(_ text: String) -> String {
        text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "?!.,;:"))
            .split(separator: " ")
            .joined(separator: " ")
    }

    /// Finds an existing visible root question matching the atomUUID or normalized label.
    func existingRootQuestionNodeId(atomUUID: String?, label: String?) -> String? {
        let key = label.map(Self.normalizedQuestionKey)
        return rootQuestionNodeIds.first { nodeId in
            guard let node = nodes[nodeId] else { return false }
            if let atomUUID, node.atomUUID == atomUUID { return true }
            if let key, !key.isEmpty, let nodeLabel = node.meta.label,
               Self.normalizedQuestionKey(nodeLabel) == key { return true }
            return false
        }
    }

    /// Append a root-level question under the Deep Dive topic. Returns the new node id,
    /// or the existing node id when the same question is already a root branch.
    @discardableResult
    mutating func appendRootQuestion(atomUUID: String? = nil, label: String? = nil, aiSuggested: Bool = false, accepted: Bool = true, sourceTabId: String? = nil, placementDecisionId: String? = nil) -> String {
        if let existingId = existingRootQuestionNodeId(atomUUID: atomUUID, label: label) {
            if let atomUUID, var existing = nodes[existingId], existing.atomUUID == nil {
                existing.atomUUID = atomUUID
                existing.meta.isPlaceholder = false
                nodes[existingId] = existing
            }
            return existingId
        }
        let newNode = ResearchTreeNode(
            kind: .question,
            atomUUID: atomUUID,
            parentNodeId: nil,
            childNodeIds: [],
            branchOrder: rootQuestionNodeIds.count,
            meta: ResearchTreeNode.Meta(
                label: label,
                sourceTabId: sourceTabId,
                aiSuggested: aiSuggested,
                accepted: accepted,
                nodeType: .rootQuestion,
                relationshipType: .rootUnderTopic,
                visibility: .solidNode,
                isPlaceholder: false,
                placementDecisionId: placementDecisionId
            )
        )
        nodes[newNode.id] = newNode
        return newNode.id
    }

    /// Append a child node under the given parent. Returns the new node id.
    @discardableResult
    mutating func appendChild(
        parentId: String,
        kind: ResearchTreeNode.Kind,
        atomUUID: String? = nil,
        label: String? = nil,
        aiSuggested: Bool = false,
        accepted: Bool = true,
        sourceTabId: String? = nil,
        nodeType: InquiryNodeType? = nil,
        relationshipType: InquiryRelationshipType? = nil,
        visibility: InquiryTreeNodeVisibility? = nil,
        placementDecisionId: String? = nil,
        linkedExtractUUIDs: [String]? = nil
    ) -> String? {
        guard var parent = nodes[parentId] else { return nil }
        let newNode = ResearchTreeNode(
            kind: kind,
            atomUUID: atomUUID,
            parentNodeId: parentId,
            childNodeIds: [],
            branchOrder: parent.childNodeIds.count,
            meta: ResearchTreeNode.Meta(
                label: label,
                sourceTabId: sourceTabId,
                aiSuggested: aiSuggested,
                accepted: accepted,
                nodeType: nodeType,
                relationshipType: relationshipType,
                visibility: visibility,
                isPlaceholder: false,
                placementDecisionId: placementDecisionId,
                linkedExtractUUIDs: linkedExtractUUIDs
            )
        )
        parent.childNodeIds.append(newNode.id)
        nodes[parentId] = parent
        nodes[newNode.id] = newNode
        return newNode.id
    }

    mutating func removeNode(_ nodeId: String, promoteChildrenTo parentId: String?) {
        guard let node = nodes[nodeId] else { return }
        if let oldParentId = node.parentNodeId, var oldParent = nodes[oldParentId] {
            oldParent.childNodeIds.removeAll { $0 == nodeId }
            nodes[oldParentId] = oldParent
        }
        if let parentId, var newParent = nodes[parentId] {
            for childId in node.childNodeIds {
                if var child = nodes[childId] {
                    child.parentNodeId = parentId
                    child.branchOrder = newParent.childNodeIds.count
                    nodes[childId] = child
                    newParent.childNodeIds.append(childId)
                }
            }
            nodes[parentId] = newParent
        } else {
            for childId in node.childNodeIds {
                if var child = nodes[childId] {
                    child.parentNodeId = nil
                    child.branchOrder = rootQuestionNodeIds.count
                    child.meta.nodeType = .rootQuestion
                    child.meta.relationshipType = .rootUnderTopic
                    nodes[childId] = child
                }
            }
        }
        nodes.removeValue(forKey: nodeId)
        normalizeBranchOrders()
    }

    mutating func reparentNode(_ nodeId: String, to newParentId: String?, relationshipType: InquiryRelationshipType) -> Bool {
        guard var node = nodes[nodeId], node.id != newParentId else { return false }
        if let newParentId, isDescendant(newParentId, of: nodeId) { return false }
        if let oldParentId = node.parentNodeId, var oldParent = nodes[oldParentId] {
            oldParent.childNodeIds.removeAll { $0 == nodeId }
            nodes[oldParentId] = oldParent
        }
        node.parentNodeId = newParentId
        node.meta.relationshipType = relationshipType
        if let newParentId, var newParent = nodes[newParentId] {
            node.branchOrder = newParent.childNodeIds.count
            node.meta.nodeType = .branchQuestion
            newParent.childNodeIds.append(nodeId)
            nodes[newParentId] = newParent
        } else {
            node.branchOrder = rootQuestionNodeIds.count
            node.meta.nodeType = .rootQuestion
            node.meta.relationshipType = .rootUnderTopic
        }
        nodes[nodeId] = node
        normalizeBranchOrders()
        return true
    }

    func isDescendant(_ possibleChildId: String, of ancestorId: String) -> Bool {
        var cursor = nodes[possibleChildId]?.parentNodeId
        while let id = cursor {
            if id == ancestorId { return true }
            cursor = nodes[id]?.parentNodeId
        }
        return false
    }

    mutating func normalizeBranchOrders() {
        for parentId in nodes.keys {
            guard var parent = nodes[parentId] else { continue }
            parent.childNodeIds = parent.childNodeIds.enumerated().map { index, childId in
                if var child = nodes[childId] {
                    child.branchOrder = index
                    nodes[childId] = child
                }
                return childId
            }
            nodes[parentId] = parent
        }
        for (index, nodeId) in rootQuestionNodeIds.enumerated() {
            if var node = nodes[nodeId] {
                node.branchOrder = index
                nodes[nodeId] = node
            }
        }
    }
}

/// Lightweight persisted UI state for the active Inquiry Workspace.
struct InquiryWorkspaceUIState: Codable, Sendable {
    var pinnedQuestionUUIDs: [String]
    var collapsedBranchNodeIds: [String]
    var pinnedNoteDraftsByQuestionUUID: [String: String]
    var selectedInspectorQuestionUUID: String?
    /// Study-shell panel visibility (nil = default visible). Optional so
    /// sessions saved before the Study shell keep decoding.
    var showTrailPanel: Bool?
    var showReadingPanel: Bool?

    init(
        pinnedQuestionUUIDs: [String] = [],
        collapsedBranchNodeIds: [String] = [],
        pinnedNoteDraftsByQuestionUUID: [String: String] = [:],
        selectedInspectorQuestionUUID: String? = nil,
        showTrailPanel: Bool? = nil,
        showReadingPanel: Bool? = nil
    ) {
        self.pinnedQuestionUUIDs = pinnedQuestionUUIDs
        self.collapsedBranchNodeIds = collapsedBranchNodeIds
        self.pinnedNoteDraftsByQuestionUUID = pinnedNoteDraftsByQuestionUUID
        self.selectedInspectorQuestionUUID = selectedInspectorQuestionUUID
        self.showTrailPanel = showTrailPanel
        self.showReadingPanel = showReadingPanel
    }
}

/// Chat-native durable action waiting for user approval.
struct InquiryRoutingCard: Codable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case branchProposal
        case childBranchProposal
        case claimProposal
        case evidenceProposal
        case counterevidenceProposal
        case mechanismProposal
        case assumptionProposal
        case sourceQualityWarning
        case sourceFinding
        case placementPreview
        case evidenceAudit
        case sourceSearchTask
        case termCandidate
        case deepDiveCandidate
        case noteRoute
        case modelUpdate
    }

    enum Status: String, Codable, Sendable {
        case pending
        case accepted
        case ignored
    }

    var id: String
    var kind: Kind
    var title: String
    var detail: String?
    var proposedQuestion: String?
    var proposedExtractText: String?
    var proposedExtractKind: ExtractKind?
    var actionTitle: String?
    var parentQuestionUUID: String?
    var parentBranchNodeId: String?
    var originExtractUUID: String?
    var sourceTabId: String?
    var placement: InquiryPlacementDecision?
    var alternatePlacements: [InquiryPlacementDecision]?
    var linkedClaimExtractUUID: String?
    var createdAt: String
    var status: Status

    init(
        id: String = UUID().uuidString,
        kind: Kind,
        title: String,
        detail: String? = nil,
        proposedQuestion: String? = nil,
        proposedExtractText: String? = nil,
        proposedExtractKind: ExtractKind? = nil,
        actionTitle: String? = nil,
        parentQuestionUUID: String? = nil,
        parentBranchNodeId: String? = nil,
        originExtractUUID: String? = nil,
        sourceTabId: String? = nil,
        placement: InquiryPlacementDecision? = nil,
        alternatePlacements: [InquiryPlacementDecision] = [],
        linkedClaimExtractUUID: String? = nil,
        createdAt: String = ISO8601.string(from: Date()),
        status: Status = .pending
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.proposedQuestion = proposedQuestion
        self.proposedExtractText = proposedExtractText
        self.proposedExtractKind = proposedExtractKind
        self.actionTitle = actionTitle
        self.parentQuestionUUID = parentQuestionUUID
        self.parentBranchNodeId = parentBranchNodeId
        self.originExtractUUID = originExtractUUID
        self.sourceTabId = sourceTabId
        self.placement = placement
        self.alternatePlacements = alternatePlacements
        self.linkedClaimExtractUUID = linkedClaimExtractUUID
        self.createdAt = createdAt
        self.status = status
    }
}

enum InquirySourceStatus: String, Codable, CaseIterable, Sendable {
    case viewed
    case saved
    case extracted
    case archived
    case deleted

    var displayName: String { rawValue.capitalized }
}

/// Durable source record for a session. Tabs are only views over these source atoms.
struct InquirySourceRef: Codable, Sendable, Identifiable {
    var id: String { sourceUUID }
    var sourceUUID: String
    var tabId: String?
    var url: String?
    var title: String
    var domain: String?
    var sourceType: String
    var status: InquirySourceStatus
    var primaryQuestionUUID: String?
    var primaryNodeId: String?
    var openedAt: String
    var lastOpenedAt: String
    var extractCount: Int
    var noteCount: Int
    var addedByUser: Bool?     // True when the user pasted/added this source themselves

    init(
        sourceUUID: String,
        tabId: String? = nil,
        url: String? = nil,
        title: String,
        domain: String? = nil,
        sourceType: String = "webpage",
        status: InquirySourceStatus = .viewed,
        primaryQuestionUUID: String? = nil,
        primaryNodeId: String? = nil,
        openedAt: String = ISO8601.string(from: Date()),
        lastOpenedAt: String = ISO8601.string(from: Date()),
        extractCount: Int = 0,
        noteCount: Int = 0,
        addedByUser: Bool? = nil
    ) {
        self.sourceUUID = sourceUUID
        self.tabId = tabId
        self.url = url
        self.title = title
        self.domain = domain
        self.sourceType = sourceType
        self.status = status
        self.primaryQuestionUUID = primaryQuestionUUID
        self.primaryNodeId = primaryNodeId
        self.openedAt = openedAt
        self.lastOpenedAt = lastOpenedAt
        self.extractCount = extractCount
        self.noteCount = noteCount
        self.addedByUser = addedByUser
    }
}

struct InquiryActivityEvent: Codable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case noteSaved
        case sourceOpened
        case sourceClosed
        case branchCreated
        case claimSaved
        case evidenceSaved
        case routingSuggested
        case routingIgnored
        case aiReply
        case extractSaved
    }

    var id: String
    var kind: Kind
    var title: String
    var detail: String?
    var questionUUID: String?
    var sourceUUID: String?
    var extractUUID: String?
    var routingCardId: String?
    var createdAt: String

    init(
        id: String = UUID().uuidString,
        kind: Kind,
        title: String,
        detail: String? = nil,
        questionUUID: String? = nil,
        sourceUUID: String? = nil,
        extractUUID: String? = nil,
        routingCardId: String? = nil,
        createdAt: String = ISO8601.string(from: Date())
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.questionUUID = questionUUID
        self.sourceUUID = sourceUUID
        self.extractUUID = extractUUID
        self.routingCardId = routingCardId
        self.createdAt = createdAt
    }
}

struct InquiryToast: Equatable {
    var message: String
    var detail: String?
}

/// A source tab within an Inquiry Session's Source Pane.
struct SourceTab: Codable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case web
        case pdf
        case youTube = "youtube"
        case internalAtom = "internal"
        case swipe
        case pageScan = "page_scan"
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
        lastReadAt: String = ISO8601.string(from: Date()),
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
    var suggestedKindConfidence: Double?
    var attachedQuestionId: String?
    var attachedSourceTabId: String?
    var status: Status
    var promotedToAtomUUID: String?

    init(
        id: String = UUID().uuidString,
        body: String,
        createdAt: String = ISO8601.string(from: Date()),
        source: Source = .type,
        suggestedKind: ExtractKind? = nil,
        suggestedKindConfidence: Double? = nil,
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
        self.suggestedKindConfidence = suggestedKindConfidence
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
        createdAt: String = ISO8601.string(from: Date()),
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
        init(id: String = UUID().uuidString, label: String, mentionCount: Int = 1, existingLexiconUUID: String? = nil, firstSeenAt: String = ISO8601.string(from: Date())) {
            self.id = id; self.label = label; self.mentionCount = mentionCount; self.existingLexiconUUID = existingLexiconUUID; self.firstSeenAt = firstSeenAt
        }
    }
    struct OpenLoop: Codable, Sendable, Identifiable {
        var id: String
        var description: String
        var sourceQuestionUUID: String?
        var detectedAt: String
        init(id: String = UUID().uuidString, description: String, sourceQuestionUUID: String? = nil, detectedAt: String = ISO8601.string(from: Date())) {
            self.id = id; self.description = description; self.sourceQuestionUUID = sourceQuestionUUID; self.detectedAt = detectedAt
        }
    }
    struct ContradictionAlert: Codable, Sendable, Identifiable {
        var id: String
        var description: String
        var leftExtractUUID: String?
        var rightExtractUUID: String?
        var detectedAt: String
        init(id: String = UUID().uuidString, description: String, leftExtractUUID: String? = nil, rightExtractUUID: String? = nil, detectedAt: String = ISO8601.string(from: Date())) {
            self.id = id; self.description = description; self.leftExtractUUID = leftExtractUUID; self.rightExtractUUID = rightExtractUUID; self.detectedAt = detectedAt
        }
    }
    struct BranchSuggestion: Codable, Sendable, Identifiable {
        var id: String
        var proposedQuestion: String
        var rationale: String?
        var fromNodeId: String?
        var detectedAt: String
        init(id: String = UUID().uuidString, proposedQuestion: String, rationale: String? = nil, fromNodeId: String? = nil, detectedAt: String = ISO8601.string(from: Date())) {
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
        lastUpdated: String = ISO8601.string(from: Date())
    ) {
        self.concepts = concepts
        self.openLoops = openLoops
        self.contradictions = contradictions
        self.branchSuggestions = branchSuggestions
        self.possibleConnectionUUIDs = possibleConnectionUUIDs
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Canvas Projection

enum CanvasProjectionStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case pendingReview
    case partiallyApplied
    case applied
    case rejected
    case rolledBack
}

enum CanvasProjectionAutoApplyPolicy: String, Codable, CaseIterable, Sendable {
    case never
    case lowRiskOnly
}

enum CanvasOperationType: String, Codable, CaseIterable, Sendable {
    case createCluster = "CREATE_CLUSTER"
    case updateCluster = "UPDATE_CLUSTER"
    case createObject = "CREATE_OBJECT"
    case appendToObject = "APPEND_TO_OBJECT"
    case createSourceCard = "CREATE_SOURCE_CARD"
    case createConceptCard = "CREATE_CONCEPT_CARD"
    case createNoteCard = "CREATE_NOTE_CARD"
    case createSticky = "CREATE_STICKY"
    case createClaimCard = "CREATE_CLAIM_CARD"
    case linkObjects = "LINK_OBJECTS"
    case placeObject = "PLACE_OBJECT"
    case moveObject = "MOVE_OBJECT"
    case hideArtifact = "HIDE_ARTIFACT"
    case promoteToConnection = "PROMOTE_TO_CONNECTION"
    case promoteToDeepDiveProfile = "PROMOTE_TO_DEEP_DIVE_PROFILE"
    case promoteToChildThinkspace = "PROMOTE_TO_CHILD_THINKSPACE"
    case updateCurrentUnderstanding = "UPDATE_CURRENT_UNDERSTANDING"
    case ignore = "IGNORE"

    var displayName: String {
        rawValue
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
            .capitalized
    }
}

enum CanvasOperationStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case accepted
    case rejected
    case edited
    case applied
    case deferred
    case blocked
}

enum CanvasObjectVisualMaturity: String, Codable, CaseIterable, Sendable {
    case rawCapture
    case noteOrExtract
    case sourceCard
    case claimQuestionOrTerm
    case conceptCardOrConnection
    case outputCard
    case openLoop
    case deepDiveProfile
    case childThinkspace
}

struct CanvasPlacementProposal: Codable, Sendable, Hashable {
    var x: Double
    var y: Double
    var width: Double?
    var height: Double?
    var clusterUUID: String?
    var placementRationale: String?

    init(
        x: Double,
        y: Double,
        width: Double? = nil,
        height: Double? = nil,
        clusterUUID: String? = nil,
        placementRationale: String? = nil
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.clusterUUID = clusterUUID
        self.placementRationale = placementRationale
    }
}

struct CanvasOperationAlternative: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var label: String
    var operationType: CanvasOperationType?
    var targetObjectUUID: String?
    var targetClusterUUID: String?
    var rationale: String?

    init(
        id: String = UUID().uuidString,
        label: String,
        operationType: CanvasOperationType? = nil,
        targetObjectUUID: String? = nil,
        targetClusterUUID: String? = nil,
        rationale: String? = nil
    ) {
        self.id = id
        self.label = label
        self.operationType = operationType
        self.targetObjectUUID = targetObjectUUID
        self.targetClusterUUID = targetClusterUUID
        self.rationale = rationale
    }
}

struct CanvasDuplicateCheckResult: Codable, Sendable, Hashable {
    enum Verdict: String, Codable, Sendable {
        case noneFound
        case likelyDuplicate
        case exactMatch
        case existingAppearance
        case needsReview
    }

    var verdict: Verdict
    var matchedObjectUUID: String?
    var matchedClusterUUID: String?
    var matchedSourceURL: String?
    var explanation: String

    init(
        verdict: Verdict = .noneFound,
        matchedObjectUUID: String? = nil,
        matchedClusterUUID: String? = nil,
        matchedSourceURL: String? = nil,
        explanation: String = "No duplicate found."
    ) {
        self.verdict = verdict
        self.matchedObjectUUID = matchedObjectUUID
        self.matchedClusterUUID = matchedClusterUUID
        self.matchedSourceURL = matchedSourceURL
        self.explanation = explanation
    }
}

enum CanvasAppendCreateRecommendation: String, Codable, CaseIterable, Sendable {
    case append
    case create
    case link
    case keepInternal
    case promote
    case review

    var displayName: String {
        rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

struct CanvasRollbackMetadata: Codable, Sendable, Hashable {
    var affectedAtomUUIDs: [String]
    var affectedCanvasBlockUUIDs: [String]
    var affectedClusterUUIDs: [String]
    var snapshotSummary: String?

    init(
        affectedAtomUUIDs: [String] = [],
        affectedCanvasBlockUUIDs: [String] = [],
        affectedClusterUUIDs: [String] = [],
        snapshotSummary: String? = nil
    ) {
        self.affectedAtomUUIDs = affectedAtomUUIDs
        self.affectedCanvasBlockUUIDs = affectedCanvasBlockUUIDs
        self.affectedClusterUUIDs = affectedClusterUUIDs
        self.snapshotSummary = snapshotSummary
    }
}

struct CanvasOperation: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var type: CanvasOperationType
    var sourceArtifactID: String
    var targetThinkspaceUUID: String
    var targetObjectUUID: String?
    var targetClusterUUID: String?
    var proposedObjectType: String?
    var proposedTitle: String?
    var proposedBody: String?
    var proposedPlacement: CanvasPlacementProposal?
    var relationshipType: String?
    var rationale: String
    var confidence: Double
    var alternatives: [CanvasOperationAlternative]
    var duplicateCheckResult: CanvasDuplicateCheckResult
    var appendCreateRecommendation: CanvasAppendCreateRecommendation
    var status: CanvasOperationStatus
    var rollbackMetadata: CanvasRollbackMetadata
    var visualMaturity: CanvasObjectVisualMaturity
    var requiresReview: Bool

    init(
        id: String = UUID().uuidString,
        type: CanvasOperationType,
        sourceArtifactID: String,
        targetThinkspaceUUID: String,
        targetObjectUUID: String? = nil,
        targetClusterUUID: String? = nil,
        proposedObjectType: String? = nil,
        proposedTitle: String? = nil,
        proposedBody: String? = nil,
        proposedPlacement: CanvasPlacementProposal? = nil,
        relationshipType: String? = nil,
        rationale: String,
        confidence: Double,
        alternatives: [CanvasOperationAlternative] = [],
        duplicateCheckResult: CanvasDuplicateCheckResult = CanvasDuplicateCheckResult(),
        appendCreateRecommendation: CanvasAppendCreateRecommendation,
        status: CanvasOperationStatus = .pending,
        rollbackMetadata: CanvasRollbackMetadata = CanvasRollbackMetadata(),
        visualMaturity: CanvasObjectVisualMaturity,
        requiresReview: Bool = true
    ) {
        self.id = id
        self.type = type
        self.sourceArtifactID = sourceArtifactID
        self.targetThinkspaceUUID = targetThinkspaceUUID
        self.targetObjectUUID = targetObjectUUID
        self.targetClusterUUID = targetClusterUUID
        self.proposedObjectType = proposedObjectType
        self.proposedTitle = proposedTitle
        self.proposedBody = proposedBody
        self.proposedPlacement = proposedPlacement
        self.relationshipType = relationshipType
        self.rationale = rationale
        self.confidence = confidence
        self.alternatives = alternatives
        self.duplicateCheckResult = duplicateCheckResult
        self.appendCreateRecommendation = appendCreateRecommendation
        self.status = status
        self.rollbackMetadata = rollbackMetadata
        self.visualMaturity = visualMaturity
        self.requiresReview = requiresReview
    }
}

struct CanvasProjectionVerificationReport: Codable, Sendable {
    var duplicateChecksPassed: Bool
    var existingObjectChecksPassed: Bool
    var existingClusterChecksPassed: Bool
    var sourceChecksPassed: Bool
    var appendCreateChecksPassed: Bool
    var linkValidationPassed: Bool
    var collisionWarnings: [String]
    var ambiguityWarnings: [String]
    var blockedOperationIds: [String]

    init(
        duplicateChecksPassed: Bool = true,
        existingObjectChecksPassed: Bool = true,
        existingClusterChecksPassed: Bool = true,
        sourceChecksPassed: Bool = true,
        appendCreateChecksPassed: Bool = true,
        linkValidationPassed: Bool = true,
        collisionWarnings: [String] = [],
        ambiguityWarnings: [String] = [],
        blockedOperationIds: [String] = []
    ) {
        self.duplicateChecksPassed = duplicateChecksPassed
        self.existingObjectChecksPassed = existingObjectChecksPassed
        self.existingClusterChecksPassed = existingClusterChecksPassed
        self.sourceChecksPassed = sourceChecksPassed
        self.appendCreateChecksPassed = appendCreateChecksPassed
        self.linkValidationPassed = linkValidationPassed
        self.collisionWarnings = collisionWarnings
        self.ambiguityWarnings = ambiguityWarnings
        self.blockedOperationIds = blockedOperationIds
    }
}

struct CanvasProjectionRollbackSnapshot: Codable, Sendable {
    var capturedAt: String
    var canvasBlockUUIDs: [String]
    var clusterUUIDs: [String]
    var atomUUIDs: [String]
    var summary: String

    init(
        capturedAt: String = ISO8601.string(from: Date()),
        canvasBlockUUIDs: [String] = [],
        clusterUUIDs: [String] = [],
        atomUUIDs: [String] = [],
        summary: String = ""
    ) {
        self.capturedAt = capturedAt
        self.canvasBlockUUIDs = canvasBlockUUIDs
        self.clusterUUIDs = clusterUUIDs
        self.atomUUIDs = atomUUIDs
        self.summary = summary
    }
}

struct CanvasProjection: Codable, Sendable, Identifiable {
    var id: String
    var sessionUUID: String
    var deepDiveProfileUUID: String
    var thinkspaceUUID: String
    var generatedAt: String
    var status: CanvasProjectionStatus
    var summary: String
    var operations: [CanvasOperation]
    var verificationReport: CanvasProjectionVerificationReport
    var rollbackSnapshot: CanvasProjectionRollbackSnapshot
    var autoApplyPolicy: CanvasProjectionAutoApplyPolicy
    var appliedAt: String?
    var appliedBy: String?

    init(
        id: String = UUID().uuidString,
        sessionUUID: String,
        deepDiveProfileUUID: String,
        thinkspaceUUID: String,
        generatedAt: String = ISO8601.string(from: Date()),
        status: CanvasProjectionStatus = .pendingReview,
        summary: String,
        operations: [CanvasOperation] = [],
        verificationReport: CanvasProjectionVerificationReport = CanvasProjectionVerificationReport(),
        rollbackSnapshot: CanvasProjectionRollbackSnapshot = CanvasProjectionRollbackSnapshot(),
        autoApplyPolicy: CanvasProjectionAutoApplyPolicy = .never,
        appliedAt: String? = nil,
        appliedBy: String? = nil
    ) {
        self.id = id
        self.sessionUUID = sessionUUID
        self.deepDiveProfileUUID = deepDiveProfileUUID
        self.thinkspaceUUID = thinkspaceUUID
        self.generatedAt = generatedAt
        self.status = status
        self.summary = summary
        self.operations = operations
        self.verificationReport = verificationReport
        self.rollbackSnapshot = rollbackSnapshot
        self.autoApplyPolicy = autoApplyPolicy
        self.appliedAt = appliedAt
        self.appliedBy = appliedBy
    }
}

/// Crystallization output (Phase 5). Persisted in InquirySession.structured.crystallizationResult.
struct ConnectionSectionItemDraft: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var body: String
    var sourceUUID: String?
    var originExtractUUID: String?
    var kindLabel: String
    /// The original verbatim capture this draft was organized/split from. When the
    /// Concept Composer cleans and splits a raw capture, `body` holds the cleaned
    /// bullet and `rawSnippet` preserves what the user actually captured, so nothing
    /// is lost — it rides through to `ConnectionItem.sourceSnippet` on promotion.
    var rawSnippet: String?

    init(
        id: String = UUID().uuidString,
        body: String,
        sourceUUID: String? = nil,
        originExtractUUID: String? = nil,
        kindLabel: String,
        rawSnippet: String? = nil
    ) {
        self.id = id
        self.body = body
        self.sourceUUID = sourceUUID
        self.originExtractUUID = originExtractUUID
        self.kindLabel = kindLabel
        self.rawSnippet = rawSnippet
    }

    enum CodingKeys: String, CodingKey {
        case id, body, sourceUUID, originExtractUUID, kindLabel, rawSnippet
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        sourceUUID = try c.decodeIfPresent(String.self, forKey: .sourceUUID)
        originExtractUUID = try c.decodeIfPresent(String.self, forKey: .originExtractUUID)
        kindLabel = try c.decodeIfPresent(String.self, forKey: .kindLabel) ?? ""
        rawSnippet = try c.decodeIfPresent(String.self, forKey: .rawSnippet)
    }
}

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
        var proposedTitle: String
        var proposedConcept: String?
        var proposedSections: [ConnectionSectionType: [ConnectionSectionItemDraft]]
        var proposedReferences: [String]
        var branchNodeId: String?
        var materialCount: Int
        var proposedNotes: [ConnectionSectionItemDraft]
        var accepted: Bool
        var mergeTargetConnectionUUID: String?   // AI-chosen merge destination (concept-first)
        var conceptAliases: [String]?
        var conceptKey: String?                  // Normalized concept name; cross-session dedup
        var relatedConceptNames: [String]?       // Other concept pages this one mentions → hyperlinks
        var parentConceptName: String?           // Broader page this one nests under (map hierarchy)

        init(
            id: String = UUID().uuidString,
            name: String,
            rationale: String? = nil,
            clusterExtractUUIDs: [String] = [],
            seededLexiconCandidateIds: [String] = [],
            proposedTitle: String? = nil,
            proposedConcept: String? = nil,
            proposedSections: [ConnectionSectionType: [ConnectionSectionItemDraft]] = [:],
            proposedReferences: [String] = [],
            branchNodeId: String? = nil,
            materialCount: Int = 0,
            proposedNotes: [ConnectionSectionItemDraft] = [],
            accepted: Bool = false,
            mergeTargetConnectionUUID: String? = nil,
            conceptAliases: [String]? = nil,
            conceptKey: String? = nil,
            relatedConceptNames: [String]? = nil,
            parentConceptName: String? = nil
        ) {
            self.id = id
            self.name = name
            self.rationale = rationale
            self.clusterExtractUUIDs = clusterExtractUUIDs
            self.seededLexiconCandidateIds = seededLexiconCandidateIds
            self.proposedTitle = proposedTitle ?? name
            self.proposedConcept = proposedConcept
            self.proposedSections = proposedSections
            self.proposedReferences = proposedReferences
            self.branchNodeId = branchNodeId
            self.materialCount = materialCount
            self.proposedNotes = proposedNotes
            self.accepted = accepted
            self.mergeTargetConnectionUUID = mergeTargetConnectionUUID
            self.conceptAliases = conceptAliases
            self.conceptKey = conceptKey
            self.relatedConceptNames = relatedConceptNames
            self.parentConceptName = parentConceptName
        }

        private enum CodingKeys: String, CodingKey {
            case id, name, rationale, clusterExtractUUIDs, seededLexiconCandidateIds
            case proposedTitle, proposedConcept, proposedSections, proposedReferences
            case branchNodeId, materialCount, proposedNotes, accepted
            case mergeTargetConnectionUUID, conceptAliases, conceptKey, relatedConceptNames, parentConceptName
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
            name = try c.decode(String.self, forKey: .name)
            rationale = try c.decodeIfPresent(String.self, forKey: .rationale)
            clusterExtractUUIDs = try c.decodeIfPresent([String].self, forKey: .clusterExtractUUIDs) ?? []
            seededLexiconCandidateIds = try c.decodeIfPresent([String].self, forKey: .seededLexiconCandidateIds) ?? []
            proposedTitle = try c.decodeIfPresent(String.self, forKey: .proposedTitle) ?? name
            proposedConcept = try c.decodeIfPresent(String.self, forKey: .proposedConcept)
            let rawSections = try c.decodeIfPresent([String: [ConnectionSectionItemDraft]].self, forKey: .proposedSections) ?? [:]
            proposedSections = rawSections.reduce(into: [:]) { partial, pair in
                guard let type = ConnectionSectionType(rawValue: pair.key) else { return }
                partial[type] = pair.value
            }
            proposedReferences = try c.decodeIfPresent([String].self, forKey: .proposedReferences) ?? []
            branchNodeId = try c.decodeIfPresent(String.self, forKey: .branchNodeId)
            materialCount = try c.decodeIfPresent(Int.self, forKey: .materialCount) ?? clusterExtractUUIDs.count
            proposedNotes = try c.decodeIfPresent([ConnectionSectionItemDraft].self, forKey: .proposedNotes) ?? []
            accepted = try c.decodeIfPresent(Bool.self, forKey: .accepted) ?? false
            mergeTargetConnectionUUID = try c.decodeIfPresent(String.self, forKey: .mergeTargetConnectionUUID)
            conceptAliases = try c.decodeIfPresent([String].self, forKey: .conceptAliases)
            conceptKey = try c.decodeIfPresent(String.self, forKey: .conceptKey)
            relatedConceptNames = try c.decodeIfPresent([String].self, forKey: .relatedConceptNames)
            parentConceptName = try c.decodeIfPresent(String.self, forKey: .parentConceptName)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encodeIfPresent(rationale, forKey: .rationale)
            try c.encode(clusterExtractUUIDs, forKey: .clusterExtractUUIDs)
            try c.encode(seededLexiconCandidateIds, forKey: .seededLexiconCandidateIds)
            try c.encode(proposedTitle, forKey: .proposedTitle)
            try c.encodeIfPresent(proposedConcept, forKey: .proposedConcept)
            let rawSections = proposedSections.reduce(into: [String: [ConnectionSectionItemDraft]]()) { partial, pair in
                partial[pair.key.rawValue] = pair.value
            }
            try c.encode(rawSections, forKey: .proposedSections)
            try c.encode(proposedReferences, forKey: .proposedReferences)
            try c.encodeIfPresent(branchNodeId, forKey: .branchNodeId)
            try c.encode(materialCount, forKey: .materialCount)
            try c.encode(proposedNotes, forKey: .proposedNotes)
            try c.encode(accepted, forKey: .accepted)
            try c.encodeIfPresent(mergeTargetConnectionUUID, forKey: .mergeTargetConnectionUUID)
            try c.encodeIfPresent(conceptAliases, forKey: .conceptAliases)
            try c.encodeIfPresent(conceptKey, forKey: .conceptKey)
            try c.encodeIfPresent(relatedConceptNames, forKey: .relatedConceptNames)
            try c.encodeIfPresent(parentConceptName, forKey: .parentConceptName)
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
    var canvasProjection: CanvasProjection?
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
        canvasProjection: CanvasProjection? = nil,
        promotionSuggestions: [PromotionSuggestion] = [],
        rejected: [RejectedItem] = [],
        generatedAt: String = ISO8601.string(from: Date())
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
        self.canvasProjection = canvasProjection
        self.promotionSuggestions = promotionSuggestions
        self.rejected = rejected
        self.generatedAt = generatedAt
    }
}

/// Structured field for `.inquirySession` atoms.
struct InquirySessionStructured: Codable, Sendable {
    var researchTree: ResearchTreeDocument
    var sourceTabs: [SourceTab]
    var sourceRefs: [InquirySourceRef]
    var sessionCaptures: [SessionCapture]
    var aiInteractions: [AIInteractionRef]
    var activityEvents: [InquiryActivityEvent]
    var mapForming: MapFormingState
    var uiState: InquiryWorkspaceUIState
    var routingCards: [InquiryRoutingCard]
    var operationalTasks: [InquiryOperationalTask]
    var recommendationBatches: [InquiryRecommendationBatch]
    var routeReceipts: [InquiryRouteReceipt]
    var crystallizationResult: CrystallizationOutput?
    var currentUnderstandingDraft: LiveUnderstandingDraft?
    var liveRoutingDecisions: [InquiryLiveRoutingDecision]

    enum CodingKeys: String, CodingKey {
        case researchTree
        case sourceTabs
        case sourceRefs
        case sessionCaptures
        case aiInteractions
        case activityEvents
        case mapForming
        case uiState
        case routingCards
        case operationalTasks
        case recommendationBatches
        case routeReceipts
        case crystallizationResult
        case currentUnderstandingDraft
        case liveRoutingDecisions
    }

    init(
        researchTree: ResearchTreeDocument,
        sourceTabs: [SourceTab] = [],
        sourceRefs: [InquirySourceRef] = [],
        sessionCaptures: [SessionCapture] = [],
        aiInteractions: [AIInteractionRef] = [],
        activityEvents: [InquiryActivityEvent] = [],
        mapForming: MapFormingState = MapFormingState(),
        uiState: InquiryWorkspaceUIState = InquiryWorkspaceUIState(),
        routingCards: [InquiryRoutingCard] = [],
        operationalTasks: [InquiryOperationalTask] = [],
        recommendationBatches: [InquiryRecommendationBatch] = [],
        routeReceipts: [InquiryRouteReceipt] = [],
        crystallizationResult: CrystallizationOutput? = nil,
        currentUnderstandingDraft: LiveUnderstandingDraft? = nil,
        liveRoutingDecisions: [InquiryLiveRoutingDecision] = []
    ) {
        self.researchTree = researchTree
        self.sourceTabs = sourceTabs
        self.sourceRefs = sourceRefs
        self.sessionCaptures = sessionCaptures
        self.aiInteractions = aiInteractions
        self.activityEvents = activityEvents
        self.mapForming = mapForming
        self.uiState = uiState
        self.routingCards = routingCards
        self.operationalTasks = operationalTasks
        self.recommendationBatches = recommendationBatches
        self.routeReceipts = routeReceipts
        self.crystallizationResult = crystallizationResult
        self.currentUnderstandingDraft = currentUnderstandingDraft
        self.liveRoutingDecisions = liveRoutingDecisions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        researchTree = try container.decode(ResearchTreeDocument.self, forKey: .researchTree)
        sourceTabs = try container.decodeIfPresent([SourceTab].self, forKey: .sourceTabs) ?? []
        sourceRefs = try container.decodeIfPresent([InquirySourceRef].self, forKey: .sourceRefs) ?? []
        sessionCaptures = try container.decodeIfPresent([SessionCapture].self, forKey: .sessionCaptures) ?? []
        aiInteractions = try container.decodeIfPresent([AIInteractionRef].self, forKey: .aiInteractions) ?? []
        activityEvents = try container.decodeIfPresent([InquiryActivityEvent].self, forKey: .activityEvents) ?? []
        mapForming = try container.decodeIfPresent(MapFormingState.self, forKey: .mapForming) ?? MapFormingState()
        uiState = try container.decodeIfPresent(InquiryWorkspaceUIState.self, forKey: .uiState) ?? InquiryWorkspaceUIState()
        routingCards = try container.decodeIfPresent([InquiryRoutingCard].self, forKey: .routingCards) ?? []
        operationalTasks = try container.decodeIfPresent([InquiryOperationalTask].self, forKey: .operationalTasks) ?? []
        recommendationBatches = try container.decodeIfPresent([InquiryRecommendationBatch].self, forKey: .recommendationBatches) ?? []
        routeReceipts = try container.decodeIfPresent([InquiryRouteReceipt].self, forKey: .routeReceipts) ?? []
        crystallizationResult = try container.decodeIfPresent(CrystallizationOutput.self, forKey: .crystallizationResult)
        currentUnderstandingDraft = try container.decodeIfPresent(LiveUnderstandingDraft.self, forKey: .currentUnderstandingDraft)
        liveRoutingDecisions = try container.decodeIfPresent([InquiryLiveRoutingDecision].self, forKey: .liveRoutingDecisions) ?? []
    }
}

/// A persisted live-router decision: how one capture was split/typed/placed.
/// The id doubles as the idempotency key stamped onto refined extracts.
struct InquiryLiveRoutingDecision: Codable, Sendable, Identifiable {
    struct Destination: Codable, Sendable {
        var extractUUID: String
        var kind: ExtractKind
        var questionUUID: String?
        var conceptNames: [String]
    }
    var id: String
    var sourceExtractUUID: String?
    var appliedAt: String          // ISO8601
    var summary: String            // "Split into 2 claims · 1 new branch"
    var destinations: [Destination]

    init(
        id: String = UUID().uuidString,
        sourceExtractUUID: String? = nil,
        appliedAt: String = ISO8601.string(from: Date()),
        summary: String,
        destinations: [Destination] = []
    ) {
        self.id = id
        self.sourceExtractUUID = sourceExtractUUID
        self.appliedAt = appliedAt
        self.summary = summary
        self.destinations = destinations
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
    var questionRole: InquiryNodeType?
    var relationshipToParent: InquiryRelationshipType?
    var placementOrigin: String?
    var placementConfidence: InquiryPlacementConfidence?
    var placementExplanation: String?
    var sourceQuestionUUID: String?
    var sourceExtractUUID: String?

    init(
        parentDeepDiveUUID: String? = nil,
        parentQuestionUUID: String? = nil,
        originSessionUUID: String? = nil,
        originExtractUUID: String? = nil,
        status: QuestionStatus = .open,
        priority: Int? = nil,
        confidence: QuestionConfidence? = nil,
        questionRole: InquiryNodeType? = nil,
        relationshipToParent: InquiryRelationshipType? = nil,
        placementOrigin: String? = nil,
        placementConfidence: InquiryPlacementConfidence? = nil,
        placementExplanation: String? = nil,
        sourceQuestionUUID: String? = nil,
        sourceExtractUUID: String? = nil
    ) {
        self.parentDeepDiveUUID = parentDeepDiveUUID
        self.parentQuestionUUID = parentQuestionUUID
        self.originSessionUUID = originSessionUUID
        self.originExtractUUID = originExtractUUID
        self.status = status
        self.priority = priority
        self.confidence = confidence
        self.questionRole = questionRole
        self.relationshipToParent = relationshipToParent
        self.placementOrigin = placementOrigin
        self.placementConfidence = placementConfidence
        self.placementExplanation = placementExplanation
        self.sourceQuestionUUID = sourceQuestionUUID
        self.sourceExtractUUID = sourceExtractUUID
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
    var routingDecisionId: String?       // Live-router decision that settled this extract (idempotency)
    var conceptNames: [String]?          // Concept-page assignments ("Pranayama", "Vagus nerve")
    var kindPending: Bool?               // True while awaiting LLM classification ("Classifying…" UI)
    var attachmentUUIDs: [String]?       // Page-scan originals this extract was digitized from

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
        committedAt: String? = ISO8601.string(from: Date()),
        promotedToUUID: String? = nil,
        originType: String? = nil,
        citation: String? = nil,
        routingDecisionId: String? = nil,
        conceptNames: [String]? = nil,
        kindPending: Bool? = nil,
        attachmentUUIDs: [String]? = nil
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
        self.routingDecisionId = routingDecisionId
        self.conceptNames = conceptNames
        self.kindPending = kindPending
        self.attachmentUUIDs = attachmentUUIDs
    }
}

// MARK: - Connection Hierarchy

/// Concept-hierarchy position of a Connection page: which broader concept
/// page it nests under on the Deep Dive map. Key-merged into the connection's
/// metadata JSON alongside its promotion metadata (`mergingMetadataKeys`).
struct ConnectionHierarchyMetadata: Codable, Sendable {
    var parentConnectionUUID: String?
    var parentPinnedByUser: Bool?    // User chose it — crystallization must never overwrite.
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
        firstSeenAt: String = ISO8601.string(from: Date()),
        lastSeenAt: String = ISO8601.string(from: Date()),
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
