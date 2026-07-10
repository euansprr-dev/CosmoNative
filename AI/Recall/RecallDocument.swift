// CosmoOS/AI/Recall/RecallDocument.swift
// Turns atoms into embedding-ready documents: a per-type text builder, a
// paragraph-packing chunker, and a content hash that detects staleness.
// The old vector layer embedded whole atoms as single vectors (semantic
// soup) and never re-embedded after edits; both problems die here.
// July 2026

import Foundation
import CryptoKit

// MARK: - Chunk

struct RecallChunk: Sendable, Equatable {
    let index: Int
    let text: String
    /// Optional locator (e.g. a PDF page) carried through to citations.
    let page: Int?

    init(index: Int, text: String, page: Int? = nil) {
        self.index = index
        self.text = text
        self.page = page
    }
}

// MARK: - Document Builder

enum RecallDocumentBuilder {
    /// Atom types worth indexing. Operational rows (tasks, habits, schedule)
    /// are noise for semantic recall and stay out.
    static let indexedTypes: Set<AtomType> = [
        .note, .content, .idea, .connection, .research, .stickyNote,
        .extract, .question,
    ]

    /// Target chunk size and overlap, in characters. ~1,000 chars ≈ 200–250
    /// tokens: small enough that a match means something, big enough to read.
    static let chunkTarget = 1_000
    static let chunkOverlap = 150
    static let maxChunksPerAtom = 40

    static func isIndexable(_ atom: Atom) -> Bool {
        guard !atom.isDeleted else { return false }
        guard indexedTypes.contains(atom.type) else { return false }
        return !documentText(for: atom).isEmpty
    }

    /// The embedding-facing text of an atom. Deliberately plain: title plus
    /// the content that matters for the type, markdown left as-is (embedding
    /// models handle it fine).
    static func documentText(for atom: Atom) -> String {
        let title = atom.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let body = atom.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var parts: [String] = []
        if !title.isEmpty { parts.append(title) }
        if !body.isEmpty { parts.append(body) }
        return parts.joined(separator: "\n\n")
    }

    /// Stable content hash — when it matches the indexed row, the index is
    /// fresh; when it differs, the atom needs re-embedding. This is what the
    /// old layer was missing (it only ever detected MISSING atoms, not stale).
    static func documentHash(for atom: Atom) -> String {
        let digest = SHA256.hash(data: Data(documentText(for: atom).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Paragraph-packed chunks with a title prefix on every chunk so each
    /// vector knows what document it belongs to. PDF-extracted bodies carry
    /// `[[page N]]` markers (written by PDFSourceStore.extractText); chunks
    /// from those documents are stamped with their page so recall citations
    /// can say "p. 12" and deep-link into the reader.
    static func chunks(for atom: Atom) -> [RecallChunk] {
        let text = documentText(for: atom)
        guard !text.isEmpty else { return [] }

        let title = atom.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let prefix = title.isEmpty ? "" : "\(title)\n"

        let pieces: [(text: String, page: Int?)]
        if let paged = pagedSegments(text) {
            pieces = paged.flatMap { segment in
                packedParagraphs(segment.text).map { ($0, segment.page) }
            }
        } else {
            pieces = packedParagraphs(text).map { ($0, nil) }
        }

        return pieces.prefix(maxChunksPerAtom).enumerated().map { index, piece in
            // Don't double-prefix the first chunk, which already starts with the title.
            let chunkText = (index == 0 || prefix.isEmpty || piece.text.hasPrefix(title))
                ? piece.text
                : prefix + piece.text
            return RecallChunk(index: index, text: chunkText, page: piece.page)
        }
    }

    /// Split a page-marked body into per-page segments, stripping the markers
    /// (they're noise in an embedding). Returns nil when the text carries no
    /// markers, so plain documents take the fast path.
    static func pagedSegments(_ text: String) -> [(text: String, page: Int?)]? {
        guard text.contains("[[page ") else { return nil }
        let pattern = /\[\[page (\d+)\]\]/
        let matches = text.matches(of: pattern)
        guard !matches.isEmpty else { return nil }

        var segments: [(text: String, page: Int?)] = []
        // Anything before the first marker (usually the title) has no page.
        let head = String(text[text.startIndex..<matches[0].range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !head.isEmpty { segments.append((head, nil)) }

        for (offset, match) in matches.enumerated() {
            let start = match.range.upperBound
            let end = offset + 1 < matches.count ? matches[offset + 1].range.lowerBound : text.endIndex
            var body = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            // The extractor's truncation note is bookkeeping, not content.
            if let truncated = body.range(of: "[[truncated after page") {
                body = String(body[body.startIndex..<truncated.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !body.isEmpty else { continue }
            segments.append((body, Int(match.output.1)))
        }
        return segments.isEmpty ? nil : segments
    }

    /// Split on blank lines, pack paragraphs into ~chunkTarget windows, and
    /// carry a small overlap so ideas that straddle a boundary stay findable.
    static func packedParagraphs(_ text: String) -> [String] {
        guard text.count > chunkTarget else { return [text] }

        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        var current = ""

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { chunks.append(trimmed) }
            current = ""
        }

        for paragraph in paragraphs {
            if paragraph.count > chunkTarget {
                // Giant paragraph (transcripts): hard-wrap on sentence-ish boundaries.
                flush()
                chunks.append(contentsOf: hardWrap(paragraph))
                continue
            }
            if current.count + paragraph.count + 2 > chunkTarget, !current.isEmpty {
                let tail = String(current.suffix(chunkOverlap))
                flush()
                current = tail.isEmpty ? "" : "…" + tail + "\n\n"
            }
            current += (current.isEmpty ? "" : "\n\n") + paragraph
        }
        flush()
        return chunks
    }

    private static func hardWrap(_ paragraph: String) -> [String] {
        var chunks: [String] = []
        var window = ""
        for sentence in paragraph.split(separator: ".", omittingEmptySubsequences: true) {
            let piece = sentence.trimmingCharacters(in: .whitespaces) + "."
            if window.count + piece.count > chunkTarget, !window.isEmpty {
                chunks.append(window.trimmingCharacters(in: .whitespaces))
                window = String(window.suffix(chunkOverlap))
            }
            window += " " + piece
        }
        let last = window.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { chunks.append(last) }
        return chunks
    }
}

// MARK: - Vector Math

enum RecallVectorMath {
    /// L2-normalize so cosine similarity is a plain dot product everywhere.
    /// One similarity definition — the old layer compared L2 distances against
    /// cosine thresholds depending on which code path ran.
    static func normalized(_ vector: [Float]) -> [Float] {
        var sum: Float = 0
        for value in vector { sum += value * value }
        let norm = sum.squareRoot()
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    static func dot(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var total: Float = 0
        for i in a.indices { total += a[i] * b[i] }
        return total
    }
}
