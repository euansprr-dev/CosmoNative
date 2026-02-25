// CosmoOS/AI/RedTeamEngine.swift
// Red Team adversarial risk assessment engine for the Polish phase.
// Runs 5 parallel risk checks against content drafts using the client's
// Intelligence Model fingerprints (failure, voice, performance).
// February 2026

import Foundation
import SwiftUI

// MARK: - Risk Types

enum RiskType: String, Codable, Sendable {
    case scrollRisk
    case promiseDeliveryGap
    case voiceDrift
    case ctaWeakness
    case structuralMatch

    var displayName: String {
        switch self {
        case .scrollRisk: return "Scroll Risk"
        case .promiseDeliveryGap: return "Promise-Delivery Gap"
        case .voiceDrift: return "Voice Drift"
        case .ctaWeakness: return "CTA Weakness"
        case .structuralMatch: return "Structural Match"
        }
    }

    var iconName: String {
        switch self {
        case .scrollRisk: return "hand.draw"
        case .promiseDeliveryGap: return "arrow.triangle.branch"
        case .voiceDrift: return "waveform.path.ecg"
        case .ctaWeakness: return "megaphone"
        case .structuralMatch: return "rectangle.3.group"
        }
    }
}

// MARK: - Risk Severity

enum RiskSeverity: String, Codable, Sendable {
    case high
    case medium
    case low

    var displayName: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }

    var color: Color {
        switch self {
        case .high: return .red
        case .medium: return .orange
        case .low: return .yellow
        }
    }
}

// MARK: - Risk Card

struct RiskCard: Codable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let riskType: RiskType
    let severity: RiskSeverity
    let evidence: String
    let metric: String
    let recommendation: String
    let fixPrompt: String

    init(
        id: UUID = UUID(),
        title: String,
        riskType: RiskType,
        severity: RiskSeverity,
        evidence: String,
        metric: String,
        recommendation: String,
        fixPrompt: String
    ) {
        self.id = id
        self.title = title
        self.riskType = riskType
        self.severity = severity
        self.evidence = evidence
        self.metric = metric
        self.recommendation = recommendation
        self.fixPrompt = fixPrompt
    }
}

// MARK: - Red Team Result

struct RedTeamResult: Codable, Sendable {
    let cards: [RiskCard]
    let evaluatedAt: Date
    let draftWordCount: Int

    var highRiskCount: Int { cards.filter { $0.severity == .high }.count }
    var mediumRiskCount: Int { cards.filter { $0.severity == .medium }.count }
}

// MARK: - Red Team Engine

@MainActor
class RedTeamEngine: ObservableObject {
    @Published var isEvaluating: Bool = false
    @Published var result: RedTeamResult?
    @Published var evaluationProgress: String = ""

