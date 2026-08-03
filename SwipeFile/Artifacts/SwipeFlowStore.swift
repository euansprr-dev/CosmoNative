// CosmoOS/SwipeFile/Artifacts/SwipeFlowStore.swift
// Flows: an ordered container of member swipes.
//
// A flow is not a new object type — it is a swipe whose units point at OTHER
// swipes (`memberSwipeUUID`). That single decision is what lets cards, boards,
// the study bench, search, undo and sync carry over with no new plumbing: a
// funnel is a swipe, so everything that already knows how to handle a swipe
// already knows how to handle a funnel.
//
// This file owns creation and membership only. The browser recording pill and
// the "Read this funnel" pass are built on top of it in step 6.

import Foundation

@MainActor
enum SwipeFlowStore {

    /// Memoized `flows()` result; invalidated whenever the library changes
    /// (creation, membership edits, sync pulls all post `libraryDidChange`).
    private static var cachedFlows: [Atom]?
    private static var cacheInvalidationObserver: NSObjectProtocol?

    private static func subscribeToInvalidationIfNeeded() {
        guard cacheInvalidationObserver == nil else { return }
        cacheInvalidationObserver = NotificationCenter.default.addObserver(
            forName: CosmoNotification.SwipeFile.libraryDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in cachedFlows = nil }
        }
    }

    /// Live flow swipes, newest first — what the "Add to flow" pickers show.
    /// Narrow SQL pre-filter (both keys `createFlow` denormalises into
    /// metadata) instead of decoding every research atom; the Swift-side
    /// `swipeKind == .flow` check stays the authority.
    static func flows() async -> [Atom] {
        subscribeToInvalidationIfNeeded()
        if let cachedFlows { return cachedFlows }

        let kindHits = (try? await AtomRepository.shared
            .fetchByMetadataSubstring("\"swipeKind\":\"flow\"", type: .research)) ?? []
        let sourceHits = (try? await AtomRepository.shared
            .fetchByMetadataSubstring("\"contentSource\":\"flow\"", type: .research)) ?? []
        let flows = await Task.detached(priority: .userInitiated) { () -> [Atom] in
            var seen = Set<String>()
            var candidates: [Atom] = []
            for atom in kindHits + sourceHits where seen.insert(atom.uuid).inserted {
                candidates.append(atom)
            }
            return candidates
                .filter { !$0.isDeleted && $0.isSwipeFileAtom && $0.swipeKind == .flow }
                .sorted { $0.updatedAt > $1.updatedAt }
        }.value
        cachedFlows = flows
        return flows
    }

    static func hasAnyFlow() async -> Bool {
        !(await flows()).isEmpty
    }

    /// Create an empty flow. Steps arrive through `append`.
    @discardableResult
    static func createFlow(named name: String) async -> Atom? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var atom = Atom.new(type: .research, title: trimmed)
        atom.updateResearchMetadata { meta in
            meta.isSwipeFile = true
            meta.contentSource = SwipeKind.flow.rawValue
            // A flow has nothing to process — it is a container. Marking it
            // complete keeps it out of every pending/retry sweep.
            meta.processingStatus = "complete"
        }
        atom = atom.withSwipeArtifact(SwipeArtifact(kind: .flow, units: [], captureMode: "manual"))

        guard let created = try? await AtomRepository.shared.create(atom) else { return nil }
        NotificationCenter.default.post(name: CosmoNotification.SwipeFile.libraryDidChange, object: nil)
        return created
    }

    /// Append a member swipe as the flow's next step.
    ///
    /// Idempotent: a swipe already in the flow is not appended twice — walking
    /// a funnel often means revisiting a page, and a flow that grows a
    /// duplicate step every time you look at the checkout is noise.
    @discardableResult
    static func append(swipeUUID: String, toFlow flowUUID: String) async -> Bool {
        guard let flow = try? await AtomRepository.shared.fetch(uuid: flowUUID),
              var artifact = flow.swipeArtifact, artifact.kind == .flow else { return false }
        guard !artifact.units.contains(where: { $0.memberSwipeUUID == swipeUUID }) else { return true }

        artifact.units.append(SwipeArtifactUnit(
            index: artifact.units.count,
            memberSwipeUUID: swipeUUID
        ))
        // A flow's anatomy describes a sequence; adding a step invalidates the
        // reading. Clearing it is honest — "Read this funnel" regenerates.
        artifact.anatomy = nil
        artifact.analyzedAt = nil

        let updated = flow.withSwipeArtifact(artifact)
        guard (try? await AtomRepository.shared.update(updated)) != nil else { return false }
        NotificationCenter.default.post(name: CosmoNotification.SwipeFile.libraryDidChange, object: nil)
        return true
    }

    /// Remove a step. Indices are re-packed so `index` stays the step number.
    @discardableResult
    static func remove(swipeUUID: String, fromFlow flowUUID: String) async -> Bool {
        guard let flow = try? await AtomRepository.shared.fetch(uuid: flowUUID),
              var artifact = flow.swipeArtifact, artifact.kind == .flow else { return false }
        let remaining = artifact.orderedUnits.filter { $0.memberSwipeUUID != swipeUUID }
        guard remaining.count != artifact.units.count else { return false }

        artifact.units = repacked(remaining)
        artifact.anatomy = nil
        artifact.analyzedAt = nil
        let updated = flow.withSwipeArtifact(artifact)
        guard (try? await AtomRepository.shared.update(updated)) != nil else { return false }
        NotificationCenter.default.post(name: CosmoNotification.SwipeFile.libraryDidChange, object: nil)
        return true
    }

    /// Renumber units 0..n-1 in their current order — a flow's `index` IS its
    /// step number, so a gap after a removal would be user-visible.
    static func repacked(_ units: [SwipeArtifactUnit]) -> [SwipeArtifactUnit] {
        units.enumerated().map { position, unit in
            var copy = unit
            copy.index = position
            return copy
        }
    }

    // MARK: - Reading a funnel

    /// One Sonnet 5 call over the members' SIGNATURE CARDS — never their
    /// transcripts or their page text.
    ///
    /// That is what makes reading a funnel cheap by construction: a signature
    /// card is ~100 tokens, so a twelve-step funnel is one small call rather
    /// than a hundred thousand tokens of sales copy. It is also the right
    /// input — a funnel's anatomy is about what each step DOES to the reader
    /// and how the steps escalate, which is exactly what a signature card
    /// already summarises.
    @discardableResult
    static func readFunnel(flowUUID: String) async -> Bool {
        guard let flow = try? await AtomRepository.shared.fetch(uuid: flowUUID),
              var artifact = flow.swipeArtifact, artifact.kind == .flow else { return false }

        let members = await memberSwipes(of: artifact)
        guard members.count >= 2 else { return false }

        let prompt = readFunnelPrompt(flowName: flow.title ?? "This funnel", members: members)
        guard let raw = try? await ResearchService.shared.analyze(
            prompt: prompt,
            tier: SwipeArtifactAnalyzer.tier,
            maxTokens: 3000,
            disableReasoning: true
        ), let response = SwipeInsightEngine.parseResponse(raw) else { return false }

        artifact.units = SwipeArtifactAnalyzer.applying(response.unitRoles, to: artifact.orderedUnits)
        artifact.anatomy = response.anatomy?.trimmed.nilIfEmpty ?? response.structuralRecipe?.trimmed
        artifact.analyzedAt = ISO8601.string(from: Date())

        var updated = flow.withSwipeArtifact(artifact)
        var analysis = updated.swipeAnalysis ?? SwipeAnalysis()
        analysis.keyInsight = response.keyInsight ?? analysis.keyInsight
        analysis.structuralRecipe = artifact.anatomy ?? analysis.structuralRecipe
        analysis.signatureCard = response.signatureCard?.trimmed ?? analysis.signatureCard
        analysis.analyzedAt = ISO8601.string(from: Date())
        analysis.isFullyAnalyzed = true
        updated = updated.withSwipeAnalysis(analysis)

        guard (try? await AtomRepository.shared.update(updated)) != nil else { return false }
        await RecallIndexer.shared.noteAtomChanged(uuid: flowUUID)
        NotificationCenter.default.post(name: CosmoNotification.SwipeFile.libraryDidChange, object: nil)
        return true
    }

    /// Member swipes in step order, skipping any that have been deleted —
    /// a removed member must not shift every later step's number.
    static func memberSwipes(of artifact: SwipeArtifact) async -> [Atom] {
        var members: [Atom] = []
        for unit in artifact.orderedUnits {
            guard let uuid = unit.memberSwipeUUID,
                  let atom = try? await AtomRepository.shared.fetch(uuid: uuid),
                  !atom.isDeleted else { continue }
            members.append(atom)
        }
        return members
    }

    static func readFunnelPrompt(flowName: String, members: [Atom]) -> String {
        let steps = members.enumerated().map { index, atom -> String in
            let analysis = atom.swipeAnalysis
            var block = "[\(index + 1)] \(atom.swipeKind.displayName.uppercased())"
            if let title = atom.title?.trimmed, !title.isEmpty { block += " — \(title)" }
            if let url = atom.researchMetadata?.url, !url.isEmpty { block += "\n\(url)" }
            if let card = analysis?.signatureCard?.trimmed, !card.isEmpty {
                block += "\n\(card)"
            } else if let insight = analysis?.keyInsight?.trimmed, !insight.isEmpty {
                block += "\n\(insight)"
            } else if let hook = analysis?.hookText?.trimmed, !hook.isEmpty {
                block += "\n\(hook)"
            }
            if let anatomy = atom.swipeArtifact?.anatomy?.trimmed, !anatomy.isEmpty {
                block += "\nStructure: \(anatomy)"
            }
            return block
        }.joined(separator: "\n\n")

        return """
        You are reading a FUNNEL a marketer walked through and saved, step by step, in order. \
        Each step below is a page, post, or screenshot they captured, summarised by its own analysis.

        FUNNEL: \(flowName)

        \(steps)

        Say what this funnel does to a reader as they move through it. Be specific about the LADDER: \
        what each step asks for, what it gives first, and what changes between one step and the next. \
        Name the escalation concretely — "step 2 trades an email for a checklist, step 3 spends that \
        permission on a 20-minute video before any price appears" — never abstractly ("builds trust").

        ROLE VOCABULARY — every step gets EXACTLY ONE. Never invent a role.

        \(SwipeUnitRole.promptVocabulary)

        RETURN ONLY THIS JSON, no prose, no code fence:
        {
          "keyInsight": "One or two sentences: the single move worth stealing from this funnel.",
          "anatomy": "One paragraph. The step sequence, what is asked at each, where the price first appears, and what the funnel does to earn it beforehand. Written so someone could rebuild the ladder from this paragraph alone.",
          "structuralRecipe": "The reusable skeleton in one line.",
          "signatureCard": "~100 tokens: the ladder's shape, its escalation pattern, and its commerce moves.",
          "unitRoles": [
            {"unit": 1, "role": "hook", "headline": "what this step IS, in a few words", "mechanic": "one sentence: what this step does to the reader and the device it uses"}
          ]
        }

        `unitRoles` must contain one entry for EVERY step above — \(members.count) entries, 1 through \(members.count).
        """
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
