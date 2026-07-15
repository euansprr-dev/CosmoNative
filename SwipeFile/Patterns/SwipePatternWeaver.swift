// CosmoOS/SwipeFile/Patterns/SwipePatternWeaver.swift
// The cross-swipe pattern miner. Runs batched: when enough newly-analyzed
// swipes accumulate (or weekly), ONE Sonnet 5 call reads compact signature
// cards — never transcripts — against the existing pattern library and
// returns assignments, refinements, and genuinely novel emerging patterns.
// Cost: ~15K tokens in / 2K out per ~8 captures.
// July 2026

import Foundation
import GRDB

@MainActor
enum SwipePatternWeaver {

    static let weaveTier: AgentModelTier = .sonnet5

    /// Weave when this many swipes are pending…
    static let minPendingForWeave = 8
    /// …or when at least 2 are pending and this many days passed.
    static let staleWeaveDays: Double = 7
    /// Cards per weave call (regular passes take the whole queue up to this).
    static let maxCardsPerWeave = 40
    /// Migration over the pre-existing library: cards per call / calls per launch.
    static let migrationBatchSize = 25
    static let maxMigrationBatchesPerLaunch = 4

    private static var hasRunThisLaunch = false

    // MARK: - Launch trigger

    static func runIfNeeded() async {
        guard !hasRunThisLaunch else { return }
        hasRunThisLaunch = true

        let store = SwipePatternStore.shared

        if !store.migrationComplete {
            await runMigrationPass()
        }

        // Cloud-analyzed swipes: the Railway worker completes the insight
        // pass server-side, so nothing on the Mac calls markPendingWeave for
        // them. Sweep once per launch for fully-analyzed swipes the pattern
        // library has never seen and enqueue them.
        await enqueueUnwovenAnalyzedSwipes()

        let pending = store.pendingWeave
        let daysSinceWeave = store.lastWeaveAt.map { Date().timeIntervalSince($0) / 86_400 } ?? .infinity
        let due = pending.count >= minPendingForWeave
            || (pending.count >= 2 && daysSinceWeave >= staleWeaveDays)
        guard due else { return }

        await weave(uuids: Array(pending.prefix(maxCardsPerWeave)))
    }

    // MARK: - Migration (existing library, resumable)

    /// Weave the pre-existing analyzed library in batches. Signature cards for
    /// legacy analyses are derived client-side from stored fields — no
    /// re-analysis calls. Resumes across launches; flips `migrationComplete`
    /// when nothing is left.
    static func runMigrationPass() async {
        let store = SwipePatternStore.shared
        let known = Set(store.patterns.flatMap { $0.members.map(\.swipeUUID) })
            .union(store.pendingWeave)

        let atoms = (try? await CosmoDatabase.shared.asyncRead { db in
            try Atom
                .filter(Column("type") == AtomType.research.rawValue)
                .filter(Column("is_deleted") == false)
                .fetchAll(db)
        }) ?? []

        let candidates = atoms.filter { atom in
            atom.isSwipeFileAtom
                && !known.contains(atom.uuid)
                && !store.migrationSeen.contains(atom.uuid)
                && atom.swipeAnalysis?.isFullyAnalyzed == true
                && signatureCard(for: atom) != nil
        }

        guard !candidates.isEmpty else {
            store.migrationComplete = true
            store.save()
            return
        }

        var batches = 0
        var index = 0
        while index < candidates.count, batches < maxMigrationBatchesPerLaunch {
            let batch = Array(candidates[index..<min(index + migrationBatchSize, candidates.count)])
            await weave(atoms: batch)
            store.markMigrationSeen(batch.map(\.uuid))
            index += batch.count
            batches += 1
        }

        if index >= candidates.count {
            store.migrationComplete = true
            store.save()
        }
    }

    /// Enqueue analyzed swipes the pattern library has never seen (neither
    /// woven, nor pending, nor swept during migration) — primarily swipes the
    /// cloud worker analyzed while the Mac was closed. Cheap no-op when clean.
    private static func enqueueUnwovenAnalyzedSwipes() async {
        let store = SwipePatternStore.shared
        let known = Set(store.patterns.flatMap { $0.members.map(\.swipeUUID) })
            .union(store.pendingWeave)
            .union(store.migrationSeen)

        let atoms = (try? await CosmoDatabase.shared.asyncRead { db in
            try Atom
                .filter(Column("type") == AtomType.research.rawValue)
                .filter(Column("is_deleted") == false)
                .fetchAll(db)
        }) ?? []

        var enqueued = 0
        for atom in atoms where atom.isSwipeFileAtom
            && !known.contains(atom.uuid)
            && atom.swipeAnalysis?.isFullyAnalyzed == true
            && signatureCard(for: atom) != nil {
            store.markPendingWeave(atom.uuid)
            enqueued += 1
        }
        if enqueued > 0 {
            print("SwipePatternWeaver: enqueued \(enqueued) cloud-analyzed swipe(s) for weaving")
        }
    }

