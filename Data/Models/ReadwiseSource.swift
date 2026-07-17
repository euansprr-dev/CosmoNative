// CosmoOS/Data/Models/ReadwiseSource.swift
// The Readwise book mirror (READWISE_INTEGRATION_PLAN.md): one `.research`
// atom per book/article, highlights in structured JSON, body = concatenated
// highlight text so search and the recall index reach every line for free.
// Replaces the older one-atom-per-highlight sync (ReadwiseService pre-July
// 2026), which had no pruning, no updates, and polluted the library — those
// legacy atoms consolidate into mirrors on the first mirror sync.
//
// Readwise stays the source of truth — Cosmo upserts and prunes, never
// edits. Highlights are EVIDENCE: they surface in development conversations
// and the sources rail, never in the inbox, never as seedling thoughts.
// Consumes the wire models ReadwiseService already decodes
// (`ReadwiseExportBook` / `ReadwiseExportHighlight`).
// July 2026.

import Foundation

// MARK: - Mirrored highlight (the structured payload's row)

struct ReadwiseMirrorHighlight: Codable, Equatable, Identifiable, Sendable {
    /// Readwise highlight id (stringified) — the dedup key.
    var id: String
    var text: String
    /// The user's own annotation — their words, not the author's.
    var note: String?
    var location: Int?
    var highlightedAt: String?
    var color: String?
    var tags: [String]
    var readwiseUrl: String?

    init(
        id: String,
        text: String,
        note: String? = nil,
        location: Int? = nil,
        highlightedAt: String? = nil,
        color: String? = nil,
        tags: [String] = [],
        readwiseUrl: String? = nil
    ) {
        self.id = id
        self.text = text
        self.note = note
        self.location = location
        self.highlightedAt = highlightedAt
        self.color = color
        self.tags = tags
        self.readwiseUrl = readwiseUrl
    }

    enum CodingKeys: String, CodingKey {
        case id, text, note, location, highlightedAt, color, tags, readwiseUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note)
        location = try c.decodeIfPresent(Int.self, forKey: .location)
        highlightedAt = try c.decodeIfPresent(String.self, forKey: .highlightedAt)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        readwiseUrl = try c.decodeIfPresent(String.self, forKey: .readwiseUrl)
    }
}

// MARK: - Structured payload (the atom's `structured` column)

struct ReadwiseSourceStructured: Codable, Equatable, Sendable {
    var highlights: [ReadwiseMirrorHighlight]

    init(highlights: [ReadwiseMirrorHighlight] = []) {
        self.highlights = highlights
    }

    enum CodingKeys: String, CodingKey { case highlights }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        highlights = try c.decodeIfPresent([ReadwiseMirrorHighlight].self, forKey: .highlights) ?? []
    }

    func toJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func fromJSON(_ json: String) -> ReadwiseSourceStructured? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ReadwiseSourceStructured.self, from: data)
    }
}

// MARK: - Atom accessors

extension Atom {
    /// True for atoms mirroring a whole Readwise book/article (the July 2026
    /// shape). Mirrors are evidence: never merge/triage targets (the next
    /// sync would clobber anything absorbed into them), never seedling food.
    var isReadwiseMirror: Bool {
        metadataDict?["subtype"] as? String == "readwise"
    }

    /// True for ANY Readwise-born atom — the book mirrors above AND the
    /// legacy one-atom-per-highlight rows (metadata.source == "readwise")
    /// that predate the mirror. Exclusion checks use this wider net.
    var isReadwiseContent: Bool {
        isReadwiseMirror || metadataDict?["source"] as? String == "readwise"
    }

    var readwiseBookId: String? {
        metadataDict?["readwiseBookId"] as? String
    }

    var readwiseAuthor: String? {
        metadataDict?["author"] as? String
    }

    var readwiseCoverImageUrl: String? {
        metadataDict?["coverImageUrl"] as? String
    }

    var readwiseStructured: ReadwiseSourceStructured? {
        guard isReadwiseMirror else { return nil }
        return structured.flatMap { ReadwiseSourceStructured.fromJSON($0) }
    }
}

// MARK: - Mirror reducer (pure, unit-tested)

/// Maps export books (the wire models ReadwiseService decodes) onto mirror
/// mutations without touching the database — the sync pass is a thin IO
/// shell around these functions, so upsert, dedup, pruning, and idempotence
/// are all testable with fixtures.
enum ReadwiseMirrorReducer {

    /// One book's incoming export merged over the existing mirror state.
    /// - Upsert per highlight by Readwise id (newer text/note/tags win).
    /// - Deleted AND discarded highlights prune.
    /// - Ordered by location (then highlightedAt) — reading order.
    /// `changed == false` means write nothing (idempotence).
    static func mergedStructured(
        existing: ReadwiseSourceStructured?,
        incoming: ReadwiseExportBook
    ) -> (structured: ReadwiseSourceStructured, changed: Bool) {
        var byId: [String: ReadwiseMirrorHighlight] = [:]
        for highlight in existing?.highlights ?? [] {
            byId[highlight.id] = highlight
        }

        for raw in incoming.highlights {
            let key = String(raw.id)
            if (raw.isDeleted ?? false) || (raw.isDiscard ?? false) {
                byId.removeValue(forKey: key)
                continue
            }
            let text = raw.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            byId[key] = ReadwiseMirrorHighlight(
                id: key,
                text: text,
                note: raw.note?.isEmpty == false ? raw.note : nil,
                location: raw.location,
                highlightedAt: raw.highlightedAt,
                color: raw.color,
                tags: raw.tags?.map(\.name).filter { !$0.isEmpty } ?? [],
                readwiseUrl: raw.url
            )
        }

        let merged = ReadwiseSourceStructured(
            highlights: byId.values.sorted { lhs, rhs in
                switch (lhs.location, rhs.location) {
                case let (l?, r?) where l != r: return l < r
                case (.some, .none): return true
                case (.none, .some): return false
                default: return (lhs.highlightedAt ?? "") < (rhs.highlightedAt ?? "")
                }
            }
        )
        return (merged, merged != (existing ?? ReadwiseSourceStructured()))
    }

    /// The atom body: concatenated highlight text (notes included) — this is
    /// what hybrid search and the recall index see.
    static func indexableBody(_ structured: ReadwiseSourceStructured) -> String {
        structured.highlights
            .map { highlight in
                if let note = highlight.note, !note.isEmpty {
                    return highlight.text + "\n※ " + note
                }
                return highlight.text
            }
            .joined(separator: "\n\n")
    }

    /// Metadata keys the mirror owns on the book atom (merged at key level —
    /// sibling keys like attachmentUUIDs survive).
    static func metadataOverlay(for book: ReadwiseExportBook) -> [String: String] {
        var overlay: [String: String] = [
            "subtype": "readwise",
            "readwiseBookId": String(book.userBookId),
        ]
        if let category = book.category, !category.isEmpty { overlay["readwiseCategory"] = category }
        if let author = book.author, !author.isEmpty { overlay["author"] = author }
        if let cover = book.coverImageUrl, !cover.isEmpty { overlay["coverImageUrl"] = cover }
        if let url = book.sourceUrl, !url.isEmpty { overlay["sourceUrl"] = url }
        return overlay
    }

    static func displayTitle(for book: ReadwiseExportBook) -> String {
        let candidate = book.readableTitle ?? book.title
        return candidate.isEmpty ? "Untitled" : candidate
    }
}
