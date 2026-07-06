// CosmoOS/UI/FocusMode/Inquiry/Scan/InquiryScanController.swift
// One scan session inside an inquiry. Pages arrive two ways — image files
// dropped on this Mac, or the iPhone streaming a "Scan with iPhone" request —
// and converge on one pipeline: each page becomes an attachment on ONE
// "page_scan" source atom, gets the vision-LLM transcription with session
// vocabulary, and its units enter the SAME live-routing pipeline as typed
// captures. The digitizing panel renders this controller's state.

import AppKit
import SwiftUI

@MainActor
@Observable
final class InquiryScanController {

    struct ScanPage: Identifiable {
        enum State: Equatable {
            case storing
            case transcribing
            case routing
            case done(unitCount: Int)
            case failed(String)
        }

        let id: String                     // MediaAttachment uuid
        var thumbnail: NSImage?
        var state: State = .storing
        var pageIndex: Int
    }

    private(set) var pages: [ScanPage] = []
    /// True while the panel should float above the thinking bar.
    var isPanelVisible = false

    /// The in-flight "Scan with iPhone" request, when one exists.
    private(set) var phoneRequest: CaptureRequest?
    /// Surfaced by the panel when the push could not be sent.
    private(set) var phoneRequestNote: String?

    let scanSessionId = UUID().uuidString
    private(set) var scanSource: Atom?
    private weak var viewModel: InquiryWorkspaceViewModel?

    private var processedRemoteUUIDs: Set<String> = []
    private var remoteObservers: [NSObjectProtocol] = []

    var isBusy: Bool {
        pages.contains {
            $0.state == .storing || $0.state == .transcribing || $0.state == .routing
        }
    }

    /// The panel shows a waiting line while the phone hasn't sent pages yet.
    var isWaitingForPhone: Bool {
        guard let phoneRequest else { return false }
        return (phoneRequest.status == .pending || phoneRequest.status == .claimed) && pages.isEmpty
    }

    func configure(viewModel: InquiryWorkspaceViewModel) {
        self.viewModel = viewModel
    }

    /// Called when the study shell goes away — observers must not outlive
    /// the session (each session gets a fresh controller).
    func teardown() {
        for observer in remoteObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        remoteObservers.removeAll()
    }

    // MARK: - Intake: files on this Mac

    func ingestImageFiles(_ urls: [URL]) {
        let images = urls.compactMap { try? Data(contentsOf: $0) }
        ingestImages(images)
    }

    func ingestImages(_ images: [Data]) {
        guard !images.isEmpty else { return }
        isPanelVisible = true
        for data in images {
            let uuid = UUID().uuidString
            var page = ScanPage(id: uuid, pageIndex: pages.count)
            page.thumbnail = NSImage(data: data)
            pages.append(page)
            Task { await processLocal(uuid: uuid, imageData: data) }
        }
    }

    // MARK: - Intake: the iPhone

    /// Create the relay request, push at the phone, and start watching for
    /// its pages. Returns a user-facing note when the push couldn't be sent
    /// (the realtime path still works if the phone is open).
    func requestPhoneScan() async {
        guard let viewModel else { return }
        isPanelVisible = true
        phoneRequestNote = nil

        if phoneRequest == nil || phoneRequest?.isFresh != true {
            let request = CaptureRequest.new(
                kind: .inquiryScan,
                scanSessionId: scanSessionId,
                deepDiveUUID: viewModel.deepDive?.uuid,
                sessionUUID: viewModel.session.uuid,
                questionUUID: viewModel.activeQuestionUUID,
                questionTitle: viewModel.activeQuestionTitle,
                deepDiveTitle: viewModel.deepDive?.title
            )
            do {
                phoneRequest = try await CaptureRequestRepository.shared.create(request)
            } catch {
                phoneRequestNote = "Couldn't create the scan request: \(error.localizedDescription)"
                return
            }
        }
        startObservingRemote()

        guard let phoneRequest else { return }
        do {
            try await PushSenderService.shared.sendScanRequest(phoneRequest)
        } catch {
            // The request row still syncs — an open Cosmo on the phone picks
            // it up via realtime. Be honest about the missing push.
            phoneRequestNote = error.localizedDescription
        }
    }

