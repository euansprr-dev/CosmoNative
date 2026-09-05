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
        /// WHAT the uuid in `.captured` refers to, so Undo dismisses the right
        /// record. A swipe row carries an ATOM uuid; sending that to
        /// `InboxRepository.dismiss` would silently no-op while the row
        /// cheerfully reported itself undone.
        var undoTarget: UndoTarget = .inboxItem

        enum UndoTarget {
            case inboxItem
            case swipeAtom
        }

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
    /// files can land as ONE linked capture. Text and ordinary link drops
    /// still capture instantly; a platform link (`CaptureSwipeLink`) lands in
    /// the field instead, where the Inbox | Swipe trigger waits for ⏎.
    /// Menu-bar drops never stage.
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

    // MARK: - Staged destination

    /// Where the staged tray — or the platform link sitting in the field — is
    /// headed.
    ///
    /// This is the ONE place in the whole system that asks the user anything
    /// kind-adjacent, and it earns the exception because both subjects are
    /// genuinely ambiguous: three ad screenshots and a PDF invoice arrive
    /// through the identical gesture, and an Instagram link is as often
    /// "swipe this" as "remind me about this". Note it is a DESTINATION, not
    /// a kind — picking Swipe still leaves the kind to `SwipeIntakeRouter`.
    enum StagedDestination: String, CaseIterable, Identifiable {
        case inbox
        case swipe

        var id: String { rawValue }

        var title: String {
            switch self {
            case .inbox: return "Inbox"
            case .swipe: return "Swipe"
            }
        }

        var iconName: String {
            switch self {
            case .inbox: return "tray"
            case .swipe: return SwipeKind.frame.iconName
            }
        }
    }

    var stagedDestination: StagedDestination = .inbox
    /// Set the moment the user touches the control. Until then the default is
    /// re-inferred on every staging change; after it, their choice sticks for
    /// the rest of the tray's life — a picker that re-guesses under your hand
    /// is worse than no picker.
    private var stagedDestinationChosen = false

    /// The platform link in the field, if any — the one text shape that earns
    /// the same Inbox | Swipe trigger staged screenshots get. Computed, never
    /// mirrored, so it can never lag the text. Nil while a resolved lane
    /// command owns the text: `Groceries: https://…` is a lane capture, and
    /// two destination controls under one field would contradict each other.
    var swipeLink: CaptureSwipeLink? {
        guard laneAssist.hint == nil else { return nil }
        return CaptureSwipeLink.detect(in: captureText)
    }
    /// Whether the previous text edit showed a link — a link LEAVING the
    /// field ends its "tray", so the next one is inferred afresh.
    private var swipeLinkWasPresent = false

    /// All-images ⇒ Swipe. A single document, or any mix, ⇒ Inbox.
    /// Screenshots are what people drop on this panel to swipe; a PDF is not.
    static func inferredStagedDestination(for staged: [StagedAttachment]) -> StagedDestination {
        guard !staged.isEmpty, staged.allSatisfy(\.isImage) else { return .inbox }
        return .swipe
    }

    /// The one inference. A staged tray is the subject whenever it exists —
    /// the field's text rides along as its note, link or not. With nothing
    /// staged, a platform link in the field ⇒ Swipe: an Instagram, YouTube,
    /// X or TikTok link is what people put in this panel to swipe, exactly as
    /// screenshots are what they drop. Anything else ⇒ Inbox.
    static func inferredDestination(
        staged: [StagedAttachment],
        link: CaptureSwipeLink?
    ) -> StagedDestination {
        if !staged.isEmpty { return inferredStagedDestination(for: staged) }
        return link == nil ? .inbox : .swipe
    }

    func chooseStagedDestination(_ destination: StagedDestination) {
        stagedDestination = destination
        stagedDestinationChosen = true
    }

    /// Re-infer while the user hasn't overridden. Called after every staging
    /// mutation and every text edit.
    private func refreshDestination() {
        guard !stagedDestinationChosen else { return }
        stagedDestination = Self.inferredDestination(staged: stagedAttachments, link: swipeLink)
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
        stagedDestination = .inbox
        stagedDestinationChosen = false
        swipeLinkWasPresent = false
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
        let link = swipeLink
        // The link is the field's "tray": while one is present the default is
        // inferred once and the user's toggle sticks; when it leaves, the
        // choice is released so the next link starts from the default again.
        if link == nil, swipeLinkWasPresent, stagedAttachments.isEmpty {
            stagedDestinationChosen = false
        }
        swipeLinkWasPresent = link != nil
        refreshDestination()
    }

    /// A platform link arriving from outside the field — a drop, or ⌘V while
    /// no field owns focus — lands IN the field rather than capturing on the
    /// spot, so the Inbox | Swipe trigger appears exactly as it does for a
    /// pasted link. Appends to a thought already there (the thought becomes
    /// the swipe's note) and hands the field focus so ⏎ sends.
    private func landInField(_ text: String) {
        let existing = captureText.trimmingCharacters(in: .whitespacesAndNewlines)
        captureText = existing.isEmpty ? text : existing + " " + text
        captureTextChanged()
        captureFieldFocusTick += 1
    }

    /// `swipe:` — the swipe alias, alongside the lane aliases. Checked before
    /// the lane assist so a user can never shadow it by naming a lane "swipe".
    static let swipeAliasPrefix = "swipe:"

    /// Strip the alias and return what follows, or nil when it isn't one.
    static func swipeAliasBody(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix(swipeAliasPrefix) else { return nil }
        let body = trimmed.dropFirst(swipeAliasPrefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }

    func submitText(asSwipe: Bool = false) async {
        // Staged files present — Enter sends the bundle: the thought and its
        // attachments leave as one linked capture.
        if !stagedAttachments.isEmpty {
            if asSwipe { chooseStagedDestination(.swipe) }
            await sendStaged()
            return
        }
        let text = captureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // ⇧⏎ or the `swipe:` alias — the same destination, two ways of saying
        // it. The alias is checked BEFORE the lane assist so naming a lane
        // "swipe" can never shadow the verb.
        if let body = Self.swipeAliasBody(in: text) {
            captureText = ""
            laneAssist.reset()
            await captureAsSwipe(body)
            return
        }
        if asSwipe {
            captureText = ""
            laneAssist.reset()
            await captureAsSwipe(text)
            return
        }

        // Read the trigger BEFORE the field clears — clearing re-infers the
        // destination back to Inbox, and the verdict that matters is the one
        // the user was looking at when they pressed ⏎.
        let link = swipeLink
        let destination = stagedDestination
        captureText = ""
        laneAssist.reset()

        // A resolved `alias:` prefix routes straight into that lane — the
        // same choke point as ⌘K and Telegram, never the triage queue.
        if let match = await LaneCaptureAssist.resolvedMatch(for: text), !match.remainder.isEmpty {
            await routeToLane(text: text, match: match)
            return
        }
        // The platform-link trigger, honoured as chosen. Inbox is the plain
        // text path below — the link rides in the item like any other.
        if link != nil, destination == .swipe {
            await captureAsSwipe(text)
            return
        }
        await ingest([.text(text)])
    }

    /// ONE FRONT DOOR: the overlay decides WHERE, never WHAT. The router reads
    /// what it is handed and lands a page / post / note as appropriate. A
    /// platform link is handed AS a link, with the rest of the text as the
    /// note — "https://instagram.com/p/… love this hook" is a post swipe
    /// carrying a note, not a note swipe that happens to contain a URL.
    private func captureAsSwipe(_ text: String) async {
        let source: SwipeIntakeRouter.Source
        let note: String?
        if let link = CaptureSwipeLink.detect(in: text) {
            source = .url(link.url)
            note = link.note
        } else {
            source = .text(text)
            note = nil
        }
        let atom = await SwipeIntakeRouter.run(source, note: note, captureMode: "capture_overlay")
        let display = text.count > 40 ? "\u{201C}\(text.prefix(40))…\u{201D}" : "\u{201C}\(text)\u{201D}"
        guard let atom else {
            // Never drop the words: a failed swipe returns them to the field.
            captureText = text
            sessionEntries.append(SessionEntry(
                displayName: display,
                kind: nil,
                state: .failed("Couldn't save that swipe"),
                fingerprint: nil
            ))
            return
        }
        // The router publishes its receipt synchronously (outside a flow
        // recording) — an adoption receipt for THIS atom means the link was
        // already in the library. That is `.consumed`, the same register as a
        // same-session duplicate: muted, no Undo (undoing an adoption would
        // delete a swipe that predates this capture).
        let adopted = SwipeIntakeReceiptCenter.shared.receipt
            .map { $0.atomUUID == atom.uuid && $0.alreadyInLibrary } ?? false
        sessionEntries.append(SessionEntry(
            displayName: display,
            kind: nil,
            state: adopted
                ? .consumed(reason: "already in your Swipe File")
                : .captured(itemUUID: atom.uuid),
            fingerprint: nil,
            destinationLabel: adopted
                ? "already in your Swipe File"
                : "→ Swipe File · \(atom.swipeKind.displayName)",
            undoTarget: .swipeAtom
        ))
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
            case .url(let url):
                // A platform link waits for the user like a screenshot does;
                // any other link captures on release, as the well promised.
                if CaptureSwipeLink.detect(in: url.absoluteString) != nil {
                    landInField(url.absoluteString)
                } else {
                    instant.append(payload)
                }
            case .text(let string):
                // Strict for drops: the dragged text must be NOTHING but the
                // link. A paragraph with a link buried in it is a text
                // capture, and hijacking it into the field would surprise.
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if let link = CaptureSwipeLink.detect(in: trimmed), link.note == nil {
                    landInField(trimmed)
                } else {
                    instant.append(payload)
                }
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
            refreshDestination()
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
            refreshDestination()
            if staged.isImage { loadThumbnail(for: staged.id, source: .data(data)) }

        case .text, .url:
            break
        }
    }

    func removeStaged(_ id: UUID) {
        stagedAttachments.removeAll { $0.id == id }
        refreshDestination()
    }

    func clearStaged() {
        stagedAttachments = []
        stagedDestinationChosen = false
        refreshDestination()
    }

    /// The send button: staged files plus whatever's in the thought field.
    /// With a thought they leave as ONE linked capture; without one each
    /// file is its own capture, exactly as a bare drop was.
    func sendStaged() async {
        let staged = stagedAttachments
        guard !staged.isEmpty else { return }
        let thought = captureText.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = stagedDestination
        stagedAttachments = []
        stagedDestinationChosen = false
        stagedDestination = .inbox
        captureText = ""
        laneAssist.reset()

        if destination == .swipe {
            await sendStagedAsSwipe(staged, note: thought.isEmpty ? nil : thought)
            return
        }

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
        var destinationLabel: String?
        if case .captured = combined.outcome {
            destinationLabel = "→ Inbox · \(combined.attachedCount) attached"
        }
        sessionEntries.append(SessionEntry(
            displayName: display,
            kind: staged.first?.kind,
            state: state,
            fingerprint: nil,
            destinationLabel: destinationLabel
        ))
    }

    /// A staged tray headed for the Swipe File leaves as ONE frame swipe —
    /// four ad screenshots dropped together are one artifact, because a set is
    /// what the user dragged. The typed thought rides along as the note.
    private func sendStagedAsSwipe(_ staged: [StagedAttachment], note: String?) async {
        var payloads: [SwipeImagePayload] = []
        var unreadable: [String] = []
        for item in staged {
            if let payload = await Self.swipeImagePayload(for: item) {
                payloads.append(payload)
            } else {
                unreadable.append(item.displayName)
            }
        }
        if !unreadable.isEmpty {
            errorLine = "Couldn't read \(unreadable.joined(separator: ", "))"
        }
        guard !payloads.isEmpty else {
            // Nothing readable — fall back to the Inbox path rather than
            // silently discarding the drop.
            await ingest(staged.map(\.payload))
            return
        }

        let atom = await SwipeIntakeRouter.run(
            .images(payloads), note: note, captureMode: "capture_overlay"
        )
        let label = SwipeKind.frame.unitCountLabel(payloads.count)
        sessionEntries.append(SessionEntry(
            displayName: note.map { $0.count > 40 ? "\u{201C}\($0.prefix(40))…\u{201D}" : "\u{201C}\($0)\u{201D}" }
                ?? label,
            kind: .screenshot,
            state: atom.map { .captured(itemUUID: $0.uuid) } ?? .failed("Couldn't save that swipe"),
            fingerprint: nil,
            destinationLabel: atom == nil ? nil : "→ Swipe File · \(label)",
            undoTarget: .swipeAtom
        ))
    }

    /// Staged payload → image bytes. File payloads read from disk; data
    /// payloads are already in hand.
    private static func swipeImagePayload(for staged: StagedAttachment) async -> SwipeImagePayload? {
        switch staged.payload {
        case .file(let url, let suggestedName):
            guard let data = try? Data(contentsOf: url) else { return nil }
            let type = UTType(filenameExtension: url.pathExtension)
            guard type?.conforms(to: .image) == true else { return nil }
            return SwipeImagePayload(
                data: data,
                filename: suggestedName ?? url.lastPathComponent,
                mimeType: type?.preferredMIMEType,
                utType: type
            )
        case .data(let data, let type, let suggestedName):
            guard type.conforms(to: .image) else { return nil }
            return SwipeImagePayload(
                data: data, filename: suggestedName,
                mimeType: type.preferredMIMEType, utType: type
            )
        case .text, .url:
            return nil
        }
    }

    /// The panel is closing with unsent staged files — capture them rather
    /// than dropping bytes on the floor. Esc never loses a capture; Clear is
    /// the explicit discard. The chosen destination is honoured on the way
    /// out: a tray headed for the Swipe File must not silently land in the
    /// Inbox just because the user pressed Esc instead of the send button.
    func flushStagedOnClose() {
        let staged = stagedAttachments
        guard !staged.isEmpty else { return }
        let destination = stagedDestination
        let thought = captureText.trimmingCharacters(in: .whitespacesAndNewlines)
        stagedAttachments = []
        Task {
            if destination == .swipe {
                await sendStagedAsSwipe(staged, note: thought.isEmpty ? nil : thought)
            } else {
                await ingest(staged.map(\.payload))
            }
        }
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
            // A platform link is the one paste that waits for the user: it
            // lands in the field with the Inbox | Swipe trigger, exactly as a
            // pasted screenshot stages. Lenient here — paste is how text
            // enters the field anyway, and the user sees what landed.
            if CaptureSwipeLink.detect(in: trimmed) != nil {
                landInField(trimmed)
                return
            }
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

    /// Per-row Undo. An inbox capture is dismissed (restorable from Recently
    /// dismissed — never a hard delete); a swipe is soft-deleted into the
    /// Trash, which is that object's own equivalent. Routing by `undoTarget`
    /// rather than by uuid shape is what keeps the two honest.
    func undo(_ entry: SessionEntry) async {
        guard case .captured(let uuid) = entry.state, let uuid else { return }
        guard let index = sessionEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        do {
            switch entry.undoTarget {
            case .inboxItem:
                try await InboxRepository.shared.dismiss(uuid: uuid)
            case .swipeAtom:
                try await AtomRepository.shared.delete(uuid: uuid)
                NotificationCenter.default.post(
                    name: CosmoNotification.SwipeFile.libraryDidChange, object: nil
                )
            }
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
    /// Every item is an image. Such a drop defaults to the Swipe File, so the
    /// release line says so BEFORE the user lets go — a destination learned
    /// from the receipt is a destination learned too late.
    var isAllImages: Bool = false
    /// The drag is a bare platform link (Instagram, YouTube, X, TikTok…). It
    /// lands in the field with the Swipe destination pre-selected, so the
    /// release line says "swipe" for the same reason an all-image drop does.
    var isSwipeLink: Bool = false

    var summary: String {
        switch totalCount {
        case 1: return items.first?.name ?? "1 item"
        default: return "\(totalCount) items"
        }
    }
}

// MARK: - Platform links

/// A social-platform link in capture text — the trigger for the ⌥C panel's
/// Inbox | Swipe choice. Pure string work, no actor, so the drop preview, the
/// paste path and the tests all read the same verdict.
///
/// Membership is by HOST, not by permalink shape: the router (`SwipeIntakeRouter`)
/// still decides what a given link becomes — a post for the platforms it has
/// a pipeline for, a page for the rest — and a profile or a short link should
/// still offer the choice. The platform set mirrors ⌘K's swipe sources
/// (`CommandKCaptureRouter.isSwipeSource`); TikTok is host-only because the
/// URL classifier has no permalink pattern for it.
struct CaptureSwipeLink: Equatable, Sendable {

    enum Platform: String, CaseIterable, Sendable {
        case instagram, youtube, x, tiktok, threads, loom

        var displayName: String {
            switch self {
            case .instagram: return "Instagram"
            case .youtube: return "YouTube"
            case .x: return "X"
            case .tiktok: return "TikTok"
            case .threads: return "Threads"
            case .loom: return "Loom"
            }
        }

        /// Key understood by `SwipePlatformGlyph`.
        var glyphKey: String { rawValue }

        /// Registrable domains. Subdomains (`www.`, `m.`, `vm.`, `mobile.`)
        /// match by suffix; unrelated hosts that merely END in these letters
        /// (`notx.com`) do not, because the match requires the dot.
        var domains: [String] {
            switch self {
            case .instagram: return ["instagram.com"]
            case .youtube: return ["youtube.com", "youtu.be"]
            case .x: return ["x.com", "twitter.com"]
            case .tiktok: return ["tiktok.com"]
            case .threads: return ["threads.net", "threads.com"]
            case .loom: return ["loom.com"]
            }
        }
    }

    /// The link exactly as the user wrote it — never the detector's
    /// normalized form, which lowercases the host and can append a slash.
    let url: String
    let platform: Platform
    /// Everything in the text that is NOT the link, trimmed — the swipe's
    /// note. Nil when the text is nothing but the link.
    let note: String?

    /// The first platform link in `text`. Strict on scheme: only a substring
    /// carrying an explicit `http(s)://` qualifies, so a bare `instagram.com/…`
    /// mentioned in prose never triggers (the router would reject it too).
    static func detect(in text: String) -> CaptureSwipeLink? {
        guard !text.isEmpty, let detector else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        var found: CaptureSwipeLink?
        detector.enumerateMatches(in: text, range: range) { match, _, stop in
            guard let match, match.resultType == .link,
                  let matchRange = Range(match.range, in: text) else { return }
            let raw = String(text[matchRange])
            let lowered = raw.lowercased()
            guard lowered.hasPrefix("http://") || lowered.hasPrefix("https://"),
                  let host = match.url?.host,
                  let platform = platform(forHost: host) else { return }
            var remainder = text
            remainder.removeSubrange(matchRange)
            let note = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
            found = CaptureSwipeLink(url: raw, platform: platform, note: note.isEmpty ? nil : note)
            stop.pointee = true
        }
        return found
    }

    static func platform(forHost host: String) -> Platform? {
        let lowered = host.lowercased()
        for platform in Platform.allCases {
            for domain in platform.domains where lowered == domain || lowered.hasSuffix("." + domain) {
                return platform
            }
        }
        return nil
    }

    /// One detector for the process — building one per keystroke is the
    /// avoidable cost here. NSDataDetector is immutable once built.
    nonisolated(unsafe) private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )
}
