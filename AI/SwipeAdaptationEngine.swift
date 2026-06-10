// CosmoOS/AI/SwipeAdaptationEngine.swift
// Dedicated engine for adapting swipe hook patterns to specific client niches.
// Two-pass Claude architecture: Haiku screening (Pass 1) → Opus adaptation (Pass 2).

import Foundation

// MARK: - Data Models

struct SwipeAdaptationCandidate {
    let swipeAtomUUID: String
    let title: String
    let hookText: String?
    let slide1Text: String?         // actual first slide content for richer context
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
    var usedFallback: Bool = false   // true if JSON parsing failed and positional fallback was used

    enum CodingKeys: String, CodingKey {
        case selectedIndices, reasoning
    }
}

struct AdaptedIdea: Codable {
    let sourceIndex: Int
    let adaptedHook: String
    let hookVariants: [String]?
    let ideaTitle: String
    let ideaBody: String
    let hookType: String
    let suggestedFramework: String
    let suggestedFormat: String?
    let adaptationReasoning: String
    let whyItWorks: String?
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
    let engineError: String?    // nil = success, non-nil = Pass 1 or 2 failed
}

// MARK: - Engine

@MainActor
final class SwipeAdaptationEngine {
    static let shared = SwipeAdaptationEngine()

    private let atomRepo = AtomRepository.shared

    /// Direct Anthropic model IDs (bypasses OpenRouter)
    private let opusModel = "claude-opus-4-6-20250929"
    private let sonnetModel = "claude-sonnet-4-5-20250514"

    private init() {}

    // MARK: - Direct Anthropic API

    /// Call Anthropic Messages API directly (not via OpenRouter) for higher quality + prompt caching.
    private nonisolated func callAnthropicDirect(
        systemPrompt: String,
        userPrompt: String,
        model: String,
        maxTokens: Int = 8192
    ) async throws -> String {
        guard let apiKey = APIKeys.agentLLM, !apiKey.isEmpty else {
            throw SwipeAdaptationError.noAnthropicKey
        }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": [
                [
                    "type": "text",
                    "text": systemPrompt,
                    "cache_control": ["type": "ephemeral"]
                ] as [String: Any]
            ],
            "messages": [
                ["role": "user", "content": userPrompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SwipeAdaptationError.apiError("Invalid response")
        }
        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SwipeAdaptationError.apiError("Anthropic API \(httpResponse.statusCode): \(errorText)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw SwipeAdaptationError.apiError("Failed to parse Anthropic response")
        }

        return text
    }

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

        // 5a. Provenance-aware exclusion: hooks from published/in-progress content
        let allContent = try await atomRepo.fetchAll(type: .content)
        let clientContent = allContent.filter { atom in
            let meta = atom.metadataDict ?? [:]
            return meta["clientProfileUUID"] as? String == clientAtom.uuid
        }
        let publishedHooks: [String] = clientContent.flatMap { atom in
            let meta = atom.metadataDict ?? [:]
            let hooks = meta["inheritedHooks"] as? [String] ?? []
            let title = atom.title?.lowercased() ?? ""
            let hook = atom.hook?.lowercased() ?? ""
            return hooks.map { $0.lowercased() } + [title, hook].filter { !$0.isEmpty }
        }

        // 5b. Swipe UUIDs already used in content for this client (skip entirely)
        let usedSwipeUUIDs: Set<String> = Set(clientContent.flatMap { atom in
            let meta = atom.metadataDict ?? [:]
            return meta["inheritedSwipeUUIDs"] as? [String] ?? []
        })

        // 5c. In-production/published idea hooks (ideas already acted on)
        let activatedIdeaHooks: [String] = allIdeas
            .filter { $0.ideaClientUUID == clientAtom.uuid }
            .filter { $0.ideaStatus == .inProduction || $0.ideaStatus == .published }
            .compactMap { $0.hook?.lowercased() }

        // 5d. Filter out swipes already used in content for this client
        swipes = swipes.filter { !usedSwipeUUIDs.contains($0.uuid) }

        // 5e. Extract top-performer first lines for deduplication
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

        // 6. STAGE 0: Mechanical pre-filter + format for screening
        let compactSwipes: [(index: Int, atom: Atom, display: String)] = swipes.enumerated().compactMap { idx, atom in
            let slide1 = atom.swipeAnalysis?.transcriptSlides?.first?.text
            let hookDisplay = slide1 ?? atom.hook ?? atom.title ?? ""
            let truncatedHook = String(hookDisplay.prefix(150))
            guard !truncatedHook.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            // Pre-filter: keep unscored swipes but filter out low scores
            let hookScore = atom.swipeAnalysis?.hookScore ?? -1
            if hookScore >= 0 && hookScore < 3 { return nil }
            let analysis = atom.swipeAnalysis
            let hookType = analysis?.hookType?.rawValue ?? "unknown"
            return (index: idx, atom: atom, display: "#\(idx + 1). \"\(truncatedHook)\" [\(hookType)]")
        }
        print("[SwipeAdaptationEngine] \(swipes.count) swipes → \(compactSwipes.count) after mechanical filter")