    private func startObservingRemote() {
        guard remoteObservers.isEmpty else { return }
        remoteObservers.append(NotificationCenter.default.addObserver(
            forName: .cosmoMediaAttachmentArrived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let uuid = notification.userInfo?["uuid"] as? String else { return }
            Task { @MainActor in
                await self?.consumeRemoteAttachment(uuid: uuid)
            }
        })
        remoteObservers.append(NotificationCenter.default.addObserver(
            forName: .cosmoScanRequestUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshPhoneRequest()
            }
        })
    }

    private func refreshPhoneRequest() async {
        guard let phoneRequest else { return }
        self.phoneRequest = (try? await CaptureRequestRepository.shared.fetch(uuid: phoneRequest.uuid)) ?? phoneRequest
    }

    /// A media_attachments row arrived from the cloud — if it belongs to this
    /// scan session, pull its bytes and run the shared pipeline.
    func consumeRemoteAttachment(uuid: String) async {
        guard let phoneRequest else { return }
        guard !processedRemoteUUIDs.contains(uuid) else { return }
        guard let attachment = try? await MediaAttachmentRepository.shared.fetch(uuid: uuid),
              (attachment.metadataStringValue("scanSessionId")) == phoneRequest.scanSessionId else { return }
        processedRemoteUUIDs.insert(uuid)

        let pageIndex = pages.count
        pages.append(ScanPage(id: uuid, pageIndex: pageIndex))
        isPanelVisible = true

        // The row can beat the blob to the cloud — wait for the mirror.
        var imageData: Data?
        for _ in 0..<30 {
            if let fresh = try? await MediaAttachmentRepository.shared.fetch(uuid: uuid),
               let url = await AttachmentCloudStore.shared.localOriginalURL(for: fresh),
               let data = try? Data(contentsOf: url) {
                imageData = data
                break
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        guard let imageData else {
            update(uuid) { $0.state = .failed("The page never finished uploading") }
            return
        }
        update(uuid) { $0.thumbnail = NSImage(data: imageData) }

        // Re-home onto the scan source; the Mac owns the careful pass now.
        guard let source = try? await ensureScanSource() else {
            update(uuid) { $0.state = .failed("Couldn't create the scan source") }
            return
        }
        _ = try? await MediaAttachmentRepository.shared.trackedMutation(uuid: uuid) { mutable in
            mutable.ownerType = MediaAttachmentOwner.sourceAtom.rawValue
            mutable.ownerUUID = source.uuid
            mutable.metadata = MediaAttachmentRepository.mergingMetadataKey(
                mutable.metadata, key: "needsLLMPass", value: false
            )
            return true
        }
        _ = try? await InquiryRepository.shared.appendToScanSource(
            uuid: source.uuid, pageAttachmentUUIDs: [uuid], transcript: nil
        )

        await digitize(uuid: uuid, imageData: imageData, source: source, runVisionPass: false)
    }

    func dismissPanel() {
        isPanelVisible = false
        if !isBusy { pages.removeAll() }
        if let phoneRequest, phoneRequest.status == .pending {
            Task { try? await CaptureRequestRepository.shared.cancel(uuid: phoneRequest.uuid) }
            self.phoneRequest = nil
        }
    }

    // MARK: - Pipeline (local files)

    private func processLocal(uuid: String, imageData: Data) async {
        // 1. Persist bytes locally (original + thumbnail).
        let stored: StoredCaptureMedia
        do {
            stored = try CaptureMediaStorage.shared.store(
                data: imageData,
                capturedItemId: scanSessionId,
                attachmentId: uuid,
                originalFilename: nil,
                mimeType: "image/jpeg",
                telegramFilePath: nil,
                kind: .pageScan
            )
        } catch {
            update(uuid) { $0.state = .failed("Couldn't save the image") }
            return
        }

        // 2. One source object per scan session — created on the first page.
        let source: Atom
        do {
            source = try await ensureScanSource()
            _ = try await InquiryRepository.shared.appendToScanSource(
                uuid: source.uuid, pageAttachmentUUIDs: [uuid], transcript: nil
            )
        } catch {
            update(uuid) { $0.state = .failed("Couldn't create the scan source") }
            return
        }

        // 3. The attachment row (synced; blob mirrors via AttachmentCloudStore).
        let pageIndex = pages.first(where: { $0.id == uuid })?.pageIndex ?? 0
        let attachmentMetadata: [String: Any] = [
            "pageIndex": pageIndex,
            "scanSessionId": scanSessionId,
        ]
        let metadataJSON = (try? JSONSerialization.data(withJSONObject: attachmentMetadata))
            .flatMap { String(data: $0, encoding: .utf8) }
        var attachment = MediaAttachment.makeLocal(
            owner: .sourceAtom,
            ownerUUID: source.uuid,
            kind: .pageScan,
            localStoragePath: stored.originalPath,
            thumbnailPath: stored.thumbnailPath,
            mimeType: "image/jpeg",
            fileSize: Int64(imageData.count),
            metadata: metadataJSON
        )
        attachment.uuid = uuid
        do {
            _ = try await MediaAttachmentRepository.shared.create(attachment)
        } catch {
            update(uuid) { $0.state = .failed("Couldn't record the page") }
            return
        }
        AttachmentCloudStore.kick()

        await digitize(uuid: uuid, imageData: imageData, source: source, runVisionPass: true)
    }

    // MARK: - Pipeline (shared tail: geometry → transcript → routing)

    private func digitize(uuid: String, imageData: Data, source: Atom, runVisionPass: Bool) async {
        guard let viewModel else { return }
        update(uuid) { $0.state = .transcribing }

        // Line geometry for provenance highlighting (the iPhone already did
        // this for relay pages).
        if runVisionPass,
           let ocr = try? await VisionPageOCR.recognize(imageData: imageData), !ocr.lines.isEmpty {
            _ = try? await MediaAttachmentRepository.shared.trackedMutation(uuid: uuid) { mutable in
                mutable.extractedText = ocr.text
                if let encoded = VisionPageOCR.encodeLines(ocr.lines) {
                    mutable.metadata = MediaAttachmentRepository.mergingMetadataKey(
                        mutable.metadata, key: "visionLines", value: encoded
                    )
                }
                return true
            }
        }

        // The careful pass — session vocabulary keeps domain terms honest.
        let transcription: PageTranscription
        do {
            transcription = try await PageTranscriptionEngine.shared.transcribe(
                imageData: imageData,
                context: viewModel.pageTranscriptionContext()
            )
        } catch {
            update(uuid) { $0.state = .failed("Couldn't read the page") }
            return
        }

        // Transcript lands on the attachment + grows the source body.
        try? await MediaAttachmentRepository.shared.updateTranscript(
            uuid: uuid, transcript: transcription.transcript, status: .transcribed
        )
        _ = try? await InquiryRepository.shared.appendToScanSource(
            uuid: source.uuid, pageAttachmentUUIDs: [], transcript: transcription.transcript
        )

        // Units enter the live-routing pipeline — the same brain as typed
        // captures, with ink marks riding as bias hints.
        update(uuid) { $0.state = .routing }
        var routed = 0
        for unit in transcription.units {
            if await viewModel.ingestScannedUnit(
                text: unit.text,
                inkMarks: unit.inkMarks,
                scanSource: source,
                attachmentUUIDs: [uuid]
            ) != nil {
                routed += 1
            }
        }
        // Sketches survive as thoughts too: the description routes like any
        // unit, and the page original stays one tap away through provenance.
        for diagram in transcription.diagrams ?? [] {
            if await viewModel.ingestScannedUnit(
                text: "Diagram — \(diagram.description)",
                inkMarks: nil,
                scanSource: source,
                attachmentUUIDs: [uuid]
            ) != nil {
                routed += 1
            }
        }
        update(uuid) { $0.state = .done(unitCount: routed) }
    }

    private func ensureScanSource() async throws -> Atom {
        if let scanSource { return scanSource }
        guard let viewModel else { throw CocoaError(.userCancelled) }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let title = "Page scan · \(formatter.string(from: Date()))"
        let source = try await InquiryRepository.shared.createScanSource(
            title: title,
            scanSessionId: scanSessionId,
            pageAttachmentUUIDs: [],
            transcript: nil
        )
        scanSource = source
        viewModel.registerScanSource(source)
        return source
    }

    private func update(_ uuid: String, _ mutate: (inout ScanPage) -> Void) {
        guard let index = pages.firstIndex(where: { $0.id == uuid }) else { return }
        mutate(&pages[index])
    }
}

private extension MediaAttachment {
    func metadataStringValue(_ key: String) -> String? {
        guard let metadata, let data = metadata.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return dict[key] as? String
    }
}
