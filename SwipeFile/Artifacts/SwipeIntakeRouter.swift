// CosmoOS/SwipeFile/Artifacts/SwipeIntakeRouter.swift
// The single front door for every swipe capture on the Mac.
//
// ONE FRONT DOOR LAW: no surface builds a swipe atom by hand. ⌘⇧S, the region
// grab, the ⌥C overlay, the Inbox verbs, library drag-and-drop, ⌘K, Discover's
// save, the browser pane and the agent tool all call `run` — so all of them
// inherit, for free and identically: kind inference, the artifact envelope,
// media attachment + mirroring, the analysis kick, undo registration, the
// library-changed notification, the flow append, and one receipt.
//
// ONE VERB LAW: no capture surface asks "what kind is this?". `resolve` decides
// from what it was handed, `run` names the answer in the receipt, and the card's
// context menu is where a wrong guess gets corrected. Correction is what trains
// the router; a picker is not.

import Foundation
import AppKit
import WebKit
import UniformTypeIdentifiers
import UserNotifications

// MARK: - Payloads

/// One image headed for a frame swipe. Bytes plus just enough provenance to
/// name the attachment sensibly.
struct SwipeImagePayload: Sendable {
    var data: Data
    var filename: String?
    var mimeType: String?
    var utType: UTType?

    init(data: Data, filename: String? = nil, mimeType: String? = nil, utType: UTType? = nil) {
        self.data = data
        self.filename = filename
        self.mimeType = mimeType
        self.utType = utType
    }

    var resolvedMimeType: String {
        mimeType ?? utType?.preferredMIMEType ?? "image/png"
    }

    var resolvedFilename: String {
        filename ?? "screenshot.\(utType?.preferredFilenameExtension ?? "png")"
    }
}

// MARK: - Receipt

/// What a completed capture tells the user. Published rather than shown here —
/// the router has no view; surfaces observe `SwipeIntakeReceiptCenter`.
struct SwipeIntakeReceipt: Equatable, Identifiable {
    let id = UUID()
    var kind: SwipeKind
    var unitCount: Int
    var atomUUID: String
    var flowName: String?
    /// What the capture was FILED AS — the space it landed in. Defaults to the
    /// kind's structural fallback so every existing call site stays honest.
    var genre: SwipeGenre?
    /// The captured item's title, for surfaces that name WHAT was captured
    /// (the native notification). Optional so pre-title captures stay honest.
    var title: String? = nil
    /// The capture matched a swipe already in the library — the existing atom
    /// was adopted, nothing new was created. The receipt must say so: a
    /// "Swiped ·" confirmation over a no-op reads as the library silently
    /// eating the capture (iOS twin: SwipeCaptureSheet's dedup state).
    var alreadyInLibrary = false

    /// "Swiped · Newsletter · 14 sections" — what it IS is always NAMED,
    /// because the user never chose it and silently guessing would make the
    /// system feel arbitrary the first time it guessed wrong. The genre is
    /// also how the user learns a new space just appeared in the sidebar.
    var message: String {
        let noun = (genre ?? SwipeGenre.defaultGenre(for: kind)).displayName
        if let flowName {
            return "Added to \(flowName) · \(noun)"
        }
        if alreadyInLibrary {
            return "Already in your Swipe File · \(noun)"
        }
        if unitCount > 0 {
            return "Swiped · \(noun) · \(kind.unitCountLabel(unitCount))"
        }
        return "Swiped · \(noun)"
    }
}

/// App-wide receipt channel. ⌘⇧S fires from anywhere, so the confirmation
/// cannot live on any one page's state.
@MainActor
@Observable
final class SwipeIntakeReceiptCenter {
    static let shared = SwipeIntakeReceiptCenter()
    private init() {}

    var receipt: SwipeIntakeReceipt?
    /// Set when a capture failed. Rare and worth saying out loud — a silent
    /// no-op after ⌘⇧S reads as a broken shortcut.
    var errorMessage: String?

    func publish(_ receipt: SwipeIntakeReceipt) {
        errorMessage = nil
        self.receipt = receipt
        // Every successful capture also confirms through the SYSTEM voice —
        // the in-app toast only renders on swipe surfaces, and ⌘⇧S fires from
        // anywhere. Errors stay in-app: a system banner for "nothing to swipe"
        // would be noise.
        SwipeCaptureNotifier.notify(receipt)
    }

    func publishError(_ message: String) {
        receipt = nil
        errorMessage = message
    }
}

// MARK: - Native capture confirmation

/// The system-notification voice of a capture: "she sells — Captured to Swipe
/// File · Newsletter", top-right, where every Mac app confirms background
/// work. The in-app receipt remains the undo seat; this banner is what makes
/// ⌘⇧S trustworthy from any focus mode, where no receipt toast renders.
///
/// Reuses SwipeFileEngine's notification plumbing wholesale — its category
/// (an "Open" action that navigates to the atom via openAtomFromCommandK) and
/// its delegate (which presents banners while the app is frontmost). One
/// notification system, not a parallel one.
@MainActor
enum SwipeCaptureNotifier {

