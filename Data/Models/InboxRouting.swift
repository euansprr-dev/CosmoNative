import Foundation
import CoreGraphics

enum InboxRouteKind: String, Codable, CaseIterable, Sendable {
    case mergeAtom
    case fileToDestination
    case placeInExistingCluster
    case createClusterAndPlace
    case placeInThinkspace
    case createThinkspaceAndPlace
    case createStandaloneAtom

    // Atlas moves (July 2026) — knowledge-graph destinations beyond folders.
    // A capture can advance an open inquiry question, become a new research
    // branch, mature a concept page, or land as an idea for a client.
    case advanceQuestion
    case spawnQuestion
    case feedConnection
    case attachClient
    case germinateConnection
    /// The capture opens a research topic no Space covers yet: a NEW Space
    /// named for the topic, with an inquiry started inside it from the
    /// capture's question. (Pre-September 2026 this made a standalone deep
    /// dive; Spaces host inquiries now, so a topic with no home gets one.)
    case germinateDeepDive
    /// The capture is something the user wants to RESEARCH inside a Space
    /// they already have: an inquiry session starts there, the capture is
    /// its question, and any extra prose lands as the session's first note.
    /// September 2026 — the capture → inquiry loop.
    case startInquiry
    // The global Seedbed (July 2026) — insight captures GROW: they add mass
    // to a named proto-concept instead of landing as canvas objects or
    // premature pages. startSeedling supersedes germinateConnection (kept
    // decodable for rows classified before the Seedbed shipped).
    case feedSeedling
    case startSeedling
    /// The capture is a craft reference — a link, image, or piece of copy the
    /// user saved for its FORM. It becomes a swipe (kind inferred by
    /// SwipeIntakeRouter), never a canvas object.
    case fileAsSwipe
    /// The capture is a step in a funnel the user is assembling — it appends
    /// to an existing flow swipe rather than landing loose.
    case addToFlow

    /// What accepting this suggestion MAKES — the noun the pill and inspector
    /// lead with, so "what it becomes" is never implicit. Spatial kinds name
    /// the atom type they'd create; knowledge-graph kinds name the move.
    func outcomeNoun(suggestedAtomType: String?) -> String {
        let atomNoun = suggestedAtomType
            .flatMap(AtomType.init(rawValue:))
            .map(\.displayName) ?? "Page"
        switch self {
        case .fileToDestination: return "File capture"
        case .mergeAtom:
            return "Attach reference"
        case .placeInExistingCluster, .createClusterAndPlace,
             .placeInThinkspace, .createThinkspaceAndPlace:
            return "Page in Space"
        case .createStandaloneAtom:
            return atomNoun
        case .advanceQuestion:
            return "Answers a question"
        case .spawnQuestion:
            return "New question"
        case .feedConnection:
            return "Evidence for review"
        case .attachClient:
            return "Client idea"
        case .germinateDeepDive:
            return "Inquiry in new Space"
        case .startInquiry:
            return "Inquiry in Space"
        case .feedSeedling:
            return "Grows a concept"
        case .startSeedling, .germinateConnection:
            return "New concept"
        case .fileAsSwipe:
            return "Swipe file"
        case .addToFlow:
            return "Step in a flow"
        }
    }

    /// The SF symbol that pairs with `outcomeNoun` in pills and the inspector.
    var outcomeIcon: String {
        switch self {
        case .fileToDestination: return "tray.and.arrow.down"
        case .mergeAtom:
            return "link"
        case .placeInExistingCluster, .createClusterAndPlace,
             .placeInThinkspace, .createThinkspaceAndPlace, .createStandaloneAtom:
            return "arrow.turn.down.right"
        case .advanceQuestion:
            return "questionmark.circle"
        case .spawnQuestion:
            return "questionmark.bubble"
        case .feedConnection:
            return "text.append"
        case .attachClient:
            return "person.crop.circle"
        case .germinateDeepDive:
            return "sparkle.magnifyingglass"
        case .startInquiry:
            return "text.magnifyingglass"
        case .feedSeedling, .startSeedling, .germinateConnection:
            return "leaf"
        case .fileAsSwipe:
            return SwipeKind.post.iconName
        case .addToFlow:
            return SwipeKind.flow.iconName
        }
    }

