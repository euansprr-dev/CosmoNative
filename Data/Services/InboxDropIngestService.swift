// CosmoOS/Data/Services/InboxDropIngestService.swift
// The general-file sibling of InboxScanIngestService: anything dropped,
// pasted, or picked in the Capture Anywhere panel converges here — bytes
// stored, cheap text extraction (OCR for images, PDFKit for PDFs, contents
// for text files), then one inbox capture per payload through the standard
// ingest choke point with the original attached. Page scans stay with
// InboxScanIngestService (they earn the careful vision-LLM pass); this
// service is deliberately fast and broad.
// July 2026 — Capture Anywhere

import AppKit
import Foundation
import Observation
import PDFKit
import UniformTypeIdentifiers

/// A capture-ready payload resolved from a drag, paste, or file picker.
enum DropPayload {
    /// A file on disk (Finder drops, file promises already received, pickers).
    case file(url: URL, suggestedName: String?)
    /// Raw bytes with a declared type (image paste, in-memory drags).
    case data(Data, type: UTType, suggestedName: String?)
    /// A link — becomes a text capture the classifier routes by flavor.
    case url(URL)
    /// Plain text — straight to the ingest choke point.
    case text(String)
}

/// What happened to one payload — the session tray renders these honestly.
struct DropCaptureResult: Identifiable {
    let id = UUID()
    let displayName: String
    let kind: MediaAttachmentKind?
    let outcome: Outcome

    enum Outcome {
        /// Captured — carries the inbox item for per-row Undo.
        case captured(itemUUID: String)
        /// Another system already owned it (ingest `.consumed`).
        case consumed(reason: String)
        case failed(String)
    }
}

@MainActor
@Observable
final class InboxDropIngestService {
    static let shared = InboxDropIngestService()

    private init() {}

    /// True while a batch is landing — capture surfaces show a quiet
    /// progress line instead of double-submitting.
    private(set) var isIngesting = false

    /// Per-file ceiling. Beyond this the capture fails honestly rather than
    /// stalling the panel or ballooning Application Support.
    static let maxFileBytes: Int64 = 100 * 1024 * 1024
    /// A dropped folder is enumerated one level deep, up to this many files.
    static let maxFolderFiles = 25
    /// Extracted text handed to the classifier is capped — it needs a gist,
    /// not the whole document.
    static let maxExtractedCharacters = 10_000

    // MARK: - Ingest

    /// Capture a batch. Each payload becomes its own inbox item (files route
    /// independently in triage); the shared `dropSessionId` groups the batch
    /// in provenance metadata.
    func ingest(_ payloads: [DropPayload], capturedFrom: String? = nil) async -> [DropCaptureResult] {
        guard !payloads.isEmpty else { return [] }
        isIngesting = true
        defer { isIngesting = false }

        let dropSessionId = UUID().uuidString
        var results: [DropCaptureResult] = []
        var attachedAny = false

        for payload in expandFolders(in: payloads, into: &results) {
            let result = await ingestOne(payload, dropSessionId: dropSessionId, capturedFrom: capturedFrom)
            if case .captured = result.outcome, result.kind != nil { attachedAny = true }
            results.append(result)
        }

        if attachedAny {
            AttachmentCloudStore.kick()
        }
        return results
    }

    // MARK: - Combined capture (thought + attachments)

    /// What happened to a staged thought-plus-files send.
    struct CombinedOutcome {
        let outcome: DropCaptureResult.Outcome
        let attachedCount: Int
        /// Files that couldn't be read or stored — reported, never silently dropped.
        let failedNames: [String]
    }

