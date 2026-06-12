// CosmoOS/AI/Craft/CosmoCraftSkillRunner.swift
// MainActor orchestrator for /review and /riff. Replaces the agent tool loop
// for the two craft skills: gathers the surface + comparables + stats in Swift
// (zero tokens), makes one structured engine call, renders the result into the
// assistant pane, and stages riff applies as reviewed diffs for $0.00.
// June 2026

import Foundation

@MainActor
final class CosmoCraftSkillRunner {
    static let shared = CosmoCraftSkillRunner()

    /// Per-surface-per-skill conversation state so follow-ups ("what about
    /// slide 4?", "apply 2") keep their context and their cache prefix.
    private struct CraftSession {
        var messages: [(role: String, content: String)] = []
        var lastRiff: CraftRiffResult?
        var lastSourceHash: String?
        var format: CraftFormat = .carousel
    }

    private var sessions: [String: CraftSession] = [:]

    private init() {}

    // MARK: - Routing

    /// The craft path owns a request only when the resolved skill is one of the
    /// two craft skills. Slash/sticky selection wins; otherwise the same keyword
    /// plan the agent bridge would compute decides — so interception never
    /// changes WHICH skill runs, only HOW it runs.
    nonisolated static func resolveCraftSkillID(
        selectedSkillID: String?,
        prompt: String,
        surfaceKind: CosmoEditableSurfaceKind?
    ) -> CosmoInlineAssistantSkillID? {
        guard surfaceKind != .canvas else { return nil }
        let plan = CosmoInlineAssistantSkillRuntime.plan(
            for: prompt,
            surfaceKind: surfaceKind,
            previousSkillID: nil,
            selectedSkillID: selectedSkillID
        )
        let id = plan.primarySkill.id
        return (id == .contentReview || id == .voiceVariations) ? id : nil
    }

    // MARK: - Entry

    func run(
        prompt: String,
        skillID: CosmoInlineAssistantSkillID,
        store: CosmoInlineAssistantStore
    ) async throws {
        // Session binding happens in submit(), atomically with the user's
        // message — never here, where it would swap the visible conversation.
        let activeSurface = CosmoEditableSurfaceRegistry.shared.activeSurface
        let snapshot = activeSurface?.editableSnapshot()

        guard let snapshot,
              !snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            store.receivePaneAnswer(
                title: nil,
                answer: "Open a content piece first — I review and riff against the draft you're looking at.",
                route: .answer
            )
            return
        }

        let sessionKey = "\(snapshot.surfaceID)|\(skillID.rawValue)"

        // Zero-cost path: "apply 2" stages the chosen riff variation as a
        // reviewed diff straight from the cached result — no model call.
        if skillID == .voiceVariations,
           let index = CraftRiffApplyParser.variationIndex(in: prompt),
           let riff = sessions[sessionKey]?.lastRiff {
            applyRiffVariation(index: index, riff: riff, prompt: prompt, snapshot: snapshot, store: store)
            return
        }

        store.receiveToolActivity(.started(
            name: "craft_context",
            displayLabel: "Reading \(snapshot.title)",
            args: [:]
        ))

        let atom = await resolveContentAtom(snapshot: snapshot)
        let clientAtom = await resolveClientAtom(prompt: prompt, contentAtom: atom)
        let format = CraftFormatDetector.detect(atom: atom, draftText: snapshot.text)
        let slides = CraftDraftParser.slides(in: snapshot.text)

        store.receiveToolActivity(.completed(
            name: "craft_context",
            displayLabel: "Read \(snapshot.title)",
            resultPreview: "\(format.displayName) · \(slides.count) slides"
        ))

        let isFollowUp = isFollowUpTurn(sessionKey: sessionKey, prompt: prompt, skillID: skillID)

        var comparables: [CraftComparable] = []
        var stats = CraftFormatStats(
            format: format, sampleCount: 0, medianViews: nil, topQuartileViews: nil,
            medianEngagementRate: nil, hookTypeLeaderboard: [], typicalSlideRange: nil
        )

        if !isFollowUp {
            store.receiveToolActivity(.started(
                name: "craft_comparables",
                displayLabel: "Selecting comparables from the swipe library",
                args: [:]
            ))
            let swipeAtoms = (try? await AtomRepository.shared.fetchAll(type: .research)) ?? []
            let clientMeta = clientAtom?.metadataValue(as: ClientProfileMetadata.self)
            let query = CraftComparableQuery(
                format: format,
                draftTitle: snapshot.title,
                draftText: snapshot.text,
                clientNiche: clientMeta?.niche
            )
            comparables = await CraftComparableSelector.select(
                from: swipeAtoms,
                query: query,
                embed: Self.daemonEmbedder
            )
            stats = CraftStatsBuilder.build(format: format, swipeAtoms: swipeAtoms)
            store.receiveToolActivity(.completed(
                name: "craft_comparables",
                displayLabel: "Selected comparables",
                resultPreview: "\(comparables.count) transcripts · \(stats.sampleCount) with metrics"
            ))
        }

