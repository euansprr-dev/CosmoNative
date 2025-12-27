// CosmoOS/Data/Models/Sanctuary/SemanticAnalysisEngine.swift
// Semantic Analysis Engine - Extracts meaning from journal entries and content
// Uses on-device NLP and optional cloud models for deep analysis

import Foundation
import GRDB
import NaturalLanguage

// MARK: - Semantic Extraction Types

/// Categories of semantic content extracted from journals
public enum SemanticCategory: String, Codable, Sendable, CaseIterable {
    case topic             // Main subjects discussed
    case emotion           // Emotional content (joy, frustration, anxiety, etc.)
    case goal              // Goals mentioned or implied
    case fear              // Fears, worries, concerns
    case gratitude         // Things the user is grateful for
    case person            // People mentioned
    case accomplishment    // Achievements mentioned
    case challenge         // Challenges or obstacles
    case insight           // Realizations or learnings
    case intention         // Future plans or intentions
}

/// Emotional valence
public enum EmotionalValence: String, Codable, Sendable {
    case veryNegative = "very_negative"
    case negative
    case slightlyNegative = "slightly_negative"
    case neutral
    case slightlyPositive = "slightly_positive"
    case positive
    case veryPositive = "very_positive"

    public var numericValue: Double {
        switch self {
        case .veryNegative: return -1.0
        case .negative: return -0.66
        case .slightlyNegative: return -0.33
        case .neutral: return 0.0
        case .slightlyPositive: return 0.33
        case .positive: return 0.66
        case .veryPositive: return 1.0
        }
    }

    public static func from(score: Double) -> EmotionalValence {
        switch score {
        case ..<(-0.75): return .veryNegative
        case ..<(-0.4): return .negative
        case ..<(-0.1): return .slightlyNegative
        case ..<0.1: return .neutral
        case ..<0.4: return .slightlyPositive
        case ..<0.75: return .positive
        default: return .veryPositive
        }
    }
}

/// Emotional energy level
public enum EmotionalEnergy: String, Codable, Sendable {
    case veryLow = "very_low"
    case low
    case moderate
    case high
    case veryHigh = "very_high"

    public var numericValue: Double {
        switch self {
        case .veryLow: return 0.1
        case .low: return 0.3
        case .moderate: return 0.5
        case .high: return 0.7
        case .veryHigh: return 0.9
        }
    }
}

// MARK: - Extracted Content

/// A single extracted semantic element
public struct SemanticElement: Codable, Sendable, Equatable, Hashable {
    public let category: SemanticCategory
    public let content: String           // The extracted text or concept
    public let confidence: Double        // 0-1 confidence score
    public let sentiment: Double?        // -1 to 1 sentiment if applicable
    public let context: String?          // Surrounding context from source

    public init(
        category: SemanticCategory,
        content: String,
        confidence: Double,
        sentiment: Double? = nil,
        context: String? = nil
    ) {
        self.category = category
        self.content = content
        self.confidence = confidence
        self.sentiment = sentiment
        self.context = context
    }
}

/// Complete semantic extraction from a journal entry
public struct SemanticExtraction: Codable, Sendable {
    public let sourceUUID: String        // Journal entry UUID
    public let extractedAt: Date
    public let wordCount: Int
    public let sentenceCount: Int
    public let overallValence: EmotionalValence
    public let overallEnergy: EmotionalEnergy
    public let elements: [SemanticElement]
    public let topics: [String]          // Top topics (normalized)
    public let emotions: [String: Double] // emotion -> intensity
    public let people: [String]          // People mentioned
    public let goals: [String]           // Goals identified
    public let fears: [String]           // Fears identified
    public let gratitude: [String]       // Gratitude items

    /// Count of elements by category
    public var elementsByCategory: [SemanticCategory: [SemanticElement]] {
        Dictionary(grouping: elements, by: { $0.category })
    }

    /// Top confidence elements
    public var topElements: [SemanticElement] {
        elements.sorted { $0.confidence > $1.confidence }.prefix(10).map { $0 }
    }
}

