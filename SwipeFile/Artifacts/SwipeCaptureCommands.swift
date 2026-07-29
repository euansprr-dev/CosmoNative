// CosmoOS/SwipeFile/Artifacts/SwipeCaptureCommands.swift
// The global swipe verbs (⌘⇧S, ⌥⌘⇧S) and the drop-provider bridge.
// Thin on purpose: every one of these resolves what the user is looking at and
// hands it to SwipeIntakeRouter. No capture logic lives here.

import Foundation
import AppKit
import WebKit
import UniformTypeIdentifiers

@MainActor
enum SwipeCaptureCommands {

    /// ⌘⇧S. Context ladder: the browser pane's live page beats the pasteboard,
    /// because if you are looking at a page that is obviously what you meant.
    static func swipeThis() {
        let source: SwipeIntakeRouter.Source
        let mode: String
        if let page = CosmoBrowserSwipeContext.frontmostPage() {
            source = .liveWebPage(url: page.url, title: page.title, webView: page.webView)
            mode = "browser_pane"
        } else {
            source = .pasteboard
            mode = "clipboard"
        }
        Task { await SwipeIntakeRouter.run(source, captureMode: mode) }
    }

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
