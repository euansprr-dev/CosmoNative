// CosmoOS/AI/Craft/CraftTypes.swift
// Core types for the Content Craft system — the human-in-the-loop replacement
// for the generation-era writing pipeline. The craft engine never writes drafts;
// it reviews them against real transcripts (/review) and riffs targeted
// variations on a single beat (/riff).
// June 2026

import Foundation

// MARK: - Format

/// The three format families the craft engine reasons about, collapsed from
/// WritingContentFormat's platform-specific cases. Reels carry one or two short
/// sentences per slide; carousels/threads carry three-plus sentence slides.
enum CraftFormat: String, Codable, Sendable {
    case reel
    case carousel
    case thread
    case longForm

    var displayName: String {
        switch self {
        case .reel: return "reel"
        case .carousel: return "carousel"
        case .thread: return "thread"
        case .longForm: return "long-form post"
        }
    }

    /// Representative WritingContentFormat used to reuse its swipe-matching
    /// logic (capture-time media metadata beats AI classification).
    var writingFormat: WritingContentFormat {
        switch self {
        case .reel: return .instagramReel
        case .carousel: return .instagramCarousel
        case .thread: return .twitterThread
        case .longForm: return .staticPost
        }
    }

    static func from(_ writingFormat: WritingContentFormat) -> CraftFormat? {
        switch writingFormat {
        case .instagramReel, .tiktokScript, .youtubeShort: return .reel
        case .instagramCarousel, .instagramStory: return .carousel
        case .twitterThread, .twitterSingle: return .thread
        case .linkedinPost, .newsletter, .youtubeLongForm: return .longForm
        default: return nil
        }
    }
}

// MARK: - Draft parsing

/// One slide/section of the open draft, split on SLIDE N headers when present
/// or paragraph boundaries otherwise.
struct CraftDraftSlide: Equatable, Sendable {
    var number: Int
    var text: String

    var sentenceCount: Int {
        text.split(whereSeparator: { ".!?".contains($0) })
            .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).count > 1 }
            .count
    }

    var wordCount: Int {
        text.split(separator: " ").count
    }
}

enum CraftDraftParser {
    private static let slideHeaderPattern = #"(?im)^\s*(?:-{2,}\s*)?(?:SLIDE|TWEET|SCENE)\s+(\d+)\s*:?\s*$"#

    /// Split a draft into slides. SLIDE/TWEET/SCENE N headers win; otherwise
    /// blank-line paragraphs.
    static func slides(in draft: String) -> [CraftDraftSlide] {
        let nsDraft = draft as NSString
        guard let regex = try? NSRegularExpression(pattern: slideHeaderPattern) else {
            return paragraphSlides(in: draft)
        }

        let matches = regex.matches(in: draft, range: NSRange(location: 0, length: nsDraft.length))
        guard matches.count >= 2 else {
            return paragraphSlides(in: draft)
        }

        var slides: [CraftDraftSlide] = []
        for (index, match) in matches.enumerated() {
            let bodyStart = match.range.location + match.range.length
            let bodyEnd = index + 1 < matches.count ? matches[index + 1].range.location : nsDraft.length
            guard bodyEnd > bodyStart else { continue }
            let body = nsDraft.substring(with: NSRange(location: bodyStart, length: bodyEnd - bodyStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let number = Int(nsDraft.substring(with: match.range(at: 1))) ?? (index + 1)
            slides.append(CraftDraftSlide(number: number, text: body))
        }
        return slides.filter { !$0.text.isEmpty }
    }

    private static func paragraphSlides(in draft: String) -> [CraftDraftSlide] {
        draft
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { CraftDraftSlide(number: $0.offset + 1, text: $0.element) }
    }
}

// MARK: - Format detection

enum CraftFormatDetector {
    /// Detect the format of the open piece. Slide density gets first say for
    /// reel/carousel scripts so comparable swipe selection follows the actual
    /// draft shape, even when older metadata says "carousel".
    static func detect(atom: Atom?, draftText: String) -> CraftFormat {
        let densityCall = densityHeuristic(draftText)
        if let atom {
            let writingFormat = WritingContentFormat.detect(from: atom)
            if let mapped = CraftFormat.from(writingFormat) {
                if (mapped == .carousel || mapped == .reel), let densityCall { return densityCall }
                return mapped
            }
        }
        return densityCall ?? .longForm
    }

    /// nil when the draft is too short to judge.
    static func densityHeuristic(_ draftText: String) -> CraftFormat? {
        let slides = CraftDraftParser.slides(in: draftText)
        guard slides.count >= 3 else { return nil }
        let avgSentences = Double(slides.map(\.sentenceCount).reduce(0, +)) / Double(slides.count)
        if avgSentences <= 2.2 { return .reel }
        return .carousel
    }
}

// MARK: - Comparables

/// A raw transcript plus its real-world numbers — the evidence unit every
/// craft claim must cite. Built from swipe atoms; never filtered by hookScore
/// (the whole library is curated; engagement is evidence, not a gate).
struct CraftComparable: Equatable, Sendable {
    var uuid: String
    var title: String
    var transcript: String
    var format: CraftFormat
    var views: Int?
    var likes: Int?
    var comments: Int?
    var engagementRate: Double?
    var hookType: String?
    var hookText: String?
    var niche: String?
    var beatFingerprint: String?
    var similarity: Float?

    var numbersLine: String {
        var parts: [String] = []
        if let views { parts.append("\(Self.compact(views)) views") }
        if let likes { parts.append("\(Self.compact(likes)) likes") }
        if let comments { parts.append("\(Self.compact(comments)) comments") }
        if let engagementRate { parts.append(String(format: "%.1f%% ER", engagementRate)) }
        return parts.isEmpty ? "no metrics recorded" : parts.joined(separator: " · ")
    }

    static func compact(_ value: Int) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...: return String(format: "%.1fK", Double(value) / 1_000)
        default: return "\(value)"
        }
    }
}

