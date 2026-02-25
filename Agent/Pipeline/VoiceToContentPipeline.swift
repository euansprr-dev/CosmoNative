// CosmoOS/Agent/Pipeline/VoiceToContentPipeline.swift
// Voice note → researched, outlined, drafted content piece
// Orchestrates the full voice-to-content workflow: transcription → swipe matching →
// idea creation → insight analysis → framework recommendation → content draft

import Foundation

// MARK: - Pipeline Step Types

/// Tracks the progress of a single pipeline step
struct PipelineStep {
    let name: String
    let description: String
    var status: StepStatus = .pending
    var result: String?
}

/// Status of a pipeline step
enum StepStatus: String, Sendable {
    case pending
    case running
    case completed
    case failed
}

/// Result of the full voice-to-content pipeline
struct PipelineResult: Sendable {
    let ideaUUID: String?
    let contentUUID: String?
    let matchingSwipeCount: Int
    let recommendedFramework: String?
    let draftBody: String?
    let summary: String
}

// MARK: - VoiceToContentPipeline

/// Orchestrates the full voice-to-content workflow.
/// NOT a singleton — instantiate per pipeline run.
///
/// Usage:
/// ```swift
/// let pipeline = VoiceToContentPipeline(chatId: "12345")
/// let result = await pipeline.execute(transcribedText: "Thread idea: 5 lessons...")
/// ```
@MainActor
class VoiceToContentPipeline {

    // MARK: - Properties

    /// Telegram chat ID for progress updates (empty string disables Telegram reporting)
    let chatId: String

    /// Ordered steps for progress tracking
    private(set) var steps: [PipelineStep]

    /// Current step index (0-based)
    private(set) var currentStep: Int = 0

    /// Atom repository for persistence
    private let atomRepo = AtomRepository.shared

    // MARK: - Init

    init(chatId: String = "") {
        self.chatId = chatId
        self.steps = [
            PipelineStep(name: "Search Swipes", description: "Searching swipe library for matching content patterns"),
            PipelineStep(name: "Create Idea", description: "Saving your voice note as an idea atom"),
            PipelineStep(name: "Quick Insight", description: "Running on-device NLP analysis"),
            PipelineStep(name: "Find Matching Swipes", description: "Finding semantically similar swipe files"),
            PipelineStep(name: "Recommend Framework", description: "Selecting the best content framework"),
            PipelineStep(name: "Create Content", description: "Creating content atom linked to idea"),
            PipelineStep(name: "Generate Draft", description: "Assembling draft from transcription + insights"),
        ]
    }

    // MARK: - Execute Full Pipeline

    /// Run the full voice-to-content pipeline.
    /// Each step sends a progress update to Telegram if chatId is set.
    /// Returns a PipelineResult with all UUIDs, matching swipe count, framework, and draft body.
    func execute(transcribedText: String) async -> PipelineResult {
        let cleanText = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            return PipelineResult(
                ideaUUID: nil,
                contentUUID: nil,
                matchingSwipeCount: 0,
                recommendedFramework: nil,
                draftBody: nil,
                summary: "Empty transcription — nothing to process."
            )
        }

        // ── Step 1: Search swipe library for matching content ──
        currentStep = 0
        markStep(0, status: .running)
        await sendProgress(step: 0, message: "Searching your swipe library...")

        var hybridSearchResults: [HybridSearchEngine.SearchResult] = []
        do {
            hybridSearchResults = try await HybridSearchEngine.shared.search(
                query: cleanText,
                limit: 10,
                entityTypes: [.research]
            )
            markStep(0, status: .completed, result: "Found \(hybridSearchResults.count) matching entries")
        } catch {
            markStep(0, status: .failed, result: "Search failed: \(error.localizedDescription)")
            // Non-fatal — continue without search results
        }

        // ── Step 2: Create idea atom from transcribed text ──
        currentStep = 1
        markStep(1, status: .running)
        await sendProgress(step: 1, message: "Saving as idea...")

        let ideaTitle = extractTitle(from: cleanText)

