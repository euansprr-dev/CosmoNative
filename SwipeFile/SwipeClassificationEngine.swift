// CosmoOS/SwipeFile/SwipeClassificationEngine.swift
// Unified AI classification + deep analysis engine for swipe files
// Single Claude call produces taxonomy classification AND structural analysis
// February 2026

import Foundation
import GRDB

@MainActor
final class SwipeClassificationEngine: ObservableObject {
    static let shared = SwipeClassificationEngine()
    static let autoIngestModel = "google/gemini-3-flash-preview"

    /// UUIDs currently being classified — supports concurrent batch processing
    private var classifyingUUIDs: Set<String> = []

    /// Whether any classification is in progress (for UI binding)
    @Published var isClassifying = false

    /// Current schema version — bump when classification prompt/output format changes
    static let currentSchemaVersion = 1

    private init() {}

    // MARK: - Main Pipeline

    /// Classify and deep-analyze a swipe atom in a single cloud call.
    /// Returns an enriched SwipeAnalysis with taxonomy fields + deep analysis.
    func classifyAndAnalyze(atom: Atom, model: String? = nil) async -> SwipeAnalysis {
        classifyingUUIDs.insert(atom.uuid)
        isClassifying = true
        defer {
            classifyingUUIDs.remove(atom.uuid)
            isClassifying = !classifyingUUIDs.isEmpty
        }

        let text = extractText(from: atom)
        guard !text.isEmpty else {
            return SwipeAnalysis(analysisVersion: 1, isFullyAnalyzed: false)
        }

        // Build the unified prompt
        let canonicalNiches = await NicheRegistry.shared.canonicalListForPrompt()
        let prompt = buildUnifiedPrompt(atom: atom, text: text, canonicalNiches: canonicalNiches)

        do {
            let response: String
            if let model {
                response = try await ResearchService.shared.analyze(
                    prompt: prompt,
                    model: model,
                    maxTokens: 4000,
                    temperature: 0.2
                )
            } else {
                response = try await ResearchService.shared.analyzeContent(prompt: prompt)
            }
            let parsed = parseResponse(response)

            if let parsed = parsed {
                // Resolve creator — AI handle first, oEmbed author fallback
                var creatorHandle = parsed.creatorHandle
                var creatorName = parsed.creatorName

                // Fallback: if AI didn't find a handle, use oEmbed author name
                if creatorHandle == nil || creatorHandle?.replacingOccurrences(of: "@", with: "").allSatisfy(\.isNumber) == true {
                    let oembedAuthor = atom.richContent?.author ?? ""
                    if !oembedAuthor.isEmpty && !oembedAuthor.allSatisfy(\.isNumber) {
                        // Normalize: "Ben Allgeyer | Real Estate Investor" → handle "@ben_allgeyer"
                        let handleBase = oembedAuthor
                            .components(separatedBy: "|").first?
                            .trimmingCharacters(in: .whitespaces) ?? oembedAuthor
                        creatorHandle = "@" + handleBase
                            .lowercased()
                            .replacingOccurrences(of: " ", with: "_")
                            .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
                        creatorName = creatorName ?? oembedAuthor
                            .components(separatedBy: "|").first?
                            .trimmingCharacters(in: .whitespaces) ?? oembedAuthor
                    }
                }

                let creatorUUID = await resolveCreator(
                    handle: creatorHandle,
                    name: creatorName,
                    atom: atom
                )

                // Build the enriched analysis
                var analysis = buildAnalysis(from: parsed, creatorUUID: creatorUUID)

                // Canonicalize the niche through the shared registry.
                if let rawNiche = analysis.niche, !rawNiche.isEmpty {
                    analysis.niche = await NicheRegistry.shared.resolve(rawNiche)
                }

                // Platform-based format validation: video content from Instagram cannot be "post"
                if analysis.swipeContentFormat == .post || analysis.swipeContentFormat == nil {
                    let rc = atom.richContent
                    let isVideo = rc?.instagramData?.extractedMediaURL != nil
                        || rc?.sourceType == .instagramReel
                        || rc?.instagramType == "reel"
                    if isVideo {
                        analysis.swipeContentFormat = .multiSliderReel
                    }
                }

                // Persist to atom
                await persistAnalysis(analysis, to: atom)

                // Update creator aggregate stats if we have a creator
                if let creatorUUID = creatorUUID {
                    await updateCreatorStats(creatorUUID: creatorUUID)
                }

                return analysis
            }
        } catch {
            print("SwipeClassificationEngine: Classification failed: \(error)")
        }

        // Return empty analysis on failure
        return SwipeAnalysis(analysisVersion: 1, isFullyAnalyzed: false)
    }