// MARK: - Structured results

struct CraftReviewEvidence: Codable, Equatable, Sendable {
    var comparable: String
    var numbers: String
    var insight: String
}

struct CraftPerformanceRead: Codable, Equatable, Sendable {
    /// top_quartile | above_median | around_median | below_median
    var tier: String
    var reasoning: String
    var evidence: [CraftReviewEvidence]

    var tierLabel: String {
        switch tier {
        case "top_quartile": return "Top-quartile potential"
        case "above_median": return "Above your median"
        case "around_median": return "Around your median"
        case "below_median": return "Below your median"
        default: return tier
        }
    }
}

struct CraftSlideNote: Codable, Equatable, Sendable {
    var slide: Int
    var failedTest: String
    var issue: String
    var fix: String
    var comparableQuote: String
}

struct CraftTopMove: Codable, Equatable, Sendable {
    var move: String
    var why: String
}

struct CraftWeakestBeat: Codable, Equatable, Sendable {
    var location: String
    var originalText: String
    var microVariations: [String]
}

/// The /review deliverable — schema-enforced so rendering never parses prose.
struct CraftReviewResult: Codable, Equatable, Sendable {
    var formatRead: String
    var performanceRead: CraftPerformanceRead
    var slideNotes: [CraftSlideNote]
    var topMoves: [CraftTopMove]
    var weakestBeat: CraftWeakestBeat?
    var verdict: String
}

struct CraftRiffVariation: Codable, Equatable, Sendable {
    var text: String
    var mechanism: String
    var borrowedFrom: String
    var numbers: String
}

/// The /riff deliverable — variations across distinct mechanisms for one beat.
struct CraftRiffResult: Codable, Equatable, Sendable {
    var beatLabel: String
    /// Copied verbatim from the draft — drives the zero-cost "apply N" path.
    var targetOriginalText: String
    var variations: [CraftRiffVariation]
    var bet: String
}

protocol CraftRenderableStructuredOutput: Decodable {
    var craftValidationIssue: String? { get }
}

extension CraftReviewResult: CraftRenderableStructuredOutput {
    var craftValidationIssue: String? {
        if formatRead.isBlankForCraft { return "missing format read" }
        if performanceRead.reasoning.isBlankForCraft { return "missing performance reasoning" }
        if verdict.isBlankForCraft { return "missing verdict" }
        // A review with no notes and no moves is a schema-shaped shell, not a
        // review. The structured-output API enforces `required` (key present)
        // and `enum`, but NOT `minLength`/`minItems` — so every free string can
        // legally come back "" and every array []. This is the substance gate
        // the schema cannot give us.
        if slideNotes.isEmpty && topMoves.isEmpty { return "no slide notes and no top moves" }
        return nil
    }
}

extension CraftRiffResult: CraftRenderableStructuredOutput {
    var craftValidationIssue: String? {
        if beatLabel.isBlankForCraft { return "missing beat label" }
        if targetOriginalText.isBlankForCraft { return "missing target text" }
        if variations.isEmpty { return "missing variations" }
        if bet.isBlankForCraft { return "missing bet" }
        if variations.contains(where: { $0.text.isBlankForCraft || $0.mechanism.isBlankForCraft }) {
            return "missing variation text"
        }
        return nil
    }
}

private extension String {
    var isBlankForCraft: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Riff apply parsing

enum CraftRiffApplyParser {
    /// Recognize "apply 2", "use option 3", "stage 1" follow-ups. 1-based.
    static func variationIndex(in prompt: String) -> Int? {
        let pattern = #"(?i)^\s*(?:apply|use|stage|go with|take)\s+(?:option\s+|variation\s+|number\s+|#)?(\d{1,2})\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsPrompt = prompt as NSString
        guard let match = regex.firstMatch(in: prompt, range: NSRange(location: 0, length: nsPrompt.length)),
              match.numberOfRanges > 1,
              let index = Int(nsPrompt.substring(with: match.range(at: 1))),
              index >= 1 else {
            return nil
        }
        return index
    }
}
