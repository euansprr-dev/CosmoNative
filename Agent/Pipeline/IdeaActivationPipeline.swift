// CosmoOS/Agent/Pipeline/IdeaActivationPipeline.swift
// Full orchestration for idea → content activation
// Runs analysis, finds swipes, recommends frameworks, creates content atom,
// awards XP, and reports back via Telegram

import Foundation

// MARK: - Activation Result

/// Result of a full idea activation pipeline run
struct ActivationResult: Sendable {
    let ideaUUID: String
    let contentUUID: String
    let ideaTitle: String
    let matchingSwipeCount: Int
    let recommendedFramework: String?
    let hookSuggestions: [String]
    let analysisComplete: Bool
}

// MARK: - IdeaActivationPipeline

/// Orchestrates the full idea-to-content activation flow.
/// NOT a singleton — instantiate per activation.
///
/// Usage:
/// ```swift
/// let pipeline = IdeaActivationPipeline()
/// let result = await pipeline.activate(ideaUUID: "abc-123", chatId: telegramChatId)
/// ```
@MainActor
class IdeaActivationPipeline {

    // MARK: - Dependencies

    private let atomRepo = AtomRepository.shared
    private let insightEngine = IdeaInsightEngine.shared

    // MARK: - Init

    init() {}

    // MARK: - Activate

