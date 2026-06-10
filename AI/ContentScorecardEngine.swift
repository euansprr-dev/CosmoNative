// CosmoOS/AI/ContentScorecardEngine.swift
// Content Scorecard evaluation engine — scores Hook, Copy, CTA, Voice Match,
// Structural Alignment, and Slide-by-Slide analysis using Opus via ResearchService.
// February 2026

import Foundation

// MARK: - Scorecard Data Models

struct ContentScorecard: Codable {
    var hookScore: ScorecardScore
    var copyScore: ScorecardScore
    var ctaScore: ScorecardScore
    var voiceMatch: VoiceMatchResult
    var structuralAlignment: StructuralAlignment
    var slideAnalysis: [SlideAnalysis]
    var originalityScore: OriginalityScore?  // Only computed when Layer 4 has content
    var overallConfidence: Int  // 0-100
    var timestamp: Date
}

struct OriginalityScore: Codable {
    let score: Double  // 0-10
    let criteria: [CriterionResult]
    let suggestions: [String]

    var colorCategory: String {
        if score > 7 { return "green" }
        if score >= 5 { return "yellow" }
        return "red"
    }
}

struct ScorecardScore: Codable {
    let score: Double  // 0-10
    let criteria: [CriterionResult]
    let suggestions: [String]

    var colorCategory: String {
        if score > 7 { return "green" }
        if score >= 5 { return "yellow" }
        return "red"
    }
}

struct CriterionResult: Codable, Identifiable {
    let id: UUID
    let name: String
    let score: Double  // 0-10
    let explanation: String

    init(name: String, score: Double, explanation: String) {
        self.id = UUID()
        self.name = name
        self.score = score
        self.explanation = explanation
    }
}

struct VoiceMatchResult: Codable {
    let percentage: Double  // 0-100
    let drifts: [VoiceDrift]
}

struct VoiceDrift: Codable, Identifiable {
    let id: UUID
    let lineNumber: Int
    let draftText: String
    let issue: String
    let suggestion: String

    init(lineNumber: Int, draftText: String, issue: String, suggestion: String) {
        self.id = UUID()
        self.lineNumber = lineNumber
        self.draftText = draftText
        self.issue = issue
        self.suggestion = suggestion
    }
}

struct StructuralAlignment: Codable {
    let draftBeats: [String]
    let recommendedBeats: [String]
    let alignmentScore: Double  // 0-100
    let suggestions: [String]
}

struct SlideAnalysis: Codable, Identifiable {
    let id: UUID
    let sectionIndex: Int
    let draftText: String
    let beatLabel: String
    let swipeComparison: String
    let suggestion: String

    init(sectionIndex: Int, draftText: String, beatLabel: String, swipeComparison: String, suggestion: String) {
        self.id = UUID()
        self.sectionIndex = sectionIndex
        self.draftText = draftText
        self.beatLabel = beatLabel
        self.swipeComparison = swipeComparison
        self.suggestion = suggestion
    }
}

// MARK: - Content Scorecard Engine

@MainActor
class ContentScorecardEngine: ObservableObject {
    @Published var isEvaluating: Bool = false
    @Published var evaluationProgress: String = ""

