// CosmoOS/UI/CaptureOverlay/CaptureOverlayViewModel.swift
// State for the Capture Anywhere panel: one capture session per summon —
// typed thoughts, drops, pastes, scans all land as tray rows with per-row
// Undo. The panel never closes on capture; Esc ends the session.
// July 2026 — Capture Anywhere

import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class CaptureOverlayViewModel {

    // MARK: - Session

    /// The app the user was in when they summoned the panel — provenance.
    private(set) var capturedFrom: String?

    var captureText = ""
    /// Bumped by the controller when the panel becomes key — focuses the field.
    var captureFieldFocusTick = 0

    /// Live lane matching for the capture field — the `Groceries:` highlight
    /// and the ghost-text autocomplete (iPhone capture-field parity).
    let laneAssist = LaneCaptureAssist()

    /// Everything captured (or attempted) this session, newest last.
    var sessionEntries: [SessionEntry] = []

    /// Honest failure line for panel-level problems (scan/pushes), separate
    /// from per-row failures in the tray.
    var errorLine: String?

    struct SessionEntry: Identifiable {
        let id = UUID()
        var displayName: String
        var kind: MediaAttachmentKind?
        var state: State
        /// path|size fingerprint for same-session duplicate coalescing.
        var fingerprint: String?
        /// Where a lane-routed capture landed ("→ Groceries") — shown in
        /// place of the default "→ Inbox" trailing label.
        var destinationLabel: String? = nil

        enum State {
            /// A file promise is still streaming in.
            case receiving
            /// Captured — `itemUUID` powers Undo (nil for non-undoable rows
            /// like a phone-scan request confirmation).
            case captured(itemUUID: String?)
            case consumed(reason: String)
            case failed(String)
            case undone
        }
    }

    // MARK: - Drag state

    var isDropTargeted = false
    var dragPreview: CaptureDragPreview?
    /// File promises currently streaming in — dismissal is suppressed.
    var receivingCount = 0

    // MARK: - Staged attachments

    /// Files and images dropped into the panel wait here — visible as tiles
    /// in the well — until the user sends them, so a typed thought and its
    /// files can land as ONE linked capture. Text and link drops still
    /// capture instantly; menu-bar drops never stage.
    var stagedAttachments: [StagedAttachment] = []

    struct StagedAttachment: Identifiable {
        let id = UUID()
        let payload: DropPayload
        let displayName: String
        let kind: MediaAttachmentKind
        /// path|size fingerprint so re-dropping the same file doesn't double-stage.
        let fingerprint: String?
        var thumbnail: NSImage?

        var isImage: Bool { kind == .image || kind == .screenshot }
    }

    // MARK: - Sources

    /// Bumped to pop the Continuity Camera device menu.
    var continuityCameraMenuTick = 0
    var showFileImporter = false

    /// True when the global hotkey couldn't register (Accessibility trust
    /// missing) — the panel shows a teaching row with the fix.
    var accessibilityHintNeeded = false

    var isBusy: Bool {
        InboxScanIngestService.shared.isIngesting
            || InboxDropIngestService.shared.isIngesting
            || receivingCount > 0
    }

    var capturedCount: Int {
        sessionEntries.filter {
            if case .captured = $0.state { return true }
            return false
        }.count
    }

    // MARK: - Session lifecycle

    /// Called by the controller on every show — a summon is a fresh session.
    func beginSession(capturedFrom: String?) {
        self.capturedFrom = capturedFrom
        captureText = ""
        sessionEntries = []
        stagedAttachments = []
        errorLine = nil
        isDropTargeted = false
        dragPreview = nil
        receivingCount = 0
        accessibilityHintNeeded = !HotkeyManager.shared.isRegistered
        laneAssist.reset()
        Task { await laneAssist.loadLanes() }
    }

    // MARK: - Text capture

    /// Every keystroke runs through the lane assist — it returns the full
    /// replacement text when a trailing space accepts the live suggestion.
    func captureTextChanged() {
        if let completed = laneAssist.textChanged(captureText) {
            captureText = completed
        }
    }

    func submitText() async {
        // Staged files present — Enter sends the bundle: the thought and its
        // attachments leave as one linked capture.
        if !stagedAttachments.isEmpty {
            await sendStaged()
            return
        }
        let text = captureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        captureText = ""
        laneAssist.reset()

        // A resolved `alias:` prefix routes straight into that lane — the
        // same choke point as ⌘K and Telegram, never the triage queue.
        if let match = await LaneCaptureAssist.resolvedMatch(for: text), !match.remainder.isEmpty {
            await routeToLane(text: text, match: match)
            return
        }
        await ingest([.text(text)])
    }

    private func routeToLane(text: String, match: LaneCaptureAssist.LaneMatch) async {
        let outcome = await TelegramCaptureRouter.shared.routeTelegramCapture(
            text: text,
            chatId: "capture-overlay",
            messageId: nil,
            sender: "Capture Anywhere"
        )
        switch outcome {
        case .handled:
            let body = match.remainder
            let display = body.count > 40 ? "\u{201C}\(body.prefix(40))…\u{201D}" : "\u{201C}\(body)\u{201D}"
            sessionEntries.append(SessionEntry(
                displayName: display,
                kind: nil,
                state: .captured(itemUUID: nil),
                fingerprint: nil,
                destinationLabel: "→ \(match.lane.name)"
            ))
        case .notCaptureCommand:
            // The router's grammar declined the prefix — never drop the words.
            await ingest([.text(text)])
        }
    }

    // MARK: - Drop / paste / picker intake

    /// The drop funnel with staging manners: panel drops stage files and
    /// images for a combined send; text and links — and every menu-bar drop
    /// (`staging: false`) — capture instantly.
    func receive(_ payloads: [DropPayload], staging: Bool) async {
        guard staging else {
            await ingest(payloads)
            return
        }
        var instant: [DropPayload] = []
        for payload in payloads {
            switch payload {
            case .text, .url:
                instant.append(payload)
            case .file(let url, _):
                // Folders and .webloc links keep the instant path — folders
                // expand to many items, weblocs are really links.
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                if isDirectory || url.pathExtension.lowercased() == "webloc" {
                    instant.append(payload)
                } else {
                    stage(payload)
                }
            case .data:
                stage(payload)
            }
        }
        if !instant.isEmpty {
            await ingest(instant)
        }
    }

    /// Stage one file/data payload as a tile. Over-limit files fail honestly
    /// here, before send; re-drops of an already-staged file are no-ops.
    private func stage(_ payload: DropPayload) {
        switch payload {
        case .file(let url, let suggestedName):
            let name = suggestedName ?? url.lastPathComponent
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            guard size <= InboxDropIngestService.maxFileBytes else {
                errorLine = "\(name) is \(size / (1024 * 1024)) MB — the capture limit is 100 MB"
                return
            }
            let fingerprint = "\(url.path)|\(size)"
            guard !stagedAttachments.contains(where: { $0.fingerprint == fingerprint }) else { return }
            let type = UTType(filenameExtension: url.pathExtension) ?? .data
            let staged = StagedAttachment(
                payload: payload,
                displayName: name,
                kind: InboxDropIngestService.attachmentKind(for: type),
                fingerprint: fingerprint
            )
            stagedAttachments.append(staged)
            if staged.isImage { loadThumbnail(for: staged.id, source: .url(url)) }

        case .data(let data, let type, let suggestedName):
            guard Int64(data.count) <= InboxDropIngestService.maxFileBytes else {
                errorLine = "That file is \(Int64(data.count) / (1024 * 1024)) MB — the capture limit is 100 MB"
                return
            }
            // Name it now so the eventual capture wears the same name the tile shows.
            let name = suggestedName ?? InboxDropIngestService.defaultName(for: type)
            let staged = StagedAttachment(
                payload: .data(data, type: type, suggestedName: name),
                displayName: name,
                kind: InboxDropIngestService.attachmentKind(for: type),
                fingerprint: nil
            )
            stagedAttachments.append(staged)
            if staged.isImage { loadThumbnail(for: staged.id, source: .data(data)) }

        case .text, .url:
            break
        }
    }

    func removeStaged(_ id: UUID) {
        stagedAttachments.removeAll { $0.id == id }
    }

    func clearStaged() {
        stagedAttachments = []
    }

    /// The send button: staged files plus whatever's in the thought field.
    /// With a thought they leave as ONE linked capture; without one each
    /// file is its own capture, exactly as a bare drop was.
    func sendStaged() async {
        let staged = stagedAttachments
        guard !staged.isEmpty else { return }
        let thought = captureText.trimmingCharacters(in: .whitespacesAndNewlines)
        stagedAttachments = []
        captureText = ""
        laneAssist.reset()

        guard !thought.isEmpty else {
            await ingest(staged.map(\.payload))
            return
        }

        let combined = await InboxDropIngestService.shared.ingestCombined(
            text: thought,
            attachments: staged.map(\.payload),
            capturedFrom: capturedFrom
        )
        if !combined.failedNames.isEmpty {
            errorLine = "Couldn't attach \(combined.failedNames.joined(separator: ", "))"
        }
        let state: SessionEntry.State
        switch combined.outcome {
        case .captured(let itemUUID): state = .captured(itemUUID: itemUUID)
        case .consumed(let reason): state = .consumed(reason: reason)
        case .failed(let detail): state = .failed(detail)
        }
        // A total failure keeps the thought — restore it, never drop the words.
        if case .failed = combined.outcome, combined.attachedCount == 0 {
            captureText = thought
        }
        let display = thought.count > 40 ? "\u{201C}\(thought.prefix(40))…\u{201D}" : "\u{201C}\(thought)\u{201D}"
        var destination: String?
        if case .captured = combined.outcome {
            destination = "→ Inbox · \(combined.attachedCount) attached"
        }
        sessionEntries.append(SessionEntry(
            displayName: display,
            kind: staged.first?.kind,
            state: state,
            fingerprint: nil,
            destinationLabel: destination
        ))
    }

    /// The panel is closing with unsent staged files — capture them
    /// individually (the bare-drop path) rather than dropping bytes on the
    /// floor. Esc never loses a capture; Clear is the explicit discard.
    func flushStagedOnClose() {
        let staged = stagedAttachments
        guard !staged.isEmpty else { return }
        stagedAttachments = []
        Task { await ingest(staged.map(\.payload)) }
    }

    // MARK: - Staged thumbnails

    private enum ThumbnailSource: Sendable {
        case url(URL)
        case data(Data)
    }

    private func loadThumbnail(for id: UUID, source: ThumbnailSource) {
        Task {
            let image = await Task.detached(priority: .utility) { () -> NSImage? in
                let cgSource: CGImageSource?
                switch source {
                case .url(let url): cgSource = CGImageSourceCreateWithURL(url as CFURL, nil)
                case .data(let data): cgSource = CGImageSourceCreateWithData(data as CFData, nil)
                }
                guard let cgSource else { return nil }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 160,
                ]
                guard let cg = CGImageSourceCreateThumbnailAtIndex(cgSource, 0, options as CFDictionary) else { return nil }
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }.value
            guard let image, let index = stagedAttachments.firstIndex(where: { $0.id == id }) else { return }
            stagedAttachments[index].thumbnail = image
        }
    }

    /// The one funnel: resolve → ingest → tray rows. Same-session duplicates
    /// (same file path + size) coalesce onto their existing row.
    func ingest(_ payloads: [DropPayload]) async {
        var fresh: [DropPayload] = []
        for payload in payloads {
            if let fingerprint = Self.fingerprint(for: payload),
               let index = sessionEntries.firstIndex(where: { $0.fingerprint == fingerprint }),
               case .captured = sessionEntries[index].state {
                // Already captured this session — surface the row, don't re-ingest.
                let entry = sessionEntries.remove(at: index)
                sessionEntries.append(entry)
                continue
            }
            fresh.append(payload)
        }
        guard !fresh.isEmpty else { return }

        let fingerprints = fresh.map(Self.fingerprint(for:))
        let results = await InboxDropIngestService.shared.ingest(fresh, capturedFrom: capturedFrom)
        for (index, result) in results.enumerated() {
            let state: SessionEntry.State
            switch result.outcome {
            case .captured(let itemUUID): state = .captured(itemUUID: itemUUID)
            case .consumed(let reason): state = .consumed(reason: reason)
            case .failed(let detail): state = .failed(detail)
            }
            sessionEntries.append(SessionEntry(
                displayName: result.displayName,
                kind: result.kind,
                state: state,
                fingerprint: index < fingerprints.count ? fingerprints[index] : nil
            ))
        }
    }

    private static func fingerprint(for payload: DropPayload) -> String? {
        guard case .file(let url, _) = payload else { return nil }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return "\(url.path)|\(size)"
    }

    // MARK: - Paste

    var clipboardHasContent: Bool {
        let pasteboard = NSPasteboard.general
        guard let types = pasteboard.types else { return false }
        return types.contains(.fileURL) || types.contains(.tiff) || types.contains(.png)
            || types.contains(.string) || types.contains(.URL)
    }

    /// ⌘V while the panel is key and no text field owns focus. Pasted files
    /// and images stage like drops; pasted text and links capture instantly.
    func handlePaste() async {
        let pasteboard = NSPasteboard.general

        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            await receive(urls.map { .file(url: $0, suggestedName: nil) }, staging: true)
            return
        }

        if let data = pasteboard.data(forType: .png) {
            await receive([.data(data, type: .png, suggestedName: nil)], staging: true)
            return
        }
        if let data = pasteboard.data(forType: .tiff) {
            await receive([.data(data, type: .tiff, suggestedName: nil)], staging: true)
            return
        }

        if let string = pasteboard.string(forType: .string) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if let url = URL(string: trimmed), let scheme = url.scheme,
               ["http", "https"].contains(scheme.lowercased()) {
                await ingest([.url(url)])
            } else {
                await ingest([.text(trimmed)])
            }
        }
    }

    // MARK: - Scans (the page-scan pipeline, not the drop pipeline)

    /// Continuity Camera shots and uploaded page images — the careful
    /// OCR + LLM transcription path, landing as one capture.
    func ingestScanImages(_ images: [Data]) async {
        guard !images.isEmpty else { return }
        errorLine = nil
        switch await InboxScanIngestService.shared.ingest(images: images) {
        case .captured(let item, let pageCount):
            sessionEntries.append(SessionEntry(
                displayName: pageCount == 1 ? "Page scan" : "Page scan (\(pageCount) pages)",
                kind: .pageScan,
                state: .captured(itemUUID: item.uuid),
                fingerprint: nil
            ))
        case .failed(let detail):
            errorLine = "Couldn't digitize the scan — \(detail)"
        }
    }

    /// "Scan with iPhone": a capture_request row + an APNs push. The pages
    /// come back as a normal inbox capture from the phone's side.
    func requestPhoneScan() async {
        errorLine = nil
        do {
            let request = try await CaptureRequestRepository.shared.create(
                .new(kind: .inboxScan, scanSessionId: UUID().uuidString)
            )
            try await PushSenderService.shared.sendScanRequest(request)
            sessionEntries.append(SessionEntry(
                displayName: "Scan requested — check your iPhone",
                kind: .pageScan,
                state: .captured(itemUUID: nil),
                fingerprint: nil
            ))
        } catch {
            errorLine = error.localizedDescription
        }
    }

    // MARK: - Undo

    /// Per-row Undo dismisses the inbox item (restorable from Recently
    /// dismissed — never a hard delete).
    func undo(_ entry: SessionEntry) async {
        guard case .captured(let itemUUID) = entry.state, let itemUUID else { return }
        guard let index = sessionEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        do {
            try await InboxRepository.shared.dismiss(uuid: itemUUID)
            sessionEntries[index].state = .undone
        } catch {
            errorLine = "Couldn't undo — \(error.localizedDescription)"
        }
    }
}

// MARK: - Drag preview

/// What's hovering over the panel — built from the drag pasteboard *before*
/// release so the drop well can show what's about to land.
struct CaptureDragPreview: Equatable {
    struct Item: Equatable, Identifiable {
        let id: Int
        var name: String
        var systemImage: String
    }

    var items: [Item]
    var totalCount: Int
    /// True when releasing will stage into the well (files/images over the
    /// panel) rather than capture instantly — the release line says "add".
    var stagesOnDrop: Bool = false

    var summary: String {
        switch totalCount {
        case 1: return items.first?.name ?? "1 item"
        default: return "\(totalCount) items"
        }
    }
}
