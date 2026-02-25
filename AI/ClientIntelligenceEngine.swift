// CosmoOS/AI/ClientIntelligenceEngine.swift
// Generates and manages client intelligence models from profile documents

import Foundation

@MainActor
final class ClientIntelligenceEngine {
    static let shared = ClientIntelligenceEngine()
    private init() {}

    // MARK: - Generate Model

    /// Generate a full intelligence model from the profile's documents.
    /// Calls Opus via ResearchService to analyze brand story, top performers, and voice guides.
    func generateModel(profile: Atom) async throws -> ClientIntelligenceModel {
        guard let meta = profile.metadataValue(as: ClientProfileMetadata.self) else {
            throw IntelligenceError.noProfileMetadata
        }

        let documents = meta.documents ?? []
        guard !documents.isEmpty else {
            throw IntelligenceError.noDocuments
        }

        let documentCount = DocumentCount(
            story: documents.filter { $0.category == .story }.count,
            reels: documents.filter { $0.category == .reel }.count,
            threads: documents.filter { $0.category == .thread }.count,
            voiceGuide: documents.filter { $0.category == .voiceGuide }.count,
            underperformingReels: documents.filter { $0.category == .underperformingReel }.count,
            underperformingThreads: documents.filter { $0.category == .underperformingThread }.count
        )

        let prompt = buildAnalysisPrompt(documents: documents, profileMeta: meta)

        let response = try await ResearchService.shared.analyze(
            prompt: prompt,
            systemPrompt: intelligenceSystemPrompt,
            tier: .writer
        )

        print("ClientIntelligenceEngine: Got response (\(response.count) chars)")

        var model = try parseIntelligenceResponse(response)
        model.generatedAt = Date()
        model.documentCount = documentCount

        // Apply any existing user overrides from the current model
        if let existingOverrides = meta.intelligenceModel?.userOverrides, !existingOverrides.isEmpty {
            model.userOverrides = existingOverrides
            model = applyOverrides(model)
        }

        // Generate failure fingerprints if underperformer documents exist
        let topReels = documents.filter { $0.category == .reel }
        let underReels = documents.filter { $0.category == .underperformingReel }
        let topThreads = documents.filter { $0.category == .thread }
        let underThreads = documents.filter { $0.category == .underperformingThread }

        if !underReels.isEmpty && !topReels.isEmpty {
            print("ClientIntelligenceEngine: Generating reel failure fingerprint (\(topReels.count) top vs \(underReels.count) under)")
            model.reelFailureFingerprint = try await generateFailureFingerprint(
                topPerformers: topReels,
                underperformers: underReels,
                formatLabel: "Reels"
            )
        }

        if !underThreads.isEmpty && !topThreads.isEmpty {
            print("ClientIntelligenceEngine: Generating thread failure fingerprint (\(topThreads.count) top vs \(underThreads.count) under)")
            model.threadFailureFingerprint = try await generateFailureFingerprint(
                topPerformers: topThreads,
                underperformers: underThreads,
                formatLabel: "Threads"
            )
        }

        // Build combined failure fingerprint from all format-specific rules
        var allFailureRules: [FailureRule] = []
        if let reelFP = model.reelFailureFingerprint { allFailureRules.append(contentsOf: reelFP.rules) }
        if let threadFP = model.threadFailureFingerprint { allFailureRules.append(contentsOf: threadFP.rules) }

        if !allFailureRules.isEmpty {
            model.failureFingerprint = FailureFingerprint(
                rules: allFailureRules,
                generatedAt: Date(),
                topPerformerCount: topReels.count + topThreads.count,
                underperformerCount: underReels.count + underThreads.count
            )
        }

        return model
    }

    // MARK: - Update Model

    /// Re-generate the model, preserving existing user overrides.
    func updateModel(profile: Atom) async throws -> ClientIntelligenceModel {
        // generateModel already applies existing overrides
        return try await generateModel(profile: profile)
    }

    // MARK: - Drafting Context