    /// Run full scorecard evaluation against the draft using Opus with mega-context.
    func evaluate(contentAtom: Atom, state: ContentFocusModeState) async throws -> ContentScorecard {
        isEvaluating = true
        evaluationProgress = "Assembling context..."
        defer {
            isEvaluating = false
            evaluationProgress = ""
        }

        // 1. Build mega-context via shared assembly (includes Layer 4 knowledge context)
        let context = await WritingContextAssembler.assembleCachedMegaContext(contentAtom: contentAtom)

        // 2. Check if Layer 4 knowledge context exists (for originality scoring)
        let contentMeta = contentAtom.metadataValue(as: ContentAtomMetadata.self)
        let knowledgeAssembler = KnowledgeContextAssembler()
        let knowledgeContext = await knowledgeAssembler.assembleKnowledgeContext(
            contentAtom: contentAtom,
            profileId: contentMeta?.clientProfileUUID
        )
        let hasKnowledgeContext = !knowledgeContext.connections.isEmpty

        // 3. Load Intelligence Model voice fingerprint for quantified checks
        //    Use format-specific fingerprint when available (reel or thread)
        evaluationProgress = "Evaluating draft..."
        var voiceFingerprint: IntelligenceVoiceFingerprint?
        if let clientUUID = contentMeta?.clientProfileUUID,
           let profileAtom = try? await AtomRepository.shared.fetch(uuid: clientUUID),
           let clientMeta = profileAtom.metadataValue(as: ClientProfileMetadata.self),
           let intModel = clientMeta.intelligenceModel {
            // Determine content format from source idea or platform
            var isReelFormat = false
            var isThreadFormat = false

            if let sourceIdeaUUID = contentMeta?.sourceIdeaUUID,
               let ideaAtom = try? await AtomRepository.shared.fetch(uuid: sourceIdeaUUID),
               let format = ideaAtom.ideaContentFormat {
                isReelFormat = (format == .reel)
                isThreadFormat = (format == .thread)
            } else if let platform = contentMeta?.platform {
                isReelFormat = (platform == .instagram || platform == .tiktok || platform == .youtube)
                isThreadFormat = (platform == .twitter)
            }

            if isReelFormat, let reelVF = intModel.reelVoiceFingerprint {
                voiceFingerprint = reelVF
            } else if isThreadFormat, let threadVF = intModel.threadVoiceFingerprint {
                voiceFingerprint = threadVF
            } else {
                voiceFingerprint = intModel.voiceFingerprint
            }
        }

        let draftText = state.draftContent
        guard !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScorecardError.emptyDraft
        }

        // 4. Load hard lesson rules for compliance evaluation
        let lessonPolicy = await LessonPolicyResolver.resolveForWritingEngine(
            clientUUID: contentMeta?.clientProfileUUID,
            intent: "draft"
        )

        // 5. Build connection names for originality evaluation
        let connectionNames = knowledgeContext.connections.map { $0.atom.title ?? "Untitled" }
        let userMessage = buildEvaluationPrompt(
            draftText: draftText,
            voiceFingerprint: voiceFingerprint,
            hasKnowledgeContext: hasKnowledgeContext,
            connectionNames: connectionNames,
            hardLessons: lessonPolicy.hardRules
        )

        let messages: [[String: Any]] = [
            ["role": "user", "content": userMessage]
        ]

        // 5. Call Opus via ResearchService with prompt caching
        let response = try await ResearchService.shared.generateWithCaching(
            systemBlocks: context.systemBlocks,
            messages: messages,
            model: context.modelTier.rawValue,
            maxTokens: 16384
        )

        // 6. Parse the JSON response into a ContentScorecard
        evaluationProgress = "Processing results..."
        var scorecard = parseScorecard(from: response, hasKnowledgeContext: hasKnowledgeContext)

        // 7. Apply calibrated weights from historical accuracy data
        let clientUUID = contentMeta?.clientProfileUUID.flatMap { UUID(uuidString: $0) }
        let weights = await loadCalibratedWeights(clientUUID: clientUUID)
        scorecard = applyCalibratedWeights(scorecard, weights: weights)

