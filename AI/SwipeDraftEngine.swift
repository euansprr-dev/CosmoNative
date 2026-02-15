// CosmoOS/AI/SwipeDraftEngine.swift
// Swipe-Powered AI Drafting Engine
// Takes an idea + matching swipes and produces a draft package informed by
// the structural patterns, hooks, and emotional arcs of top-performing swipe files.

import Foundation

// MARK: - Data Models

struct ContentDraftPackage: Codable, Sendable {
    var suggestedOutline: [DraftOutlineItem]
    var hookVariants: [String]
    var structuralBlueprint: String
    var emotionalArcTarget: String
    var firstDraft: String?
    var swipeReferences: [SwipeReference]
    var confidence: Double
}

/// Draft-specific outline item (distinct from ContentFocusModeState.OutlineItem)
struct DraftOutlineItem: Codable, Sendable, Identifiable {
    var id: String
    var title: String
    var description: String
    var estimatedDuration: String?
    var emotion: String?
}

struct SwipeReference: Codable, Sendable, Identifiable {
    var id: String
    var swipeUUID: String
    var swipeTitle: String
    var contribution: String
    var hookScore: Double?
}

// MARK: - SwipeDraftEngine

@MainActor
final class SwipeDraftEngine {

    static let shared = SwipeDraftEngine()

    private init() {}

    // MARK: - Generate Draft Package

