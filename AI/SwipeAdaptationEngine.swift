// CosmoOS/AI/SwipeAdaptationEngine.swift
// Dedicated engine for adapting swipe hook patterns to specific client niches.
// Two-pass Claude architecture: Haiku screening (Pass 1) → Sonnet adaptation (Pass 2).

import Foundation

// MARK: - Data Models

struct SwipeAdaptationCandidate {
    let swipeAtomUUID: String
    let title: String
    let hookText: String?
    let hookType: SwipeHookType?
    let frameworkType: SwipeFrameworkType?
    let dominantEmotion: SwipeEmotion?
    let platform: String?
    let fullBody: String?           // loaded only for Pass 2 candidates
    let screeningReason: String?    // reasoning from Pass 1
}

struct ScreeningResult: Codable {
    let selectedIndices: [Int]
    let reasoning: [String]?
}

struct AdaptedIdea: Codable {
    let sourceIndex: Int
    let adaptedHook: String
    let ideaTitle: String
    let ideaBody: String
    let hookType: String
    let suggestedFramework: String
    let adaptationReasoning: String
    let confidence: String
}

struct SwipeAdaptationResult {
    let clientName: String
    let clientUUID: String
    let totalSwipesScanned: Int
    let candidatesEvaluated: Int
    let adaptedIdeas: [AdaptedIdea]
    let sourceSwipes: [SwipeAdaptationCandidate]
    let timeFilter: String?
}

// MARK: - Engine

@MainActor
final class SwipeAdaptationEngine {
    static let shared = SwipeAdaptationEngine()

    private let atomRepo = AtomRepository.shared

    private init() {}

    // MARK: - Public API

    func adaptSwipesForClient(
        clientName: String,
        timeFilter: String? = nil,
        maxResults: Int = 10
    ) async throws -> SwipeAdaptationResult {

        // 1. Resolve client
        guard let clientAtom = try await atomRepo.fuzzyFindClient(query: clientName) else {
            throw SwipeAdaptationError.clientNotFound(clientName)
        }
        let clientMeta = clientAtom.metadataValue(as: ClientProfileMetadata.self)
        let resolvedName = clientMeta?.clientName ?? clientName

        // 2. Load all swipes
        let allResearch = try await atomRepo.fetchAll(type: .research)
        var swipes = allResearch.filter { $0.isSwipeFileAtom }

        // 3. Apply time filter
        if let timeFilter = timeFilter, let cutoff = parseTimeFilter(timeFilter) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallbackFormatter = ISO8601DateFormatter()
            fallbackFormatter.formatOptions = [.withInternetDateTime]

            swipes = swipes.filter { atom in
                let date = formatter.date(from: atom.createdAt) ?? fallbackFormatter.date(from: atom.createdAt)
                guard let date = date else { return false }
                return date >= cutoff
            }
        }

        guard !swipes.isEmpty else {
            throw SwipeAdaptationError.noSwipesFound(timeFilter)
        }

        // 4. Load existing client ideas for deduplication
        let allIdeas = try await atomRepo.fetchAll(type: .idea)
        let existingIdeaTitles = allIdeas
            .filter { $0.ideaClientUUID == clientAtom.uuid }
            .compactMap { $0.title?.lowercased() }

        // 5. Extract top-performer first lines for deduplication
        let topPerformerFirstLines: [String] = {
            guard let meta = clientMeta else { return [] }
            var lines: [String] = []
            if let topPosts = meta.topPerformingPosts {
                lines += topPosts.compactMap { post in
                    let firstLine = post.transcript.components(separatedBy: .newlines).first ?? ""
                    return firstLine.isEmpty ? nil : firstLine.lowercased()
                }
            }
            if let transcripts = meta.topPerformingTranscripts {
                lines += transcripts.compactMap { transcript in
                    let firstLine = transcript.components(separatedBy: .newlines).first ?? ""
                    return firstLine.isEmpty ? nil : firstLine.lowercased()
                }
            }
            return lines
        }()

        // 6. Format ALL swipes compactly for screening
        let compactSwipes: [(index: Int, atom: Atom, display: String)] = swipes.enumerated().compactMap { idx, atom in
            let title = atom.title ?? ""
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let analysis = atom.swipeAnalysis
            let hookType = analysis?.hookType?.rawValue ?? "unknown"
            return (index: idx, atom: atom, display: "#\(idx + 1). \"\(title)\" [\(hookType)]")
        }

