// CosmoOS/UI/CommandK/CommandKInstantResearchCapture.swift

import Foundation

// Instant "save this link as research": the atom lands immediately with the
// URL + a derivable thumbnail so the capture feels instant, then a
// fire-and-forget enrichment pass fetches the real title (YouTube oEmbed,
// X oEmbed, page <title>) and an og:image for plain websites. No transcript
// pipeline — a captured link is complete as itself; Research focus mode and
// the browser pane both open it from the URL alone.
struct CommandKInstantResearchCapture {
    private let classifier = SwipeURLClassifier()

    func pendingAtom(for url: String) throws -> Atom {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let classification = classifier.classify(trimmed)
        guard classification.isUrl else {
            throw CommandKInstantSwipeCaptureError.invalidURL
        }

        var atom = Research.new(
            title: Self.placeholderTitle(for: trimmed, sourceType: classification.sourceType),
            url: trimmed,
            sourceType: classification.sourceType
        )
        atom.processingStatus = "complete"

        var richContent = ResearchRichContent()
        richContent.sourceType = classification.sourceType

        switch classification.sourceType {
        case .youtube, .youtubeShort:
            richContent.videoId = classification.contentId
            if let videoId = classification.contentId {
                let thumbnailURL = "https://img.youtube.com/vi/\(videoId)/maxresdefault.jpg"
                atom.thumbnailUrl = thumbnailURL
                richContent.thumbnailUrl = thumbnailURL
            }
        case .loom:
            richContent.loomId = classification.contentId
        default:
            break
        }

        atom.setRichContent(richContent)
        atom.updatedAt = ISO8601.string(from: Date())
        return atom
    }

    @MainActor
    func capture(url: String, note: String? = nil) async throws -> Atom {
        var atom = try pendingAtom(for: url)

        // Prose the user typed around the link rides along as their note —
        // never as the body, which stays reserved for transcript content.
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty, note != url.trimmingCharacters(in: .whitespacesAndNewlines) {
            atom.personalNotes = note
        }

        let saved = try await AtomRepository.shared.create(atom)

        NotificationCenter.default.post(
            name: .researchCreated,
            object: nil,
            userInfo: ["research": saved, "uuid": saved.uuid]
        )

        let placeholder = saved.title
        Task {
            await Self.enrich(uuid: saved.uuid, url: url, placeholderTitle: placeholder)
        }

        return saved
    }

    // MARK: - Enrichment (title + thumbnail after the instant save)

    /// Best-effort metadata pass. Every fetch is optional: a failure leaves
    /// the placeholder title standing, never an error state. The title is
    /// only replaced while it still IS the placeholder — a rename that beat
    /// the fetch wins.
    private static func enrich(uuid: String, url: String, placeholderTitle: String?) async {
        let classification = SwipeURLClassifier().classify(url)

        var fetchedTitle: String?
        var fetchedAuthor: String?
        var fetchedThumbnail: String?

        switch classification.sourceType {
        case .youtube, .youtubeShort:
            guard let videoId = classification.contentId else { break }
            let metadata = try? await YouTubeProcessor.shared.fetchMetadata(videoId: videoId)
            fetchedTitle = metadata?.title
            fetchedAuthor = metadata?.channelName
        case .xPost, .twitter:
            let embed = try? await XEmbedFetcher.shared.fetchEmbed(url: url)
            fetchedAuthor = embed?.authorName
            if let author = embed?.authorName {
                fetchedTitle = "Post by \(author)"
            }
        default:
            if let page = await fetchPageMetadata(url: url) {
                fetchedTitle = page.title
                fetchedThumbnail = page.imageURL
            }
        }

        guard fetchedTitle != nil || fetchedAuthor != nil || fetchedThumbnail != nil else { return }

        _ = try? await AtomRepository.shared.update(uuid: uuid) { atom in
            if let fetchedTitle, !fetchedTitle.isEmpty,
               atom.title == placeholderTitle || (atom.title ?? "").isEmpty {
                atom.title = fetchedTitle
            }
            if fetchedAuthor != nil || fetchedThumbnail != nil || fetchedTitle != nil {
                var richContent = atom.richContent ?? ResearchRichContent()
                if let fetchedTitle { richContent.title = fetchedTitle }
                if let fetchedAuthor { richContent.author = fetchedAuthor }
                if let fetchedThumbnail {
                    richContent.thumbnailUrl = fetchedThumbnail
                    atom.thumbnailUrl = fetchedThumbnail
                }
                atom.setRichContent(richContent)
            }
        }
    }

    private struct PageMetadata {
        var title: String?
        var imageURL: String?
    }

    /// One GET for both <title> and og:image / og:title.
    private static func fetchPageMetadata(url urlString: String) async -> PageMetadata? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
            forHTTPHeaderField: "User-Agent"
        )
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else { return nil }

        var metadata = PageMetadata()
        metadata.title = metaContent(in: html, property: "og:title") ?? htmlTitle(in: html)
        metadata.imageURL = metaContent(in: html, property: "og:image")
        return (metadata.title == nil && metadata.imageURL == nil) ? nil : metadata
    }

    private static func htmlTitle(in html: String) -> String? {
        guard let open = html.range(of: "<title", options: .caseInsensitive),
              let openEnd = html.range(of: ">", range: open.upperBound..<html.endIndex),
              let close = html.range(of: "</title>", options: .caseInsensitive,
                                     range: openEnd.upperBound..<html.endIndex) else { return nil }
        let raw = String(html[openEnd.upperBound..<close.lowerBound])
        let title = decodeHTMLEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private static func metaContent(in html: String, property: String) -> String? {
        // Both attribute orders occur in the wild: property-then-content and
        // content-then-property.
        let patterns = [
            "<meta[^>]+(?:property|name)=[\"']\(property)[\"'][^>]*content=[\"']([^\"']+)[\"']",
            "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]*(?:property|name)=[\"']\(property)[\"']"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            if let match = regex.firstMatch(in: html, range: range),
               let contentRange = Range(match.range(at: 1), in: html) {
                let value = decodeHTMLEntities(String(html[contentRange]))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func placeholderTitle(
        for url: String,
        sourceType: ResearchRichContent.SourceType
    ) -> String {
        switch sourceType {
        case .youtube: return "YouTube Video"
        case .youtubeShort: return "YouTube Short"
        case .loom: return "Loom Video"
        case .xPost, .twitter: return "X Post"
        case .threads: return "Threads Post"
        default:
            return URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? url
        }
    }
}
