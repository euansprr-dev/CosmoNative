import Foundation
import SwiftUI
import GRDB

@MainActor
final class InboxActionExecutor {
    static let shared = InboxActionExecutor()

    private let atomRepo = AtomRepository.shared
    private let inboxRepo = InboxRepository.shared
    private let planner = SpatialPlacementPlanner.shared
    private let database = CosmoDatabase.shared
    private let flashModel = "google/gemini-3.1-flash-lite-preview"

    private init() {}

    @discardableResult
    func executePrimaryRecommendation(item: InboxItem) async throws -> Atom? {
        if let recommendation = item.primaryRecommendationValue {
            return try await executeRecommendation(item: item, recommendation: recommendation)
        }

        switch item.classification {
        case .merge:
            guard let targetUuid = item.mergeTargetUuid else { return nil }
            return try await executeMerge(item: item, targetAtomUuid: targetUuid)
        case .place:
            guard let thinkspaceId = item.placeThinkspaceId else { return try await executeNew(item: item) }
            let atomType = AtomType(rawValue: item.placeAtomType ?? AtomType.connection.rawValue) ?? .connection
            return try await executePlace(item: item, thinkspaceId: thinkspaceId, atomType: atomType)
        case .new, .unsorted, .none:
            return try await executeNew(item: item)
        }
    }

    @discardableResult
    func executeRecommendation(item: InboxItem, recommendation: InboxRecommendation) async throws -> Atom? {
        switch recommendation.kind {
        case .mergeAtom:
            guard let targetUuid = recommendation.mergeTargetUuid else { return nil }
            return try await executeMerge(item: item, targetAtomUuid: targetUuid)
        case .placeInExistingCluster, .createClusterAndPlace, .placeInThinkspace, .createThinkspaceAndPlace:
            return try await executePlacementRecommendation(item: item, recommendation: recommendation)
        case .createStandaloneAtom:
            let atomType = AtomType(rawValue: recommendation.suggestedAtomType) ?? .connection
            return try await executeNew(item: item, atomType: atomType)
        }
    }

    @discardableResult
    func executeMerge(item: InboxItem, targetAtomUuid: String) async throws -> Atom? {
        guard let targetAtom = try await atomRepo.fetch(uuid: targetAtomUuid) else {
            print("⚠️ [InboxAction] Merge target not found: \(targetAtomUuid)")
            return nil
        }

        let existingBody = targetAtom.body ?? ""
        let newText = item.rawText
        // Long targets never go through the LLM: blendMerge only sees the first
        // 3000 chars, so an LLM rewrite would silently amputate the tail.
        // The lossless append fallback preserves every byte.
        let mergedBody: String
        if existingBody.count > 3000 {
            mergedBody = fallbackMerge(existing: existingBody, newContext: newText)
        } else {
            mergedBody = await blendMerge(existing: existingBody, newContext: newText, title: targetAtom.title ?? "Note")
        }

        // Durable undo source: persist the pre-merge body on the inbox item
        // BEFORE mutating the target, so the original text survives app restarts.
        do {
            try await inboxRepo.updateMetadata(uuid: item.uuid, merging: [
                "premergeBody": existingBody,
                "premergeTargetUuid": targetAtomUuid
            ])
        } catch {
            print("⚠️ [InboxAction] Failed to persist pre-merge snapshot: \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxActionExecutor.executeMerge", detail: "pre-merge snapshot store failed for \(item.uuid): \(error.localizedDescription)")
        }

        let updated = try await atomRepo.update(uuid: targetAtomUuid) { atom in
            atom.body = mergedBody
        }

        if let updated {
            await adoptAttachments(from: item, into: updated.uuid)
            await reindex(atom: updated)
            try await inboxRepo.markActioned(uuid: item.uuid)

            let originalItem = item
            let targetUUID = updated.uuid
            let merged = updated.body ?? mergedBody
            let previousBody = existingBody

            CosmoUndoManager.shared.register(
                InlineUndoAction(actionDescription: "Merge Inbox Capture") { [weak self] in
                    guard let self else { return }
                    _ = try? await self.atomRepo.update(uuid: targetUUID) { atom in
                        atom.body = previousBody
                    }
                    if let restored = try? await self.atomRepo.fetch(uuid: targetUUID) {
                        await self.reindex(atom: restored)
                    }
                    try? await self.inboxRepo.restore(originalItem)
                } redo: { [weak self] in
                    guard let self else { return }
                    _ = try? await self.atomRepo.update(uuid: targetUUID) { atom in
                        atom.body = merged
                    }
                    if let restored = try? await self.atomRepo.fetch(uuid: targetUUID) {
                        await self.reindex(atom: restored)
                    }
                    try? await self.inboxRepo.markActioned(uuid: originalItem.uuid)
                }
            )
        }

        return updated
    }