    /// Run all 5 adversarial risk assessments in parallel.
    func evaluate(contentAtom: Atom, state: ContentFocusModeState) async {
        let draftText = state.draftContent
        guard !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isEvaluating = true
        evaluationProgress = "Assembling context..."
        defer {
            isEvaluating = false
            evaluationProgress = ""
        }

        // Load client intelligence model
        let contentMeta = contentAtom.metadataValue(as: ContentAtomMetadata.self)
        var intelligenceModel: ClientIntelligenceModel?
        var isReelFormat = false
        var isThreadFormat = false

        if let clientUUID = contentMeta?.clientProfileUUID,
           let profileAtom = try? await AtomRepository.shared.fetch(uuid: clientUUID),
           let clientMeta = profileAtom.metadataValue(as: ClientProfileMetadata.self) {
            intelligenceModel = clientMeta.intelligenceModel

            // Determine content format
            if let sourceIdeaUUID = contentMeta?.sourceIdeaUUID,
               let ideaAtom = try? await AtomRepository.shared.fetch(uuid: sourceIdeaUUID),
               let format = ideaAtom.ideaContentFormat {
                isReelFormat = (format == .reel)
                isThreadFormat = (format == .thread)
            } else if let platform = contentMeta?.platform {
                isReelFormat = (platform == .instagram || platform == .tiktok || platform == .youtube)
                isThreadFormat = (platform == .twitter)
            }
        }

        // Select format-specific fingerprints
        let failureFingerprint: FailureFingerprint? = {
            guard let model = intelligenceModel else { return nil }
            if isReelFormat, let fp = model.reelFailureFingerprint { return fp }
            if isThreadFormat, let fp = model.threadFailureFingerprint { return fp }
            return model.failureFingerprint
        }()

        let voiceFingerprint: IntelligenceVoiceFingerprint? = {
            guard let model = intelligenceModel else { return nil }
            if isReelFormat, let vf = model.reelVoiceFingerprint { return vf }
            if isThreadFormat, let vf = model.threadVoiceFingerprint { return vf }
            return model.voiceFingerprint
        }()

        let performanceFingerprint: IntelligencePerformanceFingerprint? = {
            guard let model = intelligenceModel else { return nil }
            if isReelFormat, let pf = model.reelPerformanceFingerprint { return pf }
            if isThreadFormat, let pf = model.threadPerformanceFingerprint { return pf }
            return model.performanceFingerprint
        }()

        // Assemble cached mega-context
        evaluationProgress = "Running red team analysis..."
        let context = await WritingContextAssembler.assembleCachedMegaContext(contentAtom: contentAtom)

        let wordCount = draftText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count

        // Run all 5 assessments in parallel
        var allCards: [RiskCard] = []

        await withTaskGroup(of: [RiskCard].self) { group in
            // 1. Scroll Risk — always run (uses failure fingerprint if available)
            group.addTask { [draftText, failureFingerprint, context] in
                await self.assessScrollRisk(
                    draftText: draftText,
                    failureFingerprint: failureFingerprint,
                    context: context
                )
            }

            // 2. Promise-Delivery Gap — always run
            group.addTask { [draftText, failureFingerprint, context] in
                await self.assessPromiseDeliveryGap(
                    draftText: draftText,
                    failureFingerprint: failureFingerprint,
                    context: context
                )
            }

            // 3. Voice Drift — needs voice fingerprint
            if voiceFingerprint != nil {
                group.addTask { [draftText, voiceFingerprint, context] in
                    await self.assessVoiceDrift(
                        draftText: draftText,
                        voiceFingerprint: voiceFingerprint!,
                        context: context
                    )
                }
            }

            // 4. CTA Weakness — needs performance fingerprint
            if performanceFingerprint != nil {
                group.addTask { [draftText, performanceFingerprint, context] in
                    await self.assessCTAWeakness(
                        draftText: draftText,
                        performanceFingerprint: performanceFingerprint!,
                        context: context
                    )
                }
            }

            // 5. Structural Match — needs performance fingerprint
            if performanceFingerprint != nil {
                group.addTask { [draftText, performanceFingerprint, context] in
                    await self.assessStructuralMatch(
                        draftText: draftText,
                        performanceFingerprint: performanceFingerprint!,
                        context: context
                    )
                }
            }

            for await cards in group {
                allCards.append(contentsOf: cards)
            }
        }

        // Filter out low-severity findings
        let filteredCards = allCards.filter { $0.severity != .low }

        result = RedTeamResult(
            cards: filteredCards,
            evaluatedAt: Date(),
            draftWordCount: wordCount
        )
    }

    // MARK: - Assessment 1: Scroll Risk

    private func assessScrollRisk(
        draftText: String,
        failureFingerprint: FailureFingerprint?,
        context: PromptContext
    ) async -> [RiskCard] {
        var failureDirectives = ""
        if let fp = failureFingerprint {
            let directives = fp.asDirectives()
            if !directives.isEmpty {
                failureDirectives = """

                FAILURE FINGERPRINT RULES (from comparing top vs underperforming content):
                \(directives.map { "- \($0)" }.joined(separator: "\n"))

                Pay special attention to hook-related rules above.
                """
            }
        }

        let prompt = """
        You are an adversarial content analyst evaluating SCROLL RISK — the probability \
        a viewer scrolls past this content within the first 3 seconds.

        Analyze the opening (first 1-3 sentences / first slide) of this draft:
        \(failureDirectives)

        === FULL DRAFT ===
        \(draftText)
        === END DRAFT ===

        Evaluate:
        1. Hook word count — is it concise enough? (Compare against failure fingerprint rules if provided)
        2. Opening pattern — does it create immediate curiosity/tension?
        3. First-line readability — is it scannable at a glance?
        4. Scroll-stopping power — would this stop a thumb mid-scroll?

        Return ONLY a JSON array of risk findings. Each finding:
        {
          "title": "Short risk title",
          "severity": "high" | "medium" | "low",
          "evidence": "Exact quoted text from the draft that demonstrates the risk",
          "metric": "Quantified comparison (e.g., 'Your hook: 22 words | Client optimal: 11 words')",
          "recommendation": "Specific actionable fix",
          "fixPrompt": "Exact prompt to send to AI to fix this issue (write as instruction to rewrite)"
        }

        Return [] if no scroll risks found. Return ONLY valid JSON array.
        """

        return await runAssessment(prompt: prompt, riskType: .scrollRisk, context: context)
    }