    // MARK: - Weave

    static func weave(uuids: [String]) async {
        guard !uuids.isEmpty else { return }
        var atoms: [Atom] = []
        for uuid in uuids {
            if let atom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                atoms.append(atom)
            }
        }
        // Whatever can't be fetched (deleted since) leaves the queue too.
        await weave(atoms: atoms)
        SwipePatternStore.shared.consumePending(uuids)
    }

    /// One model call over a batch of swipes' signature cards.
    static func weave(atoms: [Atom]) async {
        let store = SwipePatternStore.shared

        let cards: [(atom: Atom, card: String)] = atoms.compactMap { atom in
            guard let card = signatureCard(for: atom) else { return nil }
            return (atom, card)
        }
        guard !cards.isEmpty else {
            store.consumePending(atoms.map(\.uuid))
            return
        }

        let prompt = buildPrompt(cards: cards, patterns: store.patterns)

        do {
            let raw = try await ResearchService.shared.analyze(
                prompt: prompt,
                tier: weaveTier,
                maxTokens: 3000
            )
            guard let response = parseResponse(raw) else {
                print("SwipePatternWeaver: Unparseable weave response")
                return
            }
            apply(response, wovenAtoms: cards.map(\.atom), to: store)
        } catch {
            print("SwipePatternWeaver: Weave failed: \(error)")
        }
    }

    // MARK: - Signature cards

    /// The stored card from the insight pass, or a derived card for legacy
    /// analyses (built from fields every version-2 analysis already has).
    static func signatureCard(for atom: Atom) -> String? {
        if let card = atom.swipeAnalysis?.signatureCard, !card.isEmpty {
            return card
        }
        return derivedSignatureCard(from: atom.swipeAnalysis)
    }

    static func derivedSignatureCard(from analysis: SwipeAnalysis?) -> String? {
        guard let analysis, analysis.isFullyAnalyzed else { return nil }
        var parts: [String] = []
        if let mechanism = analysis.hookMechanism, !mechanism.isEmpty {
            parts.append("HOOK: \(mechanism)")
        } else if let hookType = analysis.hookType {
            parts.append("HOOK: \(hookType.displayName) opener")
        }
        let beats = analysis.normalizedBeats ?? analysis.sections?.map(\.label) ?? []
        if !beats.isEmpty {
            parts.append("BEATS: \(beats.joined(separator: " → "))")
        }
        if let moves = analysis.persuasionStack?.keys.sorted(), !moves.isEmpty {
            parts.append("MOVES: \(moves.prefix(4).joined(separator: ", "))")
        }
        if let niche = analysis.niche, !niche.isEmpty {
            parts.append("SUBJECT: \(niche)")
        }
        if let voice = analysis.voiceMarkers, !voice.isEmpty {
            parts.append("VOICE: \(voice.prefix(3).joined(separator: ", "))")
        }
        guard parts.count >= 2 else { return nil }
        return parts.joined(separator: ". ") + "."
    }

    // MARK: - Prompt

    static func buildPrompt(
        cards: [(atom: Atom, card: String)],
        patterns: [SwipePattern]
    ) -> String {
        let patternDigests: String
        if patterns.isEmpty {
            patternDigests = "(none yet — the library starts with this batch)"
        } else {
            patternDigests = patterns.map { pattern in
                let signature = pattern.beatSignature.isEmpty
                    ? "" : " | beats: \(pattern.beatSignature.joined(separator: " → "))"
                return """
                - id: \(pattern.id.uuidString)
                  name: \(pattern.name) [\(pattern.level.rawValue), \(pattern.members.count) swipes]
                  definition: \(pattern.definition)\(signature)
                """
            }.joined(separator: "\n")
        }

        let cardBlock = cards.map { entry in
            let title = entry.atom.title ?? "Untitled"
            var hints = ""
            if let beats = entry.atom.swipeAnalysis?.normalizedBeats {
                let candidates = SwipePatternStore.shared.candidatePatterns(forBeats: beats)
                if !candidates.isEmpty {
                    hints = "\n  candidate patterns (beat-overlap hint only): \(candidates.map(\.name).joined(separator: "; "))"
                }
            }
            return """
            - swipeUUID: \(entry.atom.uuid)
              title: \(title)
              card: \(entry.card)\(hints)
            """
        }.joined(separator: "\n")

        return """
        You maintain a creator's private library of RECURRING CONTENT MOVES — patterns they keep saving without realizing it. You see compact signature cards of newly saved swipes plus the existing pattern library. Your job: notice when several swipes share the same specific, replicable move, and name it.

        ## What counts as a pattern (be strict)

        - A pattern is an idiosyncratic, OBSERVABLE move — specific enough that the creator could deliberately reuse it tomorrow. "Opens with a dollar figure in the first five words", "myth-busts with a historical data receipt before any opinion", "second-person accusation hook aimed at renters".
        - Textbook frameworks (PAS, AIDA, listicle, storytelling) are ALREADY tracked elsewhere — never create a pattern that just restates one. A pattern may live INSIDE a framework ("PAS where the agitation is all third-party statistics") if the specific expression recurs.
        - Levels: hook (opening move), structure (beat sequence), voice (prose style), topic (subject × angle pairing).
        - Evidence bar: a NEW pattern needs at least 2 swipes from THIS batch (or batch + library) genuinely sharing the move, each with a one-line evidence note. Do not force matches — an empty result is a valid result.
        - Assignment bar: assign a swipe to an existing pattern only when its card clearly expresses that pattern's definition. Candidate hints are beat-overlap guesses, not truth.
        - Refine a pattern (rename/redefine) only when new evidence sharpens it.

        ## Existing pattern library

        \(patternDigests)

        ## Newly analyzed swipes (signature cards)

        \(cardBlock)

        ## Output

        Return ONLY valid JSON, no markdown fences:
        {
          "assignments": [
            {"swipeUUID": "...", "patternId": "existing-pattern-uuid", "evidence": "one line on how this swipe expresses the move"}
          ],
          "refinements": [
            {"patternId": "existing-pattern-uuid", "name": "sharper name or null", "definition": "sharper definition or null"}
          ],
          "newPatterns": [
            {
              "name": "Receipts-first myth bust",
              "definition": "1-2 sentences: the move and why it works.",
              "level": "hook" | "structure" | "voice" | "topic",
              "beatSignature": ["MythStatement", "DataReceipt", "Reframe"],
              "members": [{"swipeUUID": "...", "evidence": "..."}],
              "novelty": "one line: why this is not just a textbook framework"
            }
          ]
        }
        Every swipeUUID must come from the cards above. Empty arrays are fine.
        """
    }

    // MARK: - Response

    struct WeaveResponse: Codable {
        struct Assignment: Codable {
            let swipeUUID: String
            let patternId: String
            let evidence: String?
        }
        struct Refinement: Codable {
            let patternId: String
            let name: String?
            let definition: String?
        }
        struct NewPattern: Codable {
            let name: String
            let definition: String
            let level: String?
            let beatSignature: [String]?
            let members: [Member]
            let novelty: String?

            struct Member: Codable {
                let swipeUUID: String
                let evidence: String?
            }
        }
        let assignments: [Assignment]?
        let refinements: [Refinement]?
        let newPatterns: [NewPattern]?
    }

    static func parseResponse(_ raw: String) -> WeaveResponse? {
        var jsonStr = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonStr.hasPrefix("```") {
            if let firstNewline = jsonStr.firstIndex(of: "\n") {
                jsonStr = String(jsonStr[jsonStr.index(after: firstNewline)...])
            }
            if jsonStr.hasSuffix("```") { jsonStr = String(jsonStr.dropLast(3)) }
            jsonStr = jsonStr.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = jsonStr.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WeaveResponse.self, from: data)
    }

    /// Validate against the woven batch (the model may only reference those
    /// UUIDs) and apply atomically.
    static func apply(_ response: WeaveResponse, wovenAtoms: [Atom], to store: SwipePatternStore) {
        let validUUIDs = Set(wovenAtoms.map(\.uuid))

        let assignments: [(UUID, SwipePatternMember)] = (response.assignments ?? []).compactMap { assignment in
            guard validUUIDs.contains(assignment.swipeUUID),
                  let patternID = UUID(uuidString: assignment.patternId),
                  store.pattern(id: patternID) != nil else { return nil }
            return (patternID, SwipePatternMember(
                swipeUUID: assignment.swipeUUID,
                evidence: assignment.evidence ?? ""
            ))
        }

        let refinements: [(UUID, String?, String?)] = (response.refinements ?? []).compactMap { refinement in
            guard let patternID = UUID(uuidString: refinement.patternId),
                  store.pattern(id: patternID) != nil else { return nil }
            return (patternID, refinement.name, refinement.definition)
        }

        let newPatterns: [SwipePattern] = (response.newPatterns ?? []).compactMap { candidate in
            let members = candidate.members
                .filter { validUUIDs.contains($0.swipeUUID) }
                .map { SwipePatternMember(swipeUUID: $0.swipeUUID, evidence: $0.evidence ?? "") }
            guard members.count >= 2, !candidate.name.isEmpty, !candidate.definition.isEmpty else {
                return nil
            }
            return SwipePattern(
                name: candidate.name,
                definition: candidate.definition,
                level: candidate.level.flatMap { SwipePatternLevel(rawValue: $0) } ?? .structure,
                beatSignature: candidate.beatSignature ?? [],
                members: members
            )
        }

        store.apply(
            assignments: assignments,
            refinements: refinements,
            newPatterns: newPatterns,
            wovenUUIDs: Array(validUUIDs)
        )

        let touched = assignments.count + newPatterns.reduce(0) { $0 + $1.members.count }
        if touched > 0 {
            print("SwipePatternWeaver: Wove \(wovenAtoms.count) swipes — \(assignments.count) assignments, \(newPatterns.count) new patterns")
        }
    }
}