    static func notify(_ receipt: SwipeIntakeReceipt) {
        // Touching the engine registers the category, installs the delegate,
        // and requests authorization on first use — all idempotent.
        _ = SwipeFileEngine.shared

        let content = UNMutableNotificationContent()
        let noun = (receipt.genre ?? SwipeGenre.defaultGenre(for: receipt.kind)).displayName
        if let title = receipt.title?.trimmed, !title.isEmpty {
            content.title = title
        } else {
            content.title = "Swipe captured"
        }
        content.body = receipt.flowName.map { "Added to \($0) · \(noun)" }
            ?? (receipt.alreadyInLibrary
                ? "Already in your Swipe File · \(noun)"
                : "Captured to Swipe File · \(noun)")
        // Deliberately silent: capture is a background confirmation, not an
        // alert. The banner carries the message; a sound would make ⌘⇧S loud.
        content.categoryIdentifier = SwipeFileEngine.captureNotificationCategory
        content.userInfo = ["atomUUID": receipt.atomUUID]

        let request = UNNotificationRequest(
            identifier: "swipe-capture-\(receipt.atomUUID)",
            content: content,
            trigger: nil
        )
        Task {
            let center = UNUserNotificationCenter.current()
            // First capture ever: wait out the permission prompt so THIS
            // capture's confirmation isn't the one that gets dropped.
            if await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            try? await center.add(request)
        }
    }
}

// MARK: - Router

@MainActor
enum SwipeIntakeRouter {

    /// What a surface hands the router. Deliberately raw: surfaces report what
    /// they HAVE, never what they think it should become.
    enum Source {
        /// Read whatever is on the pasteboard right now (⌘⇧S with no context).
        case pasteboard
        case images([SwipeImagePayload])
        case url(String)
        case text(String)
        /// A live page in the browser pane — its session, its scroll, past
        /// the opt-in. The webview rides along so the capture reads the page
        /// the user is actually looking at, not a fresh anonymous render.
        case liveWebPage(url: String, title: String?, webView: WKWebView? = nil)
        /// A parsed email file (.eml/.emlx dragged out of Mail) — the
        /// Newsletters front door. Newsletters live in inboxes, not at URLs.
        case email(SwipeEmailPayload)
    }

    /// What the router decided to make.
    enum Intake: Equatable {
        case frames(count: Int)
        case pageFromLiveWebPage(url: String, title: String?)
        case pageFromURL(String)
        /// A page rendered from a parsed email's HTML (no URL exists).
        case pageFromEmail(subject: String?)
        /// The existing platform pipeline, untouched.
        case postURL(String)
        case note(String)
        /// Nothing usable — the caller should open the ⌥C overlay instead.
        case nothing

        var kind: SwipeKind? {
            switch self {
            case .frames: return .frame
            case .pageFromLiveWebPage, .pageFromURL, .pageFromEmail: return .page
            case .postURL: return .post
            case .note: return .note
            case .nothing: return nil
            }
        }
    }

    // MARK: Resolution

    /// The ladder. First match wins, and every branch is reachable from a
    /// plain ⌘⇧S — which is the point: one shortcut, no menu.
    static func resolve(_ source: Source) -> Intake {
        switch source {
        case .liveWebPage(let url, let title, _):
            return .pageFromLiveWebPage(url: url, title: title)

        case .images(let payloads):
            return payloads.isEmpty ? .nothing : .frames(count: payloads.count)

        case .url(let raw):
            return resolveURL(raw)

        case .text(let raw):
            let trimmed = raw.trimmed
            guard !trimmed.isEmpty else { return .nothing }
            // A pasted link wrapped in prose is still a link capture.
            if let url = SwipeURLClassifier().firstURL(in: trimmed), url == trimmed {
                return resolveURL(url)
            }
            return .note(trimmed)

        case .email(let payload):
            return .pageFromEmail(subject: payload.subject)

        case .pasteboard:
            return resolvePasteboard()
        }
    }

    /// Known platform ⇒ the existing post pipeline. Anything else that is a
    /// real link is a PAGE — which is the single most consequential line in
    /// this file: it is what turns "paste a sales page" from a dead research
    /// row into a decomposable artifact.
    ///
    /// `nonisolated` because it is pure string work and callers off the main
    /// actor need it to PREDICT a kind for a label (the Inbox verb names what
    /// it will make). Only `resolve(.pasteboard)` touches AppKit.
    nonisolated static func resolveURL(_ raw: String) -> Intake {
        let trimmed = raw.trimmed
        let classifier = SwipeURLClassifier()
        guard classifier.isURL(trimmed) else {
            return trimmed.isEmpty ? .nothing : .note(trimmed)
        }
        let classification = classifier.classify(trimmed)
        switch classification.sourceType {
        case .website, .other, .unknown, .rawNote:
            return .pageFromURL(trimmed)
        default:
            return .postURL(trimmed)
        }
    }

    private static func resolvePasteboard() -> Intake {
        let pasteboard = NSPasteboard.general
        let payloads = imagePayloads(from: pasteboard)
        if !payloads.isEmpty { return .frames(count: payloads.count) }
        if let text = pasteboard.string(forType: .string)?.trimmed, !text.isEmpty {
            return resolve(.text(text))
        }
        return .nothing
    }

