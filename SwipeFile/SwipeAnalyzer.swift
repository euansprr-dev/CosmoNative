// CosmoOS/SwipeFile/SwipeAnalyzer.swift
// On-device content analysis engine for swipe files
// Uses Apple NaturalLanguage framework -- no network calls

import Foundation
import SwiftUI
import NaturalLanguage

@MainActor
final class SwipeAnalyzer: ObservableObject {
    static let shared = SwipeAnalyzer()

    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0

    private init() {}

    // MARK: - Main Pipeline

    /// Run fast local NLP analysis only (no network). Returns immediately.
    func analyze(atom: Atom) async -> SwipeAnalysis {
        isAnalyzing = true
        analysisProgress = 0

        let text = extractText(from: atom)
        let title = atom.title

        guard !text.isEmpty else {
            isAnalyzing = false
            return SwipeAnalysis(analysisVersion: 1, isFullyAnalyzed: false)
        }

        // Stage 1: Hook extraction
        analysisProgress = 0.15
        let hookResult = extractHook(from: text, title: title)

        // Stage 2: Hook scoring
        analysisProgress = 0.30
        let hookScore = scoreHook(hookText: hookResult.hookText, hookType: hookResult.hookType)

        // Stage 3: Sentiment analysis
        analysisProgress = 0.50
        let emotionalArc = analyzeSentiment(text: text)

        // Stage 4: Dominant emotion
        analysisProgress = 0.60
        let dominantEmotion = computeDominantEmotion(from: emotionalArc)

        // Stage 5: Overall sentiment
        let overallSentiment = computeOverallSentiment(from: emotionalArc)

        // Stage 6: Persuasion techniques
        analysisProgress = 0.75
        let persuasionTechniques = detectPersuasionTechniques(text: text)

        // Stage 7: Persuasion stack (type -> intensity map)
        let persuasionStack = Dictionary(
            uniqueKeysWithValues: persuasionTechniques.map { ($0.type.rawValue, $0.intensity) }
        )

        // Stage 8: Framework detection
        analysisProgress = 0.90
        let frameworkType = detectFramework(text: text, sentimentArc: emotionalArc)

        analysisProgress = 1.0
        isAnalyzing = false

        return SwipeAnalysis(
            hookText: hookResult.hookText,
            hookType: hookResult.hookType,
            hookScore: hookScore,
            hookWordCount: hookResult.hookText.split(separator: " ").count,
            frameworkType: frameworkType,
            sections: nil,
            structureComplexity: nil,
            dominantEmotion: dominantEmotion,
            emotionalArc: emotionalArc,
            sentimentScore: overallSentiment,
            persuasionTechniques: persuasionTechniques.isEmpty ? nil : persuasionTechniques,
            persuasionStack: persuasionStack.isEmpty ? nil : persuasionStack,
            analysisVersion: 1,
            analyzedAt: ISO8601DateFormatter().string(from: Date()),
            isFullyAnalyzed: true
        )
    }

    /// Full analysis pipeline: local NLP first (returned for progressive loading),
    /// then SwipeClassificationEngine for deep analysis + taxonomy classification.
    /// The callback fires when the deep/classified result is ready to merge.
    func analyzeWithClassification(
        atom: Atom,
        onLocalComplete: ((SwipeAnalysis) -> Void)? = nil
    ) async -> SwipeAnalysis {
        // Phase 1: Fast local NLP
        let localResult = await analyze(atom: atom)
        onLocalComplete?(localResult)

        // Phase 2: AI classification + deep analysis (single Claude call)
        let classifiedResult = await SwipeClassificationEngine.shared.classifyAndAnalyze(atom: atom)

        // Merge: classification results override/enrich local NLP
        let merged = SwipeClassificationEngine.shared.mergeClassification(classifiedResult, into: localResult)

        return merged
    }

    // MARK: - Text Extraction

