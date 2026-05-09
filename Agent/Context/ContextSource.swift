import Foundation

enum ContextSourceKind: String, Codable, Sendable, Equatable {
    case atom
    case clientProfile
    case swipe
    case content
    case conversation
    case webCapture
    case externalFile
}

enum ContextPinState: String, Codable, Sendable, Equatable {
    case unpinned
    case pinned
    case active
}

enum ContextSurface: String, Codable, Sendable, Equatable {
    case cosmoWindow
    case writingMode
    case focusPanel
    case commandK
    case voice
    case automation
}

enum RetrievalPurpose: String, Codable, Sendable, Equatable {
    case factLookup
    case brainstorm
    case writing
    case memory
    case globalSynthesis
    case general
}

struct ContextSource: Codable, Identifiable, Sendable, Equatable {
    let id: String
    var kind: ContextSourceKind
    var title: String
    var atomUUID: String?
    var externalID: String?
    var bodyHash: String
    var metadataHash: String
    var clientUUID: String?
    var pinState: ContextPinState
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        kind: ContextSourceKind,
        title: String,
        atomUUID: String? = nil,
        externalID: String? = nil,
        bodyHash: String,
        metadataHash: String,
        clientUUID: String? = nil,
        pinState: ContextPinState = .unpinned,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.atomUUID = atomUUID
        self.externalID = externalID
        self.bodyHash = bodyHash
        self.metadataHash = metadataHash
        self.clientUUID = clientUUID
        self.pinState = pinState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func needsReindex(currentBodyHash: String, currentMetadataHash: String) -> Bool {
        bodyHash != currentBodyHash || metadataHash != currentMetadataHash
    }
}

struct ContextSession: Codable, Identifiable, Sendable, Equatable {
    let id: String
    var surface: ContextSurface
    var activeAtomUUID: String?
    var activeClientUUID: String?
    var pinnedSourceIDs: [String]
    var recentDecisionSummaries: [String]
    var updatedAt: Date

    init(
        id: String,
        surface: ContextSurface,
        activeAtomUUID: String? = nil,
        activeClientUUID: String? = nil,
        pinnedSourceIDs: [String] = [],
        recentDecisionSummaries: [String] = [],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.surface = surface
        self.activeAtomUUID = activeAtomUUID
        self.activeClientUUID = activeClientUUID
        self.pinnedSourceIDs = pinnedSourceIDs
        self.recentDecisionSummaries = recentDecisionSummaries
        self.updatedAt = updatedAt
    }

    mutating func pinSourceID(_ sourceID: String) {
        guard !pinnedSourceIDs.contains(sourceID) else { return }
        pinnedSourceIDs.append(sourceID)
        updatedAt = Date()
    }
}

struct ContextChunk: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let sourceID: String
    let ordinal: Int
    let rawText: String
    var contextualHeader: String
    var anchor: String?
    var tokenCount: Int
    var bodyHash: String

    var searchableText: String {
        [contextualHeader, rawText]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }
}

struct ContextRetrievalRequest: Sendable, Equatable {
    let query: String
    let conversationID: String
    let surface: ContextSurface
    let purpose: RetrievalPurpose
    let pinnedSourceIDs: [String]
    let activeAtomUUID: String?
    let activeClientUUID: String?
    let maxChunks: Int
    let tokenBudget: Int
}

struct ContextRetrievalResult: Sendable, Equatable {
    let chunk: ContextChunk
    let source: ContextSource
    let score: Double
    let matchType: String
}

struct AgentContextPack: Sendable, Equatable {
    let request: ContextRetrievalRequest
    let retrievedResults: [ContextRetrievalResult]
    let coreMemory: [String]
    let workingMemory: [String]
    let recallMemory: [String]
    let provenanceLines: [String]
    let estimatedTokens: Int
}

extension AgentContextPack {
    var promptBlock: String {
        var lines: [String] = ["[COSMO CONTEXT PACK]"]

        if !retrievedResults.isEmpty {
            lines.append("Retrieved source evidence:")
            for result in retrievedResults {
                let anchor = result.chunk.anchor.map { " @ \($0)" } ?? ""
                lines.append("- \(result.source.title)\(anchor) [\(result.matchType), score \(String(format: "%.3f", result.score))]")
                lines.append(result.chunk.searchableText)
            }
        }

        if !coreMemory.isEmpty {
            lines.append("Core memory:")
            lines.append(contentsOf: coreMemory.map { "- \($0)" })
        }

        if !workingMemory.isEmpty {
            lines.append("Working memory:")
            lines.append(contentsOf: workingMemory.map { "- \($0)" })
        }

        if !recallMemory.isEmpty {
            lines.append("Recall memory:")
            lines.append(contentsOf: recallMemory.map { "- \($0)" })
        }

        if !provenanceLines.isEmpty {
            lines.append("Provenance:")
            lines.append(contentsOf: provenanceLines.map { "- \($0)" })
        }

        return lines.joined(separator: "\n")
    }
}
