// CosmoOS/SwipeFile/Artifacts/SwipeArtifactAnalyzer.swift
// The CRAFT pass for non-post swipes: one Sonnet 5 call that reads an
// artifact's units and returns the same output contract SwipeInsightEngine
// produces for posts — displayTitle, keyInsight, hook fields, structuralRecipe,
// voiceMarkers, taxonomy, signatureCard — plus a role and a mechanic per unit,
// plus the artifact's anatomy.
//
// WHY REUSE THE POST CONTRACT: a screenshot is only as useful to the writing
// engine as a reel if it arrives carrying the SAME fields. Pattern weaving,
// the client-adaptation pass, the codex, and every writing-context assembler
// read `signatureCard` / `structuralRecipe` / `hookText` without caring what
// medium produced them. Emitting a different shape for frames would have meant
// teaching all of those about kinds; emitting this one means none of them
// change.
//
// The post path is untouched. `SwipeInsightEngine.analyze` still builds its own
// prompt and never asks for `unitRoles`; this file borrows only the shared
// response struct and its deterministic mapper (`parseResponse` / `buildAnalysis`).

import Foundation

@MainActor
enum SwipeArtifactAnalyzer {

    /// Same tier as the post insight pass — every swipe is curated, so one
    /// premium call per capture is the budget.
    static let tier: AgentModelTier = SwipeInsightEngine.analysisTier

    /// NO `contentType` IN THIS PROMPT — deliberate.
    ///
    /// `ContentFormat` is a POST vocabulary (reel variants, carousel, tweet,
    /// thread, newsletter…). Asked about a screenshot set of a webinar landing
    /// page it has no right answer, so the model picks the least-wrong one and
    /// the swipe lands filed as a "Two-Step CTA" — wrong in the Details rail
    /// and wrong under the Format filter. The KIND already answers "what shape
    /// is this"; asking a second, post-shaped shape question can only produce
    /// noise. Non-post swipes leave `swipeContentFormat` nil.

    struct Result {
        var analysis: SwipeAnalysis
        var units: [SwipeArtifactUnit]
        var anatomy: String?
        /// The model's genre verdict, already resolved onto the closed
        /// vocabulary — nil when it answered nothing usable, in which case the
        /// swipe keeps whatever it had (seed or structural default).
        var genre: SwipeGenre?
    }

    /// Read an artifact and return the analysis + role-assigned units.
    ///
    /// `units` must already carry their `copy` (vision OCR for frames, DOM text
    /// for pages) — this pass judges, it does not transcribe. Returns nil when
    /// there is nothing to judge or the model call fails; callers keep the
    /// captured units and leave the swipe visibly un-analyzed rather than
    /// stamping a hollow analysis over it.
    static func analyze(
        atom: Atom,
        artifact: SwipeArtifact,
        userNote: String?
    ) async -> Result? {
        let units = artifact.orderedUnits
        let substantive = units.filter(\.hasSubstance)
        guard !substantive.isEmpty else { return nil }

        let canonicalNiches = await NicheRegistry.shared.canonicalListForPrompt()
        let prompt = buildPrompt(
            artifact: artifact,
            units: units,
            userNote: userNote,
            canonicalNiches: canonicalNiches
        )

        let raw: String
        do {
            // reasoning OFF — Sonnet 5's adaptive thinking shares the
            // max_tokens budget and on a 40-section page consumed all of it,
            // returning empty content. See sonnet5_adaptive_thinking_budget_trap.
            raw = try await ResearchService.shared.analyze(
                prompt: prompt,
                tier: tier,
                maxTokens: 8000,
                disableReasoning: true
            )
        } catch {
            print("SwipeArtifactAnalyzer: call failed for \(atom.uuid.prefix(8)): \(error)")
            return nil
        }

        guard let response = SwipeInsightEngine.parseResponse(raw) else {
            print("SwipeArtifactAnalyzer: unparseable response for \(atom.uuid.prefix(8))")
            return nil
        }

        let hookText = resolvedHookText(response: response, units: units)
        let (handle, name) = SwipeInsightEngine.effectiveCreator(from: response, atom: atom)
        let creatorUUID = await SwipeClassificationEngine.shared.resolveCreator(
            handle: handle, name: name, atom: atom
        )

        var analysis = SwipeInsightEngine.buildAnalysis(
            from: response,
            hookText: hookText,
            // Unit anchors, not slide anchors: `buildAnalysis` clamps section
            // slideStart/slideEnd into this range, and for an artifact the
            // units ARE the addressable positions.
            slideCount: units.count,
            creatorUUID: creatorUUID,
            atom: atom
        )

        if let rawNiche = analysis.niche, !rawNiche.isEmpty {
            analysis.niche = await NicheRegistry.shared.resolve(rawNiche)
        }
        if let sections = analysis.sections, !sections.isEmpty {
            let normalized = BeatPatternService.shared.normalizeBeats(rawLabels: sections.map(\.label))
            analysis.normalizedBeats = normalized
            analysis.beatFingerprint = BeatPatternService.shared
                .computeStructuralFingerprint(normalizedBeats: normalized)
            BeatPatternService.shared.trackUsage(beats: normalized)
        }
        if let creatorUUID {
            await SwipeClassificationEngine.shared.updateCreatorStats(creatorUUID: creatorUUID)
        }

        return Result(
            analysis: analysis,
            units: applying(response.unitRoles, to: units),
            anatomy: response.anatomy?.trimmed.isEmpty == false
                ? response.anatomy?.trimmed
                : analysis.structuralRecipe,
            genre: SwipeGenre.resolve(response.genre)
        )
    }