    /// Every image on the pasteboard, in order. Handles both file promises
    /// (Finder, screenshot-to-file) and raw bitmap data (⌘⇧⌃4, most apps).
    static func imagePayloads(from pasteboard: NSPasteboard) -> [SwipeImagePayload] {
        var payloads: [SwipeImagePayload] = []

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] {
            for url in urls {
                guard let type = UTType(filenameExtension: url.pathExtension),
                      type.conforms(to: .image),
                      let data = try? Data(contentsOf: url) else { continue }
                payloads.append(SwipeImagePayload(
                    data: data, filename: url.lastPathComponent,
                    mimeType: type.preferredMIMEType, utType: type
                ))
            }
        }
        if !payloads.isEmpty { return payloads }

        // Raw bitmap. PNG first — a screenshot on the pasteboard is PNG, and
        // going through TIFF would re-encode it for nothing.
        for (pasteType, utType) in [(NSPasteboard.PasteboardType.png, UTType.png),
                                    (NSPasteboard.PasteboardType.tiff, UTType.tiff)] {
            if let data = pasteboard.data(forType: pasteType) {
                payloads.append(SwipeImagePayload(
                    data: data, filename: nil,
                    mimeType: utType.preferredMIMEType, utType: utType
                ))
                break
            }
        }
        return payloads
    }

    // MARK: Run

    /// Create the swipe. ONE completion path — receipt, undo, notification and
    /// analysis kick all happen here, so no surface can forget one of them.
    @discardableResult
    static func run(
        _ source: Source,
        note: String? = nil,
        boardIDs: [String] = [],
        captureMode: String
    ) async -> Atom? {
        let intake = resolve(source)
        guard intake != .nothing else {
            SwipeIntakeReceiptCenter.shared.publishError("Nothing to swipe — copy a link or an image first.")
            return nil
        }

        let images: [SwipeImagePayload]
        switch source {
        case .images(let payloads): images = payloads
        case .pasteboard: images = imagePayloads(from: NSPasteboard.general)
        default: images = []
        }
        let liveWebView: WKWebView? = {
            if case .liveWebPage(_, _, let webView) = source { return webView }
            return nil
        }()

        switch intake {
        case .frames:
            return await captureFrames(images, note: note, boardIDs: boardIDs, captureMode: captureMode)
        case .pageFromURL(let url):
            return await capturePage(url: url, title: nil, note: note, boardIDs: boardIDs, captureMode: captureMode)
        case .pageFromLiveWebPage(let url, let title):
            return await capturePage(
                url: url, title: title, note: note, boardIDs: boardIDs,
                captureMode: captureMode, liveWebView: liveWebView
            )
        case .pageFromEmail:
            guard case .email(let payload) = source else { return nil }
            return await captureEmail(payload, note: note, boardIDs: boardIDs, captureMode: captureMode)
        case .postURL(let url):
            return await capturePost(url: url, note: note, boardIDs: boardIDs, captureMode: captureMode)
        case .note(let text):
            return await captureNote(text, boardIDs: boardIDs, captureMode: captureMode)
        case .nothing:
            return nil
        }
    }

    // MARK: Email

    /// A dragged-in email lands instantly as a Newsletter page swipe; the
    /// render + slicing + reading happen behind it, exactly like a URL page —
    /// except the source HTML is already in hand, so there is nothing to
    /// re-fetch and no dedup URL to check.
    private static func captureEmail(
        _ payload: SwipeEmailPayload,
        note: String?,
        boardIDs: [String],
        captureMode: String
    ) async -> Atom? {
        let subject = payload.subject?.trimmed
        var atom = Atom.newSwipeFile(
            url: "", hook: nil, sourceType: .website, contentSource: .clipboard
        )
        atom.title = (subject?.isEmpty == false ? subject! : "Email")
        atom.updateResearchMetadata { meta in
            meta.contentSource = SwipeKind.page.rawValue
            meta.processingStatus = "extracting"
            meta.swipeBoardIDs = boardIDs.isEmpty ? nil : boardIDs
            meta.url = nil
            meta.swipeGenre = SwipeGenre.newsletter.rawValue
        }
        if let note = note?.trimmed, !note.isEmpty { atom.body = note }
        var artifact = SwipeArtifact(
            kind: .page, units: [], genre: .newsletter,
            captureMode: captureMode, pageTitle: subject
        )
        // The sender is the artifact's provenance — the same seat a
        // screenshotted post's detected author uses.
        if payload.senderName != nil || payload.senderAddress != nil {
            artifact.detectedSource = DetectedSource(
                platform: "email", handle: payload.senderAddress ?? payload.senderName
            )
        }
        atom = atom.withSwipeArtifact(artifact)

        guard let created = await persist(atom, attachments: []) else { return nil }
        finish(created, kind: .page, unitCount: 0, genre: .newsletter)

        let uuid = created.uuid
        let html = payload.html
        Task { await SwipePageDecomposition.run(swipeUUID: uuid, htmlString: html, note: note) }
        return created
    }

    // MARK: Frames

    private static func captureFrames(
        _ images: [SwipeImagePayload],
        note: String?,
        boardIDs: [String],
        captureMode: String
    ) async -> Atom? {
        guard !images.isEmpty else { return nil }

        var atom = Atom.new(type: .research, title: provisionalFrameTitle(count: images.count))
        atom.updateResearchMetadata { meta in
            meta.isSwipeFile = true
            meta.contentSource = SwipeKind.frame.rawValue
            meta.processingStatus = "analyzing"
            meta.swipeBoardIDs = boardIDs.isEmpty ? nil : boardIDs
        }
        if let note = note?.trimmed, !note.isEmpty { atom.body = note }

        // Store the bytes FIRST: the images are the irreplaceable part, and a
        // failure past this point must never lose them.
        var units: [SwipeArtifactUnit] = []
        var attachments: [MediaAttachment] = []
        for (index, payload) in images.enumerated() {
            let attachmentID = UUID().uuidString
            guard let stored = try? CaptureMediaStorage.shared.store(
                data: payload.data,
                capturedItemId: atom.uuid,
                attachmentId: attachmentID,
                originalFilename: payload.resolvedFilename,
                mimeType: payload.resolvedMimeType,
                telegramFilePath: nil,
                kind: .screenshot
            ) else { continue }

            var attachment = MediaAttachment.makeLocal(
                owner: .atom,
                ownerUUID: atom.uuid,
                kind: .screenshot,
                localStoragePath: stored.originalPath,
                thumbnailPath: stored.thumbnailPath,
                originalFilename: payload.resolvedFilename,
                mimeType: payload.resolvedMimeType,
                fileSize: Int64(payload.data.count),
                metadata: metadataJSON([
                    "captureSource": captureMode,
                    "unitIndex": index
                ])
            )
            attachment.uuid = attachmentID
            attachments.append(attachment)
            units.append(SwipeArtifactUnit(
                index: index,
                attachmentUUID: attachmentID,
                aspectRatio: aspectRatio(of: payload.data)
            ))
        }
        guard !units.isEmpty else {
            SwipeIntakeReceiptCenter.shared.publishError("Couldn't read those images.")
            return nil
        }

        atom = atom.withSwipeArtifact(SwipeArtifact(
            kind: .frame,
            units: units,
            captureMode: captureMode
        ))
        // The first frame's thumbnail IS the card's artwork until the mirror
        // lands, so the grid never shows an empty well.
        if let firstThumb = attachments.first?.thumbnailPath {
            atom.updateResearchMetadata { $0.thumbnailUrl = URL(fileURLWithPath: firstThumb).absoluteString }
        }

        guard let created = await persist(atom, attachments: attachments) else { return nil }
        finish(created, kind: .frame, unitCount: units.count)

        let uuid = created.uuid
        Task { await SwipeFrameDecomposition.run(swipeUUID: uuid, note: note) }
        return created
    }

    private static func provisionalFrameTitle(count: Int) -> String {
        count == 1 ? "Screenshot" : "\(count) screenshots"
    }

    private static func aspectRatio(of data: Data) -> Double? {
        guard let image = NSImage(data: data), image.size.height > 0 else { return nil }
        return Double(image.size.width / image.size.height)
    }

    // MARK: Pages

    /// The page lands immediately as a correctly-typed row; the render, the
    /// slicing and the reading all happen behind it. Capture must feel
    /// instant — a sales page takes seconds to settle and snapshot, and
    /// blocking ⌘⇧S on that would make the verb feel broken.
    private static func capturePage(
        url: String,
        title: String?,
        note: String?,
        boardIDs: [String],
        captureMode: String,
        liveWebView: WKWebView? = nil
    ) async -> Atom? {
        if let existing = await QuickCaptureProcessor.findExistingLiveSwipe(url: url) {
            // Adopt, never duplicate — but the re-capture's input still lands:
            // a note rides in when the existing swipe has none (the post
            // path's policy), and boards union rather than clobber.
            var updated = existing
            var changed = false
            if let note = note?.trimmed, !note.isEmpty, updated.body?.isEmpty != false {
                updated.body = note
                changed = true
            }
            if !boardIDs.isEmpty {
                var boards = updated.researchMetadata?.swipeBoardIDs ?? []
                for id in boardIDs where !boards.contains(id) { boards.append(id) }
                if boards != updated.researchMetadata?.swipeBoardIDs {
                    updated.updateResearchMetadata { $0.swipeBoardIDs = boards }
                    changed = true
                }
            }
            if changed {
                _ = try? await AtomRepository.shared.update(updated)
            }
            finish(
                updated, kind: updated.swipeKind,
                unitCount: updated.swipeArtifactUnits.count,
                genre: updated.swipeGenre,
                isExisting: true
            )
            return updated
        }

        // Genre seed from the URL alone — a Substack issue files under
        // Newsletters the moment it is swiped, not a model round-trip later.
        // The analyzer may refine it; the measured page shape seeds only when
        // this said nothing (host identity is the stronger prior).
        let genreSeed = SwipeGenreSeed.infer(url: url)

        var atom = Atom.newSwipeFile(
            url: url, hook: nil, sourceType: .website, contentSource: .clipboard
        )
        atom.title = title?.trimmed.isEmpty == false ? title!.trimmed : url
        atom.updateResearchMetadata { meta in
            meta.contentSource = SwipeKind.page.rawValue
            meta.processingStatus = "extracting"
            meta.swipeBoardIDs = boardIDs.isEmpty ? nil : boardIDs
            if let genreSeed { meta.swipeGenre = genreSeed.rawValue }
        }
        if let note = note?.trimmed, !note.isEmpty { atom.body = note }
        atom = atom.withSwipeArtifact(SwipeArtifact(
            kind: .page, units: [], genre: genreSeed,
            captureMode: captureMode, capturedURL: url, pageTitle: title
        ))

        guard let created = await persist(atom, attachments: []) else { return nil }
        finish(created, kind: .page, unitCount: 0, genre: genreSeed)

        let uuid = created.uuid
        // The live webview must be read on THIS turn of the main actor — the
        // user can navigate it away a moment later, and a capture of the next
        // page under the previous page's title is worse than no capture.
        if let liveWebView {
            Task { await SwipePageDecomposition.run(swipeUUID: uuid, webView: liveWebView, note: note) }
        } else if let pageURL = URL(string: url) {
            Task { await SwipePageDecomposition.run(swipeUUID: uuid, url: pageURL, note: note) }
        }
        return created
    }

    // MARK: Posts

    private static func capturePost(
        url: String,
        note: String?,
        boardIDs: [String],
        captureMode: String
    ) async -> Atom? {
        // The existing pipeline owns this entirely — dedup, instant thumbnail,
        // cloud kick. The router only adds the receipt and the board stamp.
        // The pipeline's dedup is internal, so probe first: adoption of a
        // pre-existing swipe must reach the receipt as such.
        let preExistingUUID = await QuickCaptureProcessor.findExistingLiveSwipe(url: url)?.uuid
        guard let research = await QuickCaptureProcessor.shared.captureURLReturningUUID(url),
              let created = try? await AtomRepository.shared.fetch(uuid: research) else {
            SwipeIntakeReceiptCenter.shared.publishError("Couldn't save that link.")
            return nil
        }
        let adoptedExisting = preExistingUUID == created.uuid
        var updated = created
        var changed = false
        if !boardIDs.isEmpty {
            updated.updateResearchMetadata { $0.swipeBoardIDs = boardIDs }
            changed = true
        }
        if let note = note?.trimmed, !note.isEmpty, updated.body?.isEmpty != false {
            updated.body = note
            changed = true
        }
        if changed {
            _ = try? await AtomRepository.shared.update(updated)
        }
        finish(updated, kind: .post, unitCount: 0, isExisting: adoptedExisting)
        return updated
    }

    // MARK: Notes

    private static func captureNote(
        _ text: String,
        boardIDs: [String],
        captureMode: String
    ) async -> Atom? {
        var atom = Atom.swipeFromRawText(text: text, hook: firstLine(of: text))
        atom.updateResearchMetadata { meta in
            meta.swipeBoardIDs = boardIDs.isEmpty ? nil : boardIDs
        }
        // A pasted VSL script is not "a note" — it has beats. The slicer
        // splits real long-form into paragraph units; a single-line hook
        // stays one unit and never spends a model call.
        let units = SwipeTextSlicer.units(from: text)
        atom = atom.withSwipeArtifact(SwipeArtifact(
            kind: .note,
            units: units,
            captureMode: captureMode
        ))
        if units.count > 1 {
            atom.updateResearchMetadata { $0.processingStatus = "analyzing" }
        }
        guard let created = await persist(atom, attachments: []) else { return nil }
        finish(created, kind: .note, unitCount: units.count)

        // Multi-block text earns the full read: roles per beat, structural
        // recipe, and the genre verdict that separates `script` from `copy`.
        if units.count > 1 {
            let uuid = created.uuid
            Task {
                guard let live = try? await AtomRepository.shared.fetch(uuid: uuid),
                      let artifact = live.swipeArtifact else { return }
                let result = await SwipeArtifactAnalyzer.analyze(atom: live, artifact: artifact, userNote: nil)
                await SwipeArtifactPersistence.apply(result, toAtomWithUUID: uuid, artifact: artifact)
            }
        }
        return created
    }

    private static func firstLine(of text: String) -> String? {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init)?.trimmed
    }

    // MARK: Shared completion

    private static func persist(_ atom: Atom, attachments: [MediaAttachment]) async -> Atom? {
        do {
            let created = try await AtomRepository.shared.create(atom)
            for attachment in attachments {
                _ = try? await MediaAttachmentRepository.shared.create(attachment)
            }
            if !attachments.isEmpty { AttachmentCloudStore.kick() }
            await RecallIndexer.shared.noteAtomChanged(uuid: created.uuid)
            return created
        } catch {
            PersistenceHealth.note(
                .writeFailure,
                context: "SwipeIntakeRouter.persist(\(atom.uuid.prefix(8)))",
                detail: String(describing: error)
            )
            SwipeIntakeReceiptCenter.shared.publishError("Couldn't save that swipe.")
            return nil
        }
    }

    /// Receipt + flow append + undo + library refresh. Every capture path ends
    /// here, which is why no capture surface has to know flows exist.
    private static func finish(
        _ atom: Atom,
        kind: SwipeKind,
        unitCount: Int,
        genre: SwipeGenre? = nil,
        isExisting: Bool = false
    ) {
        // A recording session claims the capture before the receipt is
        // published, so the receipt can say "Added to Client X funnel" rather
        // than "Swiped" followed by a second, contradicting message.
        if SwipeFlowRecorder.shared.isRecording {
            let uuid = atom.uuid
            let title = atom.title
            Task { @MainActor in
                if let session = await SwipeFlowRecorder.shared.appendCapturedSwipe(uuid: uuid) {
                    SwipeIntakeReceiptCenter.shared.publish(SwipeIntakeReceipt(
                        kind: kind, unitCount: unitCount, atomUUID: uuid,
                        flowName: session.name, genre: genre, title: title,
                        alreadyInLibrary: isExisting
                    ))
                } else {
                    SwipeIntakeReceiptCenter.shared.publish(SwipeIntakeReceipt(
                        kind: kind, unitCount: unitCount, atomUUID: uuid, genre: genre,
                        title: title, alreadyInLibrary: isExisting
                    ))
                }
            }
        } else {
            SwipeIntakeReceiptCenter.shared.publish(SwipeIntakeReceipt(
                kind: kind, unitCount: unitCount, atomUUID: atom.uuid, genre: genre,
                title: atom.title, alreadyInLibrary: isExisting
            ))
        }
        NotificationCenter.default.post(name: CosmoNotification.SwipeFile.libraryDidChange, object: nil)

        // A dedup adopted a swipe that predates this capture — there is
        // nothing to undo, and registering one would let ⌘Z DELETE a
        // pre-existing library object.
        guard !isExisting else { return }

        let snapshot = atom
        CosmoUndoManager.shared.register(InlineUndoAction(
            actionDescription: "Swipe \(kind.displayName)"
        ) {
            try? await AtomRepository.shared.delete(uuid: snapshot.uuid)
            NotificationCenter.default.post(name: CosmoNotification.SwipeFile.libraryDidChange, object: nil)
        } redo: {
            _ = try? await AtomRepository.shared.create(snapshot)
            NotificationCenter.default.post(name: CosmoNotification.SwipeFile.libraryDidChange, object: nil)
        })
    }

    /// For surfaces that legitimately build their own swipe atom but must
    /// still inherit everything the front door provides.
    ///
    /// Three capture paths genuinely cannot go through `run`: Discover's save
    /// already holds the post's fetched metadata (routing it back through a URL
    /// would re-fetch what it has), the Inbox executor owns its own undo +
    /// capture-provenance + actioned-marking, and the agent tool creates
    /// swipes on the user's behalf from a conversation. Forcing those through
    /// `run` would mean losing real behaviour to satisfy a rule.
    ///
    /// So the LAW is on the completion, not the construction: whatever built
    /// the atom, it lands here, and therefore joins an open flow, publishes a
    /// receipt, and refreshes the library exactly like every other capture.
    /// `registersUndo` is false for surfaces that already registered their own.
    static func noteExternallyCreatedSwipe(
        _ atom: Atom,
        registersUndo: Bool = false,
        publishesReceipt: Bool = true
    ) {
        let kind = atom.swipeKind
        let genre = atom.swipeGenre
        let unitCount = atom.swipeArtifactUnits.count

        if SwipeFlowRecorder.shared.isRecording {
            let uuid = atom.uuid
            let title = atom.title
            Task { @MainActor in
                let session = await SwipeFlowRecorder.shared.appendCapturedSwipe(uuid: uuid)
                guard publishesReceipt else { return }
                SwipeIntakeReceiptCenter.shared.publish(SwipeIntakeReceipt(
                    kind: kind, unitCount: unitCount, atomUUID: uuid,
                    flowName: session?.name, genre: genre, title: title
                ))
            }
        } else if publishesReceipt {
            SwipeIntakeReceiptCenter.shared.publish(SwipeIntakeReceipt(
                kind: kind, unitCount: unitCount, atomUUID: atom.uuid, genre: genre,
                title: atom.title
            ))
        }

        NotificationCenter.default.post(name: CosmoNotification.SwipeFile.libraryDidChange, object: nil)

        guard registersUndo else { return }
        let snapshot = atom
        CosmoUndoManager.shared.register(InlineUndoAction(
            actionDescription: "Swipe \(kind.displayName)"
        ) {
            try? await AtomRepository.shared.delete(uuid: snapshot.uuid)
            NotificationCenter.default.post(name: CosmoNotification.SwipeFile.libraryDidChange, object: nil)
        } redo: {
            _ = try? await AtomRepository.shared.create(snapshot)
            NotificationCenter.default.post(name: CosmoNotification.SwipeFile.libraryDidChange, object: nil)
        })
    }

    private static func metadataJSON(_ dict: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Frame decomposition

/// Pass 1 (vision) + pass 2 (craft) for a frame swipe, from anywhere.
///
/// Deliberately reads its images back from the swipe's OWN attachments rather
/// than taking bytes as an argument: the ⌥C overlay and ⌘⇧S have the bytes in
/// hand, the Inbox never did (its attachments arrived from the phone), and the
/// retry path has only a uuid. One entry point means all four behave
/// identically — and the bytes are already on disk before the atom exists, so
/// re-reading them costs nothing.
@MainActor
enum SwipeFrameDecomposition {

    static func run(swipeUUID: String, note: String?) async {
        guard let live = try? await AtomRepository.shared.fetch(uuid: swipeUUID),
              let artifact = live.swipeArtifact else { return }

        let images = await imageBytes(for: artifact)
        guard !images.isEmpty else {
            // Nothing readable — leave the swipe visibly un-analyzed rather
            // than stamping a hollow analysis on it.
            await SwipeArtifactPersistence.apply(nil, toAtomWithUUID: swipeUUID, artifact: artifact)
            return
        }

        // Fast filing, in parallel: the cheap classifier names the room in
        // about a second; the craft pass judges behind it (and its verdict
        // refines the filing when it lands). Fill-only — a seed or a human
        // choice is never overwritten from here.
        if artifact.genre == nil, artifact.genreLockedByUser != true {
            let classifierImages = images
            let copy = artifact.orderedUnits.compactMap(\.copy)
            let body = live.body
            Task {
                let verdict = await SwipeGenreClassifier.classify(
                    images: classifierImages, note: body, unitCopy: copy
                )
                await SwipeGenreClassifier.fill(verdict, intoAtomWithUUID: swipeUUID)
            }
        }

        let result = await SwipeFrameAnalyzer.analyze(
            atom: live, artifact: artifact, images: images, userNote: note
        )
        await SwipeArtifactPersistence.apply(result, toAtomWithUUID: swipeUUID, artifact: artifact)
    }

    /// Unit-ordered bytes. A unit whose attachment hasn't mirrored down yet is
    /// skipped rather than failing the batch; the retry picks it up later.
    /// Internal: the heal sweep's genre-classify arm reads the same bytes.
    static func imageBytes(for artifact: SwipeArtifact) async -> [Data] {
        let uuids = artifact.orderedUnits.compactMap(\.attachmentUUID)
        guard !uuids.isEmpty else { return [] }
        let rows = (try? await MediaAttachmentRepository.shared.fetch(uuids: uuids)) ?? []
        let byUUID = Dictionary(rows.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })

        var bytes: [Data] = []
        for uuid in uuids {
            guard let attachment = byUUID[uuid],
                  let url = await AttachmentCloudStore.shared.localOriginalURL(for: attachment),
                  let data = try? Data(contentsOf: url) else { continue }
            bytes.append(data)
        }
        return bytes
    }
}

