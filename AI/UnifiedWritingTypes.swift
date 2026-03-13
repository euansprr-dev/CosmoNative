// CosmoOS/AI/UnifiedWritingTypes.swift
// Shared types for the Unified Writing Engine
// February 2026

import Foundation

// MARK: - Conversation Types

struct WritingMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: WritingMessageRole
    let content: String
    let timestamp: Date
    var toolCalls: [WritingToolCall]?
    var toolResults: [WritingToolResult]?

    enum WritingMessageRole: String, Codable {
        case user
        case assistant
        case system
        case toolResult
    }

    init(id: UUID = UUID(), role: WritingMessageRole, content: String, timestamp: Date = Date(), toolCalls: [WritingToolCall]? = nil, toolResults: [WritingToolResult]? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCalls = toolCalls
        self.toolResults = toolResults
    }
}

struct WritingToolCall: Identifiable, Codable, Equatable {
    /// Tool call ID — preserved from Claude's response (e.g., "toolu_01abc..."). NOT a UUID.
    let id: String
    let toolName: String
    let parameters: String // JSON string
    var status: ToolCallStatus

    enum ToolCallStatus: String, Codable {
        case pending
        case executing
        case completed
        case failed
    }

    init(id: String = UUID().uuidString, toolName: String, parameters: String, status: ToolCallStatus = .pending) {
        self.id = id
        self.toolName = toolName
        self.parameters = parameters
        self.status = status
    }
}

struct WritingToolResult: Identifiable, Codable, Equatable {
    let id: UUID
    /// The original tool call ID from Claude (e.g., "toolu_01abc..."). Must match exactly.
    let toolCallId: String
    let content: String
    let isError: Bool

    init(id: UUID = UUID(), toolCallId: String, content: String, isError: Bool = false) {
        self.id = id
        self.toolCallId = toolCallId
        self.content = content
        self.isError = isError
    }
}

// MARK: - Compressed Swipe (for few-shot injection)

struct CompressedSwipe: Identifiable {
    let id: UUID
    let title: String
    let hookText: String
    let hookType: String
    let hookScore: Double
    let beatSequence: [String]
    let keyTransitions: [String]
    let ctaText: String
    let framework: String
    let format: String
    var isPrimary: Bool = false

    /// Marks this swipe as a client's own top-performing post (not a library swipe)
    var isClientExample: Bool = false

    /// Engagement score string for client examples (e.g., "1.2K likes, 340 saves")
    var engagementSummary: String = ""

    /// Full body excerpt for client example posts (their body text IS the correct topic)
    var fullBodyExcerpt: String = ""

    /// Structural breakdown for PRIMARY swipes — section functions, density, arc (NO topical text)
    var structuralBreakdown: String = ""

    /// Format as injection text (~200 tokens for non-primary, ~600 tokens for PRIMARY)
    func formatted() -> String {
        let beats = beatSequence.joined(separator: " > ")
        let primaryTag = isPrimary ? " [PRIMARY BLUEPRINT — EMULATE THIS]" : ""

        // Client top-performing post — different formatting with engagement data
        if isClientExample {
            let engagementLabel = engagementSummary.isEmpty ? "" : " (engagement: \(engagementSummary))"
            var result = """
            [CLIENT TOP POST]: "\(title)"\(engagementLabel)
            Format: \(format)
            """
            if !fullBodyExcerpt.isEmpty {
                result += "\n\(fullBodyExcerpt)"
            }
            return result
        }

        if isPrimary {
            // Expanded format for PRIMARY swipes: include full hook, all transitions, and body excerpt
            let allTransitions = keyTransitions.joined(separator: "\n  ")
            var result = """
            SWIPE EXAMPLE\(primaryTag): "\(title)"
            Hook (\(hookType), score \(String(format: "%.1f", hookScore))/10): "\(hookText)"
            Beat Pattern: \(beats)
            Section-by-Section Transitions:
              \(allTransitions)
            CTA: "\(ctaText)"
            Framework: \(framework) | Format: \(format)

            EMULATION NOTES: Your outline MUST mirror this swipe's beat pattern and hook type. \
            The hook must use the same syntactic structure and tension mechanism. \
            The section sequence must follow the same function order.
            """
            if !structuralBreakdown.isEmpty {
                result += "\n\nStructural Blueprint (extract structure only — topic may differ from client):\n\(structuralBreakdown)"
            }
            return result
        } else {
            let transitions = keyTransitions.prefix(3).joined(separator: "\n  ")
            let truncatedHook = hookText.count > 200 ? String(hookText.prefix(200)) + "..." : hookText
            return """
            SWIPE EXAMPLE: "\(title)"
            Hook (\(hookType), score \(String(format: "%.1f", hookScore))/10): "\(truncatedHook)"
            Structure: \(beats)
            Key Transitions:
              \(transitions)
            CTA: "\(ctaText)"
            Framework: \(framework) | Format: \(format)
            """
        }
    }
}