    /// Merge classification results into an existing (local NLP) SwipeAnalysis.
    /// Used when local analysis ran first and classification arrives later.
    func mergeClassification(_ classified: SwipeAnalysis, into local: SwipeAnalysis) -> SwipeAnalysis {
        var merged = local

        // Taxonomy fields (always override from AI)
        merged.primaryNarrative = classified.primaryNarrative ?? merged.primaryNarrative
        merged.secondaryNarrative = classified.secondaryNarrative ?? merged.secondaryNarrative
        merged.swipeContentFormat = classified.swipeContentFormat ?? merged.swipeContentFormat
        merged.niche = classified.niche ?? merged.niche
        merged.creatorUUID = classified.creatorUUID ?? merged.creatorUUID
        merged.classifiedAt = classified.classifiedAt ?? merged.classifiedAt
        merged.classificationSource = classified.classificationSource ?? merged.classificationSource
        merged.classificationConfidence = classified.classificationConfidence ?? merged.classificationConfidence

        // Deep analysis fields (override from Claude when present)
        if classified.frameworkType != nil {
            merged.frameworkType = classified.frameworkType
        }
        if let sections = classified.sections, !sections.isEmpty {
            merged.sections = sections
        }
        if let arc = classified.emotionalArc, !arc.isEmpty {
            merged.emotionalArc = arc
            // Recompute dominant emotion
            var emotionIntensity: [SwipeEmotion: Double] = [:]
            for point in arc {
                emotionIntensity[point.emotion, default: 0] += point.intensity
            }
            merged.dominantEmotion = emotionIntensity.max(by: { $0.value < $1.value })?.key
        }
        if let techniques = classified.persuasionTechniques, !techniques.isEmpty {
            merged.persuasionTechniques = techniques
            merged.persuasionStack = Dictionary(
                uniqueKeysWithValues: techniques.map { ($0.type.rawValue, $0.intensity) }
            )
        }
        if let score = classified.hookScore, score > 0 {
            merged.hookScore = score
        }
        merged.hookScoreReason = classified.hookScoreReason ?? merged.hookScoreReason
        merged.keyInsight = classified.keyInsight ?? merged.keyInsight
        merged.fingerprint = classified.fingerprint ?? merged.fingerprint
        merged.hookMechanism = classified.hookMechanism ?? merged.hookMechanism
        merged.structuralRecipe = classified.structuralRecipe ?? merged.structuralRecipe
        merged.voiceMarkers = classified.voiceMarkers ?? merged.voiceMarkers

        // Bump version
        merged.analysisVersion = max(merged.analysisVersion, SwipeClassificationEngine.currentSchemaVersion + 1)
        merged.analyzedAt = ISO8601.string(from: Date())
        merged.isFullyAnalyzed = true

        return merged
    }

    // MARK: - Prompt Building

