// CosmoOS/Data/Services/AttachmentTranscriptionWorker.swift
// The Mac finishes what the iPhone started: attachments saved with
// `needsLLMPass` (no AI key on the phone, offline, or saved mid-pass) get
// the careful vision-LLM transcription here once their bytes arrive via the
// Storage mirror. The transcript lands on the attachment; a still-pending
// inbox item's draft text upgrades too, so classification reads real words
// instead of a rough OCR draft or a "Page scan" placeholder.

import Foundation

extension Notification.Name {
    /// Posted when a media_attachments row arrives from the cloud (realtime).
    /// userInfo: ["uuid": String]. Live scan surfaces (the inquiry digitizing
    /// panel) observe this to show pages the moment the iPhone lands them.
    static let cosmoMediaAttachmentArrived = Notification.Name("cosmoMediaAttachmentArrived")
}

@MainActor
final class AttachmentTranscriptionWorker {
    static let shared = AttachmentTranscriptionWorker()

    private var inFlight = false
    private let maxAttempts = 3

    private init() {}

    /// Fire-and-forget from sync passes and realtime attachment arrivals.
    static func kick() {
        Task { @MainActor in
            await shared.run()
        }
    }

    func run() async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        let pending = (try? await MediaAttachmentRepository.shared.fetchNeedingTranscription()) ?? []
        for attachment in pending {
            let attempts = attachment.metadataIntValue("transcriptionAttempts") ?? 0
            guard attempts < maxAttempts else { continue }
            await process(attachment, attempts: attempts)
        }
    }

    private func process(_ attachment: MediaAttachment, attempts: Int) async {
        // Bytes may not have mirrored yet — silently retry on a later kick.
        guard let url = await AttachmentCloudStore.shared.localOriginalURL(for: attachment),
              let data = try? Data(contentsOf: url) else { return }

        do {
            let result = try await PageTranscriptionEngine.shared.transcribe(imageData: data)

            _ = try? await MediaAttachmentRepository.shared.trackedMutation(uuid: attachment.uuid) { mutable in
                mutable.transcriptText = result.transcript
                mutable.processingStatus = .transcribed
                var metadata = MediaAttachmentRepository.mergingMetadataKey(mutable.metadata, key: "needsLLMPass", value: false)
                metadata = MediaAttachmentRepository.mergingMetadataKey(metadata, key: "transcriptionConfidence", value: result.confidence)
                let marks = result.units.flatMap { $0.inkMarks ?? [] }
                if !marks.isEmpty {
                    metadata = MediaAttachmentRepository.mergingMetadataKey(metadata, key: "inkMarks", value: Array(Set(marks)).sorted())
                }
                mutable.metadata = metadata
                return true
            }

            await upgradeOwnerText(attachment: attachment, transcript: result.transcript)
        } catch {
            // Count the attempt so an unreadable page can't loop forever.
            _ = try? await MediaAttachmentRepository.shared.trackedMutation(uuid: attachment.uuid) { mutable in
                mutable.metadata = MediaAttachmentRepository.mergingMetadataKey(
                    mutable.metadata, key: "transcriptionAttempts", value: attempts + 1
                )
                if attempts + 1 >= self.maxAttempts {
                    mutable.metadata = MediaAttachmentRepository.mergingMetadataKey(
                        mutable.metadata, key: "needsLLMPass", value: false
                    )
                    mutable.processingStatus = .failed
                }
                return true
            }
            print("AttachmentTranscriptionWorker: pass \(attempts + 1) failed for \(attachment.uuid): \(error)")
        }
    }

    /// A pending inbox capture's text upgrades to the transcript — but only
    /// where the draft is provably machine text (the Vision OCR block or the
    /// photo-only placeholder), never over words the user wrote or edited.
    private func upgradeOwnerText(attachment: MediaAttachment, transcript: String) async {
        guard attachment.ownerType == MediaAttachmentOwner.inboxItem.rawValue else { return }
        guard let item = try? await InboxRepository.shared.fetch(uuid: attachment.ownerUUID),
              item.status == .pending else { return }

        guard let upgraded = Self.upgradedText(
            existing: item.rawText,
            visionDraft: attachment.extractedText,
            transcript: transcript
        ) else { return }

        try? await InboxRepository.shared.upgradeRawText(uuid: item.uuid, to: upgraded)
    }

    static func upgradedText(existing: String, visionDraft: String?, transcript: String) -> String? {
        let trimmedExisting = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        // Photo-only placeholder → the transcript IS the capture.
        if trimmedExisting.hasPrefix("Page scan") { return transcript }
        guard let visionDraft, !visionDraft.isEmpty else { return nil }
        if trimmedExisting == visionDraft.trimmingCharacters(in: .whitespacesAndNewlines) { return transcript }
        if existing.contains(visionDraft) {
            return existing.replacingOccurrences(of: visionDraft, with: transcript)
        }
        return nil
    }
}

private extension MediaAttachment {
    func metadataIntValue(_ key: String) -> Int? {
        guard let metadata, let data = metadata.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return dict[key] as? Int
    }
}
