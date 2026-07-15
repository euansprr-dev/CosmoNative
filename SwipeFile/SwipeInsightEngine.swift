// CosmoOS/SwipeFile/SwipeInsightEngine.swift
// The single per-swipe analysis pass — one Sonnet 5 call that replaces the
// keyword-heuristic NLP layer (SwipeAnalyzer), the unified classification
// prompt (SwipeClassificationEngine.buildUnifiedPrompt), and the separate
// deepAnalyze path. Produces the display title, key insight, hook analysis,
// slide-anchored structure, taxonomy, and the signature card that feeds the
// cross-swipe PatternWeaver.
// July 2026

import Foundation
import GRDB

// MARK: - Response Schema

/// The JSON contract with the model. Internal + Codable so tests can decode
/// fixtures directly.
struct SwipeInsightResponse: Codable {
    var displayTitle: String?
    var keyInsight: String?

    var hookType: String?
    var hookScore: Double?
    var hookScoreReason: String?
    var hookMechanism: String?

    var primaryNarrative: String?
    var secondaryNarrative: String?
    var contentType: String?
    var niche: String?
    var creatorHandle: String?
    var creatorName: String?
    var classificationConfidence: Double?

    var frameworkType: String?
    var sections: [InsightSection]?
    var structuralRecipe: String?
    var voiceMarkers: [String]?

    var signatureCard: String?

    struct InsightSection: Codable {
        var label: String
        var purpose: String
        var slideStart: Int?
        var slideEnd: Int?
        var sizePercent: Double?
    }
}

// MARK: - SwipeInsightEngine

@MainActor
final class SwipeInsightEngine {
    static let shared = SwipeInsightEngine()

    /// Every swipe is curated — one premium call per capture is the budget.
    static let analysisTier: AgentModelTier = .sonnet5

    /// Stamped into `SwipeAnalysis.analysisVersion`. Bump when the prompt or
    /// output schema changes materially. (Legacy: heuristic pass = 1, unified
    /// classification = 2, pre-canonical-niche insight = 3.)
    static let insightVersion = 4

    /// UUIDs currently being analyzed — supports concurrent batch processing.
    private(set) var analyzingUUIDs: Set<String> = []

    var isAnalyzing: Bool { !analyzingUUIDs.isEmpty }

    private init() {}

    // MARK: - Main entry