    /// One typed thought plus its staged files as a SINGLE inbox capture —
    /// the thought is the item's text and every file rides it as an owned
    /// attachment. The Capture Anywhere staging tray lands here; bare drops
    /// (no thought) keep the one-item-per-file path above.
    func ingestCombined(
        text: String,
        attachments: [DropPayload],
        capturedFrom: String? = nil
    ) async -> CombinedOutcome {
        isIngesting = true
        defer { isIngesting = false }

        let dropSessionId = UUID().uuidString
        var failedNames: [String] = []
        var drafts: [StoredAttachmentDraft] = []

        for payload in attachments {
            guard let resolved = resolveAttachmentBytes(payload, failedNames: &failedNames) else { continue }
            let kind = Self.attachmentKind(for: resolved.type)
            let attachmentId = UUID().uuidString
            do {
                let media = try CaptureMediaStorage.shared.store(
                    data: resolved.data,
                    capturedItemId: dropSessionId,
                    attachmentId: attachmentId,
                    originalFilename: resolved.filename,
                    mimeType: resolved.type.preferredMIMEType,
                    telegramFilePath: nil,
                    kind: kind
                )
                drafts.append(StoredAttachmentDraft(
                    attachmentId: attachmentId,
                    media: media,
                    byteCount: resolved.data.count,
                    type: resolved.type,
                    filename: resolved.filename,
                    kind: kind,
                    extracted: await extractText(from: resolved.data, type: resolved.type, kind: kind)
                ))
            } catch {
                failedNames.append(resolved.filename)
            }
        }

        guard !drafts.isEmpty else {
            return CombinedOutcome(
                outcome: .failed("Couldn't read the attached files"),
                attachedCount: 0,
                failedNames: failedNames
            )
        }

        let outcome = await ingestText(
            rawText: text, title: nil,
            dropSessionId: dropSessionId, capturedFrom: capturedFrom,
            attachmentUUIDs: drafts.map(\.attachmentId)
        )
        guard case .captured(let itemUUID) = outcome else {
            return CombinedOutcome(outcome: outcome, attachedCount: 0, failedNames: failedNames)
        }

        for draft in drafts {
            var attachment = MediaAttachment.makeLocal(
                owner: .inboxItem,
                ownerUUID: itemUUID,
                kind: draft.kind,
                localStoragePath: draft.media.originalPath,
                thumbnailPath: draft.media.thumbnailPath,
                originalFilename: draft.filename,
                mimeType: draft.type.preferredMIMEType,
                fileSize: Int64(draft.byteCount),
                metadata: metadataJSON([
                    "captureSource": "mac_drop",
                    "dropSessionId": dropSessionId,
                ])
            )
            attachment.uuid = draft.attachmentId
            attachment.extractedText = draft.extracted
            do {
                _ = try await MediaAttachmentRepository.shared.create(attachment)
            } catch {
                PersistenceHealth.note(
                    .writeFailure,
                    context: "InboxDropIngest.attachment(\(draft.attachmentId.prefix(8)))",
                    detail: String(describing: error)
                )
            }
        }
        AttachmentCloudStore.kick()

        return CombinedOutcome(
            outcome: .captured(itemUUID: itemUUID),
            attachedCount: drafts.count,
            failedNames: failedNames
        )
    }

    private struct StoredAttachmentDraft {
        let attachmentId: String
        let media: StoredCaptureMedia
        let byteCount: Int
        let type: UTType
        let filename: String
        let kind: MediaAttachmentKind
        let extracted: String?
    }

    /// Resolve a stage-able payload (file or data) to bytes; size caps and
    /// read failures land in `failedNames` honestly.
    private func resolveAttachmentBytes(
        _ payload: DropPayload,
        failedNames: inout [String]
    ) -> (data: Data, type: UTType, filename: String)? {
        switch payload {
        case .data(let data, let type, let suggestedName):
            let name = suggestedName ?? Self.defaultName(for: type)
            guard Int64(data.count) <= Self.maxFileBytes else {
                failedNames.append(name)
                return nil
            }
            return (data, type, name)
        case .file(let url, let suggestedName):
            let name = suggestedName ?? url.lastPathComponent
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               Int64(size) > Self.maxFileBytes {
                failedNames.append(name)
                return nil
            }
            guard let data = try? Data(contentsOf: url) else {
                failedNames.append(name)
                return nil
            }
            return (data, UTType(filenameExtension: url.pathExtension) ?? .data, name)
        case .text, .url:
            return nil
        }
    }

    // MARK: - Folder expansion