    // MARK: - Assessment 2: Promise-Delivery Gap

    private func assessPromiseDeliveryGap(
        draftText: String,
        failureFingerprint: FailureFingerprint?,
        context: PromptContext
    ) async -> [RiskCard] {
        var failureDirectives = ""
        if let fp = failureFingerprint {
            let directives = fp.asDirectives()
            if !directives.isEmpty {
                failureDirectives = """

                FAILURE FINGERPRINT RULES:
                \(directives.map { "- \($0)" }.joined(separator: "\n"))
                """
            }
        }

        let prompt = """
        You are an adversarial content analyst evaluating PROMISE-DELIVERY GAP — whether \
        the content body delivers on what the hook promises.
        \(failureDirectives)

        === FULL DRAFT ===
        \(draftText)
        === END DRAFT ===

        Evaluate:
        1. Hook promise — what specific outcome/value does the hook promise?
        2. Body delivery — does the content actually deliver that value?
        3. Value positioning — does the payoff come early enough to retain viewers?
        4. Specificity gap — does the hook promise specifics but the body deliver vagueness?
        5. Clickbait risk — is the hook so provocative the body can't match it?

        Return ONLY a JSON array of risk findings. Each finding:
        {
          "title": "Short risk title",
          "severity": "high" | "medium" | "low",
          "evidence": "Exact quoted text showing the gap",
          "metric": "Quantified description of the gap",
          "recommendation": "Specific actionable fix",
          "fixPrompt": "Exact prompt to send to AI to fix this issue"
        }

        Return [] if no gaps found. Return ONLY valid JSON array.
        """

        return await runAssessment(prompt: prompt, riskType: .promiseDeliveryGap, context: context)
    }

    // MARK: - Assessment 3: Voice Drift

    private func assessVoiceDrift(
        draftText: String,
        voiceFingerprint: IntelligenceVoiceFingerprint,
        context: PromptContext
    ) async -> [RiskCard] {
        var voiceRules: [String] = []

        if voiceFingerprint.avgSentenceLength > 0 {
            voiceRules.append("Target avg sentence length: \(Int(voiceFingerprint.avgSentenceLength)) words")
        }
        if voiceFingerprint.maxSentenceLength > 0 {
            voiceRules.append("Hard max sentence length: \(voiceFingerprint.maxSentenceLength) words")
        }
        if !voiceFingerprint.readingLevel.isEmpty {
            voiceRules.append("Target reading level: \(voiceFingerprint.readingLevel)")
        }
        if !voiceFingerprint.blacklistedPhrases.isEmpty {
            voiceRules.append("BLACKLISTED phrases (must NEVER appear): \(voiceFingerprint.blacklistedPhrases.joined(separator: ", "))")
        }
        if !voiceFingerprint.signaturePhrases.isEmpty {
            voiceRules.append("Signature phrases (should appear 1-2x): \(voiceFingerprint.signaturePhrases.joined(separator: ", "))")
        }
        if !voiceFingerprint.punctuationStyle.isEmpty {
            voiceRules.append("Punctuation style: \(voiceFingerprint.punctuationStyle)")
        }
        if !voiceFingerprint.ctaPattern.isEmpty {
            voiceRules.append("CTA pattern: \(voiceFingerprint.ctaPattern)")
        }
        if !voiceFingerprint.emotionalToneDistribution.isEmpty {
            let tones = voiceFingerprint.emotionalToneDistribution
                .sorted { $0.value > $1.value }
                .prefix(5)
                .map { "\($0.key): \(Int($0.value * 100))%" }
                .joined(separator: ", ")
            voiceRules.append("Emotional tone distribution: \(tones)")
        }
        if !voiceFingerprint.sentenceStarterDistribution.isEmpty {
            let starters = voiceFingerprint.sentenceStarterDistribution
                .sorted { $0.value > $1.value }
                .prefix(5)
                .map { "\($0.key): \(Int($0.value * 100))%" }
                .joined(separator: ", ")
            voiceRules.append("Sentence starter distribution: \(starters)")
        }

        let voiceRulesText = voiceRules.isEmpty
            ? "No quantified voice rules available."
            : voiceRules.map { "- \($0)" }.joined(separator: "\n")

        let prompt = """
        You are an adversarial content analyst evaluating VOICE DRIFT — whether the draft \
        deviates from the client's established voice patterns.

        QUANTIFIED VOICE FINGERPRINT:
        \(voiceRulesText)

        === FULL DRAFT ===
        \(draftText)
        === END DRAFT ===

        Evaluate the draft against EVERY voice fingerprint metric above. Check:
        1. Sentence length — measure actual avg and max against targets
        2. Reading level — estimate grade level vs target
        3. Blacklisted phrases — flag ANY occurrence
        4. Signature phrases — flag if ZERO present
        5. Tone distribution — compare draft emotional tone to client targets
        6. Sentence starters — check for overused patterns that deviate from client norms
        7. Punctuation style — check for inconsistencies

        Return ONLY a JSON array of risk findings. Each finding:
        {
          "title": "Short risk title",
          "severity": "high" | "medium" | "low",
          "evidence": "Exact quoted text showing the drift",
          "metric": "Quantified comparison (e.g., 'Draft avg: 18 words | Client target: 11 words')",
          "recommendation": "Specific actionable fix",
          "fixPrompt": "Exact prompt to send to AI to fix this issue"
        }

        Severity guide:
        - high: blacklisted phrase found, or >40% deviation in sentence length/reading level
        - medium: 15-40% deviation in measured metrics, or missing signature phrases
        - low: minor stylistic drift

        Return [] if voice is well-matched. Return ONLY valid JSON array.
        """

        return await runAssessment(prompt: prompt, riskType: .voiceDrift, context: context)
    }

