// CosmoOS/Canvas/ThinkspaceEditableSurface.swift
// The thinkspace itself as an inline-assistant surface — the assistant's
// "eyes" on the canvas. The snapshot is a structured digest (blocks, clusters,
// intents, tallies) that rides the volatile prompt layer, so organize-style
// requests see the whole canvas with ZERO tool round-trips.
//
// This surface never applies edits: canvas mutations go exclusively through
// the reviewed canvas-plan card (propose_canvas_plan → approve), the same
// trust contract text edits have.

import Foundation

@MainActor
final class ThinkspaceEditableSurface: CosmoEditableSurfaceProvider {
    private weak var spatialEngine: SpatialEngine?
    private weak var clusterEngine: CanvasClusterEngine?
    private let thinkspaceId: String

    init(thinkspaceId: String, spatialEngine: SpatialEngine, clusterEngine: CanvasClusterEngine) {
        self.thinkspaceId = thinkspaceId
        self.spatialEngine = spatialEngine
        self.clusterEngine = clusterEngine
    }

    var surfaceID: String { Self.surfaceID(forThinkspaceId: thinkspaceId) }

    static func surfaceID(forThinkspaceId id: String) -> String {
        "thinkspace:\(id)"
    }

    static func targetID(forThinkspaceId id: String) -> String {
        "thinkspace:\(id):canvas"
    }

    private var thinkspaceName: String {
        ThinkspaceManager.shared.thinkspaces.first(where: { $0.id == thinkspaceId })?.name
            ?? ThinkspaceManager.shared.currentThinkspace.flatMap { $0.id == thinkspaceId ? $0.name : nil }
            ?? "Thinkspace"
    }

    func editableSnapshot() -> CosmoEditableSourceSnapshot {
        let blocks = spatialEngine?.blocks ?? []
        let clusters = (clusterEngine?.userClusters ?? []).filter {
            $0.thinkspaceId == nil || $0.thinkspaceId == thinkspaceId
        }
        let digest = Self.digest(
            thinkspaceName: thinkspaceName,
            blocks: blocks,
            clusters: clusters
        )
        return CosmoEditableSourceSnapshot(
            surfaceID: surfaceID,
            targetID: Self.targetID(forThinkspaceId: thinkspaceId),
            kind: .canvas,
            title: thinkspaceName,
            text: digest,
            sourceHash: CosmoEditableSurfaceHasher.hash(digest),
            anchors: [
                .init(id: "canvas", label: "Canvas", utf16Start: 0, utf16Length: digest.utf16.count)
            ]
        )
    }

    func apply(operation: CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(
            operationID: operation.id,
            status: .conflicted,
            message: "Canvas changes go through a reviewed canvas plan — ask Cosmo to organize and approve the plan card."
        )
    }

    func reject(operation: CosmoAssistantProposalOperation) async -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(operationID: operation.id, status: .rejected, message: "Rejected")
    }

    // MARK: - Digest

    /// The structured canvas digest the model reads. Pure and testable.
    /// Cluster membership matches `CanvasCluster.blockUUIDs` semantics
    /// (atom entityUuids, see updateBoundingRect).
    static func digest(
        thinkspaceName: String,
        blocks: [CanvasBlock],
        clusters: [CanvasCluster],
        blockCap: Int = 150
    ) -> String {
        var sections: [String] = []

        var clusterNameByAtomUUID: [String: String] = [:]
        for cluster in clusters {
            for uuid in cluster.blockUUIDs {
                clusterNameByAtomUUID[uuid] = cluster.name
            }
        }

        var typeCounts: [String: Int] = [:]
        for block in blocks {
            typeCounts[block.entityType.rawValue, default: 0] += 1
        }
        let tallies = typeCounts
            .sorted { $0.value > $1.value }
            .map { "\($0.value) \($0.key)" }
            .joined(separator: ", ")
        sections.append("""
        Thinkspace canvas: \(thinkspaceName)
        \(blocks.count) blocks (\(tallies.isEmpty ? "empty" : tallies)), \(clusters.count) clusters
        """)

        if !clusters.isEmpty {
            let clusterLines = clusters.map { cluster -> String in
                let memberTitles = blocks
                    .filter { cluster.blockUUIDs.contains($0.entityUuid) }
                    .prefix(8)
                    .map(\.title)
                    .filter { !$0.isEmpty }
                var line = "- \(cluster.name) (\(cluster.blockUUIDs.count) blocks"
                if let intent = cluster.intent, !intent.isEmpty {
                    line += ", intent: \(intent)"
                }
                line += ")"
                if !memberTitles.isEmpty {
                    line += ": \(memberTitles.joined(separator: " | "))"
                }
                return line
            }
            sections.append("Clusters:\n" + clusterLines.joined(separator: "\n"))
        }

        if !blocks.isEmpty {
            let blockLines = blocks.prefix(blockCap).map { block -> String in
                let title = block.title.isEmpty ? "Untitled" : block.title
                let cluster = clusterNameByAtomUUID[block.entityUuid] ?? "unclustered"
                return "- \(title) (\(block.entityType.rawValue), uuid: \(block.entityUuid), cluster: \(cluster))"
            }
            var body = "Blocks:\n" + blockLines.joined(separator: "\n")
            if blocks.count > blockCap {
                body += "\n(+\(blocks.count - blockCap) more blocks not listed)"
            }
            sections.append(body)
        }

        return sections.joined(separator: "\n\n")
    }
}
