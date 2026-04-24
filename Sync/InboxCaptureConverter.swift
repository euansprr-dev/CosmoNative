// CosmoOS/Sync/InboxCaptureConverter.swift
// Shared conversion: cloud transport atom (metadata.isInboxCapture=true) -> local InboxItem.
// Used by both RealtimeSyncService (live INSERTs) and SyncEngine (batch pull catch-up
// for captures that arrived while the Mac was offline).

import Foundation
import GRDB

enum InboxCaptureConverter {
    /// If `atomData` represents a cloud inbox capture, create a local InboxItem,
    /// classify it, and soft-delete the transport atom. No-op otherwise.
    ///
    /// Safe to call from both the Realtime INSERT path and the batch pull loop —
    /// self-guards on `metadata.isInboxCapture`, skips already-soft-deleted rows,
    /// and deduplicates via `sourceAtomUuid`.
    static func convertIfInboxCapture(uuid: String, atomData: [String: Any]) async {
        // Skip rows already soft-deleted (Realtime may have processed them first).
        if let deletedInt = atomData["is_deleted"] as? Int, deletedInt == 1 { return }
        if let deletedBool = atomData["is_deleted"] as? Bool, deletedBool { return }

        // Parse metadata — may arrive as a JSON string (GRDB TEXT) or a dict (JSONB).
        let metadataStr: String?
        if let str = atomData["metadata"] as? String {
            metadataStr = str
        } else if let obj = atomData["metadata"], !(obj is NSNull),
                  let jsonData = try? JSONSerialization.data(withJSONObject: obj),
                  let str = String(data: jsonData, encoding: .utf8) {
            metadataStr = str
        } else {
            metadataStr = nil
        }

        guard let metaStr = metadataStr,
              let metaData = metaStr.data(using: .utf8),
              let meta = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any],
              meta["isInboxCapture"] as? Bool == true else { return }

        let rawText = atomData["body"] as? String ?? atomData["title"] as? String ?? ""
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let title = atomData["title"] as? String

        // Dedupe: we tag the InboxItem's metadata JSON with the source atom uuid.
        // If one already exists for this atom, don't create a second InboxItem.
        let dedupeNeedle = "\"sourceAtomUuid\":\"\(uuid)\""
        let alreadyConverted = (try? await CosmoDatabase.shared.asyncRead { db in
            try Row.fetchOne(
                db,
                sql: "SELECT 1 FROM inbox_items WHERE metadata LIKE ? LIMIT 1",
                arguments: ["%\(dedupeNeedle)%"]
            )
        }) ?? nil
        if alreadyConverted != nil {
            // Make sure the transport atom is soft-deleted so future pulls skip it.
            try? await CosmoDatabase.shared.asyncWrite { db in
                try db.execute(
                    sql: "UPDATE atoms SET is_deleted = 1, updated_at = ? WHERE uuid = ?",
                    arguments: [ISO8601DateFormatter().string(from: Date()), uuid]
                )
            }
            return
        }

        print("📥 InboxCaptureConverter: converting cloud inbox capture \(uuid)")

        await MainActor.run { () -> Void in
            Task {
                let inboxMetadata = "{\"sourceAtomUuid\":\"\(uuid)\"}"
                let item = InboxItem.new(
                    source: .telegramText,
                    rawText: rawText,
                    title: title,
                    metadata: inboxMetadata
                )

                do {
                    let saved = try await InboxRepository.shared.create(item)

                    try? await CosmoDatabase.shared.asyncWrite { db in
                        try db.execute(
                            sql: "UPDATE atoms SET is_deleted = 1, updated_at = ? WHERE uuid = ?",
                            arguments: [ISO8601DateFormatter().string(from: Date()), uuid]
                        )
                    }

                    let classification = await InboxClassificationEngine.shared.classify(
                        text: rawText,
                        source: .telegramText,
                        excludedAtomUUIDs: [uuid],
                        preferredTitle: title
                    )

                    try await InboxRepository.shared.updateClassification(
                        uuid: saved.uuid,
                        classification: classification.classification,
                        confidence: classification.confidence,
                        title: classification.title,
                        mergeTargetUuid: classification.mergeTarget?.atomUuid,
                        mergeTargetTitle: classification.mergeTarget?.atomTitle,
                        mergeTargetType: classification.mergeTarget?.atomType,
                        mergePreview: classification.mergeTarget?.preview,
                        placeThinkspaceId: classification.placeTarget?.thinkspaceId,
                        placeThinkspaceName: classification.placeTarget?.thinkspaceName,
                        placeAtomType: classification.placeTarget?.suggestedAtomType,
                        recommendations: classification.recommendationBundle.encodedJSONString,
                        primaryRouteKind: classification.recommendationBundle.primaryRecommendation?.kind.rawValue,
                        destinationPath: classification.recommendationBundle.primaryRecommendation?.destinationPath,
                        rationale: classification.recommendationBundle.primaryRecommendation?.rationale,
                        placementPlanSummary: classification.recommendationBundle.primaryRecommendation?.placementPlan?.summary
                    )

                    print("📥 InboxCaptureConverter: InboxItem created from cloud capture — \(saved.uuid)")
                } catch {
                    print("⚠️ InboxCaptureConverter: Failed to create InboxItem from cloud capture: \(error)")
                }
            }
        }
    }
}