    private func buildUnifiedPrompt(atom: Atom, text: String, canonicalNiches: String = "") -> String {
        // Truncate text to ~4000 words
        let words = text.split(separator: " ")
        let truncated = words.prefix(4000).joined(separator: " ")

        // Gather atom context
        let title = atom.title ?? "Untitled"
        let url = atom.researchMetadata?.url ?? ""
        let platform = atom.researchMetadata?.contentSource ?? ""

        // Gather oEmbed metadata
        let richContent = atom.richContent
        let author = richContent?.author ?? ""
        let oembedTitle = richContent?.title ?? ""

        // Gather media context for format classification
        let sourceType = richContent?.sourceType?.rawValue ?? ""
        let instagramType = richContent?.instagramType ?? ""
        let hasVideo = richContent?.instagramData?.extractedMediaURL != nil
        let slideCount = richContent?.instagramData?.carouselItems?.count ?? 0

        // Extract duration from autoMetadata JSON
        var duration: Int = 0
        if let structuredStr = atom.structured,
           let data = structuredStr.data(using: .utf8),
           let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let autoMetaStr = outer["autoMetadata"] as? String,
           let autoData = autoMetaStr.data(using: .utf8),
           let autoMeta = try? JSONSerialization.jsonObject(with: autoData) as? [String: Any],
           let d = autoMeta["duration"] as? Int {
            duration = d
        }

        // Build available taxonomy values lists
        let narrativeValues = NarrativeStyle.allCases.map { $0.rawValue }.joined(separator: ", ")
        let formatValues = ContentFormat.allCases.map { $0.rawValue }.joined(separator: ", ")
        let frameworkValues = SwipeFrameworkType.allCases.map { $0.rawValue }.joined(separator: ", ")

        // Build media context string
        var mediaContext = ""
        if !sourceType.isEmpty { mediaContext += "Source Type: \(sourceType)\n" }
        if !instagramType.isEmpty { mediaContext += "Instagram Type: \(instagramType)\n" }
        if duration > 0 { mediaContext += "Duration: \(duration) seconds\n" }
        if slideCount > 0 { mediaContext += "Carousel/Slide Count: \(slideCount)\n" }
        if hasVideo { mediaContext += "Has Video: yes\n" }
        mediaContext += transcriptionContext(from: atom)

        return """
        You are a content intelligence analyst. Analyze this content and return a single JSON object that covers BOTH taxonomy classification AND structural analysis.

        Title: \(title)
        URL: \(url)
        Platform: \(platform)
        Creator/Author: \(author)
        oEmbed Title: \(oembedTitle)
        \(mediaContext)
        Transcript (first 4000 words): \(truncated)

        ## Taxonomy Classification
        Classify the content across these dimensions:

        Narrative Styles (pick primary and optional secondary): \(narrativeValues)
        - studentSuccess: A STUDENT or CLIENT success story — someone ELSE achieved a specific result (revenue, transformation, milestone). Must feature a real person's outcome, NOT generic tips. Example: "My student went from $0 to $10K/month in 90 days."
        - storytelling: The creator recapping a STORY — their own journey, a client's story told narratively, or a behind-the-scenes experience. The content is structured as a narrative arc, not tips or analysis.
        - lessonsLearned: A LISTICLE or numbered list of lessons, mistakes, or takeaways. The format is "X things I learned" or "X mistakes to avoid." Must be structured as a list, not a single topic deep-dive.
        - authorityHacking: The HOOK or opening references a famous person, public figure, brand, or celebrity to borrow credibility. Example: "How Warren Buffett buys real estate" or "The strategy Hormozi uses to..."
        - businessBreakdown: Analyzing, explaining, or breaking down a BUSINESS MODEL, market, strategy, tool, or system. Includes resource lists, platform comparisons, market analysis, how-to explanations of business mechanics. Example: "5 websites to find homes under $75K" = businessBreakdown (analyzing tools/market), NOT lessonsLearned.
        - fearMongering: The hook leverages a CURRENT EVENT, alarming trend, or scary scenario to grab attention. Creates urgency through fear or concern. Example: "The housing market is about to crash" or "This new law will destroy your business."
        - noValue: Pure entertainment, engagement-bait, or meme content with no educational, aspirational, or strategic value.
        Content Formats: \(formatValues)
        - voiceoverReel: A single continuous video with voiceover narration (talking head, B-roll with VO)
        - oneSliderReel: A reel with ONE static or slow-motion background image/clip and text overlay
        - multiSliderReel: A reel with MULTIPLE distinct visual slides/cards shown in sequence (timed text cards, image transitions). Use this ONLY when the video clearly contains unique visual cards carrying the content. Do NOT infer multiSliderReel from subtitle fragments, burned captions, or talking-head captions that mirror speech.
        - carousel: Static multi-image swipeable post (NO video, NO audio)
        - post: A single static image post (NO video). Only use this for truly static single-image content.
        - reel: Generic short-form video (use a more specific reel type if possible)
        IMPORTANT: If the content has VIDEO (duration > 0 seconds) and is from Instagram, it is a REEL format (voiceoverReel, oneSliderReel, or multiSliderReel), NEVER "post". "post" is ONLY for static images with no video.
        IMPORTANT TRANSCRIPTION GUIDANCE:
        - If inferred transcription modality is voiceoverOnly, strongly prefer voiceoverReel.
        - If inferred transcription modality is voiceoverPlusText, prefer voiceoverReel or oneSliderReel unless there is clear evidence of distinct visual cards.
        - If speech segments exist but on-screen text largely mirrors the speech, treat that as captions/subtitles, not multi-slider structure.
        - Music lyrics, chant-like repetition, or sparse repeated speech should NOT by themselves force voiceoverReel.
        \(NicheRegistry.promptInstruction(canonicalList: canonicalNiches))
        Creator: Extract the creator's @username handle and display name. IMPORTANT: The Creator/Author field above may contain a numeric ID (e.g. "63181063998") — do NOT use this. Instead, look for the actual @username in the transcript text, captions, or any visible mentions. If no real username is found, return null for creatorHandle.

        ## Structural Analysis
        Also provide deep structural analysis:

        Frameworks: \(frameworkValues)
        Valid emotions: curiosity, urgency, aspiration, fear, desire, awe, frustration, relief, belonging, exclusivity
        Valid persuasion types: socialProof, curiosityGap, contrastEffect, authority, scarcity, urgency, reciprocity, storytelling, lossAversion, exclusivity, anchoring, framing

        Return ONLY valid JSON with no markdown formatting:
        {
          "primaryNarrative": "storytelling",
          "secondaryNarrative": null,
          "contentType": "voiceoverReel",
          "niche": "Real Estate Wholesaling",
          "creatorHandle": "@username",
          "creatorName": "Display Name",
          "classificationConfidence": 0.85,
          "frameworkType": "aida",
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
          "hookScore": 8.5,
          "hookScoreReason": "Strong curiosity gap with specific number...",
          "keyInsight": "One sentence structural insight about what makes this content work",
          "hookMechanism": "WHY this hook works — explain the psychological mechanism in 1 sentence",
          "structuralRecipe": "Step-by-step writing recipe. Format: numbered list, each step = beat label + word count + density (sparse/moderate/dense)",
          "voiceMarkers": ["conversational", "data-driven", "short sentences"],
          "sentimentQuartiles": [0.1, -0.3, 0.2, 0.6],
          "intensityQuartiles": [0.7, 0.5, 0.6, 0.9]
        }

        Provide at least 6 emotional arc data points. Provide at least 3 sections.
        For classificationConfidence, use 0.0-1.0 where 1.0 = very confident.
        If you cannot determine a field, use null.
        """
    }

