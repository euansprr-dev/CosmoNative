// CosmoOS/SwipeFile/Artifacts/SwipePageCapture.swift
// Capturing a whole web page as a Page swipe: the full-height image, its
// DOM-guided section slices, and the text each slice contains.
//
// TWO SOURCES, ONE PIPELINE. The live browser pane's WKWebView is the primary
// — your session, your scroll, past the opt-in, which is where the pages worth
// swiping actually live. A pasted URL renders headlessly in a webview built the
// same way (same user agent, same JS settings), so a link captured on the phone
// still becomes a real Page swipe when the Mac gets to it.
//
// The analysis reads the DOM TEXT, not the images: the text is exact, it is
// already in hand, and it is roughly fifty times cheaper than vision. Vision is
// held back for the sections that have no text at all.

import Foundation
import WebKit
import AppKit

@MainActor
enum SwipePageCapture {

    /// Render width. Wide enough that a desktop sales page lays out as its
    /// author intended (a narrower viewport trips responsive breakpoints and
    /// captures the phone design), narrow enough that a 20,000px page is a
    /// sane amount of pixels.
    static let captureWidth: CGFloat = 1400

    /// Viewport height used while loading — a page's lazy loaders and
    /// scroll-triggered animations key off a realistic window, not a 20,000px one.
    static let loadViewportHeight: CGFloat = 1000

    /// Section slices: legible at full width, cheap enough to store forty of.
    static let sliceJPEGQuality: CGFloat = 0.72
    /// The full-page image is a map, not a reading surface.
    static let fullPageJPEGQuality: CGFloat = 0.6

    struct Probe: Sendable {
        var title: String?
        var contentHeight: Int
        var sections: [SwipePageSection]
        var shape: SwipePageShape
    }

    struct Capture {
        var probe: Probe
        var units: [SwipeArtifactUnit]
        var attachments: [MediaAttachment]
    }

    // MARK: - Entry points

    /// Capture the page a live webview is showing — the browser-pane path.
    static func capture(webView: WKWebView, swipeUUID: String) async -> Capture? {
        await settle(webView)
        guard let probe = await probe(webView) else { return nil }
        guard let image = await snapshot(webView, contentHeight: probe.contentHeight) else { return nil }
        return await slice(image: image, probe: probe, swipeUUID: swipeUUID)
    }

    /// Render a URL headlessly and capture it — the pasted-link path.
    /// Reuses `WebsiteCapture`'s configuration, including the shared browser
    /// user agent (`customUserAgent` stays banned).
    static func capture(url: URL, swipeUUID: String) async -> Capture? {
        let webView = makeHeadlessWebView()
        guard await load(webView, url: url) else { return nil }
        return await capture(webView: webView, swipeUUID: swipeUUID)
    }

