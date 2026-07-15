// CosmoOS/AI/ConceptComposerEngine.swift
// The "smart" promotion step: turns a concept's raw, verbatim inquiry captures
// (transcript timestamps, typos, whole multi-point blocks) into clean, split,
// content-routed section bullets — the same organize-not-verbatim philosophy the
// concept collaborator (/concept skill) uses. Runs one LLM call per concept at
// crystallization; on any failure a concept keeps its original verbatim drafts, so
// this can only improve output, never regress it.
//
// It operates on the drafts ConnectionRoutingEngine already produced (which carry
// body + originExtractUUID + sourceUUID + kindLabel), so no atom refetch is needed.

import Foundation

@MainActor
final class ConceptComposerEngine {
    static let shared = ConceptComposerEngine()
    private init() {}

    /// Organize every candidate concurrently. Each concept's material drafts are
    /// cleaned/split/re-routed; scaffold (Goal/Concept Name) and reference/link
    /// drafts pass through untouched.
    func organize(
        _ candidates: [CrystallizationOutput.ConnectionCandidate]
    ) async -> [CrystallizationOutput.ConnectionCandidate] {
        guard !candidates.isEmpty else { return candidates }
        return await withTaskGroup(of: (Int, CrystallizationOutput.ConnectionCandidate).self) { group in
            for (index, candidate) in candidates.enumerated() {
                group.addTask { @MainActor in
                    (index, await ConceptComposerEngine.shared.organizeOne(candidate))
                }
            }
            var result = candidates
            for await (index, organized) in group {
                result[index] = organized
            }
            return result
        }
    }

    // MARK: - Per-concept

    /// One capture unit handed to the model, plus the provenance the model can't see.
    struct MaterialUnit {
        let index: Int
        let rawBody: String
        let currentSection: ConnectionSectionType
        let kindHint: String
        let originExtractUUID: String?
        let sourceUUID: String?
    }

    private func organizeOne(
        _ candidate: CrystallizationOutput.ConnectionCandidate
    ) async -> CrystallizationOutput.ConnectionCandidate {
        // Material = capture-derived drafts (have an origin extract), excluding the
        // References section (source-link rows, not prose to reorganize).
        var passthrough: [ConnectionSectionType: [ConnectionSectionItemDraft]] = [:]
        var units: [MaterialUnit] = []
        for (section, drafts) in candidate.proposedSections {
            for draft in drafts {
                let isMaterial = draft.originExtractUUID != nil && section != .references
                if isMaterial, !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    units.append(MaterialUnit(
                        index: units.count,
                        rawBody: draft.body,
                        currentSection: section,
                        kindHint: draft.kindLabel,
                        originExtractUUID: draft.originExtractUUID,
                        sourceUUID: draft.sourceUUID
                    ))
                } else {
                    passthrough[section, default: []].append(draft)
                }
            }
        }

        // Nothing messy to organize — leave the candidate exactly as-is.
        guard units.count >= 1 else { return candidate }

        guard let organized = await composeUnits(conceptName: candidate.name, units: units) else {
            return candidate // fallback: keep verbatim drafts on any failure
        }