    /// Generates a full draft package from an idea and its matching swipes.
    /// Makes a single Claude call via ResearchService to produce outline, hooks,
    /// structural blueprint, and emotional arc target.
    func generateDraftPackage(
        idea: Atom,
        targetFormat: ContentFormat,
        matchingSwipes: [Atom],
        clientProfile: Atom?
    ) async -> ContentDraftPackage? {
        let ideaTitle = idea.title ?? "Untitled Idea"
        let ideaBody = idea.body ?? ""
        let _ = ideaBody.isEmpty ? ideaTitle : "\(ideaTitle)\n\n\(ideaBody)"

        // Build swipe reference material
        let swipeContext = buildSwipeContext(from: matchingSwipes)
        let swipeRefs = buildSwipeReferences(from: matchingSwipes)

        // Build client voice guidelines
        let clientContext = buildClientContext(from: clientProfile)

        // Build format-specific instructions
        let formatInstructions = formatSpecificInstructions(for: targetFormat)

        let prompt = """
        You are a content strategist analyzing successful content patterns to create an original content plan.

        ## The Idea
        Title: \(ideaTitle)
        Description: \(ideaBody)
        Target Format: \(targetFormat.displayName)

        ## Reference Swipe Files (Top-Performing Content Patterns)
        These are high-performing content pieces analyzed for structural patterns. Use them as inspiration — do NOT copy them.

        \(swipeContext)

        \(clientContext)

        ## Format-Specific Requirements
        \(formatInstructions)

        ## Instructions
        Synthesize the patterns from the reference swipe files into an ORIGINAL content plan for the idea above. Do not copy the swipes — extract what makes them work and apply those patterns to new content.

        Return ONLY valid JSON with no markdown formatting:
        {
          "outline": [
            {
              "title": "Section title",
              "description": "What this section covers and achieves",
              "estimatedDuration": "30s",
              "emotion": "curiosity"
            }
          ],
          "hookVariants": [
            "Hook option 1 text",
            "Hook option 2 text",
            "Hook option 3 text",
            "Hook option 4 text",
            "Hook option 5 text"
          ],
          "structuralBlueprint": "Markdown description of the recommended structure, pacing, and flow",
          "emotionalArcTarget": "Description of the recommended emotional journey (e.g., curiosity -> tension -> relief -> aspiration)"
        }

        Valid emotions: curiosity, urgency, aspiration, fear, desire, awe, frustration, relief, belonging, exclusivity

        Generate exactly 5 hook variants. Make them varied in style (question, bold claim, story, statistic, curiosity gap).
        The outline should have 3-7 sections depending on the format.
        """

        do {
            let response = try await ResearchService.shared.analyzeContent(prompt: prompt)
            let cleaned = stripCodeFences(from: response)

            guard let data = cleaned.data(using: .utf8) else {
                print("SwipeDraftEngine: Response not valid UTF-8")
                return nil
            }

            let parsed = try JSONDecoder().decode(DraftPackageResponse.self, from: data)

            let outlineItems = parsed.outline.map { item in
                DraftOutlineItem(
                    id: UUID().uuidString,
                    title: item.title,
                    description: item.description,
                    estimatedDuration: item.estimatedDuration,
                    emotion: item.emotion
                )
            }

            // Calculate confidence based on swipe data quality
            let confidence = calculateConfidence(matchingSwipes: matchingSwipes)

            return ContentDraftPackage(
                suggestedOutline: outlineItems,
                hookVariants: Array(parsed.hookVariants.prefix(5)),
                structuralBlueprint: parsed.structuralBlueprint,
                emotionalArcTarget: parsed.emotionalArcTarget,
                firstDraft: nil,
                swipeReferences: swipeRefs,
                confidence: confidence
            )
        } catch {
            print("SwipeDraftEngine: Draft package generation failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Generate First Draft

    /// Takes an existing draft package and generates a complete first draft text.
    func generateFirstDraft(
        idea: Atom,
        draftPackage: ContentDraftPackage,
        targetFormat: ContentFormat
    ) async -> String? {
        let ideaTitle = idea.title ?? "Untitled Idea"
        let ideaBody = idea.body ?? ""

        // Serialize outline for context
        let outlineSummary = draftPackage.suggestedOutline.enumerated().map { index, item in
            "\(index + 1). \(item.title): \(item.description)"
        }.joined(separator: "\n")

        // Pick best hook (first variant)
        let selectedHook = draftPackage.hookVariants.first ?? ""

        let prompt = """
        You are a skilled content writer. Write a complete first draft based on this content plan.

        ## Idea
        Title: \(ideaTitle)
        Description: \(ideaBody)
        Format: \(targetFormat.displayName)

        ## Opening Hook
        \(selectedHook)

        ## Content Outline
        \(outlineSummary)

        ## Structure
        \(draftPackage.structuralBlueprint)

        ## Emotional Arc
        \(draftPackage.emotionalArcTarget)

        ## Instructions
        Write the complete draft following the outline and emotional arc.
        Use the hook as the opening line.
        Match the tone and pacing to the target format (\(targetFormat.displayName)).
        Be specific, punchy, and value-dense. Avoid filler.
        Return ONLY the draft text — no JSON, no markdown headings like "# Draft", no meta-commentary.
        """

        do {
            let response = try await ResearchService.shared.analyzeContent(prompt: prompt)
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            print("SwipeDraftEngine: First draft generation failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private Helpers

    /// Build rich context from matching swipe atoms for the prompt.
    private func buildSwipeContext(from swipes: [Atom]) -> String {
        guard !swipes.isEmpty else { return "No reference swipes available." }

        var context = ""
        for (index, swipe) in swipes.prefix(5).enumerated() {
            let analysis = swipe.swipeAnalysis
            let title = swipe.title ?? "Untitled"
            let body = swipe.body ?? ""
            let hookText = analysis?.hookText ?? "N/A"
            let hookType = analysis?.hookType?.displayName ?? "Unknown"
            let framework = analysis?.frameworkType?.displayName ?? "Unknown"
            let hookScore = analysis?.hookScore.map { String(format: "%.1f", $0) } ?? "N/A"
            let emotion = analysis?.dominantEmotion?.displayName ?? "N/A"

            // Build emotional arc summary
            var arcSummary = "N/A"
            if let arc = analysis?.emotionalArc, !arc.isEmpty {
                let emotions = arc.prefix(5).map { $0.emotion.displayName }
                arcSummary = emotions.joined(separator: " -> ")
            }

            // Build persuasion techniques
            var persuasionSummary = "N/A"
            if let techniques = analysis?.persuasionTechniques, !techniques.isEmpty {
                persuasionSummary = techniques.prefix(3).map { $0.type.rawValue }.joined(separator: ", ")
            }

            // Include a snippet of the actual content (truncated)
            let contentSnippet = String(body.prefix(300))

            context += """
            ### Swipe \(index + 1): "\(title)"
            - Hook [\(hookType)]: \(hookText)
            - Hook Score: \(hookScore)/10
            - Framework: \(framework)
            - Dominant Emotion: \(emotion)
            - Emotional Arc: \(arcSummary)
            - Persuasion: \(persuasionSummary)
            - Content Preview: \(contentSnippet)\(body.count > 300 ? "..." : "")

            """
        }

        return context
    }

    /// Build SwipeReference array from matching swipe atoms.
    private func buildSwipeReferences(from swipes: [Atom]) -> [SwipeReference] {
        swipes.prefix(5).map { swipe in
            let analysis = swipe.swipeAnalysis
            var contributions: [String] = []

            if analysis?.hookType != nil { contributions.append("hook pattern") }
            if analysis?.frameworkType != nil { contributions.append("structure") }
            if analysis?.emotionalArc != nil { contributions.append("emotional arc") }
            if analysis?.persuasionTechniques != nil { contributions.append("persuasion techniques") }

            return SwipeReference(
                id: UUID().uuidString,
                swipeUUID: swipe.uuid,
                swipeTitle: swipe.title ?? "Untitled Swipe",
                contribution: contributions.isEmpty ? "topic relevance" : contributions.joined(separator: ", "),
                hookScore: analysis?.hookScore
            )
        }
    }

    /// Build client voice/style context for the prompt.
    /// Tries ClientProfileMetadata (rich format) first, falls back to ClientMetadata.
    private func buildClientContext(from clientProfile: Atom?) -> String {
        guard let client = clientProfile else { return "" }

        // Try rich profile metadata first (ContentPipelineService format)
        if let richMeta = client.metadataValue(as: ClientProfileMetadata.self) {
            return "## Client Voice & Style\n" + richMeta.toAIContextString()
        }

        // Fallback to legacy ClientMetadata
        guard let meta = client.metadataValue(as: ClientMetadata.self) else {
            return ""
        }

        var lines: [String] = ["## Client Voice & Style"]
        lines.append("Client: \(client.title ?? "Unknown")")

        if let niche = meta.niche {
            lines.append("Niche: \(niche)")
        }
        if let brandVoice = meta.brandVoice {
            lines.append("Brand Voice: \(brandVoice)")
        }
        if let formats = meta.preferredFormats, !formats.isEmpty {
            lines.append("Preferred Formats: \(formats.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }

    /// Return format-specific writing instructions.
    private func formatSpecificInstructions(for format: ContentFormat) -> String {
        switch format {
        case .voiceoverReel, .oneSliderReel, .multiSliderReel, .reel:
            return """
            This is a short-form video (Reel/TikTok). Requirements:
            - Script should be 30-90 seconds when read aloud
            - Hook must grab attention in the first 2 seconds
            - Each section should be a visual scene or text overlay beat
            - End with a clear CTA (follow, save, comment)
            - Pacing: fast, punchy, no filler sentences
            """
        case .twoStepCTA:
            return """
            This is a two-step CTA reel. Requirements:
            - First part delivers value/entertainment
            - Second part pivots to a specific call-to-action
            - Keep total length under 60 seconds
            - The CTA transition should feel natural, not salesy
            """
        case .carousel:
            return """
            This is an Instagram carousel. Requirements:
            - Design for 5-10 slides
            - First slide = hook (must stop the scroll)
            - Each slide = one key point with supporting detail
            - Last slide = CTA + summary
            - Text must be scannable (short paragraphs, bullet points)
            """
        case .tweet:
            return """
            This is a single tweet/post. Requirements:
            - Maximum 280 characters
            - Must be self-contained and complete
            - Hook IS the entire content
            - Optimize for engagement (likes, retweets, replies)
            """
        case .thread:
            return """
            This is a Twitter/X thread. Requirements:
            - First tweet = hook (the only one most people see)
            - 5-15 tweets total
            - Each tweet should be valuable standalone
            - Build momentum and escalate value
            - End with summary + CTA + "follow for more"
            """
        case .longForm:
            return """
            This is a long-form article/blog post. Requirements:
            - 1000-3000 words
            - Strong headline and opening paragraph
            - Use subheadings, bullet points, and formatting
            - Include specific examples and data
            - End with actionable takeaways
            """
        case .youtube:
            return """
            This is a YouTube video script. Requirements:
            - Hook in the first 10 seconds (before the viewer clicks away)
            - Include timestamps/sections for each major topic
            - Estimated duration per section
            - Pattern interrupts every 2-3 minutes
            - End with CTA (subscribe, like, next video)
            """
        case .newsletter:
            return """
            This is a newsletter. Requirements:
            - Compelling subject line suggestion
            - Personal, conversational tone
            - One main idea with supporting examples
            - Actionable takeaway or framework
            - PS line with secondary CTA
            """
        case .post:
            return """
            This is a social media post. Requirements:
            - Hook in the first line
            - Value-dense body (3-5 short paragraphs)
            - End with a question or CTA to drive engagement
            - Use line breaks for readability
            """
        }
    }

    /// Calculate confidence score based on swipe data quality.
    private func calculateConfidence(matchingSwipes: [Atom]) -> Double {
        guard !matchingSwipes.isEmpty else { return 0.1 }

        var score: Double = 0

        // More swipes = higher base confidence
        let swipeCountFactor = min(Double(matchingSwipes.count) / 5.0, 1.0) * 0.3
        score += swipeCountFactor

        // Average analysis completeness
        var analysisCompleteness: Double = 0
        for swipe in matchingSwipes {
            if let analysis = swipe.swipeAnalysis {
                var fields: Double = 0
                if analysis.hookType != nil { fields += 1 }
                if analysis.frameworkType != nil { fields += 1 }
                if analysis.emotionalArc != nil { fields += 1 }
                if analysis.hookScore != nil { fields += 1 }
                if analysis.persuasionTechniques != nil { fields += 1 }
                analysisCompleteness += fields / 5.0
            }
        }
        let avgCompleteness = analysisCompleteness / Double(matchingSwipes.count)
        score += avgCompleteness * 0.4

        // Average hook score quality
        let hookScores = matchingSwipes.compactMap { $0.swipeAnalysis?.hookScore }
        if !hookScores.isEmpty {
            let avgHookScore = hookScores.reduce(0, +) / Double(hookScores.count)
            score += (avgHookScore / 10.0) * 0.3
        }

        return min(score, 1.0)
    }

    /// Strip markdown code fences from a response string.
    private func stripCodeFences(from response: String) -> String {
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

        return jsonStr
    }
}

// MARK: - JSON Response Types

private struct DraftPackageResponse: Codable {
    let outline: [OutlineResponse]
    let hookVariants: [String]
    let structuralBlueprint: String
    let emotionalArcTarget: String
}

private struct OutlineResponse: Codable {
    let title: String
    let description: String
    let estimatedDuration: String?
    let emotion: String?
}