    @discardableResult
    func executePlace(
        item: InboxItem,
        thinkspaceId: String,
        atomType: AtomType = .connection
    ) async throws -> Atom {
        let thinkspaceName = await resolveThinkspaceName(for: thinkspaceId) ?? "Thinkspace"
        let plan = await planner.planForThinkspacePlacement(
            title: item.title ?? fallbackTitle(for: item),
            atomType: atomType,
            thinkspaceId: thinkspaceId,
            thinkspaceName: thinkspaceName,
            relatedAtomUUIDs: []
        )

        let recommendation = InboxRecommendation(
            kind: .placeInThinkspace,
            confidence: 1.0,
            suggestedAtomType: atomType.rawValue,
            destinationPath: thinkspaceName,
            rationale: "Manual override: place directly on \(thinkspaceName).",
            thinkspaceId: thinkspaceId,
            thinkspaceName: thinkspaceName,
            placementPlan: plan
        )

        guard let atom = try await executePlacementRecommendation(item: item, recommendation: recommendation) else {
            throw NSError(domain: "InboxActionExecutor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to place inbox item"])
        }
        return atom
    }

    @discardableResult
    func executeNew(item: InboxItem, atomType: AtomType = .connection) async throws -> Atom {
        var atom = Atom.new(
            type: atomType,
            title: item.title ?? fallbackTitle(for: item),
            body: item.rawText
        )
        atom = applyingChecklist(to: atom, atomType: atomType, rawText: item.rawText)
        atom = atom.mergingMetadataKeys(captureProvenance(for: item))
        atom = try await atomRepo.create(atom)
        await adoptAttachments(from: item, into: atom.uuid)
        await reindex(atom: atom)
        try await inboxRepo.markActioned(uuid: item.uuid)

        let createdAtom = atom
        let originalItem = item

        CosmoUndoManager.shared.register(
            InlineUndoAction(actionDescription: "Create Inbox Atom") { [weak self] in
                guard let self else { return }
                try? await self.atomRepo.delete(uuid: createdAtom.uuid)
                try? await self.inboxRepo.restore(originalItem)
            } redo: { [weak self] in
                guard let self else { return }
                try? await self.restoreAtomSnapshot(createdAtom)
                await self.reindex(atom: createdAtom)
                try? await self.inboxRepo.markActioned(uuid: originalItem.uuid)
            }
        )

        return atom
    }

    /// Create a `.connection` atom from the capture and link it to the atoms
    /// it bridges. A capture that strongly matches several existing objects is
    /// a connection between them, not a duplicate of any one.
    @discardableResult
    func executeConnect(item: InboxItem, relatedAtomUUIDs: [String]) async throws -> Atom {
        var atom = Atom.new(
            type: .connection,
            title: item.title ?? fallbackTitle(for: item),
            body: item.rawText
        )

        for uuid in relatedAtomUUIDs {
            guard let related = try? await atomRepo.fetch(uuid: uuid), !related.isDeleted else { continue }
            atom = atom.appendingLink(AtomLink(
                type: AtomLinkType.related.rawValue,
                uuid: related.uuid,
                entityType: related.type.rawValue
            ))
        }

        atom = atom.mergingMetadataKeys(captureProvenance(for: item))
        atom = try await atomRepo.create(atom)
        await adoptAttachments(from: item, into: atom.uuid)
        await reindex(atom: atom)
        try await inboxRepo.markActioned(uuid: item.uuid)

        let createdAtom = atom
        let originalItem = item

        CosmoUndoManager.shared.register(
            InlineUndoAction(actionDescription: "Connect Inbox Capture") { [weak self] in
                guard let self else { return }
                try? await self.atomRepo.delete(uuid: createdAtom.uuid)
                try? await self.inboxRepo.restore(originalItem)
            } redo: { [weak self] in
                guard let self else { return }
                try? await self.restoreAtomSnapshot(createdAtom)
                await self.reindex(atom: createdAtom)
                try? await self.inboxRepo.markActioned(uuid: originalItem.uuid)
            }
        )

        return atom
    }

    private func executePlacementRecommendation(
        item: InboxItem,
        recommendation: InboxRecommendation
    ) async throws -> Atom? {
        let atomType = AtomType(rawValue: recommendation.suggestedAtomType) ?? .connection
        let originalItem = item

        var targetThinkspaceId = recommendation.thinkspaceId
        var mutatedThinkspaceBefore: Atom?
        var mutatedThinkspaceAfter: Atom?

        if recommendation.kind == .createThinkspaceAndPlace {
            let thinkspaceName = recommendation.placementPlan?.targetThinkspaceName
                ?? recommendation.thinkspaceName
                ?? recommendation.destinationPath
            guard let thinkspace = await ThinkspaceManager.shared.createThinkspace(name: thinkspaceName) else {
                return nil
            }
            targetThinkspaceId = thinkspace.id
        }

        var atom = Atom.new(
            type: atomType,
            title: item.title ?? fallbackTitle(for: item),
            body: item.rawText
        )
        atom = applyingChecklist(to: atom, atomType: atomType, rawText: item.rawText)
        atom = atom.mergingMetadataKeys(captureProvenance(for: item))
        atom = try await atomRepo.create(atom)
        await adoptAttachments(from: item, into: atom.uuid)
        await reindex(atom: atom)

        var createdBlockRecord: CanvasBlockRecord?

        if let thinkspaceId = targetThinkspaceId {
            if recommendation.kind == .placeInExistingCluster || recommendation.kind == .createClusterAndPlace || recommendation.kind == .createThinkspaceAndPlace,
               let placementPlan = recommendation.placementPlan {
                let snapshots = try await applyClusterMutation(
                    thinkspaceId: thinkspaceId,
                    recommendation: recommendation,
                    placementPlan: placementPlan,
                    atomUUID: atom.uuid
                )
                mutatedThinkspaceBefore = snapshots.before
                mutatedThinkspaceAfter = snapshots.after
            }

            if let placementPlan = recommendation.placementPlan,
               let x = placementPlan.blockPositionX,
               let y = placementPlan.blockPositionY {
                let block = CanvasBlock.fromAtom(atom, position: CGPoint(x: x, y: y))
                let record = CanvasBlockRecord.from(block, documentType: "home", documentId: 0, thinkspaceId: thinkspaceId)
                try await persistCanvasBlockSnapshot(record)
                createdBlockRecord = record
            }

            await refreshThinkspace(thinkspaceId)
        }

        try await inboxRepo.markActioned(uuid: item.uuid)

        let afterThinkspaceSnapshot = mutatedThinkspaceAfter
        let beforeThinkspaceSnapshot = mutatedThinkspaceBefore
        let createdAtom = atom
        let blockSnapshot = createdBlockRecord
        let affectedThinkspaceId = targetThinkspaceId

        CosmoUndoManager.shared.register(
            InlineUndoAction(actionDescription: "Apply Inbox Recommendation") { [weak self] in
                guard let self else { return }

                try? await self.atomRepo.delete(uuid: createdAtom.uuid)

                if let beforeThinkspaceSnapshot {
                    try? await self.persistAtomSnapshot(beforeThinkspaceSnapshot)
                } else if let afterThinkspaceSnapshot {
                    try? await self.atomRepo.delete(uuid: afterThinkspaceSnapshot.uuid)
                }

                if let affectedThinkspaceId {
                    await ThinkspaceManager.shared.loadThinkspaces()
                    await self.refreshThinkspace(affectedThinkspaceId)
                }

                try? await self.inboxRepo.restore(originalItem)
            } redo: { [weak self] in
                guard let self else { return }

                if let afterThinkspaceSnapshot {
                    try? await self.restoreAtomSnapshot(afterThinkspaceSnapshot)
                    await ThinkspaceManager.shared.loadThinkspaces()
                }

                try? await self.restoreAtomSnapshot(createdAtom)
                if let blockSnapshot {
                    try? await self.persistCanvasBlockSnapshot(blockSnapshot)
                }
                await self.reindex(atom: createdAtom)

                if let affectedThinkspaceId {
                    await self.refreshThinkspace(affectedThinkspaceId)
                }

                try? await self.inboxRepo.markActioned(uuid: originalItem.uuid)
            }
        )

        return atom
    }

    private func applyClusterMutation(
        thinkspaceId: String,
        recommendation: InboxRecommendation,
        placementPlan: InboxPlacementPlan,
        atomUUID: String
    ) async throws -> (before: Atom, after: Atom) {
        guard var thinkspaceAtom = try await atomRepo.fetch(uuid: thinkspaceId) else {
            throw NSError(domain: "InboxActionExecutor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Thinkspace not found"])
        }

        let before = thinkspaceAtom
        var metadata = thinkspaceAtom.metadataValue(as: ThinkspaceMetadata.self) ?? ThinkspaceMetadata(
            name: recommendation.thinkspaceName ?? thinkspaceAtom.title ?? "Thinkspace"
        )

        let clusterId = placementPlan.targetClusterId ?? recommendation.clusterId ?? UUID().uuidString
        let clusterName = placementPlan.targetClusterName ?? recommendation.clusterName ?? "Cluster"
        let rect = placementPlan.clusterRect

        if let index = metadata.clusters.firstIndex(where: { $0.id == clusterId }) {
            if !metadata.clusters[index].blockUUIDs.contains(atomUUID) {
                metadata.clusters[index].blockUUIDs.append(atomUUID)
            }
            metadata.clusters[index].name = clusterName
            metadata.clusters[index].intent = recommendation.rationale
            metadata.clusters[index].viewMode = placementPlan.clusterViewMode ?? metadata.clusters[index].viewMode
            if let rect {
                metadata.clusters[index].originX = rect.originX
                metadata.clusters[index].originY = rect.originY
                metadata.clusters[index].rectWidth = rect.width
                metadata.clusters[index].rectHeight = rect.height
                metadata.clusters[index].manualWidth = rect.width
                metadata.clusters[index].manualHeight = rect.height
            }
        } else {
            metadata.clusters.append(
                CodableCluster(
                    id: clusterId,
                    name: clusterName,
                    blockUUIDs: [atomUUID],
                    colorIndex: 0,
                    originX: rect?.originX,
                    originY: rect?.originY,
                    rectWidth: rect?.width,
                    rectHeight: rect?.height,
                    manualWidth: rect?.width,
                    manualHeight: rect?.height,
                    isZone: true,
                    zoneType: nil,
                    intent: recommendation.rationale,
                    viewMode: placementPlan.clusterViewMode ?? ClusterViewMode.canvas.rawValue,
                    sortOrder: ClusterSortOrder.dateUpdated.rawValue,
                    boardGrouping: ClusterBoardGrouping.auto.rawValue
                )
            )
        }

        if let json = try? JSONEncoder().encode(metadata),
           let string = String(data: json, encoding: .utf8) {
            thinkspaceAtom.metadata = string
        }
        thinkspaceAtom.title = metadata.name

        try await persistAtomSnapshot(thinkspaceAtom)
        return (before, thinkspaceAtom)
    }

    private func persistAtomSnapshot(_ atom: Atom) async throws {
        try await database.asyncWrite { db in
            var mutable = atom
            let existing = try Atom
                .filter(Column("uuid") == atom.uuid)
                .fetchOne(db)
            if existing != nil {
                try mutable.update(db)
            } else {
                try mutable.insert(db)
            }
        }
    }

    private func restoreAtomSnapshot(_ atom: Atom) async throws {
        try await persistAtomSnapshot(atom)
    }

    private func persistCanvasBlockSnapshot(_ record: CanvasBlockRecord) async throws {
        try await database.asyncWrite { db in
            var mutable = record
            let existing = try CanvasBlockRecord
                .filter(Column("id") == record.id)
                .fetchOne(db)
            if existing != nil {
                try mutable.update(db)
            } else {
                try mutable.insert(db)
            }
        }
    }

    private func refreshThinkspace(_ thinkspaceId: String) async {
        NotificationCenter.default.post(
            name: CosmoNotification.Canvas.refreshThinkspacePlacements,
            object: nil,
            userInfo: ["thinkspaceId": thinkspaceId]
        )
        // Placement changed cluster membership — routing centroids are stale.
        await InboxRoutingEngine.shared.invalidateCentroids()
    }

    private func resolveThinkspaceName(for thinkspaceId: String) async -> String? {
        if let thinkspace = ThinkspaceManager.shared.thinkspaces.first(where: { $0.id == thinkspaceId }) {
            return thinkspace.name
        }
        let fetchedAtom = try? await atomRepo.fetch(uuid: thinkspaceId)
        guard let atom = fetchedAtom ?? nil else {
            return nil
        }
        return atom.metadataValue(as: ThinkspaceMetadata.self)?.name
    }

    private func fallbackTitle(for item: InboxItem) -> String {
        item.title ?? String(item.rawText.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A checkbox-bearing capture routed as a TASK becomes a real one: prose
    /// names it, the checkboxes become its Things-style subtasks (checked
    /// state preserved from the page), the body keeps just the prose.
    private func applyingChecklist(to atom: Atom, atomType: AtomType, rawText: String) -> Atom {
        guard atomType == .task,
              let payload = CapturedChecklist.taskPayload(from: rawText) else { return atom }
        var copy = atom
        copy.title = payload.title
        copy.body = payload.notes.isEmpty ? nil : payload.notes
        if let checklistJSON = CapturedChecklist.checklistJSON(payload.checklist) {
            copy = copy.mergingMetadataKeys(["checklist": checklistJSON])
        }
        return copy
    }

    /// Provenance metadata stamped on every atom created from an inbox capture.
    /// The launch reconciler uses `sourceCaptureUuid` to safely auto-dismiss
    /// captures whose atoms already exist instead of guessing by text match.
    private func captureProvenance(for item: InboxItem) -> [String: String] {
        ["sourceCaptureUuid": item.uuid]
    }

    /// The originals follow the thought: page/photo attachments captured with
    /// the inbox item are re-homed on the atom it became, and listed in the
    /// atom's metadata so any surface can render them. Never fails the route —
    /// a failed adoption leaves attachments reachable via the inbox item.
    private func adoptAttachments(from item: InboxItem, into atomUUID: String) async {
        let uuids = item.attachmentUUIDs
        guard !uuids.isEmpty else { return }

        for uuid in uuids {
            _ = try? await MediaAttachmentRepository.shared.trackedMutation(uuid: uuid) { attachment in
                attachment.ownerType = MediaAttachmentOwner.atom.rawValue
                attachment.ownerUUID = atomUUID
                return true
            }
        }
        _ = try? await atomRepo.update(uuid: atomUUID) { atom in
            atom = atom.mergingMetadataKeys(["attachmentUUIDs": uuids])
        }
    }

    private func reindex(atom: Atom) async {
        let text = [atom.title, atom.body].compactMap { $0 }.joined(separator: "\n\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            try await VectorDatabase.shared.index(
                text: text,
                entityType: atom.type.rawValue,
                entityId: atom.id ?? 0,
                entityUUID: atom.uuid
            )
        } catch {
            print("⚠️ [InboxAction] Vector reindex failed for \(atom.uuid): \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxActionExecutor.reindex", detail: "vector index failed for \(atom.uuid): \(error.localizedDescription)")
        }
    }

    private func blendMerge(existing: String, newContext: String, title: String) async -> String {
        guard !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return newContext
        }

        do {
            let prompt = """
            You are merging new context into an existing note. Produce a single coherent document that integrates both.

            RULES:
            - Preserve all information from both texts
            - Do not add commentary or headings
            - Write naturally as if this were always one note
            - Keep contradictions if both perspectives matter
            - Return only the merged note

            EXISTING NOTE ("\(title)"):
            \(String(existing.prefix(3000)))

            NEW CONTEXT:
            \(String(newContext.prefix(2000)))
            """

            let result = try await ResearchService.shared.analyze(
                prompt: prompt,
                model: flashModel,
                maxTokens: 4000,
                temperature: 0.1
            )

            let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? fallbackMerge(existing: existing, newContext: newContext) : cleaned
        } catch {
            return fallbackMerge(existing: existing, newContext: newContext)
        }
    }

    private func fallbackMerge(existing: String, newContext: String) -> String {
        let datestamp = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
        return existing + "\n\n---\n\nAdded \(datestamp):\n\n" + newContext
    }
}