        // Merge organized material back with the passthrough scaffold/reference rows.
        var sections = passthrough
        for (section, drafts) in organized {
            sections[section, default: []].append(contentsOf: drafts)
        }
        var copy = candidate
        copy.proposedSections = sections
        return copy
    }

    // MARK: - LLM

    private func composeUnits(
        conceptName: String,
        units: [MaterialUnit]
    ) async -> [ConnectionSectionType: [ConnectionSectionItemDraft]]? {
        let prompt = buildPrompt(conceptName: conceptName, units: units)
        let raw: String
        do {
            raw = try await ResearchService.shared.analyze(
                prompt: prompt,
                systemPrompt: Self.systemPrompt,
                tier: .sonnet5
            )
        } catch {
            print("[ConceptComposerEngine] LLM failed for \(conceptName): \(error) — keeping verbatim")
            return nil
        }
        return Self.parseComposition(raw: raw, units: units)
    }

    private static let systemPrompt = """
    You are Cosmo's Concept Composer. A user captured messy research notes (voice \
    transcripts, pasted excerpts, quick thoughts) while studying, and you are turning \
    them into a clean, well-organized concept page. Think like a sharp study partner \
    organizing someone's scattered notes — NOT like a transcriber, and NOT like an author.

    Your job for each captured note:
    - CLEAN IT UP. Strip copied timestamps (e.g. "17:10"), transcription artifacts \
    ("we we", "um", "like"), and filler. Fix obvious typos and broken words. Tighten \
    run-on speech into clear sentences. Never leave a timestamp or an obvious typo in the \
    output.
    - SPLIT IT. A single captured block often contains several distinct points. Break it \
    into separate bullets, one clear idea each — do not dump a whole block as one item.
    - ROUTE EACH BULLET BY WHAT IT ACTUALLY SAYS to the section it belongs in. The \
    section options are exactly: goal, problems, claims, evidence, benefits, examples, \
    beliefsObjections, process, openQuestions. (Do NOT output conceptName or references.) \
    A capture's existing kind is only a hint; decide from the content. One block can span \
    several sections — e.g. a Problem it names and a Claim it makes go to different \
    sections. Worked example: the note "this is something the mind loves to do all the \
    time and loves to judge things especially when it has zero experience" becomes a \
    Problems bullet: "The mind judges things prematurely, especially when it has zero \
    experience."
    - ORGANIZE, DON'T AUTHOR. Keep the user's OWN substance and voice. Reword only to \
    clarify and tighten; never add a claim, mechanism, reason, or example they did not \
    say. If a note is thin, keep the bullet thin — do not pad it.
    - NEVER use em dashes. Use commas, periods, or semicolons.
    - Attribute every output bullet to the sourceIndex of the capture it came from.

    Respond with VALID JSON only, no prose outside it:
    {"bullets":[{"text":"<clean bullet>","section":"<one of the section ids above>","sourceIndex":<int>}]}
    Every input capture must contribute at least one bullet (unless it is pure noise). \
    Do not invent bullets from nothing.
    """

    private func buildPrompt(conceptName: String, units: [MaterialUnit]) -> String {
        var lines: [String] = []
        lines.append("Concept page: \(conceptName)")
        lines.append("\nCaptured notes to organize (sourceIndex · current-kind-hint · text):")
        for unit in units {
            let body = unit.rawBody.replacingOccurrences(of: "\n", with: " ").prefix(700)
            lines.append("[\(unit.index)] (\(unit.kindHint)) \(body)")
        }
        lines.append("\nReturn the JSON described in the system prompt.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Parsing

    /// Pure JSON → drafts mapping (no network), exposed for tests. Rebuilds each
    /// bullet's provenance from its `sourceIndex`, strips em dashes, and keeps the
    /// raw capture as `rawSnippet`.
    nonisolated static func parseComposition(
        raw: String,
        units: [MaterialUnit]
    ) -> [ConnectionSectionType: [ConnectionSectionItemDraft]]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped: String
        if trimmed.hasPrefix("```") {
            let inner = trimmed.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().dropLast()
            stripped = inner.joined(separator: "\n")
        } else {
            stripped = trimmed
        }
        guard let data = stripped.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bullets = dict["bullets"] as? [[String: Any]], !bullets.isEmpty else {
            return nil
        }

        var sections: [ConnectionSectionType: [ConnectionSectionItemDraft]] = [:]
        for bullet in bullets {
            guard let text = (bullet["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { continue }
            let sectionRaw = (bullet["section"] as? String) ?? ""
            // A capture never belongs in conceptName/references via this path; fall back
            // to the unit's original section if the model names an invalid one.
            let sourceIndex = (bullet["sourceIndex"] as? Int) ?? (bullet["sourceIndex"] as? NSNumber)?.intValue ?? -1
            let unit = units.indices.contains(sourceIndex) ? units[sourceIndex] : nil
            var section = ConnectionSectionType(rawValue: sectionRaw) ?? unit?.currentSection ?? .claims
            if section == .references || section == .conceptName {
                section = unit?.currentSection ?? .claims
            }
            let clean = ConnectionSurfaceSerializer.removeEmDashes(text)
            sections[section, default: []].append(ConnectionSectionItemDraft(
                body: clean,
                sourceUUID: unit?.sourceUUID,
                originExtractUUID: unit?.originExtractUUID,
                kindLabel: section.displayName,
                rawSnippet: unit?.rawBody
            ))
        }
        return sections.isEmpty ? nil : sections
    }
}
