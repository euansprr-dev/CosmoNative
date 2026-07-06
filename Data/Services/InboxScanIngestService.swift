// CosmoOS/Data/Services/InboxScanIngestService.swift
// The Mac's local page-scan intake — Continuity Camera shots, uploaded
// images, and Command-K scans all converge here: bytes stored, on-device
// line geometry, the careful vision-LLM transcription, then ONE inbox
// capture through the standard ingest choke point with the originals
// attached. The inquiry sibling is InquiryScanController; this one feeds
// triage instead of a live session.

import Foundation
import Observation

@MainActor
@Observable
final class InboxScanIngestService {
    static let shared = InboxScanIngestService()

    private init() {}

    enum Outcome {
        case captured(InboxItem, pageCount: Int)
        case failed(String)
    }

    /// True while a batch is digitizing — capture surfaces show a quiet
    /// progress line instead of double-submitting.
    private(set) var isIngesting = false

    func ingest(images: [Data]) async -> Outcome {
        guard !images.isEmpty else { return .failed("No images to scan") }
        isIngesting = true
        defer { isIngesting = false }

        let scanSessionId = UUID().uuidString
        let legend = UserDefaults.standard.string(forKey: "cosmoInkLegend")
        let context = PageTranscriptionContext(inkLegend: (legend?.isEmpty == false) ? legend : nil)

        struct Page {
            let uuid: String
            let stored: StoredCaptureMedia
            let byteCount: Int
            let ocr: VisionPageOCR.Result?
            let transcription: PageTranscription?
        }

        var pages: [Page] = []
        for imageData in images {
            let uuid = UUID().uuidString
            guard let stored = try? CaptureMediaStorage.shared.store(
                data: imageData,
                capturedItemId: scanSessionId,
                attachmentId: uuid,
                originalFilename: nil,
                mimeType: "image/jpeg",
                telegramFilePath: nil,
                kind: .pageScan
            ) else { continue }
            let ocr = try? await VisionPageOCR.recognize(imageData: imageData)
            let transcription = try? await PageTranscriptionEngine.shared.transcribe(
                imageData: imageData, context: context
            )
            pages.append(Page(
                uuid: uuid, stored: stored, byteCount: imageData.count,
                ocr: ocr, transcription: transcription
            ))
        }
        guard !pages.isEmpty else { return .failed("Couldn't save the images") }

        // Capture text: transcript wins, Vision draft covers an offline LLM,
        // an honest placeholder covers an unreadable page.
        let blocks = pages.compactMap { page -> String? in
            let text = page.transcription?.transcript ?? page.ocr?.text
            return text?.isEmpty == false ? text : nil
        }
        let rawText = blocks.isEmpty
            ? (pages.count == 1 ? "Page scan" : "Page scan (\(pages.count) pages)")
            : blocks.joined(separator: "\n\n")

        let itemMetadata: [String: Any] = [
            "captureSource": "mac_scan",
            "attachmentUUIDs": pages.map(\.uuid),
        ]
        let metadataJSON = (try? JSONSerialization.data(withJSONObject: itemMetadata))
            .flatMap { String(data: $0, encoding: .utf8) }

        let outcome = await InboxIngestService.shared.ingest(
            .init(source: .quickCapture, rawText: rawText, metadata: metadataJSON)
        )
        guard case .enqueued(let item) = outcome else {
            if case .failed(let detail) = outcome { return .failed(detail) }
            return .failed("The capture was consumed by another system")
        }

        // The originals, owned by the capture they became.
        for (index, page) in pages.enumerated() {
            var pageMetadata: [String: Any] = [
                "pageIndex": index,
                "scanSessionId": scanSessionId,
            ]
            if let ocr = page.ocr, !ocr.lines.isEmpty,
               let encoded = VisionPageOCR.encodeLines(ocr.lines) {
                pageMetadata["visionLines"] = encoded
            }
            if let transcription = page.transcription {
                pageMetadata["transcriptionConfidence"] = transcription.confidence
                let marks = transcription.units.flatMap { $0.inkMarks ?? [] }
                if !marks.isEmpty { pageMetadata["inkMarks"] = Array(Set(marks)).sorted() }
            } else {
                // The LLM pass failed here — the transcription worker retries.
                pageMetadata["needsLLMPass"] = true
            }
            let pageMetadataJSON = (try? JSONSerialization.data(withJSONObject: pageMetadata))
                .flatMap { String(data: $0, encoding: .utf8) }

            var attachment = MediaAttachment.makeLocal(
                owner: .inboxItem,
                ownerUUID: item.uuid,
                kind: .pageScan,
                localStoragePath: page.stored.originalPath,
                thumbnailPath: page.stored.thumbnailPath,
                mimeType: "image/jpeg",
                fileSize: Int64(page.byteCount),
                metadata: pageMetadataJSON
            )
            attachment.uuid = page.uuid
            attachment.extractedText = page.ocr?.text
            attachment.transcriptText = page.transcription?.transcript
            if page.transcription != nil { attachment.processingStatus = .transcribed }
            do {
                _ = try await MediaAttachmentRepository.shared.create(attachment)
            } catch {
                PersistenceHealth.note(.writeFailure, context: "InboxScanIngest.attachment(\(page.uuid.prefix(8)))", detail: String(describing: error))
            }
        }
        AttachmentCloudStore.kick()

        return .captured(item, pageCount: pages.count)
    }
}