    /// Extract analyzable text from an atom's body, title, or structured transcript
    private func extractText(from atom: Atom) -> String {
        // Try body first (contains transcript JSON for videos or raw text)
        if let body = atom.body, !body.isEmpty {
            // Check if body is a JSON transcript array and extract text
            if let transcriptText = extractTranscriptText(from: body) {
                return transcriptText
            }
            return body
        }

        // Try structured data for transcript
        if let structuredStr = atom.structured,
           let data = structuredStr.data(using: .utf8) {
            // Try ResearchRichContent transcript field
            struct TranscriptExtractor: Codable {
                var transcript: String?
                var formattedTranscript: String?
                var description: String?
            }
            if let extracted = try? JSONDecoder().decode(TranscriptExtractor.self, from: data) {
                if let transcript = extracted.formattedTranscript ?? extracted.transcript, !transcript.isEmpty {
                    return transcript
                }
                if let desc = extracted.description, !desc.isEmpty {
                    return desc
                }
            }
        }

        // Fall back to title
        return atom.title ?? ""
    }

    /// Try to parse body as a JSON transcript array and join segment texts
    private func extractTranscriptText(from body: String) -> String? {
        guard let data = body.data(using: .utf8) else { return nil }

        // TranscriptSegment array format: [{"text": "...", "start": 0, ...}, ...]
        struct SegmentText: Codable {
            var text: String?
        }

        if let segments = try? JSONDecoder().decode([SegmentText].self, from: data) {
            let joined = segments.compactMap(\.text).joined(separator: " ")
            return joined.isEmpty ? nil : joined
        }

        return nil
    }

    // MARK: - Hook Extraction

    /// Extract the hook text, classify its type, and estimate confidence
    func extractHook(from text: String, title: String?) -> (hookText: String, hookType: SwipeHookType, confidence: Double) {
        // Prefer title if available and non-trivial
        let hookText: String
        if let title = title, !title.isEmpty, title.count > 3 {
            hookText = title
        } else {
            // Use the first sentence of the body
            hookText = firstSentence(of: text)
        }

        let lower = hookText.lowercased()
        var bestType: SwipeHookType = .boldClaim
        var bestConfidence: Double = 0.2

        // Classification with weighted pattern matching
        let classifications: [(SwipeHookType, [String], Double)] = [
            (.curiosityGap, ["how", "why", "what happens", "secret", "nobody", "hidden", "you won't believe", "what if"], 0.75),
            (.boldClaim, ["best", "worst", "most", "never", "always", "every", "greatest", "ultimate"], 0.65),
            (.question, [], 0.80), // special: ends with "?"
            (.contrast, ["vs", "versus", "compared to", "better than", "worse than"], 0.70),
            (.story, ["i ", "i've", "i'm", "my ", "when i", "i was", "i had"], 0.60),
            (.list, ["things", "ways", "tips", "reasons", "steps", "habits", "rules", "mistakes", "lessons"], 0.70),
            (.statistic, ["%", "$", "percent", "billion", "million", "data shows", "study found", "research shows"], 0.75),
            (.controversy, ["wrong", "lie", "truth", "nobody tells", "unpopular", "myth", "overrated"], 0.70),
            (.challenge, ["tried", "tested", "attempted", "for 30 days", "for 7 days", "experiment", "challenge"], 0.70),
            (.hiddenGem, ["sleeping on", "underrated", "nobody uses", "free", "overlooked", "hidden"], 0.65),
            (.contrarian, ["stop", "don't", "never do", "quit", "avoid", "you're doing it wrong"], 0.70),
            (.personal, ["my story", "i learned", "my experience", "vulnerability", "honest", "confess"], 0.60),
            (.transformation, ["changed", "transformed", "went from", "before and after", "before/after", "journey"], 0.70),
            (.howTo, ["how to", "step by step", "guide", "tutorial", "beginner", "complete guide"], 0.75),
        ]

        for (hookType, patterns, baseConfidence) in classifications {
            // Special case for question type
            if hookType == .question {
                if hookText.trimmingCharacters(in: .whitespaces).hasSuffix("?") {
                    if baseConfidence > bestConfidence {
                        bestType = hookType
                        bestConfidence = baseConfidence
                    }
                }
                continue
            }

            var matchCount = 0
            for pattern in patterns {
                if lower.contains(pattern) {
                    matchCount += 1
                }
            }

            if matchCount > 0 {
                // More matches increase confidence
                let confidence = min(baseConfidence + Double(matchCount - 1) * 0.05, 0.95)
                if confidence > bestConfidence {
                    bestType = hookType
                    bestConfidence = confidence
                }
            }
        }

        // Check for list pattern: starts with number
        if let first = hookText.trimmingCharacters(in: .whitespaces).first, first.isNumber {
            let listConfidence = 0.75
            if listConfidence > bestConfidence {
                bestType = .list
                bestConfidence = listConfidence
            }
        }

        // Check for numbers in text (boost statistic/boldClaim)
        let numberPattern = try? NSRegularExpression(pattern: "\\d+")
        let numberMatches = numberPattern?.numberOfMatches(in: hookText, range: NSRange(hookText.startIndex..., in: hookText)) ?? 0
        if numberMatches > 0 && bestType == .boldClaim {
            bestConfidence = max(bestConfidence, 0.60)
        }

        return (hookText, bestType, bestConfidence)
    }

