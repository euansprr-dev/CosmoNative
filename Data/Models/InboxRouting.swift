import Foundation

enum InboxRouteKind: String, Codable, CaseIterable, Sendable {
    case mergeAtom
    case placeInExistingCluster
    case createClusterAndPlace
    case placeInThinkspace
    case createThinkspaceAndPlace
    case createStandaloneAtom

    var legacyClassification: InboxClassification {
        switch self {
        case .mergeAtom:
            return .merge
        case .placeInExistingCluster, .createClusterAndPlace, .placeInThinkspace, .createThinkspaceAndPlace:
            return .place
        case .createStandaloneAtom:
            return .new
        }
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
        placementPlan: InboxPlacementPlan? = nil
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
    }
}

struct InboxRecommendationBundle: Codable, Equatable, Sendable {
    let bundleId: String
    let title: String
    let createdAt: String
    let recommendations: [InboxRecommendation]

    init(
        bundleId: String = UUID().uuidString,
        title: String,
        createdAt: String = ISO8601.string(from: Date()),
        recommendations: [InboxRecommendation]
    ) {
        self.bundleId = bundleId
        self.title = title
        self.createdAt = createdAt
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
}
