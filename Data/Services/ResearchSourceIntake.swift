// CosmoOS/Data/Services/ResearchSourceIntake.swift
// A link (or a set of captured pages) saved for its CONTENT — a Research
// source, not a swipe. The swipe file keeps things for their FORM (how they
// are built); the research lens keeps things to READ, WATCH, and CITE. Both
// are `.research` atoms, so one link is never two rows: a source that
// already exists as a swipe simply gains the research lens, and a source
// saved here is what an inquiry's "import" would have found.
//
// Nothing here goes through the swipe worker (its scanner filters on
// isSwipeFile by design). Enrichment is local and best-effort: oEmbed where
// a platform offers it, otherwise the page's own <title> / og:image. The
// Study reader fetches transcripts live from the link, so none is stored.
// September 2026 — the inbox "Research, not swipe" verb.

import Foundation

@MainActor
enum ResearchSourceIntake {

    /// What the intake resolved for a link: a fresh research-lens atom to
    /// insert, or the uuid of the live source that already holds the link.
    struct Prepared {
        let atom: Atom
        let existingUUID: String?
    }

    /// Resolve a link. Dedups against EVERY research atom carrying the same
    /// canonical URL — inquiry sources and swipes alike — before shaping a
    /// new research-lens atom. `note` is the prose the user wrote beside the
    /// link; `title` is the router's or the user's title, when there is one.
    static func prepare(url: String, note: String?, title: String?) async -> Prepared {
        let canonical = InquiryRepository.shared.canonicalURL(url)
        if let existing = try? await InquiryRepository.shared.fetchSource(canonicalURL: canonical), !existing.isDeleted {
            return Prepared(atom: existing, existingUUID: existing.uuid)
        }
        if let swipe = await QuickCaptureProcessor.findExistingLiveSwipe(url: url) {
            return Prepared(atom: swipe, existingUUID: swipe.uuid)
        }

        let classification = SwipeURLClassifier().classify(url)
        let sourceType = classification.isUrl ? classification.sourceType : .website
        var atom = Atom.newSwipeFile(url: url, hook: nil, sourceType: sourceType, contentSource: .clipboard)
        // Research lens only — the swipe stamp the factory sets comes off.
        atom = atom.addingLens(.research).removingLens(.swipe)
        let cleanedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        atom.title = cleanedTitle.isEmpty ? url : cleanedTitle
        // No worker owns this atom; "ready" keeps it out of every pending scan.
        atom.processingStatus = "ready"
        atom.updateResearchMetadata { meta in
            meta.researchType = meta.researchType ?? "webpage"
            meta.tags = Array(Set((meta.tags ?? []) + ["inquiry-source"]))
        }
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            atom.body = note
        }
        return Prepared(atom: atom, existingUUID: nil)
    }

    /// Captured pages or photos saved to study: one research-lens atom whose
    /// originals are the attachments (the filing writer re-owns them onto it).
    static func prepare(pages attachmentUUIDs: [String], text: String, title: String) -> Atom {
        var atom = Atom.new(type: .research, title: title, body: text.isEmpty ? nil : text)
        atom = atom.addingLens(.research)
        atom.processingStatus = "ready"
        atom.updateResearchMetadata { meta in
            meta.researchType = "pages"
            meta.contentSource = "capture"
            meta.tags = Array(Set((meta.tags ?? []) + ["inquiry-source"]))
        }
        return atom
    }

    // MARK: - Enrichment

    struct Enrichment: Sendable {
        var title: String?
        var thumbnailUrl: String?
        var isEmpty: Bool { title == nil && thumbnailUrl == nil }
    }

    /// Fill in the title and thumbnail a bare link can't show. Best-effort
    /// and bounded — a source is already filed before this runs, and a
    /// failure leaves it legible under its URL.
    static func enrich(atomUUID: String) async {
        guard let atom = try? await AtomRepository.shared.fetch(uuid: atomUUID), !atom.isDeleted,
              let url = atom.url else { return }
        let enrichment = await ResearchLinkEnrichment.fetch(url: url)
        guard !enrichment.isEmpty else { return }
        let placeholderTitle = (atom.title ?? "").isEmpty || atom.title == url
        _ = try? await AtomRepository.shared.update(uuid: atomUUID) { current in
            if let title = enrichment.title, placeholderTitle { current.title = title }
            if let thumb = enrichment.thumbnailUrl, (current.thumbnailUrl ?? "").isEmpty { current.thumbnailUrl = thumb }
        }
        NotificationCenter.default.post(name: CosmoNotification.Entity.updated, object: nil)
    }
}

/// Key-free metadata for a link: oEmbed where the platform publishes one
/// (YouTube, Vimeo, X), otherwise the page's <title> and Open Graph image.
enum ResearchLinkEnrichment {
    private static let timeout: TimeInterval = 8
    private static let htmlByteCap = 512 * 1024

    static func fetch(url: String) async -> ResearchSourceIntake.Enrichment {
        if let endpoint = oEmbedEndpoint(for: url), let result = await fetchOEmbed(endpoint), !result.isEmpty {
            return result
        }
        return await fetchHTMLHead(url: url)
    }

    private static func oEmbedEndpoint(for url: String) -> URL? {
        guard let host = URLComponents(string: url)?.host?.lowercased() else { return nil }
        let escaped = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        if host.contains("youtube.com") || host == "youtu.be" || host.hasSuffix(".youtu.be") {
            return URL(string: "https://www.youtube.com/oembed?format=json&url=\(escaped)")
        }
        if host.contains("vimeo.com") {
            return URL(string: "https://vimeo.com/api/oembed.json?url=\(escaped)")
        }
        if host == "x.com" || host.hasSuffix(".x.com") || host.contains("twitter.com") {
            return URL(string: "https://publish.twitter.com/oembed?omit_script=1&url=\(escaped)")
        }
        return nil
    }

    private static func fetchOEmbed(_ endpoint: URL) async -> ResearchSourceIntake.Enrichment? {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = timeout
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var result = ResearchSourceIntake.Enrichment()
        if let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            result.title = String(title.prefix(200))
        }
        result.thumbnailUrl = json["thumbnail_url"] as? String
        return result
    }

    private static func fetchHTMLHead(url: String) async -> ResearchSourceIntake.Enrichment {
        guard let target = URL(string: url) else { return .init() }
        var request = URLRequest(url: target)
        request.timeoutInterval = timeout
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode ?? 500 < 400 else { return .init() }
        let head = String(decoding: data.prefix(htmlByteCap), as: UTF8.self)
        var result = ResearchSourceIntake.Enrichment()
        result.title = metaContent(in: head, property: "og:title") ?? htmlTitle(in: head)
        result.thumbnailUrl = metaContent(in: head, property: "og:image")
        return result
    }

    /// `<meta property="og:title" content="…">` in either attribute order.
    static func metaContent(in html: String, property: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: property)
        let patterns = [
            "<meta[^>]+(?:property|name)=[\"']\(escaped)[\"'][^>]+content=[\"']([^\"']+)[\"']",
            "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+(?:property|name)=[\"']\(escaped)[\"']"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { continue }
            let value = decodingEntities(String(html[range])).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return String(value.prefix(300)) }
        }
        return nil
    }

    static func htmlTitle(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<title[^>]*>([^<]{1,300})</title>", options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        let value = decodingEntities(String(html[range]))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func decodingEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
