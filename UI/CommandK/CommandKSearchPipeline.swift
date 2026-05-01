import Foundation
import os

actor CommandKSearchPipeline {
    private var currentRequest = CommandKSearchRequestID()

    func nextRequestID() -> CommandKSearchRequestID {
        currentRequest = CommandKSearchRequestID()
        return currentRequest
    }

    func isCurrent(_ requestID: CommandKSearchRequestID) -> Bool {
        requestID == currentRequest
    }
}

struct CommandKSearchRequestID: Equatable, Sendable {
    private let rawValue = UUID()
}

struct CommandKSearchIndex {
    struct Entry: Identifiable, Equatable {
        let id: String
        let atomUUID: String
        let atomType: AtomType
        let title: String
        let snippet: String?
        let updatedAt: String
        let searchableText: String

        init(
            id: String,
            atomUUID: String,
            atomType: AtomType,
            title: String,
            snippet: String?,
            updatedAt: String
        ) {
            self.id = id
            self.atomUUID = atomUUID
            self.atomType = atomType
            self.title = title
            self.snippet = snippet
            self.updatedAt = updatedAt
            self.searchableText = CommandKSearchMatcher.searchableText(from: [
                title,
                snippet,
                atomType.rawValue
            ])
        }
    }

    private(set) var entries: [Entry] = []

    mutating func replace(_ entries: [Entry]) {
        self.entries = entries
    }

    mutating func replace(atoms: [Atom]) {
        entries = atoms.map { atom in
            Entry(
                id: atom.uuid,
                atomUUID: atom.uuid,
                atomType: atom.type,
                title: atom.title ?? "Untitled",
                snippet: atom.body,
                updatedAt: atom.updatedAt
            )
        }
    }

    func search(_ query: String, limit: Int) -> [RankedResult] {
        let normalizedQuery = CommandKSearchMatcher.normalizeQuery(query)
        guard !normalizedQuery.isEmpty else { return [] }

        return entries
            .compactMap { entry -> RankedResult? in
                guard entry.searchableText.contains(normalizedQuery) else { return nil }
                let normalizedTitle = CommandKSearchMatcher.normalize(entry.title)
                let structural: Double
                if normalizedTitle == normalizedQuery {
                    structural = 1.0
                } else if normalizedTitle.hasPrefix(normalizedQuery) {
                    structural = 0.86
                } else if normalizedTitle.contains(normalizedQuery) {
                    structural = 0.68
                } else {
                    structural = 0.42
                }

                return RankedResult(
                    atomUUID: entry.atomUUID,
                    atomType: entry.atomType,
                    title: entry.title,
                    snippet: entry.snippet?.prefix(160).description,
                    semanticWeight: 0.0,
                    structuralWeight: structural,
                    recencyWeight: 0.5,
                    usageWeight: 0.5,
                    updatedAt: entry.updatedAt
                )
            }
            .sorted()
            .prefix(limit)
            .map { $0 }
    }
}

enum CommandKPerformanceInstrumentation {
    static let logger = Logger(subsystem: "com.cosmo.os", category: "CommandKPerformance")
    static let signposter = OSSignposter(subsystem: "com.cosmo.os", category: "CommandKPerformance")
}
