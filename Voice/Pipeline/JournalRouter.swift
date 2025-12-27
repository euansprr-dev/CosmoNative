// CosmoOS/Voice/Pipeline/JournalRouter.swift
// Routes freeform voice input to journal categories with AI classification

import Foundation
import NaturalLanguage
import GRDB

// MARK: - Journal Entry Type

/// Classification of journal entry types
enum JournalEntryType: String, Codable, Sendable, CaseIterable {
    case reflection = "reflection"       // Deep thoughts, life observations
    case gratitude = "gratitude"         // Things to be thankful for
    case mood = "mood"                   // Emotional state logging
    case dailyLog = "daily_log"          // What happened today
    case goal = "goal"                   // Goals and aspirations
    case learning = "learning"           // What I learned
    case challenge = "challenge"         // Obstacles and challenges
    case celebration = "celebration"     // Wins and achievements
    case intention = "intention"         // Daily/weekly intentions
    case freeform = "freeform"           // Unclassified thoughts

    var dimension: String {
        switch self {
        case .reflection, .mood, .freeform:
            return "reflection"
        case .gratitude, .celebration:
            return "behavioral"
        case .goal, .intention:
            return "cognitive"
        case .learning:
            return "knowledge"
        case .dailyLog:
            return "behavioral"
        case .challenge:
            return "reflection"
        }
    }

    var xpValue: Int {
        switch self {
        case .reflection: return 25
        case .gratitude: return 20
        case .mood: return 10
        case .dailyLog: return 15
        case .goal: return 30
        case .learning: return 35
        case .challenge: return 25
        case .celebration: return 20
        case .intention: return 20
        case .freeform: return 10
        }
    }

    var icon: String {
        switch self {
        case .reflection: return "bubble.left.and.bubble.right.fill"
        case .gratitude: return "heart.fill"
        case .mood: return "face.smiling"
        case .dailyLog: return "calendar"
        case .goal: return "target"
        case .learning: return "lightbulb.fill"
        case .challenge: return "mountain.2.fill"
        case .celebration: return "party.popper.fill"
        case .intention: return "sunrise.fill"
        case .freeform: return "text.bubble.fill"
        }
    }

    var promptSuggestion: String {
        switch self {
        case .reflection: return "What's on your mind?"
        case .gratitude: return "What are you grateful for?"
        case .mood: return "How are you feeling?"
        case .dailyLog: return "What happened today?"
        case .goal: return "What do you want to achieve?"
        case .learning: return "What did you learn?"
        case .challenge: return "What's challenging you?"
        case .celebration: return "What are you celebrating?"
        case .intention: return "What's your intention?"
        case .freeform: return "What's on your mind?"
        }
    }
}

// MARK: - Mood Classification

/// Mood classification for emotional journaling
enum MoodCategory: String, Codable, Sendable {
    case positive = "positive"
    case neutral = "neutral"
    case negative = "negative"
    case mixed = "mixed"

    var energyLevel: EnergyLevel {
        switch self {
        case .positive: return .high
        case .neutral: return .medium
        case .negative: return .low
        case .mixed: return .medium
        }
    }
}

enum EnergyLevel: String, Codable, Sendable {
    case high = "high"
    case medium = "medium"
    case low = "low"
}

// MARK: - Voice Journal Entry Metadata

/// Metadata for classified journal entries from voice pipeline
struct VoiceJournalMetadata: Codable, Sendable {
    let entryType: JournalEntryType
    let mood: MoodCategory?
    let energyLevel: EnergyLevel?
    let sentiment: Double               // -1.0 to 1.0
    let topics: [String]                // Extracted topics
    let entities: [JournalExtractedEntity]     // People, places, things
    let xpEarned: Int
    let dimension: String
    let wordCount: Int
    let recordedVia: RecordingMethod

    enum RecordingMethod: String, Codable, Sendable {
        case voice = "voice"
        case text = "text"
    }
}

/// Extracted entity from journal text
struct JournalExtractedEntity: Codable, Sendable {
    let text: String
    let type: JournalEntityType
    let confidence: Double

