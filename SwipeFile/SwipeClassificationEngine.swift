// CosmoOS/SwipeFile/SwipeClassificationEngine.swift
// Unified AI classification + deep analysis engine for swipe files
// Single Claude call produces taxonomy classification AND structural analysis
// February 2026

import Foundation

@MainActor
final class SwipeClassificationEngine: ObservableObject {
    static let shared = SwipeClassificationEngine()

    @Published var isClassifying = false

    /// Current schema version — bump when classification prompt/output format changes
    static let currentSchemaVersion = 1

    private init() {}

    // MARK: - Main Pipeline

    /// Classify and deep-analyze a swipe atom in a single Claude call.
    /// Returns an enriched SwipeAnalysis with taxonomy fields + deep analysis.
    func classifyAndAnalyze(atom: Atom) async -> SwipeAnalysis {
        isClassifying = true
        defer { isClassifying = false }

        let text = extractText(from: atom)
        guard !text.isEmpty else {
            return SwipeAnalysis(analysisVersion: 1, isFullyAnalyzed: false)
        }

        // Build the unified prompt
        let prompt = buildUnifiedPrompt(atom: atom, text: text)

        do {
            let response = try await ResearchService.shared.analyzeContent(prompt: prompt)
            let parsed = parseResponse(response)

            if let parsed = parsed {
                // Resolve creator
                let creatorUUID = await resolveCreator(
                    handle: parsed.creatorHandle,
                    name: parsed.creatorName,
                    atom: atom
                )

                // Build the enriched analysis
                var analysis = buildAnalysis(from: parsed, creatorUUID: creatorUUID)

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

        // Bump version
        merged.analysisVersion = max(merged.analysisVersion, SwipeClassificationEngine.currentSchemaVersion + 1)
        merged.analyzedAt = ISO8601DateFormatter().string(from: Date())
        merged.isFullyAnalyzed = true

        return merged
    }

    // MARK: - Prompt Building

    private func buildUnifiedPrompt(atom: Atom, text: String) -> String {
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

        // Build available taxonomy values lists
        let narrativeValues = NarrativeStyle.allCases.map { $0.rawValue }.joined(separator: ", ")
        let formatValues = ContentFormat.allCases.map { $0.rawValue }.joined(separator: ", ")
        let frameworkValues = SwipeFrameworkType.allCases.map { $0.rawValue }.joined(separator: ", ")

        return """
        You are a content intelligence analyst. Analyze this content and return a single JSON object that covers BOTH taxonomy classification AND structural analysis.

        Title: \(title)
        URL: \(url)
        Platform: \(platform)
        Creator/Author: \(author)
        oEmbed Title: \(oembedTitle)
        Transcript (first 4000 words): \(truncated)

        ## Taxonomy Classification
        Classify the content across these dimensions:

        Narrative Styles (pick primary and optional secondary): \(narrativeValues)
        Content Formats: \(formatValues)
        Niche: A short label for the content vertical (e.g., "Real Estate Wholesaling", "Fitness", "SaaS Marketing")
        Creator: Extract the creator's handle (@username) and display name if identifiable

        ## Structural Analysis
        Also provide deep structural analysis:

        Frameworks: \(frameworkValues)
        Valid emotions: curiosity, urgency, aspiration, fear, desire, awe, frustration, relief, belonging, exclusivity
        Valid persuasion types: socialProof, curiosityGap, contrastEffect, authority, scarcity, urgency, reciprocity, storytelling, lossAversion, exclusivity, anchoring, framing

        Return ONLY valid JSON with no markdown formatting:
        {
          "primaryNarrative": "studentSuccess",
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

        return SwipeAnalysis(
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
            analyzedAt: ISO8601DateFormatter().string(from: Date()),
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
    }

    // MARK: - Creator Resolution

    /// Find or create a creator atom based on handle/name from the AI response.
    /// Returns the creator's UUID if resolved.
    private func resolveCreator(handle: String?, name: String?, atom: Atom) async -> String? {
        guard let handle = handle, !handle.isEmpty else { return nil }

        // Normalize handle
        let normalizedHandle = handle.hasPrefix("@") ? handle : "@\(handle)"
        let displayName = name ?? normalizedHandle

        // Detect platform from atom metadata
        let platform = atom.researchMetadata?.contentSource ?? "unknown"

        do {
            // Search existing creators by handle
            let existing = try await AtomRepository.shared.fetchCreators()
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

            // Link swipe to creator
            await linkSwipeToCreator(swipeAtom: atom, creatorUUID: newCreator.uuid)

            return newCreator.uuid
        } catch {
            print("SwipeClassificationEngine: Creator resolution failed: \(error)")
            return nil
        }
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
    private func updateCreatorStats(creatorUUID: String) async {
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
        let updated = atom.withSwipeAnalysis(analysis)
        try? await AtomRepository.shared.update(updated)
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
}