    /// Render an HTML STRING and capture it — the email path. The string
    /// arrives from SwipeEmailCapture with `cid:` inline images already
    /// rewritten to `data:` URIs, so the render isn't holey; remote https
    /// images load normally. Same settle → probe → slice → read pipeline.
    static func capture(htmlString: String, baseURL: URL?, swipeUUID: String) async -> Capture? {
        let webView = makeHeadlessWebView()
        webView.loadHTMLString(htmlString, baseURL: baseURL)
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(250))
            if !webView.isLoading { break }
        }
        return await capture(webView: webView, swipeUUID: swipeUUID)
    }

    // MARK: - Webview

    private static func makeHeadlessWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        // Captures are of the same page the browser pane would show, so they
        // must ask for it as the same browser.
        config.applicationNameForUserAgent = CosmoBrowserUserAgent.applicationName

        return WKWebView(
            frame: CGRect(x: 0, y: 0, width: captureWidth, height: loadViewportHeight),
            configuration: config
        )
    }

    private static func load(_ webView: WKWebView, url: URL) async -> Bool {
        webView.load(URLRequest(url: url))
        // Poll rather than delegate: this webview has no owner to hold a
        // delegate alive, and a page that never finishes must not hang us.
        for _ in 0..<60 {
            try? await Task.sleep(for: .milliseconds(250))
            if !webView.isLoading, webView.url != nil { return true }
        }
        return webView.url != nil
    }

    /// Wake the page up before measuring it: scroll to the bottom so lazy
    /// images and scroll-triggered sections render, then back to the top so
    /// the capture starts where the reader would.
    private static func settle(_ webView: WKWebView) async {
        _ = try? await webView.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight);")
        try? await Task.sleep(for: .milliseconds(800))
        _ = try? await webView.evaluateJavaScript("window.scrollTo(0, 0);")
        try? await Task.sleep(for: .milliseconds(400))
    }

    // MARK: - DOM probe

    static func probe(_ webView: WKWebView) async -> Probe? {
        guard let raw = try? await webView.evaluateJavaScript(probeScript),
              let dict = raw as? [String: Any] else { return nil }

        let height = (dict["contentHeight"] as? NSNumber)?.intValue ?? 0
        guard height > 0 else { return nil }

        let sections = (dict["sections"] as? [[String: Any]] ?? []).compactMap { entry -> SwipePageSection? in
            guard let top = (entry["top"] as? NSNumber)?.intValue,
                  let sectionHeight = (entry["height"] as? NSNumber)?.intValue else { return nil }
            return SwipePageSection(
                top: top,
                height: sectionHeight,
                text: (entry["text"] as? String)?.trimmed ?? ""
            )
        }

        let shapeDict = dict["shape"] as? [String: Any] ?? [:]
        let shape = SwipePageShape(
            ctaCount: (shapeDict["ctaCount"] as? NSNumber)?.intValue ?? 0,
            hasPricingTable: (shapeDict["hasPricingTable"] as? NSNumber)?.boolValue ?? false,
            testimonialCount: (shapeDict["testimonialCount"] as? NSNumber)?.intValue ?? 0,
            paragraphCount: (shapeDict["paragraphCount"] as? NSNumber)?.intValue ?? 0
        )

        return Probe(
            title: (dict["title"] as? String)?.trimmed,
            contentHeight: height,
            sections: sections,
            shape: shape
        )
    }

    /// Walk down from `body` taking block children that are tall enough to be
    /// a section but not so tall they are obviously a wrapper; descend into
    /// anything bigger. That single rule is what produces cuts a human would
    /// have made, because it lands on whatever element the page's own author
    /// used to hold a section together.
    private static let probeScript = """
    (function () {
      var viewport = window.innerHeight || 900;
      var docHeight = Math.max(
        document.body ? document.body.scrollHeight : 0,
        document.documentElement ? document.documentElement.scrollHeight : 0
      );
      var MIN = 200;
      var MAX = viewport * 3;
      var sections = [];

      function topOf(el) {
        var rect = el.getBoundingClientRect();
        return Math.round(rect.top + window.scrollY);
      }

      function visible(el) {
        var style = window.getComputedStyle(el);
        if (style.display === 'none' || style.visibility === 'hidden') return false;
        // Sticky and fixed chrome rides along with the reader; it is not a
        // section of the page and would otherwise claim the first slice.
        if (style.position === 'fixed' || style.position === 'sticky') return false;
        return true;
      }

      function walk(el, depth) {
        if (sections.length >= 80 || depth > 6) return;
        var children = Array.prototype.slice.call(el.children || []);
        for (var i = 0; i < children.length; i++) {
          var child = children[i];
          var tag = child.tagName;
          if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT' || tag === 'SVG') continue;
          if (!visible(child)) continue;
          var height = Math.round(child.getBoundingClientRect().height);
          if (height <= 0) continue;
          if (height > MAX && child.children && child.children.length > 0) {
            walk(child, depth + 1);
          } else if (height >= MIN) {
            sections.push({
              top: topOf(child),
              height: height,
              text: (child.innerText || '').trim().slice(0, 4000)
            });
          }
        }
      }

      if (document.body) walk(document.body, 0);

      var text = document.body ? (document.body.innerText || '') : '';
      var ctaWords = /(buy|get|start|join|sign up|subscribe|enroll|book|claim|order|add to cart|checkout|apply)/i;
      var ctas = Array.prototype.slice.call(
        document.querySelectorAll('a,button,input[type=submit]')
      ).filter(function (el) {
        var label = (el.innerText || el.value || '').trim();
        return label.length > 0 && label.length < 60 && ctaWords.test(label);
      });
      var priceish = /(\\$|€|£)\\s?\\d/;
      var hasPricing = document.querySelectorAll('table').length > 0
        ? priceish.test(text)
        : (document.querySelectorAll('[class*=pricing],[class*=price],[id*=pricing]').length > 0 && priceish.test(text));
      var testimonials = document.querySelectorAll(
        'blockquote,[class*=testimonial],[class*=review],[class*=quote]'
      ).length;

      return {
        title: document.title || null,
        contentHeight: docHeight,
        sections: sections,
        shape: {
          ctaCount: ctas.length,
          hasPricingTable: !!hasPricing,
          testimonialCount: testimonials,
          paragraphCount: document.querySelectorAll('p').length
        }
      };
    })();
    """

    // MARK: - Snapshot

    /// The full page as one image. Resizing the webview to the content height
    /// (rather than scrolling and stitching) is what keeps a sticky header
    /// from appearing once per tile. Only a page past the single-capture cap
    /// falls back to tiles.
    static func snapshot(_ webView: WKWebView, contentHeight: Int) async -> NSImage? {
        let originalFrame = webView.frame
        defer { webView.frame = originalFrame }

        let offsets = SwipePageSlicer.tileOffsets(forHeight: contentHeight)
        if offsets.count == 1 {
            webView.frame = CGRect(x: 0, y: 0, width: captureWidth, height: CGFloat(contentHeight))
            webView.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(350))
            return await takeSnapshot(webView)
        }

        var tiles: [NSImage] = []
        webView.frame = CGRect(
            x: 0, y: 0, width: captureWidth,
            height: CGFloat(SwipePageSlicer.tileHeight)
        )
        for offset in offsets {
            _ = try? await webView.evaluateJavaScript("window.scrollTo(0, \(offset));")
            try? await Task.sleep(for: .milliseconds(300))
            guard let tile = await takeSnapshot(webView) else { continue }
            tiles.append(tile)
        }
        return stitch(tiles, totalHeight: CGFloat(contentHeight))
    }

    private static func takeSnapshot(_ webView: WKWebView) async -> NSImage? {
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: Int(captureWidth))
        return await withCheckedContinuation { continuation in
            webView.takeSnapshot(with: config) { image, error in
                if let error { print("SwipePageCapture: snapshot failed — \(error)") }
                continuation.resume(returning: image)
            }
        }
    }

    private static func stitch(_ tiles: [NSImage], totalHeight: CGFloat) -> NSImage? {
        guard !tiles.isEmpty else { return nil }
        let canvas = NSImage(size: CGSize(width: captureWidth, height: totalHeight))
        canvas.lockFocus()
        var y = totalHeight
        for tile in tiles {
            let height = min(tile.size.height, y)
            y -= height
            // AppKit's origin is bottom-left; tiles were captured top-down.
            tile.draw(
                in: CGRect(x: 0, y: y, width: captureWidth, height: height),
                from: CGRect(x: 0, y: tile.size.height - height, width: tile.size.width, height: height),
                operation: .copy,
                fraction: 1
            )
            if y <= 0 { break }
        }
        canvas.unlockFocus()
        return canvas
    }

    // MARK: - Slicing into attachments

    private static func slice(image: NSImage, probe: Probe, swipeUUID: String) async -> Capture? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let pixelHeight = cgImage.height
        let pixelWidth = cgImage.width
        // The snapshot is `captureWidth` points wide but may be backed by more
        // pixels; every CSS measurement scales by the same factor.
        let scale = probe.contentHeight > 0
            ? Double(pixelHeight) / Double(probe.contentHeight)
            : 1

        let slices = SwipePageSlicer.slices(
            from: probe.sections, contentHeight: probe.contentHeight, scale: scale
        )
        guard !slices.isEmpty else { return nil }

        var units: [SwipeArtifactUnit] = []
        var attachments: [MediaAttachment] = []

        // The whole page, once — the Study stage's map.
        if let fullData = jpegData(from: cgImage, quality: fullPageJPEGQuality),
           let stored = store(fullData, swipeUUID: swipeUUID, name: "page-full.jpg",
                              metadata: ["isFullPage": true]) {
            attachments.append(stored)
        }

        for slice in slices {
            let top = max(0, min(slice.top, pixelHeight))
            let height = max(1, min(slice.height, pixelHeight - top))
            guard let cropped = cgImage.cropping(
                to: CGRect(x: 0, y: top, width: pixelWidth, height: height)
            ), let data = jpegData(from: cropped, quality: sliceJPEGQuality) else { continue }

            guard let stored = store(
                data, swipeUUID: swipeUUID, name: "page-\(slice.index).jpg",
                metadata: ["pageIndex": slice.index]
            ) else { continue }

            attachments.append(stored)
            units.append(SwipeArtifactUnit(
                index: slice.index,
                copy: slice.text.isEmpty ? nil : slice.text,
                attachmentUUID: stored.uuid,
                pageOffset: slice.top,
                aspectRatio: Double(pixelWidth) / Double(height)
            ))
        }

        guard !units.isEmpty else { return nil }
        return Capture(probe: probe, units: units, attachments: attachments)
    }

    private static func store(
        _ data: Data,
        swipeUUID: String,
        name: String,
        metadata: [String: Any]
    ) -> MediaAttachment? {
        let attachmentID = UUID().uuidString
        guard let stored = try? CaptureMediaStorage.shared.store(
            data: data,
            capturedItemId: swipeUUID,
            attachmentId: attachmentID,
            originalFilename: name,
            mimeType: "image/jpeg",
            telegramFilePath: nil,
            kind: .screenshot
        ) else { return nil }

        var merged = metadata
        merged["captureSource"] = "page"
        var attachment = MediaAttachment.makeLocal(
            owner: .atom,
            ownerUUID: swipeUUID,
            kind: .screenshot,
            localStoragePath: stored.originalPath,
            thumbnailPath: stored.thumbnailPath,
            originalFilename: name,
            mimeType: "image/jpeg",
            fileSize: Int64(data.count),
            metadata: (try? JSONSerialization.data(withJSONObject: merged))
                .flatMap { String(data: $0, encoding: .utf8) }
        )
        attachment.uuid = attachmentID
        return attachment
    }

    private static func jpegData(from cgImage: CGImage, quality: CGFloat) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