        return scorecard
    }

    // MARK: - Prompt Construction

    private func buildEvaluationPrompt(
        draftText: String,
        voiceFingerprint: IntelligenceVoiceFingerprint? = nil,
        hasKnowledgeContext: Bool = false,
        connectionNames: [String] = [],
        hardLessons: [InferredLesson] = []
    ) -> String {
        // Build quantified voice rules section if Intelligence Model exists
        var quantifiedVoiceRules = ""
        if let vf = voiceFingerprint {
            var rules: [String] = []
            rules.append("QUANTIFIED VOICE RULES (from Client Intelligence Model):")

            if vf.avgSentenceLength > 0 {
                let maxTarget = Int(vf.avgSentenceLength * 1.5)
                rules.append("- Target avg sentence length: \(Int(vf.avgSentenceLength)) words. Flag any sentence >\(maxTarget) words.")
            }
            if vf.maxSentenceLength > 0 {
                rules.append("- Hard max sentence length: \(vf.maxSentenceLength) words. Flag any sentence exceeding this.")
            }
            if !vf.readingLevel.isEmpty {
                rules.append("- Target reading level: \(vf.readingLevel). Flag if draft reads 2+ grade levels higher.")
            }
            if !vf.sentenceStarterDistribution.isEmpty {
                let starters = vf.sentenceStarterDistribution.sorted { $0.value > $1.value }
                    .prefix(5).map { "\($0.key): \(Int($0.value * 100))%" }
                    .joined(separator: ", ")
                rules.append("- Sentence starter distribution: \(starters). Flag major deviations (>15% drift).")
            }
            if !vf.blacklistedPhrases.isEmpty {
                rules.append("- BLACKLISTED phrases (must NEVER appear): \(vf.blacklistedPhrases.joined(separator: ", ")). Flag ANY occurrence.")
            }
            if !vf.signaturePhrases.isEmpty {
                rules.append("- Signature phrases: \(vf.signaturePhrases.joined(separator: ", ")). Flag if zero present — target 1-2 per post.")
            }
            if !vf.ctaPattern.isEmpty {
                rules.append("- CTA pattern: \"\(vf.ctaPattern)\". Flag if CTA doesn't match this pattern.")
            }
            if !vf.punctuationStyle.isEmpty {
                rules.append("- Punctuation style: \(vf.punctuationStyle). Flag deviations.")
            }

            quantifiedVoiceRules = rules.joined(separator: "\n") + "\n\n"
        }

        // Build hard lesson rules section for compliance checking
        var lessonRulesSection = ""
        if !hardLessons.isEmpty {
            var lessonLines = ["HARD WRITING RULES (learned from user's past edits — violations are critical):"]
            for (i, lesson) in hardLessons.prefix(10).enumerated() {
                if let optimized = lesson.optimizedInstruction, !optimized.isEmpty {
                    lessonLines.append("\(i + 1). \(optimized)")
                } else {
                    lessonLines.append("\(i + 1). \(lesson.rule)")
                }
            }
            lessonLines.append("")
            lessonLines.append("When evaluating Voice Match and Copy Score, flag any violation of these hard rules as a voice drift.")
            lessonRulesSection = lessonLines.joined(separator: "\n") + "\n\n"
        }

        return """
        You are a content scorecard evaluator. Analyze the following draft against the editing \
        checklist criteria from the methodology (Layer 1) and the client voice patterns (Layer 2), \
        compare structural alignment against the top swipe patterns (Layer 3)\(hasKnowledgeContext ? ", \\\nand evaluate intellectual originality against the knowledge frameworks (Layer 4)" : "").

        \(quantifiedVoiceRules)\(lessonRulesSection)=== FULL DRAFT ===
        \(draftText)
        === END DRAFT ===

        Evaluate the draft and return a JSON scorecard with this EXACT structure. Return ONLY the JSON, no other text.

        {
          "hookScore": {
            "score": 7.5,
            "criteria": [
              {"name": "Curiosity Gap", "score": 8.0, "explanation": "Creates a strong open loop..."},
              {"name": "Low Barrier", "score": 7.0, "explanation": "Accessible language..."},
              {"name": "Clear Promise (WIIFM)", "score": 8.0, "explanation": "Viewer knows what they gain..."},
              {"name": "Numbers/Power Words", "score": 6.5, "explanation": "Could use more specificity..."},
              {"name": "Large TAM", "score": 8.0, "explanation": "Broad appeal topic..."},
              {"name": "Emotional Trigger", "score": 7.0, "explanation": "Moderate emotional pull..."},
              {"name": "Short and Concise", "score": 7.5, "explanation": "Within ideal length..."}
            ],
            "suggestions": ["Add a specific number to the hook", "Increase emotional urgency"]
          },
          "copyScore": {
            "score": 7.0,
            "criteria": [
              {"name": "Tied to Business Model", "score": 7.0, "explanation": "..."},
              {"name": "I Could Do This Factor", "score": 7.5, "explanation": "..."},
              {"name": "No Filler", "score": 6.5, "explanation": "..."},
              {"name": "Targets Pains/Benefits", "score": 7.0, "explanation": "..."},
              {"name": "Authentic Voice", "score": 7.5, "explanation": "..."},
              {"name": "Delivers on Hook", "score": 7.0, "explanation": "..."},
              {"name": "Closes the Loop", "score": 7.0, "explanation": "..."},
              {"name": "Congruent Flow", "score": 7.0, "explanation": "..."}
            ],
            "suggestions": ["Remove filler in paragraph 3", "Strengthen the proof section"]
          },
          "ctaScore": {
            "score": 6.0,
            "criteria": [
              {"name": "Calls Out ICP", "score": 6.0, "explanation": "..."},
              {"name": "Answers WIIFM", "score": 6.5, "explanation": "..."},
              {"name": "Clear Outcome/Timeline", "score": 5.5, "explanation": "..."},
              {"name": "Clear Benefit", "score": 6.0, "explanation": "..."}
            ],
            "suggestions": ["Add a specific timeline", "Name the ideal customer profile"]
          },
          "voiceMatch": {
            "percentage": 78.0,
            "drifts": [
              {
                "lineNumber": 5,
                "draftText": "The exact text that drifts from voice",
                "issue": "Sentence is too formal compared to client's casual tone",
                "suggestion": "Rewrite as: More casual version here"
              }
            ]
          },
          "structuralAlignment": {
            "draftBeats": ["BoldClaim", "StepByStepProof", "SocialProofNumbers"],
            "recommendedBeats": ["BoldClaim", "PersonalFailure", "DiscoveryMoment", "StepByStepProof", "SocialProofNumbers", "UrgencyCTA"],
            "alignmentScore": 65.0,
            "suggestions": ["Add a PersonalFailure beat after the hook", "Add a DiscoveryMoment before the proof"]
          },
          "slideAnalysis": [
            {
              "sectionIndex": 0,
              "draftText": "First 50 chars of this section...",
              "beatLabel": "BoldClaim",
              "swipeComparison": "Top swipes use specific dollar amounts here — your draft uses vague 'significant income'",
              "suggestion": "Replace 'significant income' with a specific number like '$47K/month'"
            }
          ],
          \(hasKnowledgeContext ? """
          "originalityScore": {
                "score": 7.0,
                "criteria": [
                  {"name": "Framework Integration", "score": 7.5, "explanation": "Uses connection terminology in 3 sections..."},
                  {"name": "Unique Terminology", "score": 6.5, "explanation": "Incorporates concept names but could weave deeper..."},
                  {"name": "Avoids Generic Advice", "score": 7.0, "explanation": "Most sections offer framework-specific insights..."}
                ],
                "suggestions": ["Weave the process steps from connection #1 into the proof section", "Use the concept name as a branded term"]
              },
          """ : "")
          "overallConfidence": 72
        }

        SCORING INSTRUCTIONS:
        - Hook Score: Average of 7 criteria (Curiosity Gap, Low Barrier, Clear Promise/WIIFM, \
        Numbers/Power Words, Large TAM, Emotional Trigger, Short and Concise). Each 0-10.
        - Copy Score: Average of 8 criteria (Tied to Business Model, "I Could Do This" Factor, \
        No Filler, Targets Pains/Benefits, Authentic Voice, Delivers on Hook, Closes the Loop, \
        Congruent Flow). Each 0-10.
        - CTA Score: Average of 4 criteria (Calls Out ICP, Answers WIIFM, Clear Outcome/Timeline, \
        Clear Benefit). Each 0-10.
        - Voice Match: Compare draft sentence patterns, word choices, emotional range, reading level, \
        and stylistic quirks against the client's voice profile in Layer 2. If QUANTIFIED VOICE RULES \
        are provided above, use those exact metrics to measure deviations objectively. Return percentage 0-100.
        - Voice Drifts: Flag specific lines where the draft deviates from the client's established voice. \
        If quantified rules exist, flag every violation of sentence length, blacklisted phrases, \
        missing signature phrases, and reading level drift as individual drifts.
        - Structural Alignment: Extract the draft's beat sequence and compare against the top patterns \
        from Layer 3. Return alignment score 0-100.
        - Slide Analysis: For each identifiable section/slide in the draft, compare against how the \
        top swipes handle that beat position.
        - Overall Confidence: Your confidence in this evaluation 0-100.
        \(hasKnowledgeContext ? """
        - Originality Score: ONLY include this if Layer 4 (Knowledge Context) is present. Average of 3 criteria:
          1. "Framework Integration" — How well does the draft incorporate unique frameworks, processes, \
        and belief systems from the linked connections (\(connectionNames.joined(separator: ", ")))? 0-10.
          2. "Unique Terminology" — Does the draft use connection-specific terminology, concept names, \
        and branded terms rather than generic industry language? 0-10.
          3. "Avoids Generic Advice" — Does the content offer distinctively framework-informed insights \
        rather than advice anyone could give? Flag sections that read as generic. 0-10.
          Suggestions should reference specific connection content that could be better integrated.
        """ : "")

        If there is no client voice profile in Layer 2, set voiceMatch percentage to -1 and drifts to [].
        \(hasKnowledgeContext ? "" : "Do NOT include an \"originalityScore\" field.\n")Return ONLY valid JSON. No markdown fencing, no explanation.
        """
    }

    // MARK: - Response Parsing

    private func parseScorecard(from response: String, hasKnowledgeContext: Bool = false) -> ContentScorecard {
        let cleaned = extractJSON(from: response)
        guard let data = cleaned.data(using: .utf8) else {
            return fallbackScorecard()
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Try to decode the raw JSON structure
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return fallbackScorecard()
        }

        let hookScore = parseScorecardScore(from: raw["hookScore"])
        let copyScore = parseScorecardScore(from: raw["copyScore"])
        let ctaScore = parseScorecardScore(from: raw["ctaScore"])
        let voiceMatch = parseVoiceMatch(from: raw["voiceMatch"])
        let structuralAlignment = parseStructuralAlignment(from: raw["structuralAlignment"])
        let slideAnalysis = parseSlideAnalysis(from: raw["slideAnalysis"])
        let overallConfidence = raw["overallConfidence"] as? Int ?? 50

        // Parse originality score only when knowledge context was available
        var originalityScore: OriginalityScore? = nil
        if hasKnowledgeContext, let originalityRaw = raw["originalityScore"] {
            originalityScore = parseOriginalityScore(from: originalityRaw)
        }

        return ContentScorecard(
            hookScore: hookScore,
            copyScore: copyScore,
            ctaScore: ctaScore,
            voiceMatch: voiceMatch,
            structuralAlignment: structuralAlignment,
            slideAnalysis: slideAnalysis,
            originalityScore: originalityScore,
            overallConfidence: overallConfidence,
            timestamp: Date()
        )
    }

    private func parseScorecardScore(from value: Any?) -> ScorecardScore {
        guard let dict = value as? [String: Any] else {
            return ScorecardScore(score: 0, criteria: [], suggestions: [])
        }

        let score = (dict["score"] as? Double) ?? 0
        let suggestions = (dict["suggestions"] as? [String]) ?? []

        var criteria: [CriterionResult] = []
        if let rawCriteria = dict["criteria"] as? [[String: Any]] {
            for c in rawCriteria {
                let name = c["name"] as? String ?? ""
                let cScore = c["score"] as? Double ?? 0
                let explanation = c["explanation"] as? String ?? ""
                criteria.append(CriterionResult(name: name, score: cScore, explanation: explanation))
            }
        }

        return ScorecardScore(score: score, criteria: criteria, suggestions: suggestions)
    }

    private func parseVoiceMatch(from value: Any?) -> VoiceMatchResult {
        guard let dict = value as? [String: Any] else {
            return VoiceMatchResult(percentage: -1, drifts: [])
        }

        let percentage = (dict["percentage"] as? Double) ?? -1
        var drifts: [VoiceDrift] = []

        if let rawDrifts = dict["drifts"] as? [[String: Any]] {
            for d in rawDrifts {
                let lineNumber = d["lineNumber"] as? Int ?? 0
                let draftText = d["draftText"] as? String ?? ""
                let issue = d["issue"] as? String ?? ""
                let suggestion = d["suggestion"] as? String ?? ""
                drifts.append(VoiceDrift(lineNumber: lineNumber, draftText: draftText, issue: issue, suggestion: suggestion))
            }
        }

        return VoiceMatchResult(percentage: percentage, drifts: drifts)
    }

    private func parseStructuralAlignment(from value: Any?) -> StructuralAlignment {
        guard let dict = value as? [String: Any] else {
            return StructuralAlignment(draftBeats: [], recommendedBeats: [], alignmentScore: 0, suggestions: [])
        }

        let draftBeats = (dict["draftBeats"] as? [String]) ?? []
        let recommendedBeats = (dict["recommendedBeats"] as? [String]) ?? []
        let alignmentScore = (dict["alignmentScore"] as? Double) ?? 0
        let suggestions = (dict["suggestions"] as? [String]) ?? []

        return StructuralAlignment(
            draftBeats: draftBeats,
            recommendedBeats: recommendedBeats,
            alignmentScore: alignmentScore,
            suggestions: suggestions
        )
    }

    private func parseSlideAnalysis(from value: Any?) -> [SlideAnalysis] {
        guard let array = value as? [[String: Any]] else { return [] }

        return array.map { dict in
            SlideAnalysis(
                sectionIndex: dict["sectionIndex"] as? Int ?? 0,
                draftText: dict["draftText"] as? String ?? "",
                beatLabel: dict["beatLabel"] as? String ?? "",
                swipeComparison: dict["swipeComparison"] as? String ?? "",
                suggestion: dict["suggestion"] as? String ?? ""
            )
        }
    }

    private func parseOriginalityScore(from value: Any?) -> OriginalityScore? {
        guard let dict = value as? [String: Any] else { return nil }

        let score = (dict["score"] as? Double) ?? 0
        let suggestions = (dict["suggestions"] as? [String]) ?? []

        var criteria: [CriterionResult] = []
        if let rawCriteria = dict["criteria"] as? [[String: Any]] {
            for c in rawCriteria {
                let name = c["name"] as? String ?? ""
                let cScore = c["score"] as? Double ?? 0
                let explanation = c["explanation"] as? String ?? ""
                criteria.append(CriterionResult(name: name, score: cScore, explanation: explanation))
            }
        }

        return OriginalityScore(score: score, criteria: criteria, suggestions: suggestions)
    }

    private func fallbackScorecard() -> ContentScorecard {
        ContentScorecard(
            hookScore: ScorecardScore(score: 0, criteria: [], suggestions: ["Could not evaluate — try again"]),
            copyScore: ScorecardScore(score: 0, criteria: [], suggestions: ["Could not evaluate — try again"]),
            ctaScore: ScorecardScore(score: 0, criteria: [], suggestions: ["Could not evaluate — try again"]),
            voiceMatch: VoiceMatchResult(percentage: -1, drifts: []),
            structuralAlignment: StructuralAlignment(draftBeats: [], recommendedBeats: [], alignmentScore: 0, suggestions: []),
            slideAnalysis: [],
            originalityScore: nil,
            overallConfidence: 0,
            timestamp: Date()
        )
    }

    // MARK: - Calibration Application

    /// Apply calibrated weights to a scorecard's dimension scores
    private func applyCalibratedWeights(_ scorecard: ContentScorecard, weights: [String: Double]) -> ContentScorecard {
        let hookWeight = weights["hook"] ?? 1.0
        let copyWeight = weights["copy"] ?? 1.0
        let ctaWeight = weights["cta"] ?? 1.0

        let calibratedHook = ScorecardScore(
            score: min(scorecard.hookScore.score * hookWeight, 10.0),
            criteria: scorecard.hookScore.criteria,
            suggestions: scorecard.hookScore.suggestions
        )
        let calibratedCopy = ScorecardScore(
            score: min(scorecard.copyScore.score * copyWeight, 10.0),
            criteria: scorecard.copyScore.criteria,
            suggestions: scorecard.copyScore.suggestions
        )
        let calibratedCTA = ScorecardScore(
            score: min(scorecard.ctaScore.score * ctaWeight, 10.0),
            criteria: scorecard.ctaScore.criteria,
            suggestions: scorecard.ctaScore.suggestions
        )

        return ContentScorecard(
            hookScore: calibratedHook,
            copyScore: calibratedCopy,
            ctaScore: calibratedCTA,
            voiceMatch: scorecard.voiceMatch,
            structuralAlignment: scorecard.structuralAlignment,
            slideAnalysis: scorecard.slideAnalysis,
            originalityScore: scorecard.originalityScore,
            overallConfidence: scorecard.overallConfidence,
            timestamp: scorecard.timestamp
        )
    }

    // MARK: - Prediction Storage

    /// Store a score prediction for later comparison with actual performance
    func storePrediction(contentUUID: UUID, scores: ContentScorecard) async {
        let overallScore = computeOverallScore(from: scores)

        let dimensionScores: [[String: Any]] = [
            ["name": "hook", "score": scores.hookScore.score],
            ["name": "copy", "score": scores.copyScore.score],
            ["name": "cta", "score": scores.ctaScore.score],
            ["name": "voiceMatch", "score": scores.voiceMatch.percentage / 10.0],
            ["name": "structuralAlignment", "score": scores.structuralAlignment.alignmentScore / 10.0]
        ]

        let metadataDict: [String: Any] = [
            "lessonType": "score_prediction",
            "contentUUID": contentUUID.uuidString,
            "overallScore": overallScore,
            "timestamp": ISO8601.string(from: Date())
        ]

        do {
            let structuredDict: [String: Any] = [
                "contentUUID": contentUUID.uuidString,
                "overallScore": overallScore,
                "dimensions": dimensionScores,
                "timestamp": ISO8601.string(from: Date())
            ]
            let structuredData = try JSONSerialization.data(withJSONObject: structuredDict)
            let structuredStr = String(data: structuredData, encoding: .utf8)

            let metadataData = try JSONSerialization.data(withJSONObject: metadataDict)
            let metadataStr = String(data: metadataData, encoding: .utf8)

            let atom = Atom.new(
                type: .agentLearning,
                title: "Score Prediction: \(String(format: "%.1f", overallScore))/10",
                body: contentUUID.uuidString,
                structured: structuredStr,
                metadata: metadataStr
            )
            _ = try await AtomRepository.shared.create(atom)
        } catch {
            print("[ContentScorecardEngine] Failed to store prediction: \(error.localizedDescription)")
        }
    }

    // MARK: - Calibration

    /// Compare prediction with actual engagement and calibrate scoring weights
    func calibrateFromPerformance(contentUUID: UUID, actualEngagement: [String: Double]) async {
        do {
            // Load prediction atom for this content
            let atoms = try await AtomRepository.shared.fetchAll(type: .agentLearning)
            guard let predictionAtom = atoms.first(where: { atom in
                guard let meta = atom.metadataDict else { return false }
                return meta["lessonType"] as? String == "score_prediction"
                    && meta["contentUUID"] as? String == contentUUID.uuidString
            }) else { return }

            // Parse predicted scores
            guard let structuredStr = predictionAtom.structured,
                  let structuredData = structuredStr.data(using: .utf8),
                  let predicted = try? JSONSerialization.jsonObject(with: structuredData) as? [String: Any],
                  let predictedOverall = predicted["overallScore"] as? Double else { return }

            // Compute actual performance score from engagement metrics
            let actualScore = computeActualScore(from: actualEngagement)

            // Store calibration delta
            let calibrationDelta = actualScore - predictedOverall

            let calibrationMeta: [String: Any] = [
                "lessonType": "score_calibration",
                "contentUUID": contentUUID.uuidString,
                "predictedScore": predictedOverall,
                "actualScore": actualScore,
                "delta": calibrationDelta
            ]
            let calibrationMetaData = try JSONSerialization.data(withJSONObject: calibrationMeta)
            let calibrationMetaStr = String(data: calibrationMetaData, encoding: .utf8)

            let calibrationAtom = Atom.new(
                type: .agentLearning,
                title: "Score Calibration: \(String(format: "%+.1f", calibrationDelta))",
                body: "Predicted \(String(format: "%.1f", predictedOverall)), Actual \(String(format: "%.1f", actualScore))",
                metadata: calibrationMetaStr
            )
            _ = try await AtomRepository.shared.create(calibrationAtom)
        } catch {
            print("[ContentScorecardEngine] Calibration failed: \(error.localizedDescription)")
        }
    }

    /// Load calibrated weights for a client based on historical accuracy
    func loadCalibratedWeights(clientUUID: UUID?) async -> [String: Double] {
        var weights: [String: Double] = [
            "hook": 1.0, "copy": 1.0, "cta": 1.0,
            "voiceMatch": 1.0, "structuralAlignment": 1.0, "originality": 1.0
        ]

        do {
            let atoms = try await AtomRepository.shared.fetchAll(type: .agentLearning)
            let calibrationAtoms = atoms.filter { atom in
                guard let meta = atom.metadataDict else { return false }
                return meta["lessonType"] as? String == "score_calibration"
            }

            guard !calibrationAtoms.isEmpty else { return weights }

            // Average deltas to compute adjustment factors
            var totalDelta = 0.0
            var count = 0
            for atom in calibrationAtoms.prefix(20) {
                guard let meta = atom.metadataDict,
                      let delta = meta["delta"] as? Double else { continue }
                totalDelta += delta
                count += 1
            }

            guard count > 0 else { return weights }
            let avgDelta = totalDelta / Double(count)

            // If predictions consistently over-estimate, reduce all weights slightly
            // If under-estimating, boost slightly
            let adjustment = 1.0 + (avgDelta * 0.05)  // Subtle: 5% per point of delta
            let clampedAdjustment = min(max(adjustment, 0.7), 1.3)  // Clamp to 0.7-1.3x

            for key in weights.keys {
                weights[key] = clampedAdjustment
            }
        } catch {
            // Return default weights on error
        }

        return weights
    }

    // MARK: - Guided Feedback

    /// Generate specific, actionable feedback for weak dimensions
    func generateGuidedFeedback(
        scores: ContentScorecard,
        matchedSwipes: [(hookType: String?, hookText: String?)],
        clientVoice: String?
    ) -> String {
        var feedback = ""

        // Hook feedback
        if scores.hookScore.score < 7 {
            var line = "[Hook] \(String(format: "%.1f", scores.hookScore.score))/10"
            if let swipe = matchedSwipes.first, let hookText = swipe.hookText {
                line += ": Top-performing hook example: \"\(String(hookText.prefix(80)))\". Rewrite to match this energy and pattern."
            } else {
                line += ": Hook needs to be more attention-grabbing. Use a bold claim, surprising stat, or direct question."
            }
            feedback += line + "\n"
        }

        // Copy feedback
        if scores.copyScore.score < 7 {
            feedback += "[Copy] \(String(format: "%.1f", scores.copyScore.score))/10: Body copy needs tightening. Remove filler words, strengthen verbs, improve flow.\n"
        }

        // CTA feedback
        if scores.ctaScore.score < 7 {
            feedback += "[CTA] \(String(format: "%.1f", scores.ctaScore.score))/10: CTA should be specific and action-oriented. Replace vague CTAs with concrete next steps.\n"
        }

        // Voice match feedback
        if scores.voiceMatch.percentage >= 0 && scores.voiceMatch.percentage < 70 {
            var line = "[VoiceMatch] \(String(format: "%.0f", scores.voiceMatch.percentage))%"
            if let voice = clientVoice {
                line += ": Target voice is \"\(String(voice.prefix(100)))\". Adjust sentence length, vocabulary, and tone to match."
            } else {
                line += ": Voice doesn't match client profile. Review sentence patterns and word choices."
            }
            feedback += line + "\n"
        }

        // Structural alignment feedback
        if scores.structuralAlignment.alignmentScore < 70 {
            feedback += "[Structure] \(String(format: "%.0f", scores.structuralAlignment.alignmentScore))%: Structure doesn't match the target framework. Check beat pattern and section flow.\n"
        }

        // Originality feedback
        if let originality = scores.originalityScore, originality.score < 7 {
            feedback += "[Originality] \(String(format: "%.1f", originality.score))/10: Weave in more unique framework terminology and avoid generic advice.\n"
        }

        return feedback
    }

    // MARK: - Private Score Helpers

    private func computeOverallScore(from scores: ContentScorecard) -> Double {
        var components: [Double] = [
            scores.hookScore.score,
            scores.copyScore.score,
            scores.ctaScore.score
        ]
        if scores.voiceMatch.percentage >= 0 {
            components.append(scores.voiceMatch.percentage / 10.0)
        }
        components.append(scores.structuralAlignment.alignmentScore / 10.0)
        if let originality = scores.originalityScore {
            components.append(originality.score)
        }

        guard !components.isEmpty else { return 0 }
        return components.reduce(0, +) / Double(components.count)
    }

    private func computeActualScore(from engagement: [String: Double]) -> Double {
        // Normalize engagement metrics to a 0-10 score
        // Expects keys like "views", "likes", "comments", "shares", "saves"
        var score = 5.0  // Baseline

        if let likes = engagement["likes"], let views = engagement["views"], views > 0 {
            let engagementRate = likes / views
            // 3%+ engagement rate = 8+, 1-3% = 5-8, <1% = below 5
            if engagementRate >= 0.03 {
                score = 8.0 + min(engagementRate * 50, 2.0)
            } else if engagementRate >= 0.01 {
                score = 5.0 + (engagementRate - 0.01) * 150
            } else {
                score = engagementRate * 500
            }
        }

        return min(max(score, 0), 10)
    }

    /// Extract JSON from a response that may contain markdown fencing or extra text
    private func extractJSON(from response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // If wrapped in code fences, extract
        if let start = trimmed.range(of: "```json") {
            let after = trimmed[start.upperBound...]
            if let end = after.range(of: "```") {
                return String(after[..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let start = trimmed.range(of: "```") {
            let after = trimmed[start.upperBound...]
            if let end = after.range(of: "```") {
                return String(after[..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Find first { and last }
        if let objStart = trimmed.firstIndex(of: "{"),
           let objEnd = trimmed.lastIndex(of: "}") {
            return String(trimmed[objStart...objEnd])
        }

        return trimmed
    }
}

// MARK: - Errors

enum ScorecardError: Error, LocalizedError {
    case emptyDraft

    var errorDescription: String? {
        switch self {
        case .emptyDraft: return "Draft is empty — write content before running the scorecard."
        }
    }
}
