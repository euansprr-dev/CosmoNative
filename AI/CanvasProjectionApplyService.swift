// CosmoOS/AI/CanvasProjectionApplyService.swift
// Applies reviewed inquiry crystallization projections into Thinkspace canvas state.

import Foundation
import GRDB
import SwiftUI

struct CanvasProjectionApplyResult: Sendable {
    var projection: CanvasProjection
    var operationsApplied: Int = 0
    var blocksCreated: Int = 0
    var clustersCreated: Int = 0
    var linksCreated: Int = 0
    var artifactsHidden: Int = 0
    var childThinkspacesCreated: Int = 0
    var blockedOperationIds: [String] = []
}

@MainActor
final class CanvasProjectionApplyService {
    static let shared = CanvasProjectionApplyService()

    private let atoms = AtomRepository.shared
    private let database = CosmoDatabase.shared
    private let iso = ISO8601DateFormatter()

    private init() {}

    @discardableResult
    func applyAcceptedOperations(in output: CrystallizationOutput, session: Atom, deepDive: Atom?) async throws -> CanvasProjectionApplyResult? {
        guard var projection = output.canvasProjection else { return nil }

        var result = CanvasProjectionApplyResult(projection: projection)
        var createdBlockIds = Set(projection.rollbackSnapshot.canvasBlockUUIDs)
        var affectedAtomUUIDs = Set(projection.rollbackSnapshot.atomUUIDs)
        var affectedClusterUUIDs = Set(projection.rollbackSnapshot.clusterUUIDs)

        for index in projection.operations.indices {
            var operation = projection.operations[index]
            guard operation.status == .accepted || operation.status == .edited else { continue }

            do {
                let applied = try await apply(operation, projection: projection, session: session, deepDive: deepDive)
                operation = applied.operation
                operation.status = .applied
                result.operationsApplied += 1
                result.blocksCreated += applied.createdBlockIds.count
                result.clustersCreated += applied.createdClusterIds.count
                result.linksCreated += applied.linksCreated
                result.artifactsHidden += applied.artifactsHidden
                result.childThinkspacesCreated += applied.childThinkspacesCreated
                createdBlockIds.formUnion(applied.createdBlockIds)
                affectedAtomUUIDs.formUnion(applied.affectedAtomUUIDs)
                affectedClusterUUIDs.formUnion(applied.createdClusterIds)
                operation.rollbackMetadata.affectedCanvasBlockUUIDs.append(contentsOf: applied.createdBlockIds)
                operation.rollbackMetadata.affectedAtomUUIDs.append(contentsOf: applied.affectedAtomUUIDs)
                operation.rollbackMetadata.affectedClusterUUIDs.append(contentsOf: applied.createdClusterIds)
            } catch {
                operation.status = .blocked
                operation.rollbackMetadata.snapshotSummary = error.localizedDescription
                result.blockedOperationIds.append(operation.id)
            }

            projection.operations[index] = operation
        }

        projection.status = result.blockedOperationIds.isEmpty ? .applied : .partiallyApplied
        projection.appliedAt = iso.string(from: Date())
        projection.appliedBy = "user"
        projection.rollbackSnapshot.canvasBlockUUIDs = Array(createdBlockIds)
        projection.rollbackSnapshot.atomUUIDs = Array(affectedAtomUUIDs)
        projection.rollbackSnapshot.clusterUUIDs = Array(affectedClusterUUIDs)
        projection.rollbackSnapshot.summary = "Applied \(result.operationsApplied) reviewed operations. Rollback hides only projection-created canvas appearances and removes projection-created clusters."
        projection.verificationReport.blockedOperationIds = result.blockedOperationIds

        result.projection = projection

        NotificationCenter.default.post(name: CosmoNotification.Canvas.blocksChanged, object: nil)
        NotificationCenter.default.post(name: CosmoNotification.Canvas.thinkspaceChanged, object: nil)
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.graphNodeUpdated, object: nil)