        var ideaUUID: String?
        do {
            let ideaMeta = IdeaMetadata(ideaStatus: .spark)
            let ideaMetaJSON = encodeJSON(ideaMeta)

            let ideaAtom = Atom.new(
                type: .idea,
                title: ideaTitle,
                body: cleanText,
                metadata: ideaMetaJSON
            )
            let saved = try await atomRepo.create(ideaAtom)
            ideaUUID = saved.uuid
            markStep(1, status: .completed, result: "Idea created: \(ideaTitle)")
        } catch {
            markStep(1, status: .failed, result: "Failed to create idea: \(error.localizedDescription)")
            return PipelineResult(
                ideaUUID: nil,
                contentUUID: nil,
                matchingSwipeCount: hybridSearchResults.count,
                recommendedFramework: nil,
                draftBody: nil,
                summary: "Failed to save idea: \(error.localizedDescription)"
            )
        }

        // ── Step 3: Run quick insight analysis ──
        currentStep = 2
        markStep(2, status: .running)
        await sendProgress(step: 2, message: "Analyzing your idea...")

        let quickInsight = IdeaInsightEngine.shared.quickInsight(ideaText: cleanText)
        let suggestedHook = quickInsight.suggestedHookType?.displayName ?? "none detected"
        let keywords = quickInsight.topicKeywords.prefix(5).joined(separator: ", ")
        markStep(2, status: .completed, result: "Hook: \(suggestedHook) | Keywords: \(keywords)")

        // ── Step 4: Find matching swipes via vector search ──
        currentStep = 3
        markStep(3, status: .running)
        await sendProgress(step: 3, message: "Finding matching swipe files...")

        let matchingSwipes = await IdeaInsightEngine.shared.findMatchingSwipes(
            ideaText: cleanText,
            limit: 5
        )
        let swipeCount = matchingSwipes.count
        markStep(3, status: .completed, result: "Found \(swipeCount) matching swipes")

        // ── Step 5: Get framework recommendations ──
        currentStep = 4
        markStep(4, status: .running)
        await sendProgress(step: 4, message: "Selecting content framework...")

        let frameworks = IdeaInsightEngine.shared.recommendFrameworks(
            ideaText: cleanText,
            matchingSwipes: matchingSwipes,
            targetFormat: nil
        )
        let topFramework = frameworks.first
        let frameworkName = topFramework?.framework.displayName
        markStep(4, status: .completed, result: "Recommended: \(frameworkName ?? "none")")

        // ── Step 6: Create content atom linked to idea ──
        currentStep = 5
        markStep(5, status: .running)
        await sendProgress(step: 5, message: "Creating content piece...")

        var contentUUID: String?
        do {
            let swipeUUIDs = matchingSwipes.map(\.swipeAtomUUID)
            let hookTexts = matchingSwipes.compactMap(\.hookText)

            let contentMeta = ContentAtomMetadata(
                phase: .ideation,
                platform: nil,
                clientProfileUUID: nil,
                wordCount: cleanText.split(separator: " ").count,
                sourceIdeaUUID: ideaUUID,
                inheritedSwipeUUIDs: swipeUUIDs.isEmpty ? nil : swipeUUIDs,
                inheritedFramework: frameworkName,
                inheritedHooks: hookTexts.isEmpty ? nil : Array(hookTexts.prefix(3))
            )
            let contentMetaJSON = encodeJSON(contentMeta)

            var links: [AtomLink] = []
            if let iUUID = ideaUUID {
                links.append(AtomLink(type: "sourceIdea", uuid: iUUID, entityType: "idea"))
            }
            for swipe in matchingSwipes.prefix(3) {
                links.append(AtomLink(type: "matchedSwipe", uuid: swipe.swipeAtomUUID, entityType: "research"))
            }

            let contentAtom = Atom.new(
                type: .content,
                title: ideaTitle,
                body: nil,
                metadata: contentMetaJSON,
                links: links.isEmpty ? nil : links
            )
            let saved = try await atomRepo.create(contentAtom)
            contentUUID = saved.uuid
            markStep(5, status: .completed, result: "Content atom created")
        } catch {
            markStep(5, status: .failed, result: "Failed to create content: \(error.localizedDescription)")
            // Non-fatal — return partial result
        }

