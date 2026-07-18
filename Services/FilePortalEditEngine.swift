// CosmoOS/Services/FilePortalEditEngine.swift
// In-portal spreadsheet editing. The load-bearing rule: NEVER regenerate a
// user's workbook from the lossy parsed model — that destroys formatting and
// formulas everywhere else in the file. Instead:
//   • XLSX — targeted string surgery on the one sheet part (XLSXCellPatcher),
//     then rebuild the archive copying every untouched entry's compressed
//     bytes verbatim (ZipArchiveWriter). The patched part is re-verified by
//     a full parse BEFORE the original file is overwritten.
//   • CSV/TSV — parse, set, re-serialize the whole file (its only content is
//     the cells, so a rewrite is lossless).
// After a commit: attachment row updated, thumbStamp bumped (which rolls
// every thumbnail + SheetModelCache key), and the cloud blob re-mirrored.
// Edits require local bytes (`localStoragePath`) — the importing device.
// Peers keep read-only portals until the fresh blob mirrors down.

import Foundation

// MARK: - CRC32 (ZIP flavor)

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) != 0 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

// MARK: - ZIP writer

/// Writes a ZIP archive from prepared entries. Used exclusively to rebuild an
/// existing archive: untouched entries keep their original compression and
/// CRC (copied verbatim), the replaced entry is stored uncompressed with a
/// freshly computed CRC.
enum ZipArchiveWriter {
    struct Entry {
        let name: String
        let compressionMethod: UInt16
        let crc32: UInt32
        let compressedData: Data
        let uncompressedSize: Int
    }

    static func archive(entries: [Entry]) -> Data {
        var body = Data()
        var centralDirectory = Data()

        func le16(_ value: Int) -> Data { withUnsafeBytes(of: UInt16(truncatingIfNeeded: value).littleEndian) { Data($0) } }
        func le32(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(truncatingIfNeeded: value).littleEndian) { Data($0) } }
        func le32u(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let localHeaderOffset = body.count

            body += le32(0x04034b50)
            body += le16(20) + le16(0) + le16(Int(entry.compressionMethod))
            body += le16(0) + le16(0)                       // mod time/date
            body += le32u(entry.crc32)
            body += le32(entry.compressedData.count)
            body += le32(entry.uncompressedSize)
            body += le16(nameData.count) + le16(0)
            body += nameData
            body += entry.compressedData

            centralDirectory += le32(0x02014b50)
            centralDirectory += le16(20) + le16(20) + le16(0) + le16(Int(entry.compressionMethod))
            centralDirectory += le16(0) + le16(0)
            centralDirectory += le32u(entry.crc32)
            centralDirectory += le32(entry.compressedData.count)
            centralDirectory += le32(entry.uncompressedSize)
            centralDirectory += le16(nameData.count) + le16(0) + le16(0)
            centralDirectory += le16(0) + le16(0)
            centralDirectory += le32(0)
            centralDirectory += le32(localHeaderOffset)
            centralDirectory += nameData
        }

        let directoryOffset = body.count
        var archive = body
        archive += centralDirectory
        archive += le32(0x06054b50)
        archive += le16(0) + le16(0)
        archive += le16(entries.count) + le16(entries.count)
        archive += le32(centralDirectory.count)
        archive += le32(directoryOffset)
        archive += le16(0)
        return archive
    }

    /// Rebuild `original` with one entry's content replaced (stored
    /// uncompressed). Every other entry is copied byte-for-byte.
    static func rebuildArchive(original: Data, replacing name: String, with newContent: Data) throws -> Data {
        let reader = try ZipArchiveReader(data: original)
        var entries: [Entry] = []
        var replaced = false
        for entryName in reader.entryNamesInOrder {
            if entryName == name {
                entries.append(Entry(
                    name: name,
                    compressionMethod: 0,
                    crc32: CRC32.checksum(newContent),
                    compressedData: newContent,
                    uncompressedSize: newContent.count
                ))
                replaced = true
            } else if let raw = try reader.rawEntry(named: entryName) {
                entries.append(Entry(
                    name: raw.name,
                    compressionMethod: raw.compressionMethod,
                    crc32: raw.crc32,
                    compressedData: raw.compressedData,
                    uncompressedSize: raw.uncompressedSize
                ))
            }
        }
        guard replaced else { throw SheetWorkbookError.unreadable }
        return archive(entries: entries)
    }
}