        guard !compactSwipes.isEmpty else {
            return SwipeAdaptationResult(
                clientName: resolvedName,
                clientUUID: clientAtom.uuid,
                totalSwipesScanned: swipes.count,
                candidatesEvaluated: 0,
                adaptedIdeas: [],
                sourceSwipes: [],
                timeFilter: timeFilter
            )
        }

        // 7. Pass 1: Claude screens entire library (Haiku)
        let maxCandidates = min(maxResults + 5, 25)
        let screeningResult = try await screenCandidates(
            compactSwipes: compactSwipes,
            clientProfile: clientMeta,
            clientName: resolvedName,
            maxCandidates: maxCandidates
        )

        // 8. Load full bodies for selected swipes + build candidates
        let selectedCandidates: [SwipeAdaptationCandidate] = screeningResult.selectedIndices.enumerated().compactMap { reasonIdx, swipeIdx in
            // Find the compact swipe entry matching this index
            guard let entry = compactSwipes.first(where: { $0.index == swipeIdx }) else { return nil }
            let atom = entry.atom
            let analysis = atom.swipeAnalysis
            let metaDict = atom.metadataDict ?? [:]
            let reason = screeningResult.reasoning.flatMap { reasonIdx < $0.count ? $0[reasonIdx] : nil }

            return SwipeAdaptationCandidate(
                swipeAtomUUID: atom.uuid,
                title: atom.title ?? "",
                hookText: analysis?.hookText,
                hookType: analysis?.hookType,
                frameworkType: analysis?.frameworkType,
                dominantEmotion: analysis?.dominantEmotion,
                platform: metaDict["contentSource"] as? String,
                fullBody: atom.body,
                screeningReason: reason
            )
        }

        // 9. Deduplicate against existing ideas + top performers
        let deduplicated = deduplicateAgainstExisting(
            candidates: selectedCandidates,
            existingIdeaTitles: existingIdeaTitles,
            topPerformerFirstLines: topPerformerFirstLines
        )

        guard !deduplicated.isEmpty else {
            return SwipeAdaptationResult(
                clientName: resolvedName,
                clientUUID: clientAtom.uuid,
                totalSwipesScanned: swipes.count,
                candidatesEvaluated: selectedCandidates.count,
                adaptedIdeas: [],
                sourceSwipes: [],
                timeFilter: timeFilter
            )
        }

        // 10. Pass 2: Claude generates adapted ideas (Sonnet, with prompt caching)
        let adaptedIdeas = await generateAdaptations(
            candidates: deduplicated,
            clientProfile: clientMeta,
            clientName: resolvedName,
            existingIdeas: existingIdeaTitles
        )

        // 11. Trim to requested maxResults
        let finalIdeas = Array(adaptedIdeas.prefix(maxResults))

