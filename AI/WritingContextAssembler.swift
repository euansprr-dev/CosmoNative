// CosmoOS/AI/WritingContextAssembler.swift
// Shared 4-layer mega-context assembly for writing-adjacent engines
// (ContentScorecardEngine, RedTeamEngine, etc.)
// Extracted from OpusWritingEngine — February 2026

import Foundation

/// Assembles the 4-layer cached mega-context prompt used by scoring and analysis engines.
/// Layer 1: Content methodology (PromptTemplateStore)
/// Layer 2: Client profile (Intelligence Model or legacy fields)
/// Layer 3: Swipe intelligence (BeatPatternService + matched swipes + task context)
/// Layer 4: Knowledge context (KnowledgeContextAssembler)
@MainActor
enum WritingContextAssembler {

    // MARK: - Public API

    /// Assembles a 4-layer mega-context prompt with cache control boundaries.
    static func assembleCachedMegaContext(contentAtom: Atom) async -> PromptContext {
        let layer1 = assembleLayer1()
        let layer2 = await assembleLayer2(contentAtom: contentAtom)
        let layer3 = await assembleLayer3(contentAtom: contentAtom)
        let layer4 = await assembleLayer4(contentAtom: contentAtom)

        var blocks: [(content: String, cacheControl: Bool)] = []

        // Layer 1: Methodology — stable across ALL requests, always cached
        blocks.append((content: layer1, cacheControl: true))

        // Layer 2: Client profile — stable per client, cached per client
        if !layer2.isEmpty {
            blocks.append((content: layer2, cacheControl: true))
        }

        // Layer 3: Swipe intelligence — changes per content piece
        if !layer3.isEmpty {
            blocks.append((content: layer3, cacheControl: true))
        }

        // Layer 4: Knowledge context — connections relevant to this content piece
        if !layer4.isEmpty {
            blocks.append((content: layer4, cacheControl: true))
        }

        return PromptContext(systemBlocks: blocks, modelTier: .writer)
    }

    // MARK: - Layer 1: Methodology

    private static func assembleLayer1() -> String {
        return """
        === LAYER 1: CONTENT METHODOLOGY ===

        \(PromptTemplateStore.shared.assemblePrompt(for: "general"))
        """
    }

    // MARK: - Layer 2: Client Profile

    private static func assembleLayer2(contentAtom: Atom) async -> String {
        let metadata = contentAtom.metadataValue(as: ContentAtomMetadata.self)

        var profileAtom: Atom?
        if let clientUUID = metadata?.clientProfileUUID {
            profileAtom = try? await AtomRepository.shared.fetch(uuid: clientUUID)
        }

        guard let profileAtom = profileAtom,
              let clientMeta = profileAtom.metadataValue(as: ClientProfileMetadata.self) else {
            return ""
        }

        if clientMeta.intelligenceModel != nil {
            return assembleIntelligenceModelLayer2(
                profileAtom: profileAtom,
                clientMeta: clientMeta,
                contentAtom: contentAtom
            )
        }

        return assembleLegacyLayer2(clientMeta: clientMeta)
    }

