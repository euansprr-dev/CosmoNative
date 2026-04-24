import Foundation

@MainActor
final class InboxClassificationEngine {
    static let shared = InboxClassificationEngine()

    private let routingEngine = InboxRoutingEngine.shared

    private init() {}

    struct ClassificationResult: Sendable {
        let classification: InboxClassification
        let confidence: Double
        let title: String
        let mergeTarget: MergeTarget?
        let placeTarget: PlaceTarget?
        let alternatives: [Alternative]
        let recommendationBundle: InboxRecommendationBundle
    }

    struct MergeTarget: Sendable {
        let atomUuid: String
        let atomTitle: String
        let atomType: String
        let similarity: Double
        let preview: String
    }

    struct PlaceTarget: Sendable {
        let thinkspaceId: String?
        let thinkspaceName: String?
        let clusterId: String?
        let clusterName: String?
        let suggestedAtomType: String
    }

    struct Alternative: Sendable {
        let classification: InboxClassification
        let label: String
        let confidence: Double
        let mergeTarget: MergeTarget?
        let placeTarget: PlaceTarget?
    }

    func classify(
        text: String,
        source: InboxSource,
        excludedAtomUUIDs: [String] = [],
        preferredTitle: String? = nil
    ) async -> ClassificationResult {
        let routingResult = await routingEngine.classify(
            text: text,
            source: source,
            excludedAtomUUIDs: excludedAtomUUIDs,
            preferredTitle: preferredTitle
        )

        let bundle = routingResult.bundle
        let primary = bundle.primaryRecommendation
        let classification = primary?.kind.legacyClassification ?? .new
        let confidence = primary?.confidence ?? 0.5

        return ClassificationResult(
            classification: classification,
            confidence: confidence,
            title: routingResult.title,
            mergeTarget: mergeTarget(from: primary),
            placeTarget: placeTarget(from: primary),
            alternatives: bundle.alternativeRecommendations.map(makeAlternative),
            recommendationBundle: bundle
        )
    }

    private func mergeTarget(from recommendation: InboxRecommendation?) -> MergeTarget? {
        guard let recommendation,
              recommendation.kind == .mergeAtom,
              let atomUuid = recommendation.mergeTargetUuid,
              let atomTitle = recommendation.mergeTargetTitle else {
            return nil
        }

        return MergeTarget(
            atomUuid: atomUuid,
            atomTitle: atomTitle,
            atomType: recommendation.mergeTargetType ?? recommendation.suggestedAtomType,
            similarity: recommendation.confidence,
            preview: recommendation.rationale
        )
    }

    private func placeTarget(from recommendation: InboxRecommendation?) -> PlaceTarget? {
        guard let recommendation,
              recommendation.kind != .mergeAtom,
              recommendation.kind != .createStandaloneAtom else {
            return nil
        }

        return PlaceTarget(
            thinkspaceId: recommendation.thinkspaceId,
            thinkspaceName: recommendation.thinkspaceName,
            clusterId: recommendation.clusterId,
            clusterName: recommendation.clusterName,
            suggestedAtomType: recommendation.suggestedAtomType
        )
    }

    private func makeAlternative(from recommendation: InboxRecommendation) -> Alternative {
        Alternative(
            classification: recommendation.kind.legacyClassification,
            label: recommendation.destinationPath,
            confidence: recommendation.confidence,
            mergeTarget: mergeTarget(from: recommendation),
            placeTarget: placeTarget(from: recommendation)
        )
    }
}
