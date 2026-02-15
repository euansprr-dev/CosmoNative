// CosmoOS/AI/IdeaInsightEngine.swift
// Intelligence core for the IdeaForge system
// Runs the idea-to-swipe matching pipeline: quick insight, vector search,
// framework recommendation, format scoring, blueprint generation, and hook generation

import Foundation
import SwiftUI
import NaturalLanguage

// MARK: - IdeaInsightEngine

@MainActor
final class IdeaInsightEngine: ObservableObject {

    // MARK: - Singleton

    static let shared = IdeaInsightEngine()

    // MARK: - Published State

    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0

    // MARK: - Private Constants

    /// Minimum vector similarity for auto-linking a swipe to an idea
    private let autoLinkThreshold: Double = 0.7

    /// Maximum swipes to consider in the initial vector search
    private let maxVectorSearchResults = 20

    // MARK: - Init

    private init() {}

    // MARK: - 1. Quick Insight (On-Device, <100ms)

    /// Lightweight on-device analysis using NaturalLanguage framework.
    /// Returns topic keywords, suggested hook type, suggested framework, and sentiment.
    func quickInsight(ideaText: String) -> QuickInsightResult {
        guard !ideaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return QuickInsightResult()
        }

        // Topic extraction via NLTagger (lexical class)
        let topicKeywords = extractTopicKeywords(from: ideaText)

        // Hook type classification via keyword patterns
        let suggestedHookType = classifyHookType(from: ideaText)

        // Framework detection via structural heuristics
        let suggestedFramework = detectFrameworkHeuristic(from: ideaText)

        // Sentiment via NLTagger
        let sentimentScore = computeSentiment(from: ideaText)