// MARK: - Tool Parameter Types

struct UpdateOutlineParams: Codable {
    let sections: [OutlineSection]
    let reasoning: String

    struct OutlineSection: Codable {
        let beatLabel: String
        let title: String
        let description: String
        let estimatedSeconds: Int?
        let notes: String?
    }
}

struct WriteDraftParams: Codable {
    let content: String
    let format: DraftFormat
    let selfEvaluation: SelfEvaluation

    enum DraftFormat: String, Codable {
        case plaintext
        case carouselJSON = "carousel_json"
        case threadJSON = "thread_json"
        case script
    }

    struct SelfEvaluation: Codable {
        let confidenceScore: Double
        let voiceMatchScore: Double
        let weakAreas: [String]
    }
}

struct EditSectionParams: Codable {
    let sectionIdentifier: String
    let newContent: String
    let reasoning: String
}

struct AddHooksParams: Codable {
    let hooks: [HookVariant]

    struct HookVariant: Codable {
        let text: String
        let hookType: String
        let estimatedScore: Double
        let reasoning: String
    }
}

struct SearchSwipesParams: Codable {
    let query: String
    let filters: SwipeFilters?

    struct SwipeFilters: Codable {
        let format: String?
        let hookType: String?
        let minScore: Double?
    }
}

struct SetDescriptionParams: Codable {
    let description: String
}

struct RunScorecardParams: Codable {
    // No parameters needed — evaluates current draft
}

struct ThinkParams: Codable {
    let thought: String
}

// MARK: - Validation Types

struct ValidationResult {
    enum Status {
        case passed(warnings: [ConstraintViolation])
        case needsCorrection([ConstraintViolation])
    }
    let status: Status
}

struct ConstraintViolation: Identifiable {
    let id = UUID()
    let constraintName: String
    let expected: String
    let actual: String
    let severity: Severity

    enum Severity {
        case hard  // Must fix before output
        case soft  // Warning only
    }

    var description: String {
        "\(constraintName): expected \(expected), got \(actual) [\(severity == .hard ? "HARD" : "SOFT")]"
    }
}

// MARK: - Platform Constraints

struct PlatformConstraints {
    let formatName: String
    let hardConstraints: [FormatConstraint]
    let softConstraints: [FormatConstraint]

    struct FormatConstraint {
        let name: String
        let validate: (ParsedContent) -> Bool
        let measure: (ParsedContent) -> String
    }
}

/// Parsed structured content for validation
enum ParsedContent {
    case carousel(slides: [SlideContent])
    case thread(tweets: [TweetContent])
    case script(scenes: [SceneContent])
    case longform(text: String, sections: [String])
    case singlePost(text: String)

    struct SlideContent {
        let number: Int
        let text: String
        let visualDirection: String?
    }

    struct TweetContent {
        let number: Int
        let text: String
    }

    struct SceneContent {
        let number: Int
        let text: String
        let estimatedSeconds: Int?
        let visualMarker: String?
    }
}

// MARK: - Content Format Detection

