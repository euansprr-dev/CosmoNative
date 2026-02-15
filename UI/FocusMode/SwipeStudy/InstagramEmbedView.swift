// CosmoOS/UI/FocusMode/SwipeStudy/InstagramEmbedView.swift
// Instagram embed view using WKWebView for in-app viewing of reels, posts, and carousels
// February 2026

import SwiftUI
import WebKit

/// Embeds Instagram content (reels, posts, carousels) via Instagram's public embed endpoint.
/// Uses the same NSViewRepresentable + WKWebView pattern as YouTubeFocusModePlayer.
struct InstagramEmbedView: NSViewRepresentable {
    let embedUrl: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard !context.coordinator.hasLoaded else { return }
        context.coordinator.hasLoaded = true

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body {
                    width: 100%;
                    height: 100%;
                    background: #0A0A0F;
                    overflow: hidden;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                }
                iframe {
                    border: none;
                    border-radius: 12px;
                    max-width: 100%;
                    max-height: 100%;
                }
            </style>
        </head>
        <body>
            <iframe
                src="\(embedUrl)"
                width="400"
                height="500"
                frameborder="0"
                scrolling="no"
                allowtransparency="true"
                allowfullscreen="true"
            ></iframe>
        </body>
        </html>
        """
        nsView.loadHTMLString(html, baseURL: URL(string: "https://www.instagram.com"))
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var hasLoaded = false

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow the initial load and Instagram embed navigation
            if navigationAction.navigationType == .other || navigationAction.navigationType == .reload {
                decisionHandler(.allow)
                return
            }
            // Open external links in browser
            if let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

// MARK: - Helpers

extension InstagramEmbedView {
    /// Build an embed URL from an Instagram shortcode and content type
    static func embedUrl(shortcode: String, contentType: ResearchRichContent.InstagramContentType?) -> String {
        switch contentType {
        case .reel:
            return "https://www.instagram.com/reel/\(shortcode)/embed/"
        default:
            return "https://www.instagram.com/p/\(shortcode)/embed/"
        }
    }

    /// Extract Instagram shortcode from various URL formats
    static func extractShortcode(from url: String) -> String? {
        // Patterns: /p/ABC123/, /reel/ABC123/, /reels/ABC123/
        let patterns = [
            #"/p/([A-Za-z0-9_-]+)"#,
            #"/reel/([A-Za-z0-9_-]+)"#,
            #"/reels/([A-Za-z0-9_-]+)"#,
            #"/tv/([A-Za-z0-9_-]+)"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
               let range = Range(match.range(at: 1), in: url) {
                return String(url[range])
            }
        }
        return nil
    }
}