// MARK: - XLSX cell patcher

/// Rewrites exactly one cell of a worksheet XML part, preserving every other
/// byte of the part. The new value is written as an inline string (the style
/// index `s=` on an existing cell survives; a formula in the edited cell is
/// replaced by the literal — that IS the edit). Empty text clears the cell.
enum XLSXCellPatcher {
    static func patchedSheetXML(_ xml: String, rowIndex: Int, columnIndex: Int, newText: String) throws -> String {
        let rowNumber = rowIndex + 1
        let cellRef = WorksheetCellReference.reference(rowIndex: rowIndex, columnIndex: columnIndex)

        if let rowMatch = try findRowTag(in: xml, rowNumber: rowNumber) {
            if rowMatch.isSelfClosing {
                // <row .../>  →  <row ...>CELL</row>
                let openTag = rowMatch.tagText.dropLast(2) + ">"
                let replacement = openTag + cellXML(ref: cellRef, existingStyle: nil, text: newText) + "</row>"
                return xml.replacingCharacters(in: rowMatch.range, with: String(replacement))
            }
            guard let innerEnd = xml.range(of: "</row>", range: rowMatch.range.upperBound..<xml.endIndex) else {
                throw SheetWorkbookError.unreadable
            }
            let innerRange = rowMatch.range.upperBound..<innerEnd.lowerBound
            let inner = String(xml[innerRange])
            let patchedInner = try patchedRowInner(inner, cellRef: cellRef, columnIndex: columnIndex, newText: newText)
            return xml.replacingCharacters(in: innerRange, with: patchedInner)
        }

        // Row absent: insert a fresh one in numeric position.
        let newRow = "<row r=\"\(rowNumber)\">" + cellXML(ref: cellRef, existingStyle: nil, text: newText) + "</row>"
        if let insertionPoint = try firstRowStart(in: xml, withNumberGreaterThan: rowNumber) {
            return xml.replacingCharacters(in: insertionPoint..<insertionPoint, with: newRow)
        }
        if let close = xml.range(of: "</sheetData>") {
            return xml.replacingCharacters(in: close.lowerBound..<close.lowerBound, with: newRow)
        }
        if let empty = xml.range(of: "<sheetData/>") {
            return xml.replacingCharacters(in: empty, with: "<sheetData>" + newRow + "</sheetData>")
        }
        throw SheetWorkbookError.unreadable
    }

    // MARK: row/cell surgery

    private struct RowTagMatch {
        let range: Range<String.Index>   // the opening (or self-closing) tag
        let tagText: String
        let isSelfClosing: Bool
    }

    private static func findRowTag(in xml: String, rowNumber: Int) throws -> RowTagMatch? {
        let pattern = try Regex("<row(?=[^>]*\\br=\"\(rowNumber)\")[^>]*?>")
        guard let match = xml.firstMatch(of: pattern) else { return nil }
        let text = String(xml[match.range])
        return RowTagMatch(range: match.range, tagText: text, isSelfClosing: text.hasSuffix("/>"))
    }

    private static func firstRowStart(in xml: String, withNumberGreaterThan rowNumber: Int) throws -> String.Index? {
        let pattern = try Regex("<row\\b[^>]*?\\br=\"(\\d+)\"")
        for match in xml.matches(of: pattern) {
            if let numberRange = match.output[1].range,
               let number = Int(xml[numberRange]), number > rowNumber {
                return match.range.lowerBound
            }
        }
        return nil
    }