    // MARK: - Merge

    /// Fold the model's per-unit answers back onto the captured units.
    ///
    /// Positional by `unit` (1-based), NOT by array order: a model that skips
    /// or reorders entries must not shift every subsequent role by one. An
    /// out-of-range index is dropped; a unit the model said nothing about
    /// keeps whatever it already had.
    static func applying(
        _ assignments: [SwipeInsightResponse.UnitRoleAssignment]?,
        to units: [SwipeArtifactUnit]
    ) -> [SwipeArtifactUnit] {
        guard let assignments, !assignments.isEmpty else { return units }
        var byIndex: [Int: SwipeInsightResponse.UnitRoleAssignment] = [:]
        for assignment in assignments {
            let zeroBased = assignment.unit - 1
            guard zeroBased >= 0, zeroBased < units.count else { continue }
            byIndex[zeroBased] = assignment
        }
        return units.enumerated().map { position, unit in
            guard let assignment = byIndex[position] else { return unit }
            var merged = unit
            // CLOSED-VOCABULARY LAW: whatever the model said resolves onto the
            // closed vocabulary or `.other`. A free-text role never reaches storage.
            if let role = SwipeUnitRole.resolve(assignment.role) { merged.role = role }
            if let headline = assignment.headline?.trimmed, !headline.isEmpty {
                merged.headline = headline
            }
            if let mechanic = assignment.mechanic?.trimmed, !mechanic.isEmpty {
                merged.mechanic = mechanic
            }
            return merged
        }
    }

    /// The artifact's hook: the model's answer when it gave one, else the
    /// first substantive unit's own opening line. Never empty when any unit
    /// carries text — `hookText` feeds card previews and the writing context.
    static func resolvedHookText(
        response: SwipeInsightResponse,
        units: [SwipeArtifactUnit]
    ) -> String {
        if let headline = units.first(where: { $0.role == .hook })?.displayLine, !headline.isEmpty {
            return headline
        }
        if let first = units.first(where: \.hasSubstance)?.displayLine, !first.isEmpty {
            return first
        }
        return response.displayTitle?.trimmed ?? ""
    }

    // MARK: - Prompt