        store.receiveToolActivity(.started(
            name: "craft_engine",
            displayLabel: skillID == .contentReview ? "Studying the draft against the library" : "Riffing directions for this beat",
            args: [:]
        ))

        var session = sessions[sessionKey] ?? CraftSession()
        session.format = format

        let userMessage = buildUserMessage(
            prompt: prompt,
            skillID: skillID,
            snapshot: snapshot,
            format: format,
            slides: slides,
            comparables: comparables,
            stats: stats,
            isFollowUp: isFollowUp,
            previousSourceHash: session.lastSourceHash
        )
        session.messages.append((role: "user", content: userMessage))
        session.messages = Array(session.messages.suffix(10))

        let systemBlocks = buildSystemBlocks(format: format, clientAtom: clientAtom)
        let schema: [String: Any]?
        if skillID == .voiceVariations {
            schema = CosmoCraftEngine.riffSchema
        } else {
            schema = isFollowUp ? nil : CosmoCraftEngine.reviewSchema
        }

        let completion = try await CosmoCraftEngine.complete(
            systemBlocks: systemBlocks,
            messages: session.messages.map { ["role": $0.role, "content": $0.content] },
            jsonSchema: schema
        )

        store.receiveToolActivity(.completed(
            name: "craft_engine",
            displayLabel: "Studied the draft",
            resultPreview: completion.usage.receiptLine
        ))
        store.receiveToolActivity(.allDone(totalCalls: isFollowUp ? 2 : 3))

        session.messages.append((role: "assistant", content: completion.text))
        session.lastSourceHash = snapshot.sourceHash

        let decoder = JSONDecoder()
        let data = Data(completion.text.utf8)