    /// The primary accept button says what accepting DOES — one word per kind.
    var primaryVerbLabel: String {
        switch self {
        case .fileToDestination: return "File"
        case .mergeAtom:
            return "Attach reference"
        case .startSeedling, .germinateConnection:
            return "Start concept"
        case .feedSeedling:
            return "Add to concept"
        case .feedConnection:
            return "Add for review"
        case .advanceQuestion:
            return "Answer"
        case .spawnQuestion:
            return "Ask"
        case .attachClient:
            return "Attach"
        case .germinateDeepDive, .startInquiry:
            return "Start inquiry"
        case .placeInExistingCluster, .createClusterAndPlace,
             .placeInThinkspace, .createThinkspaceAndPlace, .createStandaloneAtom:
            return "Place"
        case .fileAsSwipe:
            return "Swipe"
        case .addToFlow:
            return "Add step"
        }
    }

    /// Seedling-family kinds grow mass instead of creating atoms — the UI
    /// branches on this for leaf icons and the develop-now follow-up.
    var isSeedlingKind: Bool {
        switch self {
        case .feedSeedling, .startSeedling, .germinateConnection:
            return true
        default:
            return false
        }
    }

    /// Kinds that land the capture in the inquiry graph (a question thread
    /// or a Space's inquiry session) — the UI tints these as research.
    var isInquiryKind: Bool {
        switch self {
        case .advanceQuestion, .spawnQuestion, .germinateDeepDive, .startInquiry:
            return true
        default:
            return false
        }
    }

    var legacyClassification: InboxClassification {
        switch self {
        case .mergeAtom:
            return .merge
        case .fileToDestination, .placeInExistingCluster, .createClusterAndPlace, .placeInThinkspace, .createThinkspaceAndPlace:
            return .place
        case .advanceQuestion, .spawnQuestion, .feedConnection, .attachClient,
             .germinateConnection, .germinateDeepDive, .startInquiry, .feedSeedling, .startSeedling,
             .fileAsSwipe, .addToFlow:
            // Actionable destination suggestions — the pill renders like a place.
            return .place
        case .createStandaloneAtom:
            // v2 only emits a standalone option when the router abstained —
            // the item is unsorted, the option is just the manual-filing default.
            return .unsorted
        }
    }
}

/// Typed payload for Atlas moves — destinations in the knowledge graph that
/// the thinkspace/cluster fields can't describe. Optional on
/// `InboxRecommendation` so bundles persisted before July 2026 still decode,
/// and every field is optional so future additions stay decode-tolerant.
struct InboxAtlasMove: Codable, Equatable, Sendable {
    // Inquiry graph (advanceQuestion / spawnQuestion)
    var deepDiveUUID: String?
    var deepDiveName: String?
    var questionUUID: String?          // Existing open question to advance
    var questionTitle: String?
    var newQuestionTitle: String?      // Cleaned phrasing for a spawned branch
    var parentQuestionUUID: String?    // Nesting contract: decomposition parent

    // Concept pages (feedConnection)
    var connectionUUID: String?
    var connectionName: String?
    var connectionSection: String?     // ConnectionSectionType rawValue

    // Clients (attachClient)
    var clientUUID: String?
    var clientName: String?

    // Germination (startSeedling / germinateDeepDive; legacy germinateConnection)
    var germinateTitle: String?

    // Space inquiry (startInquiry) — the Space that hosts the session. The
    // question itself rides `newQuestionTitle`; germinateDeepDive names the
    // NEW Space via `germinateTitle` instead.
    var spaceUUID: String?
    var spaceName: String?

    // The global Seedbed (feedSeedling)
    var seedlingUUID: String?
    var seedlingName: String?

    // The concept's future home (feedSeedling / startSeedling) — stamps the
    // seedling's spatial affinity so the developed page knows where it lives.
    // Tags, never places: no canvas object exists until development.
    var homeThinkspaceId: String?
    var homeThinkspaceName: String?
    var homeClusterId: String?
    var homeClusterName: String?

