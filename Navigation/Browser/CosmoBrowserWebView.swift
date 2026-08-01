// CosmoOS/Navigation/Browser/CosmoBrowserWebView.swift
// WKWebView bridge for the browser pane, plus the system authentication
// coordinator for OAuth flows that block embedded browsers.

import SwiftUI
import WebKit
import AppKit
import AuthenticationServices

@MainActor
@Observable
final class CosmoBrowserSystemAuthenticationCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private(set) var isAuthenticating = false

    private var session: ASWebAuthenticationSession?
    private var anchor: ASPresentationAnchor?

    func start(url: URL) -> Bool {
        session?.cancel()

        let authenticationSession = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { [weak self] _, _ in
            Task { @MainActor in
                self?.isAuthenticating = false
                self?.session = nil
            }
        }
        authenticationSession.prefersEphemeralWebBrowserSession = false
        authenticationSession.presentationContextProvider = self

        anchor = NSApp.keyWindow ?? NSApp.mainWindow
        session = authenticationSession
        isAuthenticating = true

        let didStart = authenticationSession.start()
        if !didStart {
            isAuthenticating = false
            session = nil
        }
        return didStart
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor ?? NSApp.keyWindow ?? NSApp.mainWindow ?? ASPresentationAnchor()
    }
}

/// The out-of-band lane for a link dragged out of a browser pane. The drag
/// PASTEBOARD cannot be trusted to carry it: WebKit bundles page-authored
/// drag types into org.webkit.custom-pasteboard-data (unreadable to AppKit),
/// and sites like Instagram rewrite the drag data anyway — the observed drop
/// arrives as plain text at best. So the drag bridge mirrors the permalink
/// here at dragstart, and the canvas drop consults it only when the drop's
/// own providers carried no web URL (⌘K precedent: session-driven placement
/// when the pasteboard is too weak). macOS runs ONE drag at a time, so a
/// fresh session IS the drag being dropped; dragend plus a short grace
/// window retires it so a later unrelated drop can never adopt a stale link.
enum BrowserPaneLinkDragSession {
    private static var url: String?
    private static var armedAt: Date?
    private static var endedAt: Date?

    /// Grace after dragend: the canvas drop's async provider loading runs a
    /// beat AFTER the page already saw dragend — clearing instantly would
    /// re-lose the very drop this session exists to save.
    private static let postEndGrace: TimeInterval = 3
    /// A webview that dies mid-drag never sends dragend; staleness caps it.
    private static let maxAge: TimeInterval = 30

    static var isArmed: Bool { currentURL(now: Date()) != nil }

    static func arm(url: String) {
        self.url = url
        armedAt = Date()
        endedAt = nil
    }

    static func noteDragEnded() {
        endedAt = Date()
    }

    static func consume() -> String? {
        defer { url = nil; armedAt = nil; endedAt = nil }
        return currentURL(now: Date())
    }

    /// Exposed for tests — the freshness ladder with an injectable clock.
    static func currentURL(now: Date) -> String? {
        guard let url, let armedAt else { return nil }
        guard now.timeIntervalSince(armedAt) < maxAge else { return nil }
        if let endedAt, now.timeIntervalSince(endedAt) > postEndGrace { return nil }
        return url
    }
}