    enum JournalEntityType: String, Codable, Sendable {
        case person = "person"
        case place = "place"
        case organization = "organization"
        case event = "event"
        case project = "project"
        case date = "date"
        case other = "other"
    }
}

// MARK: - Journal Classification Result

/// Result of journal entry classification
struct JournalClassificationResult: Sendable {
    let entryType: JournalEntryType
    let confidence: Double
    let mood: MoodCategory?
    let sentiment: Double
    let topics: [String]
    let entities: [JournalExtractedEntity]
    let suggestedPrompts: [String]

    init(
        entryType: JournalEntryType,
        confidence: Double,
        mood: MoodCategory? = nil,
        sentiment: Double = 0.0,
        topics: [String] = [],
        entities: [JournalExtractedEntity] = [],
        suggestedPrompts: [String] = []
    ) {
        self.entryType = entryType
        self.confidence = confidence
        self.mood = mood
        self.sentiment = sentiment
        self.topics = topics
        self.entities = entities
        self.suggestedPrompts = suggestedPrompts
    }
}

// MARK: - Journal Router

/// Routes freeform voice input to journal categories with AI classification.
/// Uses NLP for local classification and optional LLM for complex cases.
actor JournalRouter {
    static let shared = JournalRouter()

    private let sentimentAnalyzer = NLTagger(tagSchemes: [.sentimentScore])
    private let entityRecognizer = NLTagger(tagSchemes: [.nameType])
    private let lemmatizer = NLTagger(tagSchemes: [.lemma])

    // Classification keywords by type
    private let typeKeywords: [JournalEntryType: [String]] = [
        .gratitude: [
            "grateful", "thankful", "appreciate", "blessed", "fortunate",
            "thanks", "thank you", "lucky", "grateful for", "appreciating"
        ],
        .mood: [
            "feeling", "feel", "i'm", "i am", "mood", "emotion", "emotional",
            "happy", "sad", "anxious", "stressed", "excited", "tired", "energetic",
            "calm", "angry", "frustrated", "content", "peaceful", "overwhelmed"
        ],
        .goal: [
            "want to", "goal", "aspire", "dream", "hoping to", "plan to",
            "going to", "will", "aim", "objective", "target", "achieve",
            "accomplish", "by next", "in the future", "someday"
        ],
        .learning: [
            "learned", "learning", "discovered", "realized", "understood",
            "figured out", "insight", "lesson", "teaching", "taught me",
            "now i know", "understand now", "epiphany"
        ],
        .challenge: [
            "challenge", "difficult", "hard", "struggle", "struggling",
            "obstacle", "problem", "issue", "stuck", "can't", "won't",
            "blocking", "frustrated with", "hard time"
        ],
        .celebration: [
            "celebrate", "won", "achieved", "accomplished", "success",
            "proud", "excited about", "finally", "milestone", "breakthrough",
            "victory", "made it", "did it"
        ],
        .intention: [
            "today i will", "this week", "intention", "focus on",
            "priority", "commit to", "dedicating", "setting", "morning",
            "starting", "beginning"
        ],
        .reflection: [
            "thinking about", "pondering", "wondering", "contemplating",
            "reflecting on", "occurred to me", "realizing", "considering",
            "looking back", "in retrospect", "perspective"
        ],
        .dailyLog: [
            "today", "this morning", "this afternoon", "this evening",
            "happened", "did", "went", "met", "worked on", "finished",
            "started", "completed"
        ]
    ]

    // MARK: - Classification

    /// Classify a freeform voice transcript into a journal entry type.
    func classify(_ transcript: String) async -> JournalClassificationResult {
        let lowered = transcript.lowercased()

        // 1. Keyword-based classification
        let keywordResult = classifyByKeywords(lowered)

        // 2. Sentiment analysis
        let sentiment = analyzeSentiment(transcript)

        // 3. Mood detection
        let mood = detectMood(lowered, sentiment: sentiment)

        // 4. Entity extraction
        let entities = extractEntities(transcript)

        // 5. Topic extraction
        let topics = extractTopics(transcript)

        // 6. Generate follow-up prompts
        let prompts = generatePrompts(for: keywordResult.type, sentiment: sentiment)

        return JournalClassificationResult(
            entryType: keywordResult.type,
            confidence: keywordResult.confidence,
            mood: mood,
            sentiment: sentiment,
            topics: topics,
            entities: entities,
            suggestedPrompts: prompts
        )
    }

    /// Classify using keyword matching
    private func classifyByKeywords(_ text: String) -> (type: JournalEntryType, confidence: Double) {
        var scores: [JournalEntryType: Int] = [:]

        for (type, keywords) in typeKeywords {
            for keyword in keywords {
                if text.contains(keyword) {
                    scores[type, default: 0] += 1
                }
            }
        }

        // Find the type with highest score
        if let (topType, topScore) = scores.max(by: { $0.value < $1.value }), topScore > 0 {
            // Confidence based on number of keyword matches
            let confidence = min(0.95, 0.5 + Double(topScore) * 0.1)
            return (topType, confidence)
        }

        // Default to freeform if no clear match
        return (.freeform, 0.4)
    }

    /// Analyze sentiment using NLP
    private func analyzeSentiment(_ text: String) -> Double {
        sentimentAnalyzer.string = text

        var totalSentiment: Double = 0
        var count = 0

        sentimentAnalyzer.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .sentence,
            scheme: .sentimentScore
        ) { tag, range in
            if let tag = tag, let score = Double(tag.rawValue) {
                totalSentiment += score
                count += 1
            }
            return true
        }

        return count > 0 ? totalSentiment / Double(count) : 0.0
    }

    /// Detect mood from text and sentiment
    private func detectMood(_ text: String, sentiment: Double) -> MoodCategory {
        // Positive mood indicators
        let positiveWords = ["happy", "excited", "grateful", "amazing", "wonderful", "great", "fantastic", "love", "joy", "peaceful", "calm", "content"]
        let negativeWords = ["sad", "anxious", "stressed", "worried", "frustrated", "angry", "tired", "exhausted", "overwhelmed", "depressed", "lonely"]

        let hasPositive = positiveWords.contains { text.contains($0) }
        let hasNegative = negativeWords.contains { text.contains($0) }

        if hasPositive && hasNegative {
            return .mixed
        } else if hasPositive || sentiment > 0.3 {
            return .positive
        } else if hasNegative || sentiment < -0.3 {
            return .negative
        } else {
            return .neutral
        }
    }

    /// Extract named entities from text
    private func extractEntities(_ text: String) -> [JournalExtractedEntity] {
        var entities: [JournalExtractedEntity] = []

        entityRecognizer.string = text

        entityRecognizer.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType
        ) { tag, range in
            guard let tag = tag else { return true }

            let entityText = String(text[range])

            // Skip common words
            guard entityText.count > 2 else { return true }

            let entityType: JournalExtractedEntity.JournalEntityType
            switch tag {
            case .personalName:
                entityType = .person
            case .placeName:
                entityType = .place
            case .organizationName:
                entityType = .organization
            default:
                return true
            }

            let entity = JournalExtractedEntity(
                text: entityText,
                type: entityType,
                confidence: 0.8
            )
            entities.append(entity)

            return true
        }

        return entities
    }

    /// Extract key topics from text
    private func extractTopics(_ text: String) -> [String] {
        var topics: Set<String> = []

        lemmatizer.string = text

        // Extract nouns as potential topics
        lemmatizer.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lemma
        ) { tag, range in
            guard let lemma = tag?.rawValue else { return true }

            let word = String(text[range]).lowercased()

            // Skip common words
            let stopWords = Set(["the", "a", "an", "is", "was", "are", "were", "been", "being",
                                 "have", "has", "had", "do", "does", "did", "will", "would",
                                 "could", "should", "may", "might", "must", "shall", "can",
                                 "i", "you", "he", "she", "it", "we", "they", "my", "your",
                                 "his", "her", "its", "our", "their", "this", "that", "these",
                                 "those", "to", "of", "in", "for", "on", "with", "at", "by",
                                 "from", "about", "into", "through", "during", "before",
                                 "after", "above", "below", "between", "under", "again",
                                 "further", "then", "once", "and", "but", "or", "nor", "so",
                                 "yet", "both", "either", "neither", "not", "only", "same",
                                 "than", "too", "very", "just", "now", "how", "all", "each",
                                 "every", "any", "some", "no", "such", "like", "what", "when",
                                 "where", "why", "which", "who", "whom", "whose", "there",
                                 "here", "am", "really", "today", "going", "think", "feel"])

            if word.count > 3 && !stopWords.contains(word) {
                topics.insert(lemma.lowercased())
            }

            return true
        }

        return Array(topics.prefix(5))
    }

    /// Generate follow-up prompts based on entry type
    private func generatePrompts(for type: JournalEntryType, sentiment: Double) -> [String] {
        switch type {
        case .gratitude:
            return [
                "What made this moment special?",
                "How did this make you feel?",
                "Is there someone you'd like to thank?"
            ]
        case .mood:
            if sentiment < 0 {
                return [
                    "What might help you feel better?",
                    "Is there something you need right now?",
                    "Would you like to explore this feeling more?"
                ]
            } else {
                return [
                    "What contributed to this feeling?",
                    "How can you hold onto this?",
                    "Who would you like to share this with?"
                ]
            }
        case .goal:
            return [
                "What's the first step?",
                "What might get in the way?",
                "How will you know you've succeeded?"
            ]
        case .learning:
            return [
                "How will you apply this?",
                "What surprised you about this?",
                "Who else might benefit from this insight?"
            ]
        case .challenge:
            return [
                "What have you tried so far?",
                "Who could help with this?",
                "What's the smallest next step?"
            ]
        case .celebration:
            return [
                "How does this achievement feel?",
                "Who helped you get here?",
                "What did you learn on the way?"
            ]
        case .intention:
            return [
                "Why is this important to you?",
                "What might distract you?",
                "How will you stay accountable?"
            ]
        case .reflection:
            return [
                "What led you to think about this?",
                "How does this connect to other parts of your life?",
                "What action, if any, does this suggest?"
            ]
        case .dailyLog:
            return [
                "What was the highlight?",
                "What would you do differently?",
                "What are you looking forward to tomorrow?"
            ]
        case .freeform:
            return [
                "Tell me more about this.",
                "How does this make you feel?",
                "What's the most important part?"
            ]
        }
    }

    // MARK: - Processing

    /// Process a classified journal entry and create an Atom
    func processEntry(
        transcript: String,
        classification: JournalClassificationResult,
        database: any DatabaseWriter
    ) async throws -> Atom {
        let wordCount = transcript.split(separator: " ").count

        let metadata = VoiceJournalMetadata(
            entryType: classification.entryType,
            mood: classification.mood,
            energyLevel: classification.mood?.energyLevel,
            sentiment: classification.sentiment,
            topics: classification.topics,
            entities: classification.entities,
            xpEarned: classification.entryType.xpValue,
            dimension: classification.entryType.dimension,
            wordCount: wordCount,
            recordedVia: .voice
        )

        let metadataJson = try JSONEncoder().encode(metadata)
        let title = generateTitle(for: classification.entryType, transcript: transcript)

        let atom = try await database.write { db in
            let newAtom = Atom.new(
                type: .journalEntry,
                title: title,
                body: transcript,
                metadata: String(data: metadataJson, encoding: .utf8)
            )
            try newAtom.insert(db)
            return newAtom
        }

        // Award XP for journaling
        await awardJournalXP(
            type: classification.entryType,
            wordCount: wordCount,
            database: database
        )

        // Update streak
        await updateJournalStreak(database: database)

        return atom
    }

    /// Generate a title for the journal entry
    private func generateTitle(for type: JournalEntryType, transcript: String) -> String {
        let words = transcript.split(separator: " ")
        let preview = words.prefix(6).joined(separator: " ")

        switch type {
        case .gratitude:
            return "Gratitude: \(preview)..."
        case .mood:
            return "Mood Check: \(preview)..."
        case .goal:
            return "Goal: \(preview)..."
        case .learning:
            return "Learning: \(preview)..."
        case .challenge:
            return "Challenge: \(preview)..."
        case .celebration:
            return "Celebration: \(preview)..."
        case .intention:
            return "Intention: \(preview)..."
        case .reflection:
            return "Reflection: \(preview)..."
        case .dailyLog:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: Date())): \(preview)..."
        case .freeform:
            return "Journal: \(preview)..."
        }
    }

    /// Award XP for journal entry
    private func awardJournalXP(
        type: JournalEntryType,
        wordCount: Int,
        database: any DatabaseWriter
    ) async {
        var xp = type.xpValue

        // Bonus for longer entries
        if wordCount > 50 { xp += 5 }
        if wordCount > 100 { xp += 10 }
        if wordCount > 200 { xp += 15 }

        // Award to the reflection dimension
        let xpToAward = xp
        do {
            try await database.write { db in
                if var state = try CosmoLevelState.fetchOne(db) {
                    state.addXP(xpToAward, dimension: type.dimension)
                    try state.update(db)
                }
            }
        } catch {
            print("Failed to award journal XP: \(error)")
        }
    }

    /// Update journal streak
    private func updateJournalStreak(database: any DatabaseWriter) async {
        // Journal streak tracking is handled by the LevelSystemService
        // through the StreakTracker which monitors atom creation
        // No direct database update needed here
    }
}