    /// Folders are enumerated one level deep up to the cap; an over-full
    /// folder becomes a failed result with an honest count, never a partial
    /// silent capture.
    private func expandFolders(in payloads: [DropPayload], into results: inout [DropCaptureResult]) -> [DropPayload] {
        var expanded: [DropPayload] = []
        for payload in payloads {
            guard case .file(let url, let suggestedName) = payload,
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                expanded.append(payload)
                continue
            }
            let children = (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            let files = children.filter {
                (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
            if files.isEmpty {
                results.append(DropCaptureResult(
                    displayName: suggestedName ?? url.lastPathComponent,
                    kind: nil,
                    outcome: .failed("That folder has no files in it")
                ))
            } else if files.count > Self.maxFolderFiles {
                results.append(DropCaptureResult(
                    displayName: suggestedName ?? url.lastPathComponent,
                    kind: nil,
                    outcome: .failed("That folder has \(files.count) files — drop a smaller selection")
                ))
            } else {
                expanded.append(contentsOf: files.map { .file(url: $0, suggestedName: nil) })
            }
        }
        return expanded
    }

    // MARK: - Single payload

    private func ingestOne(
        _ payload: DropPayload,
        dropSessionId: String,
        capturedFrom: String?
    ) async -> DropCaptureResult {
        switch payload {
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return DropCaptureResult(displayName: "Text", kind: nil, outcome: .failed("Nothing to capture"))
            }
            let display = trimmed.count > 40 ? "\u{201C}\(trimmed.prefix(40))…\u{201D}" : "\u{201C}\(trimmed)\u{201D}"
            let outcome = await ingestText(
                rawText: trimmed, title: nil,
                dropSessionId: dropSessionId, capturedFrom: capturedFrom, attachmentUUIDs: []
            )
            return DropCaptureResult(displayName: display, kind: nil, outcome: outcome)

        case .url(let url):
            let outcome = await ingestText(
                rawText: url.absoluteString, title: nil,
                dropSessionId: dropSessionId, capturedFrom: capturedFrom, attachmentUUIDs: []
            )
            return DropCaptureResult(displayName: url.host ?? url.absoluteString, kind: nil, outcome: outcome)

        case .data(let data, let type, let suggestedName):
            let name = suggestedName ?? Self.defaultName(for: type)
            return await ingestBytes(
                data: data, type: type, filename: name,
                dropSessionId: dropSessionId, capturedFrom: capturedFrom
            )

        case .file(let url, let suggestedName):
            let name = suggestedName ?? url.lastPathComponent

            // .webloc — a saved link, not a file worth attaching.
            if url.pathExtension.lowercased() == "webloc", let target = weblocURL(from: url) {
                let outcome = await ingestText(
                    rawText: target.absoluteString, title: nil,
                    dropSessionId: dropSessionId, capturedFrom: capturedFrom, attachmentUUIDs: []
                )
                return DropCaptureResult(displayName: target.host ?? name, kind: nil, outcome: outcome)
            }

            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               Int64(size) > Self.maxFileBytes {
                let mb = Int64(size) / (1024 * 1024)
                return DropCaptureResult(
                    displayName: name, kind: nil,
                    outcome: .failed("\(name) is \(mb) MB — the capture limit is 100 MB")
                )
            }
            guard let data = try? Data(contentsOf: url) else {
                return DropCaptureResult(displayName: name, kind: nil, outcome: .failed("Couldn't read \(name)"))
            }
            let type = UTType(filenameExtension: url.pathExtension) ?? .data
            return await ingestBytes(
                data: data, type: type, filename: name,
                dropSessionId: dropSessionId, capturedFrom: capturedFrom
            )
        }
    }

    // MARK: - Bytes → attachment + capture

    private func ingestBytes(
        data: Data,
        type: UTType,
        filename: String,
        dropSessionId: String,
        capturedFrom: String?
    ) async -> DropCaptureResult {
        guard Int64(data.count) <= Self.maxFileBytes else {
            let mb = Int64(data.count) / (1024 * 1024)
            return DropCaptureResult(
                displayName: filename, kind: nil,
                outcome: .failed("\(filename) is \(mb) MB — the capture limit is 100 MB")
            )
        }

        let kind = Self.attachmentKind(for: type)
        let attachmentId = UUID().uuidString

        let stored: StoredCaptureMedia
        do {
            stored = try CaptureMediaStorage.shared.store(
                data: data,
                capturedItemId: dropSessionId,
                attachmentId: attachmentId,
                originalFilename: filename,
                mimeType: type.preferredMIMEType,
                telegramFilePath: nil,
                kind: kind
            )
        } catch {
            return DropCaptureResult(displayName: filename, kind: kind, outcome: .failed("Couldn't save \(filename)"))
        }

        // Cheap extraction — enough signal for the classifier, never a blocker.
        let extracted = await extractText(from: data, type: type, kind: kind)

        let title = (filename as NSString).deletingPathExtension
        // Pictures attach as pictures: their OCR rides the attachment row for
        // search, never as the capture's text — transcription belongs to the
        // scan-pages pipeline alone.
        let isPicture = kind == .image || kind == .screenshot
        let rawText = isPicture ? title : (extracted.flatMap { $0.isEmpty ? nil : $0 } ?? title)
        let outcome = await ingestText(
            rawText: rawText, title: title,
            dropSessionId: dropSessionId, capturedFrom: capturedFrom, attachmentUUIDs: [attachmentId]
        )

        guard case .captured(let itemUUID) = outcome else {
            return DropCaptureResult(displayName: filename, kind: kind, outcome: outcome)
        }

        // The original, owned by the capture it became.
        var attachment = MediaAttachment.makeLocal(
            owner: .inboxItem,
            ownerUUID: itemUUID,
            kind: kind,
            localStoragePath: stored.originalPath,
            thumbnailPath: stored.thumbnailPath,
            originalFilename: filename,
            mimeType: type.preferredMIMEType,
            fileSize: Int64(data.count),
            metadata: metadataJSON([
                "captureSource": "mac_drop",
                "dropSessionId": dropSessionId,
            ])
        )
        attachment.uuid = attachmentId
        attachment.extractedText = extracted
        do {
            _ = try await MediaAttachmentRepository.shared.create(attachment)
        } catch {
            PersistenceHealth.note(
                .writeFailure,
                context: "InboxDropIngest.attachment(\(attachmentId.prefix(8)))",
                detail: String(describing: error)
            )
        }

        return DropCaptureResult(displayName: filename, kind: kind, outcome: .captured(itemUUID: itemUUID))
    }

    /// The one gate to the inbox — everything above is preparation.
    private func ingestText(
        rawText: String,
        title: String?,
        dropSessionId: String,
        capturedFrom: String?,
        attachmentUUIDs: [String]
    ) async -> DropCaptureResult.Outcome {
        var meta: [String: Any] = [
            "captureSource": "mac_drop",
            "dropSessionId": dropSessionId,
        ]
        if let capturedFrom, !capturedFrom.isEmpty {
            meta["capturedFrom"] = capturedFrom
        }
        if !attachmentUUIDs.isEmpty {
            meta["attachmentUUIDs"] = attachmentUUIDs
        }

        let outcome = await InboxIngestService.shared.ingest(
            .init(
                source: .quickCapture,
                rawText: rawText,
                title: title,
                metadata: metadataJSON(meta)
            )
        )
        switch outcome {
        case .enqueued(let item):
            return .captured(itemUUID: item.uuid)
        case .consumed(let reason):
            return .consumed(reason: reason)
        case .failed(let detail):
            return .failed(detail)
        }
    }

    // MARK: - Text extraction

    private func extractText(from data: Data, type: UTType, kind: MediaAttachmentKind) async -> String? {
        switch kind {
        case .textFile, .markdown:
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            return String(text.prefix(Self.maxExtractedCharacters))
        case .pdf:
            guard let document = PDFDocument(data: data) else { return nil }
            var text = ""
            for index in 0..<min(document.pageCount, 5) {
                guard let page = document.page(at: index), let pageText = page.string else { continue }
                text += pageText + "\n\n"
                if text.count >= Self.maxExtractedCharacters { break }
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : String(trimmed.prefix(Self.maxExtractedCharacters))
        case .image, .screenshot:
            // Fast on-device OCR only — the LLM pass is for page scans.
            guard let result = try? await VisionPageOCR.recognize(imageData: data) else { return nil }
            let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : String(trimmed.prefix(Self.maxExtractedCharacters))
        default:
            if type.conforms(to: .rtf), let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ) {
                let trimmed = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : String(trimmed.prefix(Self.maxExtractedCharacters))
            }
            return nil
        }
    }

    // MARK: - Type mapping

    static func attachmentKind(for type: UTType) -> MediaAttachmentKind {
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .pdf) { return .pdf }
        if type.identifier == "org.idpf.epub-container" { return .epub }
        if type.identifier.contains("markdown") || type.preferredFilenameExtension == "md" { return .markdown }
        // Spreadsheets before plainText — CSV/TSV conform to public.plain-text.
        if type.conforms(to: .spreadsheet)
            || type.conforms(to: .commaSeparatedText)
            || type.conforms(to: .tabSeparatedText)
            || ["xlsx", "xls", "xlsm", "xltx"].contains(type.preferredFilenameExtension ?? "") {
            return .spreadsheet
        }
        if type.conforms(to: .plainText) { return .textFile }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .rtf) || type.conforms(to: .content) { return .document }
        return .unknown
    }

    static func defaultName(for type: UTType) -> String {
        let ext = type.preferredFilenameExtension ?? "bin"
        let stamp = Self.nameStampFormatter.string(from: Date())
        if type.conforms(to: .image) { return "Pasted image \(stamp).\(ext)" }
        return "Capture \(stamp).\(ext)"
    }

    private static let nameStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()

    // MARK: - Helpers

    private func weblocURL(from fileURL: URL) -> URL? {
        guard let data = try? Data(contentsOf: fileURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any],
              let urlString = dict["URL"] as? String else { return nil }
        return URL(string: urlString)
    }

    private func metadataJSON(_ dict: [String: Any]) -> String? {
        (try? JSONSerialization.data(withJSONObject: dict))
            .flatMap { String(data: $0, encoding: .utf8) }
    }
}