        return SwipeAdaptationResult(
            clientName: resolvedName,
            clientUUID: clientAtom.uuid,
            totalSwipesScanned: swipes.count,
            candidatesEvaluated: deduplicated.count,
            adaptedIdeas: finalIdeas,
            sourceSwipes: deduplicated,
            timeFilter: timeFilter
        )
    }

    // MARK: - Pass 1: Claude Screening (Haiku)

    private func screenCandidates(
        compactSwipes: [(index: Int, atom: Atom, display: String)],
        clientProfile: ClientProfileMetadata?,
        clientName: String,
        maxCandidates: Int
    ) async throws -> ScreeningResult {

        let prompt = buildScreeningPrompt(
            compactSwipes: compactSwipes,
            clientProfile: clientProfile,
            clientName: clientName,
            maxCandidates: maxCandidates
        )

        let response = try await ResearchService.shared.analyze(
            prompt: prompt,
            systemPrompt: "You are a content strategist screening a swipe file library. Return ONLY valid JSON, no other text.",
            tier: .sensor,
            maxTokens: 2048
        )

        return parseScreeningResponse(response, swipeCount: compactSwipes.count)
    }

    private func buildScreeningPrompt(
        compactSwipes: [(index: Int, atom: Atom, display: String)],
        clientProfile: ClientProfileMetadata?,
        clientName: String,
        maxCandidates: Int
    ) -> String {
        var sections: [String] = []

        sections.append("""
        You are screening a swipe file library to find hooks whose STRUCTURAL PATTERN can be adapted \
        to a specific client's niche. You are NOT looking for topic similarity — you are looking for \
        hook MECHANISMS that work universally when you swap the domain-specific nouns.

        Example: "The one foreclosure trick banks don't want you to know" → for a fitness client, \
        the curiosity gap + authority challenge STRUCTURE adapts perfectly: "The one recovery \
        technique physical therapists don't want you to know"
        """)

        // Client context
        var clientSection = "CLIENT: \(clientName)"
        if let meta = clientProfile {
            if let niche = meta.niche ?? meta.industry { clientSection += " — \(niche)" }
            if let brandStory = meta.brandStory, !brandStory.isEmpty { clientSection += "\nBrand Story: \(String(brandStory.prefix(200)))" }
            if let targetAudience = meta.targetAudience, !targetAudience.isEmpty { clientSection += "\nAudience: \(targetAudience)" }
            if let audienceModel = meta.intelligenceModel?.audienceModel {
                if !audienceModel.topPainPoints.isEmpty {
                    clientSection += "\nPain Points: \(audienceModel.topPainPoints.joined(separator: "; "))"
                }
                if !audienceModel.aspirationalOutcomes.isEmpty {
                    clientSection += "\nAspirations: \(audienceModel.aspirationalOutcomes.joined(separator: "; "))"
                }
            }
        }
        sections.append(clientSection)

        // Swipe list
        let swipeList = compactSwipes.map { $0.display }.joined(separator: "\n")
        sections.append("SWIPE LIBRARY (\(compactSwipes.count) swipes):\n\(swipeList)")

        // Instructions
        sections.append("""
        Select the \(maxCandidates) swipes whose hook structures are MOST adaptable to this client. \
        Consider:
        - Can the hook's open loop mechanism transfer? (curiosity gaps, bold claims, contrasts)
        - Can domain-specific nouns be swapped for client-relevant equivalents?
        - Does the emotional trigger map to this audience's pain points or aspirations?
        - Would the adapted version pass the scroll test for this niche?

        Return ONLY valid JSON:
        {"selectedIndices": [3, 7, 12], "reasoning": ["brief reason for #3", "brief reason for #7", "brief reason for #12"]}

        IMPORTANT: selectedIndices must use the exact # numbers from the list above.
        """)

        return sections.joined(separator: "\n\n")
    }

    private func parseScreeningResponse(_ response: String, swipeCount: Int) -> ScreeningResult {
        // Try direct JSON decode
        if let data = response.data(using: .utf8),
           let result = try? JSONDecoder().decode(ScreeningResult.self, from: data) {
            return sanitizeScreeningResult(result, swipeCount: swipeCount)
        }

        // Regex fallback: extract JSON from response text
        if let range = response.range(of: #"\{[\s\S]*"selectedIndices"[\s\S]*\}"#, options: .regularExpression) {
            let jsonStr = String(response[range])
            if let data = jsonStr.data(using: .utf8),
               let result = try? JSONDecoder().decode(ScreeningResult.self, from: data) {
                return sanitizeScreeningResult(result, swipeCount: swipeCount)
            }
        }

        // Fallback: if parsing fails, return first N indices as a safe default
        print("⚠️ [SwipeAdaptationEngine] Failed to parse screening response, using positional fallback")
        let fallbackCount = min(20, swipeCount)
        return ScreeningResult(
            selectedIndices: Array(1...fallbackCount),
            reasoning: nil
        )
    }

    private func sanitizeScreeningResult(_ result: ScreeningResult, swipeCount: Int) -> ScreeningResult {
        // Convert from 1-indexed (prompt uses #1, #2...) to 0-indexed, filter out-of-range
        let sanitized = result.selectedIndices.map { $0 - 1 }.filter { $0 >= 0 && $0 < swipeCount }
        return ScreeningResult(selectedIndices: sanitized, reasoning: result.reasoning)
    }

    // MARK: - Deduplication

    private func deduplicateAgainstExisting(
        candidates: [SwipeAdaptationCandidate],
        existingIdeaTitles: [String],
        topPerformerFirstLines: [String]
    ) -> [SwipeAdaptationCandidate] {
        guard !existingIdeaTitles.isEmpty || !topPerformerFirstLines.isEmpty else { return candidates }

        let allExisting = existingIdeaTitles + topPerformerFirstLines

        return candidates.filter { candidate in
            let hookLower = (candidate.hookText ?? candidate.title).lowercased()
            for existing in allExisting {
                if levenshteinRatio(hookLower, existing) > 0.8 {
                    return false
                }
            }
            return true
        }
    }

    // MARK: - Pass 2: Claude-Powered Adaptation (Sonnet, cached)

    private func generateAdaptations(
        candidates: [SwipeAdaptationCandidate],
        clientProfile: ClientProfileMetadata?,
        clientName: String,
        existingIdeas: [String]
    ) async -> [AdaptedIdea] {

        let hookExpertise = buildHookExpertisePrompt()
        let userPrompt = buildUserPrompt(
            candidates: candidates,
            clientProfile: clientProfile,
            clientName: clientName,
            existingIdeas: existingIdeas
        )

        do {
            let response = try await ResearchService.shared.generateWithCaching(
                systemBlocks: [
                    (content: hookExpertise, cacheControl: true)
                ],
                messages: [
                    ["role": "user", "content": userPrompt]
                ],
                model: AgentModelTier.strategist.modelId,
                maxTokens: 8192
            )
            return parseAdaptationResponse(response, sourceSwipes: candidates)
        } catch {
            print("⚠️ [SwipeAdaptationEngine] Claude API failed: \(error). Returning empty.")
            return []
        }
    }

    // MARK: - Hook Expertise Prompt (cached across calls)

    private func buildHookExpertisePrompt() -> String {
        return """
        You are a content strategy engine specializing in hook adaptation. Your job is to take proven \
        hook STRUCTURES from a swipe library and adapt them to a specific client's niche, voice, and audience.

        HOOK TYPE REFERENCE (14 types):
        - curiosityGap: Creates information gap the viewer needs to close. "The one thing most [X] get wrong about [Y]"
        - boldClaim: Provocative statement to arrest attention. "[Unexpected number] in [short time] doing [surprising method]"
        - question: Direct question demanding an answer. "Why does every [audience] struggle with [specific thing]?"
        - story: Personal narrative building relatability. "I was [relatable low point] until [discovery moment]"
        - statistic: Concrete numbers or data. "[Specific number]% of [audience] don't know [valuable insight]"
        - controversy: Inflammatory or contrarian statement. "[Common practice] is actually destroying your [outcome]"
        - contrast: Side-by-side comparison. "[Method A] vs [Method B] — the results shocked me"
        - howTo: Process-driven educational. "How to [desirable outcome] in [specific timeframe] (step by step)"
        - list: Numbered items. "[N] [things] that [outcome] — #[last] changed everything"
        - challenge: Test or experiment format. "I tried [method] for [time period] and here's what happened"
        - hiddenGem: Underrated discovery. "The [tool/method/place] nobody talks about that [impressive result]"
        - contrarian: "Stop doing X / Don't do Y" format. "Stop [common advice]. Do [counterintuitive thing] instead."
        - personal: Vulnerability or honest confession. "I've never told anyone this, but [honest truth about topic]"
        - transformation: Before/after or journey arc. "From [low point] to [high point] in [time] — here's the playbook"

        CRITICAL ADAPTATION RULES:
        1. Extract the PATTERN, never copy the text. "Stop doing X, start doing Y" becomes \
        "Stop [client-relevant mistake], start [client-relevant solution]"
        2. Every adapted hook must pass the COVER TEST — if you hide the hook and read the next \
        line, it should NOT make sense without the hook. The hook must create an open loop.
        3. Every adapted hook must pass the SCROLL TEST — would someone stop scrolling between \
        a cooking video and a dog video to read this?
        4. Maintain the original hook's MECHANISM (curiosity gap, bold claim, contrast, etc.) \
        while transplanting it to the client's world.
        5. Reference the client's specific data points, methods, stories, and audience language — \
        never generic placeholders like "[your niche]" or "[your product]".
        6. Hook-ability: must fit in under 15 words for reels/shorts, under 80 characters for carousels.
        7. Emotional charge: neutral = dead. Every hook must trigger curiosity, fear, desire, or awe.
        8. Angle uniqueness: if the adaptation sounds like every other post in the niche, try harder.

        EMOTIONAL SEQUENCING (for ideaBody):
        Map a 4-beat emotional arc: Tension (cortisol) → Relatability (oxytocin) → Insight (dopamine) → CTA (serotonin)

        IDEA EVALUATION (mental checklist before including):
        - TAM: Does this reach a large enough audience segment?
        - Hook-ability: Can it be compressed to a compelling <15 word hook?
        - Authority Match: Does the client have credibility to say this?
        - Emotional Charge: Does it trigger a visceral reaction?
        - Angle Uniqueness: Is this a fresh take, not a rehash?
        If any criterion scores below 3/10, skip the candidate.
        """
    }

    // MARK: - User Prompt (Pass 2)

    private func buildUserPrompt(
        candidates: [SwipeAdaptationCandidate],
        clientProfile: ClientProfileMetadata?,
        clientName: String,
        existingIdeas: [String]
    ) -> String {
        var sections: [String] = []

        // Client profile section
        var clientSection = "CLIENT PROFILE:\nName: \(clientName)"
        if let meta = clientProfile {
            if let niche = meta.niche ?? meta.industry { clientSection += "\nNiche: \(niche)" }
            if let brandStory = meta.brandStory, !brandStory.isEmpty { clientSection += "\nBrand Story: \(String(brandStory.prefix(300)))" }
            if let uniqueAngle = meta.uniqueAngle, !uniqueAngle.isEmpty { clientSection += "\nUnique Angle: \(uniqueAngle)" }
            if let voiceNotes = meta.voiceNotes, !voiceNotes.isEmpty { clientSection += "\nVoice: \(String(voiceNotes.prefix(200)))" }
            if let coreBeliefs = meta.coreBeliefs, !coreBeliefs.isEmpty { clientSection += "\nCore Beliefs: \(coreBeliefs.joined(separator: ", "))" }
            if let targetAudience = meta.targetAudience, !targetAudience.isEmpty { clientSection += "\nTarget Audience: \(targetAudience)" }
            if let signaturePhrases = meta.signaturePhrases, !signaturePhrases.isEmpty { clientSection += "\nSignature Phrases: \(signaturePhrases.joined(separator: ", "))" }

            if let audienceModel = meta.intelligenceModel?.audienceModel {
                if !audienceModel.topPainPoints.isEmpty {
                    clientSection += "\nAudience Pain Points: \(audienceModel.topPainPoints.joined(separator: "; "))"
                }
                if !audienceModel.aspirationalOutcomes.isEmpty {
                    clientSection += "\nAspirational Outcomes: \(audienceModel.aspirationalOutcomes.joined(separator: "; "))"
                }
                if !audienceModel.commonObjections.isEmpty {
                    clientSection += "\nCommon Objections: \(audienceModel.commonObjections.joined(separator: "; "))"
                }
            }

            // Top-performing post excerpts (so Claude understands what already works)
            if let topPosts = meta.topPerformingPosts, !topPosts.isEmpty {
                clientSection += "\n\nTOP-PERFORMING POSTS (what already works for this client):"
                for (i, post) in topPosts.prefix(3).enumerated() {
                    clientSection += "\n\(i + 1). \(String(post.transcript.prefix(200)))"
                }
            } else if let transcripts = meta.topPerformingTranscripts, !transcripts.isEmpty {
                clientSection += "\n\nTOP-PERFORMING POSTS:"
                for (i, t) in transcripts.prefix(3).enumerated() {
                    clientSection += "\n\(i + 1). \(String(t.prefix(200)))"
                }
            }
        } else {
            clientSection += "\nNote: Client profile is sparse. Adapt hooks based on general viral patterns and the client name as niche context."
        }
        sections.append(clientSection)

        // Existing ideas to avoid
        if !existingIdeas.isEmpty {
            let avoidList = existingIdeas.prefix(10).map { "- \($0)" }.joined(separator: "\n")
            sections.append("HOOKS TO ALREADY AVOID (client already has ideas covering these):\n\(avoidList)")
        }

        // Swipe candidates with full body excerpts
        var candidateSection = "SWIPE CANDIDATES TO ADAPT:"
        for (i, c) in candidates.enumerated() {
            candidateSection += "\n\n#\(i + 1). \"\(c.title)\""
            if let hookText = c.hookText, hookText != c.title {
                candidateSection += "\n   Hook: \"\(hookText)\""
            }
            if let hookType = c.hookType { candidateSection += "\n   Type: \(hookType.rawValue)" }
            if let framework = c.frameworkType { candidateSection += "\n   Framework: \(framework.rawValue)" }
            if let emotion = c.dominantEmotion { candidateSection += "\n   Emotion: \(emotion.rawValue)" }
            if let body = c.fullBody, !body.isEmpty {
                let excerpt = String(body.prefix(300))
                candidateSection += "\n   Body excerpt: \"\(excerpt)\""
            }
            if let reason = c.screeningReason {
                candidateSection += "\n   Screening reason: \"\(reason)\""
            }
        }
        sections.append(candidateSection)

        // Output format
        sections.append("""
        For each candidate above, generate an adapted idea for \(clientName). Return ONLY valid JSON:
        {
          "adaptedIdeas": [
            {
              "sourceIndex": 1,
              "adaptedHook": "The actual adapted hook text for this client",
              "ideaTitle": "Short title for the idea (3-8 words)",
              "ideaBody": "2-3 sentence expansion. Map a 4-beat arc: tension → relatability → insight → CTA.",
              "hookType": "curiosityGap",
              "suggestedFramework": "pas",
              "adaptationReasoning": "One sentence: what structural pattern was borrowed and how it was transplanted",
              "confidence": "high"
            }
          ]
        }

        Valid hookTypes: curiosityGap, boldClaim, question, story, statistic, controversy, contrast, howTo, list, challenge, hiddenGem, contrarian, personal, transformation
        Valid frameworks: aida, pas, bab, escalationArc, storyLoop, listicle, tutorial, caseStudy, interview, beforeAfter, mythBusting, dayInLife
        Confidence: "high" = hook structure maps directly, "medium" = requires creative bridging, "low" = stretch adaptation

        Skip a candidate ONLY if its hook structure genuinely cannot be adapted to this client's niche (and explain why). Generate for ALL others.
        """)

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Response Parsing

    private func parseAdaptationResponse(_ response: String, sourceSwipes: [SwipeAdaptationCandidate]) -> [AdaptedIdea] {
        // Try direct JSON decode
        if let data = response.data(using: .utf8),
           let wrapper = try? JSONDecoder().decode(AdaptationResponseWrapper.self, from: data) {
            return wrapper.adaptedIdeas
        }

        // Regex fallback: extract JSON object from response text
        if let range = response.range(of: #"\{[\s\S]*"adaptedIdeas"[\s\S]*\}"#, options: .regularExpression) {
            let jsonStr = String(response[range])
            if let data = jsonStr.data(using: .utf8),
               let wrapper = try? JSONDecoder().decode(AdaptationResponseWrapper.self, from: data) {
                return wrapper.adaptedIdeas
            }
        }

        // Try extracting just the array
        if let range = response.range(of: #"\[[\s\S]*\]"#, options: .regularExpression) {
            let jsonStr = String(response[range])
            if let data = jsonStr.data(using: .utf8),
               let ideas = try? JSONDecoder().decode([AdaptedIdea].self, from: data) {
                return ideas
            }
        }

        print("⚠️ [SwipeAdaptationEngine] Failed to parse Claude response")
        return []
    }

    // MARK: - Time Filtering

    private func parseTimeFilter(_ filter: String) -> Date? {
        let lower = filter.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let calendar = Calendar.current

        if lower == "today" {
            return calendar.startOfDay(for: now)
        } else if lower == "yesterday" {
            return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
        } else if lower == "this week" {
            return calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))
        } else if lower == "this month" {
            return calendar.date(from: calendar.dateComponents([.year, .month], from: now))
        } else if let match = lower.range(of: #"(\d+)"#, options: .regularExpression),
                  lower.contains("day") || lower.contains("last") {
            let numberStr = String(lower[match])
            if let days = Int(numberStr) {
                return calendar.date(byAdding: .day, value: -days, to: now)
            }
        }
        return nil
    }

    // MARK: - Levenshtein Ratio

    private func levenshteinRatio(_ a: String, _ b: String) -> Double {
        let aChars = Array(a)
        let bChars = Array(b)
        let aLen = aChars.count
        let bLen = bChars.count

        guard aLen > 0 && bLen > 0 else { return 0 }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: bLen + 1), count: aLen + 1)
        for i in 0...aLen { matrix[i][0] = i }
        for j in 0...bLen { matrix[0][j] = j }

        for i in 1...aLen {
            for j in 1...bLen {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }

        let distance = matrix[aLen][bLen]
        let maxLen = max(aLen, bLen)
        return 1.0 - (Double(distance) / Double(maxLen))
    }
}

// MARK: - Response Wrapper

private struct AdaptationResponseWrapper: Codable {
    let adaptedIdeas: [AdaptedIdea]
}

// MARK: - Errors

enum SwipeAdaptationError: LocalizedError {
    case clientNotFound(String)
    case noSwipesFound(String?)

    var errorDescription: String? {
        switch self {
        case .clientNotFound(let name):
            return "No client profile found matching '\(name)'"
        case .noSwipesFound(let filter):
            if let filter = filter {
                return "No swipe files found for time filter '\(filter)'"
            }
            return "No swipe files found in the library"
        }
    }
}