// MARK: - Page decomposition

/// Render → slice → read, for a Page swipe.
///
/// The reading runs on the sliced DOM TEXT, never the images: the text is
/// exact, it is already in hand from the probe, and it is roughly fifty times
/// cheaper than vision. Vision is reserved for the sections that carry no text
/// at all (an image-only hero), where it is the only way to say anything.
@MainActor
enum SwipePageDecomposition {

    static func run(swipeUUID: String, webView: WKWebView, note: String?) async {
        guard let capture = await SwipePageCapture.capture(webView: webView, swipeUUID: swipeUUID) else {
            await failCapture(swipeUUID: swipeUUID)
            return
        }
        await finish(capture, swipeUUID: swipeUUID, note: note)
    }

    static func run(swipeUUID: String, url: URL, note: String?) async {
        guard let capture = await SwipePageCapture.capture(url: url, swipeUUID: swipeUUID) else {
            await failCapture(swipeUUID: swipeUUID)
            return
        }
        await finish(capture, swipeUUID: swipeUUID, note: note)
    }

    /// The email path: the HTML is already in hand (SwipeEmailCapture), so
    /// the render starts from the string, not a fetch.
    static func run(swipeUUID: String, htmlString: String, note: String?) async {
        guard let capture = await SwipePageCapture.capture(
            htmlString: htmlString, baseURL: nil, swipeUUID: swipeUUID
        ) else {
            await failCapture(swipeUUID: swipeUUID)
            return
        }
        await finish(capture, swipeUUID: swipeUUID, note: note)
    }