    /// Intelligence Model path: model summary + top transcripts + story + failure fingerprint
    private static func assembleIntelligenceModelLayer2(
        profileAtom: Atom,
        clientMeta: ClientProfileMetadata,
        contentAtom: Atom
    ) -> String {
        var lines: [String] = []
        lines.append("=== LAYER 2: CLIENT PROFILE (Intelligence Model) ===")
        lines.append("")
        lines.append("Client: \(clientMeta.clientName)")
        if let handle = clientMeta.handle { lines.append("Handle: \(handle)") }

        let platforms = clientMeta.platforms.map(\.displayName).joined(separator: ", ")
        if !platforms.isEmpty { lines.append("Platforms: \(platforms)") }
        lines.append("")

        // Block 1: Intelligence Model summary
        let modelSummary = ClientIntelligenceEngine.shared.getModelForDrafting(profile: profileAtom)
        if !modelSummary.isEmpty {
            lines.append("--- INTELLIGENCE MODEL ---")
            lines.append(modelSummary)
            lines.append("")
        }

        // Block 2: Format-grouped top transcripts
        let reelTranscripts = ClientIntelligenceEngine.shared.getTopTranscripts(
            profile: profileAtom, count: 10, category: .reel
        )
        if !reelTranscripts.isEmpty {
            lines.append("--- TOP PERFORMING REELS (\(reelTranscripts.count) posts) ---")
            for (i, transcript) in reelTranscripts.enumerated() {
                let truncated = transcript.count > 3000 ? String(transcript.prefix(3000)) + "..." : transcript
                lines.append("Reel #\(i + 1):\n\(truncated)")
                lines.append("")
            }
        }

        let threadTranscripts = ClientIntelligenceEngine.shared.getTopTranscripts(
            profile: profileAtom, count: 10, category: .thread
        )
        if !threadTranscripts.isEmpty {
            lines.append("--- TOP PERFORMING THREADS (\(threadTranscripts.count) posts) ---")
            for (i, transcript) in threadTranscripts.enumerated() {
                let truncated = transcript.count > 3000 ? String(transcript.prefix(3000)) + "..." : transcript
                lines.append("Thread #\(i + 1):\n\(truncated)")
                lines.append("")
            }
        }

        // Block 3: Story context
        if let documents = clientMeta.documents {
            let storyDocs = documents.filter { $0.category == .story }
            if !storyDocs.isEmpty {
                lines.append("--- BRAND STORY CONTEXT ---")
                for doc in storyDocs.prefix(2) {
                    let truncated = doc.content.count > 2000 ? String(doc.content.prefix(2000)) + "..." : doc.content
                    lines.append(truncated)
                }
                lines.append("")
            }
        }

        // Block 4: Failure Fingerprint
        if let model = clientMeta.intelligenceModel {
            let contentMeta = contentAtom.metadataValue(as: ContentAtomMetadata.self)

            let formatFingerprint: FailureFingerprint?
            if contentMeta?.platform == .instagram || contentMeta?.platform == .tiktok || contentMeta?.platform == .youtube {
                formatFingerprint = model.reelFailureFingerprint ?? model.failureFingerprint
            } else if contentMeta?.platform == .twitter || contentMeta?.platform == .linkedin {
                formatFingerprint = model.threadFailureFingerprint ?? model.failureFingerprint
            } else {
                formatFingerprint = model.failureFingerprint
            }

            if let fingerprint = formatFingerprint, !fingerprint.rules.isEmpty {
                lines.append("--- FAILURE FINGERPRINT ---")
                lines.append("Based on analysis of \(fingerprint.topPerformerCount) top performers vs \(fingerprint.underperformerCount) underperformers:")
                lines.append("")
                for rule in fingerprint.rules {
                    lines.append("[\(rule.severity.rawValue.uppercased())] \(rule.rule)")
                    lines.append("  Best: \(rule.bestMetric) | Worst: \(rule.worstMetric) | Delta: \(rule.delta)")
                }
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Legacy field-based assembly for profiles without Intelligence Model.
    private static func assembleLegacyLayer2(clientMeta: ClientProfileMetadata) -> String {
        var lines: [String] = []
        lines.append("=== LAYER 2: CLIENT PROFILE ===")
        lines.append("")
        lines.append("Client: \(clientMeta.clientName)")

        if let niche = clientMeta.niche { lines.append("Niche: \(niche)") }
        if let industry = clientMeta.industry { lines.append("Industry: \(industry)") }
        if let audience = clientMeta.targetAudience { lines.append("Target Audience: \(audience)") }
        if let handle = clientMeta.handle { lines.append("Handle: \(handle)") }

        if let brandStory = clientMeta.brandStory, !brandStory.isEmpty {
            lines.append("Brand Story: \(brandStory)")
        }
        if let brandVision = clientMeta.brandVision, !brandVision.isEmpty {
            lines.append("Brand Vision: \(brandVision)")
        }
        if let voiceNotes = clientMeta.voiceNotes, !voiceNotes.isEmpty {
            lines.append("Voice & Tone: \(voiceNotes)")
        }
        if let uniqueAngle = clientMeta.uniqueAngle, !uniqueAngle.isEmpty {
            lines.append("Unique Angle: \(uniqueAngle)")
        }
        if let beliefs = clientMeta.coreBeliefs, !beliefs.isEmpty {
            lines.append("Core Beliefs: \(beliefs.joined(separator: ", "))")
        }
        if let phrases = clientMeta.signaturePhrases, !phrases.isEmpty {
            lines.append("Signature Phrases: \(phrases.joined(separator: " | "))")
        }

        if let posts = clientMeta.topPerformingPosts, !posts.isEmpty {
            lines.append("")
            lines.append("--- TOP PERFORMING CONTENT ---")
            for (i, post) in posts.prefix(5).enumerated() {
                lines.append("Top #\(i + 1) [\(post.platform), \(post.likes) likes, \(post.shares) shares, \(post.views) views]:")
                lines.append(post.transcript)
            }
        } else if let transcripts = clientMeta.topPerformingTranscripts, !transcripts.isEmpty {
            lines.append("")
            lines.append("--- TOP PERFORMING CONTENT ---")
            for (i, transcript) in transcripts.prefix(3).enumerated() {
                lines.append("Top #\(i + 1):\n\(transcript)")
            }
        }

        if let voice = clientMeta.extractedVoicePatterns {
            lines.append("")
            lines.append("--- EXTRACTED VOICE PATTERNS ---")
            lines.append("Avg Sentence Length: \(String(format: "%.1f", voice.avgSentenceLength)) words")
            lines.append("Reading Level: \(voice.readingLevel)")
            lines.append("Emotional Range: \(voice.emotionalRange)")
            if !voice.recurringPhrases.isEmpty {
                lines.append("Recurring Phrases: \(voice.recurringPhrases.joined(separator: " | "))")
            }
            if !voice.stylisticQuirks.isEmpty {
                lines.append("Stylistic Quirks: \(voice.stylisticQuirks.joined(separator: ", "))")
            }
            if !voice.ctaPatterns.isEmpty {
                lines.append("CTA Patterns: \(voice.ctaPatterns.joined(separator: " | "))")
            }
            if !voice.hookStyleDistribution.isEmpty {
                let hookSummary = voice.hookStyleDistribution
                    .sorted { $0.value > $1.value }
                    .prefix(5)
                    .map { "\($0.key) (\($0.value)x)" }
                    .joined(separator: ", ")
                lines.append("Hook Style Distribution: \(hookSummary)")
            }
        }

        if let patterns = clientMeta.preferredBeatPatterns, !patterns.isEmpty {
            lines.append("Preferred Beat Patterns: \(patterns.joined(separator: ", "))")
        }
        if let bestFormats = clientMeta.bestFormats, !bestFormats.isEmpty {
            lines.append("Best Formats: \(bestFormats.joined(separator: ", "))")
        }

        let platforms = clientMeta.platforms.map(\.displayName).joined(separator: ", ")
        if !platforms.isEmpty { lines.append("Platforms: \(platforms)") }

        return lines.joined(separator: "\n")
    }

    // MARK: - Layer 3: Swipe Intelligence

    private static func assembleLayer3(contentAtom: Atom) async -> String {
        let metadata = contentAtom.metadataValue(as: ContentAtomMetadata.self)
        var lines: [String] = []
        lines.append("=== LAYER 3: SWIPE INTELLIGENCE ===")
        lines.append("")

        // Extract niche for pattern queries
        var niche: String?
        if let clientUUID = metadata?.clientProfileUUID,
           let profile = try? await AtomRepository.shared.fetch(uuid: clientUUID),
           let clientMeta = profile.metadataValue(as: ClientProfileMetadata.self) {
            let modelNiche = clientMeta.intelligenceModel?.nicheAndPositioning.specificNiche
            niche = (modelNiche?.isEmpty == false) ? modelNiche : clientMeta.niche
        }

        // Top beat patterns
        let topPatterns = await BeatPatternService.shared.findTopPatterns(niche: niche, limit: 5)
        if !topPatterns.isEmpty {
            lines.append("--- TOP BEAT PATTERNS (by frequency + hook score) ---")
            for (i, pattern) in topPatterns.enumerated() {
                lines.append("Pattern #\(i + 1): \(pattern.fingerprint)")
                lines.append("  Beats: \(pattern.beatSequence.joined(separator: " > "))")
                lines.append("  Frequency: \(pattern.frequency)x | Avg Hook Score: \(String(format: "%.1f", pattern.avgHookScore))/10")
            }
            lines.append("")
        }

        // Matching swipes with full transcripts
        let swipeAtoms = await findMatchingSwipes(for: contentAtom, limit: 30)
        if !swipeAtoms.isEmpty {
            lines.append("--- MATCHING SWIPES (\(swipeAtoms.count) files) ---")
            lines.append("")

            for (index, swipe) in swipeAtoms.enumerated() {
                var swipeLines: [String] = []
                swipeLines.append("SWIPE #\(index + 1): \(swipe.title ?? "Untitled")")

                let analysis = swipe.swipeAnalysis
                if let hookType = analysis?.hookType {
                    swipeLines.append("Hook Type: \(hookType.displayName)")
                }
                if let hookScore = analysis?.hookScore {
                    swipeLines.append("Hook Score: \(String(format: "%.1f", hookScore))/10")
                }
                if let hookText = analysis?.hookText {
                    swipeLines.append("Hook: \"\(hookText)\"")
                }
                if let framework = analysis?.frameworkType {
                    swipeLines.append("Framework: \(framework.displayName)")
                }
                if let fp = analysis?.beatFingerprint, !fp.isEmpty {
                    swipeLines.append("Beat Pattern: \(fp)")
                }

                if let sections = analysis?.sections, !sections.isEmpty {
                    let sectionSummary = sections.map { "\($0.label) (\($0.purpose))" }
                        .joined(separator: " > ")
                    swipeLines.append("Structure: \(sectionSummary)")
                }

                let body = swipe.body ?? ""
                if !body.isEmpty {
                    let truncated = body.count > 3000 ? String(body.prefix(3000)) + "..." : body
                    swipeLines.append("Transcript:\n\(truncated)")
                }

                lines.append(swipeLines.joined(separator: "\n"))
                lines.append("")
            }
        }

        // Content task context
        lines.append("--- CONTENT TASK ---")
        lines.append("Title: \(contentAtom.title ?? "Untitled")")
        if let platform = metadata?.platform {
            lines.append("Platform: \(platform.displayName)")
        }
        let body = contentAtom.body ?? ""
        if !body.isEmpty {
            lines.append("Core Idea:\n\(body)")
        }
        if let framework = metadata?.inheritedFramework {
            lines.append("Selected Framework: \(framework)")
        }
        if let hooks = metadata?.inheritedHooks, !hooks.isEmpty {
            lines.append("Suggested Hooks:")
            for (i, hook) in hooks.enumerated() {
                lines.append("  \(i + 1). \(hook)")
            }
        }
        lines.append("Current Phase: \(metadata?.phase.displayName ?? "Unknown")")

        return lines.joined(separator: "\n")
    }

    // MARK: - Layer 4: Knowledge Context

    private static func assembleLayer4(contentAtom: Atom) async -> String {
        let metadata = contentAtom.metadataValue(as: ContentAtomMetadata.self)
        let profileId = metadata?.clientProfileUUID

        let assembler = KnowledgeContextAssembler()
        let knowledgeContext = await assembler.assembleKnowledgeContext(
            contentAtom: contentAtom,
            profileId: profileId
        )

        guard !knowledgeContext.connections.isEmpty else {
            return ""
        }

        return knowledgeContext.formattedBlock
    }

    // MARK: - Swipe Search

    private static func findMatchingSwipes(for contentAtom: Atom, limit: Int) async -> [Atom] {
        let metadata = contentAtom.metadataValue(as: ContentAtomMetadata.self)

        // First, load inherited swipes directly
        var swipes: [Atom] = []
        if let swipeUUIDs = metadata?.inheritedSwipeUUIDs {
            for uuid in swipeUUIDs {
                if let swipe = try? await AtomRepository.shared.fetch(uuid: uuid) {
                    swipes.append(swipe)
                }
            }
        }

        // If we need more, search via HybridSearchEngine
        if swipes.count < limit {
            let query = contentAtom.title ?? contentAtom.body ?? ""
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return swipes
            }

            let remaining = limit - swipes.count
            let existingUUIDs = Set(swipes.map(\.uuid))

            do {
                let results = try await HybridSearchEngine.shared.search(
                    query: query,
                    limit: remaining + 5,
                    entityTypes: [.research]
                )

                for result in results {
                    guard swipes.count < limit else { break }
                    guard let uuid = result.entityUUID, !existingUUIDs.contains(uuid) else { continue }

                    if let swipe = try? await AtomRepository.shared.fetch(uuid: uuid),
                       swipe.isSwipeFileAtom {
                        swipes.append(swipe)
                    }
                }
            } catch {
                print("WritingContextAssembler: swipe search failed: \(error)")
            }
        }

        return swipes
    }
}
