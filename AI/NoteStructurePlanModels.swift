// CosmoOS/AI/NoteStructurePlanModels.swift
// Exact-copy planning models for splitting long notes into canvas clusters.

import CoreGraphics
import CryptoKit
import Foundation

struct NoteStructureSourceSnapshot: Equatable, Sendable {
    let sourceNoteUUID: UUID
    let sourceTitle: String
    let body: String
    let bodyHash: String

    init(sourceNoteUUID: UUID, sourceTitle: String, body: String) {
        self.sourceNoteUUID = sourceNoteUUID
        self.sourceTitle = sourceTitle
        self.body = body
        self.bodyHash = Self.hashBody(body)
    }

    static func hashBody(_ body: String) -> String {
        let digest = SHA256.hash(data: Data(body.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

struct PendingNoteStructurePlan: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let rationale: String
    let sourceNoteUUID: UUID
    let sourceTitle: String
    let sourceBodyHash: String
    let targetThinkspaceUUID: UUID
    let keepOriginalVisible: Bool
    let clusters: [NoteStructureClusterProposal]
    let modules: [NoteStructureModuleProposal]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        rationale: String,
        sourceNoteUUID: UUID,
        sourceTitle: String,
        sourceBodyHash: String,
        targetThinkspaceUUID: UUID,
        keepOriginalVisible: Bool = true,
        clusters: [NoteStructureClusterProposal],
        modules: [NoteStructureModuleProposal],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.rationale = rationale
        self.sourceNoteUUID = sourceNoteUUID
        self.sourceTitle = sourceTitle
        self.sourceBodyHash = sourceBodyHash
        self.targetThinkspaceUUID = targetThinkspaceUUID
        self.keepOriginalVisible = keepOriginalVisible
        self.clusters = clusters
        self.modules = modules
        self.createdAt = createdAt
    }

    var affectedObjectCount: Int {
        clusters.count + modules.count
    }

    func validate(against snapshot: NoteStructureSourceSnapshot) throws {
        guard sourceNoteUUID == snapshot.sourceNoteUUID else {
            throw NoteStructurePlanError.sourceHashMismatch(expected: sourceBodyHash, actual: snapshot.bodyHash)
        }
        guard sourceBodyHash == snapshot.bodyHash else {
            throw NoteStructurePlanError.sourceHashMismatch(expected: sourceBodyHash, actual: snapshot.bodyHash)
        }
        guard !clusters.isEmpty else {
            throw NoteStructurePlanError.emptyClusters
        }
        guard !modules.isEmpty else {
            throw NoteStructurePlanError.emptyModules
        }

        let clustersByID = Dictionary(uniqueKeysWithValues: clusters.map { ($0.id, $0) })
        let modulesByID = Dictionary(uniqueKeysWithValues: modules.map { ($0.id, $0) })

        for module in modules {
            guard clustersByID[module.clusterID] != nil else {
                throw NoteStructurePlanError.missingCluster(moduleID: module.id, clusterID: module.clusterID)
            }
            _ = try module.copiedText(in: snapshot.body)
        }

        for cluster in clusters {
            for moduleID in cluster.moduleIDs {
                guard modulesByID[moduleID] != nil else {
                    throw NoteStructurePlanError.missingModule(clusterID: cluster.id, moduleID: moduleID)
                }
            }
        }
    }
}

struct NoteStructureClusterProposal: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let colorIndex: Int
    let frame: CGRect
    let moduleIDs: [UUID]
}

struct NoteStructureModuleProposal: Identifiable, Equatable, Sendable {
    let id: UUID
    let clusterID: UUID
    let title: String
    let startUTF16Offset: Int
    let lengthUTF16: Int
    let position: CGPoint
    let size: CGSize

    func copiedText(in body: String) throws -> String {
        let nsBody = body as NSString
        let range = NSRange(location: startUTF16Offset, length: lengthUTF16)
        guard range.location >= 0,
              range.length > 0,
              NSMaxRange(range) <= nsBody.length else {
            throw NoteStructurePlanError.invalidRange(moduleID: id)
        }

        let text = nsBody.substring(with: range)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NoteStructurePlanError.emptyModuleText(moduleID: id)
        }
        return text
    }
}

enum NoteStructurePlanError: LocalizedError, Equatable, Sendable {
    case sourceHashMismatch(expected: String, actual: String)
    case invalidRange(moduleID: UUID)
    case emptyModuleText(moduleID: UUID)
    case missingCluster(moduleID: UUID, clusterID: UUID)
    case missingModule(clusterID: UUID, moduleID: UUID)
    case emptyClusters
    case emptyModules
    case missingSourceNote
    case missingTargetThinkspace

    var errorDescription: String? {
        switch self {
        case .sourceHashMismatch:
            return "The source note changed after this plan was created. Regenerate the plan before applying it."
        case .invalidRange:
            return "One module points to text outside the current source note."
        case .emptyModuleText:
            return "One module points to empty source text."
        case .missingCluster:
            return "One module points to a missing cluster."
        case .missingModule:
            return "One cluster points to a missing module."
        case .emptyClusters:
            return "The plan does not include any clusters."
        case .emptyModules:
            return "The plan does not include any modules."
        case .missingSourceNote:
            return "The source note could not be found."
        case .missingTargetThinkspace:
            return "The target thinkspace could not be found."
        }
    }
}