struct CosmoBrowserWebView: NSViewRepresentable {
    let state: CosmoWebBrowserState
    var paneId: String? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, paneId: paneId)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = state.profile.websiteDataMode.makeDataStore()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController = context.coordinator.userContentController
        config.applicationNameForUserAgent = CosmoBrowserUserAgent.applicationName

        let webView = CosmoBrowserWKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        context.coordinator.installDeleteKeyMonitor(for: webView)
        context.coordinator.installWebViewObservers(for: webView)
        state.attach(webView)
        context.coordinator.lastNavigationRequestID = state.navigationRequest.id
        webView.load(URLRequest(url: state.navigationRequest.url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastNavigationRequestID != state.navigationRequest.id else { return }
        context.coordinator.lastNavigationRequestID = state.navigationRequest.id
        webView.load(URLRequest(url: state.navigationRequest.url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let state: CosmoWebBrowserState
        let paneId: String?
        weak var webView: WKWebView?
        let userContentController: WKUserContentController
        var lastNavigationRequestID: UUID?
        private var deleteKeyMonitor: Any?
        private var webViewObservations: [NSKeyValueObservation] = []

        init(state: CosmoWebBrowserState, paneId: String? = nil) {
            self.state = state
            self.paneId = paneId
            self.userContentController = WKUserContentController()
            super.init()
            installSelectionBridge()
            installDragBridge()
        }

        deinit {
            if let deleteKeyMonitor {
                NSEvent.removeMonitor(deleteKeyMonitor)
            }
            webViewObservations.forEach { $0.invalidate() }
            userContentController.removeScriptMessageHandler(forName: "cosmoSelection")
            userContentController.removeScriptMessageHandler(forName: "cosmoLinkDrag")
        }

        private func installSelectionBridge() {
            let script = WKUserScript(
                source: """
                (function() {
                    let lastSelection = '';
                    function notifySelection() {
                        const selection = window.getSelection ? window.getSelection().toString() : '';
                        if (selection !== lastSelection) {
                            lastSelection = selection;
                            window.webkit.messageHandlers.cosmoSelection.postMessage(selection);
                        }
                    }
                    document.addEventListener('mouseup', notifySelection);
                    document.addEventListener('keyup', notifySelection);
                    document.addEventListener('selectionchange', function() {
                        window.clearTimeout(window.__cosmoSelectionTimer);
                        window.__cosmoSelectionTimer = window.setTimeout(notifySelection, 120);
                    });
                })();
                """,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
            userContentController.addUserScript(script)
            userContentController.add(self, name: "cosmoSelection")
        }

        /// Instagram fights drag-out: grid tiles and post media are marked
        /// undraggable, and when an image drag does start it carries the CDN
        /// asset URL, not the post. This bridge makes the post PERMALINK the
        /// drag payload — mousedown re-arms dragging on the tile's anchor,
        /// and dragstart stamps the permalink into the drag pasteboard
        /// (WebKit maps text/uri-list to public.url, which the canvas drop
        /// delegate reads). Gated to instagram.com; every other site's native
        /// drag behaviour is untouched.
        private func installDragBridge() {
            let script = WKUserScript(
                source: """
                (function() {
                    if (!/(^|\\.)instagram\\.com$/.test(location.hostname)) { return; }
                    const POST_ANCHOR = 'a[href*="/p/"], a[href*="/reel/"]';
                    function permalink(node) {
                        const anchor = node instanceof Element ? node.closest(POST_ANCHOR) : null;
                        if (anchor && anchor.href) { return anchor.href; }
                        // An open post rewrites the location to its permalink —
                        // dragging the lightbox media falls back to that.
                        if (/^\\/(?:[^/]+\\/)?(p|reel)\\//.test(location.pathname)) { return location.href; }
                        return null;
                    }
                    document.addEventListener('mousedown', function(event) {
                        const anchor = event.target instanceof Element ? event.target.closest(POST_ANCHOR) : null;
                        if (!anchor) { return; }
                        anchor.draggable = true;
                        anchor.style.webkitUserDrag = 'element';
                    }, true);
                    document.addEventListener('dragstart', function(event) {
                        const url = permalink(event.target);
                        // Mirror out-of-band: WebKit may not surface these
                        // dataTransfer entries to AppKit (custom-pasteboard
                        // bundling), and the page may rewrite them.
                        try {
                            window.webkit.messageHandlers.cosmoLinkDrag.postMessage({
                                phase: 'start',
                                url: url || null,
                                tag: event.target.tagName || '?'
                            });
                        } catch (e) {}
                        if (!url || !event.dataTransfer) { return; }
                        event.dataTransfer.setData('text/uri-list', url);
                        event.dataTransfer.setData('text/plain', url);
                    }, true);
                    document.addEventListener('dragend', function(event) {
                        try {
                            window.webkit.messageHandlers.cosmoLinkDrag.postMessage({ phase: 'end' });
                        } catch (e) {}
                    }, true);
                })();
                """,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
            userContentController.addUserScript(script)
            userContentController.add(self, name: "cosmoLinkDrag")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "cosmoLinkDrag", let body = message.body as? [String: Any] {
                let phase = body["phase"] as? String
                if phase == "start" {
                    if let url = body["url"] as? String, !url.isEmpty {
                        BrowserPaneLinkDragSession.arm(url: url)
                    }
                    CanvasDropDebugLog.note("browser bridge: dragstart tag=\(body["tag"] as? String ?? "?") permalink=\(body["url"] as? String ?? "NONE")")
                } else if phase == "end" {
                    BrowserPaneLinkDragSession.noteDragEnded()
                    CanvasDropDebugLog.note("browser bridge: dragend")
                }
                return
            }
            guard message.name == "cosmoSelection", let text = message.body as? String else { return }
            Task { @MainActor in
                state.updateSelectedText(text)
            }
        }

        func installDeleteKeyMonitor(for webView: WKWebView) {
            if let deleteKeyMonitor {
                NSEvent.removeMonitor(deleteKeyMonitor)
            }

            deleteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak webView] event in
                guard let webView,
                      Self.isPlainDeleteKey(event),
                      Self.browserOwnsFirstResponder(in: event.window, webView: webView)
                else {
                    return event
                }

                event.window?.firstResponder?.keyDown(with: event)
                return nil
            }
        }

        func installWebViewObservers(for webView: WKWebView) {
            webViewObservations.forEach { $0.invalidate() }
            webViewObservations = [
                webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                    self?.updateState(from: webView)
                }
            ]
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            updateState(from: webView, clearError: true)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            updateState(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateState(from: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            failState(with: error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            failState(with: error)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let scheme = url.scheme?.lowercased()
            guard scheme == "http" || scheme == "https" || scheme == "about" else {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            // ⌘-click a link → open in split beside this pane. Deliberate
            // user gesture only; plain target=_blank still loads in place —
            // a site can never spawn panes, only the user can.
            if navigationAction.navigationType == .linkActivated,
               navigationAction.modifierFlags.contains(.command) {
                postSplitOpen(url: url)
                decisionHandler(.cancel)
                return
            }

            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        private func postSplitOpen(url: URL) {
            var userInfo: [String: Any] = [
                "url": url,
                "disposition": BrowserOpenDisposition.split.rawValue
            ]
            if let paneId {
                userInfo["sourcePaneId"] = paneId
            }
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openWebBrowserPane,
                object: nil,
                userInfo: userInfo
            )
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        private func updateState(from webView: WKWebView, clearError: Bool = false) {
            let url = webView.url
            let title = webView.title
            let isLoading = webView.isLoading
            let estimatedProgress = webView.estimatedProgress
            let canGoBack = webView.canGoBack
            let canGoForward = webView.canGoForward

            Task { @MainActor in
                if clearError {
                    state.clearError()
                }
                state.applySnapshot(
                    url: url,
                    title: title,
                    isLoading: isLoading,
                    estimatedProgress: estimatedProgress,
                    canGoBack: canGoBack,
                    canGoForward: canGoForward
                )
            }
        }

        private func failState(with error: Error) {
            let message = error.localizedDescription
            Task { @MainActor in
                state.fail(with: NSError(domain: "CosmoWebBrowserPane", code: 0, userInfo: [NSLocalizedDescriptionKey: message]))
            }
        }

        private static func isPlainDeleteKey(_ event: NSEvent) -> Bool {
            guard event.keyCode == 51 || event.keyCode == 117 else { return false }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            return !modifiers.contains(.command) && !modifiers.contains(.control)
        }

        private static func browserOwnsFirstResponder(in window: NSWindow?, webView: WKWebView) -> Bool {
            guard let responder = window?.firstResponder else { return false }

            if responder === webView {
                return true
            }

            if let responderView = responder as? NSView {
                return responderView === webView || responderView.isDescendant(of: webView)
            }

            return String(describing: type(of: responder)).contains("WK")
        }
    }
}

final class CosmoBrowserWKWebView: WKWebView {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}