    /// Returns a token-optimized plain-text summary of the intelligence model (~2-3K tokens).
    /// Strips confidence scores and source evidence for efficient prompt inclusion.
    func getModelForDrafting(profile: Atom) -> String {
        guard let meta = profile.metadataValue(as: ClientProfileMetadata.self),
              let model = meta.intelligenceModel else {
            return ""
        }

        var lines: [String] = []

        // Voice profile (Overall)
        lines.append("## Voice Profile (Overall)")
        lines.append(contentsOf: formatVoiceLines(model.voiceFingerprint))

        // Voice profile (Reels)
        if let reelVoice = model.reelVoiceFingerprint {
            lines.append("")
            lines.append("## Voice Profile (Reels)")
            lines.append(contentsOf: formatVoiceLines(reelVoice))
        }

        // Voice profile (Threads)
        if let threadVoice = model.threadVoiceFingerprint {
            lines.append("")
            lines.append("## Voice Profile (Threads)")
            lines.append(contentsOf: formatVoiceLines(threadVoice))
        }

        // Performance patterns (Overall)
        lines.append("")
        lines.append("## Performance Patterns (Overall)")
        lines.append(contentsOf: formatPerformanceLines(model.performanceFingerprint))

        // Performance patterns (Reels)
        if let reelPerf = model.reelPerformanceFingerprint {
            lines.append("")
            lines.append("## Performance Patterns (Reels)")
            lines.append(contentsOf: formatPerformanceLines(reelPerf))
        }

        // Performance patterns (Threads)
        if let threadPerf = model.threadPerformanceFingerprint {
            lines.append("")
            lines.append("## Performance Patterns (Threads)")
            lines.append(contentsOf: formatPerformanceLines(threadPerf))
        }

        // Audience model
        lines.append("")
        lines.append("## Audience")
        let am = model.audienceModel
        if !am.primaryAudience.isEmpty {
            lines.append("Primary audience: \(am.primaryAudience)")
        }
        if !am.topPainPoints.isEmpty {
            lines.append("Pain points: \(am.topPainPoints.joined(separator: "; "))")
        }
        if !am.aspirationalOutcomes.isEmpty {
            lines.append("Aspirational outcomes: \(am.aspirationalOutcomes.joined(separator: "; "))")
        }
        if !am.commonObjections.isEmpty {
            lines.append("Common objections: \(am.commonObjections.joined(separator: "; "))")
        }
        if !am.audienceLanguage.isEmpty {
            lines.append("Audience language: \(am.audienceLanguage.joined(separator: ", "))")
        }

        // Niche positioning
        lines.append("")
        lines.append("## Positioning")
        let np = model.nicheAndPositioning
        if !np.specificNiche.isEmpty {
            lines.append("Niche: \(np.specificNiche)")
        }
        if !np.uniqueAngle.isEmpty {
            lines.append("Unique angle: \(np.uniqueAngle)")
        }
        if !np.uniqueMechanism.isEmpty {
            lines.append("Unique mechanism: \(np.uniqueMechanism)")
        }
        if !np.coreBeliefs.isEmpty {
            lines.append("Core beliefs: \(np.coreBeliefs.joined(separator: "; "))")
        }
        if !np.enemies.isEmpty {
            lines.append("Enemies (what they stand against): \(np.enemies.joined(separator: "; "))")
        }

        // Failure fingerprint (overall)
        if let fp = model.failureFingerprint, !fp.rules.isEmpty {
            lines.append("")
            lines.append("## FAILURE FINGERPRINT")
            lines.append("Based on comparing \(fp.topPerformerCount) top performers vs \(fp.underperformerCount) underperformers:")
            lines.append(contentsOf: formatFailureDirectives(fp))
        }

        // Failure fingerprint (Reels)
        if let fp = model.reelFailureFingerprint, !fp.rules.isEmpty {
            lines.append("")
            lines.append("## FAILURE FINGERPRINT (Reels)")
            lines.append(contentsOf: formatFailureDirectives(fp))
        }

        // Failure fingerprint (Threads)
        if let fp = model.threadFailureFingerprint, !fp.rules.isEmpty {
            lines.append("")
            lines.append("## FAILURE FINGERPRINT (Threads)")
            lines.append(contentsOf: formatFailureDirectives(fp))
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Top Transcripts

    /// Returns raw transcripts of top N performing posts, optionally filtered by category (.reel or .thread).
    /// Pass nil to get both reels and threads combined.
    func getTopTranscripts(profile: Atom, count: Int, category: ProfileDocumentCategory? = nil) -> [String] {
        guard let meta = profile.metadataValue(as: ClientProfileMetadata.self),
              let documents = meta.documents else {
            return []
        }

        let performers: [ProfileDocument]
        if let category = category {
            performers = documents.filter { $0.category == category }
        } else {
            performers = documents.filter { $0.category.isHighPerformer }
        }

        return Array(performers.prefix(count).map { $0.content })
    }

    // MARK: - Failure Fingerprint Generation

    /// Generate a failure fingerprint by comparing top performers against underperformers.
    /// Sends both sets of transcripts to Claude and extracts rules where meaningful differences exist.
    private func generateFailureFingerprint(
        topPerformers: [ProfileDocument],
        underperformers: [ProfileDocument],
        formatLabel: String
    ) async throws -> FailureFingerprint {
        let prompt = buildFailureAnalysisPrompt(
            topPerformers: topPerformers,
            underperformers: underperformers,
            formatLabel: formatLabel
        )

        let response = try await ResearchService.shared.analyze(
            prompt: prompt,
            systemPrompt: failureAnalysisSystemPrompt,
            tier: .writer
        )

        print("ClientIntelligenceEngine: Failure fingerprint response (\(response.count) chars) for \(formatLabel)")

        let fingerprint = try parseFailureFingerprint(
            response,
            topCount: topPerformers.count,
            underCount: underperformers.count
        )

        return fingerprint
    }

    /// Build the comparison prompt for failure fingerprint analysis
    private func buildFailureAnalysisPrompt(
        topPerformers: [ProfileDocument],
        underperformers: [ProfileDocument],
        formatLabel: String
    ) -> String {
        var sections: [String] = []

        sections.append("# FAILURE PATTERN ANALYSIS: \(formatLabel)")
        sections.append("")
        sections.append("Compare these two sets of content from the same creator to identify what the underperforming content does differently from the top-performing content.")

        // Top performers
        sections.append("")
        sections.append("# TOP-PERFORMING \(formatLabel.uppercased()) (\(topPerformers.count) pieces)")
        for (i, doc) in topPerformers.enumerated() {
            sections.append("")
            sections.append("## Top \(formatLabel) \(i + 1): \(doc.title)")
            if let likes = doc.likes { sections.append("Likes: \(likes)") }
            if let shares = doc.shares { sections.append("Shares: \(shares)") }
            if let saves = doc.saves { sections.append("Saves: \(saves)") }
            if let comments = doc.comments { sections.append("Comments: \(comments)") }
            sections.append("Content:\n\(doc.content)")
        }

        // Underperformers
        sections.append("")
        sections.append("# UNDERPERFORMING \(formatLabel.uppercased()) (\(underperformers.count) pieces)")
        for (i, doc) in underperformers.enumerated() {
            sections.append("")
            sections.append("## Underperforming \(formatLabel) \(i + 1): \(doc.title)")
            if let likes = doc.likes { sections.append("Likes: \(likes)") }
            if let shares = doc.shares { sections.append("Shares: \(shares)") }
            if let saves = doc.saves { sections.append("Saves: \(saves)") }
            if let comments = doc.comments { sections.append("Comments: \(comments)") }
            sections.append("Content:\n\(doc.content)")
        }

        // Instructions
        sections.append("""

        # INSTRUCTIONS

        Analyze the structural and stylistic differences between the top-performing and underperforming content above.

        For each of these dimensions, measure the metric in BOTH sets and calculate the delta:
        1. Hook Length — word count of the opening hook/first sentence
        2. Reading Level — grade level or complexity
        3. Beat Count — number of distinct content beats/sections
        4. CTA Type — type and strength of call-to-action
        5. Value Delivery Position — where in the content the core value/insight appears (early/middle/late)
        6. Emotional Intensity — strength of emotional language (measured 1-10)
        7. Opening Pattern — classification of how the content opens (question/statement/story/statistic/etc.)
        8. Slide/Section Density — words per slide or section

        ONLY include a rule if the difference is statistically meaningful:
        - Delta > 15% for percentage-based metrics
        - Delta > 1 standard deviation for absolute metrics
        - Clear qualitative pattern difference (e.g., all top performers use questions, none of the underperformers do)

        For each rule, write a plain-English directive that tells the writer what to AVOID.

        Return a JSON array of failure rules:
        ```json
        {
          "rules": [
            {
              "dimension": "Hook Length",
              "bestMetric": "11 words avg",
              "worstMetric": "22 words avg",
              "delta": "100% longer",
              "rule": "AVOID hooks over 15 words. Your client's best hooks average 11 words, worst average 22.",
              "severity": "high"
            }
          ]
        }
        ```

        severity levels:
        - "high": Strong pattern across most documents, large delta
        - "medium": Visible pattern, moderate delta
        - "low": Weak but notable difference

        Return ONLY the JSON object, no additional text.
        """)

        return sections.joined(separator: "\n")
    }

    private var failureAnalysisSystemPrompt: String {
        """
        You are an expert content performance analyst. Your job is to compare a creator's top-performing content against their underperforming content and extract precise, actionable failure rules.

        You must measure real metrics — count actual words, count actual sections, assess actual reading complexity. Do not guess or generalize. Every rule must cite specific numbers from the content provided.

        Only flag differences that are statistically meaningful. If the top and underperforming content are similar on a dimension, do NOT create a rule for it. Quality over quantity — 3 strong rules are better than 8 weak ones.
        """
    }

    /// Parse the failure fingerprint JSON response into a FailureFingerprint
    private func parseFailureFingerprint(
        _ response: String,
        topCount: Int,
        underCount: Int
    ) throws -> FailureFingerprint {
        // Extract JSON using same strategy as parseIntelligenceResponse
        let jsonString: String

        if let codeBlockRange = response.range(of: "```json\\s*\\n", options: .regularExpression),
           let codeBlockEnd = response.range(of: "\\n\\s*```", options: .regularExpression, range: codeBlockRange.upperBound..<response.endIndex) {
            jsonString = String(response[codeBlockRange.upperBound..<codeBlockEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let codeBlockRange = response.range(of: "```\\s*\\n", options: .regularExpression),
                  let codeBlockEnd = response.range(of: "\\n\\s*```", options: .regularExpression, range: codeBlockRange.upperBound..<response.endIndex) {
            jsonString = String(response[codeBlockRange.upperBound..<codeBlockEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let jsonStart = response.range(of: "{"),
                  let jsonEnd = response.range(of: "}", options: .backwards) {
            jsonString = String(response[jsonStart.lowerBound...jsonEnd.lowerBound])
        } else {
            print("ClientIntelligenceEngine: No JSON found in failure response: \(String(response.prefix(500)))")
            throw IntelligenceError.invalidResponse
        }

        guard let data = jsonString.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rulesArray = raw["rules"] as? [[String: Any]] else {
            print("ClientIntelligenceEngine: Failed to parse failure fingerprint JSON")
            throw IntelligenceError.invalidResponse
        }

        let rules: [FailureRule] = rulesArray.compactMap { dict in
            guard let dimension = dict["dimension"] as? String,
                  let bestMetric = dict["bestMetric"] as? String,
                  let worstMetric = dict["worstMetric"] as? String,
                  let delta = dict["delta"] as? String,
                  let rule = dict["rule"] as? String,
                  let severityStr = dict["severity"] as? String,
                  let severity = FailureRuleSeverity(rawValue: severityStr) else {
                return nil
            }

            return FailureRule(
                dimension: dimension,
                bestMetric: bestMetric,
                worstMetric: worstMetric,
                delta: delta,
                rule: rule,
                severity: severity
            )
        }

        return FailureFingerprint(
            rules: rules,
            generatedAt: Date(),
            topPerformerCount: topCount,
            underperformerCount: underCount
        )
    }

    // MARK: - Failure Drafting Format

    /// Format failure fingerprint rules as drafting context lines, grouped by severity
    private func formatFailureDirectives(_ fp: FailureFingerprint) -> [String] {
        var lines: [String] = []

        let highRules = fp.rules(severity: .high)
        let mediumRules = fp.rules(severity: .medium)
        let lowRules = fp.rules(severity: .low)

        if !highRules.isEmpty {
            for rule in highRules {
                lines.append("- [HIGH] \(rule.rule)")
            }
        }
        if !mediumRules.isEmpty {
            for rule in mediumRules {
                lines.append("- [MEDIUM] \(rule.rule)")
            }
        }
        if !lowRules.isEmpty {
            for rule in lowRules {
                lines.append("- [LOW] \(rule.rule)")
            }
        }

        return lines
    }

    // MARK: - Parse Helpers

    /// Parse a voice fingerprint from a raw JSON dictionary
    private func parseVoiceFingerprint(_ dict: [String: Any]) -> IntelligenceVoiceFingerprint {
        var vf = IntelligenceVoiceFingerprint()
        vf.avgSentenceLength = dict["avgSentenceLength"] as? Double ?? 0
        vf.maxSentenceLength = dict["maxSentenceLength"] as? Int ?? 0
        vf.sentenceStarterDistribution = dict["sentenceStarterDistribution"] as? [String: Double] ?? [:]
        vf.readingLevel = dict["readingLevel"] as? String ?? ""
        vf.powerWords = dict["powerWords"] as? [String] ?? []
        vf.emotionalToneDistribution = dict["emotionalToneDistribution"] as? [String: Double] ?? [:]
        vf.punctuationStyle = dict["punctuationStyle"] as? String ?? ""
        vf.ctaPattern = dict["ctaPattern"] as? String ?? ""
        vf.signaturePhrases = dict["signaturePhrases"] as? [String] ?? []
        vf.blacklistedPhrases = dict["blacklistedPhrases"] as? [String] ?? []
        vf.paragraphLength = dict["paragraphLength"] as? String ?? ""
        vf.formattingQuirks = dict["formattingQuirks"] as? [String] ?? []
        return vf
    }

    /// Parse a performance fingerprint from a raw JSON dictionary
    private func parsePerformanceFingerprint(_ dict: [String: Any]) -> IntelligencePerformanceFingerprint {
        var pf = IntelligencePerformanceFingerprint()
        pf.hookTypePerformance = dict["hookTypePerformance"] as? [String: Double] ?? [:]
        pf.bestBeatPatterns = dict["bestBeatPatterns"] as? [String] ?? []
        pf.optimalLength = dict["optimalLength"] as? String ?? ""
        pf.bestTopics = dict["bestTopics"] as? [String] ?? []
        pf.engagementTriggers = dict["engagementTriggers"] as? [String] ?? []
        pf.formatComparison = dict["formatComparison"] as? [String: Double] ?? [:]
        return pf
    }

    // MARK: - Drafting Format Helpers

    /// Format voice fingerprint fields as drafting context lines
    private func formatVoiceLines(_ vf: IntelligenceVoiceFingerprint) -> [String] {
        var lines: [String] = []
        if vf.avgSentenceLength > 0 {
            lines.append("Avg sentence length: \(Int(vf.avgSentenceLength)) words")
        }
        if !vf.readingLevel.isEmpty { lines.append("Reading level: \(vf.readingLevel)") }
        if !vf.punctuationStyle.isEmpty { lines.append("Punctuation style: \(vf.punctuationStyle)") }
        if !vf.ctaPattern.isEmpty { lines.append("CTA pattern: \(vf.ctaPattern)") }
        if !vf.paragraphLength.isEmpty { lines.append("Paragraph length: \(vf.paragraphLength)") }
        if !vf.signaturePhrases.isEmpty {
            lines.append("Signature phrases: \(vf.signaturePhrases.joined(separator: ", "))")
        }
        if !vf.blacklistedPhrases.isEmpty {
            lines.append("Never use: \(vf.blacklistedPhrases.joined(separator: ", "))")
        }
        if !vf.powerWords.isEmpty {
            lines.append("Power words: \(vf.powerWords.joined(separator: ", "))")
        }
        if !vf.formattingQuirks.isEmpty {
            lines.append("Formatting quirks: \(vf.formattingQuirks.joined(separator: ", "))")
        }
        if !vf.emotionalToneDistribution.isEmpty {
            let tones = vf.emotionalToneDistribution.sorted { $0.value > $1.value }
                .prefix(5).map { "\($0.key): \(Int($0.value * 100))%" }
            lines.append("Emotional tone: \(tones.joined(separator: ", "))")
        }
        if !vf.sentenceStarterDistribution.isEmpty {
            let starters = vf.sentenceStarterDistribution.sorted { $0.value > $1.value }
                .prefix(5).map { "\($0.key): \(Int($0.value * 100))%" }
            lines.append("Sentence starters: \(starters.joined(separator: ", "))")
        }
        return lines
    }

    /// Format performance fingerprint fields as drafting context lines
    private func formatPerformanceLines(_ pf: IntelligencePerformanceFingerprint) -> [String] {
        var lines: [String] = []
        if !pf.bestTopics.isEmpty {
            lines.append("Best topics: \(pf.bestTopics.joined(separator: ", "))")
        }
        if !pf.optimalLength.isEmpty { lines.append("Optimal length: \(pf.optimalLength)") }
        if !pf.bestBeatPatterns.isEmpty {
            lines.append("Best beat patterns: \(pf.bestBeatPatterns.joined(separator: "; "))")
        }
        if !pf.engagementTriggers.isEmpty {
            lines.append("Engagement triggers: \(pf.engagementTriggers.joined(separator: ", "))")
        }
        if !pf.hookTypePerformance.isEmpty {
            let hooks = pf.hookTypePerformance.sorted { $0.value > $1.value }
                .prefix(5).map { "\($0.key): \(String(format: "%.1f", $0.value))" }
            lines.append("Top hook types: \(hooks.joined(separator: ", "))")
        }
        return lines
    }

    // MARK: - Private Helpers

    private var intelligenceSystemPrompt: String {
        """
        You are an expert content strategist and voice analyst. Your job is to analyze a creator's brand documents and top-performing content to extract a comprehensive intelligence model.

        You will receive four types of documents:
        1. BRAND STORY — The creator's origin story, mission, and narrative
        2. TOP-PERFORMING REELS — Their best-performing reels (short-form video scripts/transcripts)
        3. TOP-PERFORMING THREADS — Their best-performing threads/carousels
        4. VOICE GUIDE — Style guides, tone notes, and writing preferences

        IMPORTANT: ALL reels and threads provided are the creator's highest-performing content. Treat every piece equally as a top performer — there are no engagement metrics because every post here represents peak performance for this creator.

        Analyze ALL documents deeply. Extract patterns, not surface observations. Your output must be a single JSON object matching the exact schema provided.

        Analyze reels and threads both separately (noting format-specific patterns like optimal reel length vs thread length, different hook styles per format, different engagement triggers) AND together (for universal voice patterns, audience insights, and positioning that apply across all formats).

        For voice analysis: count actual sentences, measure real word frequencies, identify genuine patterns — do not guess or generalize.
        For performance analysis: identify structural patterns across all top-performing content to find what drives results. Note differences between reel and thread patterns.
        For audience modeling: infer the audience from the content that resonates, not from stated intentions.
        For niche positioning: identify what makes this creator genuinely different, not generic platitudes.

        Assign confidence levels (high/medium/low) to each metric based on evidence strength:
        - high: Clear pattern across 3+ documents with strong evidence
        - medium: Pattern visible in 2+ documents or inferred from strong signals
        - low: Single data point or weak inference
        """
    }

    private func buildAnalysisPrompt(documents: [ProfileDocument], profileMeta: ClientProfileMetadata) -> String {
        var sections: [String] = []

        // Profile context
        sections.append("# CLIENT PROFILE")
        sections.append("Name: \(profileMeta.clientName)")
        if let niche = profileMeta.niche, !niche.isEmpty {
            sections.append("Niche: \(niche)")
        }
        if let handle = profileMeta.handle, !handle.isEmpty {
            sections.append("Handle: \(handle)")
        }
        if !profileMeta.platforms.isEmpty {
            sections.append("Platforms: \(profileMeta.platforms.map { $0.displayName }.joined(separator: ", "))")
        }

        // Brand stories
        let stories = documents.filter { $0.category == .story }
        if !stories.isEmpty {
            sections.append("\n# BRAND STORY DOCUMENTS")
            for (i, doc) in stories.enumerated() {
                sections.append("\n## Story \(i + 1): \(doc.title)")
                sections.append(doc.content)
            }
        }

        // Top-performing reels
        let reels = documents.filter { $0.category == .reel }
        if !reels.isEmpty {
            sections.append("\n# TOP-PERFORMING REELS (all are peak performers)")
            for (i, doc) in reels.enumerated() {
                sections.append("\n## Reel \(i + 1): \(doc.title)")
                sections.append("Content:\n\(doc.content)")
            }
        }

        // Top-performing threads/carousels
        let threads = documents.filter { $0.category == .thread }
        if !threads.isEmpty {
            sections.append("\n# TOP-PERFORMING THREADS/CAROUSELS (all are peak performers)")
            for (i, doc) in threads.enumerated() {
                sections.append("\n## Thread \(i + 1): \(doc.title)")
                sections.append("Content:\n\(doc.content)")
            }
        }

        // Voice guides
        let voiceGuides = documents.filter { $0.category == .voiceGuide }
        if !voiceGuides.isEmpty {
            sections.append("\n# VOICE GUIDE DOCUMENTS")
            for (i, doc) in voiceGuides.enumerated() {
                sections.append("\n## Guide \(i + 1): \(doc.title)")
                sections.append(doc.content)
            }
        }

        // Determine which format-specific sections to request
        let hasReels = documents.contains { $0.category == .reel }
        let hasThreads = documents.contains { $0.category == .thread }

        // Response schema
        var schemaLines: [String] = []
        schemaLines.append("""

        # INSTRUCTIONS

        Analyze all documents above and return a single JSON object with this exact structure.
        The overall voiceFingerprint/performanceFingerprint analyze ALL content combined.
        Format-specific fingerprints analyze ONLY that format's content and capture what's unique to it (e.g., different sentence lengths for reels vs threads, different hook types, different pacing).

        ```json
        {
          "voiceFingerprint": {
            "avgSentenceLength": <number>,
            "maxSentenceLength": <number>,
            "sentenceStarterDistribution": {"pattern": <0-1 proportion>, ...},
            "readingLevel": "<grade level or description>",
            "powerWords": ["word1", "word2", ...],
            "emotionalToneDistribution": {"tone": <0-1 proportion>, ...},
            "punctuationStyle": "<description of punctuation usage>",
            "ctaPattern": "<typical call-to-action pattern>",
            "signaturePhrases": ["phrase1", "phrase2", ...],
            "blacklistedPhrases": ["phrase1", "phrase2", ...],
            "paragraphLength": "<short/medium/long with avg word count>",
            "formattingQuirks": ["quirk1", "quirk2", ...]
          },
          "performanceFingerprint": {
            "hookTypePerformance": {"hookType": <frequency 0-1 across top content>, ...},
            "bestBeatPatterns": ["Beat1>Beat2>Beat3>Beat4", ...],
            "optimalLength": "<word count range or description>",
            "bestTopics": ["topic1", "topic2", ...],
            "engagementTriggers": ["trigger1", "trigger2", ...],
            "formatComparison": {"format": <prevalence 0-1 across top content>, ...}
          },
        """)

        if hasReels {
            schemaLines.append("""
              "reelVoiceFingerprint": { <same shape as voiceFingerprint — analyzing ONLY reels> },
              "reelPerformanceFingerprint": { <same shape as performanceFingerprint — analyzing ONLY reels> },
            """)
        }

        if hasThreads {
            schemaLines.append("""
              "threadVoiceFingerprint": { <same shape as voiceFingerprint — analyzing ONLY threads> },
              "threadPerformanceFingerprint": { <same shape as performanceFingerprint — analyzing ONLY threads> },
            """)
        }

        schemaLines.append("""
          "audienceModel": {
            "primaryAudience": "<description>",
            "topPainPoints": ["pain1", "pain2", ...],
            "aspirationalOutcomes": ["outcome1", "outcome2", ...],
            "commonObjections": ["objection1", "objection2", ...],
            "audienceLanguage": ["phrase1", "phrase2", ...]
          },
          "nicheAndPositioning": {
            "specificNiche": "<specific niche description>",
            "uniqueAngle": "<what makes them different>",
            "coreBeliefs": ["belief1", "belief2", ...],
            "enemies": ["enemy1", "enemy2", ...],
            "uniqueMechanism": "<their unique approach/framework>"
          },
          "confidenceScores": [
            {"metricPath": "voiceFingerprint.avgSentenceLength", "confidence": "high|medium|low", "reasoning": "..."},
            ...
          ]
        }
        ```

        Return ONLY the JSON object, no additional text. Ensure all string values are properly escaped.
        """)

        sections.append(schemaLines.joined(separator: "\n"))

        return sections.joined(separator: "\n")
    }


    private func parseIntelligenceResponse(_ response: String) throws -> ClientIntelligenceModel {
        // Extract JSON from the response (may be wrapped in markdown code blocks)
        let jsonString: String

        // Strategy 1: Extract from markdown ```json ... ``` code block
        if let codeBlockRange = response.range(of: "```json\\s*\\n", options: .regularExpression),
           let codeBlockEnd = response.range(of: "\\n\\s*```", options: .regularExpression, range: codeBlockRange.upperBound..<response.endIndex) {
            jsonString = String(response[codeBlockRange.upperBound..<codeBlockEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Strategy 2: Extract from generic ``` ... ``` code block
        else if let codeBlockRange = response.range(of: "```\\s*\\n", options: .regularExpression),
                let codeBlockEnd = response.range(of: "\\n\\s*```", options: .regularExpression, range: codeBlockRange.upperBound..<response.endIndex) {
            jsonString = String(response[codeBlockRange.upperBound..<codeBlockEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Strategy 3: Find first { and last } directly
        else if let jsonStart = response.range(of: "{"),
                let jsonEnd = response.range(of: "}", options: .backwards) {
            jsonString = String(response[jsonStart.lowerBound...jsonEnd.lowerBound])
        } else {
            print("ClientIntelligenceEngine: No JSON found in response (\(response.count) chars): \(String(response.prefix(500)))")
            throw IntelligenceError.invalidResponse
        }

        guard let data = jsonString.data(using: .utf8) else {
            print("ClientIntelligenceEngine: Failed to convert JSON string to UTF-8 data")
            throw IntelligenceError.invalidResponse
        }

        // Parse the raw JSON structure
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("ClientIntelligenceEngine: JSONSerialization failed. JSON string (\(jsonString.count) chars): \(String(jsonString.prefix(500)))")
            throw IntelligenceError.invalidResponse
        }

        // Build model from parsed JSON
        var model = ClientIntelligenceModel()

        // Voice fingerprint (overall)
        if let vfDict = raw["voiceFingerprint"] as? [String: Any] {
            model.voiceFingerprint = parseVoiceFingerprint(vfDict)
        }

        // Performance fingerprint (overall)
        if let pfDict = raw["performanceFingerprint"] as? [String: Any] {
            model.performanceFingerprint = parsePerformanceFingerprint(pfDict)
        }

        // Format-specific fingerprints
        if let d = raw["reelVoiceFingerprint"] as? [String: Any] {
            model.reelVoiceFingerprint = parseVoiceFingerprint(d)
        }
        if let d = raw["reelPerformanceFingerprint"] as? [String: Any] {
            model.reelPerformanceFingerprint = parsePerformanceFingerprint(d)
        }
        if let d = raw["threadVoiceFingerprint"] as? [String: Any] {
            model.threadVoiceFingerprint = parseVoiceFingerprint(d)
        }
        if let d = raw["threadPerformanceFingerprint"] as? [String: Any] {
            model.threadPerformanceFingerprint = parsePerformanceFingerprint(d)
        }

        // Audience model
        if let amDict = raw["audienceModel"] as? [String: Any] {
            var am = IntelligenceAudienceModel()
            am.primaryAudience = amDict["primaryAudience"] as? String ?? ""
            am.topPainPoints = amDict["topPainPoints"] as? [String] ?? []
            am.aspirationalOutcomes = amDict["aspirationalOutcomes"] as? [String] ?? []
            am.commonObjections = amDict["commonObjections"] as? [String] ?? []
            am.audienceLanguage = amDict["audienceLanguage"] as? [String] ?? []
            model.audienceModel = am
        }

        // Niche positioning
        if let npDict = raw["nicheAndPositioning"] as? [String: Any] {
            var np = IntelligenceNichePositioning()
            np.specificNiche = npDict["specificNiche"] as? String ?? ""
            np.uniqueAngle = npDict["uniqueAngle"] as? String ?? ""
            np.coreBeliefs = npDict["coreBeliefs"] as? [String] ?? []
            np.enemies = npDict["enemies"] as? [String] ?? []
            np.uniqueMechanism = npDict["uniqueMechanism"] as? String ?? ""
            model.nicheAndPositioning = np
        }

        // Confidence scores
        if let csArray = raw["confidenceScores"] as? [[String: Any]] {
            model.confidenceScores = csArray.compactMap { dict in
                guard let path = dict["metricPath"] as? String,
                      let confStr = dict["confidence"] as? String,
                      let confidence = ConfidenceLevel(rawValue: confStr) else {
                    return nil
                }
                return MetricConfidence(
                    metricPath: path,
                    confidence: confidence,
                    reasoning: dict["reasoning"] as? String ?? ""
                )
            }
        }

        return model
    }

    /// Apply user overrides to the generated model values
    private func applyOverrides(_ model: ClientIntelligenceModel) -> ClientIntelligenceModel {
        var m = model
        for override in m.userOverrides {
            // Apply overrides by metric path
            switch override.metricPath {
            // Overall voice
            case "voiceFingerprint.readingLevel":
                m.voiceFingerprint.readingLevel = override.userValue
            case "voiceFingerprint.punctuationStyle":
                m.voiceFingerprint.punctuationStyle = override.userValue
            case "voiceFingerprint.ctaPattern":
                m.voiceFingerprint.ctaPattern = override.userValue
            case "voiceFingerprint.paragraphLength":
                m.voiceFingerprint.paragraphLength = override.userValue
            // Reel voice
            case "reelVoiceFingerprint.readingLevel":
                m.reelVoiceFingerprint?.readingLevel = override.userValue
            case "reelVoiceFingerprint.punctuationStyle":
                m.reelVoiceFingerprint?.punctuationStyle = override.userValue
            case "reelVoiceFingerprint.ctaPattern":
                m.reelVoiceFingerprint?.ctaPattern = override.userValue
            case "reelVoiceFingerprint.paragraphLength":
                m.reelVoiceFingerprint?.paragraphLength = override.userValue
            // Thread voice
            case "threadVoiceFingerprint.readingLevel":
                m.threadVoiceFingerprint?.readingLevel = override.userValue
            case "threadVoiceFingerprint.punctuationStyle":
                m.threadVoiceFingerprint?.punctuationStyle = override.userValue
            case "threadVoiceFingerprint.ctaPattern":
                m.threadVoiceFingerprint?.ctaPattern = override.userValue
            case "threadVoiceFingerprint.paragraphLength":
                m.threadVoiceFingerprint?.paragraphLength = override.userValue
            // Overall performance
            case "performanceFingerprint.optimalLength":
                m.performanceFingerprint.optimalLength = override.userValue
            // Reel performance
            case "reelPerformanceFingerprint.optimalLength":
                m.reelPerformanceFingerprint?.optimalLength = override.userValue
            // Thread performance
            case "threadPerformanceFingerprint.optimalLength":
                m.threadPerformanceFingerprint?.optimalLength = override.userValue
            // Audience
            case "audienceModel.primaryAudience":
                m.audienceModel.primaryAudience = override.userValue
            // Niche
            case "nicheAndPositioning.specificNiche":
                m.nicheAndPositioning.specificNiche = override.userValue
            case "nicheAndPositioning.uniqueAngle":
                m.nicheAndPositioning.uniqueAngle = override.userValue
            case "nicheAndPositioning.uniqueMechanism":
                m.nicheAndPositioning.uniqueMechanism = override.userValue
            default:
                // Unknown metric path — override stored but not applied
                break
            }
        }
        return m
    }
}

// MARK: - Errors

enum IntelligenceError: LocalizedError {
    case noProfileMetadata
    case noDocuments
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noProfileMetadata:
            return "Profile has no metadata. Create a client profile first."
        case .noDocuments:
            return "No documents found. Add brand stories, top performers, or voice guides to generate intelligence."
        case .invalidResponse:
            return "Failed to parse intelligence model from AI response."
        }
    }
}