    // MARK: - Assessment 4: CTA Weakness

    private func assessCTAWeakness(
        draftText: String,
        performanceFingerprint: IntelligencePerformanceFingerprint,
        context: PromptContext
    ) async -> [RiskCard] {
        var perfContext: [String] = []

        if !performanceFingerprint.hookTypePerformance.isEmpty {
            let topHooks = performanceFingerprint.hookTypePerformance
                .sorted { $0.value > $1.value }
                .prefix(5)
                .map { "\($0.key): \(String(format: "%.1f", $0.value))" }
                .joined(separator: ", ")
            perfContext.append("Best hook types by engagement: \(topHooks)")
        }
        if !performanceFingerprint.engagementTriggers.isEmpty {
            perfContext.append("Top engagement triggers: \(performanceFingerprint.engagementTriggers.joined(separator: ", "))")
        }
        if !performanceFingerprint.optimalLength.isEmpty {
            perfContext.append("Optimal content length: \(performanceFingerprint.optimalLength)")
        }

        let perfText = perfContext.isEmpty
            ? "No performance data available."
            : perfContext.map { "- \($0)" }.joined(separator: "\n")

        let prompt = """
        You are an adversarial content analyst evaluating CTA WEAKNESS — whether the \
        call-to-action is strong enough to convert viewers into action-takers.

        CLIENT PERFORMANCE FINGERPRINT:
        \(perfText)

        === FULL DRAFT ===
        \(draftText)
        === END DRAFT ===

        Evaluate:
        1. CTA presence — is there a clear call-to-action?
        2. CTA clarity — does the reader know EXACTLY what to do?
        3. CTA benefit — does it answer "what's in it for me?"
        4. CTA specificity — does it include a timeline, outcome, or concrete next step?
        5. CTA positioning — is it placed where engagement is highest?
        6. CTA match — does it align with the client's best-performing CTA patterns?

        Return ONLY a JSON array of risk findings. Each finding:
        {
          "title": "Short risk title",
          "severity": "high" | "medium" | "low",
          "evidence": "Exact quoted CTA text (or note if missing entirely)",
          "metric": "Comparison to client's best patterns",
          "recommendation": "Specific actionable fix",
          "fixPrompt": "Exact prompt to send to AI to rewrite the CTA"
        }

        Return [] if CTA is strong. Return ONLY valid JSON array.
        """

        return await runAssessment(prompt: prompt, riskType: .ctaWeakness, context: context)
    }

    // MARK: - Assessment 5: Structural Match

