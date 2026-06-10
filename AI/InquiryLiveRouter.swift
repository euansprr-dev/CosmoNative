// CosmoOS/AI/InquiryLiveRouter.swift
// Hybrid async capture routing. Captures land instantly via heuristics
// (CaptureIntentClassifier); this router then refines them in the background
// with a fast LLM (.sensor tier): splitting long captures into typed units,
// correcting kinds, routing to the right question, proposing branches, and
// tagging concepts. On any failure the heuristic result simply stands.

import Foundation

actor InquiryLiveRouter {
    static let shared = InquiryLiveRouter()

    /// Value-only snapshot of the session built on the MainActor.
    struct ContextSnapshot: Sendable {
        struct QuestionRef: Sendable {
            var uuid: String
            var title: String
            var parentUUID: String?
        }
        var deepDiveTitle: String?
        var activeQuestionUUID: String?
        var activeQuestionTitle: String
        var questions: [QuestionRef]
        var lexiconTerms: [String]
        var conceptNames: [String]      // Existing connection-page titles
        var recentCaptures: [String]
    }

    struct RoutedUnit: Sendable, Equatable {
        var text: String
        var kind: ExtractKind
        var targetQuestionUUID: String?     // Existing question (validated)
        var newBranchTitle: String?         // Create a branch instead
        var conceptNames: [String]
        var confidence: Double
    }

    struct Refinement: Sendable, Equatable {
        var decisionId: String
        var units: [RoutedUnit]
    }

    /// What applying a refinement means for the original extract + new ones.
    /// Pure value so the apply logic is unit-testable without a database.
    struct ApplyPlan: Sendable, Equatable {
        struct OriginalUpdate: Sendable, Equatable {
            var newText: String?
            var newKind: ExtractKind?
            var targetQuestionUUID: String?
            var newBranchTitle: String?
            var conceptNames: [String]
        }
        var original: OriginalUpdate
        var additions: [RoutedUnit]
        var summary: String
        var isNoOp: Bool
    }

    private let timeoutNanoseconds: UInt64 = 8_000_000_000

    /// Refines a capture. Returns nil on LLM failure/timeout — caller keeps heuristics.
    func refine(
        text: String,
        currentKind: ExtractKind,
        context: ContextSnapshot
    ) async -> Refinement? {
        let prompt = Self.buildPrompt(text: text, currentKind: currentKind, context: context)
        let raw = await withTimeout {
            try await ResearchService.shared.analyze(
                prompt: prompt,
                systemPrompt: Self.systemPrompt,
                tier: .sensor,
                maxTokens: 1200
            )
        }
        guard let raw else { return nil }
        let validUUIDs = Set(context.questions.map(\.uuid))
        let units = Self.parseUnits(raw: raw, validQuestionUUIDs: validUUIDs)
        guard !units.isEmpty else { return nil }
        return Refinement(decisionId: UUID().uuidString, units: units)
    }

    private func withTimeout(_ work: @escaping @Sendable () async throws -> String) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { try? await work() }
            group.addTask { [timeoutNanoseconds] in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Prompt

    static let systemPrompt = """
    You are Cosmo's Live Router. A user is thinking out loud in a research session. Each capture was \
    provisionally classified by simple keyword rules; your job is to produce the CORRECT routing: \
    split multi-thought captures into units, fix each unit's kind, route it to the right question, \
    and tag the concepts it belongs to.

    THE EXTRACT KINDS (use the raw value exactly):
    - "goal" — an aim or outcome the user wants to achieve.
    - "problem" — a pain point, obstacle, or unsolved difficulty.
    - "benefit" — a statement THAT something has a positive outcome or payoff ("X improves Y",
      "X is good for Y", "X positively affects Y"). It names WHAT gets better, not how.
    - "quote" — verbatim text from a source the user wants to keep.
    - "highlight" — a passage marked while reading, no commentary added.
    - "claim" — a declarative statement the user believes is true.
    - "speculativeClaim" — a hunch or maybe ("I think...", "might", "perhaps").
    - "evidence" — a fact/finding that SUPPORTS a claim.
    - "counterevidence" — a fact/finding that UNDERMINES a claim.
    - "mechanism" — an explanation of HOW or WHY an effect happens: the text names the intermediate
      pathway, process, or cause ("X raises Y via Z", "X works by triggering Z"). If no intermediate
      step is named, it is NOT a mechanism — see the kind test below.
    - "assumption" — something taken for granted that hasn't been verified.
    - "sourceQualityNote" — a remark about how trustworthy a source is.
    - "principle" — a general rule or distilled lesson.
    - "example" — a concrete instance illustrating something broader.
    - "objection" — a counterargument or pushback against an idea.
    - "question" — something the user wants to find out (route as a unit ONLY when it's a real research question).
    - "term" — a piece of vocabulary worth defining.
    - "practice" — a technique, protocol, dosage, or exercise to do ("do X for 10-30 minutes", "ideally you should...").
    - "outputIdea" — an idea for content/writing the user could produce.
    - "reference" — a pointer to a source (citation, link mention).
    - "note" — a thought that fits none of the above.
    - "sourceSnippet" — copied source material with context.
    - "aiInsight" — an insight produced by AI assistance.
    - (legacy "highlight"/"quote" overlap: prefer "quote" when text is verbatim.)

    HOW TO DECIDE (apply in this order for every capture):
    1. SPLIT TEST: split ONLY when the parts would carry DIFFERENT kinds or DIFFERENT target
       questions. Sentences that elaborate one thought stay together as one unit. When in doubt,
       do not split.
    2. KIND TEST (per unit) — ask these in order, first match wins:
       a. Does it prescribe an action, protocol, or dosage? → "practice"
       b. Does it explain HOW an effect happens by naming an intermediate pathway, process, or
          cause ("via", "by triggering", "because ... which then ...")? → "mechanism"
       c. Does it state THAT something has positive outcomes or payoffs (helps, improves, boosts,
          supports, positively affects)? → "benefit"
       d. Is it a cited fact or finding for/against a claim? → "evidence" / "counterevidence"
       e. Otherwise: a declarative assertion → "claim" (hedged → "speculativeClaim").
       THE MECHANISM TRAP: "X affects/improves Y" asserts that an effect EXISTS — that is a
       "benefit" (or "claim"), never a "mechanism". A mechanism must answer "how?" with a step
       in between. "Sunlight improves liver function" → benefit. "Sunlight improves liver
       function by stimulating vitamin D synthesis, which reduces hepatic inflammation" → mechanism.
    3. DESTINATION: pick the existing question each unit answers; null keeps it on the active
       question. Move a unit only when another question clearly fits better.
    4. CONCEPTS: tag durable concepts per rule 5 below.

    HARD RULES:
    1. NEVER invent question UUIDs — targetQuestionUUID must be copied from the QUESTIONS list, or null.
    2. Produce AT MOST 3 units per capture. Splitting is for genuinely separate thoughts, not sentences of one thought.
    3. Copy the user's wording verbatim into each unit's text — never paraphrase or "improve" it.
    4. Propose newBranchTitle (with targetQuestionUUID null) ONLY when a unit is a substantial research
       question that no existing question covers. At most ONE new branch per capture.
    5. conceptNames: pick from LEXICON/CONCEPTS when one clearly applies; you may add at most one new
       noun-phrase concept when the unit is clearly about a durable concept not yet listed. Otherwise [].
    6. Respond with VALID JSON only. No prose, no markdown fences.

    WORKED EXAMPLES:

    Example A — long ramble splits into three units:
    Capture: "Slow exhales seem to raise vagal tone. I should find out whether monks measured this somehow. Box breathing: in 4, hold 4, out 4, hold 4."
    → {"units":[
      {"text":"Slow exhales seem to raise vagal tone.","kind":"speculativeClaim","targetQuestionUUID":"<uuid of the breath-physiology question from the list>","newBranchTitle":null,"conceptNames":["Vagal tone"],"confidence":0.85},
      {"text":"I should find out whether monks measured this somehow.","kind":"question","targetQuestionUUID":null,"newBranchTitle":"Did contemplative traditions measure breath effects?","conceptNames":[],"confidence":0.7},
      {"text":"Box breathing: in 4, hold 4, out 4, hold 4.","kind":"practice","targetQuestionUUID":null,"newBranchTitle":null,"conceptNames":["Box breathing"],"confidence":0.9}]}

    Example B — kind correction, no split:
    Capture: "A 2019 trial found 6 breaths/min lowered blood pressure in hypertensive adults" (heuristic said: note)
    → {"units":[{"text":"A 2019 trial found 6 breaths/min lowered blood pressure in hypertensive adults","kind":"evidence","targetQuestionUUID":"<matching question uuid>","newBranchTitle":null,"conceptNames":["Coherent breathing"],"confidence":0.9}]}

    Example C — already correct, confirm as-is:
    Capture: "Pranayama means extension of the life force" (heuristic said: claim, active question fits)
    → {"units":[{"text":"Pranayama means extension of the life force","kind":"claim","targetQuestionUUID":null,"newBranchTitle":null,"conceptNames":["Pranayama"],"confidence":0.95}]}
    (targetQuestionUUID null = keep it on the active question.)

    Example D — effects + protocol split into benefit + practice (NOT mechanism):
    Capture: "Morning sunlight positively affects the liver, heart, and circadian rhythm. Ideally you should get 10 to 30 minutes per day in the morning."
    → {"units":[
      {"text":"Morning sunlight positively affects the liver, heart, and circadian rhythm.","kind":"benefit","targetQuestionUUID":null,"newBranchTitle":null,"conceptNames":["Morning sunlight"],"confidence":0.9},
      {"text":"Ideally you should get 10 to 30 minutes per day in the morning.","kind":"practice","targetQuestionUUID":null,"newBranchTitle":null,"conceptNames":["Morning sunlight"],"confidence":0.9}]}
    (The first unit lists WHAT improves with no pathway named, so it is "benefit", not "mechanism".
    The second prescribes a dosage, so it is "practice". Two kinds = a correct split.)

    OUTPUT SCHEMA:
    {"units":[{"text":"<verbatim>","kind":"<raw kind>","targetQuestionUUID":"<uuid or null>","newBranchTitle":"<title or null>","conceptNames":["<name>"],"confidence":<0-1>}]}
    """

    static func buildPrompt(
        text: String,
        currentKind: ExtractKind,
        context: ContextSnapshot
    ) -> String {
        var lines: [String] = []
        if let title = context.deepDiveTitle {
            lines.append("Deep Dive: \(title)")
        }
        lines.append("ACTIVE QUESTION (default destination): \(context.activeQuestionTitle)")
        lines.append("\nQUESTIONS (the only valid targetQuestionUUID values):")
        for question in context.questions.prefix(20) {
            let marker = question.uuid == context.activeQuestionUUID ? " (active)" : ""
            lines.append(#"- {"uuid":"\#(question.uuid)","title":"\#(question.title)"}\#(marker)"#)
        }
        if !context.lexiconTerms.isEmpty {
            lines.append("\nLEXICON: \(context.lexiconTerms.prefix(25).joined(separator: ", "))")
        }
        if !context.conceptNames.isEmpty {
            lines.append("CONCEPTS (existing pages): \(context.conceptNames.prefix(25).joined(separator: ", "))")
        }
        if !context.recentCaptures.isEmpty {
            lines.append("\nRECENT CAPTURES (context only, do not route):")
            for capture in context.recentCaptures.suffix(4) {
                lines.append("- \(capture.prefix(140))")
            }
        }
        lines.append("\nCAPTURE TO ROUTE (heuristic guessed kind \"\(currentKind.rawValue)\"):")
        lines.append(text)
        lines.append("\nReturn the routing JSON now.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Parsing

    static func parseUnits(raw: String, validQuestionUUIDs: Set<String>) -> [RoutedUnit] {
        guard let dict = ConceptResolver.jsonObject(from: raw),
              let array = dict["units"] as? [[String: Any]] else { return [] }
        var units: [RoutedUnit] = []
        var proposedBranch = false
        for entry in array.prefix(3) {
            guard let text = (entry["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty,
                  let kindRaw = entry["kind"] as? String,
                  let kind = ExtractKind(rawValue: kindRaw) else { continue }
            var target = entry["targetQuestionUUID"] as? String
            if let candidate = target, !validQuestionUUIDs.contains(candidate) {
                target = nil   // Never trust invented UUIDs.
            }
            var branchTitle = (entry["newBranchTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if branchTitle?.isEmpty == true { branchTitle = nil }
            if branchTitle != nil {
                if proposedBranch { branchTitle = nil } else { proposedBranch = true }
            }
            units.append(RoutedUnit(
                text: text,
                kind: kind,
                targetQuestionUUID: target,
                newBranchTitle: branchTitle,
                conceptNames: (entry["conceptNames"] as? [String]) ?? [],
                confidence: (entry["confidence"] as? Double) ?? 0.6
            ))
        }
        return units
    }

    // MARK: - Apply plan (pure)

    /// Computes what to change. Idempotent callers must check the extract's
    /// routingDecisionId before applying.
    static func applyPlan(
        for refinement: Refinement,
        originalText: String,
        originalKind: ExtractKind,
        originalQuestionUUID: String?
    ) -> ApplyPlan {
        guard let first = refinement.units.first else {
            return ApplyPlan(
                original: .init(newText: nil, newKind: nil, targetQuestionUUID: nil, newBranchTitle: nil, conceptNames: []),
                additions: [],
                summary: "Confirmed as \(originalKind.displayName)",
                isNoOp: true
            )
        }
        let additions = Array(refinement.units.dropFirst())
        let isSplit = !additions.isEmpty
        let textChanged = isSplit && first.text != originalText
        let kindChanged = first.kind != originalKind
        let moved = first.targetQuestionUUID != nil && first.targetQuestionUUID != originalQuestionUUID

        let original = ApplyPlan.OriginalUpdate(
            newText: textChanged ? first.text : nil,
            newKind: kindChanged ? first.kind : nil,
            targetQuestionUUID: moved ? first.targetQuestionUUID : nil,
            newBranchTitle: first.newBranchTitle,
            conceptNames: first.conceptNames
        )

        var parts: [String] = []
        if isSplit { parts.append("Split into \(refinement.units.count) parts") }
        if kindChanged { parts.append("\(originalKind.displayName) → \(first.kind.displayName)") }
        if moved { parts.append("Moved to another question") }
        if refinement.units.contains(where: { $0.newBranchTitle != nil }) { parts.append("New branch proposed") }
        let conceptCount = Set(refinement.units.flatMap(\.conceptNames)).count
        if conceptCount > 0 { parts.append("\(conceptCount) concept\(conceptCount == 1 ? "" : "s") tagged") }
        let isNoOp = !isSplit && !kindChanged && !moved && first.newBranchTitle == nil

        return ApplyPlan(
            original: original,
            additions: additions,
            summary: parts.isEmpty ? "Confirmed as \(originalKind.displayName)" : parts.joined(separator: " · "),
            isNoOp: isNoOp
        )
    }
}