    init(
        deepDiveUUID: String? = nil,
        deepDiveName: String? = nil,
        questionUUID: String? = nil,
        questionTitle: String? = nil,
        newQuestionTitle: String? = nil,
        parentQuestionUUID: String? = nil,
        connectionUUID: String? = nil,
        connectionName: String? = nil,
        connectionSection: String? = nil,
        clientUUID: String? = nil,
        clientName: String? = nil,
        germinateTitle: String? = nil,
        seedlingUUID: String? = nil,
        seedlingName: String? = nil,
        homeThinkspaceId: String? = nil,
        homeThinkspaceName: String? = nil,
        homeClusterId: String? = nil,
        homeClusterName: String? = nil,
        spaceUUID: String? = nil,
        spaceName: String? = nil
    ) {
        self.deepDiveUUID = deepDiveUUID
        self.deepDiveName = deepDiveName
        self.questionUUID = questionUUID
        self.questionTitle = questionTitle
        self.newQuestionTitle = newQuestionTitle
        self.parentQuestionUUID = parentQuestionUUID
        self.connectionUUID = connectionUUID
        self.connectionName = connectionName
        self.connectionSection = connectionSection
        self.clientUUID = clientUUID
        self.clientName = clientName
        self.germinateTitle = germinateTitle
        self.seedlingUUID = seedlingUUID
        self.seedlingName = seedlingName
        self.homeThinkspaceId = homeThinkspaceId
        self.homeThinkspaceName = homeThinkspaceName
        self.homeClusterId = homeClusterId
        self.homeClusterName = homeClusterName
        self.spaceUUID = spaceUUID
        self.spaceName = spaceName
    }
}

enum InboxPlacementOperationKind: String, Codable, CaseIterable, Sendable {
    case createThinkspace
    case createCluster
    case resizeCluster
    case createAtom
    case mergeIntoAtom
    case placeBlock
    case moveBlock
}

struct InboxPlacementRect: Codable, Equatable, Sendable {
    let originX: Double
    let originY: Double
    let width: Double
    let height: Double
}

struct InboxPlacementOperation: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: InboxPlacementOperationKind
    let description: String

    init(
        id: String = UUID().uuidString,
        kind: InboxPlacementOperationKind,
        description: String
    ) {
        self.id = id
        self.kind = kind
        self.description = description
    }
}

struct InboxPlacementPlan: Codable, Equatable, Sendable {
    let targetThinkspaceId: String?
    let targetThinkspaceName: String?
    let targetClusterId: String?
    let targetClusterName: String?
    let clusterViewMode: String?
    let blockPositionX: Double?
    let blockPositionY: Double?
    let clusterRect: InboxPlacementRect?
    let operations: [InboxPlacementOperation]
    let summary: String
}

struct InboxRecommendation: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: InboxRouteKind
    let confidence: Double
    let suggestedAtomType: String
    let destinationPath: String
    let rationale: String
    let mergeTargetUuid: String?
    let mergeTargetTitle: String?
    let mergeTargetType: String?
    let thinkspaceId: String?
    let thinkspaceName: String?
    let clusterId: String?
    let clusterName: String?
    let placementPlan: InboxPlacementPlan?
    /// Atlas destination payload (inquiry question, connection section, client…).
    /// Optional for decode compatibility with pre-July-2026 bundles.
    let atlasMove: InboxAtlasMove?
    let filingDestination: InboxFilingDestination?
    let filingAction: InboxFilingAction?

    init(
        id: String = UUID().uuidString,
        kind: InboxRouteKind,
        confidence: Double,
        suggestedAtomType: String,
        destinationPath: String,
        rationale: String,
        mergeTargetUuid: String? = nil,
        mergeTargetTitle: String? = nil,
        mergeTargetType: String? = nil,
        thinkspaceId: String? = nil,
        thinkspaceName: String? = nil,
        clusterId: String? = nil,
        clusterName: String? = nil,
        placementPlan: InboxPlacementPlan? = nil,
        atlasMove: InboxAtlasMove? = nil,
        filingDestination: InboxFilingDestination? = nil,
        filingAction: InboxFilingAction? = nil
    ) {
        self.id = id
        self.kind = kind
        self.confidence = confidence
        self.suggestedAtomType = suggestedAtomType
        self.destinationPath = destinationPath
        self.rationale = rationale
        self.mergeTargetUuid = mergeTargetUuid
        self.mergeTargetTitle = mergeTargetTitle
        self.mergeTargetType = mergeTargetType
        self.thinkspaceId = thinkspaceId
        self.thinkspaceName = thinkspaceName
        self.clusterId = clusterId
        self.clusterName = clusterName
        self.placementPlan = placementPlan
        self.atlasMove = atlasMove
        self.filingDestination = filingDestination
        self.filingAction = filingAction
    }
}