        if skillID == .voiceVariations, let riff = try? decoder.decode(CraftRiffResult.self, from: data) {
            session.lastRiff = riff
            sessions[sessionKey] = session
            store.receivePaneAnswer(
                title: nil,
                answer: CraftAnswerRenderer.markdown(for: riff, usage: completion.usage),
                route: .answer
            )
        } else if skillID == .contentReview, !isFollowUp,
                  let review = try? decoder.decode(CraftReviewResult.self, from: data) {
            sessions[sessionKey] = session
            store.receivePaneAnswer(
                title: nil,
                answer: CraftAnswerRenderer.markdown(for: review, usage: completion.usage),
                route: .answer
            )
        } else {
            // Conversational follow-up (or a decode miss) — the text is the answer.
            sessions[sessionKey] = session
            let footer = "\n\n_\(completion.usage.receiptLine)_"
            store.receivePaneAnswer(title: nil, answer: completion.text + footer, route: .answer)
        }
    }

    // MARK: - Riff apply (zero LLM cost)

    private func applyRiffVariation(
        index: Int,
        riff: CraftRiffResult,
        prompt: String,
        snapshot: CosmoEditableSourceSnapshot,
        store: CosmoInlineAssistantStore
    ) {
        guard index <= riff.variations.count, index >= 1 else {
            store.receivePaneAnswer(
                title: nil,
                answer: "There are only \(riff.variations.count) variations on the table — pick one of those numbers.",
                route: .answer
            )
            return
        }
        let variation = riff.variations[index - 1]
        let original = riff.targetOriginalText

        guard !original.isEmpty else {
            store.receivePaneAnswer(
                title: nil,
                answer: "I don't have a clean handle on the original text for that beat — re-run /riff and I'll grab it.",
                route: .answer
            )
            return
        }

        let operation = CosmoAssistantProposalOperation(
            kind: .textReplacement,
            targetID: snapshot.targetID,
            anchorID: nil,
            originalText: original,
            proposedText: variation.text,
            sourceHash: snapshot.sourceHash,
            rationale: "Riff \(index) — \(variation.mechanism)"
                + (variation.borrowedFrom.isEmpty || variation.borrowedFrom == "none"
                    ? ""
                    : ", pattern from \(variation.borrowedFrom)")
        )
        let proposal = CosmoAssistantProposal(
            prompt: prompt,
            surfaceID: snapshot.surfaceID,
            title: "Riff variation \(index)",
            summary: "Swap the \(riff.beatLabel.lowercased()) for variation \(index) (\(variation.mechanism)). Review the diff in the editor.",
            operations: [operation],
            skillID: CosmoInlineAssistantSkillID.voiceVariations.rawValue
        )
        store.receive(proposal: proposal)
    }

    // MARK: - Context resolution

    private func resolveContentAtom(snapshot: CosmoEditableSourceSnapshot) async -> Atom? {
        for candidate in [snapshot.surfaceID, snapshot.targetID] {
            guard let uuid = candidate.split(separator: ":").last.map(String.init),
                  !uuid.isEmpty else { continue }
            if let atom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                return atom
            }
        }
        return nil
    }

    private func resolveClientAtom(prompt: String, contentAtom: Atom?) async -> Atom? {
        if let reference = CosmoInlineAssistantWorkingContextCache.clientReference(in: prompt),
           let atom = try? await AtomRepository.shared.fuzzyFindClient(query: reference) {
            return atom
        }
        if let meta = contentAtom?.metadataValue(as: ContentAtomMetadata.self),
           let clientUUID = meta.clientProfileUUID,
           let atom = try? await AtomRepository.shared.fetch(uuid: clientUUID),
           atom.type == .clientProfile {
            return atom
        }
        return nil
    }

    private func isFollowUpTurn(sessionKey: String, prompt: String, skillID: CosmoInlineAssistantSkillID) -> Bool {
        guard let session = sessions[sessionKey], !session.messages.isEmpty else { return false }
        // A bare slash re-invocation restarts the task fresh.
        if prompt == "Begin." {
            sessions[sessionKey] = nil
            return false
        }
        // Riffs always re-run the full task shape; reviews converse.
        return skillID == .contentReview
    }

    // MARK: - Prompt assembly

    private func buildSystemBlocks(format: CraftFormat, clientAtom: Atom?) -> [CraftSystemBlock] {
        var blocks: [CraftSystemBlock] = [
            CraftSystemBlock(text: CraftStudyMethod.systemBlock(format: format), cacheTTL: "1h")
        ]
        if let clientAtom,
           let meta = clientAtom.metadataValue(as: ClientProfileMetadata.self) {
            blocks.append(CraftSystemBlock(text: clientPack(atom: clientAtom, meta: meta), cacheTTL: "1h"))
        }
        return blocks
    }

    /// Compact profile + the client's own top-performing raw transcripts — the
    /// voice ground truth. Deterministic rendering keeps the cache block stable
    /// between profile edits.
    private func clientPack(atom: Atom, meta: ClientProfileMetadata) -> String {
        var sections = [
            "## Client Pack — \(meta.clientName)",
            CosmoCompactClientProfile.format(atom: atom, meta: meta)
        ]

        let topPosts = (meta.topPerformingPosts ?? [])
            .filter { !$0.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.views > $1.views }
            .prefix(3)
        if !topPosts.isEmpty {
            let rendered = topPosts.map { post in
                let numbers = [
                    post.views > 0 ? "\(CraftComparable.compact(post.views)) views" : nil,
                    post.likes > 0 ? "\(CraftComparable.compact(post.likes)) likes" : nil
                ].compactMap { $0 }.joined(separator: " · ")
                let transcript = String(post.transcript.prefix(1_500))
                return "<top_post numbers=\"\(numbers)\">\n\(transcript)\n</top_post>"
            }
            sections.append("### The client's own top performers (voice ground truth)\n" + rendered.joined(separator: "\n"))
        } else if let transcripts = meta.topPerformingTranscripts, !transcripts.isEmpty {
            let rendered = transcripts.prefix(3).map { "<top_post>\n\(String($0.prefix(1_500)))\n</top_post>" }
            sections.append("### The client's own top performers (voice ground truth)\n" + rendered.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    private func buildUserMessage(
        prompt: String,
        skillID: CosmoInlineAssistantSkillID,
        snapshot: CosmoEditableSourceSnapshot,
        format: CraftFormat,
        slides: [CraftDraftSlide],
        comparables: [CraftComparable],
        stats: CraftFormatStats,
        isFollowUp: Bool,
        previousSourceHash: String?
    ) -> String {
        if isFollowUp {
            var message = prompt
            if previousSourceHash != snapshot.sourceHash {
                message += "\n\n(The draft changed since your last read. Current draft:)\n<draft>\n\(snapshot.text)\n</draft>"
            }
            return message
        }

        var sections: [String] = []
        sections.append("""
        ## The Draft
        Title: \(snapshot.title)
        Detected format: \(format.displayName) (\(slides.count) slides)

        <draft>
        \(snapshot.text)
        </draft>
        """)

        sections.append("## Library Stats\n\(stats.promptBlock)")

        if comparables.isEmpty {
            sections.append("## Comparables\nNo comparable transcripts available for this format — judge on the craft tests alone and say so explicitly.")
        } else {
            let rendered = comparables.enumerated().map { index, comparable in
                var attrs = "index=\"\(index + 1)\" title=\"\(comparable.title)\" numbers=\"\(comparable.numbersLine)\""
                if let hookType = comparable.hookType { attrs += " hookMechanism=\"\(hookType)\"" }
                if let fingerprint = comparable.beatFingerprint { attrs += " beats=\"\(fingerprint)\"" }
                return "<comparable \(attrs)>\n\(comparable.transcript)\n</comparable>"
            }
            sections.append("## Comparables — raw transcripts with real numbers\n" + rendered.joined(separator: "\n"))
        }

        let task: String
        switch skillID {
        case .voiceVariations:
            task = """
            ## Task — Riff
            The writer is stuck on one beat and wants directions, not a rewrite. Their request: "\(prompt)"

            Identify which beat of the draft they mean (use their words; if genuinely ambiguous, riff the hook). Copy that beat's current text VERBATIM into targetOriginalText. Then write 5–7 variations, each using a genuinely different mechanism, each at \(format.displayName) density, each in the client's voice from the top-performer transcripts. Borrow patterns from the comparables and carry their numbers. Close with the one you'd bet on and why.
            """
        default:
            task = """
            ## Task — Review
            Review this draft with the Transcript Study Method. Read the draft with all three passes, then: performance read (tier + evidence from named comparables with their real numbers), slide notes only where a craft test actually fails (quote the draft's line, name the test), the top 1–3 moves ranked by impact, micro-variations for the single weakest beat only, and a verdict in dinner-table voice. If the draft is strong, say so — do not invent criticism.\(prompt.isEmpty || prompt == "Begin." ? "" : "\n\nThe writer adds: \"\(prompt)\"")
            """
        }
        sections.append(task)

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Embedding

    /// Same daemon + cache + Matryoshka truncation the skill auto-router uses.
    nonisolated private static let daemonEmbedder: CraftComparableSelector.Embedder = { text in
        if let cached = await EmbeddingCache.shared.get(for: text) { return cached }
        guard let full = try? await DaemonXPCClient.shared.embed(text: text) else { return nil }
        let truncated = Array(full.prefix(256))
        await EmbeddingCache.shared.set(truncated, for: text)
        return truncated
    }
}

// MARK: - Markdown rendering

enum CraftAnswerRenderer {
    static func markdown(for review: CraftReviewResult, usage: CraftUsage) -> String {
        var lines: [String] = []
        lines.append("**Reading this as:** \(review.formatRead)")
        lines.append("")
        lines.append("### \(review.performanceRead.tierLabel)")
        lines.append(review.performanceRead.reasoning)
        for evidence in review.performanceRead.evidence {
            lines.append("- **\(evidence.comparable)** (\(evidence.numbers)) — \(evidence.insight)")
        }

        if !review.slideNotes.isEmpty {
            lines.append("")
            lines.append("### Slide notes")
            for note in review.slideNotes {
                lines.append("**Slide \(note.slide)** · \(note.failedTest)")
                lines.append(note.issue)
                lines.append("→ \(note.fix)")
                if !note.comparableQuote.isEmpty {
                    lines.append("> \(note.comparableQuote)")
                }
                lines.append("")
            }
        }

        if !review.topMoves.isEmpty {
            lines.append("### Top moves")
            for (index, move) in review.topMoves.enumerated() {
                lines.append("\(index + 1). **\(move.move)** — \(move.why)")
            }
            lines.append("")
        }

        if let beat = review.weakestBeat, !beat.microVariations.isEmpty, !beat.location.isEmpty {
            lines.append("### Weakest beat — \(beat.location)")
            if !beat.originalText.isEmpty {
                lines.append("Current: \"\(beat.originalText)\"")
            }
            for variation in beat.microVariations {
                lines.append("- \(variation)")
            }
            lines.append("")
        }

        lines.append("**Verdict:** \(review.verdict)")
        lines.append("")
        lines.append("_\(usage.receiptLine)_")
        return lines.joined(separator: "\n")
    }

    static func markdown(for riff: CraftRiffResult, usage: CraftUsage) -> String {
        var lines: [String] = []
        lines.append("### \(riff.beatLabel) — \(riff.variations.count) directions")
        if !riff.targetOriginalText.isEmpty {
            lines.append("Current: \"\(riff.targetOriginalText)\"")
        }
        lines.append("")
        for (index, variation) in riff.variations.enumerated() {
            var source = ""
            if !variation.borrowedFrom.isEmpty, variation.borrowedFrom.lowercased() != "none" {
                source = " · from \(variation.borrowedFrom)"
                if !variation.numbers.isEmpty { source += " (\(variation.numbers))" }
            }
            lines.append("**\(index + 1). \(variation.mechanism)**\(source)")
            lines.append("> \(variation.text)")
            lines.append("")
        }
        lines.append("**My bet:** \(riff.bet)")
        lines.append("")
        lines.append("Reply `apply N` to stage one as a reviewed diff.")
        lines.append("")
        lines.append("_\(usage.receiptLine)_")
        return lines.joined(separator: "\n")
    }
}