        return result
    }

    func rollback(_ projection: CanvasProjection) async throws -> CanvasProjection {
        try await database.asyncWrite { db in
            for blockId in projection.rollbackSnapshot.canvasBlockUUIDs {
                try db.execute(
                    sql: "UPDATE canvas_blocks SET is_deleted = 1, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                    arguments: [blockId]
                )
            }
        }

        try await removeProjectionClusters(projection)

        var copy = projection
        copy.status = .rolledBack
        for index in copy.operations.indices where copy.operations[index].status == .applied {
            copy.operations[index].status = .accepted
        }

        NotificationCenter.default.post(name: CosmoNotification.Canvas.blocksChanged, object: nil)
        NotificationCenter.default.post(name: CosmoNotification.Canvas.thinkspaceChanged, object: nil)
        return copy
    }

    private struct OperationApplyResult {
        var operation: CanvasOperation
        var createdBlockIds: [String] = []
        var createdClusterIds: [String] = []
        var affectedAtomUUIDs: [String] = []
        var linksCreated: Int = 0
        var artifactsHidden: Int = 0
        var childThinkspacesCreated: Int = 0
    }

    private func apply(_ operation: CanvasOperation, projection: CanvasProjection, session: Atom, deepDive: Atom?) async throws -> OperationApplyResult {
        var result = OperationApplyResult(operation: operation)

        switch operation.type {
        case .createCluster, .updateCluster:
            let clusterId = try await upsertCluster(for: operation, projection: projection)
            result.createdClusterIds.append(clusterId)

        case .createSourceCard:
            if let source = try await atoms.fetch(uuid: operation.targetObjectUUID ?? operation.sourceArtifactID) {
                let blockId = try await placeAtom(source, operation: operation, projection: projection)
                result.createdBlockIds.append(blockId)
                result.affectedAtomUUIDs.append(source.uuid)
                try await ensureAppearanceLinks(atomUUID: source.uuid, thinkspaceUUID: projection.thinkspaceUUID, sessionUUID: projection.sessionUUID, blockId: blockId)
            }

        case .createObject:
            let atom = try await objectAtom(for: operation, projection: projection, session: session, deepDive: deepDive)
            let blockId = try await placeAtom(atom, operation: operation, projection: projection)
            result.createdBlockIds.append(blockId)
            result.affectedAtomUUIDs.append(atom.uuid)

        case .createConceptCard, .promoteToConnection:
            let atom = try await createProjectionAtom(type: .connection, operation: operation, projection: projection, session: session)
            let blockId = try await placeAtom(atom, operation: operation, projection: projection)
            result.createdBlockIds.append(blockId)
            result.affectedAtomUUIDs.append(atom.uuid)

        case .createNoteCard, .createSticky, .createClaimCard:
            let atom = try await createProjectionAtom(type: .note, operation: operation, projection: projection, session: session)
            let blockId = try await placeAtom(atom, operation: operation, projection: projection)
            result.createdBlockIds.append(blockId)
            result.affectedAtomUUIDs.append(atom.uuid)

        case .appendToObject, .updateCurrentUnderstanding:
            let targetUUID = operation.targetObjectUUID ?? deepDive?.uuid
            if let targetUUID {
                try await append(operation: operation, toAtomUUID: targetUUID, session: session)
                result.affectedAtomUUIDs.append(targetUUID)
            }

        case .linkObjects:
            if try await linkOperation(operation, projection: projection) {
                result.linksCreated += 1
            }

        case .hideArtifact, .ignore:
            try await markArtifactInternal(operation.sourceArtifactID, projection: projection, reason: operation.rationale)
            result.artifactsHidden += 1

        case .placeObject:
            if let atomUUID = operation.targetObjectUUID ?? operation.duplicateCheckResult.matchedObjectUUID,
               let atom = try await atoms.fetch(uuid: atomUUID) {
                let blockId = try await placeAtom(atom, operation: operation, projection: projection)
                result.createdBlockIds.append(blockId)
                result.affectedAtomUUIDs.append(atom.uuid)
            }

        case .moveObject:
            if let blockId = operation.rollbackMetadata.affectedCanvasBlockUUIDs.first,
               let placement = operation.proposedPlacement {
                try await moveBlock(blockId, placement: placement)
                result.createdBlockIds.append(blockId)
            }

        case .promoteToDeepDiveProfile:
            if let deepDive {
                try await append(operation: operation, toAtomUUID: deepDive.uuid, session: session)
                result.affectedAtomUUIDs.append(deepDive.uuid)
            }

        case .promoteToChildThinkspace:
            let child = try await createChildThinkspace(operation: operation, projection: projection)
            let blockId = try await placeAtom(child, operation: operation, projection: projection)
            result.createdBlockIds.append(blockId)
            result.affectedAtomUUIDs.append(child.uuid)
            result.childThinkspacesCreated += 1

        }

        return result
    }

    private func objectAtom(for operation: CanvasOperation, projection: CanvasProjection, session: Atom, deepDive: Atom?) async throws -> Atom {
        if operation.appendCreateRecommendation == .append,
           let target = operation.targetObjectUUID ?? operation.duplicateCheckResult.matchedObjectUUID,
           let atom = try await atoms.fetch(uuid: target) {
            try await append(operation: operation, toAtomUUID: atom.uuid, session: session)
            return atom
        }

        if operation.proposedObjectType == AtomType.question.rawValue {
            return try await InquiryRepository.shared.createQuestion(
                title: operation.proposedTitle ?? "Untitled Question",
                parentDeepDiveUUID: deepDive?.uuid ?? projection.deepDiveProfileUUID,
                originSessionUUID: session.uuid,
                parentQuestionUUID: nil,
                originExtractUUID: operation.sourceArtifactID
            )
        }

        return try await createProjectionAtom(type: .note, operation: operation, projection: projection, session: session)
    }

    private func createProjectionAtom(type: AtomType, operation: CanvasOperation, projection: CanvasProjection, session: Atom) async throws -> Atom {
        let metadata = ProjectionAtomMetadata(
            kind: operation.proposedObjectType ?? operation.type.rawValue,
            projectionUUID: projection.id,
            operationUUID: operation.id,
            originSessionUUID: session.uuid,
            primaryHomeThinkspaceUUID: projection.thinkspaceUUID,
            sourceArtifactUUID: operation.sourceArtifactID,
            relationshipType: operation.relationshipType,
            confidence: operation.confidence,
            rationale: operation.rationale,
            visualMaturity: operation.visualMaturity.rawValue
        )
        let metadataString = try encode(metadata)
        var atom = Atom.new(
            type: type,
            title: operation.proposedTitle ?? operation.type.displayName,
            body: operation.proposedBody ?? operation.rationale,
            metadata: metadataString,
            links: [
                AtomLink(type: "primary_home_thinkspace", uuid: projection.thinkspaceUUID, entityType: AtomType.thinkspace.rawValue),
                AtomLink(type: "origin_session", uuid: session.uuid, entityType: AtomType.inquirySession.rawValue),
                AtomLink(type: "created_by_projection", uuid: projection.id, metadata: operation.id)
            ]
        )
        atom = try await atoms.create(atom)
        try await ensureAppearanceLinks(atomUUID: atom.uuid, thinkspaceUUID: projection.thinkspaceUUID, sessionUUID: session.uuid, blockId: nil)
        return atom
    }

    private func placeAtom(_ atom: Atom, operation: CanvasOperation, projection: CanvasProjection) async throws -> String {
        if let existing = try await existingCanvasBlockId(atomUUID: atom.uuid, thinkspaceUUID: projection.thinkspaceUUID) {
            try await appendBlockToCluster(blockEntityUUID: atom.uuid, clusterUUID: operation.targetClusterUUID, thinkspaceUUID: projection.thinkspaceUUID)
            return existing
        }

        let blockId = UUID().uuidString
        let placement = operation.proposedPlacement ?? CanvasPlacementProposal(x: 0, y: 0)
        var block = CanvasBlock.fromAtom(atom, position: CGPoint(x: placement.x, y: placement.y))
        block = CanvasBlock(
            id: blockId,
            position: CGPoint(x: placement.x, y: placement.y),
            size: CGSize(width: placement.width ?? block.size.width, height: placement.height ?? block.size.height),
            isPinned: block.isPinned,
            zIndex: 0,
            entityType: block.entityType,
            entityId: block.entityId,
            entityUuid: block.entityUuid,
            title: block.title,
            subtitle: block.subtitle,
            metadata: block.metadata.merging([
                "projectionUUID": projection.id,
                "operationUUID": operation.id,
                "visualMaturity": operation.visualMaturity.rawValue
            ]) { current, _ in current }
        )

        let record = CanvasBlockRecord.from(block, documentType: "home", documentId: 0, thinkspaceId: projection.thinkspaceUUID)
        try await database.asyncWrite { db in
            try record.save(db)
        }
        try await appendBlockToThinkspaceMetadata(blockId: blockId, thinkspaceUUID: projection.thinkspaceUUID)
        try await appendBlockToCluster(blockEntityUUID: atom.uuid, clusterUUID: operation.targetClusterUUID, thinkspaceUUID: projection.thinkspaceUUID)
        try await ensureAppearanceLinks(atomUUID: atom.uuid, thinkspaceUUID: projection.thinkspaceUUID, sessionUUID: projection.sessionUUID, blockId: blockId)
        return blockId
    }

    private func upsertCluster(for operation: CanvasOperation, projection: CanvasProjection) async throws -> String {
        let clusterId = operation.targetClusterUUID ?? operation.id
        guard var thinkspace = try await atoms.fetch(uuid: projection.thinkspaceUUID) else {
            throw CanvasProjectionApplyError.missingThinkspace
        }

        var metadata = thinkspace.metadataValue(as: ThinkspaceMetadata.self) ?? ThinkspaceMetadata(name: thinkspace.title ?? "Thinkspace")
        if let index = metadata.clusters.firstIndex(where: { $0.id == clusterId }) {
            if metadata.clusters[index].synthesis?.contains("operation \(operation.id)") != true {
                metadata.clusters[index].synthesis = appendText(
                    metadata.clusters[index].synthesis,
                    title: "Crystallization update",
                    body: operation.rationale,
                    sessionUUID: projection.sessionUUID,
                    sourceArtifactUUID: operation.sourceArtifactID,
                    operationId: operation.id
                )
                metadata.clusters[index].synthesisUpdatedAt = iso.string(from: Date())
            }
        } else {
            let placement = operation.proposedPlacement ?? CanvasPlacementProposal(x: 0, y: 0, width: 760, height: 520)
            metadata.clusters.append(CodableCluster(
                id: clusterId,
                name: operation.proposedTitle ?? "Crystallized Cluster",
                blockUUIDs: [],
                colorIndex: 0,
                synthesis: operation.rationale,
                synthesisUpdatedAt: iso.string(from: Date()),
                originX: placement.x,
                originY: placement.y,
                rectWidth: placement.width ?? 760,
                rectHeight: placement.height ?? 520,
                isZone: true,
                intent: "Created from inquiry crystallization proposal \(projection.id)",
                viewMode: ClusterViewMode.canvas.rawValue
            ))
        }

        thinkspace = thinkspace.withMetadata(metadata)
        _ = try await atoms.update(thinkspace)
        return clusterId
    }

    private func append(operation: CanvasOperation, toAtomUUID atomUUID: String, session: Atom) async throws {
        guard var atom = try await atoms.fetch(uuid: atomUUID) else {
            throw CanvasProjectionApplyError.missingTarget
        }
        // Deep Dives keep their body clean: updates land as structured,
        // idempotent narrative revisions instead of raw markdown appends.
        if atom.type == .deepDive {
            var structured = atom.deepDiveStructured ?? DeepDiveStructured()
            let recorded = structured.currentUnderstanding.recordNarrativeRevision(
                UnderstandingNarrativeRevision(
                    date: iso.string(from: Date()),
                    text: operation.proposedBody ?? operation.rationale,
                    sessionUUID: session.uuid,
                    originOperationId: operation.id,
                    kind: .canvasOp
                )
            )
            guard recorded else { return }
            atom = atom.withStructured(structured)
        } else {
            // Idempotency: each operation appends at most once.
            if atom.body?.contains("operation \(operation.id)") == true { return }
            atom.body = appendText(
                atom.body,
                title: operation.proposedTitle ?? operation.type.displayName,
                body: operation.proposedBody ?? operation.rationale,
                sessionUUID: session.uuid,
                sourceArtifactUUID: operation.sourceArtifactID,
                operationId: operation.id
            )
        }
        atom.updatedAt = iso.string(from: Date())
        _ = try await atoms.update(atom)
    }

    private func linkOperation(_ operation: CanvasOperation, projection: CanvasProjection) async throws -> Bool {
        let sourceUUID = operation.duplicateCheckResult.matchedObjectUUID ?? operation.sourceArtifactID
        guard let targetUUID = operation.targetObjectUUID,
              var source = try await atoms.fetch(uuid: sourceUUID),
              let target = try await atoms.fetch(uuid: targetUUID) else {
            return false
        }
        if source.linksList.contains(where: { $0.type == AtomLinkType.linksTo.rawValue && $0.uuid == targetUUID }) {
            return false
        }

        let metadata = try encode(ProjectionRelationshipMetadata(
            projectionUUID: projection.id,
            operationUUID: operation.id,
            relationshipType: operation.relationshipType ?? "related_to",
            confidence: operation.confidence,
            rationale: operation.rationale
        ))
        source = source.addingLink(.linksTo(targetUUID, entityType: target.type))
        var links = source.linksList
        if let idx = links.lastIndex(where: { $0.type == AtomLinkType.linksTo.rawValue && $0.uuid == targetUUID }) {
            links[idx] = AtomLink(type: AtomLinkType.linksTo.rawValue, uuid: targetUUID, entityType: target.type.rawValue, metadata: metadata)
        }
        source = source.withLinks(links)
        _ = try await atoms.update(source)
        return true
    }

    private func markArtifactInternal(_ atomUUID: String, projection: CanvasProjection, reason: String) async throws {
        guard var atom = try await atoms.fetch(uuid: atomUUID) else { return }
        if atom.body?.contains("operation \(projection.id)") == true { return }
        atom.body = appendText(
            atom.body,
            title: "Kept internal by crystallization",
            body: reason,
            sessionUUID: projection.sessionUUID,
            sourceArtifactUUID: atomUUID,
            operationId: projection.id
        )
        atom.updatedAt = iso.string(from: Date())
        _ = try await atoms.update(atom)
    }

    private func createChildThinkspace(operation: CanvasOperation, projection: CanvasProjection) async throws -> Atom {
        let title = operation.proposedTitle ?? "Child Thinkspace"
        let existing = try await atoms.search(query: title, types: [.thinkspace]).first { atom in
            atom.title?.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(title) == .orderedSame
                && atom.metadataValue(as: ThinkspaceMetadata.self)?.parentThinkspaceId == projection.thinkspaceUUID
        }
        if let existing { return existing }

        let metadata = ThinkspaceMetadata(
            name: title,
            parentThinkspaceId: projection.thinkspaceUUID,
            clusters: [],
            deepDiveProfileUUID: nil
        )
        var child = Atom.new(
            type: .thinkspace,
            title: title,
            body: "Created as a child Thinkspace candidate from inquiry crystallization.",
            metadata: try encode(metadata),
            links: [
                AtomLink(type: "created_by_projection", uuid: projection.id, metadata: operation.id),
                AtomLink(type: "parent_thinkspace", uuid: projection.thinkspaceUUID, entityType: AtomType.thinkspace.rawValue)
            ]
        )
        child = try await atoms.create(child)
        _ = try? await InquiryRepository.shared.resolveDeepDiveProfile(forThinkspace: child.uuid, title: title)
        return child
    }

    private func existingCanvasBlockId(atomUUID: String, thinkspaceUUID: String) async throws -> String? {
        try await database.asyncRead { db in
            try String.fetchOne(
                db,
                sql: """
                    SELECT id FROM canvas_blocks
                    WHERE entity_uuid = ? AND thinkspace_id = ? AND document_type = 'home' AND document_id = 0 AND is_deleted = 0
                    LIMIT 1
                """,
                arguments: [atomUUID, thinkspaceUUID]
            )
        }
    }

    private func appendBlockToThinkspaceMetadata(blockId: String, thinkspaceUUID: String) async throws {
        guard var thinkspace = try await atoms.fetch(uuid: thinkspaceUUID) else { return }
        var metadata = thinkspace.metadataValue(as: ThinkspaceMetadata.self) ?? ThinkspaceMetadata(name: thinkspace.title ?? "Thinkspace")
        if !metadata.blockIds.contains(blockId) {
            metadata.blockIds.append(blockId)
            thinkspace = thinkspace.withMetadata(metadata)
            _ = try await atoms.update(thinkspace)
        }
    }

    private func appendBlockToCluster(blockEntityUUID: String, clusterUUID: String?, thinkspaceUUID: String) async throws {
        guard let clusterUUID,
              var thinkspace = try await atoms.fetch(uuid: thinkspaceUUID) else { return }
        var metadata = thinkspace.metadataValue(as: ThinkspaceMetadata.self) ?? ThinkspaceMetadata(name: thinkspace.title ?? "Thinkspace")
        guard let index = metadata.clusters.firstIndex(where: { $0.id == clusterUUID }) else { return }
        if !metadata.clusters[index].blockUUIDs.contains(blockEntityUUID) {
            metadata.clusters[index].blockUUIDs.append(blockEntityUUID)
            thinkspace = thinkspace.withMetadata(metadata)
            _ = try await atoms.update(thinkspace)
        }
    }

    private func moveBlock(_ blockId: String, placement: CanvasPlacementProposal) async throws {
        try await database.asyncWrite { db in
            try db.execute(
                sql: "UPDATE canvas_blocks SET position_x = ?, position_y = ?, width = COALESCE(?, width), height = COALESCE(?, height), updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                arguments: [
                    Int(placement.x),
                    Int(placement.y),
                    placement.width.map { Int($0) },
                    placement.height.map { Int($0) },
                    blockId
                ]
            )
        }
    }

    private func ensureAppearanceLinks(atomUUID: String, thinkspaceUUID: String, sessionUUID: String, blockId: String?) async throws {
        guard var atom = try await atoms.fetch(uuid: atomUUID) else { return }
        let encodedAppearance = try encode(CanvasAppearanceLinkMetadata(
            thinkspaceUUID: thinkspaceUUID,
            canvasBlockUUID: blockId,
            originSessionUUID: sessionUUID,
            createdAt: iso.string(from: Date())
        ))
        var links = atom.linksList
        if !links.contains(where: { $0.type == "primary_home_thinkspace" }) {
            links.append(AtomLink(type: "primary_home_thinkspace", uuid: thinkspaceUUID, entityType: AtomType.thinkspace.rawValue))
        }
        if !links.contains(where: { $0.type == "appears_in_thinkspace" && $0.uuid == thinkspaceUUID && $0.metadata == encodedAppearance }) {
            links.append(AtomLink(type: "appears_in_thinkspace", uuid: thinkspaceUUID, entityType: AtomType.thinkspace.rawValue, metadata: encodedAppearance))
        }
        atom = atom.withLinks(links)
        atom.updatedAt = iso.string(from: Date())
        _ = try await atoms.update(atom)
    }

    private func removeProjectionClusters(_ projection: CanvasProjection) async throws {
        guard var thinkspace = try await atoms.fetch(uuid: projection.thinkspaceUUID) else { return }
        var metadata = thinkspace.metadataValue(as: ThinkspaceMetadata.self) ?? ThinkspaceMetadata(name: thinkspace.title ?? "Thinkspace")
        let ids = Set(projection.rollbackSnapshot.clusterUUIDs)
        metadata.clusters.removeAll { ids.contains($0.id) }
        thinkspace = thinkspace.withMetadata(metadata)
        _ = try await atoms.update(thinkspace)
    }

    private func appendText(_ existing: String?, title: String, body: String, sessionUUID: String, sourceArtifactUUID: String, operationId: String) -> String {
        let current = existing?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let section = """

        ## \(title)
        \(body)

        _Appended from Inquiry Session \(sessionUUID), source artifact \(sourceArtifactUUID), operation \(operationId), \(iso.string(from: Date()))._
        """
        return current.isEmpty ? section.trimmingCharacters(in: .whitespacesAndNewlines) : current + section
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

private enum CanvasProjectionApplyError: LocalizedError {
    case missingThinkspace
    case missingTarget

    var errorDescription: String? {
        switch self {
        case .missingThinkspace: return "The target Thinkspace no longer exists."
        case .missingTarget: return "The target object no longer exists."
        }
    }
}

private struct ProjectionAtomMetadata: Codable, Sendable {
    var kind: String
    var projectionUUID: String
    var operationUUID: String
    var originSessionUUID: String
    var primaryHomeThinkspaceUUID: String
    var sourceArtifactUUID: String
    var relationshipType: String?
    var confidence: Double
    var rationale: String
    var visualMaturity: String
}

private struct ProjectionRelationshipMetadata: Codable, Sendable {
    var projectionUUID: String
    var operationUUID: String
    var relationshipType: String
    var confidence: Double
    var rationale: String
}

private struct CanvasAppearanceLinkMetadata: Codable, Sendable {
    var thinkspaceUUID: String
    var canvasBlockUUID: String?
    var originSessionUUID: String
    var createdAt: String
}