struct InboxRecommendationBundle: Codable, Equatable, Sendable {
    let bundleId: String
    let title: String
    let createdAt: String
    let recommendations: [InboxRecommendation]
    /// Existing atoms the capture strongly relates to (without being a
    /// duplicate of any) — powers the Connect verb. Optional for decode
    /// compatibility with pre-June-2026 rows.
    let relatedAtomUUIDs: [String]?

    init(
        bundleId: String = UUID().uuidString,
        title: String,
        createdAt: String = ISO8601.string(from: Date()),
        recommendations: [InboxRecommendation],
        relatedAtomUUIDs: [String]? = nil
    ) {
        self.bundleId = bundleId
        self.title = title
        self.createdAt = createdAt
        self.relatedAtomUUIDs = relatedAtomUUIDs
        self.recommendations = recommendations.sorted { lhs, rhs in
            if abs(lhs.confidence - rhs.confidence) > 0.0001 {
                return lhs.confidence > rhs.confidence
            }
            return lhs.destinationPath < rhs.destinationPath
        }
    }

    var primaryRecommendation: InboxRecommendation? {
        recommendations.first
    }

    var alternativeRecommendations: [InboxRecommendation] {
        Array(recommendations.dropFirst())
    }

    var encodedJSONString: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension InboxItem {
    var recommendationBundleValue: InboxRecommendationBundle? {
        guard let recommendations,
              let data = recommendations.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(InboxRecommendationBundle.self, from: data)
    }

    var primaryRecommendationValue: InboxRecommendation? {
        recommendationBundleValue?.primaryRecommendation
    }

    var alternativeRecommendationValues: [InboxRecommendation] {
        recommendationBundleValue?.alternativeRecommendations ?? []
    }

    /// Atoms this capture strongly relates to — enables the Connect verb.
    var relatedAtomUUIDsValue: [String] {
        recommendationBundleValue?.relatedAtomUUIDs ?? []
    }
}

extension InboxRecommendation {
    /// The same recommendation with the block landing position replaced — used
    /// when the user drags the ghost block on the inspector minimap before placing.
    func overridingBlockPosition(_ position: CGPoint) -> InboxRecommendation {
        guard let plan = placementPlan else { return self }
        let adjustedPlan = InboxPlacementPlan(
            targetThinkspaceId: plan.targetThinkspaceId,
            targetThinkspaceName: plan.targetThinkspaceName,
            targetClusterId: plan.targetClusterId,
            targetClusterName: plan.targetClusterName,
            clusterViewMode: plan.clusterViewMode,
            blockPositionX: Double(position.x),
            blockPositionY: Double(position.y),
            clusterRect: plan.clusterRect,
            operations: plan.operations,
            summary: plan.summary
        )
        return InboxRecommendation(
            id: id,
            kind: kind,
            confidence: confidence,
            suggestedAtomType: suggestedAtomType,
            destinationPath: destinationPath,
            rationale: rationale,
            mergeTargetUuid: mergeTargetUuid,
            mergeTargetTitle: mergeTargetTitle,
            mergeTargetType: mergeTargetType,
            thinkspaceId: thinkspaceId,
            thinkspaceName: thinkspaceName,
            clusterId: clusterId,
            clusterName: clusterName,
            placementPlan: adjustedPlan,
            atlasMove: atlasMove,
            filingDestination: filingDestination,
            filingAction: filingAction
        )
    }
}