    /// Run the full insight pass for a swipe. Pure with respect to the swipe
    /// atom — the caller persists the returned analysis (the single-write +
    /// version-conflict invariant lives in SwipeProcessingService). Creator
    /// atoms ARE written as a side effect (resolution, linking, stats).
    func analyze(atom: Atom) async -> SwipeAnalysis {
        analyzingUUIDs.insert(atom.uuid)
        defer { analyzingUUIDs.remove(atom.uuid) }

        let slides = Self.analyzableSlides(from: atom)
        let fallbackText = Self.fallbackText(from: atom)
        guard !slides.isEmpty || !fallbackText.isEmpty else {
            return SwipeAnalysis(analysisVersion: Self.insightVersion, isFullyAnalyzed: false)
        }

        let hookText = slides.first?.text ?? String(fallbackText.prefix(500))
        let canonicalNiches = await NicheRegistry.shared.canonicalListForPrompt()
        let prompt = Self.buildPrompt(
            atom: atom,
            slides: slides,
            fallbackText: fallbackText,
            canonicalBeats: BeatPatternService.shared.canonicalLabelsForPrompt,
            canonicalNiches: canonicalNiches
        )

        do {
            let raw = try await ResearchService.shared.analyze(
                prompt: prompt,
                tier: Self.analysisTier,
                maxTokens: 4000
            )
            guard let response = Self.parseResponse(raw) else {
                print("SwipeInsightEngine: Unparseable response for \(atom.uuid.prefix(8))")
                return SwipeAnalysis(analysisVersion: Self.insightVersion, isFullyAnalyzed: false)
            }

            // Creator: AI handle first, oEmbed author fallback — then resolve
            // to a creator atom (find-or-create + bidirectional links).
            let (handle, name) = Self.effectiveCreator(from: response, atom: atom)
            let creatorUUID = await SwipeClassificationEngine.shared.resolveCreator(
                handle: handle, name: name, atom: atom
            )

            var analysis = Self.buildAnalysis(
                from: response,
                hookText: hookText,
                slideCount: slides.count,
                creatorUUID: creatorUUID,
                atom: atom
            )

            // Canonicalize the niche — the model was shown the registry, the
            // deterministic matcher is the net (exact → alias → fuzzy → create).
            if let rawNiche = analysis.niche, !rawNiche.isEmpty {
                analysis.niche = await NicheRegistry.shared.resolve(rawNiche)
            }

            // Beat normalization → the structural fingerprint that Stage A
            // pattern matching keys on.
            if let sections = analysis.sections, !sections.isEmpty {
                let normalized = BeatPatternService.shared.normalizeBeats(
                    rawLabels: sections.map(\.label)
                )
                analysis.normalizedBeats = normalized
                analysis.beatFingerprint = BeatPatternService.shared
                    .computeStructuralFingerprint(normalizedBeats: normalized)
                BeatPatternService.shared.trackUsage(beats: normalized)
            }

            if let creatorUUID {
                await SwipeClassificationEngine.shared.updateCreatorStats(creatorUUID: creatorUUID)
            }

            return analysis
        } catch {
            print("SwipeInsightEngine: Analysis failed for \(atom.uuid.prefix(8)): \(error)")
            return SwipeAnalysis(analysisVersion: Self.insightVersion, isFullyAnalyzed: false)
        }
    }

    /// Re-run the insight pass on a swipe the user already has (Study's
    /// Reanalyze action) and persist safely: curated fields survive, only the
    /// structured column (+ title when a fresh displayTitle landed) is written.
    func reanalyzeAndPersist(atom: Atom) async -> SwipeAnalysis? {
        let fresh = (try? await AtomRepository.shared.fetch(uuid: atom.uuid)) ?? atom
        let analysis = await analyze(atom: fresh)
        guard analysis.isFullyAnalyzed else { return nil }

        // Re-fetch again — the model call is long; don't clobber edits made
        // during it.
        let live = (try? await AtomRepository.shared.fetch(uuid: atom.uuid)) ?? fresh
        let merged = analysis.preservingCuratedFields(from: live.swipeAnalysis)
        var updated = live.withSwipeAnalysis(merged)

        var columns: [String: (any DatabaseValueConvertible)?] = [
            "structured": updated.structured
        ]
        if let title = merged.displayTitle, !title.isEmpty,
           !AtomRepository.shared.isBeingEdited(atom.uuid) {
            updated.title = title
            columns["title"] = title
        }
        do {
            _ = try await AtomRepository.shared.updateFields(uuid: atom.uuid, columns: columns)
        } catch {
            PersistenceHealth.note(
                .writeFailure,
                context: "SwipeInsightEngine.reanalyzeAndPersist(\(atom.uuid.prefix(8)))",
                detail: error.localizedDescription
            )
            return nil
        }
        return merged
    }

    // MARK: - Input assembly