/// Metadata for storing SemanticExtraction as an Atom
public struct SemanticExtractionMetadata: Codable, Sendable {
    public let sourceUUID: String
    public let extractedAt: Date
    public let wordCount: Int
    public let sentenceCount: Int
    public let overallValence: String
    public let overallEnergy: String
    public let valenceScore: Double
    public let energyScore: Double
    public let topicCount: Int
    public let emotionCount: Int
    public let personCount: Int
    public let goalCount: Int
    public let fearCount: Int
    public let gratitudeCount: Int
    public let usedCloudModel: Bool

    public init(from extraction: SemanticExtraction, usedCloudModel: Bool = false) {
        self.sourceUUID = extraction.sourceUUID
        self.extractedAt = extraction.extractedAt
        self.wordCount = extraction.wordCount
        self.sentenceCount = extraction.sentenceCount
        self.overallValence = extraction.overallValence.rawValue
        self.overallEnergy = extraction.overallEnergy.rawValue
        self.valenceScore = extraction.overallValence.numericValue
        self.energyScore = extraction.overallEnergy.numericValue
        self.topicCount = extraction.topics.count
        self.emotionCount = extraction.emotions.count
        self.personCount = extraction.people.count
        self.goalCount = extraction.goals.count
        self.fearCount = extraction.fears.count
        self.gratitudeCount = extraction.gratitude.count
        self.usedCloudModel = usedCloudModel
    }
}

/// Structured data for SemanticExtraction atom
public struct SemanticExtractionStructured: Codable, Sendable {
    public let topics: [String]
    public let emotions: [String: Double]
    public let people: [String]
    public let goals: [String]
    public let fears: [String]
    public let gratitude: [String]
    public let elements: [SemanticElement]
}

// MARK: - Semantic Analysis Engine