    static func buildPrompt(
        artifact: SwipeArtifact,
        units: [SwipeArtifactUnit],
        userNote: String?,
        canonicalNiches: String
    ) -> String {
        let kind = artifact.kind
        var lines: [String] = []

        lines.append("""
        You are reading a \(kindDescription(kind)) that a marketer saved as reference — \
        something they want to be able to imitate later. Your job is to say exactly what \
        it does and how, in terms specific enough to rebuild from.
        """)

        if let url = artifact.capturedURL, !url.isEmpty {
            lines.append("Source URL: \(url)")
        }
        if let title = artifact.pageTitle, !title.isEmpty {
            lines.append("Page title: \(title)")
        }
        if let note = userNote?.trimmed, !note.isEmpty {
            lines.append("""
            The person who saved it wrote this note. It tells you what they cared about — \
            weight your reading toward it, but never let it override what the artifact \
            actually says:
            \(note)
            """)
        }

        lines.append("\nTHE \(kind.unitNoun.uppercased())S, IN ORDER:")
        lines.append(unitsBlock(units, kind: kind))

        lines.append("""

        ROLE VOCABULARY — every \(kind.unitNoun) gets EXACTLY ONE of these. Never invent a \
        role, never combine two with a slash. If nothing fits, answer `other`.

        \(SwipeUnitRole.promptVocabulary)
        """)

        lines.append("""

        HOW TO WRITE A `mechanic`
        One sentence per \(kind.unitNoun), naming what it does to the reader AND the \
        concrete device it uses to do it. Name the device, not the effect.
        BAD: "builds credibility" — that is the effect, and it describes a thousand \
        different sections equally well.
        GOOD: "stacks three dated screenshots under a dollar figure so the claim is checkable"
        BAD: "creates urgency"
        GOOD: "prices the delay — puts the monthly cost of waiting next to the one-time price"
        If a \(kind.unitNoun) carries no readable copy, say what the image is doing \
        compositionally instead: "full-bleed photo of the founder at a desk, no text, \
        buys trust before the pitch starts".

        HOW TO WRITE `headline`
        The \(kind.unitNoun)'s own headline, copied VERBATIM from its text — never \
        paraphrased, never title-cased differently, never summarised. If it has no \
        headline, answer null.

        HOW TO WRITE `anatomy`
        One paragraph. The sequence of roles in order, how many times the ask repeats \
        and where it falls, and what the artifact does BEFORE it first asks for anything. \
        Write it so someone holding only this paragraph could rebuild the structure.
        """)

        lines.append("""

        TAXONOMY
        `genre` — what this artifact IS, from this closed list. Choose exactly one. \
        When none of the specific genres fits, answer the structural fallback \
        (`page` for web pages, `screenshot` for images, `copy` for text) rather \
        than forcing a fit:
        \(SwipeGenre.promptVocabulary)

        `niche` — choose from this canonical list when one fits; only coin a new one when \
        nothing does:
        \(canonicalNiches)

        `hookType` — one of: \(SwipeHookType.allCases.map(\.rawValue).joined(separator: ", "))
        `primaryNarrative` / `secondaryNarrative` — one of: \(NarrativeStyle.allCases.map(\.rawValue).joined(separator: ", "))
        `frameworkType` — one of: \(SwipeFrameworkType.allCases.map(\.rawValue).joined(separator: ", "))
        `creatorHandle` / `creatorName` — only when the artifact itself names its author. \
        Never guess from the domain.
        """)

        lines.append("""

        RETURN ONLY THIS JSON — no prose before or after, no code fence:
        {
          "displayTitle": "≤60 chars. The artifact's own headline verbatim when it is already short; a compression of it when it is long. Never a description of the artifact.",
          "keyInsight": "One or two sentences: the single thing worth stealing here.",
          "genre": "one value from the genre list above",
          "hookType": "...",
          "hookScore": 0.0,
          "hookScoreReason": "...",
          "hookMechanism": "What the opening does to earn the next second of attention.",
          "primaryNarrative": "...",
          "secondaryNarrative": "...",
          "niche": "...",
          "creatorHandle": "@handle or null",
          "creatorName": "Name or null",
          "classificationConfidence": 0.0,
          "frameworkType": "...",
          "structuralRecipe": "The reusable skeleton, one paragraph.",
          "voiceMarkers": ["concrete recurring habits of phrasing, punctuation or rhythm"],
          "signatureCard": "~100 tokens: hook mechanism, beat sequence, persuasion moves, subject, quantification style. This is what cross-artifact pattern matching reads.",
          "anatomy": "See HOW TO WRITE anatomy above.",
          "unitRoles": [
            {"unit": 1, "role": "hook", "headline": "verbatim or null", "mechanic": "one sentence"}
          ]
        }

        `unitRoles` must contain one entry for EVERY \(kind.unitNoun) listed above, \
        numbered exactly as they were numbered — \(units.count) entries, 1 through \(units.count).
        """)

        return lines.joined(separator: "\n")
    }

    private static func kindDescription(_ kind: SwipeKind) -> String {
        switch kind {
        case .page: return "web page (a sales page, landing page, pricing page or opt-in)"
        case .frame: return "set of screenshots"
        case .flow: return "funnel — an ordered sequence of steps someone walks through"
        case .note: return "piece of saved copy"
        case .post: return "social post"
        }
    }

    private static func unitsBlock(_ units: [SwipeArtifactUnit], kind: SwipeKind) -> String {
        units.enumerated().map { position, unit in
            var block = "[\(position + 1)]"
            if let headline = unit.headline?.trimmed, !headline.isEmpty {
                block += " HEADLINE: \(headline)"
            }
            let copy = unit.copy?.trimmed ?? ""
            if copy.isEmpty {
                block += "\n(no readable copy — image only)"
            } else {
                // Long pages blow the budget otherwise; a section's role and
                // device are both legible well inside this.
                block += "\n\(String(copy.prefix(2400)))"
            }
            if let existing = unit.mechanic?.trimmed, !existing.isEmpty {
                block += "\n(observed: \(existing))"
            }
            return block
        }.joined(separator: "\n\n")
    }
}
