// CosmoOS/Services/FilePortalImportService.swift
// One choke point for every file-portal entry path (Finder drop, ⌘V paste,
// open panel): bytes are COPIED into CaptureMediaStorage (never referenced in
// place), the row lands in the synced media_attachments domain (ownerType
// `atom`), the atom is an AtomType.file carrying FilePortalMetadata under its
// `filePortal` key, and AttachmentCloudStore mirrors original + thumbnail to
// the private `capture-media` bucket so portals resolve on every device.

import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class FilePortalImportService {
    static let shared = FilePortalImportService()

    nonisolated static let maxFileBytes: Int64 = 100 * 1024 * 1024
    nonisolated static let maxExtractedCharacters = 20_000

    enum ImportError: LocalizedError {
        case tooLarge(filename: String, bytes: Int64)
        case unreadable(filename: String)

        var errorDescription: String? {
            switch self {
            case .tooLarge(let filename, let bytes):
                let mb = bytes / (1024 * 1024)
                return "\(filename) is \(mb) MB — the portal limit is 100 MB"
            case .unreadable(let filename):
                return "Couldn't read \(filename)"
            }
        }
    }

    struct ImportedPortal {
        let atom: Atom
        let attachment: MediaAttachment
    }

    private init() {}

    /// True when a portal should claim this file (images stay with the native
    /// image-block pipeline; folders and packages are not portal material).
    static func acceptsFileURL(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey]) else {
            return false
        }
        if values.isDirectory == true { return false }
        if let type = values.contentType, type.conforms(to: .image) { return false }
        return true
    }

    func importFile(at url: URL) async throws -> ImportedPortal {
        let filename = url.lastPathComponent
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           Int64(size) > Self.maxFileBytes {
            throw ImportError.tooLarge(filename: filename, bytes: Int64(size))
        }
        guard let data = try? Data(contentsOf: url) else {
            throw ImportError.unreadable(filename: filename)
        }
        return try await importData(data, filename: filename)
    }

    func importData(_ data: Data, filename: String) async throws -> ImportedPortal {
        guard Int64(data.count) <= Self.maxFileBytes else {
            throw ImportError.tooLarge(filename: filename, bytes: Int64(data.count))
        }

        let fileExtension = (filename as NSString).pathExtension.lowercased()
        let portalKind = FilePortalMetadata.Kind.detect(fileExtension: fileExtension)
        let utType = UTType(filenameExtension: fileExtension) ?? .data
        let attachmentUUID = UUID().uuidString
        let atomUUID = UUID().uuidString

        // Bytes first — the copy is the source of truth from here on.
        let stored = try CaptureMediaStorage.shared.store(
            data: data,
            capturedItemId: atomUUID,
            attachmentId: attachmentUUID,
            originalFilename: filename,
            mimeType: utType.preferredMIMEType,
            telegramFilePath: nil,
            kind: Self.attachmentKind(portalKind: portalKind, utType: utType)
        )
        let originalURL = URL(fileURLWithPath: stored.originalPath)

        // Format enrichment — page count, sheet names, searchable text.
        // Best-effort: a parse failure only costs the enrichment, never the import.
        var pageCount: Int?
        var sheetNames: [String]?
        var extractedText: String?
        switch portalKind {
        case .pdf:
            if let document = PDFDocument(url: originalURL) {
                pageCount = document.pageCount
                extractedText = Self.extractPDFText(document)
            }
        case .csv:
            if let text = String(data: data, encoding: .utf8) {
                extractedText = String(text.prefix(Self.maxExtractedCharacters))
            }
        case .spreadsheet:
            if let workbook = try? await Task.detached(priority: .utility, operation: {
                try XLSXWorkbookReader.read(data: data)
            }).value {
                sheetNames = workbook.sheets.map(\.name)
                extractedText = Self.extractWorkbookText(workbook)
            }
        case .generic:
            break
        }

        // Portal skin — rendered once at import so the block never waits, and
        // written beside the original so the cloud mirror ships it to peers.
        var thumbnailPath = stored.thumbnailPath
        if thumbnailPath == nil,
           let jpeg = await FilePortalThumbnailStore.shared.renderThumbnailJPEG(for: originalURL) {
            let thumbURL = originalURL.deletingLastPathComponent()
                .appendingPathComponent("\(attachmentUUID)-thumb.jpg")
            if (try? jpeg.write(to: thumbURL, options: [.atomic])) != nil {
                thumbnailPath = thumbURL.path
            }
        }

        var attachment = MediaAttachment.makeLocal(
            owner: .atom,
            ownerUUID: atomUUID,
            kind: Self.attachmentKind(portalKind: portalKind, utType: utType),
            localStoragePath: stored.originalPath,
            thumbnailPath: thumbnailPath,
            originalFilename: filename,
            mimeType: utType.preferredMIMEType,
            fileSize: Int64(data.count),
            metadata: nil
        )
        attachment.uuid = attachmentUUID
        attachment.extractedText = extractedText
        attachment.processingStatus = extractedText == nil ? .downloaded : .textExtracted
        let savedAttachment = try await MediaAttachmentRepository.shared.create(attachment)

        let portalMeta = FilePortalMetadata(
            attachmentUUID: attachmentUUID,
            originalFilename: filename,
            fileExtension: fileExtension,
            byteSize: Int64(data.count),
            portalKind: portalKind,
            pageCount: pageCount,
            sheetNames: sheetNames,
            thumbStamp: ISO8601.string(from: Date())
        )

        // Body carries the extracted content so file portals are findable by
        // what's INSIDE them — the atoms_fts triggers index title + body on
        // insert, no extra indexing step. Falls back to the filename.
        var newAtom = Atom.new(
            type: .file,
            title: (filename as NSString).deletingPathExtension,
            body: extractedText ?? filename
        ).mergingFilePortalMetadata(portalMeta)
        newAtom.uuid = atomUUID
        let atomToInsert = newAtom
        // PersistableRecord.insert never writes back the rowid — stamp it so
        // the block's entityId is valid for peek/pane/focus from second one.
        let atom = try await CosmoDatabase.shared.asyncWrite { db -> Atom in
            try atomToInsert.insert(db)
            var saved = atomToInsert
            saved.id = db.lastInsertedRowID
            return saved
        }

        AttachmentCloudStore.kick()
        return ImportedPortal(atom: atom, attachment: savedAttachment)
    }

    // MARK: - Kind mapping

    static func attachmentKind(portalKind: FilePortalMetadata.Kind, utType: UTType) -> MediaAttachmentKind {
        switch portalKind {
        case .pdf: return .pdf
        case .spreadsheet, .csv: return .spreadsheet
        case .generic: return InboxDropIngestService.attachmentKind(for: utType)
        }
    }

    // MARK: - Text extraction

    /// Cell text flattened row-per-line for search — bounded, tab-joined.
    /// Internal: FilePortalEditService re-extracts after in-portal edits.
    nonisolated static func extractWorkbookText(_ workbook: SheetWorkbook) -> String? {
        var text = ""
        for sheet in workbook.sheets {
            text += sheet.name + "\n"
            for row in sheet.rows {
                let line = row.map(\.text).joined(separator: "\t").trimmingCharacters(in: .whitespaces)
                if !line.isEmpty { text += line + "\n" }
                if text.count >= maxExtractedCharacters { break }
            }
            if text.count >= maxExtractedCharacters { break }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maxExtractedCharacters))
    }

    private static func extractPDFText(_ document: PDFDocument) -> String? {
        var text = ""
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let pageText = page.string else { continue }
            text += pageText + "\n\n"
            if text.count >= maxExtractedCharacters { break }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maxExtractedCharacters))
    }
}
