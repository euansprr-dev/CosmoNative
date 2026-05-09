import Foundation

enum ContextChunker {
    static func chunk(
        sourceID: String,
        title: String,
        body: String,
        bodyHash: String,
        maxCharacters: Int = 2_800,
        overlapCharacters: Int = 500
    ) -> [ContextChunk] {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let safeMax = max(300, maxCharacters)
        let safeOverlap = min(max(0, overlapCharacters), safeMax / 2)
        var chunks: [ContextChunk] = []
        var start = trimmed.startIndex
        var ordinal = 0

        while start < trimmed.endIndex {
            let roughEnd = trimmed.index(start, offsetBy: safeMax, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
            let end = adjustedEnd(in: trimmed, start: start, roughEnd: roughEnd)
            let raw = String(trimmed[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)

            if !raw.isEmpty {
                chunks.append(
                    ContextChunk(
                        id: "\(sourceID)-chunk-\(ordinal)",
                        sourceID: sourceID,
                        ordinal: ordinal,
                        rawText: raw,
                        contextualHeader: "Source: \(title). Chunk \(ordinal + 1).",
                        anchor: "chunk-\(ordinal + 1)",
                        tokenCount: max(1, raw.count / 4),
                        bodyHash: bodyHash
                    )
                )
                ordinal += 1
            }

            guard end < trimmed.endIndex else { break }
            let overlapStart = trimmed.index(end, offsetBy: -safeOverlap, limitedBy: trimmed.startIndex) ?? start
            start = overlapStart > start ? overlapStart : end
        }

        return chunks
    }

    private static func adjustedEnd(in text: String, start: String.Index, roughEnd: String.Index) -> String.Index {
        guard roughEnd < text.endIndex else { return text.endIndex }
        let searchRange = start..<roughEnd
        let markers = [". ", "\n\n", "\n", " "]

        for marker in markers {
            if let range = text.range(of: marker, options: .backwards, range: searchRange),
               text.distance(from: start, to: range.upperBound) > 200 {
                return range.upperBound
            }
        }

        return roughEnd
    }
}
