// CosmoOS/Data/Models/PDFHighlight.swift
// Reading Room highlights: persistent visual marks on a PDF source atom,
// linked to the capture atom the selection produced. Rehydrated as
// PDFAnnotation overlays whenever the document reopens; cascade with both
// the source atom and the capture atom (tombstone law).

import Foundation
import GRDB

struct PDFHighlight: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "pdf_highlights"

    var id: Int64?
    /// The PDF-backed source atom this mark lives on.
    var atomUuid: String
    /// Zero-based PDF page index.
    var page: Int
    /// Page-space rects, one per selected line, JSON-encoded.
    var quads: String
    var text: String
    /// The capture/extract atom the selection produced (nil if capture failed).
    var captureUuid: String?
    var createdAt: String

    enum CodingKeys: String, ColumnExpression, CodingKey {
        case id
        case atomUuid = "atom_uuid"
        case page, quads, text
        case captureUuid = "capture_uuid"
        case createdAt = "created_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var quadRects: [CGRect] {
        guard let data = quads.data(using: .utf8),
              let raw = try? JSONDecoder().decode([[Double]].self, from: data) else { return [] }
        return raw.compactMap { values in
            guard values.count == 4 else { return nil }
            return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }
    }

    static func encodeQuads(_ rects: [CGRect]) -> String {
        let raw = rects.map { [Double($0.origin.x), Double($0.origin.y), Double($0.width), Double($0.height)] }
        guard let data = try? JSONEncoder().encode(raw),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }
}

// MARK: - Store

enum PDFHighlightStore {
    static func record(
        atomUuid: String,
        page: Int,
        quads: [CGRect],
        text: String,
        captureUuid: String?
    ) async {
        guard !quads.isEmpty else { return }
        let highlight = PDFHighlight(
            id: nil,
            atomUuid: atomUuid,
            page: page,
            quads: PDFHighlight.encodeQuads(quads),
            text: String(text.prefix(2_000)),
            captureUuid: captureUuid,
            createdAt: ISO8601.string(from: Date())
        )
        try? await CosmoDatabase.shared.asyncWrite { db in
            guard (try? db.tableExists(PDFHighlight.databaseTableName)) ?? false else { return }
            var row = highlight
            try row.insert(db)
        }
        await MainActor.run {
            NotificationCenter.default.post(
                name: .cosmoPDFHighlightsChanged,
                object: nil,
                userInfo: ["atomUuid": atomUuid]
            )
        }
    }

    static func highlights(forAtom uuid: String) async -> [PDFHighlight] {
        (try? await CosmoDatabase.shared.asyncRead { db in
            guard (try? db.tableExists(PDFHighlight.databaseTableName)) ?? false else { return [] }
            return try PDFHighlight
                .filter(PDFHighlight.CodingKeys.atomUuid == uuid)
                .order(PDFHighlight.CodingKeys.createdAt.asc)
                .fetchAll(db)
        }) ?? []
    }

    /// Tombstone cascade: an atom died — remove marks it owned (as the PDF
    /// source) AND marks whose capture it was.
    static func removeForAtom(_ uuid: String) async {
        try? await CosmoDatabase.shared.asyncWrite { db in
            guard (try? db.tableExists(PDFHighlight.databaseTableName)) ?? false else { return }
            try db.execute(
                sql: "DELETE FROM pdf_highlights WHERE atom_uuid = ? OR capture_uuid = ?",
                arguments: [uuid, uuid]
            )
        }
    }
}

extension Notification.Name {
    /// Posted after a highlight lands so an open reader can rehydrate live.
    static let cosmoPDFHighlightsChanged = Notification.Name("cosmoPDFHighlightsChanged")
}