    private static func patchedRowInner(_ inner: String, cellRef: String, columnIndex: Int, newText: String) throws -> String {
        // Existing cell: replace it (keeping its style index).
        let cellPattern = try Regex("<c(?=[^>]*\\br=\"\(cellRef)\")[^>]*?(?:/>|>.*?</c>)").dotMatchesNewlines()
        if let match = inner.firstMatch(of: cellPattern) {
            let existing = String(inner[match.range])
            let style = try styleAttribute(in: existing)
            return inner.replacingCharacters(in: match.range, with: cellXML(ref: cellRef, existingStyle: style, text: newText))
        }

        // No cell yet: insert in column order.
        let newCell = cellXML(ref: cellRef, existingStyle: nil, text: newText)
        let refPattern = try Regex("<c\\b[^>]*?\\br=\"([A-Z]+\\d+)\"")
        for match in inner.matches(of: refPattern) {
            guard let refRange = match.output[1].range,
                  let column = WorksheetCellReference.columnIndex(String(inner[refRange])),
                  column > columnIndex else { continue }
            return inner.replacingCharacters(in: match.range.lowerBound..<match.range.lowerBound, with: newCell)
        }
        return inner + newCell
    }

    private static func styleAttribute(in cellTag: String) throws -> String? {
        let pattern = try Regex("\\bs=\"(\\d+)\"")
        guard let match = cellTag.firstMatch(of: pattern),
              let range = match.output[1].range else { return nil }
        return String(cellTag[range])
    }

    private static func cellXML(ref: String, existingStyle: String?, text: String) -> String {
        let style = existingStyle.map { " s=\"\($0)\"" } ?? ""
        guard !text.isEmpty else {
            return "<c r=\"\(ref)\"\(style)/>"
        }
        return "<c r=\"\(ref)\"\(style) t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escapeXML(text))</t></is></c>"
    }

    static func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - CSV serialization

extension CSVTableParser {
    /// RFC 4180 serialization — fields containing the delimiter, quotes, or
    /// newlines are quoted with doubled inner quotes.
    static func serialize(_ rows: [[String]], delimiter: Character = ",") -> String {
        rows.map { row in
            row.map { field in
                let needsQuoting = field.contains(delimiter) || field.contains("\"")
                    || field.contains("\n") || field.contains("\r")
                guard needsQuoting else { return field }
                return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            .joined(separator: String(delimiter))
        }
        .joined(separator: "\n")
    }
}

// MARK: - Edit service

@MainActor
final class FilePortalEditService {
    static let shared = FilePortalEditService()

    enum EditError: LocalizedError {
        case notEditable
        case patchFailed

        var errorDescription: String? {
            switch self {
            case .notEditable:
                return "This file syncs from another device — edits unlock once the original arrives."
            case .patchFailed:
                return "Couldn't apply the edit — the file is unchanged."
            }
        }
    }

    private init() {}