    /// Full idea activation orchestration:
    /// 1. Fetch idea atom
    /// 2. Run full analysis if none exists
    /// 3. Find matching swipes
    /// 4. Get framework recommendations
    /// 5. Create content atom linked to idea
    /// 6. Update idea status to "inProduction"
    /// 7. Award 10 XP
    /// 8. Send summary to Telegram
    func activate(ideaUUID: String, chatId: String?) async -> ActivationResult {
        // ── 1. Fetch idea atom ──
        let ideaAtom: Atom
        do {
            guard let fetched = try await atomRepo.fetch(uuid: ideaUUID) else {
                let errorResult = emptyResult(ideaUUID: ideaUUID, reason: "Idea not found")
                if let cid = chatId { await notifyTelegram(chatId: cid, text: "Activation failed: idea not found.") }
                return errorResult
            }
            ideaAtom = fetched
        } catch {
            let errorResult = emptyResult(ideaUUID: ideaUUID, reason: error.localizedDescription)
            if let cid = chatId { await notifyTelegram(chatId: cid, text: "Activation failed: \(error.localizedDescription)") }
            return errorResult
        }

        guard ideaAtom.type == .idea else {
            let errorResult = emptyResult(ideaUUID: ideaUUID, reason: "Atom is not an idea")
            if let cid = chatId { await notifyTelegram(chatId: cid, text: "Activation failed: atom is not an idea type.") }
            return errorResult
        }

        let ideaTitle = ideaAtom.title ?? "Untitled Idea"
        let ideaText = ideaAtom.body ?? ideaAtom.title ?? ""

        if let cid = chatId {
            await notifyTelegram(chatId: cid, text: "Activating: \"\(ideaTitle)\"...")
        }

        // ── 2. Run full analysis if no existing insight ──
        var insight: IdeaInsight
        let existingInsight = ideaAtom.structuredValue(as: IdeaInsight.self)

        if let existing = existingInsight, existing.isFullyAnalyzed {
            insight = existing
        } else {
            if let cid = chatId {
                await notifyTelegram(chatId: cid, text: "Running full analysis...")
            }
            insight = await insightEngine.fullAnalysis(atom: ideaAtom)

            // Persist the analysis to the idea atom's structured field
            do {
                _ = try await atomRepo.update(uuid: ideaUUID) { atom in
                    if let data = try? JSONEncoder().encode(insight),
                       let json = String(data: data, encoding: .utf8) {
                        atom.structured = json
                    }
                }
            } catch {
                print("[IdeaActivationPipeline] Failed to save analysis: \(error.localizedDescription)")
            }
        }

        // ── 3. Gather matching swipes ──
        let matchingSwipes = insight.matchingSwipes ?? []
        let swipeCount = matchingSwipes.count

        // ── 4. Get framework recommendations ──
        let frameworks = insight.frameworkRecommendations ?? []
        let topFramework = frameworks.first
        let frameworkName = topFramework?.framework.displayName

        // ── 5. Gather hook suggestions ──
        let hookSuggestions: [String] = (insight.hookSuggestions ?? []).map(\.hookText)

        // ── 6. Create content atom linked to idea ──
        var contentUUID = ""
        do {
            let swipeUUIDs = matchingSwipes.map(\.swipeAtomUUID)

            let contentMeta = ContentAtomMetadata(
                phase: .ideation,
                platform: nil,
                clientProfileUUID: ideaAtom.ideaClientUUID,
                wordCount: ideaText.split(separator: " ").count,
                sourceIdeaUUID: ideaUUID,
                inheritedSwipeUUIDs: swipeUUIDs.isEmpty ? nil : swipeUUIDs,
                inheritedFramework: frameworkName,
                inheritedHooks: hookSuggestions.isEmpty ? nil : Array(hookSuggestions.prefix(5)),
                activatedAt: ISO8601.string(from: Date())
            )
            let contentMetaJSON = encodeJSON(contentMeta)

            // Build links
            var links: [AtomLink] = [
                AtomLink(type: "sourceIdea", uuid: ideaUUID, entityType: "idea")
            ]
            for swipe in matchingSwipes.prefix(3) {
                links.append(AtomLink(type: "matchedSwipe", uuid: swipe.swipeAtomUUID, entityType: "research"))
            }

            // Use idea body as core idea (not draft content)
            let contentAtom = Atom.new(
                type: .content,
                title: ideaTitle,
                body: nil, // Draft starts empty — idea body is the seed, not the draft
                metadata: contentMetaJSON,
                links: links
            )
            let saved = try await atomRepo.create(contentAtom)
            contentUUID = saved.uuid
        } catch {
            print("[IdeaActivationPipeline] Failed to create content atom: \(error.localizedDescription)")
            if let cid = chatId {
                await notifyTelegram(chatId: cid, text: "Warning: content creation failed, but idea was analyzed.")
            }
        }

        // ── 7. Update idea status to inProduction ──
        do {
            _ = try await atomRepo.update(uuid: ideaUUID) { atom in
                var meta = atom.metadataValue(as: IdeaMetadata.self) ?? IdeaMetadata()
                meta.ideaStatus = .inProduction
                if let data = try? JSONEncoder().encode(meta),
                   let json = String(data: data, encoding: .utf8) {
                    atom.metadata = json
                }
            }
        } catch {
            print("[IdeaActivationPipeline] Failed to update idea status: \(error.localizedDescription)")
        }

        // ── 8. Award 10 XP via xpEvent atom ──
        do {
            let xpMeta: [String: Any] = [
                "amount": 10,
                "source": "idea_activation",
                "dimension": "creative",
                "relatedAtomUUID": ideaUUID
            ]
            let xpMetaJSON = dictToJSON(xpMeta)

            let xpAtom = Atom.new(
                type: .xpEvent,
                title: "Idea Activated: \(ideaTitle)",
                metadata: xpMetaJSON,
                links: [AtomLink(type: "source", uuid: ideaUUID, entityType: "idea")]
            )
            _ = try await atomRepo.create(xpAtom)
        } catch {
            print("[IdeaActivationPipeline] Failed to award XP: \(error.localizedDescription)")
        }

        // ── 9. Build result ──
        let result = ActivationResult(
            ideaUUID: ideaUUID,
            contentUUID: contentUUID,
            ideaTitle: ideaTitle,
            matchingSwipeCount: swipeCount,
            recommendedFramework: frameworkName,
            hookSuggestions: hookSuggestions,
            analysisComplete: insight.isFullyAnalyzed
        )

        // ── 10. Send summary to Telegram ──
        if let cid = chatId {
            let summaryText = formatActivationSummary(result)
            await notifyTelegram(chatId: cid, text: summaryText)
        }

        return result
    }

    // MARK: - Propose Activation