/// Engine for extracting semantic content from journal entries
public actor SemanticAnalysisEngine {

    // MARK: - Dependencies

    private let database: any DatabaseWriter
    private let tagger: NLTagger
    private let sentimentClassifier: NLModel?
    private let tokenizer: NLTokenizer

    // MARK: - Keyword Lists

    private let goalKeywords = ["want to", "need to", "going to", "planning to", "hope to", "my goal", "aim to", "intend to", "working toward", "striving for"]
    private let fearKeywords = ["worried about", "afraid of", "scared of", "anxious about", "concern about", "fear that", "nervous about", "dread", "terrified"]
    private let gratitudeKeywords = ["grateful for", "thankful for", "appreciate", "blessed", "fortunate", "lucky to", "appreciating"]
    private let accomplishmentKeywords = ["accomplished", "achieved", "completed", "finished", "succeeded", "managed to", "proud of", "did it"]
    private let challengeKeywords = ["struggling with", "difficult", "hard to", "challenge", "obstacle", "problem", "issue", "stuck on"]

    private let emotionKeywords: [String: String] = [
        // Positive emotions
        "happy": "joy", "excited": "excitement", "grateful": "gratitude", "peaceful": "peace",
        "confident": "confidence", "hopeful": "hope", "proud": "pride", "love": "love",
        "content": "contentment", "inspired": "inspiration", "motivated": "motivation",
        // Negative emotions
        "sad": "sadness", "angry": "anger", "frustrated": "frustration", "anxious": "anxiety",
        "stressed": "stress", "tired": "fatigue", "overwhelmed": "overwhelm", "disappointed": "disappointment",
        "lonely": "loneliness", "bored": "boredom", "confused": "confusion", "worried": "worry"
    ]

    // MARK: - Initialization

    public init(database: (any DatabaseWriter)? = nil) async {
        // Get database from main actor if not provided
        if let db = database {
            self.database = db
        } else {
            self.database = await MainActor.run {
                CosmoDatabase.shared.dbQueue! as any DatabaseWriter
            }
        }
        self.tagger = NLTagger(tagSchemes: [.tokenType, .lexicalClass, .nameType, .sentimentScore])
        self.tokenizer = NLTokenizer(unit: .sentence)

        // Sentiment analysis will use NLTagger's built-in sentiment support
        self.sentimentClassifier = nil
    }

    // MARK: - Main Extraction

    /// Extract semantic content from a journal entry
    public func extractSemantics(from journalEntry: Atom) async throws -> SemanticExtraction {
        guard journalEntry.type == .journalEntry else {
            throw SemanticAnalysisError.invalidAtomType
        }

        guard let text = journalEntry.body, !text.isEmpty else {
            throw SemanticAnalysisError.emptyContent
        }

        // Basic text analysis
        let wordCount = text.split(separator: " ").count
        let sentenceCount = countSentences(in: text)

        // Sentiment analysis
        let (valence, energy) = analyzeSentiment(text)

        // Extract various semantic elements
        var elements: [SemanticElement] = []

        // Extract named entities (people)
        let people = extractNamedEntities(from: text, type: .personalName)
        for person in people {
            elements.append(SemanticElement(
                category: .person,
                content: person,
                confidence: 0.8
            ))
        }

        // Extract topics using NLP
        let topics = extractTopics(from: text)

        // Extract emotions
        let emotions = extractEmotions(from: text)
        for (emotion, intensity) in emotions {
            elements.append(SemanticElement(
                category: .emotion,
                content: emotion,
                confidence: intensity,
                sentiment: valence.numericValue
            ))
        }

        // Extract goals
        let goals = extractByKeywords(from: text, keywords: goalKeywords, category: .goal)
        elements.append(contentsOf: goals)

        // Extract fears
        let fears = extractByKeywords(from: text, keywords: fearKeywords, category: .fear)
        elements.append(contentsOf: fears)

        // Extract gratitude
        let gratitude = extractByKeywords(from: text, keywords: gratitudeKeywords, category: .gratitude)
        elements.append(contentsOf: gratitude)

        // Extract accomplishments
        let accomplishments = extractByKeywords(from: text, keywords: accomplishmentKeywords, category: .accomplishment)
        elements.append(contentsOf: accomplishments)

        // Extract challenges
        let challenges = extractByKeywords(from: text, keywords: challengeKeywords, category: .challenge)
        elements.append(contentsOf: challenges)

        return SemanticExtraction(
            sourceUUID: journalEntry.uuid,
            extractedAt: Date(),
            wordCount: wordCount,
            sentenceCount: sentenceCount,
            overallValence: valence,
            overallEnergy: energy,
            elements: elements,
            topics: topics,
            emotions: emotions,
            people: people,
            goals: goals.map { $0.content },
            fears: fears.map { $0.content },
            gratitude: gratitude.map { $0.content }
        )
    }

    /// Process all unprocessed journal entries
    public func processUnprocessedJournals() async throws -> Int {
        let unprocessedJournals = try await database.read { db in
            // Find journal entries that don't have a semantic extraction
            let processedUUIDs = try Atom
                .filter(Column("type") == AtomType.semanticExtraction.rawValue)
                .filter(Column("is_deleted") == false)
                .select(sql: "json_extract(metadata, '$.sourceUUID')")
                .fetchAll(db)
                .compactMap { (row: Row) -> String? in
                    row[0] as? String
                }

            var query = Atom
                .filter(Column("type") == AtomType.journalEntry.rawValue)
                .filter(Column("is_deleted") == false)

            if !processedUUIDs.isEmpty {
                query = query.filter(!processedUUIDs.contains(Column("uuid")))
            }

            return try query.fetchAll(db)
        }

        var processed = 0
        for journal in unprocessedJournals {
            do {
                let extraction = try await extractSemantics(from: journal)
                try await saveExtraction(extraction)
                processed += 1
            } catch {
                // Log but continue with other entries
                print("Failed to extract semantics from journal \(journal.uuid): \(error)")
            }
        }

        return processed
    }

    // MARK: - NLP Helpers

    private func countSentences(in text: String) -> Int {
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            count += 1
            return true
        }
        return count
    }

    private func analyzeSentiment(_ text: String) -> (EmotionalValence, EmotionalEnergy) {
        tagger.string = text

        var totalSentiment = 0.0
        var count = 0

        tagger.enumerateTags(
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

        let avgSentiment = count > 0 ? totalSentiment / Double(count) : 0
        let valence = EmotionalValence.from(score: avgSentiment)

        // Estimate energy from text features
        let exclamationCount = text.filter { $0 == "!" }.count
        let capsRatio = Double(text.filter { $0.isUppercase }.count) / Double(max(text.count, 1))
        let wordCount = text.split(separator: " ").count

        var energyScore = 0.5
        energyScore += Double(exclamationCount) * 0.05
        energyScore += capsRatio * 0.2
        energyScore += min(Double(wordCount) / 500.0, 0.2)
        energyScore = min(max(energyScore, 0.1), 0.9)

        let energy: EmotionalEnergy
        switch energyScore {
        case ..<0.25: energy = .veryLow
        case ..<0.4: energy = .low
        case ..<0.6: energy = .moderate
        case ..<0.8: energy = .high
        default: energy = .veryHigh
        }

        return (valence, energy)
    }

    private func extractNamedEntities(from text: String, type: NLTag) -> [String] {
        tagger.string = text
        var entities: [String] = []

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitPunctuation, .omitWhitespace]
        ) { tag, range in
            if tag == type {
                let entity = String(text[range])
                if !entities.contains(entity) && entity.count > 1 {
                    entities.append(entity)
                }
            }
            return true
        }

        return entities
    }

    private func extractTopics(from text: String) -> [String] {
        tagger.string = text
        var nouns: [String: Int] = [:]

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitPunctuation, .omitWhitespace]
        ) { tag, range in
            if tag == .noun {
                let word = String(text[range]).lowercased()
                if word.count > 3 {  // Skip short words
                    nouns[word, default: 0] += 1
                }
            }
            return true
        }

        // Return top nouns as topics
        return nouns
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key }
    }

    private func extractEmotions(from text: String) -> [String: Double] {
        let lowercasedText = text.lowercased()
        var emotions: [String: Double] = [:]

        for (keyword, emotion) in emotionKeywords {
            if lowercasedText.contains(keyword) {
                // Count occurrences
                let count = lowercasedText.components(separatedBy: keyword).count - 1
                let intensity = min(Double(count) * 0.3 + 0.5, 1.0)
                emotions[emotion] = max(emotions[emotion] ?? 0, intensity)
            }
        }

        return emotions
    }

    private func extractByKeywords(
        from text: String,
        keywords: [String],
        category: SemanticCategory
    ) -> [SemanticElement] {
        let lowercasedText = text.lowercased()
        var elements: [SemanticElement] = []

        for keyword in keywords {
            if let range = lowercasedText.range(of: keyword) {
                // Extract the sentence containing the keyword
                let startIndex = text.index(range.lowerBound, offsetBy: -50, limitedBy: text.startIndex) ?? text.startIndex
                let endIndex = text.index(range.upperBound, offsetBy: 100, limitedBy: text.endIndex) ?? text.endIndex
                let context = String(text[startIndex..<endIndex])

                // Extract the content after the keyword
                let afterKeyword = text[range.upperBound...]
                let content = afterKeyword
                    .prefix(while: { !".!?".contains($0) })
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !content.isEmpty && content.count > 3 {
                    elements.append(SemanticElement(
                        category: category,
                        content: String(content),
                        confidence: 0.7,
                        context: context
                    ))
                }
            }
        }

        return elements
    }

    // MARK: - Persistence

    private func saveExtraction(_ extraction: SemanticExtraction) async throws {
        try await database.write { db in
            let metadata = SemanticExtractionMetadata(from: extraction)
            let structured = SemanticExtractionStructured(
                topics: extraction.topics,
                emotions: extraction.emotions,
                people: extraction.people,
                goals: extraction.goals,
                fears: extraction.fears,
                gratitude: extraction.gratitude,
                elements: extraction.elements
            )

            var atom = Atom.new(
                type: .semanticExtraction,
                title: "Semantic Extraction",
                body: "Extracted \(extraction.topics.count) topics, \(extraction.emotions.count) emotions from journal"
            )

            atom.metadata = try? String(data: JSONEncoder().encode(metadata), encoding: .utf8)
            atom.structured = try? String(data: JSONEncoder().encode(structured), encoding: .utf8)
            atom.links = try? String(data: JSONEncoder().encode([
                AtomLink.semanticSource(extraction.sourceUUID)
            ]), encoding: .utf8)

            try atom.insert(db)
        }
    }

    // MARK: - Query Methods

    /// Get semantic data for correlation with other metrics
    public func getSemanticMetrics(from startDate: Date, to endDate: Date) async throws -> [DailySemanticMetrics] {
        try await database.read { db in
            let extractions = try Atom
                .filter(Column("type") == AtomType.semanticExtraction.rawValue)
                .filter(Column("created_at") >= startDate.ISO8601Format())
                .filter(Column("created_at") < endDate.ISO8601Format())
                .filter(Column("is_deleted") == false)
                .fetchAll(db)

            var dailyMetrics: [String: DailySemanticMetrics] = [:]
            let calendar = Calendar.current
            let dateFormatter = ISO8601DateFormatter()

            for atom in extractions {
                guard let createdAtString = atom.createdAt as String?,
                      let createdAt = dateFormatter.date(from: createdAtString),
                      let metadata = atom.metadataValue(as: SemanticExtractionMetadata.self) else {
                    continue
                }

                let key = self.dateKey(createdAt)
                var metrics = dailyMetrics[key] ?? DailySemanticMetrics(date: calendar.startOfDay(for: createdAt))

                metrics.journalCount += 1
                metrics.totalWordCount += metadata.wordCount
                metrics.valenceSum += metadata.valenceScore
                metrics.energySum += metadata.energyScore
                metrics.topicCount += metadata.topicCount
                metrics.emotionCount += metadata.emotionCount
                metrics.goalCount += metadata.goalCount
                metrics.fearCount += metadata.fearCount
                metrics.gratitudeCount += metadata.gratitudeCount

                dailyMetrics[key] = metrics
            }

            return dailyMetrics.values.map { metrics in
                var finalized = metrics
                if metrics.journalCount > 0 {
                    finalized.avgValence = metrics.valenceSum / Double(metrics.journalCount)
                    finalized.avgEnergy = metrics.energySum / Double(metrics.journalCount)
                }
                return finalized
            }.sorted { $0.date < $1.date }
        }
    }

    /// Get aggregated topics over time for pattern analysis
    public func getTopicTrends(from startDate: Date, to endDate: Date) async throws -> [String: Int] {
        try await database.read { db in
            let extractions = try Atom
                .filter(Column("type") == AtomType.semanticExtraction.rawValue)
                .filter(Column("created_at") >= startDate.ISO8601Format())
                .filter(Column("created_at") < endDate.ISO8601Format())
                .filter(Column("is_deleted") == false)
                .fetchAll(db)

            var topicCounts: [String: Int] = [:]

            for atom in extractions {
                if let structured = atom.structuredData(as: SemanticExtractionStructured.self) {
                    for topic in structured.topics {
                        topicCounts[topic, default: 0] += 1
                    }
                }
            }

            return topicCounts
        }
    }

    nonisolated private func dateKey(_ date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year!)-\(components.month!)-\(components.day!)"
    }
}

// MARK: - Daily Semantic Metrics

/// Aggregated semantic metrics for a single day
public struct DailySemanticMetrics: Codable, Sendable {
    public let date: Date
    public var journalCount: Int = 0
    public var totalWordCount: Int = 0
    public var valenceSum: Double = 0
    public var energySum: Double = 0
    public var avgValence: Double = 0
    public var avgEnergy: Double = 0
    public var topicCount: Int = 0
    public var emotionCount: Int = 0
    public var goalCount: Int = 0
    public var fearCount: Int = 0
    public var gratitudeCount: Int = 0

    public init(date: Date) {
        self.date = date
    }
}

// MARK: - Errors

public enum SemanticAnalysisError: Error, LocalizedError {
    case invalidAtomType
    case emptyContent
    case processingFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .invalidAtomType:
            return "Semantic analysis requires a journal entry atom"
        case .emptyContent:
            return "Journal entry has no content to analyze"
        case .processingFailed(let error):
            return "Processing failed: \(error.localizedDescription)"
        }
    }
}
