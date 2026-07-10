// CosmoOS/Services/ContentExportFormatter.swift
// The last mile: deterministic per-platform formatting for finished drafts.
// Pure code, not LLM — instant, reliable, and identical every time. Each
// formatter returns copy-ready sections (a thread's tweets, a carousel's
// slides, one caption) so the export sheet can offer copy-per-section and
// copy-all without any model round trip.
// July 2026

import Foundation

// MARK: - Target Platforms

enum ExportPlatform: String, CaseIterable, Identifiable, Sendable {
    case xThread = "x_thread"
    case xPost = "x_post"
    case linkedIn = "linkedin"
    case instagramCaption = "instagram"
    case carouselSlides = "carousel"
    case newsletterMarkdown = "newsletter"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .xThread: return "X — Thread"
        case .xPost: return "X — Single Post"
        case .linkedIn: return "LinkedIn"
        case .instagramCaption: return "Instagram Caption"
        case .carouselSlides: return "Carousel Slides"
        case .newsletterMarkdown: return "Newsletter (Markdown)"
        }
    }

    var icon: String {
        switch self {
        case .xThread, .xPost: return "bird"
        case .linkedIn: return "briefcase"
        case .instagramCaption: return "camera"
        case .carouselSlides: return "square.stack"
        case .newsletterMarkdown: return "envelope"
        }
    }
}

// MARK: - Output

struct ExportSection: Identifiable, Equatable, Sendable {
    let index: Int
    /// e.g. "1/7", "Slide 3", "Caption"
    let label: String
    let text: String
    /// Character count against the platform limit, when one exists.
    let limit: Int?

    var id: Int { index }

    var isOverLimit: Bool {
        guard let limit else { return false }
        return text.count > limit
    }
}

// MARK: - Formatter

enum ContentExportFormatter {
    static let tweetLimit = 280
    static let linkedInLimit = 3_000
    static let instagramLimit = 2_200

    static func format(_ draft: String, for platform: ExportPlatform) -> [ExportSection] {
        let text = normalized(draft)
        guard !text.isEmpty else { return [] }
        switch platform {
        case .xThread: return xThread(text)
        case .xPost: return single(text, label: "Post", limit: tweetLimit)
        case .linkedIn: return single(linkedInSpacing(text), label: "Post", limit: linkedInLimit)
        case .instagramCaption: return single(text, label: "Caption", limit: instagramLimit)
        case .carouselSlides: return carousel(text)
        case .newsletterMarkdown: return single(text, label: "Newsletter", limit: nil)
        }
    }

    /// Everything joined, for copy-all.
    static func combined(_ sections: [ExportSection]) -> String {
        sections.map(\.text).joined(separator: "\n\n---\n\n")
    }

    // MARK: - Normalization

    /// Collapse editor artifacts: 3+ blank lines → one blank line, trim edges.
    static func normalized(_ text: String) -> String {
        var out = text.replacingOccurrences(of: "\r\n", with: "\n")
        while out.contains("\n\n\n") {
            out = out.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - X Thread

    /// Split into tweets on paragraph boundaries first, sentences when a
    /// paragraph alone exceeds the limit, with "n/total" suffixes.
    static func xThread(_ text: String) -> [ExportSection] {
        // Reserve room for the " n/m" counter suffix.
        let budget = tweetLimit - 8

        var tweets: [String] = []
        var current = ""

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { tweets.append(trimmed) }
            current = ""
        }

        for paragraph in text.components(separatedBy: "\n\n") {
            let para = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !para.isEmpty else { continue }

            if para.count > budget {
                // Sentence-pack the giant paragraph.
                flush()
                var window = ""
                for sentence in splitSentences(para) {
                    if window.count + sentence.count + 1 > budget, !window.isEmpty {
                        tweets.append(window.trimmingCharacters(in: .whitespaces))
                        window = ""
                    }
                    window += (window.isEmpty ? "" : " ") + sentence
                }
                if !window.isEmpty { tweets.append(window.trimmingCharacters(in: .whitespaces)) }
                continue
            }

            if current.count + para.count + 2 > budget, !current.isEmpty {
                flush()
            }
            current += (current.isEmpty ? "" : "\n\n") + para
        }
        flush()

        guard tweets.count > 1 else {
            return single(text, label: "Post", limit: tweetLimit)
        }

        return tweets.enumerated().map { index, tweet in
            ExportSection(
                index: index,
                label: "\(index + 1)/\(tweets.count)",
                text: "\(tweet) \(index + 1)/\(tweets.count)",
                limit: tweetLimit
            )
        }
    }

    // MARK: - LinkedIn

    /// LinkedIn reads best with one idea per line-block: break multi-sentence
    /// paragraphs into short line groups separated by blank lines.
    static func linkedInSpacing(_ text: String) -> String {
        var blocks: [String] = []
        for paragraph in text.components(separatedBy: "\n\n") {
            let para = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !para.isEmpty else { continue }
            let sentences = splitSentences(para)
            if sentences.count >= 3, para.count > 240 {
                // Two sentences per block keeps the feed rhythm.
                var window: [String] = []
                for sentence in sentences {
                    window.append(sentence)
                    if window.count == 2 {
                        blocks.append(window.joined(separator: " "))
                        window = []
                    }
                }
                if !window.isEmpty { blocks.append(window.joined(separator: " ")) }
            } else {
                blocks.append(para)
            }
        }
        return blocks.joined(separator: "\n\n")
    }

    // MARK: - Carousel

    /// Slide-marked drafts ("SLIDE 1", "Slide 2:") split on markers; unmarked
    /// drafts fall back to one paragraph per slide.
    static func carousel(_ text: String) -> [ExportSection] {
        let pattern = #"(?im)^slide\s+(\d+)\s*[:.\-]?\s*$|^slide\s+(\d+)\s*[:.\-]\s*"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let nsText = text as NSString
        let matches = regex?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? []

        var slides: [String] = []
        if matches.count >= 2 {
            for (offset, match) in matches.enumerated() {
                let start = match.range.location + match.range.length
                let end = offset + 1 < matches.count ? matches[offset + 1].range.location : nsText.length
                let body = nsText.substring(with: NSRange(location: start, length: end - start))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty { slides.append(body) }
            }
        } else {
            slides = text.components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return slides.enumerated().map { index, slide in
            ExportSection(index: index, label: "Slide \(index + 1)", text: slide, limit: nil)
        }
    }

    // MARK: - Helpers

    private static func single(_ text: String, label: String, limit: Int?) -> [ExportSection] {
        [ExportSection(index: 0, label: label, text: text, limit: limit)]
    }

    static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == "." || character == "!" || character == "?" {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { sentences.append(tail) }
        return sentences
    }
}