    /// Extract the first sentence from text
    private func firstSentence(of text: String) -> String {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        if let range = tokenizer.tokens(for: text.startIndex..<text.endIndex).first {
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Fallback: take first 100 characters
        let prefix = String(text.prefix(100))
        return prefix
    }

    // MARK: - Sentiment Analysis

    /// Analyze sentiment per sentence using NLTagger, returning an emotional arc
    func analyzeSentiment(text: String) -> [EmotionDataPoint] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }

        guard !sentences.isEmpty else { return [] }

        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        var dataPoints: [EmotionDataPoint] = []

        for (index, sentence) in sentences.enumerated() {
            tagger.string = sentence

            let sentiment = tagger.tag(at: sentence.startIndex, unit: .paragraph, scheme: .sentimentScore).0
            let score = Double(sentiment?.rawValue ?? "0") ?? 0

            let position = sentences.count == 1 ? 0.5 : Double(index) / Double(sentences.count - 1)
            let intensity = min(abs(score), 1.0)

            let emotion: SwipeEmotion
            if score > 0.3 {
                emotion = .aspiration
            } else if score > 0.1 {
                emotion = .desire
            } else if score < -0.3 {
                emotion = .fear
            } else if score < -0.1 {
                emotion = .frustration
            } else {
                emotion = .curiosity
            }

            dataPoints.append(EmotionDataPoint(
                position: position,
                intensity: intensity,
                emotion: emotion
            ))
        }

