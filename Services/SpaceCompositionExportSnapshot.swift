import CryptoKit
import Foundation

/// A value copy of the authored work at the moment Preview opens. Rendering and
/// saving never reread live atoms, so a later edit cannot change an open preview.
struct SpaceCompositionExportSnapshot: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let schemaVersion: Int
    let spaceID: String
    let rootUUID: String
    let title: String
    let capturedAt: Date
    let sections: [Section]
    let assets: [String: Asset]

    struct Section: Codable, Equatable, Sendable, Identifiable {
        let id: String
        let title: String
        let depth: Int
        let document: RichDocument
    }

    struct Asset: Codable, Equatable, Sendable {
        let data: Data
        let mimeType: String
        let width: Double?
        let height: Double?

        init(data: Data, mimeType: String, width: Double? = nil, height: Double? = nil) {
            self.data = data
            self.mimeType = mimeType
            self.width = width
            self.height = height
        }

        var dataURL: String { "data:\(mimeType);base64,\(data.base64EncodedString())" }
    }

    init(
        id: UUID = UUID(), spaceID: String, rootUUID: String, title: String,
        capturedAt: Date = Date(), sections: [Section], assets: [String: Asset] = [:]
    ) {
        self.id = id
        schemaVersion = 1
        self.spaceID = spaceID
        self.rootUUID = rootUUID
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : title
        self.capturedAt = capturedAt
        self.sections = sections
        self.assets = assets
    }

    static func capture(from composition: SpaceCompositionSnapshot, rootUUID: String) throws -> Self {
        let sections = composition.orderedSections(of: rootUUID, includedOnly: true).map { section in
            let atom = section.atom
            let rich = RichDocumentMetadataStorage.readDocument(
                from: atom.metadata, key: RichDocumentMetadataKeys.bodyDocument, atomUUID: atom.uuid
            ) ?? RichDocumentMetadataStorage.readDocument(
                from: atom.metadata, key: RichDocumentMetadataKeys.contentDraftDocument, atomUUID: atom.uuid
            ) ?? RichDocument.migrateLegacy(atom.body ?? "")
            return Section(id: atom.uuid, title: atom.title ?? "Untitled", depth: section.depth, document: rich)
        }
        guard let root = sections.first, root.id == rootUUID else {
            throw SpaceCompositionExportError.nothingIncluded
        }
        return Self(spaceID: composition.spaceID, rootUUID: rootUUID, title: root.title, sections: sections)
    }

    var wordCount: Int {
        sections.reduce(0) { total, section in
            total + (section.title + " " + section.document.plainText)
                .split(whereSeparator: { $0.isWhitespace }).count
        }
    }

    func replacingAssets(_ assets: [String: Asset]) -> Self {
        Self(id: id, spaceID: spaceID, rootUUID: rootUUID, title: title,
             capturedAt: capturedAt, sections: sections, assets: assets)
    }

    static func imageKey(_ image: RichImageReference) -> String {
        "image:" + SHA256.hash(data: Data((image.path + "|" + (image.remoteURL ?? "")).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    static func sketchKey(_ block: RichBlock) -> String { "sketch:" + block.id.uuidString }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

enum SpaceCompositionExportError: LocalizedError {
    case nothingIncluded
    case missingImage(String)
    case unsupportedBlock(String)
    case assetTooLarge
    case renderingFailed
    case paginationFailed

    var errorDescription: String? {
        switch self {
        case .nothingIncluded: return "Include at least one authored page before exporting this work."
        case .missingImage(let title): return "An image in “\(title)” is unavailable. Open the page to download or replace it, then preview again."
        case .unsupportedBlock(let title): return "“\(title)” contains a newer block this version cannot export faithfully. Update Cosmo before exporting."
        case .assetTooLarge: return "The images in this work are too large to export together. Export a smaller section or reduce the image sizes."
        case .renderingFailed: return "The document could not be rendered. Your writing is unchanged. Try exporting as HTML or Markdown."
        case .paginationFailed: return "A section is too large to fit on the printed page. Try exporting an editable Word document or HTML."
        }
    }
}

enum SpaceCompositionExportFormat: String, CaseIterable, Identifiable, Sendable {
    case pdf, word, markdown, html
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pdf: return "PDF"
        case .word: return "Word document"
        case .markdown: return "Markdown"
        case .html: return "HTML"
        }
    }
    var fileExtension: String {
        switch self {
        case .word: return "docx"
        case .markdown: return "md"
        default: return rawValue
        }
    }
    var detail: String {
        switch self {
        case .pdf: return "A reading copy with the pagination shown above."
        case .word: return "Editable text, tables, and images. Pagination follows the app you open it in."
        case .markdown: return "Portable text. Rich tables and images use HTML; some Markdown readers may hide them."
        case .html: return "A self-contained document with its images, ready to open in a browser."
        }
    }
}