enum WritingContentFormat: String, CaseIterable {
    case instagramCarousel
    case instagramReel
    case instagramStory
    case twitterThread
    case twitterSingle
    case linkedinPost
    case youtubeShort
    case youtubeLongForm
    case tiktokScript
    case newsletter
    case staticPost

    var displayName: String {
        switch self {
        case .instagramCarousel: return "Instagram Carousel"
        case .instagramReel: return "Instagram Reel"
        case .instagramStory: return "Instagram Story"
        case .twitterThread: return "Twitter/X Thread"
        case .twitterSingle: return "Twitter/X Post"
        case .linkedinPost: return "LinkedIn Post"
        case .youtubeShort: return "YouTube Short"
        case .youtubeLongForm: return "YouTube Long-Form"
        case .tiktokScript: return "TikTok Script"
        case .newsletter: return "Newsletter"
        case .staticPost: return "Static Image Post"
        }
    }

    /// Exact swipe types allowed for this writing target.
    var swipeFormatFamily: Set<ContentFormat> {
        switch self {
        case .instagramReel, .tiktokScript, .youtubeShort:
            return [.reel, .voiceoverReel, .oneSliderReel, .multiSliderReel, .twoStepCTA]
        case .instagramCarousel, .instagramStory:
            return [.carousel]
        case .twitterThread:
            return [.thread]
        case .twitterSingle:
            return [.tweet]
        case .linkedinPost, .staticPost:
            return [.post]
        case .youtubeLongForm:
            return [.youtube]
        case .newsletter:
            return [.newsletter]
        }
    }

    var isVideoFormat: Bool {
        switch self {
        case .instagramReel, .tiktokScript, .youtubeShort, .youtubeLongForm:
            return true
        default: return false
        }
    }

    var draftFormat: WriteDraftParams.DraftFormat {
        switch self {
        case .instagramCarousel, .instagramStory: return .carouselJSON
        case .twitterThread: return .threadJSON
        case .instagramReel, .youtubeShort, .youtubeLongForm, .tiktokScript: return .script
        case .twitterSingle, .linkedinPost, .newsletter, .staticPost: return .plaintext
        }
    }

    /// Query terms used when backfilling same-type swipes from search.
    var swipeSearchTerms: [String] {
        switch self {
        case .instagramReel, .tiktokScript, .youtubeShort:
            return ["reel", "short form video", "voiceover reel"]
        case .instagramCarousel:
            return ["carousel", "slides"]
        case .instagramStory:
            return ["story", "slides"]
        case .twitterThread:
            return ["thread"]
        case .twitterSingle:
            return ["tweet", "x post"]
        case .linkedinPost:
            return ["linkedin post", "post"]
        case .youtubeLongForm:
            return ["youtube", "long form"]
        case .newsletter:
            return ["newsletter"]
        case .staticPost:
            return ["post", "static post"]
        }
    }

    func matchesSwipeFormat(_ format: ContentFormat?) -> Bool {
        guard let format else { return false }
        return swipeFormatFamily.contains(format)
    }

    static func detect(from atom: Atom) -> WritingContentFormat {
        if let explicitFormat = atom.metadataDict?["explicitFormat"] as? String {
            switch explicitFormat {
            case "reel": return .instagramReel
            case "carousel": return .instagramCarousel
            case "thread": return .twitterThread
            case "post": return .staticPost
            default: break
            }
        }

        guard let meta = atom.metadataValue(as: ContentAtomMetadata.self) else {
            return .staticPost
        }

        switch meta.platform {
        case .instagram:
            let focusState = ContentFocusModeState.from(atom: atom)
            let draft = focusState?.draftContent ?? ""
            if draft.contains("\"slides\"") { return .instagramCarousel }
            if draft.contains("[STORY:") { return .instagramStory }
            if draft.contains("[VISUAL:") { return .instagramReel }
            return .instagramReel

        case .twitter:
            let focusState = ContentFocusModeState.from(atom: atom)
            let draft = focusState?.draftContent ?? ""
            if draft.contains("\"tweets\"") { return .twitterThread }
            return .twitterSingle

        case .linkedin: return .linkedinPost
        case .youtube: return .youtubeLongForm
        case .tiktok: return .tiktokScript
        default: return .staticPost
        }
    }