        return dataPoints
    }

    // MARK: - Persuasion Detection

    /// Detect persuasion techniques via keyword pattern matching
    func detectPersuasionTechniques(text: String) -> [PersuasionTechnique] {
        let lower = text.lowercased()
        let wordCount = max(text.split(separator: " ").count, 1)

        let techniquePatterns: [(PersuasionType, [String])] = [
            (.socialProof, ["million", "thousands", "everyone", "popular", "trending", "followers", "people use", "users", "community", "viral"]),
            (.scarcity, ["limited", "only", "exclusive", "rare", "last chance", "few left", "running out", "scarce"]),
            (.urgency, ["now", "today", "hurry", "don't miss", "before", "deadline", "act fast", "immediately", "time is"]),
            (.authority, ["expert", "study", "research shows", "phd", "years of experience", "scientist", "professor", "according to", "proven"]),
            (.lossAversion, ["don't lose", "miss out", "before it's too late", "risk", "losing", "waste", "regret", "cost you"]),
            (.contrastEffect, ["vs", "compared to", "instead of", "better than", "worse", "unlike", "difference between"]),
            (.storytelling, ["i remember", "one day", "it all started", "years ago", "told me", "realized", "moment", "story"]),
            (.curiosityGap, ["secret", "revealed", "hidden", "what nobody", "you don't know", "surprising", "shocking", "unexpected"]),
            (.reciprocity, ["free", "bonus", "gift", "for you", "complimentary", "no cost", "included", "extra"]),
            (.anchoring, ["was $", "now $", "worth $", "valued at", "originally", "retail", "save $", "discount"]),
            (.framing, ["imagine", "picture this", "what if", "think about", "consider", "suppose", "envision"]),
            (.exclusivity, ["vip", "members only", "invitation", "select", "inner circle", "elite", "premium", "private"]),
        ]

        var techniques: [PersuasionTechnique] = []

        for (type, patterns) in techniquePatterns {
            var matchCount = 0
            var ranges: [SwipeTextRange] = []

            for pattern in patterns {
                var searchStart = lower.startIndex
                while let foundRange = lower.range(of: pattern, range: searchStart..<lower.endIndex) {
                    matchCount += 1
                    let start = lower.distance(from: lower.startIndex, to: foundRange.lowerBound)
                    let end = lower.distance(from: lower.startIndex, to: foundRange.upperBound)
                    ranges.append(SwipeTextRange(start: start, end: end))
                    searchStart = foundRange.upperBound
                }
            }

            if matchCount > 0 {
                // Intensity: scale by frequency relative to text length
                // More matches in shorter text = higher intensity
                let rawIntensity = Double(matchCount) / (Double(wordCount) / 50.0)
                let intensity = min(max(rawIntensity, 0.1), 1.0)

                techniques.append(PersuasionTechnique(
                    type: type,
                    intensity: intensity,
                    textRanges: ranges.isEmpty ? nil : ranges
                ))
            }
        }

        // Sort by intensity descending
        return techniques.sorted { $0.intensity > $1.intensity }
    }

    // MARK: - Framework Detection

    /// Detect content framework/structure from sentiment arc shape and structural markers
    func detectFramework(text: String, sentimentArc: [EmotionDataPoint]) -> SwipeFrameworkType? {
        let lower = text.lowercased()

        // Check for listicle: numbered items
        let listPattern = try? NSRegularExpression(pattern: "(?m)^\\s*\\d+[.\\)\\-]")
        let listMatches = listPattern?.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) ?? 0
        if listMatches >= 3 {
            return .listicle
        }

        // Check for tutorial: step-by-step markers
        let tutorialMarkers = ["step 1", "step 2", "first,", "second,", "third,", "next,", "finally,", "how to", "tutorial"]
        let tutorialHits = tutorialMarkers.filter { lower.contains($0) }.count
        if tutorialHits >= 3 {
            return .tutorial
        }

        // Check for before/after
        let baMarkers = ["before", "after", "used to", "now i", "transformation", "went from", "changed"]
        let baHits = baMarkers.filter { lower.contains($0) }.count
        if baHits >= 3 {
            return .beforeAfter
        }

        // Check for myth busting
        let mythMarkers = ["myth", "actually", "wrong", "truth is", "misconception", "debunk", "lie"]
        let mythHits = mythMarkers.filter { lower.contains($0) }.count
        if mythHits >= 2 {
            return .mythBusting
        }

        // Check for case study
        let caseMarkers = ["case study", "example", "deep dive", "analysis", "breakdown", "how they", "their strategy"]
        let caseHits = caseMarkers.filter { lower.contains($0) }.count
        if caseHits >= 2 {
            return .caseStudy
        }

        // Check for day-in-the-life
        let ditlMarkers = ["morning", "afternoon", "evening", "wake up", "routine", "day in", "daily"]
        let ditlHits = ditlMarkers.filter { lower.contains($0) }.count
        if ditlHits >= 3 {
            return .dayInLife
        }

        // Sentiment arc-based detection (need at least 4 data points)
        guard sentimentArc.count >= 4 else { return nil }

        let quarterSize = sentimentArc.count / 4
        let q1 = sentimentArc.prefix(quarterSize)
        let q2 = sentimentArc[quarterSize..<quarterSize * 2]
        let q3 = sentimentArc[quarterSize * 2..<quarterSize * 3]
        let q4 = sentimentArc.suffix(from: quarterSize * 3)

        let avgIntensity: (ArraySlice<EmotionDataPoint>) -> Double = { points in
            guard !points.isEmpty else { return 0 }
            return points.reduce(0.0) { $0 + $1.intensity } / Double(points.count)
        }

        let avgSentiment: (ArraySlice<EmotionDataPoint>) -> Double = { points in
            guard !points.isEmpty else { return 0 }
            return points.reduce(0.0) { sum, point in
                let sign: Double
                switch point.emotion {
                case .aspiration, .desire, .awe, .relief: sign = 1.0
                case .fear, .frustration, .urgency: sign = -1.0
                default: sign = 0.0
                }
                return sum + sign * point.intensity
            } / Double(points.count)
        }

        let s1 = avgSentiment(ArraySlice(q1))
        let s2 = avgSentiment(ArraySlice(q2))
        let s3 = avgSentiment(ArraySlice(q3))
        let s4 = avgSentiment(ArraySlice(q4))

        let i1 = avgIntensity(ArraySlice(q1))
        let i2 = avgIntensity(ArraySlice(q2))
        let i3 = avgIntensity(ArraySlice(q3))
        let i4 = avgIntensity(ArraySlice(q4))

        // PAS: Problem (negative) -> Agitate (more negative) -> Solve (positive)
        if s1 < 0 && s2 < s1 && s4 > 0.1 {
            return .pas
        }

        // AIDA: Attention (neutral/hook) -> Interest (rising) -> Desire (peak positive) -> Action (end call)
        if s1 >= -0.1 && s2 > s1 && s3 > s2 {
            // Check for action words at end
            let lastChunk = String(text.suffix(100)).lowercased()
            let actionWords = ["click", "subscribe", "follow", "buy", "sign up", "start", "try", "get", "join", "link"]
            let hasAction = actionWords.contains { lastChunk.contains($0) }
            if hasAction || s3 > 0.2 {
                return .aida
            }
        }

        // Escalation Arc: steadily increasing intensity
        if i1 < i2 && i2 < i3 && i3 < i4 {
            return .escalationArc
        }

        // Story Loop: tension build -> peak -> resolution
        if i2 > i1 && i3 >= i2 && i4 < i3 && s4 > s3 {
            return .storyLoop
        }

        // BAB: Before (state A) -> After (state B positive) -> Bridge (how to get there)
        if s1 < 0 && s2 > 0.1 && s3 > 0 {
            return .bab
        }

        return nil
    }

    // MARK: - Deep Analysis (Claude Sonnet 4.5)

    /// Claude-powered deep analysis — enriches NLP results with sections, richer emotional arc, and structural fingerprint
    func deepAnalyze(title: String, transcript: String) async -> DeepAnalysisResult? {
        // Truncate transcript to ~4000 words
        let words = transcript.split(separator: " ")
        let truncated = words.prefix(4000).joined(separator: " ")

        let prompt = """
        You are a content structure analyst. Analyze this video transcript and return a JSON object.

        Title: \(title)
        Transcript (first 4000 words): \(truncated)

        Return ONLY valid JSON with no markdown formatting:
        {
          "frameworkType": "aida" | "pas" | "bab" | "storyLoop" | "escalationArc" | "listicle" | "tutorial" | "caseStudy" | "mythBusting" | "beforeAfter" | "dayInLife" | "interview" | null,
          "frameworkDescription": "If no standard framework matches, describe the structure in one sentence. Otherwise null.",
          "sections": [
            {"label": "Hook", "purpose": "Creates curiosity gap about...", "sizePercent": 0.12, "emotion": "curiosity"},
            {"label": "Problem", "purpose": "Establishes the pain point...", "sizePercent": 0.25, "emotion": "frustration"}
          ],
          "emotionalArc": [
            {"position": 0.0, "emotion": "curiosity", "intensity": 0.8},
            {"position": 0.15, "emotion": "frustration", "intensity": 0.6}
          ],
          "persuasionTechniques": [
            {"type": "socialProof", "intensity": 0.7, "example": "Quote from transcript"}
          ],
          "hookScore": 8,
          "hookScoreReason": "Strong curiosity gap with specific number...",
          "keyInsight": "One sentence structural insight about what makes this content work",
          "sentimentQuartiles": [0.1, -0.3, 0.2, 0.6],
          "intensityQuartiles": [0.7, 0.5, 0.6, 0.9]
        }

        Valid emotions: curiosity, urgency, aspiration, fear, desire, awe, frustration, relief, belonging, exclusivity
        Valid persuasion types: socialProof, curiosityGap, contrastEffect, authority, scarcity, urgency, reciprocity, storytelling, lossAversion, exclusivity, anchoring, framing
        Provide at least 6 emotional arc data points. Provide at least 3 sections.
        """

        do {
            let response = try await ResearchService.shared.analyzeContent(prompt: prompt)

            // Strip markdown code fences if present
            var jsonStr = response.trimmingCharacters(in: .whitespacesAndNewlines)
            if jsonStr.hasPrefix("```") {
                // Remove opening fence (```json or ```)
                if let firstNewline = jsonStr.firstIndex(of: "\n") {
                    jsonStr = String(jsonStr[jsonStr.index(after: firstNewline)...])
                }
                // Remove closing fence
                if jsonStr.hasSuffix("```") {
                    jsonStr = String(jsonStr.dropLast(3))
                }
                jsonStr = jsonStr.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard let data = jsonStr.data(using: .utf8) else { return nil }
            let result = try JSONDecoder().decode(DeepAnalysisResult.self, from: data)
            return result
        } catch {
            print("SwipeAnalyzer: Deep analysis failed: \(error)")
            return nil
        }
    }

    /// Merge Claude deep analysis results into an existing SwipeAnalysis
    func mergeDeepAnalysis(_ deep: DeepAnalysisResult, into analysis: SwipeAnalysis) -> SwipeAnalysis {
        var merged = analysis

        // Override framework type if Claude detected one
        if let ft = deep.frameworkType, let framework = SwipeFrameworkType(rawValue: ft) {
            merged.frameworkType = framework
        }

        // Override sections — filter out any with empty/blank labels
        if let sections = deep.sections, !sections.isEmpty {
            merged.sections = sections.enumerated().compactMap { index, s in
                let emotion = SwipeEmotion(rawValue: s.emotion ?? "") ?? nil
                let label = s.label.trimmingCharacters(in: .whitespacesAndNewlines)
                let effectiveLabel = label.isEmpty ? s.purpose.prefix(30).trimmingCharacters(in: .whitespacesAndNewlines) : label
                guard !effectiveLabel.isEmpty else { return nil }
                return SwipeSection(
                    label: String(effectiveLabel),
                    startIndex: index,
                    endIndex: index + 1,
                    purpose: s.purpose,
                    emotion: emotion,
                    sizePercent: s.sizePercent
                )
            }
        }

        // Override emotional arc
        if let arc = deep.emotionalArc, !arc.isEmpty {
            merged.emotionalArc = arc.compactMap { point in
                guard let emotion = SwipeEmotion(rawValue: point.emotion) else { return nil }
                return EmotionDataPoint(
                    position: point.position,
                    intensity: point.intensity,
                    emotion: emotion
                )
            }
            // Recompute dominant emotion
            if let newArc = merged.emotionalArc, !newArc.isEmpty {
                var emotionIntensity: [SwipeEmotion: Double] = [:]
                for point in newArc {
                    emotionIntensity[point.emotion, default: 0] += point.intensity
                }
                merged.dominantEmotion = emotionIntensity.max(by: { $0.value < $1.value })?.key
            }
        }

        // Override persuasion techniques
        if let techniques = deep.persuasionTechniques, !techniques.isEmpty {
            merged.persuasionTechniques = techniques.compactMap { t in
                guard let type = PersuasionType(rawValue: t.type) else { return nil }
                return PersuasionTechnique(
                    type: type,
                    intensity: t.intensity,
                    example: t.example
                )
            }
            merged.persuasionStack = Dictionary(
                uniqueKeysWithValues: (merged.persuasionTechniques ?? []).map { ($0.type.rawValue, $0.intensity) }
            )
        }

        // Override hook score
        if let score = deep.hookScore {
            merged.hookScore = score
        }
        merged.hookScoreReason = deep.hookScoreReason
        merged.keyInsight = deep.keyInsight

        // Build fingerprint from Claude quartiles + merged data
        let sentimentQ = deep.sentimentQuartiles ?? [0, 0, 0, 0]
        let intensityQ = deep.intensityQuartiles ?? [0, 0, 0, 0]
        let techniqueMap = Dictionary(
            uniqueKeysWithValues: (merged.persuasionTechniques ?? []).map { ($0.type, $0.intensity) }
        )
        let techniqueWeights = PersuasionType.allCases.map { techniqueMap[$0] ?? 0 }

        merged.fingerprint = StructuralFingerprint(
            sentimentArc: sentimentQ,
            intensityArc: intensityQ,
            techniqueWeights: techniqueWeights,
            sectionCount: merged.sections?.count ?? 0,
            hookType: merged.hookType,
            frameworkType: merged.frameworkType
        )

        merged.analysisVersion = 2

        return merged
    }

    // MARK: - Hook Scoring

    /// Score a hook from 0-10 based on word count, specificity, emotion, and pattern quality
    func scoreHook(hookText: String, hookType: SwipeHookType) -> Double {
        let words = hookText.split(separator: " ")
        let wordCount = words.count

        // Word count factor: 6-12 is ideal
        let wordCountFactor: Double
        if wordCount >= 6 && wordCount <= 12 {
            wordCountFactor = 1.0
        } else if wordCount >= 4 && wordCount <= 16 {
            wordCountFactor = 0.7
        } else if wordCount >= 2 && wordCount <= 20 {
            wordCountFactor = 0.5
        } else {
            wordCountFactor = 0.3
        }

        // Specificity: numbers, names (capitalized words), concrete details
        let lower = hookText.lowercased()
        var specificityScore: Double = 0.3

        let numberPattern = try? NSRegularExpression(pattern: "\\d+")
        let numberCount = numberPattern?.numberOfMatches(in: hookText, range: NSRange(hookText.startIndex..., in: hookText)) ?? 0
        if numberCount > 0 {
            specificityScore += 0.3
        }

        // Capitalized words (potential names/brands) beyond first word
        let capitalizedWords = words.dropFirst().filter { word in
            guard let first = word.first else { return false }
            return first.isUppercase
        }.count
        if capitalizedWords > 0 {
            specificityScore += 0.2
        }

        specificityScore = min(specificityScore, 1.0)

        // Emotion strength
        let emotionWords = ["amazing", "incredible", "shocking", "secret", "powerful", "devastating", "life-changing",
                           "mind-blowing", "insane", "crazy", "unbelievable", "terrifying", "brilliant", "genius",
                           "revolutionary", "dangerous", "critical", "essential", "epic", "ultimate"]
        let emotionHits = emotionWords.filter { lower.contains($0) }.count
        let emotionScore = min(Double(emotionHits) * 0.3 + 0.2, 1.0)

        // Pattern quality: certain hook types inherently score higher for clean execution
        let patternBonus: Double
        switch hookType {
        case .curiosityGap: patternBonus = 0.9
        case .boldClaim: patternBonus = 0.8
        case .question: patternBonus = 0.7
        case .contrast: patternBonus = 0.85
        case .statistic: patternBonus = 0.85
        case .controversy: patternBonus = 0.8
        case .challenge: patternBonus = 0.75
        case .contrarian: patternBonus = 0.8
        case .transformation: patternBonus = 0.75
        case .story: patternBonus = 0.65
        case .list: patternBonus = 0.6
        case .howTo: patternBonus = 0.65
        case .hiddenGem: patternBonus = 0.7
        case .personal: patternBonus = 0.6
        }

        // Weighted combination
        let rawScore = (wordCountFactor * 2.5
                      + specificityScore * 2.5
                      + emotionScore * 2.5
                      + patternBonus * 2.5)

        // Clamp to 0-10
        return min(max(rawScore, 0), 10)
    }

    // MARK: - Helpers

    /// Determine the dominant emotion from an emotional arc
    private func computeDominantEmotion(from arc: [EmotionDataPoint]) -> SwipeEmotion? {
        guard !arc.isEmpty else { return nil }

        // Sum intensity by emotion type
        var emotionIntensity: [SwipeEmotion: Double] = [:]
        for point in arc {
            emotionIntensity[point.emotion, default: 0] += point.intensity
        }

        return emotionIntensity.max(by: { $0.value < $1.value })?.key
    }

    /// Compute overall sentiment score from arc
    private func computeOverallSentiment(from arc: [EmotionDataPoint]) -> Double? {
        guard !arc.isEmpty else { return nil }

        let total = arc.reduce(0.0) { sum, point in
            let sign: Double
            switch point.emotion {
            case .aspiration, .desire, .awe, .relief: sign = 1.0
            case .fear, .frustration, .urgency: sign = -1.0
            default: sign = 0.0
            }
            return sum + sign * point.intensity
        }

        return max(min(total / Double(arc.count), 1.0), -1.0)
    }
}

// MARK: - Deep Analysis Result (Claude JSON response)

struct DeepAnalysisResult: Codable {
    let frameworkType: String?
    let frameworkDescription: String?
    let sections: [DeepSection]?
    let emotionalArc: [DeepEmotionPoint]?
    let persuasionTechniques: [DeepPersuasionTechnique]?
    let hookScore: Double?
    let hookScoreReason: String?
    let keyInsight: String?
    let sentimentQuartiles: [Double]?
    let intensityQuartiles: [Double]?

    struct DeepSection: Codable {
        let label: String
        let purpose: String
        let sizePercent: Double?
        let emotion: String?
    }

    struct DeepEmotionPoint: Codable {
        let position: Double
        let emotion: String
        let intensity: Double
    }

    struct DeepPersuasionTechnique: Codable {
        let type: String
        let intensity: Double
        let example: String?
    }
}
