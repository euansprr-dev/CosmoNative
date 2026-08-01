// CosmoOS/SwipeFile/Artifacts/SwipeCaptureCommands.swift
// The global swipe verbs (⌘⇧S, ⌥⌘⇧S) and the drop-provider bridge.
// Thin on purpose: every one of these resolves what the user is looking at and
// hands it to SwipeIntakeRouter. No capture logic lives here.

import Foundation
import AppKit
import WebKit
import UniformTypeIdentifiers
import PDFKit

@MainActor
enum SwipeCaptureCommands {

    /// ⌘⇧S. Context ladder: the browser pane's live page beats everything; a
    /// FRESH pasteboard (something copied since the last capture) beats your
    /// real browser's front tab — copying IS intent, and "copy the full
    /// text, ⌘⇧S" is a taught flow; a STALE pasteboard loses to the browser
    /// tab, because "⌘⇧S captures whatever old thing was on the clipboard"
    /// was exactly the broken feeling this rung exists to fix. You read a
    /// Substack issue in Chrome, ⌘tab to Cosmo, ⌘⇧S — it files under
    /// Newsletters.
    static func swipeThis() {
        Task {
            if let page = CosmoBrowserSwipeContext.frontmostPage() {
                await SwipeIntakeRouter.run(
                    .liveWebPage(url: page.url, title: page.title, webView: page.webView),
                    captureMode: "browser_pane"
                )
                return
            }
            let pasteboard = NSPasteboard.general
            let isFresh = pasteboard.changeCount != lastUsedPasteboardChangeCount
            lastUsedPasteboardChangeCount = pasteboard.changeCount
            if !isFresh, let external = ExternalBrowserTab.current() {
                await SwipeIntakeRouter.run(.url(external), captureMode: "external_browser")
            } else {
                await SwipeIntakeRouter.run(.pasteboard, captureMode: "clipboard")
            }
        }
    }

    /// The pasteboard state the last ⌘⇧S already consumed. -1 = never — the
    /// first press after launch always trusts the clipboard (old behavior).
    private static var lastUsedPasteboardChangeCount = -1

    /// ⌥⌘⇧S. `screencapture -i -c` gives the standard system crosshair and
    /// puts the result on the pasteboard, so the frame path picks it up
    /// unchanged — no new window, no new permission beyond Screen Recording
    /// (which macOS prompts for on first use).
    static func swipeRegion() {
        Task {
            guard await runInteractiveScreenCapture() else { return }
            // The pasteboard write lands a beat after the process exits.
            try? await Task.sleep(for: .milliseconds(150))
            let payloads = SwipeIntakeRouter.imagePayloads(from: NSPasteboard.general)
            guard !payloads.isEmpty else {
                // Cancelling the crosshair (Esc) is not an error — say nothing.
                return
            }
            await SwipeIntakeRouter.run(.images(payloads), captureMode: "region")
        }
    }