    static func matchingSwipeFormats(for filter: String) -> Set<ContentFormat>? {
        let normalized = normalizeFormatFilter(filter)
        guard !normalized.isEmpty else { return nil }

        if normalized.contains("carousel") { return [.carousel] }
        if normalized.contains("story") { return [.carousel] }
        if normalized.contains("thread") { return [.thread] }
        if normalized.contains("tweet") || normalized.contains("x post") || normalized.contains("twitter post") {
            return [.tweet]
        }
        if normalized.contains("linkedin") || normalized.contains("static post") {
            return [.post]
        }
        if normalized.contains("newsletter") { return [.newsletter] }
        if normalized.contains("youtube") && normalized.contains("long") { return [.youtube] }
        if normalized.contains("reel") || normalized.contains("tiktok") || normalized.contains("short") {
            return [.reel, .voiceoverReel, .oneSliderReel, .multiSliderReel, .twoStepCTA]
        }

        if let direct = ContentFormat.allCases.first(where: {
            normalizeFormatFilter($0.rawValue) == normalized || normalizeFormatFilter($0.displayName) == normalized
        }) {
            return [direct]
        }

        return nil
    }

    private static func normalizeFormatFilter(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

// MARK: - Experience Entry (for learning bridge)

struct ExperienceEntry: Codable {
    let generatedExcerpt: String
    let editedExcerpt: String
    let diffSummary: String
    let editDistance: Double
    let contentFormat: String
    let createdAt: Date
}

// MARK: - Writing Tool Chain Visualization

struct WritingToolChainStep: Identifiable {
    let id = UUID()
    let toolName: String
    var label: String
    let timestamp: Date
    var status: WritingToolCall.ToolCallStatus
    var resultPreview: String?
}

// MARK: - Claude Tool Use Response Parsing

struct ClaudeToolUseResponse: @unchecked Sendable {
    let textContent: String
    let toolCalls: [ClaudeToolCall]
    let stopReason: String?

    struct ClaudeToolCall: Identifiable, @unchecked Sendable {
        let id: String
        let name: String
        let input: [String: Any]
    }
}

// MARK: - Model Tier Selection

/// Model tier selection for cost/quality optimization (moved from OpusWritingEngine)
enum ContentModelTier: String {
    case writer = "anthropic/claude-opus-4.6"
    case strategist = "anthropic/claude-sonnet-4.5"
    case fast = "google/gemini-2.0-flash-001"

    var maxTokens: Int {
        switch self {
        case .writer: return 16384
        case .strategist: return 8192
        case .fast: return 4096
        }
    }
}

// MARK: - Telegram Writer Model Selection

/// Available writer models for Telegram A/B testing.
/// Scorecard stays on Sonnet — this only affects brainstorm/draft/polish phases.
enum TelegramWriterModel: String, CaseIterable {
    case opus = "anthropic/claude-opus-4.6"
    case gpt5 = "openai/gpt-5.4"

    var displayName: String {
        switch self {
        case .opus: return "Opus 4.6"
        case .gpt5: return "GPT 5.4"
        }
    }

    var maxTokens: Int { 16384 }

    private static let userDefaultsKey = "telegram_writer_model"

    static var current: TelegramWriterModel {
        guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
              let model = TelegramWriterModel(rawValue: raw) else {
            return .opus
        }
        return model
    }

    static func setCurrent(_ model: TelegramWriterModel) {
        UserDefaults.standard.set(model.rawValue, forKey: userDefaultsKey)
    }

    @discardableResult
    static func toggle() -> TelegramWriterModel {
        let next: TelegramWriterModel = current == .opus ? .gpt5 : .opus
        setCurrent(next)
        return next
    }
}

// MARK: - Legacy Result Types (used by agent tools and ContentAICollaboratorEngine)

/// A single item in an AI-generated outline
struct OpusOutlineItem: Codable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var keyPoints: [String]
    var estimatedSeconds: Int?
    var reasoning: String?

    init(id: UUID = UUID(), title: String, keyPoints: [String] = [], estimatedSeconds: Int? = nil, reasoning: String? = nil) {
        self.id = id
        self.title = title
        self.keyPoints = keyPoints
        self.estimatedSeconds = estimatedSeconds
        self.reasoning = reasoning
    }
}

/// Result from a full draft generation
struct DraftResult: Codable, Sendable {
    let body: String
    let hookUsed: String?
    let frameworkUsed: String?
    let wordCount: Int
    let confidenceScore: Int          // 0-100
    let confidenceReasoning: String?
    let swipeSourceCount: Int
}

/// A hook variant with analysis metadata
struct HookVariant: Codable, Identifiable, Sendable {
    let id: UUID
    let text: String
    let hookType: String
    let estimatedScore: Double        // 0.0-10.0
    let reasoning: String

