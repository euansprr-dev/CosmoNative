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
        surfaceKind: CosmoEditableSurfaceKind?,
        residentSkillID: String? = nil
    ) -> CosmoInlineAssistantSkillID? {
        guard let surfaceKind, surfaceKind != .canvas else { return nil }
        // Surfaces that live in a skill (concept boards) never keyword-route
        // into /review or /riff — an explicit slash pick arrives as
        // selectedSkillID and still wins below.
        guard residentSkillID == nil || selectedSkillID != nil else { return nil }
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
        store: CosmoInlineAssistantStore,
        snapshot preferredSnapshot: CosmoEditableSourceSnapshot? = nil
    ) async throws {
        // Session binding happens in submit(), atomically with the user's
        // message — never here, where it would swap the visible conversation.
        let snapshot = preferredSnapshot ?? store.activeEditableSnapshot()

        guard let snapshot,
              CraftSurfaceContext.hasUsableDraft(snapshot) else {
            store.receivePaneAnswer(
                title: nil,
                answer: "Open an idea, note, or draft first — I review and riff against the workspace you're looking at.",
                route: .answer
            )
            return
        }
        let draftText = CraftSurfaceContext.draftText(for: snapshot)
        let craftSourceHash = CraftSurfaceContext.sourceHash(for: snapshot)

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
        let format = CraftFormatDetector.detect(atom: atom, draftText: draftText)
        let slides = CraftDraftParser.slides(in: draftText)

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
                draftText: draftText,
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
            draftText: draftText,
            format: format,
            slides: slides,
            comparables: comparables,
            stats: stats,
            isFollowUp: isFollowUp,
            currentSourceHash: craftSourceHash,
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
        session.lastSourceHash = craftSourceHash

        sessions[sessionKey] = session

        // `schema` is the contract, and it is the ONLY thing that decides how to
        // read the reply. When we asked for structured output, prose is never a
        // valid answer — a parse or validation failure is a real failure and has
        // to surface as one. Collapsing "this was never JSON" and "this decoded
        // but is semantically empty" into one `try?` is what once rendered a raw
        // `{"topMoves":[],"verdict":"", ...}` skeleton into the pane.
        guard schema != nil else {
            // No schema requested (conversational follow-up) — prose is the deliverable.
            let footer = "\n\n_\(completion.usage.receiptLine)_"
            store.receivePaneAnswer(title: nil, answer: completion.text + footer, route: .answer)
            return
        }

        do {
            if skillID == .voiceVariations {
                let riff = try CraftStructuredOutputParser.decodeRenderable(
                    CraftRiffResult.self,
                    from: completion.text
                )
                session.lastRiff = riff
                sessions[sessionKey] = session
                // Interactive directions card: each variation is a block that
                // previews in the live draft and applies with one click. The
                // rendered markdown rides along as the durable fallback (old
                // sessions, copy, repair). Typed "apply N" still works.
                store.receiveRiffDirections(
                    riff: riff,
                    snapshot: snapshot,
                    receiptLine: completion.usage.receiptLine,
                    fallbackMarkdown: CraftAnswerRenderer.markdown(for: riff, usage: completion.usage)
                )
            } else {
                let review = try CraftStructuredOutputParser.decodeRenderable(
                    CraftReviewResult.self,
                    from: completion.text
                )
                store.receivePaneAnswer(
                    title: nil,
                    answer: CraftAnswerRenderer.markdown(for: review, usage: completion.usage),
                    route: .answer
                )
            }
        } catch {
            store.receivePaneAnswer(
                title: skillID == .voiceVariations ? "Couldn't riff that beat" : "Couldn't review this draft",
                answer: Self.structuredOutputFailureMessage(for: error, usage: completion.usage),
                route: .answer
            )
        }
    }

    /// A structured-output turn that came back unparseable or semantically empty.
    /// `decodeRenderable` already knows *why* (`craftValidationIssue`) — surface
    /// that instead of dumping the raw payload into the pane.
    private static func structuredOutputFailureMessage(
        for error: Error,
        usage: CraftUsage
    ) -> String {
        let reason: String
        switch error {
        case CraftStructuredOutputParser.ParseError.noRenderableJSONObject(let issue):
            reason = "The model came back with \(issue)."
        case CraftStructuredOutputParser.ParseError.noJSONObject:
            reason = "The model didn't return a structured result."
        default:
            reason = "The model's response didn't match the expected shape."
        }

        return """
        \(reason)

        That usually means there wasn't a draft in scope worth studying. Select \
        the draft you want looked at and try again, or just ask me directly.

        _\(usage.receiptLine)_
        """
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
        let operation = Self.riffApplyOperation(index: index, riff: riff, snapshot: snapshot)
        let isNewBeat = riff.targetOriginalText.isEmpty

        let proposal = CosmoAssistantProposal(
            prompt: prompt,
            surfaceID: snapshot.surfaceID,
            title: "Riff variation \(index)",
            summary: isNewBeat
                ? "Insert variation \(index) (\(variation.mechanism)) as the \(riff.beatLabel.lowercased()). Review the diff in the editor."
                : "Swap the \(riff.beatLabel.lowercased()) for variation \(index) (\(variation.mechanism)). Review the diff in the editor.",
            operations: [operation],
            skillID: CosmoInlineAssistantSkillID.voiceVariations.rawValue
        )
        store.receive(proposal: proposal)
    }

    /// Build the staged operation for "apply N". A non-empty target stages the
    /// verbatim replacement diff. An empty target means the beat doesn't exist
    /// in the draft yet — stage a textInsertion instead, with the beat label in
    /// the rationale so the diff engine's slide-header fallback places it under
    /// the right SLIDE N header (or appends when no header matches).
    nonisolated static func riffApplyOperation(
        index: Int,
        riff: CraftRiffResult,
        snapshot: CosmoEditableSourceSnapshot
    ) -> CosmoAssistantProposalOperation {
        let variation = riff.variations[index - 1]
        let original = riff.targetOriginalText
        let borrowedSuffix = variation.borrowedFrom.isEmpty || variation.borrowedFrom == "none"
            ? ""
            : ", pattern from \(variation.borrowedFrom)"

        guard !original.isEmpty else {
            return CosmoAssistantProposalOperation(
                kind: .textInsertion,
                targetID: snapshot.targetID,
                anchorID: nil,
                originalText: nil,
                proposedText: variation.text,
                sourceHash: snapshot.sourceHash,
                rationale: "Riff \(index) for the \(riff.beatLabel) — \(variation.mechanism)\(borrowedSuffix)"
            )
        }

        return CosmoAssistantProposalOperation(
            kind: .textReplacement,
            targetID: snapshot.targetID,
            anchorID: CraftSurfaceContext.anchorID(forOriginalText: original, in: snapshot),
            originalText: original,
            proposedText: variation.text,
            sourceHash: snapshot.sourceHash,
            rationale: "Riff \(index) — \(variation.mechanism)\(borrowedSuffix)"
        )
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
        if let reference = CosmoExplicitClientReference.firstName(in: prompt),
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
        draftText: String,
        format: CraftFormat,
        slides: [CraftDraftSlide],
        comparables: [CraftComparable],
        stats: CraftFormatStats,
        isFollowUp: Bool,
        currentSourceHash: String,
        previousSourceHash: String?
    ) -> String {
        if isFollowUp {
            var message = prompt
            if previousSourceHash != currentSourceHash {
                message += "\n\n(The workspace changed since your last read. Current draft:)\n<draft>\n\(draftText)\n</draft>"
            }
            return message
        }

        var sections: [String] = []
        sections.append("""
        ## The Draft
        Title: \(snapshot.title)
        Detected format: \(format.displayName) (\(slides.count) slides)

        <draft>
        \(draftText)
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

            Identify which beat of the draft they mean (use their words; if genuinely ambiguous, riff the hook). Copy that beat's current text VERBATIM into targetOriginalText. If the beat is new or currently empty — they're asking what to write there — leave targetOriginalText as an empty string and write each variation as a complete candidate for that beat; never invent a quote the draft doesn't contain. Then write 5–7 variations, each using a genuinely different mechanism, each at \(format.displayName) density, each in the client's voice from the top-performer transcripts. Borrow patterns from the comparables and carry their numbers. Close with the one you'd bet on and why.
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

    /// Same Recall cloud client + cache the skill auto-router uses (the old
    /// daemon embedding path threw on every call).
    nonisolated private static let daemonEmbedder: CraftComparableSelector.Embedder = { text in
        if let cached = await EmbeddingCache.shared.get(for: text) { return cached }
        guard let vector = try? await RecallEmbedding.embedText(text) else { return nil }
        await EmbeddingCache.shared.set(vector, for: text)
        return vector
    }
}

enum CraftSurfaceContext {
    static func hasUsableDraft(_ snapshot: CosmoEditableSourceSnapshot) -> Bool {
        !draftText(for: snapshot).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func draftText(for snapshot: CosmoEditableSourceSnapshot) -> String {
        let body = snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = meaningfulTitle(snapshot.title)
        let hooks = hookAnchors(in: snapshot).map { "- \($0.label)" }

        var sections: [String] = []
        if snapshot.surfaceID.hasPrefix("idea:"), let title {
            sections.append("Idea title:\n\(title)")
        }
        if !body.isEmpty {
            sections.append(body)
        }
        if snapshot.surfaceID.hasPrefix("idea:"), !hooks.isEmpty {
            sections.append("Hooks:\n\(hooks.joined(separator: "\n"))")
        }
        if sections.isEmpty, let title {
            sections.append(title)
        }
        return sections.joined(separator: "\n\n")
    }

    static func sourceHash(for snapshot: CosmoEditableSourceSnapshot) -> String {
        CosmoEditableSurfaceHasher.hash(draftText(for: snapshot))
    }

    static func anchorID(
        forOriginalText originalText: String,
        in snapshot: CosmoEditableSourceSnapshot
    ) -> String? {
        let normalizedOriginal = normalize(originalText)
        guard !normalizedOriginal.isEmpty else { return nil }
        return hookAnchors(in: snapshot).first { normalize($0.label) == normalizedOriginal }?.id
    }

    private static func hookAnchors(
        in snapshot: CosmoEditableSourceSnapshot
    ) -> [CosmoEditableAnchor] {
        snapshot.anchors.filter {
            $0.id.hasPrefix("hook-")
                && !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func meaningfulTitle(_ rawTitle: String) -> String? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              title.lowercased() != "untitled",
              title.lowercased() != "untitled idea" else {
            return nil
        }
        return title
    }

    private static func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

// MARK: - Markdown rendering

enum CraftStructuredOutputParser {
    enum ParseError: LocalizedError {
        case noJSONObject
        case noRenderableJSONObject(String)

        var errorDescription: String? {
            switch self {
            case .noJSONObject:
                "No JSON object found in structured Craft output."
            case .noRenderableJSONObject(let issue):
                "No renderable structured Craft output found: \(issue)"
            }
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        let candidates = candidatePayloads(in: text, recursionDepth: 0)
        let decoder = JSONDecoder()
        var lastError: Error?

        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else { continue }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                lastError = error
            }
        }

        if let lastError { throw lastError }
        throw ParseError.noJSONObject
    }

    static func decodeRenderable<T: CraftRenderableStructuredOutput>(
        _ type: T.Type,
        from text: String
    ) throws -> T {
        let candidates = candidatePayloads(in: text, recursionDepth: 0)
        let decoder = JSONDecoder()
        var lastError: Error?
        var lastValidationIssue = "output did not match the expected shape"

        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else { continue }
            do {
                let decoded = try decoder.decode(T.self, from: data)
                if let issue = decoded.craftValidationIssue {
                    lastValidationIssue = issue
                    continue
                }
                return decoded
            } catch {
                lastError = error
            }
        }

        if let lastError { throw lastError }
        throw ParseError.noRenderableJSONObject(lastValidationIssue)
    }

    private static func candidatePayloads(
        in text: String,
        recursionDepth: Int
    ) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var candidates = [trimmed]
        if recursionDepth == 0,
           let data = trimmed.data(using: .utf8),
           let nested = try? JSONDecoder().decode(String.self, from: data),
           nested != trimmed {
            candidates.append(contentsOf: candidatePayloads(in: nested, recursionDepth: recursionDepth + 1))
        }
        candidates.append(contentsOf: jsonObjects(in: trimmed).filter { $0 != trimmed })

        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    /// Models occasionally wrap schema output in prose or emit a false-start
    /// object before the real answer; pull every complete root object without
    /// being confused by braces inside strings.
    private static func jsonObjects(in text: String) -> [String] {
        var objects: [String] = []
        var start: String.Index?
        var depth = 0
        var inString = false
        var escaping = false

        for index in text.indices {
            let character = text[index]
            guard start != nil else {
                if character == "{" {
                    start = index
                    depth = 1
                }
                continue
            }

            if inString {
                if escaping {
                    escaping = false
                } else if character == "\\" {
                    escaping = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0, let objectStart = start {
                    objects.append(String(text[objectStart...index]))
                    start = nil
                }
            }
        }

        return objects
    }
}

enum CraftPaneAnswerRepair {
    static func repairedAnswer(
        forRawSkillID rawValue: String?,
        content: String
    ) -> String? {
        guard let craftSkillID = craftSkillID(from: rawValue) else { return nil }
        return repairedAnswer(for: craftSkillID, content: content)
    }

    static func repairedMessages(
        _ messages: [CosmoInlineAssistantPaneMessage]
    ) -> (messages: [CosmoInlineAssistantPaneMessage], repaired: Bool) {
        var repairedMessages = messages
        var didRepair = false
        var pendingCraftSkillID: CosmoInlineAssistantSkillID?

        for index in repairedMessages.indices {
            switch repairedMessages[index].role {
            case .user:
                pendingCraftSkillID = craftSkillID(from: repairedMessages[index].skillID)
            case .system:
                continue
            case .assistant:
                guard let craftSkillID = pendingCraftSkillID else { continue }
                let originalContent = repairedMessages[index].content
                if let repairedContent = repairedAnswer(for: craftSkillID, content: originalContent),
                   repairedContent != originalContent {
                    repairedMessages[index].content = repairedContent
                    didRepair = true
                }
                pendingCraftSkillID = nil
            }
        }

        return (repairedMessages, didRepair)
    }

    private static func craftSkillID(from rawValue: String?) -> CosmoInlineAssistantSkillID? {
        guard let rawValue,
              let skillID = CosmoInlineAssistantSkillID(rawValue: rawValue),
              skillID == .contentReview || skillID == .voiceVariations else {
            return nil
        }
        return skillID
    }

    private static func repairedAnswer(
        for skillID: CosmoInlineAssistantSkillID,
        content: String
    ) -> String? {
        guard looksLikeRawCraftStructuredOutput(content) else { return nil }
        let receiptLine = receiptLine(in: content) ?? "Parsed from previous Craft response"
        switch skillID {
        case .contentReview:
            guard let review = try? CraftStructuredOutputParser.decodeRenderable(CraftReviewResult.self, from: content) else {
                return nil
            }
            return CraftAnswerRenderer.markdown(for: review, receiptLine: receiptLine)
        case .voiceVariations:
            guard let riff = try? CraftStructuredOutputParser.decodeRenderable(CraftRiffResult.self, from: content) else {
                return nil
            }
            return CraftAnswerRenderer.markdown(for: riff, receiptLine: receiptLine)
        default:
            return nil
        }
    }

    private static func looksLikeRawCraftStructuredOutput(_ content: String) -> Bool {
        content.contains("\"slideNotes\"")
            || content.contains("\"performanceRead\"")
            || content.contains("\"variations\"")
            || content.contains("\"beatLabel\"")
    }

    private static func receiptLine(in content: String) -> String? {
        for line in content.split(separator: "\n", omittingEmptySubsequences: false).reversed() {
            let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("_"), trimmed.hasSuffix("_"), trimmed.count > 2 else { continue }
            return String(trimmed.dropFirst().dropLast())
        }
        return nil
    }
}

enum CraftAnswerRenderer {
    static func markdown(for review: CraftReviewResult, usage: CraftUsage) -> String {
        markdown(for: review, receiptLine: usage.receiptLine)
    }

    static func markdown(for review: CraftReviewResult, receiptLine: String) -> String {
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
        lines.append("_\(receiptLine)_")
        return lines.joined(separator: "\n")
    }

    static func markdown(for riff: CraftRiffResult, usage: CraftUsage) -> String {
        markdown(for: riff, receiptLine: usage.receiptLine)
    }

    static func markdown(for riff: CraftRiffResult, receiptLine: String) -> String {
        var lines: [String] = []
        let directionLabel = riff.variations.count == 1 ? "direction" : "directions"
        lines.append("### \(riff.beatLabel) — \(riff.variations.count) \(directionLabel)")
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
        let bet = riff.bet.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bet.isEmpty, bet.lowercased() != "x" {
            lines.append("**My bet:** \(bet)")
            lines.append("")
        }
        lines.append("Reply `apply N` to stage one as a reviewed diff.")
        lines.append("")
        lines.append("_\(receiptLine)_")
        return lines.joined(separator: "\n")
    }
}
