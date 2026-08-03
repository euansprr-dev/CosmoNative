// CosmoOS/UI/FocusMode/Inquiry/Source/WebSourceView.swift
// WKWebView wrapper for web sources in the Inquiry Source Pane.
// JS bridge reports user selections (text + rect) so the host can float
// a capture pill next to the highlight.

import SwiftUI
import WebKit

/// Load lifecycle for a web source, surfaced so the reader can show
/// spinner/failure states instead of a silent blank pane.
enum WebSourceLoadState: Equatable {
    case loading
    case loaded
    case failed(String)
}

struct WebSourceView: NSViewRepresentable {
    let url: URL
    let readerMode: Bool
    @Binding var lastSelectedText: String
    /// Selection's bounding rect in SwiftUI `.global` space, so the host can
    /// float a capture pill next to the highlight. Optional — hosts that keep
    /// their own fixed menu simply don't pass it.
    var selectionAnchor: Binding<CGRect?>? = nil
    var loadState: Binding<WebSourceLoadState>? = nil

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "selection")
        // JS that posts the selection (text + viewport rect) every time it
        // changes — including the empty selection, so the native pill can
        // dismiss when the highlight collapses.
        let script = WKUserScript(
            source: """
            (function() {
                let lastSel = '';
                function report() {
                    const sel = window.getSelection();
                    const text = sel ? sel.toString() : '';
                    if (text === lastSel) { return; }
                    lastSel = text;
                    let payload = { text: text, x: 0, y: 0, w: 0, h: 0 };
                    if (text && sel.rangeCount > 0) {
                        const r = sel.getRangeAt(0).getBoundingClientRect();
                        payload = { text: text, x: r.x, y: r.y, w: r.width, h: r.height };
                    }
                    window.webkit.messageHandlers.selection.postMessage(payload);
                }
                document.addEventListener('mouseup', report);
                document.addEventListener('keyup', report);
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        userContentController.addUserScript(script)
        config.userContentController = userContentController
        // Academic publishers (doi.org redirect targets) often refuse the
        // default embedded-WebKit user agent — present as Safari.
        config.applicationNameForUserAgent = CosmoBrowserUserAgent.applicationName

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        // If the URL changed, navigate. The new page starts without the reader
        // style, so the applied marker resets and didFinish re-applies it.
        if webView.url != url {
            context.coordinator.appliedReaderMode = nil
            webView.load(URLRequest(url: url))
        }
        // Reader mode is applied exactly once per state change — every other
        // SwiftUI render pass of the host must not cost a WebContent IPC.
        guard context.coordinator.appliedReaderMode != readerMode else { return }
        context.coordinator.appliedReaderMode = readerMode
        webView.evaluateJavaScript(readerMode ? Self.applyReaderCSS : Self.removeReaderCSS)
    }

    // Apply a simple reader-mode CSS overlay
    static let applyReaderCSS = """
    (function() {
        if (document.getElementById('cosmo-reader-style')) return;
        const style = document.createElement('style');
        style.id = 'cosmo-reader-style';
        style.textContent = `
          body { max-width: 720px !important; margin: 32px auto !important; line-height: 1.6 !important; font-family: 'New York', Georgia, serif !important; font-size: 17px !important; color: #1A1814 !important; background: #F8F7F4 !important; padding: 0 24px !important; }
          nav, header, footer, aside, .ad, .advertisement, .sidebar, [class*='banner'], [class*='popup'] { display: none !important; }
          img { max-width: 100% !important; height: auto !important; }
          pre, code { background: #F0EFEC !important; padding: 8px 12px !important; border-radius: 6px !important; font-size: 14px !important; }
          a { color: #2D6A4F !important; text-decoration: underline !important; }
        `;
        document.head.appendChild(style);
    })();
    """

    static let removeReaderCSS = """
    (function() {
        const s = document.getElementById('cosmo-reader-style');
        if (s) s.remove();
    })();
    """

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebSourceView
        /// The reader-mode state last pushed into the page. `nil` after a
        /// navigation (fresh pages carry no reader style).
        var appliedReaderMode: Bool?
        init(parent: WebSourceView) { self.parent = parent }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "selection" else { return }
            // Rich payload: text + selection rect in the page's viewport
            // coordinates (== the web view's local space at default zoom).
            if let dict = message.body as? [String: Any], let text = dict["text"] as? String {
                let webView = message.webView
                Task { @MainActor in
                    guard !text.isEmpty else {
                        parent.lastSelectedText = ""
                        parent.selectionAnchor?.wrappedValue = nil
                        return
                    }
                    parent.lastSelectedText = text
                    if let webView,
                       let x = dict["x"] as? Double, let y = dict["y"] as? Double,
                       let w = dict["w"] as? Double, let h = dict["h"] as? Double {
                        let local = CGRect(x: x, y: y, width: w, height: h)
                        parent.selectionAnchor?.wrappedValue =
                            SelectionAnchorSpace.globalRect(fromLocal: local, in: webView)
                    }
                }
            } else if let text = message.body as? String {
                Task { @MainActor in
                    parent.lastSelectedText = text
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            setLoadState(.loading)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // A fresh page never carries the reader style — apply the current
            // state here deterministically instead of waiting for a host
            // re-render to happen to call updateNSView.
            appliedReaderMode = parent.readerMode
            if parent.readerMode {
                webView.evaluateJavaScript(WebSourceView.applyReaderCSS)
            }
            setLoadState(.loaded)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            reportFailure(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            reportFailure(error)
        }

        private func reportFailure(_ error: Error) {
            let nsError = error as NSError
            // Redirect-triggered cancellations are not real failures.
            guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else { return }
            setLoadState(.failed(error.localizedDescription))
        }

        private func setLoadState(_ state: WebSourceLoadState) {
            guard let binding = parent.loadState else { return }
            Task { @MainActor in
                binding.wrappedValue = state
            }
        }
    }
}
