// CosmoOS/AI/InquiryLiveRouter.swift
// The single authoritative capture classifier for inquiry sessions. Captures
// land instantly as pending ("Classifying…"), then one LLM call (.strategist)
// classifies each batch from scratch: splitting multi-thought captures into
// typed units, choosing each unit's kind, routing it to the right question,
// and tagging concepts. There is no heuristic pre-classification to confirm —
// keyword guesses anchored the model toward "claim" and are gone from the
// primary path. CaptureIntentClassifier survives only as the offline fallback.

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
        var corrections: [CorrectionExample] = []
    }

    /// A past user kind-correction, injected as a learned rule the model must follow.
    struct CorrectionExample: Sendable, Equatable {
        var text: String
        var fromKind: ExtractKind
        var toKind: ExtractKind
    }

    /// One capture awaiting classification. `lockedKind` is set when the user
    /// chose the kind explicitly (dock prefix like "benefit:") — the model may
    /// split and route it but never re-type it.
    struct CaptureInput: Sendable, Equatable {
        var id: String                  // Extract UUID
        var text: String
        var lockedKind: ExtractKind?
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

    /// Accuracy over latency: captures sit in a visible "Classifying…" state,
    /// so a slower, smarter model with a generous timeout is the right trade.
    private let timeoutNanoseconds: UInt64 = 20_000_000_000
    private let maxAttempts = 2
    /// Captures per LLM call; overflow stays queued for the next batch.
    static let maxBatchSize = 6

    /// Classifies a batch of captures in one call. Returns refinements keyed by
    /// capture id. Empty dictionary on total failure (both attempts) — caller
    /// falls back to heuristics and marks the extracts unconfirmed.
    func classify(
        captures: [CaptureInput],
        context: ContextSnapshot
    ) async -> [String: Refinement] {
        guard !captures.isEmpty else { return [:] }
        let batch = Array(captures.prefix(Self.maxBatchSize))
        let prompt = Self.buildPrompt(captures: batch, context: context)

        var raw: String?
        for attempt in 1...maxAttempts {
            raw = await withTimeout {
                try await ResearchService.shared.analyze(
                    prompt: prompt,
                    systemPrompt: Self.systemPrompt,
                    tier: .strategist,
                    maxTokens: 700 + batch.count * 500
                )
            }
            if raw != nil { break }
            if attempt < maxAttempts {
                print("[InquiryLiveRouter] classify attempt \(attempt) timed out — retrying")
            }
        }
        guard let raw else { return [:] }

        let validUUIDs = Set(context.questions.map(\.uuid))
        let parsed = Self.parseBatch(raw: raw, captures: batch, validQuestionUUIDs: validUUIDs)
        var refinements: [String: Refinement] = [:]
        for (captureId, units) in parsed where !units.isEmpty {
            refinements[captureId] = Refinement(decisionId: UUID().uuidString, units: units)
        }
        return refinements
    }

    /// Single-capture convenience over the batch API.
    func classify(_ capture: CaptureInput, context: ContextSnapshot) async -> Refinement? {
        await classify(captures: [capture], context: context)[capture.id]
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
    You are Cosmo's Live Router. A user is thinking out loud in a research session. You receive one or \
    more raw captures; for each, produce its routing: split multi-thought captures into units, choose \
    each unit's kind, route it to the right question, and tag the concepts it belongs to. You are the \
    only classifier — there is no earlier guess to confirm or correct. Decide from scratch.

    THE EXTRACT KINDS (use the raw value exactly):
    - "goal" — an aim or outcome the user wants to achieve ("I want to...", "the point is to...").
    - "problem" — a pain point, obstacle, or unsolved difficulty; something gets WORSE or blocks progress.
    - "benefit" — a statement THAT something has a positive outcome or payoff ("X improves Y",
      "X is good for Y", "X increases Y and makes you happier"). It names WHAT gets better, not how.
    - "quote" — verbatim text from a source the user wants to keep.
    - "highlight" — a passage marked while reading, no commentary added.
    - "claim" — a value-neutral declarative statement the user believes is true. The LAST RESORT kind —
      see THE CLAIM TRAP below.
    - "speculativeClaim" — a hunch or maybe ("I think...", "might", "perhaps").
    - "evidence" — a cited fact/finding that SUPPORTS a claim (attributed to a study, source, or data).
    - "counterevidence" — a cited fact/finding that UNDERMINES a claim.
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
       c. Is it a fact ATTRIBUTED to a study, source, or data ("a trial found", "research shows",
          a citation)? → "evidence" (supports) / "counterevidence" (undermines). Attribution beats
          valence: an attributed positive finding is evidence, not benefit.
       d. VALENCE TEST — does the statement say something gets BETTER (helps, improves, boosts,
          increases something desirable, makes you happier/healthier/calmer)? → "benefit".
          Does it say something gets WORSE, hurts, or blocks progress? → "problem".
          Is it an aim or outcome the user wants for themselves? → "goal".
       e. Only if none of the above: a value-neutral declarative assertion → "claim"
          (hedged → "speculativeClaim").
       THE MECHANISM TRAP: "X affects/improves Y" asserts that an effect EXISTS — that is a
       "benefit" (or "problem"), never a "mechanism". A mechanism must answer "how?" with a step
       in between. "Sunlight improves liver function" → benefit. "Sunlight improves liver
       function by stimulating vitamin D synthesis, which reduces hepatic inflammation" → mechanism.
       THE CLAIM TRAP: "claim" is the LAST RESORT, reserved for value-neutral facts ("Pranayama
       means extension of the life force"). A benefit is still a declarative sentence — valence
       decides, not sentence shape. "This increases energy, focus, and makes you happier" names
       positive payoffs → "benefit", never "claim". If most of your units come out "claim", you
       are misapplying the ladder — a healthy session spreads across benefits, problems,
       mechanisms, practices, examples, and evidence.
    3. DESTINATION: pick the existing question each unit answers; null keeps it on the active
       question. Move a unit only when another question clearly fits better.
    4. CONCEPTS: tag durable concepts per rule 6 below.

    HARD RULES:
    1. NEVER invent question UUIDs — targetQuestionUUID must be copied from the QUESTIONS list, or null.
    2. Produce AT MOST 3 units per capture. Splitting is for genuinely separate thoughts, not sentences of one thought.
    3. Copy the user's wording verbatim into each unit's text — never paraphrase or "improve" it.
    4. A capture marked KIND LOCKED BY USER keeps that kind on its first unit no matter what — the
       user chose it explicitly. You may still split it (later units choose their own kinds), route
       it, and tag concepts.
    5. Propose newBranchTitle (with targetQuestionUUID null) ONLY when a unit is a substantial research
       question that no existing question covers. At most ONE new branch per capture.
    6. conceptNames: pick from LEXICON/CONCEPTS when one clearly applies; you may add at most one new
       noun-phrase concept when the unit is clearly about a durable concept not yet listed. Otherwise [].
    7. PAST USER CORRECTIONS in the input are learned rules — when a capture resembles one, follow the
       corrected kind. They override your instincts.
    8. Respond with VALID JSON only. No prose, no markdown fences. Every capture id from the input
       must appear exactly once in "captures".

    WORKED EXAMPLES (single-capture, shown without ids for brevity):

    Example A — long ramble splits into three units:
    Capture: "Slow exhales seem to raise vagal tone. I should find out whether monks measured this somehow. Box breathing: in 4, hold 4, out 4, hold 4."
    → units:
      {"text":"Slow exhales seem to raise vagal tone.","kind":"speculativeClaim","targetQuestionUUID":"<uuid of the breath-physiology question from the list>","newBranchTitle":null,"conceptNames":["Vagal tone"],"confidence":0.85},
      {"text":"I should find out whether monks measured this somehow.","kind":"question","targetQuestionUUID":null,"newBranchTitle":"Did contemplative traditions measure breath effects?","conceptNames":[],"confidence":0.7},
      {"text":"Box breathing: in 4, hold 4, out 4, hold 4.","kind":"practice","targetQuestionUUID":null,"newBranchTitle":null,"conceptNames":["Box breathing"],"confidence":0.9}

    Example B — attributed finding is evidence (attribution beats valence):
    Capture: "A 2019 trial found 6 breaths/min lowered blood pressure in hypertensive adults"
    → units: {"text":"A 2019 trial found 6 breaths/min lowered blood pressure in hypertensive adults","kind":"evidence","targetQuestionUUID":"<matching question uuid>","newBranchTitle":null,"conceptNames":["Coherent breathing"],"confidence":0.9}

    Example C — value-neutral fact is the rare true claim:
    Capture: "Pranayama means extension of the life force"
    → units: {"text":"Pranayama means extension of the life force","kind":"claim","targetQuestionUUID":null,"newBranchTitle":null,"conceptNames":["Pranayama"],"confidence":0.95}
    (targetQuestionUUID null = keep it on the active question.)

    Example D — effects + protocol split into benefit + practice (NOT mechanism):
    Capture: "Morning sunlight positively affects the liver, heart, and circadian rhythm. Ideally you should get 10 to 30 minutes per day in the morning."
    → units:
      {"text":"Morning sunlight positively affects the liver, heart, and circadian rhythm.","kind":"benefit","targetQuestionUUID":null,"newBranchTitle":null,"conceptNames":["Morning sunlight"],"confidence":0.9},
      {"text":"Ideally you should get 10 to 30 minutes per day in the morning.","kind":"practice","targetQuestionUUID":null,"newBranchTitle":null,"conceptNames":["Morning sunlight"],"confidence":0.9}
    (The first unit lists WHAT improves with no pathway named, so it is "benefit", not "mechanism".
    The second prescribes a dosage, so it is "practice". Two kinds = a correct split.)

    Example E — positive payoffs are a benefit, never a claim (THE CLAIM TRAP):
    Capture: "This increases energy, focus, and makes you happier"
    → units: {"text":"This increases energy, focus, and makes you happier","kind":"benefit","targetQuestionUUID":null,"newBranchTitle":null,"conceptNames":[],"confidence":0.9}
    (Declarative shape, but it names positive payoffs — the valence test fires before the claim fallback.)

    OUTPUT SCHEMA:
    {"captures":[{"id":"<capture id from input>","units":[{"text":"<verbatim>","kind":"<raw kind>","targetQuestionUUID":"<uuid or null>","newBranchTitle":"<title or null>","conceptNames":["<name>"],"confidence":<0-1>}]}]}
    """

    static func buildPrompt(
        captures: [CaptureInput],
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
        if !context.corrections.isEmpty {
            lines.append("\nPAST USER CORRECTIONS (learned rules — follow these patterns, they override your instincts):")
            for correction in context.corrections.prefix(8) {
                lines.append("- \"\(correction.text.prefix(160))\" → \(correction.toKind.rawValue) (user corrected from \(correction.fromKind.rawValue))")
            }
        }
        if !context.recentCaptures.isEmpty {
            lines.append("\nRECENT CAPTURES (context only, do not route):")
            for capture in context.recentCaptures.suffix(4) {
                lines.append("- \(capture.prefix(140))")
            }
        }
        lines.append("\nCAPTURES TO ROUTE:")
        for capture in captures {
            if let locked = capture.lockedKind {
                lines.append(#"- {"id":"\#(capture.id)"} (KIND LOCKED BY USER: "\#(locked.rawValue)")"#)
            } else {
                lines.append(#"- {"id":"\#(capture.id)"}"#)
            }
            lines.append(capture.text)
        }
        lines.append("\nReturn the routing JSON now.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Parsing

    /// Parses the batch response. Unknown capture ids are dropped; locked kinds
    /// are enforced on each capture's first unit.
    static func parseBatch(
        raw: String,
        captures: [CaptureInput],
        validQuestionUUIDs: Set<String>
    ) -> [String: [RoutedUnit]] {
        guard let dict = ConceptResolver.jsonObject(from: raw) else { return [:] }
        let capturesById = Dictionary(uniqueKeysWithValues: captures.map { ($0.id, $0) })

        // Tolerate the legacy single-capture shape {"units":[...]} for a one-capture batch.
        let entries: [[String: Any]]
        if let array = dict["captures"] as? [[String: Any]] {
            entries = array
        } else if captures.count == 1, dict["units"] != nil {
            entries = [["id": captures[0].id, "units": dict["units"] as Any]]
        } else {
            return [:]
        }

        var result: [String: [RoutedUnit]] = [:]
        for entry in entries {
            guard let id = entry["id"] as? String,
                  let capture = capturesById[id],
                  result[id] == nil else { continue }
            var units = parseUnits(entry: entry, validQuestionUUIDs: validQuestionUUIDs)
            if let locked = capture.lockedKind, !units.isEmpty {
                units[0].kind = locked
            }
            if !units.isEmpty { result[id] = units }
        }
        return result
    }

    static func parseUnits(raw: String, validQuestionUUIDs: Set<String>) -> [RoutedUnit] {
        guard let dict = ConceptResolver.jsonObject(from: raw) else { return [] }
        return parseUnits(entry: dict, validQuestionUUIDs: validQuestionUUIDs)
    }

    private static func parseUnits(entry: [String: Any], validQuestionUUIDs: Set<String>) -> [RoutedUnit] {
        guard let array = entry["units"] as? [[String: Any]] else { return [] }
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
