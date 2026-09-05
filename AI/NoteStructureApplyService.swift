// CosmoOS/AI/NoteStructureApplyService.swift
// Applies reviewed exact-copy note structure plans to thinkspace canvas state.

import Foundation
import GRDB
import SwiftUI

struct NoteStructureApplyResult: Equatable, Sendable {
    let operationsApplied: Int
    let clustersCreated: Int
    let notesCreated: Int
    let blocksCreated: Int
    let sourceKeptVisible: Bool
}

@MainActor
final class NoteStructureApplyService {
    static let shared = NoteStructureApplyService()

    private let atoms = AtomRepository.shared
    private let database = CosmoDatabase.shared
    private let iso = ISO8601DateFormatter()

    private init() {}

    @discardableResult
    func apply(_ plan: PendingNoteStructurePlan) async throws -> NoteStructureApplyResult {
        guard let source = try await atoms.fetch(uuid: plan.sourceNoteUUID.uuidString) else {
            throw NoteStructurePlanError.missingSourceNote
        }
        guard var thinkspace = try await atoms.fetch(uuid: plan.targetThinkspaceUUID.uuidString) else {
            throw NoteStructurePlanError.missingTargetThinkspace
        }

        let sourceBody = source.body ?? ""
        let snapshot = NoteStructureSourceSnapshot(
            sourceNoteUUID: plan.sourceNoteUUID,
            sourceTitle: source.title ?? plan.sourceTitle,
            body: sourceBody
        )
        try plan.validate(against: snapshot)

        var metadata = thinkspace.metadataValue(as: ThinkspaceMetadata.self)
            ?? ThinkspaceMetadata(name: thinkspace.title ?? "Thinkspace")
        let beforeClusterIDs = Set(metadata.clusters.map(\.id))

        for cluster in plan.clusters {
            upsertCluster(cluster, in: &metadata)
        }

        var notesCreated = 0
        var blocksCreated = 0

        for module in plan.modules {
            let exactText = try module.copiedText(in: sourceBody)
            let note = try await createModuleNote(module, body: exactText, source: source, plan: plan)
            let blockId = try await placeModuleNote(note, module: module, plan: plan)
            notesCreated += 1
            blocksCreated += 1

            if !metadata.blockIds.contains(blockId) {
                metadata.blockIds.append(blockId)
            }
            if let clusterIndex = metadata.clusters.firstIndex(where: { $0.id == module.clusterID.uuidString }),
               !metadata.clusters[clusterIndex].blockUUIDs.contains(note.uuid) {
                metadata.clusters[clusterIndex].blockUUIDs.append(note.uuid)
            }
        }

        thinkspace = thinkspace.withMetadata(metadata)
        _ = try await atoms.update(thinkspace)

        NotificationCenter.default.post(name: CosmoNotification.Canvas.blocksChanged, object: nil)
        NotificationCenter.default.post(name: CosmoNotification.Canvas.thinkspaceChanged, object: nil)
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.graphNodeUpdated, object: nil)

        let afterClusterIDs = Set(metadata.clusters.map(\.id))
        return NoteStructureApplyResult(
            operationsApplied: plan.affectedObjectCount,
            clustersCreated: afterClusterIDs.subtracting(beforeClusterIDs).count,
            notesCreated: notesCreated,
            blocksCreated: blocksCreated,
            sourceKeptVisible: plan.keepOriginalVisible
        )
    }

    private func upsertCluster(_ proposal: NoteStructureClusterProposal, in metadata: inout ThinkspaceMetadata) {
        if let index = metadata.clusters.firstIndex(where: { $0.id == proposal.id.uuidString }) {
            metadata.clusters[index].name = proposal.name
            metadata.clusters[index].colorIndex = proposal.colorIndex
            metadata.clusters[index].originX = proposal.frame.origin.x
            metadata.clusters[index].originY = proposal.frame.origin.y
            metadata.clusters[index].rectWidth = proposal.frame.width
            metadata.clusters[index].rectHeight = proposal.frame.height
            metadata.clusters[index].manualWidth = proposal.frame.width
            metadata.clusters[index].manualHeight = proposal.frame.height
            metadata.clusters[index].isZone = true
            metadata.clusters[index].viewMode = ClusterViewMode.canvas.rawValue
            return
        }

        metadata.clusters.append(
            CodableCluster(
                id: proposal.id.uuidString,
                name: proposal.name,
                blockUUIDs: [],
                colorIndex: proposal.colorIndex,
                originX: proposal.frame.origin.x,
                originY: proposal.frame.origin.y,
                rectWidth: proposal.frame.width,
                rectHeight: proposal.frame.height,
                manualWidth: proposal.frame.width,
                manualHeight: proposal.frame.height,
                isZone: true,
                intent: "Exact-copy structure cluster created from a long source note.",
                viewMode: ClusterViewMode.canvas.rawValue
            )
        )
    }

    private func createModuleNote(
        _ module: NoteStructureModuleProposal,
        body: String,
        source: Atom,
        plan: PendingNoteStructurePlan
    ) async throws -> Atom {
        let metadata = NoteStructureModuleMetadata(
            kind: "exact_note_structure_module",
            sourceNoteUUID: plan.sourceNoteUUID.uuidString,
            sourceBodyHash: plan.sourceBodyHash,
            sourceUTF16Offset: module.startUTF16Offset,
            sourceUTF16Length: module.lengthUTF16,
            targetThinkspaceUUID: plan.targetThinkspaceUUID.uuidString,
            createdAt: iso.string(from: Date())
        )
        var note = Atom.new(
            type: .note,
            title: module.title,
            body: body,
            metadata: try encode(metadata),
            links: [
                AtomLink(type: "source_note", uuid: source.uuid, entityType: source.type.rawValue),
                AtomLink(type: "primary_home_thinkspace", uuid: plan.targetThinkspaceUUID.uuidString, entityType: AtomType.thinkspace.rawValue)
            ]
        )
        note = try await atoms.create(note)
        return note
    }

    private func placeModuleNote(
        _ note: Atom,
        module: NoteStructureModuleProposal,
        plan: PendingNoteStructurePlan
    ) async throws -> String {
        let blockId = UUID().uuidString
        let base = CanvasBlock.fromAtom(note, position: module.position)
        let block = CanvasBlock(
            id: blockId,
            position: module.position,
            size: module.size,
            isPinned: base.isPinned,
            zIndex: 0,
            entityType: base.entityType,
            entityId: base.entityId,
            entityUuid: base.entityUuid,
            title: base.title,
            subtitle: base.subtitle,
            metadata: base.metadata.merging([
                "sourceNoteUUID": plan.sourceNoteUUID.uuidString,
                "noteStructurePlanID": plan.id.uuidString,
                "clusterID": module.clusterID.uuidString
            ]) { current, _ in current }
        )

        let record = CanvasBlockRecord.from(
            block,
            documentType: "home",
            documentId: 0,
            thinkspaceId: plan.targetThinkspaceUUID.uuidString,
            isPlaced: false
        )
        try await database.asyncWrite { db in
            try record.save(db)
        }
        return blockId
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

private struct NoteStructureModuleMetadata: Codable, Sendable {
    let kind: String
    let sourceNoteUUID: String
    let sourceBodyHash: String
    let sourceUTF16Offset: Int
    let sourceUTF16Length: Int
    let targetThinkspaceUUID: String
    let createdAt: String
}