    // MARK: - Response Parsing

    /// Unified JSON response from Claude
    private struct ClassificationResponse: Codable {
        let primaryNarrative: String?
        let secondaryNarrative: String?
        let contentType: String?
        let niche: String?
        let creatorHandle: String?
        let creatorName: String?
        let classificationConfidence: Double?
        let frameworkType: String?
        let sections: [DeepAnalysisResult.DeepSection]?
        let emotionalArc: [DeepAnalysisResult.DeepEmotionPoint]?
        let persuasionTechniques: [DeepAnalysisResult.DeepPersuasionTechnique]?
        let hookScore: Double?
        let hookScoreReason: String?
        let keyInsight: String?
        let hookMechanism: String?
        let structuralRecipe: String?
        let voiceMarkers: [String]?
        let sentimentQuartiles: [Double]?
        let intensityQuartiles: [Double]?
    }

    private func parseResponse(_ response: String) -> ClassificationResponse? {
        // Strip markdown code fences if present
        var jsonStr = response.trimmingCharacters(in: .whitespacesAndNewlines)
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
        return try? JSONDecoder().decode(ClassificationResponse.self, from: data)
    }

    // MARK: - Build Analysis from Response

    private func buildAnalysis(from response: ClassificationResponse, creatorUUID: String?) -> SwipeAnalysis {
        // Parse taxonomy fields
        let primaryNarrative = response.primaryNarrative.flatMap { NarrativeStyle(rawValue: $0) }
        let secondaryNarrative = response.secondaryNarrative.flatMap { NarrativeStyle(rawValue: $0) }
        let contentFormat = response.contentType.flatMap { ContentFormat(rawValue: $0) }
        let frameworkType = response.frameworkType.flatMap { SwipeFrameworkType(rawValue: $0) }

        // Parse sections — filter out any with empty/blank labels
        let sections: [SwipeSection]? = response.sections?.enumerated().compactMap { index, s in
            let emotion = s.emotion.flatMap { SwipeEmotion(rawValue: $0) }
            let label = s.label.trimmingCharacters(in: .whitespacesAndNewlines)
            // Skip sections with empty labels and no usable purpose fallback
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

        // Parse emotional arc
        let emotionalArc: [EmotionDataPoint]? = response.emotionalArc?.compactMap { point in
            guard let emotion = SwipeEmotion(rawValue: point.emotion) else { return nil }
            return EmotionDataPoint(
                position: point.position,
                intensity: point.intensity,
                emotion: emotion
            )
        }

        // Compute dominant emotion
        var dominantEmotion: SwipeEmotion? = nil
        if let arc = emotionalArc, !arc.isEmpty {
            var emotionIntensity: [SwipeEmotion: Double] = [:]
            for point in arc {
                emotionIntensity[point.emotion, default: 0] += point.intensity
            }
            dominantEmotion = emotionIntensity.max(by: { $0.value < $1.value })?.key
        }

        // Parse persuasion techniques
        let persuasionTechniques: [PersuasionTechnique]? = response.persuasionTechniques?.compactMap { t in
            guard let type = PersuasionType(rawValue: t.type) else { return nil }
            return PersuasionTechnique(
                type: type,
                intensity: t.intensity,
                example: t.example
            )
        }

        let persuasionStack: [String: Double]? = persuasionTechniques.flatMap { techniques in
            techniques.isEmpty ? nil : Dictionary(uniqueKeysWithValues: techniques.map { ($0.type.rawValue, $0.intensity) })
        }

        // Build fingerprint
        let sentimentQ = response.sentimentQuartiles ?? [0, 0, 0, 0]
        let intensityQ = response.intensityQuartiles ?? [0, 0, 0, 0]
        let techniqueMap = Dictionary(
            uniqueKeysWithValues: (persuasionTechniques ?? []).map { ($0.type, $0.intensity) }
        )
        let techniqueWeights = PersuasionType.allCases.map { techniqueMap[$0] ?? 0 }

        let fingerprint = StructuralFingerprint(
            sentimentArc: sentimentQ,
            intensityArc: intensityQ,
            techniqueWeights: techniqueWeights,
            sectionCount: sections?.count ?? 0,
            hookType: nil, // Will be filled from local NLP
            frameworkType: frameworkType
        )

        var result = SwipeAnalysis(
            hookScore: response.hookScore,
            frameworkType: frameworkType,
            sections: sections,
            dominantEmotion: dominantEmotion,
            emotionalArc: emotionalArc,
            persuasionTechniques: persuasionTechniques,
            persuasionStack: persuasionStack,
            keyInsight: response.keyInsight,
            fingerprint: fingerprint,
            hookScoreReason: response.hookScoreReason,
            analysisVersion: SwipeClassificationEngine.currentSchemaVersion + 1,
            analyzedAt: ISO8601.string(from: Date()),
            isFullyAnalyzed: true,
            primaryNarrative: primaryNarrative,
            secondaryNarrative: secondaryNarrative,
            swipeContentFormat: contentFormat,
            niche: response.niche,
            creatorUUID: creatorUUID,
            classifiedAt: Date(),
            classificationSource: .ai,
            classificationConfidence: response.classificationConfidence
        )
        result.hookMechanism = response.hookMechanism
        result.structuralRecipe = response.structuralRecipe
        result.voiceMarkers = response.voiceMarkers
        return result
    }

    // MARK: - Creator Resolution

    /// 60s creator-list cache: batch classification resolved creators once
    /// per swipe with a full-table fetch each time (4 queries/swipe).
    private static var creatorCache: (atoms: [Atom], fetchedAt: Date)?

    private static func cachedCreators() async throws -> [Atom] {
        if let cache = creatorCache, Date().timeIntervalSince(cache.fetchedAt) < 60 {
            return cache.atoms
        }
        let fresh = try await AtomRepository.shared.fetchCreators()
        creatorCache = (fresh, Date())
        return fresh
    }

    private static func invalidateCreatorCache() {
        creatorCache = nil
    }

    /// Find or create a creator atom based on handle/name from the AI response.
    /// Returns the creator's UUID if resolved.
    /// Internal: SwipeInsightEngine delegates creator resolution here.
    func resolveCreator(handle: String?, name: String?, atom: Atom) async -> String? {
        guard let handle = handle, !handle.isEmpty else { return nil }

        // Skip purely numeric handles (Instagram user IDs leaked through)
        let stripped = handle.replacingOccurrences(of: "@", with: "")
        guard !stripped.allSatisfy(\.isNumber) else { return nil }

        // Normalize handle
        let normalizedHandle = handle.hasPrefix("@") ? handle : "@\(handle)"
        let displayName = name ?? normalizedHandle

        // Detect platform from atom metadata
        let platform = atom.researchMetadata?.contentSource ?? "unknown"

        // Backfill: if the stored author was a numeric ID, update it with the real handle
        await backfillAuthor(normalizedHandle, on: atom)

        do {
            // Search existing creators by handle (60s cache — batch classification
            // was re-fetching the whole creators table once per swipe).
            let existing = try await Self.cachedCreators()
            let match = existing.first { creator in
                guard let meta = creator.metadataValue(as: CreatorMetadata.self) else { return false }
                return meta.handle?.lowercased() == normalizedHandle.lowercased()
            }

            if let match = match {
                // Link swipe to creator
                await linkSwipeToCreator(swipeAtom: atom, creatorUUID: match.uuid)
                return match.uuid
            }

            // Create new creator
            let newCreator = try await AtomRepository.shared.createCreator(
                name: displayName,
                handle: normalizedHandle,
                platform: platform
            )
            Self.invalidateCreatorCache() // next resolve must see the new creator

            // Link swipe to creator
            await linkSwipeToCreator(swipeAtom: atom, creatorUUID: newCreator.uuid)

            return newCreator.uuid
        } catch {
            print("SwipeClassificationEngine: Creator resolution failed: \(error)")
            return nil
        }
    }

    /// If the stored author is a numeric ID, replace it with the real handle from AI classification.
    private func backfillAuthor(_ handle: String, on atom: Atom) async {
        guard var rc = atom.richContent else { return }
        let currentAuthor = rc.author ?? ""
        // Only backfill if current author is empty or purely numeric
        let isNumericOrEmpty = currentAuthor.isEmpty || currentAuthor.replacingOccurrences(of: "@", with: "").allSatisfy(\.isNumber)
        guard isNumericOrEmpty else { return }

        rc.author = handle
        if var igData = rc.instagramData {
            igData.authorUsername = handle.replacingOccurrences(of: "@", with: "")
            rc.instagramData = igData
        }

        var updated = atom
        updated.setRichContent(rc)
        try? await AtomRepository.shared.update(updated)
    }

    /// Add bidirectional links between swipe and creator
    private func linkSwipeToCreator(swipeAtom: Atom, creatorUUID: String) async {
        // Add swipe -> creator link
        let existingLinks = swipeAtom.linksList
        let alreadyLinked = existingLinks.contains { $0.linkType == .swipeToCreator && $0.uuid == creatorUUID }
        guard !alreadyLinked else { return }

        let updatedSwipe = swipeAtom.addingLink(.swipeToCreator(creatorUUID))
        try? await AtomRepository.shared.update(updatedSwipe)

        // Add creator -> swipe link
        if var creator = try? await AtomRepository.shared.fetch(uuid: creatorUUID) {
            let creatorAlreadyLinked = creator.linksList.contains {
                $0.linkType == .creatorToSwipe && $0.uuid == swipeAtom.uuid
            }
            if !creatorAlreadyLinked {
                creator = creator.addingLink(.creatorToSwipe(swipeAtom.uuid))
                try? await AtomRepository.shared.update(creator)
            }
        }
    }

    /// Update creator aggregate stats (swipeCount, avgHookScore, topNarratives)
    /// Internal: SwipeInsightEngine delegates stats refresh here.
    func updateCreatorStats(creatorUUID: String) async {
        guard var creator = try? await AtomRepository.shared.fetch(uuid: creatorUUID) else { return }
        guard var meta = creator.metadataValue(as: CreatorMetadata.self) else { return }

        // Count linked swipes
        let swipeLinks = creator.links(ofType: .creatorToSwipe)
        meta.swipeCount = swipeLinks.count

        // Compute average hook score and top narratives from linked swipes
        var totalHookScore = 0.0
        var hookScoreCount = 0
        var narrativeCounts: [String: Int] = [:]
        var formatCounts: [String: Int] = [:]

        for link in swipeLinks {
            if let swipe = try? await AtomRepository.shared.fetch(uuid: link.uuid),
               let analysis = swipe.swipeAnalysis {
                if let score = analysis.hookScore, score > 0 {
                    totalHookScore += score
                    hookScoreCount += 1
                }
                if let narrative = analysis.primaryNarrative {
                    narrativeCounts[narrative.rawValue, default: 0] += 1
                }
                if let format = analysis.swipeContentFormat {
                    formatCounts[format.rawValue, default: 0] += 1
                }
            }
        }

        if hookScoreCount > 0 {
            meta.averageHookScore = totalHookScore / Double(hookScoreCount)
        }

        // Top 3 narratives
        let sortedNarratives = narrativeCounts.sorted { $0.value > $1.value }
        meta.topNarratives = Array(sortedNarratives.prefix(3).map(\.key))

        // Top 3 formats
        let sortedFormats = formatCounts.sorted { $0.value > $1.value }
        meta.topFormats = Array(sortedFormats.prefix(3).map(\.key))

        creator = creator.withMetadata(meta)
        try? await AtomRepository.shared.update(creator)
    }

    // MARK: - Persistence

    private func persistAnalysis(_ analysis: SwipeAnalysis, to atom: Atom) async {
        // Re-fetch the live row: the passed `atom` was captured before a long
        // Claude call, and writing its structured column back would clobber
        // anything saved during the call (slide edits, comments, engagement).
        let fresh = (try? await AtomRepository.shared.fetch(uuid: atom.uuid)) ?? atom
        // `analysis` is freshly built — carry over curated fields (engagement,
        // study state, comments, slides, manual taxonomy) before persisting.
        let merged = analysis.preservingCuratedFields(from: fresh.swipeAnalysis)
        let updated = fresh.withSwipeAnalysis(merged)
        // Use field-level update to only write structured (where swipeAnalysis lives)
        // This prevents overwriting user edits to body/title/metadata
        do {
            _ = try await AtomRepository.shared.updateFields(uuid: atom.uuid, columns: [
                "structured": updated.structured,
            ])
        } catch {
            PersistenceHealth.note(
                .writeFailure,
                context: "SwipeClassificationEngine.persistAnalysis(\(atom.uuid.prefix(8)))",
                detail: error.localizedDescription
            )
        }
    }

    // MARK: - Text Extraction

    /// Extract analyzable text from an atom (same logic as SwipeAnalyzer)
    private func extractText(from atom: Atom) -> String {
        if let body = atom.body, !body.isEmpty {
            if let transcriptText = extractTranscriptText(from: body) {
                return transcriptText
            }
            return body
        }

        if let structuredStr = atom.structured,
           let data = structuredStr.data(using: .utf8) {
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

        return atom.title ?? ""
    }

    private func extractTranscriptText(from body: String) -> String? {
        guard let data = body.data(using: .utf8) else { return nil }
        struct SegmentText: Codable {
            var text: String?
        }
        if let segments = try? JSONDecoder().decode([SegmentText].self, from: data) {
            let joined = segments.compactMap(\.text).joined(separator: " ")
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    private func transcriptionContext(from atom: Atom) -> String {
        guard let analysis = atom.swipeAnalysis else { return "" }

        let rawSlides = analysis.rawTranscriptSlides ?? analysis.transcriptSlides ?? []
        let speechSegments = analysis.transcriptSpeechSegments ?? []
        let inferredContentType = inferredTranscriptionContentType(rawSlides: rawSlides, speechSegments: speechSegments)

        var lines: [String] = []
        if let inferredContentType {
            lines.append("Inferred Transcription Modality: \(inferredContentType.rawValue)")
        }
        if !rawSlides.isEmpty {
            let visualSlides = rawSlides.filter { ($0.source ?? .manual) != .speechAudio }
            lines.append("Transcript Slide Count: \(rawSlides.count)")
            lines.append("Visual Slide Count: \(visualSlides.count)")
        }
        if !speechSegments.isEmpty {
            lines.append("Speech Segment Count: \(speechSegments.count)")
        }
        if let quality = analysis.transcriptionQuality {
            lines.append("Transcription Quality: \(quality.rawValue)")
        }
        if let warnings = analysis.transcriptionWarnings, !warnings.isEmpty {
            lines.append("Transcription Warnings: \(warnings.joined(separator: " | "))")
        }

        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    private func inferredTranscriptionContentType(
        rawSlides: [TranscriptSlide],
        speechSegments: [TranscriptSegment]
    ) -> TranscriptionContentType? {
        let nonEmptySlides = rawSlides.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let hasSpeech = !speechSegments.isEmpty

        guard !nonEmptySlides.isEmpty || hasSpeech else { return nil }
        if !hasSpeech { return .textOnly }

        let hasVisualSlides = nonEmptySlides.contains { ($0.source ?? .manual) != .speechAudio }
        if !hasVisualSlides { return .voiceoverOnly }
        return .voiceoverPlusText
    }
}
