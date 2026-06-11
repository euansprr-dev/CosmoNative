// CosmoOS/AI/InboxClassificationEngine.swift
// Thin adapter between the staged routing engine and the InboxItem schema.
// Runs off the main actor — classification work never blocks the UI.
// June 2026 — Inbox Revamp (INBOX_REVAMP_PLAN.md §2)

import Foundation

final class InboxClassificationEngine: Sendable {
    static let shared = InboxClassificationEngine()

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
        let routingResult = await InboxRoutingEngine.shared.classify(
            text: text,
            source: source,
            excludedAtomUUIDs: excludedAtomUUIDs,
            preferredTitle: preferredTitle
        )

        let bundle = routingResult.bundle
        let primary = bundle.primaryRecommendation

        // The router abstains when nothing clears the confidence bars — that is
        // an honest `unsorted`, never a fake suggestion.
        let classification: InboxClassification = routingResult.abstained
            ? .unsorted
            : (primary?.kind.legacyClassification ?? .unsorted)
        let confidence = routingResult.abstained ? 0 : (primary?.confidence ?? 0)

        return ClassificationResult(
            classification: classification,
            confidence: confidence,
            title: routingResult.title,
            mergeTarget: routingResult.abstained ? nil : mergeTarget(from: primary),
            placeTarget: routingResult.abstained ? nil : placeTarget(from: primary),
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