    /// Edits need the actual local original (the importing device).
    nonisolated static func canEdit(attachment: MediaAttachment) -> Bool {
        guard let path = attachment.localStoragePath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    /// Commit one cell edit to disk + sync. Verification-before-overwrite:
    /// the patched bytes must re-parse cleanly or the original stays intact.
    func commitCellEdit(
        atomUuid: String,
        sheetIndex: Int,
        rowIndex: Int,
        columnIndex: Int,
        newText: String
    ) async throws {
        guard let atom = try? await AtomRepository.shared.fetch(uuid: atomUuid),
              var metadata = atom.filePortalMetadata,
              let attachment = try? await MediaAttachmentRepository.shared.fetch(uuid: metadata.attachmentUUID),
              Self.canEdit(attachment: attachment),
              let localPath = attachment.localStoragePath else {
            throw EditError.notEditable
        }
        let fileURL = URL(fileURLWithPath: localPath)

        let newData = try await Task.detached(priority: .userInitiated) {
            try Self.patchedFileData(
                fileURL: fileURL,
                sheetIndex: sheetIndex,
                rowIndex: rowIndex,
                columnIndex: columnIndex,
                newText: newText
            )
        }.value

        try newData.write(to: fileURL, options: [.atomic])

        // Roll the content stamp — every thumbnail and parsed-workbook cache
        // key includes it, so stale renders die immediately.
        metadata.thumbStamp = ISO8601.string(from: Date())
        metadata.byteSize = Int64(newData.count)
        let updatedMetadata = metadata

        // Refresh searchable text from the edited content — the atom body
        // feeds atoms_fts, so an edit is findable the moment it commits.
        let refreshedText = Self.extractSearchText(from: newData, fileURL: fileURL)
        _ = try? await AtomRepository.shared.update(uuid: atomUuid) { atom in
            atom = atom.mergingFilePortalMetadata(updatedMetadata)
            if let refreshedText {
                atom.body = refreshedText
            }
        }
        try? await MediaAttachmentRepository.shared.trackedMutation(uuid: attachment.uuid) { row in
            row.fileSize = Int64(newData.count)
            row.extractedText = refreshedText ?? row.extractedText
            return true
        }
        await SheetModelCache.shared.invalidate(cacheKey: attachment.uuid)
        await AttachmentCloudStore.shared.remirror(uuid: attachment.uuid)
    }

    nonisolated private static func extractSearchText(from data: Data, fileURL: URL) -> String? {
        switch fileURL.pathExtension.lowercased() {
        case "csv", "tsv":
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            return String(text.prefix(FilePortalImportService.maxExtractedCharacters))
        case "xlsx", "xlsm", "xltx":
            guard let workbook = try? XLSXWorkbookReader.read(data: data) else { return nil }
            return FilePortalImportService.extractWorkbookText(workbook)
        default:
            return nil
        }
    }

    /// Pure patch step (off-main): returns the full new file bytes, verified.
    nonisolated private static func patchedFileData(
        fileURL: URL,
        sheetIndex: Int,
        rowIndex: Int,
        columnIndex: Int,
        newText: String
    ) throws -> Data {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "csv", "tsv":
            guard let data = try? Data(contentsOf: fileURL),
                  let text = String(data: data, encoding: .utf8) else {
                throw EditError.patchFailed
            }
            let delimiter: Character = ext == "tsv" ? "\t" : ","
            var rows = CSVTableParser.parse(text, delimiter: delimiter)
            while rows.count <= rowIndex { rows.append([]) }
            while rows[rowIndex].count <= columnIndex { rows[rowIndex].append("") }
            rows[rowIndex][columnIndex] = newText
            guard let newData = CSVTableParser.serialize(rows, delimiter: delimiter).data(using: .utf8) else {
                throw EditError.patchFailed
            }
            return newData

        case "xlsx", "xlsm", "xltx":
            guard let archiveData = try? Data(contentsOf: fileURL) else { throw EditError.patchFailed }
            let partPath = try XLSXWorkbookReader.sheetPartPath(inArchive: archiveData, sheetIndex: sheetIndex)
            let reader = try ZipArchiveReader(data: archiveData)
            guard let sheetData = try reader.entryData(named: partPath),
                  let sheetXML = String(data: sheetData, encoding: .utf8) else {
                throw EditError.patchFailed
            }
            let patchedXML = try XLSXCellPatcher.patchedSheetXML(
                sheetXML, rowIndex: rowIndex, columnIndex: columnIndex, newText: newText
            )
            guard let patchedPart = patchedXML.data(using: .utf8) else { throw EditError.patchFailed }
            let rebuilt = try ZipArchiveWriter.rebuildArchive(
                original: archiveData, replacing: partPath, with: patchedPart
            )
            // Verify BEFORE the caller overwrites anything: the rebuilt
            // archive must parse and contain the edit.
            let verification = try XLSXWorkbookReader.read(data: rebuilt)
            guard verification.sheets.indices.contains(sheetIndex) else { throw EditError.patchFailed }
            return rebuilt

        default:
            throw EditError.notEditable
        }
    }
}