    /// The slide list the model sees. Prefers cleaned transcript slides; a
    /// swipe with only a body text becomes a single pseudo-slide downstream.
    static func analyzableSlides(from atom: Atom) -> [TranscriptSlide] {
        (atom.swipeAnalysis?.transcriptSlides ?? []).filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Body-text fallback for swipes without slide transcripts (YouTube, X,
    /// plain saves). Mirrors the old engines' extraction order.
    static func fallbackText(from atom: Atom) -> String {
        if let body = atom.body, !body.isEmpty { return body }
        if let transcript = atom.richContent?.transcript, !transcript.isEmpty { return transcript }
        return ""
    }

    /// AI handle first; oEmbed author as fallback when the AI handle is
    /// missing or a leaked numeric Instagram ID.
    static func effectiveCreator(
        from response: SwipeInsightResponse,
        atom: Atom
    ) -> (handle: String?, name: String?) {
        var handle = response.creatorHandle
        var name = response.creatorName

        let isNumeric = handle?
            .replacingOccurrences(of: "@", with: "")
            .allSatisfy(\.isNumber) ?? true
        if handle == nil || isNumeric {
            let oembedAuthor = atom.richContent?.author ?? ""
            if !oembedAuthor.isEmpty && !oembedAuthor.allSatisfy(\.isNumber) {
                let base = oembedAuthor
                    .components(separatedBy: "|").first?
                    .trimmingCharacters(in: .whitespaces) ?? oembedAuthor
                handle = "@" + base
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "_")
                    .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
                name = name ?? base
            }
        }
        return (handle, name)
    }

    // MARK: - Response parsing

    /// Strip code fences and decode. Static + internal for direct testing.
    static func parseResponse(_ raw: String) -> SwipeInsightResponse? {
        var jsonStr = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonStr.hasPrefix("```") {
            if let firstNewline = jsonStr.firstIndex(of: "\n") {
                jsonStr = String(jsonStr[jsonStr.index(after: firstNewline)...])
            }
            if jsonStr.hasSuffix("```") {
                jsonStr = String(jsonStr.dropLast(3))
            }
            jsonStr = jsonStr.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = jsonStr.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SwipeInsightResponse.self, from: data)
    }

    // MARK: - Analysis construction

    /// Map a parsed response onto SwipeAnalysis. Deterministic + testable.
    static func buildAnalysis(
        from response: SwipeInsightResponse,
        hookText: String,
        slideCount: Int,
        creatorUUID: String?,
        atom: Atom
    ) -> SwipeAnalysis {
        let sections: [SwipeSection]? = response.sections?.enumerated().compactMap { index, s in
            let label = s.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveLabel = label.isEmpty
                ? String(s.purpose.prefix(30)).trimmingCharacters(in: .whitespacesAndNewlines)
                : label
            guard !effectiveLabel.isEmpty else { return nil }
            // Clamp slide anchors to the actual slide range; drop nonsense.
            var slideStart = s.slideStart
            var slideEnd = s.slideEnd
            if slideCount > 0 {
                slideStart = slideStart.map { min(max($0, 1), slideCount) }
                slideEnd = slideEnd.map { min(max($0, slideStart ?? 1), slideCount) }
            } else {
                slideStart = nil
                slideEnd = nil
            }
            return SwipeSection(
                label: effectiveLabel,
                startIndex: index,
                endIndex: index + 1,
                purpose: s.purpose,
                emotion: nil,
                sizePercent: s.sizePercent,
                slideStart: slideStart,
                slideEnd: slideEnd
            )
        }

        var analysis = SwipeAnalysis(
            hookText: hookText.isEmpty ? nil : hookText,
            hookType: response.hookType.flatMap { SwipeHookType(rawValue: $0) },
            hookScore: response.hookScore.map { min(max($0, 0), 10) },
            hookWordCount: hookText.split(separator: " ").count,
            frameworkType: response.frameworkType.flatMap { SwipeFrameworkType(rawValue: $0) },
            sections: sections,
            keyInsight: response.keyInsight,
            hookScoreReason: response.hookScoreReason,
            analysisVersion: insightVersion,
            analyzedAt: ISO8601.string(from: Date()),
            isFullyAnalyzed: true,
            primaryNarrative: response.primaryNarrative.flatMap { NarrativeStyle(rawValue: $0) },
            secondaryNarrative: response.secondaryNarrative.flatMap { NarrativeStyle(rawValue: $0) },
            swipeContentFormat: response.contentType.flatMap { ContentFormat(rawValue: $0) },
            niche: response.niche,
            creatorUUID: creatorUUID,
            classifiedAt: Date(),
            classificationSource: .ai,
            classificationConfidence: response.classificationConfidence
        )
        analysis.hookMechanism = response.hookMechanism
        analysis.structuralRecipe = response.structuralRecipe
        analysis.voiceMarkers = response.voiceMarkers
        analysis.displayTitle = sanitizedDisplayTitle(response.displayTitle, hook: hookText)
        analysis.signatureCard = response.signatureCard?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Format sanity: Instagram video can never be a static "post".
        if analysis.swipeContentFormat == .post || analysis.swipeContentFormat == nil {
            let rc = atom.richContent
            let isVideo = rc?.instagramData?.extractedMediaURL != nil
                || rc?.sourceType == .instagramReel
                || rc?.instagramType == "reel"
            if isVideo {
                analysis.swipeContentFormat = .multiSliderReel
            }
        }

        return analysis
    }

    /// Deterministic guardrail on the model's title: trim, strip wrapping
    /// quotes, collapse whitespace, hard-cap at 90 chars on a word boundary.
    /// A short hook passes through verbatim even if the model rewrote it.
    static func sanitizedDisplayTitle(_ raw: String?, hook: String?) -> String? {
        let cleanedHook = hook?
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleanedHook, !cleanedHook.isEmpty, cleanedHook.count <= 60 {
            return cleanedHook
        }

        guard var title = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }
        while title.count >= 2,
              let first = title.first, let last = title.last,
              (first == "\"" && last == "\"") || (first == "“" && last == "”") || (first == "'" && last == "'") {
            title = String(title.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        title = title
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard !title.isEmpty else { return nil }
        if title.count > 90 {
            let cut = String(title.prefix(90))
            title = cut.contains(" ")
                ? cut.split(separator: " ").dropLast().joined(separator: " ")
                : cut
        }
        return title.isEmpty ? nil : title
    }

    // MARK: - Prompt

    static func buildPrompt(
        atom: Atom,
        slides: [TranscriptSlide],
        fallbackText: String,
        canonicalBeats: String,
        canonicalNiches: String = ""
    ) -> String {
        let richContent = atom.richContent
        let platform = atom.researchMetadata?.contentSource ?? "unknown"
        let author = richContent?.author ?? ""
        let caption = richContent?.title ?? ""
        let analysis = atom.swipeAnalysis

        // Media signals
        var mediaLines: [String] = []
        if let sourceType = richContent?.sourceType?.rawValue, !sourceType.isEmpty {
            mediaLines.append("Source type: \(sourceType)")
        }
        if let igType = richContent?.instagramType, !igType.isEmpty {
            mediaLines.append("Instagram type: \(igType)")
        }
        if let duration = Self.durationSeconds(from: atom), duration > 0 {
            mediaLines.append("Video duration: \(duration) seconds")
        }
        if let carouselCount = richContent?.instagramData?.carouselItems?.count, carouselCount > 0 {
            mediaLines.append("Carousel image count: \(carouselCount)")
        }
        if richContent?.instagramData?.extractedMediaURL != nil {
            mediaLines.append("Has video: yes")
        }
        mediaLines.append(contentsOf: Self.transcriptionModalityLines(analysis: analysis))

        // Engagement signals
        var engagementLines: [String] = []
        if let views = analysis?.viewsCount { engagementLines.append("Views: \(views)") }
        if let likes = analysis?.likesCount { engagementLines.append("Likes: \(likes)") }
        if let comments = analysis?.commentsCount { engagementLines.append("Comments: \(comments)") }

        // The transcript, slide-indexed so structure anchors are verifiable.
        let transcriptBlock: String
        if !slides.isEmpty {
            transcriptBlock = slides.enumerated().map { index, slide in
                let provenance = slide.source == .speechAudio ? " (spoken)" : ""
                return "[Slide \(index + 1)\(provenance)] \(slide.text)"
            }.joined(separator: "\n\n")
        } else {
            let words = fallbackText.split(separator: " ")
            transcriptBlock = "[Slide 1] " + words.prefix(4000).joined(separator: " ")
        }
        let slideCount = max(slides.count, 1)

        let narrativeValues = NarrativeStyle.allCases.map(\.rawValue).joined(separator: ", ")
        let formatValues = ContentFormat.allCases.map(\.rawValue).joined(separator: ", ")
        let frameworkList = SwipeFrameworkType.allCases
            .map { "\($0.rawValue): \($0.description)" }
            .joined(separator: "\n")
        let hookTypeList = Self.hookTypeDefinitions
            .map { "- \($0.0): \($0.1)" }
            .joined(separator: "\n")

        return """
        You are a senior direct-response content analyst inside a swipe-file study tool. A creator saved this piece of short-form content because it worked; your job is to explain WHY it worked precisely enough that they could replicate the mechanics on a different topic tomorrow. Every field you return is displayed in a study interface or fed to a pattern-mining engine, so be specific, mechanical, and grounded in the actual text — never generic.

        ## THE CONTENT

        Platform: \(platform)
        Creator/Author (may be a numeric ID — see creator rules): \(author)
        Caption/oEmbed title: \(caption)
        \(mediaLines.joined(separator: "\n"))
        \(engagementLines.isEmpty ? "" : engagementLines.joined(separator: "\n"))

        Transcript (\(slideCount) slide\(slideCount == 1 ? "" : "s"), 1-indexed — slide 1 is the hook the viewer sees first):

        \(transcriptBlock)

        ## WHAT TO PRODUCE

        ### displayTitle
        A short library headline for this swipe, ≤60 characters.
        - If slide 1 is already ≤60 characters, return it VERBATIM.
        - Otherwise compress slide 1 into one headline that keeps the creator's voice and the single most specific claim. Keep concrete numbers ("$75K", "90 days") — specificity is the value. No quotation marks, no emoji, no trailing period, no editorializing ("Amazing thread about...").
        - Example: slide 1 = "Housing didn't get expensive by accident. For decades, home prices ran way ahead of incomes, and now everyone wants to act surprised that young families can't buy" → displayTitle = "Housing didn't get expensive by accident".

        ### keyInsight
        2–3 sentences explaining the MECHANISM that makes this content work — not a summary of what it says. The test: a reader should be able to apply the insight to a completely different niche. Name the specific move (e.g. "validates the audience's struggle with third-party data before offering the reframe, so the solve lands as relief instead of a lecture"), not the category ("uses social proof").

        ### Hook analysis (judge slide 1 / the first 3 seconds ONLY)
        hookType — exactly one of:
        \(hookTypeList)

        hookScore — 0 to 10, one decimal, anchored rubric:
        - 9–10: stops the scroll cold — a specific, unresolved tension aimed at a defined audience (a number, a named enemy, a forbidden claim). Rare.
        - 7–8.9: strong — specific and curiosity-driving, but the tension is familiar or the audience broad.
        - 5–6.9: clear topic, generic angle — tells you WHAT it's about but gives no reason to need the answer now.
        - 3–4.9: slow or self-focused opening; the viewer must be patient to find the value.
        - 0–2.9: no hook — greeting, context-first ramble, or pure vibes.
        hookScoreReason — one sentence citing the exact words that earn (or lose) the score.
        hookMechanism — one sentence on the psychological lever (what unresolved question or identity-threat/validation it plants, and in whom).

        ### Structure (sections)
        Segment the ENTIRE transcript into 3–8 beats, in order, covering every slide with no gaps or overlaps.
        - label: use ONLY these canonical beat labels: \(canonicalBeats). If nothing fits, use "Uncategorized: YourLabel".
        - purpose: what this beat DOES to the reader (creates the gap / supplies proof / removes the objection), not what it says.
        - slideStart / slideEnd: 1-based inclusive slide numbers this beat spans. Beats must be verifiable against the numbered transcript above.
        - sizePercent: fraction of total content length, all sections summing to ~1.0.

        frameworkType — one of the following if (and only if) the beat sequence genuinely matches; otherwise null:
        \(frameworkList)

        structuralRecipe — a numbered, step-by-step writing recipe someone could follow to recreate this structure on a new topic. Each step: beat + approximate length + density (sparse/moderate/dense). Ground it in what THIS content actually did.

        voiceMarkers — 3–5 short phrases capturing the prose voice (e.g. "second-person accusation", "data-point-per-sentence", "no hedging").

        ### Taxonomy
        primaryNarrative and optional secondaryNarrative — from: \(narrativeValues)
        - studentSuccess: A STUDENT or CLIENT success story — someone ELSE achieved a specific result (revenue, transformation, milestone). Must feature a real person's outcome, NOT generic tips. Example: "My student went from $0 to $10K/month in 90 days."
        - storytelling: The creator recapping a STORY — their own journey, a client's story told narratively, or a behind-the-scenes experience. Structured as a narrative arc, not tips or analysis.
        - lessonsLearned: A LISTICLE or numbered list of lessons, mistakes, or takeaways ("X things I learned", "X mistakes to avoid"). Must be structured as a list, not a single-topic deep-dive.
        - authorityHacking: The HOOK references a famous person, public figure, brand, or celebrity to borrow credibility ("How Warren Buffett buys real estate").
        - businessBreakdown: Analyzing or breaking down a BUSINESS MODEL, market, strategy, tool, or system — including resource lists, platform comparisons, market analysis, how-to explanations of business mechanics. "5 websites to find homes under $75K" = businessBreakdown (analyzing tools/market), NOT lessonsLearned.
        - fearMongering: The hook leverages a CURRENT EVENT, alarming trend, or scary scenario for urgency ("The housing market is about to crash").
        - noValue: Pure entertainment, engagement-bait, or meme content with no educational, aspirational, or strategic value.

        contentType — from: \(formatValues)
        - voiceoverReel: continuous video with voiceover narration (talking head or B-roll with VO).
        - oneSliderReel: a reel with ONE static or slow-motion background and text overlay.
        - multiSliderReel: a reel with MULTIPLE distinct visual cards in sequence. Use ONLY with clear evidence of distinct cards carrying the content — do NOT infer it from subtitle fragments or burned captions that mirror speech.
        - carousel: static multi-image swipeable post (no video, no audio).
        - post: a single static image (no video). NEVER use "post" for anything with video or duration > 0.
        Transcription-modality guidance: voiceoverOnly ⇒ strongly prefer voiceoverReel. voiceoverPlusText ⇒ prefer voiceoverReel or oneSliderReel unless distinct visual cards are evident. On-screen text that mirrors speech = captions, not slides.

        \(NicheRegistry.promptInstruction(canonicalList: canonicalNiches))

        creatorHandle / creatorName — the creator's @username and display name. The Creator/Author field above may be a numeric ID — never use a numeric ID. Look for the real @username in the transcript or caption; if none exists, return null for creatorHandle.

        classificationConfidence — 0.0–1.0.

        ### signatureCard
        A compact pattern fingerprint (≤80 words) that a pattern-mining engine will compare across many swipes WITHOUT seeing transcripts. Exact format:
        "HOOK: <mechanism, 5–8 words>. BEATS: <label → label → label>. MOVES: <2–4 persuasion moves actually used>. SUBJECT: <topic, 3–5 words>. NUMBERS: <how quantification is used, or 'none'>. VOICE: <2–3 markers>."
        Describe the observable moves of THIS content — not textbook framework names.

        ## OUTPUT

        Return ONLY valid JSON, no markdown fences, exactly this shape (null for unknowable fields):
        {
          "displayTitle": "...",
          "keyInsight": "...",
          "hookType": "boldClaim",
          "hookScore": 8.5,
          "hookScoreReason": "...",
          "hookMechanism": "...",
          "primaryNarrative": "businessBreakdown",
          "secondaryNarrative": null,
          "contentType": "carousel",
          "niche": "...",
          "creatorHandle": "@username",
          "creatorName": "Display Name",
          "classificationConfidence": 0.9,
          "frameworkType": "pas",
          "sections": [
            {"label": "Hook", "purpose": "...", "slideStart": 1, "slideEnd": 1, "sizePercent": 0.12},
            {"label": "PainAmplification", "purpose": "...", "slideStart": 2, "slideEnd": 4, "sizePercent": 0.4}
          ],
          "structuralRecipe": "1. ...\\n2. ...",
          "voiceMarkers": ["...", "..."],
          "signatureCard": "HOOK: ... BEATS: ... MOVES: ... SUBJECT: ... NUMBERS: ... VOICE: ..."
        }
        """
    }

    /// Hook type definitions taught to the model — one discriminating line each.
    static let hookTypeDefinitions: [(String, String)] = [
        ("curiosityGap", "opens a specific unanswered question the viewer must resolve (\"Nobody talks about why...\")"),
        ("boldClaim", "a declarative, falsifiable assertion stated as fact (\"Housing didn't get expensive by accident.\")"),
        ("question", "a direct question aimed at the viewer"),
        ("story", "drops the viewer mid-narrative (\"I lost the deal at 11pm on a Tuesday...\")"),
        ("statistic", "leads with a specific number or data point as the attention device"),
        ("controversy", "takes a side on a divisive topic to provoke reaction"),
        ("contrast", "juxtaposes two states or options (\"Rich people do X. Everyone else does Y.\")"),
        ("howTo", "promises a method (\"How to...\" / \"The exact system for...\")"),
        ("list", "promises enumerated items (\"5 websites that...\")"),
        ("challenge", "dares the viewer or sets a test (\"Try this for 30 days\")"),
        ("hiddenGem", "reveals something obscure or insider (\"The clause nobody reads...\")"),
        ("contrarian", "inverts accepted advice (\"Stop saving money.\")"),
        ("personal", "leads with the creator's own status or vulnerability (\"I made $40K last month and I'm terrified.\")"),
        ("transformation", "before→after change as the opener (\"From evicted to 12 doors in 3 years\")")
    ]

    // MARK: - Context helpers

    static func durationSeconds(from atom: Atom) -> Int? {
        guard let structuredStr = atom.structured,
              let data = structuredStr.data(using: .utf8),
              let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let autoMetaStr = outer["autoMetadata"] as? String,
              let autoData = autoMetaStr.data(using: .utf8),
              let autoMeta = try? JSONSerialization.jsonObject(with: autoData) as? [String: Any],
              let d = autoMeta["duration"] as? Int else { return nil }
        return d
    }

    static func transcriptionModalityLines(analysis: SwipeAnalysis?) -> [String] {
        guard let analysis else { return [] }
        var lines: [String] = []
        let rawSlides = analysis.rawTranscriptSlides ?? analysis.transcriptSlides ?? []
        let speech = analysis.transcriptSpeechSegments ?? []
        let nonEmpty = rawSlides.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !nonEmpty.isEmpty || !speech.isEmpty {
            let hasVisual = nonEmpty.contains { ($0.source ?? .manual) != .speechAudio }
            let modality: TranscriptionContentType = speech.isEmpty
                ? .textOnly
                : (hasVisual ? .voiceoverPlusText : .voiceoverOnly)
            lines.append("Inferred transcription modality: \(modality.rawValue)")
        }
        if !speech.isEmpty { lines.append("Speech segment count: \(speech.count)") }
        if let quality = analysis.transcriptionQuality {
            lines.append("Transcription quality: \(quality.rawValue)")
        }
        if let warnings = analysis.transcriptionWarnings, !warnings.isEmpty {
            lines.append("Transcription warnings: \(warnings.joined(separator: " | "))")
        }
        return lines
    }
}