        return QuickInsightResult(
            suggestedHookType: suggestedHookType,
            suggestedFramework: suggestedFramework,
            topicKeywords: topicKeywords,
            sentimentScore: sentimentScore
        )
    }

    // MARK: - 2. Find Matching Swipes (Local DB, ~200ms)

    /// Search the vector database for swipe files semantically similar to the idea text.
    /// Returns SwipeMatch array sorted by descending similarity.
    func findMatchingSwipes(ideaText: String, limit: Int = 5) async -> [SwipeMatch] {
        guard !ideaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        do {
            // Search the vector database for research entities (swipe files are research atoms)
            let vectorResults = try await VectorDatabase.shared.search(
                query: ideaText,
                limit: maxVectorSearchResults,
                entityTypeFilter: "research",
                minSimilarity: 0.3
            )

            // Filter to swipe file atoms only and load their analysis
            var matches: [SwipeMatch] = []

            for result in vectorResults {
                guard let entityUUID = result.entityUUID else { continue }

                // Load the atom to check if it is actually a swipe file
                guard let atom = try? await AtomRepository.shared.fetch(uuid: entityUUID),
                      atom.isSwipeFileAtom else {
                    continue
                }

                let analysis = atom.swipeAnalysis
                let meta = atom.metadataValue(as: ResearchMetadata.self)

                let match = SwipeMatch(
                    swipeAtomUUID: atom.uuid,
                    title: atom.title ?? "Untitled Swipe",
                    similarityScore: Double(result.similarity),
                    matchReason: buildMatchReason(similarity: Double(result.similarity), analysis: analysis),
                    hookType: analysis?.hookType,
                    frameworkType: analysis?.frameworkType,
                    hookText: analysis?.hookText ?? meta?.hook,
                    platform: meta?.contentSource
                )

                matches.append(match)

                if matches.count >= limit {
                    break
                }
            }

            // Sort by similarity descending
            return matches.sorted { $0.similarityScore > $1.similarityScore }

        } catch {
            print("IdeaInsightEngine: Vector search failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - 3. Recommend Frameworks

    /// Recommend content frameworks based on matching swipe analysis and optional format target.
    /// Tallies framework usage across matching swipes and returns top 3 recommendations.
    func recommendFrameworks(
        ideaText: String,
        matchingSwipes: [SwipeMatch],
        targetFormat: ContentFormat?
    ) -> [FrameworkRecommendation] {
        // Tally framework occurrences weighted by similarity score
        var frameworkScores: [SwipeFrameworkType: (score: Double, examples: [String])] = [:]

        for swipe in matchingSwipes {
            guard let framework = swipe.frameworkType else { continue }

            let existing = frameworkScores[framework] ?? (score: 0, examples: [])
            let updatedExamples = existing.examples + [swipe.swipeAtomUUID]
            frameworkScores[framework] = (
                score: existing.score + swipe.similarityScore,
                examples: updatedExamples
            )
        }

        // Apply format affinity boosts
        if let format = targetFormat {
            let affinityMap = frameworkFormatAffinity(format: format)
            for (framework, boost) in affinityMap {
                let existing = frameworkScores[framework] ?? (score: 0, examples: [])
                frameworkScores[framework] = (
                    score: existing.score + boost,
                    examples: existing.examples
                )
            }
        }

        // Heuristic boost from idea text itself
        if let heuristicFramework = detectFrameworkHeuristic(from: ideaText) {
            let existing = frameworkScores[heuristicFramework] ?? (score: 0, examples: [])
            frameworkScores[heuristicFramework] = (
                score: existing.score + 0.3,
                examples: existing.examples
            )
        }

        // Normalize and sort
        let maxScore = frameworkScores.values.map(\.score).max() ?? 1.0
        let normalizer = maxScore > 0 ? maxScore : 1.0

        let sorted = frameworkScores
            .sorted { $0.value.score > $1.value.score }
            .prefix(3)

        return sorted.map { framework, data in
            let confidence = min(data.score / normalizer, 1.0)
            let rationale = buildFrameworkRationale(
                framework: framework,
                matchCount: data.examples.count,
                totalSwipes: matchingSwipes.count,
                targetFormat: targetFormat
            )
            let reasoning = buildFrameworkReasoning(
                framework: framework,
                matchingSwipes: matchingSwipes,
                exampleUUIDs: data.examples,
                confidence: confidence,
                targetFormat: targetFormat
            )

            return FrameworkRecommendation(
                framework: framework,
                confidence: confidence,
                rationale: rationale,
                exampleSwipeUUIDs: data.examples.isEmpty ? nil : Array(data.examples.prefix(3)),
                reasoning: reasoning
            )
        }
    }

    // MARK: - 4. Score Formats

    /// Score content formats based on idea complexity, client preferences, and matching swipe distribution.
    /// Returns a dictionary of ContentFormat rawValue to 0-1 score.
    func scoreFormats(
        ideaText: String,
        matchingSwipes: [SwipeMatch],
        clientProfile: Atom?
    ) -> [String: Double] {
        var scores: [String: Double] = [:]

        // Initialize all formats with a baseline
        for format in ContentFormat.allCases {
            scores[format.rawValue] = 0.1
        }

        // Factor 1: Idea text complexity (word count heuristic)
        let wordCount = ideaText.split(separator: " ").count
        let complexityScores = scoreFormatsForComplexity(wordCount: wordCount)
        for (format, score) in complexityScores {
            scores[format, default: 0] += score * 0.35
        }

        // Factor 2: Matching swipe platform distribution
        let platformScores = scoreFormatsForSwipePlatforms(matchingSwipes: matchingSwipes)
        for (format, score) in platformScores {
            scores[format, default: 0] += score * 0.35
        }

        // Factor 3: Client preferences (if available)
        if let clientAtom = clientProfile,
           let clientMeta = clientAtom.metadataValue(as: ClientMetadata.self) {
            if let preferredFormats = clientMeta.preferredFormats {
                for formatRaw in preferredFormats {
                    scores[formatRaw, default: 0] += 0.3
                }
            }
        }

        // Normalize to 0-1
        let maxScore = scores.values.max() ?? 1.0
        if maxScore > 0 {
            for key in scores.keys {
                scores[key] = (scores[key] ?? 0) / maxScore
            }
        }

        return scores
    }

    // MARK: - 4b. Format Data Sources

    /// Generate human-readable data source descriptions for each format score.
    func buildFormatDataSources(
        ideaText: String,
        matchingSwipes: [SwipeMatch]
    ) -> [String: String] {
        var sources: [String: String] = [:]
        let wordCount = ideaText.split(separator: " ").count
        let swipeCount = matchingSwipes.count

        for format in ContentFormat.allCases {
            var parts: [String] = []

            // Count swipes from matching platforms for this format
            let relevantSwipeCount = matchingSwipes.filter { swipe in
                guard let platform = swipe.platform?.lowercased() else { return false }
                switch format {
                case .reel, .voiceoverReel, .oneSliderReel, .multiSliderReel, .twoStepCTA:
                    return ["instagram", "instagramreel", "tiktok"].contains(platform)
                case .carousel: return ["instagram", "instagramcarousel"].contains(platform)
                case .thread: return ["xpost", "twitter", "threads"].contains(platform)
                case .tweet, .post: return ["xpost", "twitter"].contains(platform)
                case .youtube: return platform == "youtube"
                case .longForm: return ["website", "youtube"].contains(platform)
                case .newsletter: return platform == "newsletter"
                }
            }.count

            if relevantSwipeCount > 0 {
                parts.append("based on \(relevantSwipeCount) matching swipe\(relevantSwipeCount == 1 ? "" : "s")")
            }

            if wordCount < 30 {
                parts.append("idea complexity: short")
            } else if wordCount < 80 {
                parts.append("idea complexity: medium")
            } else {
                parts.append("idea complexity: detailed")
            }

            if swipeCount == 0 && relevantSwipeCount == 0 {
                parts.append("no matching swipes yet")
            }

            sources[format.rawValue] = parts.joined(separator: " | ")
        }

        return sources
    }

    // MARK: - 5. Generate Blueprint (Claude API)

    /// Generate a production-ready content blueprint using Claude via ResearchService.
    /// Combines the idea text, selected framework, format constraints, and reference swipes.
    func generateBlueprint(
        ideaText: String,
        framework: SwipeFrameworkType,
        format: ContentFormat,
        referenceSwipes: [SwipeMatch]
    ) async -> ContentBlueprint? {
        // Build reference context from swipes
        var swipeContext = ""
        for (index, swipe) in referenceSwipes.prefix(3).enumerated() {
            swipeContext += """
            Reference \(index + 1): "\(swipe.title)"
              Hook type: \(swipe.hookType?.displayName ?? "Unknown")
              Framework: \(swipe.frameworkType?.displayName ?? "Unknown")
              Hook: \(swipe.hookText ?? "N/A")

            """
        }

        let sectionRange = format.idealSectionCount
        let prompt = """
        You are a content strategist. Create a content blueprint for this idea.

        Idea: \(ideaText)
        Framework: \(framework.displayName) (\(framework.description))
        Format: \(format.displayName)
        Target sections: \(sectionRange.lowerBound)-\(sectionRange.upperBound)

        \(swipeContext.isEmpty ? "" : "Reference swipe files for inspiration:\n\(swipeContext)")

        Return ONLY valid JSON with no markdown formatting:
        {
          "sections": [
            {
              "label": "Section name",
              "purpose": "What this section achieves",
              "suggestedContent": "Draft content or detailed guidance",
              "targetWordCount": 100,
              "emotion": "curiosity"
            }
          ],
          "estimatedWordCount": 800,
          "suggestedHook": "Opening line suggestion",
          "suggestedCTA": "Call to action suggestion"
        }

        Valid emotions: curiosity, urgency, aspiration, fear, desire, awe, frustration, relief, belonging, exclusivity
        """

        do {
            let response = try await ResearchService.shared.analyzeContent(prompt: prompt)

            // Strip markdown code fences if present
            let cleaned = stripCodeFences(from: response)

            guard let data = cleaned.data(using: .utf8) else {
                print("IdeaInsightEngine: Blueprint response not valid UTF-8")
                return nil
            }

            let parsed = try JSONDecoder().decode(BlueprintResponse.self, from: data)

            let sections = parsed.sections.enumerated().map { index, section in
                BlueprintSection(
                    label: section.label,
                    purpose: section.purpose,
                    suggestedContent: section.suggestedContent,
                    referenceSwipeUUID: referenceSwipes.indices.contains(index)
                        ? referenceSwipes[index].swipeAtomUUID : nil,
                    targetWordCount: section.targetWordCount,
                    emotion: section.emotion,
                    sortOrder: index
                )
            }

            return ContentBlueprint(
                format: format.rawValue,
                framework: framework.rawValue,
                sections: sections,
                estimatedWordCount: parsed.estimatedWordCount,
                suggestedHook: parsed.suggestedHook,
                suggestedCTA: parsed.suggestedCTA
            )
        } catch {
            print("IdeaInsightEngine: Blueprint generation failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - 6. Generate Hooks (Claude API)

    /// Generate hook suggestions for an idea using Claude, informed by matching swipe hooks.
    /// Returns 5 hook variants with classified hook types.
    func generateHooks(
        ideaText: String,
        matchingSwipes: [SwipeMatch],
        topHookTypes: [SwipeHookType]
    ) async -> [HookSuggestion] {
        // Build example hooks from swipes
        var exampleHooks = ""
        for swipe in matchingSwipes.prefix(5) {
            if let hookText = swipe.hookText {
                let typeLabel = swipe.hookType?.displayName ?? "General"
                exampleHooks += "- [\(typeLabel)] \(hookText)\n"
            }
        }

        let hookTypeNames = topHookTypes.map(\.displayName).joined(separator: ", ")

        let prompt = """
        You are a viral content hook specialist. Generate 5 compelling hooks for this idea.

        Idea: \(ideaText)
        Preferred hook types: \(hookTypeNames.isEmpty ? "Any" : hookTypeNames)

        \(exampleHooks.isEmpty ? "" : "Example hooks from similar high-performing content:\n\(exampleHooks)")

        Return ONLY valid JSON with no markdown formatting:
        {
          "hooks": [
            {
              "hookText": "The actual hook text",
              "hookType": "curiosityGap"
            }
          ]
        }

        Valid hook types: curiosityGap, boldClaim, question, story, statistic, controversy, contrast, howTo, list, challenge, hiddenGem, contrarian, personal, transformation
        Generate exactly 5 hooks. Make them varied in type and approach.
        """

        do {
            let response = try await ResearchService.shared.analyzeContent(prompt: prompt)
            let cleaned = stripCodeFences(from: response)

            guard let data = cleaned.data(using: .utf8) else {
                print("IdeaInsightEngine: Hook response not valid UTF-8")
                return []
            }

            let parsed = try JSONDecoder().decode(HookGenerationResponse.self, from: data)

            return parsed.hooks.prefix(5).enumerated().map { index, hook in
                let hookType = SwipeHookType(rawValue: hook.hookType ?? "")
                let inspiredBy = matchingSwipes.indices.contains(index)
                    ? matchingSwipes[index].swipeAtomUUID : nil

                return HookSuggestion(
                    hookText: hook.hookText,
                    hookType: hookType,
                    inspiredBySwipeUUID: inspiredBy,
                    isSelected: false
                )
            }
        } catch {
            print("IdeaInsightEngine: Hook generation failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - 7. Find Ideas for Swipe (Auto-Link)

    /// Called when a new swipe file is saved. Searches for existing ideas that match
    /// the swipe content and auto-creates bidirectional links for high-similarity matches.
    func findIdeasForSwipe(swipeAtom: Atom) async {
        guard swipeAtom.isSwipeFileAtom else { return }

        let searchText = swipeAtom.title ?? swipeAtom.body ?? ""
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        do {
            // Search vector DB for idea entities
            let vectorResults = try await VectorDatabase.shared.search(
                query: searchText,
                limit: 10,
                entityTypeFilter: "idea",
                minSimilarity: Float(autoLinkThreshold)
            )

            for result in vectorResults {
                guard let ideaUUID = result.entityUUID,
                      Double(result.similarity) >= autoLinkThreshold else {
                    continue
                }

                // Load the idea atom
                guard var ideaAtom = try? await AtomRepository.shared.fetch(uuid: ideaUUID),
                      ideaAtom.type == .idea else {
                    continue
                }

                // Check if link already exists
                let existingLinks = ideaAtom.links(ofType: .ideaToSwipe)
                if existingLinks.contains(where: { $0.uuid == swipeAtom.uuid }) {
                    continue
                }

                // Create bidirectional links
                ideaAtom = ideaAtom.addingLink(.ideaToSwipe(swipeAtom.uuid))
                var updatedSwipe = swipeAtom
                updatedSwipe = updatedSwipe.addingLink(.swipeToIdea(ideaAtom.uuid))

                // Update matching swipe count in idea metadata
                let currentCount = ideaAtom.ideaMetadata?.matchingSwipeCount ?? 0
                ideaAtom = ideaAtom.withUpdatedIdeaMetadata { meta in
                    meta.matchingSwipeCount = currentCount + 1
                }

                // Persist both atoms
                try? await AtomRepository.shared.update(ideaAtom)
                try? await AtomRepository.shared.update(updatedSwipe)

                print("IdeaInsightEngine: Auto-linked idea '\(ideaAtom.title ?? "Untitled")' to swipe '\(swipeAtom.title ?? "Untitled")' (similarity: \(String(format: "%.2f", result.similarity)))")
            }
        } catch {
            print("IdeaInsightEngine: findIdeasForSwipe failed: \(error.localizedDescription)")
        }
    }

    // MARK: - 8. Quick Enrich

    /// Called after idea creation. Runs quickInsight on the idea text, updates
    /// atom metadata with suggested hook type and framework, and indexes the
    /// idea in the vector database for future matching.
    func quickEnrich(atom: Atom) async {
        guard atom.type == .idea else { return }

        let ideaText = atom.body ?? atom.title ?? ""
        guard !ideaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Run on-device quick insight
        let insight = quickInsight(ideaText: ideaText)

        // Update atom metadata
        var updated = atom.withUpdatedIdeaMetadata { meta in
            if let hookType = insight.suggestedHookType {
                meta.suggestedHookType = hookType.rawValue
            }
            if let framework = insight.suggestedFramework {
                meta.suggestedFramework = framework.rawValue
            }
        }

        do {
            updated = try await AtomRepository.shared.update(updated)
        } catch {
            print("IdeaInsightEngine: Failed to update atom metadata: \(error.localizedDescription)")
        }

        // Index in vector database for future swipe matching
        do {
            try await VectorDatabase.shared.index(
                text: ideaText,
                entityType: "idea",
                entityId: atom.id ?? 0,
                entityUUID: atom.uuid
            )
        } catch {
            print("IdeaInsightEngine: Failed to index idea in vector DB: \(error.localizedDescription)")
        }
    }

    // MARK: - 9. Full Analysis

    /// Run the complete analysis pipeline: quickInsight, findMatchingSwipes,
    /// recommendFrameworks, scoreFormats. Combines all results into IdeaInsight
    /// and persists to the atom's structured JSON.
    func fullAnalysis(atom: Atom) async -> IdeaInsight {
        guard atom.type == .idea else {
            return IdeaInsight(insightVersion: 1, isFullyAnalyzed: false)
        }

        isAnalyzing = true
        analysisProgress = 0

        let ideaText = atom.body ?? atom.title ?? ""

        // Stage 1: Quick insight (on-device)
        analysisProgress = 0.1
        let quick = quickInsight(ideaText: ideaText)

        // Stage 2: Find matching swipes (vector search)
        analysisProgress = 0.3
        let matchingSwipes = await findMatchingSwipes(ideaText: ideaText, limit: 5)

        // Stage 3: Recommend frameworks
        analysisProgress = 0.5
        let targetFormat = atom.ideaContentFormat
        let frameworks = recommendFrameworks(
            ideaText: ideaText,
            matchingSwipes: matchingSwipes,
            targetFormat: targetFormat
        )

        // Stage 4: Score formats
        analysisProgress = 0.7
        var clientAtom: Atom?
        if let clientUUID = atom.ideaClientUUID {
            clientAtom = try? await AtomRepository.shared.fetch(uuid: clientUUID)
        }
        let formatScores = scoreFormats(
            ideaText: ideaText,
            matchingSwipes: matchingSwipes,
            clientProfile: clientAtom
        )

        // Build format data sources
        let formatDataSources = buildFormatDataSources(
            ideaText: ideaText,
            matchingSwipes: matchingSwipes
        )

        // Determine recommended format
        let recommendedFormat = formatScores.max(by: { $0.value < $1.value })?.key

        // Build emotional arc suggestion from top matching swipe
        let suggestedArc: [EmotionDataPoint]?
        if let topSwipe = matchingSwipes.first,
           let topAtom = try? await AtomRepository.shared.fetch(uuid: topSwipe.swipeAtomUUID),
           let analysis = topAtom.swipeAnalysis {
            suggestedArc = analysis.emotionalArc
        } else {
            suggestedArc = nil
        }

        // Collect suggested persuasion techniques from matching swipes
        var persuasionSet = Set<String>()
        for swipe in matchingSwipes.prefix(3) {
            if let swipeAtom = try? await AtomRepository.shared.fetch(uuid: swipe.swipeAtomUUID),
               let analysis = swipeAtom.swipeAnalysis,
               let techniques = analysis.persuasionTechniques {
                for technique in techniques {
                    persuasionSet.insert(technique.type.rawValue)
                }
            }
        }

        analysisProgress = 0.9

        // Build IdeaInsight
        let insight = IdeaInsight(
            matchingSwipes: matchingSwipes.isEmpty ? nil : matchingSwipes,
            frameworkRecommendations: frameworks.isEmpty ? nil : frameworks,
            hookSuggestions: nil, // hooks are generated separately via generateHooks
            formatScores: formatScores.isEmpty ? nil : formatScores,
            formatDataSources: formatDataSources.isEmpty ? nil : formatDataSources,
            recommendedFormat: recommendedFormat,
            formatRationale: buildFormatRationale(recommendedFormat: recommendedFormat, formatScores: formatScores),
            blueprint: nil, // blueprint generated separately via generateBlueprint
            suggestedEmotionalArc: suggestedArc,
            suggestedPersuasionTechniques: persuasionSet.isEmpty ? nil : Array(persuasionSet),
            insightVersion: 1,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            isFullyAnalyzed: true
        )

        // Persist to atom's structured JSON and update metadata
        do {
            var updated = atom.withIdeaInsight(insight)
            updated = updated.withUpdatedIdeaMetadata { meta in
                meta.insightScore = computeInsightScore(insight: insight)
                meta.matchingSwipeCount = matchingSwipes.count
                meta.lastAnalyzedAt = ISO8601DateFormatter().string(from: Date())
                if let hookType = quick.suggestedHookType {
                    meta.suggestedHookType = hookType.rawValue
                }
                if let framework = quick.suggestedFramework {
                    meta.suggestedFramework = framework.rawValue
                }
            }
            try await AtomRepository.shared.update(updated)
        } catch {
            print("IdeaInsightEngine: Failed to save IdeaInsight: \(error.localizedDescription)")
        }

        analysisProgress = 1.0
        isAnalyzing = false

        return insight
    }

    // MARK: - NLP Helpers (On-Device)

    /// Extract topic keywords from text using NLTagger with lexical class scheme.
    /// Returns unique nouns and proper nouns as topic indicators.
    private func extractTopicKeywords(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        var keywords: [String] = []
        var seen = Set<String>()

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass
        ) { tag, tokenRange in
            guard let tag = tag else { return true }

            // Extract nouns and proper nouns as topic keywords
            if tag == .noun || tag == .personalName || tag == .placeName || tag == .organizationName {
                let word = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let lowered = word.lowercased()
                if word.count > 2, !seen.contains(lowered), !commonStopWords.contains(lowered) {
                    seen.insert(lowered)
                    keywords.append(word)
                }
            }
            return true
        }

        // Return up to 10 keywords
        return Array(keywords.prefix(10))
    }

    /// Classify the likely hook type of an idea using keyword pattern matching.
    /// Follows the same approach as SwipeAnalyzer.extractHook.
    private func classifyHookType(from text: String) -> SwipeHookType? {
        let lower = text.lowercased()

        // Question check
        if text.trimmingCharacters(in: .whitespaces).hasSuffix("?") {
            return .question
        }

        let classifications: [(SwipeHookType, [String], Double)] = [
            (.curiosityGap, ["secret", "hidden", "nobody", "you won't believe", "what if", "most people don't"], 0.80),
            (.howTo, ["how to", "step by step", "guide", "tutorial", "complete guide"], 0.75),
            (.list, ["things", "ways", "tips", "reasons", "steps", "habits", "rules", "mistakes", "lessons"], 0.70),
            (.boldClaim, ["best", "worst", "most", "never", "always", "every", "greatest", "ultimate"], 0.65),
            (.contrast, ["vs", "versus", "compared to", "better than", "worse than"], 0.70),
            (.statistic, ["%", "$", "percent", "billion", "million", "data shows", "study found"], 0.75),
            (.controversy, ["wrong", "lie", "truth", "nobody tells", "unpopular", "myth", "overrated"], 0.70),
            (.challenge, ["tried", "tested", "for 30 days", "experiment", "challenge"], 0.70),
            (.contrarian, ["stop", "don't", "never do", "quit", "avoid", "you're doing it wrong"], 0.70),
            (.story, ["i ", "i've", "i'm", "my ", "when i", "i was"], 0.55),
            (.transformation, ["changed", "transformed", "went from", "before and after", "journey"], 0.70),
            (.personal, ["my story", "i learned", "my experience", "honest", "confess"], 0.60),
            (.hiddenGem, ["sleeping on", "underrated", "nobody uses", "overlooked"], 0.65),
        ]

        var bestType: SwipeHookType?
        var bestScore: Double = 0

        for (hookType, patterns, baseConfidence) in classifications {
            var matchCount = 0
            for pattern in patterns {
                if lower.contains(pattern) {
                    matchCount += 1
                }
            }
            if matchCount > 0 {
                let confidence = min(baseConfidence + Double(matchCount - 1) * 0.05, 0.95)
                if confidence > bestScore {
                    bestType = hookType
                    bestScore = confidence
                }
            }
        }

        // Require a minimum confidence threshold
        return bestScore >= 0.55 ? bestType : nil
    }

    /// Detect a content framework from text using keyword/structural heuristics.
    private func detectFrameworkHeuristic(from text: String) -> SwipeFrameworkType? {
        let lower = text.lowercased()

        // Listicle: contains numbered items or list keywords
        let listMarkers = ["things", "ways", "tips", "reasons", "steps", "habits", "rules"]
        let listHits = listMarkers.filter { lower.contains($0) }.count
        if listHits >= 2 { return .listicle }

        // Starts with a number
        if let first = text.trimmingCharacters(in: .whitespaces).first, first.isNumber {
            return .listicle
        }

        // Tutorial
        let tutorialMarkers = ["how to", "step by step", "tutorial", "guide", "beginner"]
        let tutorialHits = tutorialMarkers.filter { lower.contains($0) }.count
        if tutorialHits >= 2 { return .tutorial }

        // Before/After
        let baMarkers = ["before", "after", "used to", "transformation", "went from", "changed"]
        let baHits = baMarkers.filter { lower.contains($0) }.count
        if baHits >= 2 { return .beforeAfter }

        // Myth busting
        let mythMarkers = ["myth", "actually", "wrong", "truth is", "misconception", "debunk"]
        let mythHits = mythMarkers.filter { lower.contains($0) }.count
        if mythHits >= 2 { return .mythBusting }

        // Case study
        let caseMarkers = ["case study", "deep dive", "analysis", "breakdown", "how they"]
        let caseHits = caseMarkers.filter { lower.contains($0) }.count
        if caseHits >= 1 { return .caseStudy }

        // PAS indicators
        let pasMarkers = ["problem", "pain", "struggle", "solution", "fix", "solve"]
        let pasHits = pasMarkers.filter { lower.contains($0) }.count
        if pasHits >= 2 { return .pas }

        // Story
        let storyMarkers = ["story", "journey", "experience", "i remember", "one day"]
        let storyHits = storyMarkers.filter { lower.contains($0) }.count
        if storyHits >= 2 { return .storyLoop }

        return nil
    }

    /// Compute overall sentiment score using NLTagger sentimentScore scheme.
    private func computeSentiment(from text: String) -> Double? {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text

        let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        guard let tag = tag else { return nil }
        return Double(tag.rawValue)
    }

    // MARK: - Scoring Helpers

    /// Compute format scores based on idea text complexity (word count).
    private func scoreFormatsForComplexity(wordCount: Int) -> [String: Double] {
        var scores: [String: Double] = [:]

        if wordCount < 30 {
            // Short idea: best for reels, posts, threads
            scores[ContentFormat.reel.rawValue] = 0.9
            scores[ContentFormat.post.rawValue] = 0.8
            scores[ContentFormat.thread.rawValue] = 0.7
            scores[ContentFormat.carousel.rawValue] = 0.5
            scores[ContentFormat.youtube.rawValue] = 0.3
            scores[ContentFormat.longForm.rawValue] = 0.2
            scores[ContentFormat.newsletter.rawValue] = 0.3
        } else if wordCount < 80 {
            // Medium idea: threads, carousels, posts work well
            scores[ContentFormat.thread.rawValue] = 0.9
            scores[ContentFormat.carousel.rawValue] = 0.85
            scores[ContentFormat.post.rawValue] = 0.7
            scores[ContentFormat.reel.rawValue] = 0.6
            scores[ContentFormat.newsletter.rawValue] = 0.6
            scores[ContentFormat.youtube.rawValue] = 0.5
            scores[ContentFormat.longForm.rawValue] = 0.4
        } else {
            // Long/complex idea: long form, youtube, newsletters
            scores[ContentFormat.longForm.rawValue] = 0.9
            scores[ContentFormat.youtube.rawValue] = 0.85
            scores[ContentFormat.newsletter.rawValue] = 0.8
            scores[ContentFormat.thread.rawValue] = 0.7
            scores[ContentFormat.carousel.rawValue] = 0.6
            scores[ContentFormat.post.rawValue] = 0.3
            scores[ContentFormat.reel.rawValue] = 0.2
        }

        return scores
    }

    /// Score formats based on matching swipe platform distribution.
    private func scoreFormatsForSwipePlatforms(matchingSwipes: [SwipeMatch]) -> [String: Double] {
        var scores: [String: Double] = [:]
        guard !matchingSwipes.isEmpty else { return scores }

        var platformCounts: [String: Int] = [:]
        for swipe in matchingSwipes {
            if let platform = swipe.platform {
                platformCounts[platform, default: 0] += 1
            }
        }

        let total = Double(matchingSwipes.count)

        for (platform, count) in platformCounts {
            let weight = Double(count) / total

            // Map platforms to favored formats
            switch platform.lowercased() {
            case "youtube":
                scores[ContentFormat.youtube.rawValue, default: 0] += weight
                scores[ContentFormat.longForm.rawValue, default: 0] += weight * 0.5
            case "instagram", "instagramreel":
                scores[ContentFormat.reel.rawValue, default: 0] += weight
                scores[ContentFormat.carousel.rawValue, default: 0] += weight * 0.7
            case "instagramcarousel":
                scores[ContentFormat.carousel.rawValue, default: 0] += weight
            case "xpost", "twitter":
                scores[ContentFormat.thread.rawValue, default: 0] += weight
                scores[ContentFormat.post.rawValue, default: 0] += weight * 0.6
            case "threads":
                scores[ContentFormat.thread.rawValue, default: 0] += weight
            case "tiktok":
                scores[ContentFormat.reel.rawValue, default: 0] += weight
            case "newsletter":
                scores[ContentFormat.newsletter.rawValue, default: 0] += weight
            case "website":
                scores[ContentFormat.longForm.rawValue, default: 0] += weight
            default:
                break
            }
        }

        return scores
    }

    /// Return framework-to-format affinity boosts.
    private func frameworkFormatAffinity(format: ContentFormat) -> [SwipeFrameworkType: Double] {
        switch format {
        case .thread:
            return [.listicle: 0.4, .escalationArc: 0.3, .aida: 0.2]
        case .reel, .voiceoverReel, .oneSliderReel, .multiSliderReel, .twoStepCTA:
            return [.pas: 0.4, .storyLoop: 0.3, .escalationArc: 0.3]
        case .carousel:
            return [.listicle: 0.5, .tutorial: 0.3, .beforeAfter: 0.3]
        case .tweet, .post:
            return [.pas: 0.3, .aida: 0.3, .bab: 0.2]
        case .longForm:
            return [.caseStudy: 0.4, .tutorial: 0.3, .storyLoop: 0.2]
        case .youtube:
            return [.escalationArc: 0.4, .storyLoop: 0.3, .tutorial: 0.3]
        case .newsletter:
            return [.aida: 0.3, .caseStudy: 0.3, .listicle: 0.2]
        }
    }

    /// Compute an overall insight score (0-1) from the analysis results.
    private func computeInsightScore(insight: IdeaInsight) -> Double {
        var score: Double = 0
        var factors: Double = 0

        // Matching swipes contribute up to 0.3
        if let swipes = insight.matchingSwipes, !swipes.isEmpty {
            let avgSimilarity = swipes.map(\.similarityScore).reduce(0, +) / Double(swipes.count)
            score += avgSimilarity * 0.3
            factors += 0.3
        }

        // Framework recommendations contribute up to 0.2
        if let frameworks = insight.frameworkRecommendations, !frameworks.isEmpty {
            let topConfidence = frameworks.first?.confidence ?? 0
            score += topConfidence * 0.2
            factors += 0.2
        }

        // Format scores contribute up to 0.2
        if let formatScores = insight.formatScores, !formatScores.isEmpty {
            let topFormatScore = formatScores.values.max() ?? 0
            score += topFormatScore * 0.2
            factors += 0.2
        }

        // Fully analyzed bonus
        if insight.isFullyAnalyzed {
            score += 0.3
            factors += 0.3
        }

        return factors > 0 ? min(score / factors, 1.0) : 0
    }

    // MARK: - Text Helpers

    /// Build a human-readable match reason from similarity score and swipe analysis.
    private func buildMatchReason(similarity: Double, analysis: SwipeAnalysis?) -> String {
        var reasons: [String] = []

        if similarity >= 0.8 {
            reasons.append("Strong semantic match")
        } else if similarity >= 0.6 {
            reasons.append("Good semantic match")
        } else {
            reasons.append("Related topic")
        }

        if let hookType = analysis?.hookType {
            reasons.append("\(hookType.displayName) hook")
        }

        if let framework = analysis?.frameworkType {
            reasons.append("\(framework.displayName) framework")
        }

        return reasons.joined(separator: " | ")
    }

    /// Build a rationale string for a framework recommendation.
    private func buildFrameworkRationale(
        framework: SwipeFrameworkType,
        matchCount: Int,
        totalSwipes: Int,
        targetFormat: ContentFormat?
    ) -> String {
        var parts: [String] = []

        if matchCount > 0 {
            parts.append("Used in \(matchCount) of \(totalSwipes) matching swipe\(totalSwipes == 1 ? "" : "s")")
        }

        parts.append(framework.description)

        if let format = targetFormat {
            parts.append("Compatible with \(format.displayName) format")
        }

        return parts.joined(separator: ". ")
    }

    /// Build an evidence-based reasoning string for a framework recommendation.
    private func buildFrameworkReasoning(
        framework: SwipeFrameworkType,
        matchingSwipes: [SwipeMatch],
        exampleUUIDs: [String],
        confidence: Double,
        targetFormat: ContentFormat?
    ) -> String {
        let swipesUsingFramework = matchingSwipes.filter { $0.frameworkType == framework }
        let swipeCount = swipesUsingFramework.count

        var parts: [String] = []

        if swipeCount > 0 {
            // Calculate average hook score-proxy from similarity
            let avgSimilarity = swipesUsingFramework.map(\.similarityScore).reduce(0, +) / Double(swipeCount)
            let hookTypes = swipesUsingFramework.compactMap(\.hookType).map(\.displayName)
            let uniqueHookTypes = Array(Set(hookTypes))

            parts.append("\(framework.displayName) recommended because your swipe library shows \(swipeCount) high-performing piece\(swipeCount == 1 ? "" : "s") using \(framework.description) with avg match score \(String(format: "%.1f", avgSimilarity * 10))")

            if !uniqueHookTypes.isEmpty {
                parts.append("common hooks: \(uniqueHookTypes.prefix(3).joined(separator: ", "))")
            }
        } else {
            parts.append("\(framework.displayName) suggested based on idea structure and content patterns")
        }

        if let format = targetFormat {
            parts.append("strong affinity with \(format.displayName) format")
        }

        return parts.joined(separator: ". ")
    }

    /// Build a rationale string for the recommended format.
    private func buildFormatRationale(recommendedFormat: String?, formatScores: [String: Double]) -> String? {
        guard let rawValue = recommendedFormat,
              let format = ContentFormat(rawValue: rawValue),
              let score = formatScores[rawValue] else {
            return nil
        }

        let confidenceLabel: String
        if score >= 0.8 {
            confidenceLabel = "Strongly recommended"
        } else if score >= 0.5 {
            confidenceLabel = "Good fit"
        } else {
            confidenceLabel = "Possible option"
        }

        return "\(confidenceLabel) based on idea complexity and swipe file analysis"
    }

    /// Strip markdown code fences from a response string.
    private func stripCodeFences(from response: String) -> String {
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

        return jsonStr
    }

    /// Common English stop words to filter from topic keywords
    private let commonStopWords: Set<String> = [
        "the", "and", "for", "are", "but", "not", "you", "all", "can",
        "had", "her", "was", "one", "our", "out", "has", "have", "been",
        "some", "them", "than", "its", "over", "such", "that", "this",
        "with", "will", "each", "make", "like", "from", "into", "just",
        "also", "more", "other", "could", "about", "which", "their",
        "would", "there", "what", "when", "how", "who", "get", "got",
        "very", "your", "they", "most", "these", "those", "then", "did",
        "does", "done", "way", "may", "well", "back", "much", "still",
    ]
}

// MARK: - JSON Response Types (Claude API parsing)

/// Response shape for blueprint generation
private struct BlueprintResponse: Codable {
    let sections: [BlueprintSectionResponse]
    let estimatedWordCount: Int?
    let suggestedHook: String?
    let suggestedCTA: String?
}

private struct BlueprintSectionResponse: Codable {
    let label: String
    let purpose: String
    let suggestedContent: String?
    let targetWordCount: Int?
    let emotion: String?
}

/// Response shape for hook generation
private struct HookGenerationResponse: Codable {
    let hooks: [HookResponse]
}

private struct HookResponse: Codable {
    let hookText: String
    let hookType: String?
}
