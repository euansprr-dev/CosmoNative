// CosmoOS/Automation/AutomationContext.swift
// Context object passed through the automation evaluation pipeline

import Foundation

/// All context needed to evaluate conditions and execute actions for an automation event
struct AutomationContext: Sendable {
    let event: AutomationEvent
    let atom: AutomationAtomSnapshot       // Snapshot of the triggering atom
    let thinkspaceId: String?              // Current thinkspace
    let clusterMembership: [String]        // Cluster IDs the atom's block belongs to
    let clusterNames: [String: String]     // Cluster ID → name mapping
    let linkedAtomUUIDs: [String]          // Direct neighbor UUIDs from atom.links
    let linkedAtomTypes: [String]          // Types of linked atoms
    let executionDepth: Int                // Cascade depth (max 5)
    let isFromSync: Bool                   // True if triggered by cloud sync catch-up

    /// Lightweight atom snapshot for Sendable context
    struct AutomationAtomSnapshot: Sendable {
        let uuid: String
        let type: String
        let title: String
        let body: String
        let status: String?                // Decoded from metadata (ideaStatus, contentPhase, taskStatus)
        let clientUUID: String?
        let platform: String?
        let contentFormat: String?
        let tags: [String]
        let captureSource: String?
        let linkTypes: [String]            // Types of outgoing links
        let linkCount: Int
        let createdAt: String
        let updatedAt: String
        let bodyLength: Int
    }
}

// MARK: - Context Builder

@MainActor
enum AutomationContextBuilder {

    /// Build context from an atom and event, querying spatial state from the canvas engines
    static func build(
        event: AutomationEvent,
        atom: Atom,
        thinkspaceId: String?,
        clusterMembership: [String] = [],
        clusterNames: [String: String] = [:],
        executionDepth: Int = 0
    ) -> AutomationContext {
        // Extract status from metadata
        let status = extractStatus(from: atom)

        // Extract client UUID
        let clientUUID = extractMetadataField(from: atom, key: "clientUUID")
            ?? extractMetadataField(from: atom, key: "client_uuid")

        // Extract capture source
        let captureSource = extractMetadataField(from: atom, key: "captureSource")
            ?? extractMetadataField(from: atom, key: "capture_source")

        // Extract platform
        let platform = extractMetadataField(from: atom, key: "platform")

        // Extract content format
        let contentFormat = extractMetadataField(from: atom, key: "contentFormat")
            ?? extractMetadataField(from: atom, key: "content_format")

        // Extract tags
        let tags = extractTags(from: atom)

        // Extract links
        let links = atom.linksList
        let linkedUUIDs = links.map { $0.uuid }
        let linkedTypes = links.compactMap { $0.entityType }
        let linkTypes = links.map { $0.type }

        let snapshot = AutomationContext.AutomationAtomSnapshot(
            uuid: atom.uuid,
            type: atom.type.rawValue,
            title: atom.title ?? "",
            body: atom.body ?? "",
            status: status,
            clientUUID: clientUUID,
            platform: platform,
            contentFormat: contentFormat,
            tags: tags,
            captureSource: captureSource,
            linkTypes: linkTypes,
            linkCount: links.count,
            createdAt: atom.createdAt,
            updatedAt: atom.updatedAt,
            bodyLength: (atom.body ?? "").count
        )

        return AutomationContext(
            event: event,
            atom: snapshot,
            thinkspaceId: thinkspaceId,
            clusterMembership: clusterMembership,
            clusterNames: clusterNames,
            linkedAtomUUIDs: linkedUUIDs,
            linkedAtomTypes: linkedTypes,
            executionDepth: executionDepth,
            isFromSync: event.isFromSync
        )
    }

    // MARK: - Metadata Helpers

    private static func extractStatus(from atom: Atom) -> String? {
        // Try each known status field in order of specificity
        if let meta = atom.ideaMetadata, let status = meta.ideaStatus {
            return status.rawValue
        }

        // Try content phase from metadata JSON
        if let phase = extractMetadataField(from: atom, key: "contentPhase")
            ?? extractMetadataField(from: atom, key: "content_phase") {
            return phase
        }

        // Try task status
        if let status = extractMetadataField(from: atom, key: "status") {
            return status
        }

        return nil
    }

    private static func extractMetadataField(from atom: Atom, key: String) -> String? {
        guard let metadataJSON = atom.metadata,
              let data = metadataJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict[key] as? String
    }

    private static func extractTags(from atom: Atom) -> [String] {
        guard let metadataJSON = atom.metadata,
              let data = metadataJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        if let tags = dict["tags"] as? String {
            return tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        if let tags = dict["tags"] as? [String] {
            return tags
        }
        return []
    }
}
