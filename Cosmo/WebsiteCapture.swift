// CosmoOS/Cosmo/WebsiteCapture.swift
// Website screenshot capture using WKWebView
// Captures full-quality screenshots for research preview

import Foundation
import WebKit
import AppKit

// MARK: - Website Data
struct WebsiteData {
    let url: URL
    let title: String
    let screenshot: NSImage?
    let summary: String?
    let domain: String
    let favicon: URL?
}

// MARK: - Website Capture
@MainActor
final class WebsiteCapture: NSObject {
    static let shared = WebsiteCapture()

    private var pendingCaptures: [UUID: PendingCapture] = [:]
    private let queue = DispatchQueue(label: "com.cosmo.websitecapture")

    private struct PendingCapture {
        let webView: WKWebView
        let continuation: CheckedContinuation<NSImage, Error>
        let timeoutTask: Task<Void, Never>?
    }

    private override init() {
        super.init()
    }

    // MARK: - Process Website
    /// Full pipeline: screenshot + AI summary
    func process(url: URL, progressHandler: ((WebsiteProcessingStep) -> Void)? = nil) async throws -> WebsiteData {
        print("🌐 Processing website: \(url.absoluteString)")

        let domain = url.host?.replacingOccurrences(of: "www.", with: "") ?? "unknown"

        // Step 1: Capture screenshot
        progressHandler?(.capturingScreenshot)
        let screenshot = try await capture(url: url)
        print("   Screenshot captured")

        // Step 2: Fetch page title
        progressHandler?(.fetchingMetadata)
        let title = await fetchTitle(url: url) ?? domain

        // Step 3: Generate AI summary (via OpenRouter)
        progressHandler?(.summarizing)
        let summary = try await generateSummary(url: url, title: title)

        progressHandler?(.complete)

        return WebsiteData(
            url: url,
            title: title,
            screenshot: screenshot,
            summary: summary,
            domain: domain,
            favicon: URL(string: "https://\(domain)/favicon.ico")
        )
    }

    // MARK: - Capture Screenshot
    /// Capture a screenshot of a URL
    func capture(
        url: URL,
        size: CGSize = CGSize(width: 1280, height: 800),
        timeout: TimeInterval = 30
    ) async throws -> NSImage {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: CaptureError.captureCreationFailed)
                    return
                }

                let id = UUID()

                // Create web view configuration
                let config = WKWebViewConfiguration()
                config.websiteDataStore = .nonPersistent()

                // Enable JavaScript for dynamic content
                let prefs = WKWebpagePreferences()
                prefs.allowsContentJavaScript = true
                config.defaultWebpagePreferences = prefs

                // Create web view
                let webView = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: config)
                webView.navigationDelegate = self
                webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"

                // Set up timeout
                let timeoutTask = Task {
                    try? await Task.sleep(for: .seconds(timeout))
                    await MainActor.run {
                        if self.pendingCaptures[id] != nil {
                            self.handleTimeout(id: id)
                        }
                    }
                }

                // Store pending capture
                self.pendingCaptures[id] = PendingCapture(
                    webView: webView,
                    continuation: continuation,
                    timeoutTask: timeoutTask
                )

                // Load URL
                webView.load(URLRequest(url: url))
            }
        }
    }

    private func handleTimeout(id: UUID) {
        guard let pending = pendingCaptures.removeValue(forKey: id) else { return }
        pending.continuation.resume(throwing: CaptureError.timeout)
    }

    // MARK: - Fetch Title
    private func fetchTitle(url: URL) async -> String? {
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

            let (data, _) = try await URLSession.shared.data(for: request)
            let html = String(data: data, encoding: .utf8) ?? ""

            // Extract title from HTML
            if let titleRange = html.range(of: "<title>"),
               let endRange = html.range(of: "</title>", range: titleRange.upperBound..<html.endIndex) {
                let title = String(html[titleRange.upperBound..<endRange.lowerBound])
                return title.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            print("⚠️ Failed to fetch title: \(error)")
        }

        return nil
    }

    // MARK: - Generate Summary
    private func generateSummary(url: URL, title: String) async throws -> String? {
        // Use ResearchService to get AI summary via OpenRouter
        do {
            let result = try await ResearchService.shared.performResearch(
                query: "Summarize the content of this webpage in 2-3 sentences: \(url.absoluteString) - Title: \(title)",
                searchType: .web,
                maxResults: 1
            )
            return result.summary
        } catch {
            print("⚠️ Failed to generate summary: \(error)")
            return nil
        }
    }
}

// MARK: - WKNavigationDelegate
extension WebsiteCapture: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Wait a bit for dynamic content to load
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.takeSnapshot(webView: webView)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleError(webView: webView, error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleError(webView: webView, error: error)
    }

    private func takeSnapshot(webView: WKWebView) {
        guard let id = findPendingId(for: webView) else { return }

        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: Int(webView.frame.width))

        webView.takeSnapshot(with: config) { [weak self] image, error in
            guard let self = self else { return }

            guard let pending = self.pendingCaptures.removeValue(forKey: id) else { return }

            pending.timeoutTask?.cancel()

            if let error = error {
                pending.continuation.resume(throwing: error)
            } else if let image = image {
                pending.continuation.resume(returning: image)
            } else {
                pending.continuation.resume(throwing: CaptureError.snapshotFailed)
            }
        }
    }

    private func handleError(webView: WKWebView, error: Error) {
        guard let id = findPendingId(for: webView),
              let pending = pendingCaptures.removeValue(forKey: id) else { return }

        pending.timeoutTask?.cancel()
        pending.continuation.resume(throwing: error)
    }

    private func findPendingId(for webView: WKWebView) -> UUID? {
        pendingCaptures.first { $0.value.webView === webView }?.key
    }
}

// MARK: - Processing Steps
enum WebsiteProcessingStep {
    case capturingScreenshot
    case fetchingMetadata
    case summarizing
    case complete

    var description: String {
        switch self {
        case .capturingScreenshot: return "Capturing screenshot..."
        case .fetchingMetadata: return "Fetching page info..."
        case .summarizing: return "Generating summary..."
        case .complete: return "Complete"
        }
    }

    var progress: Double {
        switch self {
        case .capturingScreenshot: return 0.2
        case .fetchingMetadata: return 0.5
        case .summarizing: return 0.8
        case .complete: return 1.0
        }
    }
}

// MARK: - Errors
enum CaptureError: LocalizedError {
    case captureCreationFailed
    case snapshotFailed
    case timeout
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .captureCreationFailed: return "Failed to create capture"
        case .snapshotFailed: return "Failed to take screenshot"
        case .timeout: return "Page load timed out"
        case .invalidURL: return "Invalid URL"
        }
    }
}

// MARK: - NSImage Extension
extension NSImage {
    /// Convert to base64 string for storage
    var base64String: String? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            return nil
        }
        return jpegData.base64EncodedString()
    }

    /// Create from base64 string
    static func fromBase64(_ base64: String) -> NSImage? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return NSImage(data: data)
    }

    /// Scale image to fit within max dimensions
    func scaled(toFit maxSize: CGSize) -> NSImage {
        let ratio = min(maxSize.width / size.width, maxSize.height / size.height)
        if ratio >= 1 { return self }

        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        draw(in: CGRect(origin: .zero, size: newSize),
             from: CGRect(origin: .zero, size: size),
             operation: .copy,
             fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}
