// CosmoOS/UI/FocusMode/Inquiry/Source/WebSourceView.swift
// WKWebView wrapper for web sources in the Inquiry Source Pane.
// JS bridge captures user selections and forwards them to a SaveAsExtract sheet.

import SwiftUI
import WebKit

struct WebSourceView: NSViewRepresentable {
    let url: URL
    let readerMode: Bool
    @Binding var lastSelectedText: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "selection")
        // JS that posts selection text to the native side every time it changes.
        let script = WKUserScript(
            source: """
            (function() {
                let lastSel = '';
                document.addEventListener('mouseup', () => {
                    const text = window.getSelection().toString();
                    if (text && text !== lastSel) {
                        lastSel = text;
                        window.webkit.messageHandlers.selection.postMessage(text);
                    }
                });
                document.addEventListener('keyup', () => {
                    const text = window.getSelection().toString();
                    if (text && text !== lastSel) {
                        lastSel = text;
                        window.webkit.messageHandlers.selection.postMessage(text);
                    }
                });
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        userContentController.addUserScript(script)
        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // If the URL changed, navigate
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
        if readerMode {
            // Apply a simple reader-mode CSS overlay
            let css = """
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
            webView.evaluateJavaScript(css)
        } else {
            let removeCSS = """
            (function() {
                const s = document.getElementById('cosmo-reader-style');
                if (s) s.remove();
            })();
            """
            webView.evaluateJavaScript(removeCSS)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebSourceView
        init(parent: WebSourceView) { self.parent = parent }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "selection", let text = message.body as? String {
                Task { @MainActor in
                    parent.lastSelectedText = text
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Apply reader mode on first load (re-applied via updateNSView)
        }
    }
}