    /// True when the capture produced something (exit status 0 and not
    /// cancelled). `screencapture` exits 0 on cancel too, so the caller checks
    /// the pasteboard rather than trusting this alone.
    private static func runInteractiveScreenCapture() async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-c"]
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                print("SwipeCaptureCommands: screencapture failed to launch: \(error)")
                SwipeIntakeReceiptCenter.shared.publishError(
                    "Couldn't start the screen capture — check Screen Recording permission in System Settings."
                )
                continuation.resume(returning: false)
            }
        }
    }

    // MARK: - File import (the "From a File…" seat)

    /// One open panel for everything the drop targets accept. The panel is a
    /// capture surface like any other: it gathers files and hands them to the
    /// SAME import ladder the drops use, so the two can never diverge.
    static func importFromOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = importableTypes
        panel.message = "Choose images, PDFs, or emails to swipe"
        panel.begin { response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in await importFiles(urls: urls) }
        }
    }

    static var importableTypes: [UTType] {
        var types: [UTType] = [.image, .pdf]
        if let eml = UTType(filenameExtension: "eml") { types.append(eml) }
        if let emlx = UTType(filenameExtension: "emlx") { types.append(emlx) }
        return types
    }

    /// Route a set of file URLs into capture. Images gather into ONE frame
    /// swipe (a multi-select is one artifact, not N library rows); every
    /// other supported type captures individually.
    static func importFiles(urls: [URL]) async {
        var imagePayloads: [SwipeImagePayload] = []
        for url in urls {
            guard let type = UTType(filenameExtension: url.pathExtension) else { continue }
            if type.conforms(to: .image), let data = try? Data(contentsOf: url) {
                imagePayloads.append(SwipeImagePayload(
                    data: data, filename: url.lastPathComponent,
                    mimeType: type.preferredMIMEType, utType: type
                ))
            } else if type.conforms(to: .pdf) {
                let payloads = pdfPagePayloads(from: url)
                guard !payloads.isEmpty else { continue }
                await SwipeIntakeRouter.run(.images(payloads), captureMode: "file_import")
            } else if url.pathExtension.lowercased() == "eml" || url.pathExtension.lowercased() == "emlx" {
                await importEmail(fileURL: url, captureMode: "file_import")
            }
        }
        if !imagePayloads.isEmpty {
            await SwipeIntakeRouter.run(.images(imagePayloads), captureMode: "file_import")
        }
    }

    // MARK: - Email + PDF drops

    /// Capture any emails and PDFs among dropped providers. Returns true when
    /// something was captured this way — the caller then skips its image/link
    /// ladder. Mail.app drags arrive as `public.email-message` data; Finder
    /// drags of .eml/.emlx/.pdf arrive as file URLs. Both roads lead to the
    /// same two front doors the open panel uses.
    static func captureSpecialFiles(from providers: [NSItemProvider], boardIDs: [String] = []) async -> Bool {
        var captured = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.emailMessage.identifier),
               let data = await loadData(from: provider, type: .emailMessage),
               let payload = SwipeEmailCapture.parse(data: data) {
                await SwipeIntakeRouter.run(.email(payload), boardIDs: boardIDs, captureMode: "drop")
                captured = true
                continue
            }
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                  let url = await loadFileURL(from: provider) else { continue }
            switch url.pathExtension.lowercased() {
            case "eml", "emlx":
                await importEmail(fileURL: url, captureMode: "drop")
                captured = true
            case "pdf":
                let payloads = pdfPagePayloads(from: url)
                if !payloads.isEmpty {
                    await SwipeIntakeRouter.run(.images(payloads), boardIDs: boardIDs, captureMode: "drop")
                    captured = true
                }
            default:
                break
            }
        }
        return captured
    }

    // MARK: - PDF pages → frame payloads

    /// Render a PDF's pages into image payloads — a swiped PDF (a funnel
    /// teardown, a lead magnet, a printed script) is a frame set, one page
    /// per unit. Capped: past 30 pages it's a book, not a reference.
    static func pdfPagePayloads(from url: URL) -> [SwipeImagePayload] {
        guard let document = PDFDocument(url: url) else { return [] }
        let pageCount = min(document.pageCount, 30)
        var payloads: [SwipeImagePayload] = []
        for index in 0..<pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { continue }
            let scale: CGFloat = 2
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let image = NSImage(size: size, flipped: false) { rect in
                NSColor.white.setFill()
                rect.fill()
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                context.scaleBy(x: scale, y: scale)
                page.draw(with: .mediaBox, to: context)
                return true
            }
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
            else { continue }
            payloads.append(SwipeImagePayload(
                data: jpeg,
                filename: "\(url.deletingPathExtension().lastPathComponent)-p\(index + 1).jpg",
                mimeType: "image/jpeg", utType: .jpeg
            ))
        }
        return payloads
    }

    // MARK: - Email files → the Newsletters front door

    /// Read an .eml/.emlx from disk and capture it as a page artifact. The
    /// parse failure mode is honest: an unreadable email publishes an error
    /// receipt rather than silently dropping the file.
    static func importEmail(fileURL: URL, captureMode: String) async {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = SwipeEmailCapture.parse(data: data) else {
            SwipeIntakeReceiptCenter.shared.publishError("Couldn't read that email file.")
            return
        }
        await SwipeIntakeRouter.run(.email(payload), captureMode: captureMode)
    }

    // MARK: - Drop bridge

    /// Turn dropped item providers into image payloads.
    ///
    /// Reuses `InboxDropIngestService.attachmentKind(for:)`'s type vocabulary
    /// rather than re-deriving it: a drop that is NOT a set of images is not a
    /// frame swipe, and the caller falls back to the URL/text ladder.
    static func imagePayloads(from providers: [NSItemProvider]) async -> [SwipeImagePayload] {
        var payloads: [SwipeImagePayload] = []
        for provider in providers {
            if let payload = await imagePayload(from: provider) {
                payloads.append(payload)
            }
        }
        return payloads
    }

    private static func imagePayload(from provider: NSItemProvider) async -> SwipeImagePayload? {
        // File URL first: it carries a real filename and avoids a re-encode.
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await loadFileURL(from: provider),
           let type = UTType(filenameExtension: url.pathExtension),
           type.conforms(to: .image),
           let data = try? Data(contentsOf: url) {
            return SwipeImagePayload(
                data: data, filename: url.lastPathComponent,
                mimeType: type.preferredMIMEType, utType: type
            )
        }
        for type in [UTType.png, .jpeg, .tiff, .heic, .image] {
            guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { continue }
            if let data = await loadData(from: provider, type: type) {
                return SwipeImagePayload(
                    data: data, filename: nil,
                    mimeType: type.preferredMIMEType, utType: type
                )
            }
        }
        return nil
    }

    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    private static func loadData(from provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

// MARK: - External browser front tab

/// The active tab of the user's REAL browser, read by Apple Events. Asked
/// only from ⌘⇧S's stale-pasteboard rung. First use per browser shows the
/// system automation consent; a denial (or no browser running, or a window
/// showing no page) answers nil and the ladder falls through silently —
/// never an error for a permission the user declined.
///
/// When several browsers run, priority order decides — almost everyone has
/// ONE primary browser, and a wrong pick is one click from correction (the
/// receipt names what was captured).
@MainActor
enum ExternalBrowserTab {

    static let browsers: [(bundleID: String, script: String)] = [
        ("com.google.Chrome", chromiumScript("Google Chrome")),
        ("company.thebrowser.Browser", chromiumScript("Arc")),
        ("company.thebrowser.dia", chromiumScript("Dia")),
        ("com.brave.Browser", chromiumScript("Brave Browser")),
        ("com.microsoft.edgemac", chromiumScript("Microsoft Edge")),
        ("com.apple.Safari",
         "tell application \"Safari\" to if (count of windows) > 0 then get URL of current tab of front window"),
    ]

    static func current() -> String? {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for browser in browsers where running.contains(browser.bundleID) {
            guard let script = NSAppleScript(source: browser.script) else { continue }
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if error == nil, let url = result.stringValue,
               url.lowercased().hasPrefix("http") {
                return url
            }
        }
        return nil
    }

    /// Chromium browsers share one scripting dictionary; only the app name
    /// differs. `if … then get` answers missing value on an empty window,
    /// which reads back as a nil stringValue — handled, not an error.
    private static func chromiumScript(_ name: String) -> String {
        "tell application \"\(name)\" to if (count of windows) > 0 then get URL of active tab of front window"
    }
}

// MARK: - Browser pane context

/// What the frontmost browser pane is showing, if one is frontmost at all.
///
/// Kept as its own seam so ⌘⇧S never reaches into pane internals: the pane
/// registers a closure when it becomes active, and the capture commands ask
/// this one question. The webview rides along because a page swipe must read
/// the page AS RENDERED — your session, your scroll, past the opt-in. Almost
/// every funnel worth swiping is behind something.
@MainActor
enum CosmoBrowserSwipeContext {
    struct Page {
        var url: String
        var title: String?
        var webView: WKWebView?
    }

    /// The most recently ACTIVATED browser pane wins. Keyed by pane id so a
    /// pane that closes can retract only its own registration — with several
    /// browser panes open, a bare "last register wins" would leave ⌘⇧S
    /// pointing at a pane that is gone.
    private static var providers: [(paneId: String, provider: @MainActor () -> Page?)] = []

    static func register(paneId: String, _ provider: @escaping @MainActor () -> Page?) {
        providers.removeAll { $0.paneId == paneId }
        providers.append((paneId, provider))
    }

    static func clear(paneId: String) {
        providers.removeAll { $0.paneId == paneId }
    }

    /// nil when no browser pane is active, or it has nothing real loaded.
    static func frontmostPage() -> Page? {
        guard let page = providers.last?.provider() else { return nil }
        guard !page.url.isEmpty, page.url.lowercased().hasPrefix("http") else { return nil }
        return page
    }
}