    private func assessStructuralMatch(
        draftText: String,
        performanceFingerprint: IntelligencePerformanceFingerprint,
        context: PromptContext
    ) async -> [RiskCard] {
        var structContext: [String] = []

        if !performanceFingerprint.bestBeatPatterns.isEmpty {
            structContext.append("Best beat patterns: \(performanceFingerprint.bestBeatPatterns.joined(separator: " | "))")
        }
        if !performanceFingerprint.formatComparison.isEmpty {
            let formats = performanceFingerprint.formatComparison
                .sorted { $0.value > $1.value }
                .map { "\($0.key): \(String(format: "%.1f", $0.value))" }
                .joined(separator: ", ")
            structContext.append("Format performance: \(formats)")
        }
        if !performanceFingerprint.optimalLength.isEmpty {
            structContext.append("Optimal length: \(performanceFingerprint.optimalLength)")
        }

        let structText = structContext.isEmpty
            ? "No structural data available."
            : structContext.map { "- \($0)" }.joined(separator: "\n")

        let prompt = """
        You are an adversarial content analyst evaluating STRUCTURAL MATCH — whether the \
        draft's beat sequence aligns with the client's best-performing structural patterns.

        CLIENT BEST BEAT PATTERNS:
        \(structText)

        === FULL DRAFT ===
        \(draftText)
        === END DRAFT ===

        Evaluate:
        1. Extract the draft's actual beat sequence (e.g., Hook > Story > Proof > CTA)
        2. Compare against the client's best-performing beat patterns above
        3. Identify missing beats that the top patterns always include
        4. Identify extra beats that dilute the structure
        5. Check beat ordering — are transitions in the optimal sequence?

        Return ONLY a JSON array of risk findings. Each finding:
        {
          "title": "Short risk title",
          "severity": "high" | "medium" | "low",
          "evidence": "Description of structural deviation with specific sections referenced",
          "metric": "Draft pattern vs client's best pattern comparison",
          "recommendation": "Specific structural change to make",
          "fixPrompt": "Exact prompt to send to AI to restructure the content"
        }

        Severity guide:
        - high: missing 2+ critical beats, or fundamentally different structure
        - medium: missing 1 beat, or suboptimal ordering
        - low: minor structural tweaks

        Return [] if structure is well-aligned. Return ONLY valid JSON array.
        """

        return await runAssessment(prompt: prompt, riskType: .structuralMatch, context: context)
    }

    // MARK: - Assessment Runner

    /// Send a single assessment prompt to ResearchService and parse the RiskCard array response.
    private func runAssessment(
        prompt: String,
        riskType: RiskType,
        context: PromptContext
    ) async -> [RiskCard] {
        let messages: [[String: Any]] = [
            ["role": "user", "content": prompt]
        ]

        do {
            let response = try await ResearchService.shared.generateWithCaching(
                systemBlocks: context.systemBlocks,
                messages: messages,
                model: ContentModelTier.strategist.rawValue,
                maxTokens: 4096
            )

            return parseRiskCards(from: response, riskType: riskType)
        } catch {
            print("RedTeamEngine: \(riskType.rawValue) assessment failed: \(error)")
            return []
        }
    }

    // MARK: - Response Parsing

    private func parseRiskCards(from response: String, riskType: RiskType) -> [RiskCard] {
        let cleaned = extractJSON(from: response)
        guard let data = cleaned.data(using: .utf8) else { return [] }

        guard let rawArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return rawArray.compactMap { dict in
            guard let title = dict["title"] as? String,
                  let severityStr = dict["severity"] as? String,
                  let severity = RiskSeverity(rawValue: severityStr) else {
                return nil
            }

            return RiskCard(
                title: title,
                riskType: riskType,
                severity: severity,
                evidence: dict["evidence"] as? String ?? "",
                metric: dict["metric"] as? String ?? "",
                recommendation: dict["recommendation"] as? String ?? "",
                fixPrompt: dict["fixPrompt"] as? String ?? ""
            )
        }
    }

    /// Extract JSON from a response that may contain markdown fencing or extra text.
    private func extractJSON(from response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

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

        if let arrayStart = trimmed.firstIndex(of: "["),
           let arrayEnd = trimmed.lastIndex(of: "]") {
            return String(trimmed[arrayStart...arrayEnd])
        }
        if let objStart = trimmed.firstIndex(of: "{"),
           let objEnd = trimmed.lastIndex(of: "}") {
            return String(trimmed[objStart...objEnd])
        }

        return trimmed
    }
}
