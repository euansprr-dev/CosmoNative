import CoreGraphics
import Foundation

enum CosmoInlineAssistantRoute: String, Codable, Equatable, Sendable {
    case action
    case answer
}

enum CosmoEditableSurfaceKind: String, Codable, Equatable, Sendable {
    case text
    case structured
    case canvas
}

enum CosmoProposalStatus: String, Codable, Equatable, Sendable {
    case pending
    case accepted
    case rejected
    case conflicted
    case applied
}

enum CosmoProposalHunkKind: String, Codable, Equatable, Sendable {
    case context
    case removed
    case added
}

struct CosmoProposalHunk: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var kind: CosmoProposalHunkKind
    var text: String

    init(id: UUID = UUID(), kind: CosmoProposalHunkKind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

struct CosmoEditableAnchor: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var label: String
    var utf16Start: Int
    var utf16Length: Int
}

struct CosmoEditableSourceSnapshot: Codable, Equatable, Sendable {
    var surfaceID: String
    var targetID: String
    var kind: CosmoEditableSurfaceKind
    var title: String
    var text: String
    var sourceHash: String
    var anchors: [CosmoEditableAnchor]

    func withSourceHash(_ nextHash: String) -> CosmoEditableSourceSnapshot {
        var copy = self
        copy.sourceHash = nextHash
        return copy
    }
}

enum CosmoAssistantProposalOperationKind: String, Codable, Equatable, Sendable {
    case textReplacement
    case textInsertion
    case structuredFieldReplacement
    case canvasPlan
}

struct CosmoAssistantProposalOperation: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var kind: CosmoAssistantProposalOperationKind
    var targetID: String
    var anchorID: String?
    var originalText: String?
    var proposedText: String?
    var sourceHash: String
    var rationale: String
    var status: CosmoProposalStatus
    var canvasPayload: [String: String]

    init(
        id: UUID = UUID(),
        kind: CosmoAssistantProposalOperationKind,
        targetID: String,
        anchorID: String?,
        originalText: String?,
        proposedText: String?,
        sourceHash: String,
        rationale: String,
        status: CosmoProposalStatus = .pending,
        canvasPayload: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.targetID = targetID
        self.anchorID = anchorID
        self.originalText = originalText
        self.proposedText = proposedText
        self.sourceHash = sourceHash
        self.rationale = rationale
        self.status = status
        self.canvasPayload = canvasPayload
    }

    static func textReplacement(
        targetID: String,
        anchorID: String,
        originalText: String,
        proposedText: String,
        sourceHash: String,
        rationale: String
    ) -> CosmoAssistantProposalOperation {
        CosmoAssistantProposalOperation(
            kind: .textReplacement,
            targetID: targetID,
            anchorID: anchorID,
            originalText: originalText,
            proposedText: proposedText,
            sourceHash: sourceHash,
            rationale: rationale
        )
    }

    func marked(_ nextStatus: CosmoProposalStatus) -> CosmoAssistantProposalOperation {
        var copy = self
        copy.status = nextStatus
        return copy
    }

    func canApply(against source: CosmoEditableSourceSnapshot) -> Bool {
        status == .pending && targetID == source.targetID && sourceHash == source.sourceHash
    }

    var hunks: [CosmoProposalHunk] {
        CosmoInlineAssistantDiffEngine.hunks(
            original: originalText ?? "",
            proposed: proposedText ?? ""
        )
    }
}

struct CosmoAssistantProposal: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var prompt: String
    var surfaceID: String
    var title: String
    var summary: String
    var operations: [CosmoAssistantProposalOperation]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        prompt: String,
        surfaceID: String,
        title: String,
        summary: String,
        operations: [CosmoAssistantProposalOperation],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.prompt = prompt
        self.surfaceID = surfaceID
        self.title = title
        self.summary = summary
        self.operations = operations
        self.createdAt = createdAt
    }
}