    init(id: UUID = UUID(), text: String, hookType: String, estimatedScore: Double, reasoning: String) {
        self.id = id
        self.text = text
        self.hookType = hookType
        self.estimatedScore = estimatedScore
        self.reasoning = reasoning
    }
}

/// Confidence breakdown returned with generations
struct ConfidenceBreakdown: Codable, Sendable {
    let overall: Int                  // 0-100
    let swipeLibraryDepth: Int        // 0-100
    let metaPatternAlignment: Int     // 0-100
    let clientVoiceMatch: Int         // 0-100
    let noveltyCheck: Int             // 0-100
    let reasoning: String
}

/// Structured system block with prompt caching metadata.
struct PromptCacheBlock: Sendable {
    let content: String
    let cacheControl: Bool
    let ttl: String?
    let label: String

    init(
        content: String,
        cacheControl: Bool,
        ttl: String? = nil,
        label: String = ""
    ) {
        self.content = content
        self.cacheControl = cacheControl
        self.ttl = ttl
        self.label = label
    }
}

/// 4-layer mega-context prompt with cache control boundaries for prompt caching.
struct PromptContext {
    let systemBlocks: [PromptCacheBlock]
    let modelTier: ContentModelTier
}

/// A single section in a generated outline, mapped to a canonical beat label
struct OutlineSection: Codable, Identifiable {
    let id: UUID
    var beatLabel: String
    var title: String
    var description: String
    var estimatedSeconds: Int?
    var notes: String?

    init(id: UUID = UUID(), beatLabel: String, title: String, description: String, estimatedSeconds: Int? = nil, notes: String? = nil) {
        self.id = id
        self.beatLabel = beatLabel
        self.title = title
        self.description = description
        self.estimatedSeconds = estimatedSeconds
        self.notes = notes
    }
}

/// Structured outline result with beat pattern analysis
struct GeneratedOutline {
    let sections: [OutlineSection]
    let hookVariants: [HookVariant]
    let selectedPatternFingerprint: String?
    let patternReasoning: String?
}

/// Full draft generation result with self-evaluation
struct GeneratedDraft {
    let content: String
    let confidenceScore: Int  // 0-100
    let selfEvaluation: String
    let weakAreas: [String]
    let wordCount: Int
    let selfCorrectionRuleCount: Int?
}

// MARK: - Chain-of-Thought Stripping

/// Strip thinking/analysis tags that LLMs sometimes include in their output.
/// Removes everything between <thinking>...</thinking>, <analysis>...</analysis>,
/// <thinking_process>...</thinking_process>, and similar tag pairs.
func stripThinkingTags(_ text: String) -> String {
    var result = text
    let tagPatterns = [
        "<thinking>[\\s\\S]*?</thinking>",
        "<thinking_process>[\\s\\S]*?</thinking_process>",
        "<analysis>[\\s\\S]*?</analysis>",
        "<chain_of_thought>[\\s\\S]*?</chain_of_thought>",
        "<reasoning>[\\s\\S]*?</reasoning>",
        "<self_check>[\\s\\S]*?</self_check>"
    ]
    for pattern in tagPatterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}