        // ── Step 7: Generate draft body ──
        currentStep = 6
        markStep(6, status: .running)
        await sendProgress(step: 6, message: "Assembling your draft...")

        let draftBody = assembleDraft(
            transcribedText: cleanText,
            quickInsight: quickInsight,
            matchingSwipes: matchingSwipes,
            framework: topFramework
        )

        // Save draft body to content atom
        if let cUUID = contentUUID, !draftBody.isEmpty {
            do {
                _ = try await atomRepo.update(uuid: cUUID) { atom in
                    atom.body = draftBody
                }
            } catch {
                print("[VoiceToContentPipeline] Failed to save draft body: \(error.localizedDescription)")
            }
        }

        markStep(6, status: .completed, result: "Draft assembled (\(draftBody.split(separator: " ").count) words)")

        // ── Final summary ──
        let summary = buildSummary(
            ideaTitle: ideaTitle,
            swipeCount: swipeCount,
            frameworkName: frameworkName,
            draftWordCount: draftBody.split(separator: " ").count
        )

        await sendProgress(step: steps.count, message: summary)

        return PipelineResult(
            ideaUUID: ideaUUID,
            contentUUID: contentUUID,
            matchingSwipeCount: swipeCount,
            recommendedFramework: frameworkName,
            draftBody: draftBody,
            summary: summary
        )
    }

    // MARK: - Propose Plan (Preview Without Executing)

    /// Generate a plan message describing what the pipeline would do, without executing.
    /// Returns a formatted message suitable for Telegram with inline keyboard options.
    func proposePlan(transcribedText: String) async -> String {
        let cleanText = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            return "Nothing to process — empty voice note."
        }

        let title = extractTitle(from: cleanText)
        let wordCount = cleanText.split(separator: " ").count

        // Quick on-device analysis for the proposal
        let quickInsight = IdeaInsightEngine.shared.quickInsight(ideaText: cleanText)
        let hookLabel = quickInsight.suggestedHookType?.displayName ?? "auto-detect"
        let frameworkLabel = quickInsight.suggestedFramework?.displayName ?? "auto-select"
        let keywordsPreview = quickInsight.topicKeywords.prefix(3).joined(separator: ", ")

        // Check swipe library size estimate
        var swipeEstimate = "searching"
        do {
            let quickResults = try await HybridSearchEngine.shared.search(
                query: cleanText,
                limit: 3,
                entityTypes: [.research]
            )
            swipeEstimate = "\(quickResults.count)+ potential matches"
        } catch {
            swipeEstimate = "available"
        }

        let plan = """
        I'll build this into content:

        "\(title)" (\(wordCount) words)

        Step 1: Search swipe library (\(swipeEstimate))
        Step 2: Save as idea atom
        Step 3: Run NLP analysis (hook: \(hookLabel))
        Step 4: Find matching swipes for inspiration
        Step 5: Select framework (\(frameworkLabel))
        Step 6: Create content piece linked to idea
        Step 7: Assemble draft from voice + swipe insights

        Topics: \(keywordsPreview.isEmpty ? "general" : keywordsPreview)
        """

        return plan.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Progress Reporting

    /// Send a Telegram progress update for the current step.
    func sendProgress(step: Int, message: String) async {
        guard !chatId.isEmpty else { return }

        let totalSteps = steps.count
        let stepLabel: String
        if step < totalSteps {
            let progressBar = buildProgressBar(current: step + 1, total: totalSteps)
            stepLabel = "\(progressBar) Step \(step + 1)/\(totalSteps)\n\(message)"
        } else {
            // Final summary
            stepLabel = "Done!\n\n\(message)"
        }

        await TelegramBridgeService.shared.sendMessage(
            chatId: chatId,
            text: stepLabel,
            parseMode: nil,
            replyMarkup: nil
        )
    }

    // MARK: - Private Helpers

    /// Mark a step's status and optionally store its result string.
    private func markStep(_ index: Int, status: StepStatus, result: String? = nil) {
        guard index < steps.count else { return }
        steps[index].status = status
        if let result = result {
            steps[index].result = result
        }
    }

    /// Extract a title from the first line or first ~80 characters of the transcription.
    private func extractTitle(from text: String) -> String {
        // Check for format-prefixed patterns (e.g., "thread idea: ...")
        let lowered = text.lowercased()
        let prefixes = ["thread idea:", "reel idea:", "carousel idea:", "newsletter idea:", "article idea:"]
        for prefix in prefixes {
            if lowered.hasPrefix(prefix) {
                let afterPrefix = text.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
                if !afterPrefix.isEmpty {
                    return String(afterPrefix.prefix(80))
                }
            }
        }

        // Use first sentence or first 80 characters
        let firstLine = text.components(separatedBy: CharacterSet.newlines).first ?? text
        let firstSentence = firstLine.components(separatedBy: ".").first ?? firstLine
        let candidate = firstSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.count > 80 {
            return String(candidate.prefix(77)) + "..."
        }
        return candidate.isEmpty ? "Voice Note" : candidate
    }

    /// Assemble a draft body from the transcribed text, analysis, and matching swipes.
    private func assembleDraft(
        transcribedText: String,
        quickInsight: QuickInsightResult,
        matchingSwipes: [SwipeMatch],
        framework: FrameworkRecommendation?
    ) -> String {
        var sections: [String] = []

        // Header with framework context
        if let fw = framework {
            sections.append("// Framework: \(fw.framework.displayName)")
            sections.append("// \(fw.rationale)")
            sections.append("")
        }

        // Core idea from transcription
        sections.append("## Core Idea")
        sections.append("")
        sections.append(transcribedText)
        sections.append("")

        // Hook suggestions from matching swipes
        let hookTexts = matchingSwipes.compactMap(\.hookText)
        if !hookTexts.isEmpty {
            sections.append("## Hook Inspiration")
            sections.append("")
            for (index, hook) in hookTexts.prefix(3).enumerated() {
                sections.append("\(index + 1). \(hook)")
            }
            sections.append("")
        }

        // Keywords for reference
        if !quickInsight.topicKeywords.isEmpty {
            sections.append("## Key Topics")
            sections.append(quickInsight.topicKeywords.joined(separator: " | "))
            sections.append("")
        }

        // Matched swipe references
        if !matchingSwipes.isEmpty {
            sections.append("## Reference Swipes")
            sections.append("")
            for swipe in matchingSwipes.prefix(3) {
                let score = Int(swipe.similarityScore * 100)
                let hookType = swipe.hookType?.displayName ?? "—"
                sections.append("- \(swipe.title) (\(score)% match, hook: \(hookType))")
            }
            sections.append("")
        }

        return sections.joined(separator: "\n")
    }

    /// Build a progress bar string (e.g., "##----" for 2/6)
    private func buildProgressBar(current: Int, total: Int) -> String {
        let filled = String(repeating: "#", count: current)
        let empty = String(repeating: "-", count: max(0, total - current))
        return "[\(filled)\(empty)]"
    }

    /// Build the final summary message.
    private func buildSummary(
        ideaTitle: String,
        swipeCount: Int,
        frameworkName: String?,
        draftWordCount: Int
    ) -> String {
        var parts: [String] = []
        parts.append("Voice-to-Content pipeline complete!")
        parts.append("")
        parts.append("Title: \(ideaTitle)")
        parts.append("Matching swipes: \(swipeCount)")
        if let fw = frameworkName {
            parts.append("Framework: \(fw)")
        }
        parts.append("Draft: \(draftWordCount) words")
        return parts.joined(separator: "\n")
    }

    /// Encode a Codable value to a JSON string, returning nil on failure.
    private func encodeJSON<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
