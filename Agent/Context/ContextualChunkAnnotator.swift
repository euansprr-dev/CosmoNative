import Foundation

enum ContextualChunkAnnotator {
    static func deterministicHeader(source: ContextSource, chunkOrdinal: Int, totalChunks: Int) -> String {
        "Source: \(source.title). Type: \(source.kind.rawValue). This is chunk \(chunkOrdinal + 1) of \(max(totalChunks, 1))."
    }

    static func shouldLLMAnnotate(source: ContextSource) -> Bool {
        source.pinState == .pinned && [.content, .clientProfile, .swipe, .atom].contains(source.kind)
    }
}