    private static func finish(
        _ capture: SwipePageCapture.Capture,
        swipeUUID: String,
        note: String?
    ) async {
        guard let live = try? await AtomRepository.shared.fetch(uuid: swipeUUID),
              var artifact = live.swipeArtifact else { return }

        // Land the slices FIRST. The render is the expensive, unrepeatable
        // part (the session that got past the opt-in may be gone by the time a
        // model call fails), so the page is stored before it is read.
        for attachment in capture.attachments {
            _ = try? await MediaAttachmentRepository.shared.create(attachment)
        }
        AttachmentCloudStore.kick()

        artifact.units = capture.units
        artifact.pageTitle = capture.probe.title ?? artifact.pageTitle
        // Second seed tier: the measured page shape, only when the URL seed
        // said nothing (host identity is the stronger prior). Runs BEFORE the
        // model call so the swipe sits in the right space even while the read
        // is in flight — and stays there if the read fails.
        if artifact.genre == nil, let shapeSeed = SwipeGenreSeed.infer(shape: capture.probe.shape) {
            artifact.genre = shapeSeed
        }
        var staged = live.withSwipeArtifact(artifact)
        staged.updateResearchMetadata { meta in
            meta.processingStatus = "analyzing"
            if let genre = artifact.genre, !genre.isStructuralFallback(for: artifact.kind) {
                meta.swipeGenre = genre.rawValue
            }
            if let thumbnail = capture.attachments.first(where: { $0.metadata?.contains("pageIndex\":0") == true })?
                .thumbnailPath ?? capture.attachments.last?.thumbnailPath {
                // The card's artwork is the page's HERO slice, not the tall
                // full-page map — a 20,000px strip shrunk into a card is grey.
                meta.thumbnailUrl = URL(fileURLWithPath: thumbnail).absoluteString
            }
        }
        _ = try? await AtomRepository.shared.update(staged)
        NotificationCenter.default.post(name: CosmoNotification.SwipeFile.libraryDidChange, object: nil)

        // Third filing tier: both seeds said nothing, so the cheap classifier
        // reads the sliced text and names the room — in parallel with (and
        // surviving the failure of) the craft pass behind it. Fill-only.
        if artifact.genre == nil, artifact.genreLockedByUser != true {
            let probeText = ([capture.probe.title ?? ""] + capture.units.compactMap(\.copy))
                .joined(separator: "\n")
            let url = staged.researchMetadata?.url
            let body = staged.body
            Task {
                let verdict = await SwipeGenreClassifier.classify(
                    pageText: probeText, url: url, note: body
                )
                await SwipeGenreClassifier.fill(verdict, intoAtomWithUUID: swipeUUID)
            }
        }

        let result = await SwipeArtifactAnalyzer.analyze(
            atom: staged, artifact: artifact, userNote: note
        )
        await SwipeArtifactPersistence.apply(result, toAtomWithUUID: swipeUUID, artifact: artifact)
    }