    /// Preview what activation would do without executing.
    /// Returns a formatted proposal message suitable for Telegram display.
    func proposeActivation(ideaUUID: String) async -> String {
        do {
            guard let ideaAtom = try await atomRepo.fetch(uuid: ideaUUID) else {
                return "Idea not found (UUID: \(ideaUUID.prefix(8))...)"
            }

            let title = ideaAtom.title ?? "Untitled Idea"
            let ideaText = ideaAtom.body ?? ideaAtom.title ?? ""
            let wordCount = ideaText.split(separator: " ").count
            let status = ideaAtom.ideaStatus?.displayName ?? "spark"

            // Check for existing analysis
            let existingInsight = ideaAtom.structuredValue(as: IdeaInsight.self)
            let hasAnalysis = existingInsight?.isFullyAnalyzed ?? false

            // Quick swipe check
            let quickSwipes = await insightEngine.findMatchingSwipes(ideaText: ideaText, limit: 3)
            let swipePreview = quickSwipes.isEmpty
                ? "No matching swipes found yet"
                : "\(quickSwipes.count) matching swipes (top: \(quickSwipes.first?.title ?? "—"))"

            // Quick insight for hook/framework preview
            let quickInsight = insightEngine.quickInsight(ideaText: ideaText)
            let hookPreview = quickInsight.suggestedHookType?.displayName ?? "auto-detect"
            let frameworkPreview = quickInsight.suggestedFramework?.displayName ?? "auto-select"

            var proposal = """
            Found: "\(title)"
            Status: \(status) | \(wordCount) words

            Activation plan:
            """

            if hasAnalysis {
                let swipeCount = existingInsight?.matchingSwipes?.count ?? 0
                let fw = existingInsight?.frameworkRecommendations?.first?.framework.displayName ?? "auto"
                proposal += "\n  - Skip analysis (already complete: \(swipeCount) swipes, \(fw))"
            } else {
                proposal += "\n  - Run full analysis (hook: \(hookPreview), framework: \(frameworkPreview))"
            }

            proposal += """

              - Find matching swipes (\(swipePreview))
              - Recommend content framework
              - Create content atom linked to idea
              - Update status: \(status) -> In Production
              - Award 10 XP (Creative dimension)
            """

            return proposal.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "Error loading idea: \(error.localizedDescription)"
        }
    }

    // MARK: - Format Summary

    /// Format an ActivationResult into a human-readable summary for Telegram.
    func formatActivationSummary(_ result: ActivationResult) -> String {
        var lines: [String] = []

        lines.append("Idea activated!")
        lines.append("")
        lines.append("\"\(result.ideaTitle)\"")
        lines.append("")
        lines.append("Matching swipes: \(result.matchingSwipeCount)")

        if let fw = result.recommendedFramework {
            lines.append("Framework: \(fw)")
        }

        if !result.hookSuggestions.isEmpty {
            lines.append("")
            lines.append("Hook suggestions:")
            for (index, hook) in result.hookSuggestions.prefix(3).enumerated() {
                let truncated = hook.count > 60 ? String(hook.prefix(57)) + "..." : hook
                lines.append("  \(index + 1). \(truncated)")
            }
        }

        lines.append("")
        lines.append("Analysis: \(result.analysisComplete ? "complete" : "partial")")
        lines.append("+10 XP (Creative)")

        if !result.contentUUID.isEmpty {
            lines.append("")
            lines.append("Content piece created. Open CosmoOS to start drafting.")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    /// Send a message via Telegram.
    private func notifyTelegram(chatId: String, text: String) async {
        await TelegramBridgeService.shared.sendMessage(
            chatId: chatId,
            text: text,
            parseMode: nil,
            replyMarkup: nil
        )
    }

    /// Create an empty/error ActivationResult.
    private func emptyResult(ideaUUID: String, reason: String) -> ActivationResult {
        ActivationResult(
            ideaUUID: ideaUUID,
            contentUUID: "",
            ideaTitle: reason,
            matchingSwipeCount: 0,
            recommendedFramework: nil,
            hookSuggestions: [],
            analysisComplete: false
        )
    }

    /// Encode a Codable value to a JSON string.
    private func encodeJSON<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Convert a [String: Any] dictionary to a JSON string.
    private func dictToJSON(_ dict: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Atom Extension (Structured Value)

private extension Atom {
    /// Decode the structured JSON field into a Codable type.
    func structuredValue<T: Decodable>(as type: T.Type) -> T? {
        guard let structured = structured,
              let data = structured.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }
}