// MARK: - Voice Pattern Extension

extension PatternMatcher {

    /// Journal voice patterns for freeform entry
    nonisolated static var journalPatterns: [CommandPattern] {
        [
            // Explicit journal commands
            CommandPattern(
                regex: #"^(journal|write|log|record)\s*(entry)?\s*(.+)$"#,
                action: .create,
                atomType: .journalEntry,
                extractor: { match in
                    let content = match[3].trimmingCharacters(in: .whitespaces)
                    return PatternMatchResult(
                        action: .create,
                        atomType: .journalEntry,
                        title: content,
                        matchedPattern: "journal_explicit",
                        confidence: 0.95
                    )
                }
            ),

            // Gratitude specific
            CommandPattern(
                regex: #"^i('?m| am)\s+(grateful|thankful)\s+(for|that)\s+(.+)$"#,
                action: .create,
                atomType: .journalEntry,
                extractor: { match in
                    let content = "I am grateful \(match[3]) \(match[4])"
                    return PatternMatchResult(
                        action: .create,
                        atomType: .journalEntry,
                        title: content,
                        matchedPattern: "gratitude_entry",
                        confidence: 0.95
                    )
                },
                metadataExtractor: { _ in
                    ["entryType": VoiceAnyCodable("gratitude")]
                }
            ),

            // Mood check
            CommandPattern(
                regex: #"^i('?m| am)\s+(feeling|so)\s+(.+)$"#,
                action: .create,
                atomType: .journalEntry,
                extractor: { match in
                    let content = "I'm feeling \(match[3])"
                    return PatternMatchResult(
                        action: .create,
                        atomType: .journalEntry,
                        title: content,
                        matchedPattern: "mood_entry",
                        confidence: 0.9
                    )
                },
                metadataExtractor: { _ in
                    ["entryType": VoiceAnyCodable("mood")]
                }
            ),

            // Reflection
            CommandPattern(
                regex: #"^i('?ve| have)\s+been\s+(thinking|wondering)\s+about\s+(.+)$"#,
                action: .create,
                atomType: .journalEntry,
                extractor: { match in
                    let content = "I've been thinking about \(match[3])"
                    return PatternMatchResult(
                        action: .create,
                        atomType: .journalEntry,
                        title: content,
                        matchedPattern: "reflection_entry",
                        confidence: 0.9
                    )
                },
                metadataExtractor: { _ in
                    ["entryType": VoiceAnyCodable("reflection")]
                }
            ),

            // Learning
            CommandPattern(
                regex: #"^i\s+(learned|realized|discovered)\s+(that\s+)?(.+)$"#,
                action: .create,
                atomType: .journalEntry,
                extractor: { match in
                    let content = "I \(match[1]) \(match[2])\(match[3])"
                    return PatternMatchResult(
                        action: .create,
                        atomType: .journalEntry,
                        title: content,
                        matchedPattern: "learning_entry",
                        confidence: 0.9
                    )
                },
                metadataExtractor: { _ in
                    ["entryType": VoiceAnyCodable("learning")]
                }
            ),
        ]
    }
}
