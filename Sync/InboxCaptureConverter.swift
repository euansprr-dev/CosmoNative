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
              let meta = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any] else { return }

        let isInboxCapture = meta["isInboxCapture"] as? Bool == true
        let isCaptureLaneCapture = meta["isCaptureLaneCapture"] as? Bool == true
        guard isInboxCapture || isCaptureLaneCapture else { return }

        let rawText = atomData["body"] as? String ?? atomData["title"] as? String ?? ""
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if isCaptureLaneCapture {
            await convertCaptureLaneCapture(
                sourceAtomUuid: uuid,
                destinationName: meta["captureDestinationName"] as? String,
                rawText: rawText,
                title: atomData["title"] as? String,
                metadata: meta
            )
            return
        }

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
                    arguments: [ISO8601.string(from: Date()), uuid]
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
                            arguments: [ISO8601.string(from: Date()), uuid]
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

    @MainActor
    private static func convertCaptureLaneCapture(
        sourceAtomUuid: String,
        destinationName: String?,
        rawText: String,
        title: String?,
        metadata: [String: Any]
    ) async {
        guard let destinationName else {
            await convertLaneCaptureToInbox(
                sourceAtomUuid: sourceAtomUuid,
                rawText: rawText,
                title: title,
                reason: "Unknown capture lane"
            )
            return
        }

        let shouldCreateLane = metadata["isCaptureLaneCreation"] as? Bool == true
        let destination: CaptureDestination?
        if shouldCreateLane {
            destination = try? await CaptureDestinationRepository.shared.createLane(named: destinationName)
        } else {
            destination = try? await CaptureDestinationRepository.shared.resolveCommand(destinationName)
        }

        guard let destination else {
            await convertLaneCaptureToInbox(
                sourceAtomUuid: sourceAtomUuid,
                rawText: rawText,
                title: title,
                reason: "Unknown capture lane"
            )
            return
        }

        let dedupeNeedle = "\"sourceAtomUuid\":\"\(sourceAtomUuid)\""
        let alreadyConverted = (try? await CosmoDatabase.shared.asyncRead { db in
            try Row.fetchOne(
                db,
                sql: "SELECT 1 FROM captured_items WHERE provenanceMetadata LIKE ? LIMIT 1",
                arguments: ["%\(dedupeNeedle)%"]
            )
        }) ?? nil
        if alreadyConverted != nil {
            await softDeleteTransportAtom(uuid: sourceAtomUuid)
            return
        }

        let provenance = [
            "sourceAtomUuid": sourceAtomUuid,
            "captureSource": "telegram_cloud",
            "captureDestinationName": destinationName,
            "telegramChatId": metadata["telegramChatId"] as? String ?? "",
            "telegramMessageId": metadata["telegramMessageId"] as? String ?? "",
            "telegramMediaGroupId": metadata["telegramMediaGroupId"] as? String ?? ""
        ]
        let provenanceJSON = try? String(
            data: JSONSerialization.data(withJSONObject: provenance),
            encoding: .utf8
        )

        do {
            let captured = try await CapturedItemRepository.shared.create(
                .makeTelegram(
                    rawText: rawText,
                    caption: nil,
                    chatId: metadata["telegramChatId"] as? String ?? "telegram_cloud",
                    messageId: metadata["telegramMessageId"] as? String ?? sourceAtomUuid,
                    mediaGroupId: metadata["telegramMediaGroupId"] as? String,
                    sender: metadata["telegramSender"] as? String,
                    metadata: provenanceJSON
                )
            )
            let mediaIds = try await createTelegramMediaAttachments(
                capturedItemId: captured.uuid,
                metadata: metadata
            )
            if !mediaIds.isEmpty {
                try await CapturedItemRepository.shared.attachMedia(
                    capturedItemId: captured.uuid,
                    mediaIds: mediaIds
                )
            }
            try await CapturedItemRepository.shared.updateRouting(
                uuid: captured.uuid,
                destinationId: destination.uuid,
                parsedCommand: destinationName,
                parsedIntent: "cloud_capture_lane",
                confidence: 1.0,
                status: .routed
            )
            await CaptureDestinationRepository.shared.markUsed(uuid: destination.uuid)
            await softDeleteTransportAtom(uuid: sourceAtomUuid)
            NotificationCenter.default.post(
                name: CosmoNotification.Inbox.itemAdded,
                object: nil,
                userInfo: ["captureDestinationId": destination.uuid]
            )
            print("📥 InboxCaptureConverter: routed cloud capture \(sourceAtomUuid) to lane \(destination.name)")
        } catch {
            print("⚠️ InboxCaptureConverter: Failed to route cloud lane capture: \(error)")
            await convertLaneCaptureToInbox(
                sourceAtomUuid: sourceAtomUuid,
                rawText: rawText,
                title: title,
                reason: "Lane routing failed"
            )
        }
    }

    @MainActor
    private static func convertLaneCaptureToInbox(sourceAtomUuid: String, rawText: String, title: String?, reason: String) async {
        let inboxMetadata = "{\"sourceAtomUuid\":\"\(sourceAtomUuid)\",\"reason\":\"\(reason)\"}"
        let item = InboxItem.new(
            source: .telegramText,
            rawText: rawText,
            title: title,
            metadata: inboxMetadata
        )

        do {
            _ = try await InboxRepository.shared.create(item)
            await softDeleteTransportAtom(uuid: sourceAtomUuid)
            NotificationCenter.default.post(name: CosmoNotification.Inbox.itemAdded, object: nil)
            print("📥 InboxCaptureConverter: fallback inbox item created for cloud lane capture \(sourceAtomUuid)")
        } catch {
            print("⚠️ InboxCaptureConverter: Failed fallback inbox capture: \(error)")
        }
    }

    @MainActor
    private static func createTelegramMediaAttachments(
        capturedItemId: String,
        metadata: [String: Any]
    ) async throws -> [String] {
        guard let media = metadata["telegramMedia"] as? [[String: Any]], !media.isEmpty else {
            return []
        }

        var ids: [String] = []
        for item in media {
            guard let fileId = item["fileId"] as? String else { continue }

            let kind = (item["kind"] as? String).flatMap(MediaAttachmentKind.init(rawValue:)) ?? .unknown
            let attachmentMetadata = try? String(
                data: JSONSerialization.data(withJSONObject: item),
                encoding: .utf8
            )
            let attachment = MediaAttachment.makeTelegram(
                capturedItemId: capturedItemId,
                kind: kind,
                fileId: fileId,
                fileUniqueId: item["fileUniqueId"] as? String,
                filename: item["filename"] as? String,
                mimeType: item["mimeType"] as? String,
                fileSize: int64Value(item["fileSize"]),
                metadata: attachmentMetadata
            )
            let saved = try await MediaAttachmentRepository.shared.create(attachment)
            ids.append(saved.uuid)
        }
        return ids
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Double { return Int64(value) }
        if let value = value as? String { return Int64(value) }
        return nil
    }

    private static func softDeleteTransportAtom(uuid: String) async {
        try? await CosmoDatabase.shared.asyncWrite { db in
            try db.execute(
                sql: "UPDATE atoms SET is_deleted = 1, updated_at = ? WHERE uuid = ?",
                arguments: [ISO8601.string(from: Date()), uuid]
            )
        }
    }
}