        guard !compactSwipes.isEmpty else {
            return SwipeAdaptationResult(
                clientName: resolvedName,
                clientUUID: clientAtom.uuid,
                totalSwipesScanned: swipes.count,
                candidatesEvaluated: 0,
                adaptedIdeas: [],
                sourceSwipes: [],
                timeFilter: timeFilter,
                engineError: nil
            )
        }

        // 7. Pass 1: Claude screens entire library (Haiku)
        var engineError: String? = nil
        let maxCandidates = min(max(maxResults * 3, 20), 30)
        let screeningResult = try await screenCandidates(
            compactSwipes: compactSwipes,
            clientProfile: clientMeta,
            clientName: resolvedName,
            maxCandidates: maxCandidates,
            topPerformerFirstLines: topPerformerFirstLines
        )

        // Track if screening fell back to positional selection
        if screeningResult.usedFallback {
            engineError = "Pass 1 screening fell back to positional selection (Haiku response was unparseable)"
        }

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
                slide1Text: analysis?.transcriptSlides?.first?.text ?? atom.hook,
                hookType: analysis?.hookType,
                frameworkType: analysis?.frameworkType,
                dominantEmotion: analysis?.dominantEmotion,
                platform: metaDict["contentSource"] as? String,
                fullBody: atom.body,
                screeningReason: reason
            )
        }

        // 9. Deduplicate against existing ideas + top performers + published hooks
        let allExclusionHooks = existingIdeaTitles + topPerformerFirstLines + publishedHooks + activatedIdeaHooks
        let deduplicated = deduplicateAgainstExisting(
            candidates: selectedCandidates,
            existingIdeaTitles: allExclusionHooks,
            topPerformerFirstLines: []
        )

        guard !deduplicated.isEmpty else {
            return SwipeAdaptationResult(
                clientName: resolvedName,
                clientUUID: clientAtom.uuid,
                totalSwipesScanned: swipes.count,
                candidatesEvaluated: selectedCandidates.count,
                adaptedIdeas: [],
                sourceSwipes: [],
                timeFilter: timeFilter,
                engineError: engineError
            )
        }

        // 10. Pass 2: Claude generates adapted ideas (Opus, with prompt caching)
        let adaptationResult = await generateAdaptations(
            candidates: deduplicated,
            clientProfile: clientMeta,
            clientName: resolvedName,
            existingIdeas: allExclusionHooks,
            topPerformerFirstLines: [],
            publishedHooks: publishedHooks,
            maxResults: maxResults
        )

        // Thread Pass 2 error (takes priority over Pass 1 fallback warning)
        if let pass2Error = adaptationResult.error {
            engineError = pass2Error
        }

        // 11. Post-adaptation dedup: remove generated ideas too similar to existing/published content
        let dedupedIdeas = deduplicateAdaptedIdeas(
            adaptationResult.ideas,
            existingIdeaTitles: allExclusionHooks,
            topPerformerFirstLines: []
        )

        // 12. Trim to requested maxResults
        let finalIdeas = Array(dedupedIdeas.prefix(maxResults))

        return SwipeAdaptationResult(
            clientName: resolvedName,
            clientUUID: clientAtom.uuid,
            totalSwipesScanned: swipes.count,
            candidatesEvaluated: deduplicated.count,
            adaptedIdeas: finalIdeas,
            sourceSwipes: deduplicated,
            timeFilter: timeFilter,
            engineError: engineError
        )
    }

    // MARK: - Pass 1: Sonnet Structural Mechanism Screening

    private func screenCandidates(
        compactSwipes: [(index: Int, atom: Atom, display: String)],
        clientProfile: ClientProfileMetadata?,
        clientName: String,
        maxCandidates: Int,
        topPerformerFirstLines: [String] = []
    ) async throws -> ScreeningResult {

        let userPrompt = buildScreeningUserPrompt(
            compactSwipes: compactSwipes,
            clientProfile: clientProfile,
            clientName: clientName,
            maxCandidates: maxCandidates,
            topPerformerFirstLines: topPerformerFirstLines
        )

        // Use Sonnet via direct Anthropic (structural reasoning requires real intelligence)
        let response = try await callAnthropicDirect(
            systemPrompt: Self.screeningExpertise,
            userPrompt: userPrompt,
            model: sonnetModel,
            maxTokens: 4096
        )

        return parseScreeningResponse(response, swipeCount: compactSwipes.count)
    }

    /// Deep structural mechanism analysis prompt for screening (cached via Anthropic prompt caching)
    static let screeningExpertise: String = """
    You are a structural hook analyst. Your job is to find hooks whose ABSTRACT MECHANISM \
    transfers to a different niche — even when the surface words have zero topical overlap.

    You do NOT look for topic similarity. You look for PSYCHOLOGICAL MACHINERY.

    THE NOUN-SWAP TEST:
    Take any hook. Replace every topic-specific word with the client's equivalent. \
    If the hook still creates the same emotional pull, it's a structural match.

    Example: "The one foreclosure trick banks don't want you to know"
    Mechanism: [curiosity gap] + [authority gatekeeper challenge] + [insider secret]
    Noun-swap for fitness: "The one recovery technique physical therapists don't want you to know"
    → PASSES. Same curiosity gap, same authority challenge, completely different niche.

    MECHANISM TAXONOMY — how to decode any hook:

    OPEN LOOP: Creates an information gap that demands closure.
      → "I stopped doing [common practice] and this happened..."

    IDENTITY VALIDATION: Tells the audience "you're not broken, society is."
      → "How to disappoint society as a woman in her 30s"
      → Noun-swap: "How to ruin your 20s according to society" — same mechanism, different demo.

    AUTHORITY CHALLENGE: Creates insider knowledge by naming a gatekeeper.
      → "[Industry experts] don't want you to know..."

    STATUS THREAT: Makes the audience question their current approach.
      → "If you're still [common practice], you're leaving [result] on the table"

    SPECIFICITY SURPRISE: A precise number where you'd expect vague claims.
      → "$47K in 11 days" / "3 calls from one DM template"

    TEMPORAL URGENCY: Frames knowledge as time-sensitive or age-sensitive.
      → "What I wish I knew at 20" / "Before you turn 30, do this"

    SOCIAL PROOF INVERSION: Flips what "most people" do against what winners do.
      → "95% of people do X. The top 1% do Y instead."

    VULNERABILITY CONFESSION: Earns trust through honest admission.
      → "I've never told anyone this, but..." / "My biggest failure was..."

    CONTRARIAN REFRAME: Takes a commonly accepted belief and inverts it.
      → "Stop [widely recommended practice]" / "[Popular advice] is actually hurting you"

    CROSS-NICHE TRANSFER EXAMPLES:

    1. IDENTITY VALIDATION across demographics:
      Source: "How to disappoint society as a woman in her 30s" [women's empowerment]
      Transfer: "How to ruin your 20s according to society" [men's philosophy]
      Why: Both audiences define identity AGAINST mainstream expectations.

    2. AUTHORITY CHALLENGE across industries:
      Source: "The one foreclosure trick banks don't want you to know" [real estate]
      Transfer: "The one recovery technique PTs don't want you to know" [fitness]
      Why: Both niches have trusted authorities the audience suspects of withholding.

    3. VULNERABILITY CONFESSION across contexts:
      Source: "I lost $200K in 6 months. Here's what nobody warned me about." [finance]
      Transfer: "I wasted 3 years in the wrong relationship. Here's what nobody warned me." [dating]
      Why: Specific loss creates empathy. "Nobody warned me" creates curiosity.

    4. SPECIFICITY SURPRISE across niches:
      Source: "How I went from $0 to $10K/month in 90 days selling digital products" [e-commerce]
      Transfer: "How I went from 0 to 10K followers in 90 days without posting reels" [social media]
      Why: Specific numbers + impossible-seeming timeframe. Topic doesn't matter.

    5. CONTRARIAN REFRAME across fields:
      Source: "Stop stretching before workouts. Here's what to do instead." [fitness]
      Transfer: "Stop posting every day. Here's what to do instead." [content creation]
      Why: "Stop doing what everyone tells you" triggers curiosity in any field.

    TRANSFERABILITY: HIGH = universal emotions, mechanism is the star not the topic. \
    MEDIUM = industry jargon swappable with creative bridging. \
    LOW = depends on specific event/celebrity, topic IS the mechanism. Skip LOW.

    PROCESS: (1) identify abstract mechanism, (2) apply noun-swap test, \
    (3) check if psychological pull survives, (4) evaluate audience fit, (5) consider format.

    Select hooks where the MECHANISM transfers, even if every surface word is different.
    """

    private func buildScreeningUserPrompt(
        compactSwipes: [(index: Int, atom: Atom, display: String)],
        clientProfile: ClientProfileMetadata?,
        clientName: String,
        maxCandidates: Int,
        topPerformerFirstLines: [String] = []
    ) -> String {
        var sections: [String] = []

        // Client context with audience model
        var clientSection = "CLIENT: \(clientName)"
        if let meta = clientProfile {
            if let niche = meta.niche ?? meta.industry { clientSection += " — \(niche)" }
            if let targetAudience = meta.targetAudience, !targetAudience.isEmpty {
                clientSection += "\nAudience: \(targetAudience)"
            }
            if let audienceModel = meta.intelligenceModel?.audienceModel {
                if !audienceModel.topPainPoints.isEmpty {
                    clientSection += "\nAudience pain points: \(audienceModel.topPainPoints.joined(separator: "; "))"
                }
                if !audienceModel.aspirationalOutcomes.isEmpty {
                    clientSection += "\nAudience aspirations: \(audienceModel.aspirationalOutcomes.joined(separator: "; "))"
                }
            }
        }

        // Best performing hook first-lines (few-shot for mechanism matching)
        if !topPerformerFirstLines.isEmpty {
            clientSection += "\n\nHooks that ALREADY work for this client (find MORE with these same MECHANISMS):"
            for h in topPerformerFirstLines.prefix(5) {
                clientSection += "\n- \"\(h)\""
            }
        }
        sections.append(clientSection)

        // Swipe list
        let swipeList = compactSwipes.map { $0.display }.joined(separator: "\n")
        sections.append("SWIPE LIBRARY (\(compactSwipes.count) swipes):\n\(swipeList)")

        // Instructions
        sections.append("""
        Select the top \(maxCandidates) hooks whose abstract MECHANISM transfers to this client's niche. \
        Apply the noun-swap test for each. The best finds are the non-obvious ones — hooks from \
        distant niches that share deep structural DNA with the client's audience.

        Return ONLY valid JSON:
        {"selectedIndices": [3, 7, 12], "reasoning": ["mechanism: identity validation — noun-swap works", "mechanism: authority challenge — gatekeeper parallel exists", "mechanism: contrarian reframe — conventional wisdom to challenge"]}

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
        var fallbackResult = ScreeningResult(
            selectedIndices: Array(1...fallbackCount),
            reasoning: nil
        )
        fallbackResult.usedFallback = true
        return fallbackResult
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

    /// Post-adaptation dedup: removes generated ideas that are too similar to existing content.
    /// Uses a lower threshold (0.6) than pre-adaptation dedup (0.8) since we're comparing
    /// generated text against reference text.
    private func deduplicateAdaptedIdeas(
        _ ideas: [AdaptedIdea],
        existingIdeaTitles: [String],
        topPerformerFirstLines: [String]
    ) -> [AdaptedIdea] {
        let allExisting = existingIdeaTitles + topPerformerFirstLines
        guard !allExisting.isEmpty else { return ideas }

        return ideas.filter { idea in
            let hookLower = idea.adaptedHook.lowercased()
            let titleLower = idea.ideaTitle.lowercased()
            for existing in allExisting {
                if levenshteinRatio(hookLower, existing) > 0.6 {
                    print("⚠️ [SwipeAdaptationEngine] Post-dedup removed idea (hook too similar): \(idea.ideaTitle)")
                    return false
                }
                if levenshteinRatio(titleLower, existing) > 0.6 {
                    print("⚠️ [SwipeAdaptationEngine] Post-dedup removed idea (title too similar): \(idea.ideaTitle)")
                    return false
                }
            }
            return true
        }
    }

    // MARK: - Pass 2: Claude-Powered Adaptation (Opus, cached)

    private func generateAdaptations(
        candidates: [SwipeAdaptationCandidate],
        clientProfile: ClientProfileMetadata?,
        clientName: String,
        existingIdeas: [String],
        topPerformerFirstLines: [String] = [],
        publishedHooks: [String] = [],
        maxResults: Int = 10
    ) async -> (ideas: [AdaptedIdea], error: String?) {

        let hookExpertise = buildHookExpertisePrompt()
        let userPrompt = buildUserPrompt(
            candidates: candidates,
            clientProfile: clientProfile,
            clientName: clientName,
            existingIdeas: existingIdeas,
            topPerformerFirstLines: topPerformerFirstLines,
            publishedHooks: publishedHooks,
            maxResults: maxResults
        )

        do {
            let response = try await callAnthropicDirect(
                systemPrompt: hookExpertise,
                userPrompt: userPrompt,
                model: opusModel,
                maxTokens: 8192
            )
            return (ideas: parseAdaptationResponse(response, sourceSwipes: candidates), error: nil)
        } catch {
            print("⚠️ [SwipeAdaptationEngine] Pass 2 failed: \(error)")
            return (ideas: [], error: "Pass 2 API failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Hook Expertise Prompt (cached across calls)

    static let sharedHookExpertise: String = """
    You are a content strategy engine inside CosmoOS. You extract proven hook STRUCTURES \
    from a swipe file library and adapt them to a specific client's niche, voice, and audience. \
    You deliver complete, ready-to-use hooks — not templates or placeholders.

    ═══════════════════════════════════════════════
    SECTION 1: HOOK CRAFT
    ═══════════════════════════════════════════════

    Process: Generate 5 variants per idea. Never use first instinct. Read each aloud — if it \
    doesn't flow naturally in under 3 seconds (for short-form) or feel compelling as a thread \
    opener (for long-form), cut and rewrite.

    Tests (EVERY hook must pass ALL of these):

    COVER TEST: Hide the hook and read what follows. If what follows makes sense on its own, \
    the hook isn't creating an open loop. FAIL → the hook needs to create an information gap \
    that the content closes.

    SCROLL TEST: Would this stop someone between a cooking video and a dog video? If not, \
    add tension, specificity, or surprise. A hook that blends in is invisible.

    DINNER TABLE TEST: Read the hook aloud as if saying it to a friend at dinner. If it sounds \
    like a caption, thesis, marketing line, or "content" — it fails. Common failures:
    - Thesis statements: "A high income didn't mean a good life" → FAILS. \
    Say: "Sure we made more money, but we were still working 80 hour weeks"
    - Caption voice: "We chose freedom." → FAILS. Too polished, not speech.
    - Corporate phrasing: "leveraged our experience" → FAILS.
    - Triple-comma lists: stacking 3 rhetorical items = copywriting, not speech. Say ONE with feeling.

    Rules:
    - Hook = open loop. Reader must continue to close it.
    - Specific > vague. "$47K in 11 days" beats "How I grew my business."
    - Hook = promise. "3 mistakes" → deliver exactly 3. Bait-and-switch kills trust.
    - Hook IS the first line. Must make you want the next line.
    - Compare structure (not words) to client's highest-performing hooks. Match their mechanism.

    ═══════════════════════════════════════════════
    SECTION 2: HOOK TYPE REFERENCE (14 types)
    ═══════════════════════════════════════════════

    - curiosityGap: Information gap the viewer needs to close. "The one thing most [X] get wrong about [Y]"
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

    ═══════════════════════════════════════════════
    SECTION 3: ADAPTATION METHODOLOGY
    ═══════════════════════════════════════════════

    BEAT PATTERNS (choose the right one for the format):
    Every piece follows a structural beat pattern. The hook is the first beat.
    Beat types: HOOK → CONTEXT → TENSION → INSIGHT → PROOF → EXPANSION → TRANSITION → CTA
    - Short reel (15-30s): HOOK → INSIGHT → CTA
    - Long reel (30-90s): HOOK → CONTEXT → TENSION → INSIGHT → CTA
    - Carousel (5-15 slides): HOOK → CONTEXT → TENSION → INSIGHT → PROOF → CTA
    - Thread (4-12 tweets): HOOK → CONTEXT → TENSION → INSIGHT → PROOF → EXPANSION → CTA
    - LinkedIn: HOOK → CONTEXT → INSIGHT → PROOF → EXPANSION → CTA

    When suggesting a framework for each idea, map the swipe's beat structure to the best \
    format for this client. The hook must fit the format's natural rhythm.

    ADAPTATION RULES:
    1. Extract the PATTERN, never copy the text. "The one foreclosure trick banks don't want \
    you to know" → for fitness: "The one recovery technique physical therapists don't want \
    you to know". The curiosity gap + authority challenge STRUCTURE transfers.
    2. Every adapted hook must pass Cover + Scroll + Dinner Table tests.
    3. Maintain the original hook's MECHANISM while transplanting to client's world.
    4. Reference the client's specific data, methods, stories, and audience language — \
    never generic placeholders like "[your niche]" or "[your product]".
    5. Match voice to client's actual voice — study their best performing content for \
    sentence length, formality, signature phrases, and absences (what they DON'T use \
    matters as much as what they do).

    FORMAT-AWARE HOOK CONSTRAINTS:
    - Reel/Short hooks: Must be speakable in <3 seconds. Max ~15 words.
    - Carousel hooks: Max ~80 characters. Must work as text on an image.
    - Thread hooks: Can be longer — up to 280 characters. Must earn the click to read \
    the full thread. Threads allow more setup and context in the hook.
    - LinkedIn hooks: First 3 lines visible before "see more". ~200 chars to earn the click.
    - Newsletter subject lines: Max 50 characters. Curiosity-first.

    VOICE MATCHING (The Absorption Method):
    Before adapting: Study the client's best performing content. Notice:
    - Sentence length: 5-8 word fragments or 15-20 word flowing sentences?
    - Formality: "I" or "we"? Contractions? Casual asides?
    - Signature patterns: "Look..." / "Here's the thing..." / emojis / "..." between thoughts?
    - Absences: No rhetorical questions? No exclamation marks? Absences define voice too.

    Same-person test: Read the client's actual post, then your hook variant. Must sound like \
    the same person, same day. If yours sounds smarter or more polished — it's wrong.

    ═══════════════════════════════════════════════
    SECTION 4: IDEA EVALUATION (Score each 1-10)
    ═══════════════════════════════════════════════

    Before including ANY idea, evaluate against these 6 criteria. \
    Minimum 40/60 total. No single criterion below 3/10. If it fails, skip the candidate.

    1. TAM: Does this reach a large enough audience segment for this client?
    2. Hook-ability: Can the core insight be compressed into a compelling hook that passes all 3 tests?
    3. Authority Match: Does the client have real credibility and experience to say this?
    4. Emotional Charge: Does it trigger a visceral reaction? Neutral = dead.
    5. Angle Uniqueness: Is this a fresh take this client hasn't covered?
    6. Trend Timing: Does this tap a current cultural moment, industry shift, or seasonal relevance?

    ═══════════════════════════════════════════════
    SECTION 5: VOICE DNA (MANDATORY)
    ═══════════════════════════════════════════════

    WRITING RULES:
    - Write like a sharp human, not a language model.
    - Use contractions naturally (don't, can't, won't).
    - Get to the point. No throat-clearing, no preamble.
    - If making a claim, be specific. Use numbers, names, concrete details.
    - Vary sentence length. Mix short punchy lines with longer ones.
    - Use physical verbs: "sanded down" not "improved," "bolted on" not "added."

    BANNED PHRASES (if even ONE appears, the output fails):
    Dead AI: "In today's [anything]", "It's important to note", "Delve", "Dive into", \
    "Unpack", "Harness", "Leverage", "Utilize", "Landscape", "Realm", "Robust", \
    "Game-changer", "Cutting-edge", "Straightforward", "In order to".
    Dead transitions: "Furthermore", "Additionally", "Moreover", "Moving forward", \
    "At the end of the day", "To put this in perspective", "In other words".
    Engagement bait: "Let that sink in", "Read that again", "Full stop", \
    "This changes everything", "Are you paying attention?", "You're not ready for this".
    AI cringe: "Supercharge", "Unlock", "Future-proof", "10x your productivity".
    Generic insider claims: "Here's the part nobody's talking about", \
    "What nobody tells you", anything with "nobody" or "most people don't realize".
    FATAL: "This isn't X. This is Y." and ALL variations — delete the negation, state the positive claim.

    ═══════════════════════════════════════════════
    SECTION 6: 5-VARIANT STRATEGY
    ═══════════════════════════════════════════════

    For each idea, generate exactly 5 hook variants spanning different emotional registers:
    - Variant 1: Most punchy, scroll-stopping version (also used as adaptedHook).
    - Variant 2: Curiosity-driven — create the strongest possible open loop.
    - Variant 3: Story/personal angle — lead with a relatable moment or confession.
    - Variant 4: Data/proof-driven — lead with a specific number, stat, or result.
    - Variant 5: Contrarian/unexpected — challenge conventional wisdom or flip expectations.

    Each variant must:
    - Use the same underlying content idea but different entry point
    - Pass all 3 tests (Cover, Scroll, Dinner Table)
    - Match the client's voice (sentence length, formality, signature patterns)
    - Contain zero banned phrases
    - Be format-appropriate (respect hook length constraints for the suggested format)
    """

    private func buildHookExpertisePrompt() -> String {
        return Self.sharedHookExpertise
    }

    // MARK: - User Prompt (Pass 2)

    private func buildUserPrompt(
        candidates: [SwipeAdaptationCandidate],
        clientProfile: ClientProfileMetadata?,
        clientName: String,
        existingIdeas: [String],
        topPerformerFirstLines: [String] = [],
        publishedHooks: [String] = [],
        maxResults: Int = 10
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

            // Voice fingerprint targets (from intelligence model)
            if let voiceFingerprint = meta.intelligenceModel?.voiceFingerprint {
                let avgLen = voiceFingerprint.avgSentenceLength
                if avgLen > 0 {
                    clientSection += "\nVoice Target — Sentence length: \(Int(avgLen * 0.7))-\(Int(avgLen * 1.3)) words"
                }
                if !voiceFingerprint.ctaPattern.isEmpty {
                    clientSection += "\nCTA Style: \(voiceFingerprint.ctaPattern)"
                }
                if !voiceFingerprint.formattingQuirks.isEmpty {
                    clientSection += "\nStyle Markers: \(voiceFingerprint.formattingQuirks.joined(separator: ", "))"
                }
                if !voiceFingerprint.powerWords.isEmpty {
                    clientSection += "\nPower Words: \(voiceFingerprint.powerWords.prefix(10).joined(separator: ", "))"
                }
            }

            if let bestFormats = meta.bestFormats, !bestFormats.isEmpty {
                clientSection += "\nBest Formats: \(bestFormats.joined(separator: ", "))"
            }

            // Full best performing post transcripts (content IS the signal — study these)
            if let topPosts = meta.topPerformingPosts, !topPosts.isEmpty {
                clientSection += "\n\nBEST PERFORMING CONTENT (study these — they define what works for this client):"
                for (i, post) in topPosts.prefix(5).enumerated() {
                    clientSection += "\n\n[\(i + 1)] \(post.transcript)"
                }
            } else if let transcripts = meta.topPerformingTranscripts, !transcripts.isEmpty {
                clientSection += "\n\nBEST PERFORMING CONTENT:"
                for (i, t) in transcripts.prefix(5).enumerated() {
                    clientSection += "\n\n[\(i + 1)] \(t)"
                }
            }
        } else {
            clientSection += "\nNote: Client profile is sparse. Adapt hooks based on general viral patterns and the client name as niche context."
        }
        sections.append(clientSection)

        // Angles to avoid (existing ideas + top performer first lines)
        let allAvoidanceItems = existingIdeas.prefix(10) + topPerformerFirstLines.prefix(10)
        if !allAvoidanceItems.isEmpty {
            let avoidList = allAvoidanceItems.map { "- \($0)" }.joined(separator: "\n")
            sections.append("""
            ANGLES TO AVOID — The client already has proven content covering these. Generate FRESH angles only:
            \(avoidList)

            Do NOT generate ideas that cover the same angle, theme, or narrative framing as the \
            items above, even with different wording. The user wants NEW angles they haven't explored.
            """)
        }

        // Published hooks (provenance-aware dedup)
        if !publishedHooks.isEmpty {
            let hookList = publishedHooks.prefix(15).map { "- \"\($0)\"" }.joined(separator: "\n")
            sections.append("""
            HOOKS ALREADY PUBLISHED OR IN PRODUCTION (do NOT regenerate these patterns):
            \(hookList)
            These hooks have already been written and published. Generate FRESH structural adaptations only.
            """)
        }

        // Swipe candidates with full body excerpts
        var candidateSection = "SWIPE CANDIDATES TO ADAPT:"
        for (i, c) in candidates.enumerated() {
            candidateSection += "\n\n#\(i + 1). \"\(c.title)\""
            if let slide1 = c.slide1Text, !slide1.isEmpty, slide1 != c.title {
                candidateSection += "\n   Slide 1: \"\(slide1)\""
            }
            if let hookText = c.hookText, hookText != c.title, hookText != c.slide1Text {
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
              "adaptedHook": "The most scroll-stopping variant (primary pick)",
              "hookVariants": [
                "Variant 1: punchy/scroll-stopping",
                "Variant 2: curiosity-driven",
                "Variant 3: story/personal angle",
                "Variant 4: data/proof-driven",
                "Variant 5: contrarian/unexpected"
              ],
              "ideaTitle": "Short title (3-8 words)",
              "ideaBody": "2-3 sentence expansion describing the content angle and key beats.",
              "hookType": "curiosityGap",
              "suggestedFramework": "pas",
              "suggestedFormat": "carousel",
              "adaptationReasoning": "What structural pattern was borrowed and how it transfers",
              "whyItWorks": "Why this resonates with \(clientName)'s audience — reference their pain points, aspirations, or voice",
              "confidence": "high"
            }
          ]
        }

        MANDATORY CHECKS:
        - Every hook must pass Cover + Scroll + Dinner Table tests
        - Every hook must use the client's actual voice from BEST PERFORMING CONTENT
        - Zero banned phrases in any hook
        - Hook length matches suggestedFormat constraints (see FORMAT-AWARE HOOK CONSTRAINTS)
        - Each idea scores 40+ across the 6 evaluation criteria

        Generate exactly \(maxResults) ideas, ranked by LEVERAGE (highest viral potential first). \
        Skip candidates only if their hook mechanism genuinely cannot transfer (explain why).

        Valid hookTypes: curiosityGap, boldClaim, question, story, statistic, controversy, contrast, howTo, list, challenge, hiddenGem, contrarian, personal, transformation
        Valid frameworks: aida, pas, bab, escalationArc, storyLoop, listicle, tutorial, caseStudy, interview, beforeAfter, mythBusting, dayInLife
        Valid formats: carousel, reel, thread, linkedinPost, newsletter, youtubeShort
        Confidence: "high" = hook structure maps directly, "medium" = creative bridging, "low" = stretch adaptation
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

    // MARK: - Single-Swipe Auto-Adaptation (per client)

    /// Generate hook adaptations for a single swipe across all active client profiles.
    /// Called automatically after swipe processing completes.
    func generateAdaptationsForSwipe(swipeAtom: Atom) async {
        // 1. Extract swipe hook text
        let slide1 = swipeAtom.swipeAnalysis?.transcriptSlides?.first?.text
        let hookText = slide1 ?? swipeAtom.hook ?? swipeAtom.title ?? ""
        guard !hookText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[SwipeAdaptationEngine] Skipping auto-adaptation: no hook text for \(swipeAtom.uuid)")
            return
        }

        // 2. Load all active client profiles
        let allAtoms = try? await atomRepo.fetchAll(type: .clientProfile)
        let activeClients: [(atom: Atom, meta: ClientProfileMetadata)] = (allAtoms ?? []).compactMap { atom in
            guard let meta = atom.metadataValue(as: ClientProfileMetadata.self),
                  meta.activeStatus == true else { return nil }
            return (atom: atom, meta: meta)
        }
        guard !activeClients.isEmpty else { return }

        // 3. Check provenance: skip clients where this swipe already produced content
        let allContent = try? await atomRepo.fetchAll(type: .content)
        let clientsToSkip: Set<String> = Set((allContent ?? []).compactMap { content in
            let meta = content.metadataDict ?? [:]
            let swipeUUIDs = meta["inheritedSwipeUUIDs"] as? [String] ?? []
            if swipeUUIDs.contains(swipeAtom.uuid) {
                return meta["clientProfileUUID"] as? String
            }
            return nil
        })
        let eligibleClients = activeClients.filter { !clientsToSkip.contains($0.atom.uuid) }
        guard !eligibleClients.isEmpty else { return }

        // 4. Build prompt
        let analysis = swipeAtom.swipeAnalysis
        var swipeContext = "SWIPE TO ADAPT:"
        swipeContext += "\nSlide 1: \"\(String(hookText.prefix(300)))\""
        if let hookType = analysis?.hookType { swipeContext += "\nHook Type: \(hookType.rawValue)" }
        if let framework = analysis?.frameworkType { swipeContext += "\nFramework: \(framework.rawValue)" }
        if let body = swipeAtom.body, !body.isEmpty {
            swipeContext += "\nFull transcript: \"\(String(body.prefix(500)))\""
        }

        var clientList = "CLIENTS:"
        for (i, client) in eligibleClients.enumerated() {
            let m = client.meta
            clientList += "\n\n\(i + 1). \(m.clientName)"
            if let niche = m.niche ?? m.industry { clientList += " — \(niche)" }
            if let audience = m.targetAudience { clientList += "\n   Audience: \(audience)" }
            if let voice = m.voiceNotes { clientList += "\n   Voice: \(String(voice.prefix(150)))" }
            if let phrases = m.signaturePhrases, !phrases.isEmpty {
                clientList += "\n   Signature phrases: \(phrases.joined(separator: ", "))"
            }
            // Best performing content (compact for single-swipe)
            if let topPosts = m.topPerformingPosts, !topPosts.isEmpty {
                clientList += "\n   Best performing:"
                for (j, post) in topPosts.prefix(3).enumerated() {
                    clientList += "\n   [\(j + 1)] \(String(post.transcript.prefix(300)))"
                }
            } else if let transcripts = m.topPerformingTranscripts, !transcripts.isEmpty {
                clientList += "\n   Best performing:"
                for (j, t) in transcripts.prefix(3).enumerated() {
                    clientList += "\n   [\(j + 1)] \(String(t.prefix(300)))"
                }
            }
        }

        let userPrompt = """
        \(swipeContext)

        \(clientList)

        For each client where this swipe's hook structure is adaptable (relevance >= 0.5), \
        generate 5 hook variations following the 5-VARIANT STRATEGY. Skip clients where the \
        hook mechanism doesn't transfer to their niche.

        Return ONLY valid JSON:
        {
          "adaptations": [
            {
              "clientIndex": 1,
              "relevanceScore": 0.85,
              "ideaTitle": "Short title (3-8 words)",
              "hookVariations": ["v1 punchy", "v2 curiosity", "v3 story", "v4 data", "v5 contrarian"],
              "whyRelevant": "Why this swipe's mechanism works for this client",
              "suggestedFramework": "pas",
              "suggestedFormat": "carousel"
            }
          ]
        }

        MANDATORY: All hooks must pass Cover + Scroll + Dinner Table tests. \
        Match each client's voice from their best performing content. Zero banned phrases.
        """

        // 5. Call LLM (Sonnet tier for single-swipe)
        do {
            let response = try await callAnthropicDirect(
                systemPrompt: Self.sharedHookExpertise,
                userPrompt: userPrompt,
                model: opusModel,
                maxTokens: 4096
            )

            // 6. Parse response
            let adaptations = parseSingleSwipeResponse(response, clients: eligibleClients)
            guard !adaptations.isEmpty else {
                print("[SwipeAdaptationEngine] No adaptations generated for swipe \(swipeAtom.uuid)")
                return
            }

            // 7. Store on atom
            var updatedAtom = swipeAtom
            var analysis = updatedAtom.swipeAnalysis ?? SwipeAnalysis()
            analysis.clientAdaptations = adaptations
            updatedAtom = updatedAtom.withSwipeAnalysis(analysis)
            _ = try? await AtomRepository.shared.update(updatedAtom)

            print("[SwipeAdaptationEngine] Generated \(adaptations.count) client adaptations for swipe \(swipeAtom.uuid)")
        } catch {
            print("⚠️ [SwipeAdaptationEngine] Auto-adaptation failed: \(error)")
        }
    }

    private func parseSingleSwipeResponse(
        _ response: String,
        clients: [(atom: Atom, meta: ClientProfileMetadata)]
    ) -> [SwipeClientAdaptation] {
        // Try JSON extraction
        let jsonStr: String?
        if let data = response.data(using: .utf8),
           let _ = try? JSONSerialization.jsonObject(with: data) {
            jsonStr = response
        } else if let range = response.range(of: #"\{[\s\S]*"adaptations"[\s\S]*\}"#, options: .regularExpression) {
            jsonStr = String(response[range])
        } else {
            jsonStr = nil
        }

        guard let jsonStr = jsonStr,
              let data = jsonStr.data(using: .utf8) else {
            print("⚠️ [SwipeAdaptationEngine] Failed to parse single-swipe response")
            return []
        }

        struct SingleSwipeResult: Codable {
            let adaptations: [SingleAdaptation]
        }
        struct SingleAdaptation: Codable {
            let clientIndex: Int
            let relevanceScore: Double?
            let ideaTitle: String?
            let hookVariations: [String]?
            let whyRelevant: String?
            let suggestedFramework: String?
            let suggestedFormat: String?
        }

        guard let result = try? JSONDecoder().decode(SingleSwipeResult.self, from: data) else { return [] }

        let now = ISO8601.string(from: Date())
        return result.adaptations.compactMap { adapt in
            let idx = adapt.clientIndex - 1  // 1-indexed in prompt
            guard idx >= 0, idx < clients.count else { return nil }
            let client = clients[idx]
            guard let hooks = adapt.hookVariations, !hooks.isEmpty else { return nil }

            return SwipeClientAdaptation(
                clientUUID: client.atom.uuid,
                clientName: client.meta.clientName,
                relevanceScore: adapt.relevanceScore ?? 0.5,
                hookVariations: hooks,
                ideaTitle: adapt.ideaTitle ?? "Untitled",
                whyRelevant: adapt.whyRelevant ?? "",
                suggestedFramework: adapt.suggestedFramework,
                suggestedFormat: adapt.suggestedFormat,
                generatedAt: now
            )
        }
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
    case noAnthropicKey
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .clientNotFound(let name):
            return "No client profile found matching '\(name)'"
        case .noSwipesFound(let filter):
            if let filter = filter {
                return "No swipe files found for time filter '\(filter)'"
            }
            return "No swipe files found in the library"
        case .noAnthropicKey:
            return "Anthropic API key not configured (set AGENT_LLM_API_KEY)"
        case .apiError(let msg):
            return "API error: \(msg)"
        }
    }
}
