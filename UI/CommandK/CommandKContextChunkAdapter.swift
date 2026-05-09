import Foundation

enum CommandKContextChunkAdapter {
    static func rankedResult(from result: ContextRetrievalResult) -> RankedResult {
        let updatedAt = ISO8601DateFormatter().string(from: result.source.updatedAt)
        return RankedResult(
            atomUUID: result.source.atomUUID ?? result.chunk.id,
            atomType: atomType(for: result.source.kind),
            title: result.source.title,
            snippet: String(result.chunk.rawText.prefix(160)),
            semanticWeight: min(max(result.score / 12.0, 0.0), 1.0),
            structuralWeight: result.matchType == "keyword" ? 0.8 : 0.55,
            recencyWeight: WeightCalculator.recencyWeight(fromISO8601: updatedAt),
            usageWeight: result.source.pinState == .pinned || result.source.pinState == .active ? 0.8 : 0.35,
            updatedAt: updatedAt,
            accessCount: 0
        )
    }

    private static func atomType(for kind: ContextSourceKind) -> AtomType {
        switch kind {
        case .clientProfile:
            return .clientProfile
        case .content:
            return .content
        case .swipe, .webCapture, .externalFile:
            return .research
        case .conversation:
            return .journalEntry
        case .atom:
            return .research
        }
    }
}