    /// A page we could not render stays a real, correctly-typed swipe with its
    /// URL — the user can open it, and a retry can try again. It never
    /// silently becomes an untyped research row.
    private static func failCapture(swipeUUID: String) async {
        guard let live = try? await AtomRepository.shared.fetch(uuid: swipeUUID) else { return }
        var atom = live
        atom.updateResearchMetadata { $0.processingStatus = "extraction_failed" }
        _ = try? await AtomRepository.shared.update(atom)
        NotificationCenter.default.post(name: CosmoNotification.SwipeFile.libraryDidChange, object: nil)
    }
}

// MARK: - Persistence

/// Where every artifact decomposition lands.
///
/// PERSIST-BY-UUID LAW: the uuid is captured at schedule time and the live row
/// is re-fetched after the model call, so a pass that finishes after the user
/// navigated away writes to the swipe it analysed — never to whatever is on
/// screen now. This is the same rule (and the same bug) as
/// SwipeStudyModel.persistAnalysis.
@MainActor
enum SwipeArtifactPersistence {

    static func apply(
        _ result: SwipeArtifactAnalyzer.Result?,
        toAtomWithUUID uuid: String,
        artifact: SwipeArtifact
    ) async {
        guard let live = try? await AtomRepository.shared.fetch(uuid: uuid) else { return }

        var updated = artifact
        // Never regress the filing: `artifact` is a snapshot from schedule
        // time, and the cheap classifier (or a "File under →") may have
        // written genre onto the LIVE row while the craft pass was in
        // flight. Carry the live filing forward before the verdict applies.
        if updated.genre == nil { updated.genre = live.swipeArtifact?.genre }
        if updated.genreLockedByUser != true {
            updated.genreLockedByUser = live.swipeArtifact?.genreLockedByUser
        }
        if let result {
            updated.units = result.units
            updated.anatomy = result.anatomy
            updated.analyzedAt = ISO8601.string(from: Date())
            if let detected = artifact.detectedSource { updated.detectedSource = detected }
            // The analyzer read the whole artifact, so its genre verdict beats
            // the capture-time seed — but never a human's "File under →".
            if let genre = result.genre, updated.genreLockedByUser != true {
                updated.genre = genre
            }
        }

        var atom = live.withSwipeArtifact(updated)
        if let result {
            let merged = result.analysis.preservingCuratedFields(from: live.swipeAnalysis)
            atom = atom.withSwipeAnalysis(merged)
            if let title = merged.displayTitle, !title.isEmpty,
               !AtomRepository.shared.isBeingEdited(uuid) {
                atom.title = title
            }
        }
        atom.updateResearchMetadata { meta in
            meta.processingStatus = result == nil ? "partial" : "complete"
            if let hook = result?.analysis.hookText, !hook.isEmpty { meta.hook = hook }
            // Keep the hint in lockstep with the envelope (absence = default).
            if let genre = updated.genre {
                meta.swipeGenre = genre.isStructuralFallback(for: updated.kind)
                    ? nil : genre.rawValue
            }
        }

        _ = try? await AtomRepository.shared.update(atom)
        await RecallIndexer.shared.noteAtomChanged(uuid: uuid)
        NotificationCenter.default.post(name: CosmoNotification.SwipeFile.libraryDidChange, object: nil)
    }
}
