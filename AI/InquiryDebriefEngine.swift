// CosmoOS/AI/InquiryDebriefEngine.swift
// The Debrief: the session's exhale. A teach-back interview that consolidates
// what the user learned — the AI asks, the USER articulates (retrieval is
// where learning happens; the machine never summarizes for them). Two or
// three probes, then a wrap that distills an updated understanding in the
// user's own voice, built only from what they said in the interview.
//
// Study-native: turns run directly against ResearchService with session
// context (the inline-assistant runtime binds to editable surfaces; a session
// is not one). Falls back gracefully — a failed turn wraps quietly.

import Foundation

struct InquiryDebriefTurn: Equatable, Sendable {
    var say: String
    var wrap: Bool
    /// Present on wrap: 2-4 sentences in the user's voice, organize-don't-author.
    var updatedUnderstanding: String?
}

@MainActor
final class InquiryDebriefEngine {
    static let shared = InquiryDebriefEngine()
    private init() {}

    /// The first question is fixed and free — the teach-back opening.
    static let openingQuestion =
        "Before I show you anything: what do you understand now that you didn't when you opened this session?"

    /// Max user answers before the wrap is forced.
    static let maxUserTurns = 3

    struct Context: Sendable {
        var questionTitle: String
        var topicTitle: String?
        var topicUnderstanding: String?      // labeled orientation-only
        var sessionCaptures: [String]        // this session's material
    }

    func nextTurn(
        history: [(role: String, text: String)],
        context: Context,
        forceWrap: Bool
    ) async -> InquiryDebriefTurn {
        let prompt = buildPrompt(history: history, context: context, forceWrap: forceWrap)
        do {
            let raw = try await ResearchService.shared.analyze(
                prompt: prompt,
                systemPrompt: Self.systemPrompt,
                tier: .sonnet5,
                maxTokens: 700
            )
            if let turn = Self.parseTurn(raw: raw) { return turn }
        } catch {
            print("[InquiryDebriefEngine] turn failed: \(error)")
        }
        // Graceful wrap: the interview never strands the user on an error.
        return InquiryDebriefTurn(
            say: "Good place to stop. I'll fold what you said into the question's understanding.",
            wrap: true,
            updatedUnderstanding: Self.fallbackUnderstanding(history: history)
        )
    }

    // MARK: - Prompt

    private static let systemPrompt = """
    You are Cosmo running a session DEBRIEF: a short teach-back interview that consolidates what the \
    user learned this research session. The user articulating their understanding IS the product — \
    never summarize the material for them, never lecture, never list what they captured back at them \
    as an answer.

    RULES:
    - Exactly ONE question per turn, 1-3 sentences of prose around it at most. Conversational, warm, \
    zero filler.
    - Probe like a good teacher: chase the mechanism ("you said X helps — how?"), the gap (something \
    they captured but did not mention), or the connection ("how does that square with Y you captured?"). \
    Quote their own captures as instruments when useful.
    - 2-3 probing turns MAXIMUM, then wrap. Wrap EARLY if their answers are short or they signal done \
    ("that's it", "not sure", "done").
    - WRAP: set "wrap" true and produce "updatedUnderstanding": 2-4 sentences in THEIR voice built ONLY \
    from what THEY said in this interview. Organize, don't author: tighten and clean their words, add \
    no claim, mechanism, or example they did not offer. If they named a genuine open unknown, end the \
    understanding with it as an open thread ("Still open: ...").
    - NEVER use em dashes. Use commas, periods, or semicolons.

    Respond with VALID JSON only:
    {"say":"<your reply; ends with your one question unless wrapping>","wrap":<bool>,"updatedUnderstanding":<"..." or null>}
    """

    private func buildPrompt(
        history: [(role: String, text: String)],
        context: Context,
        forceWrap: Bool
    ) -> String {
        var lines: [String] = []
        lines.append("SESSION QUESTION (the frame): \(context.questionTitle)")
        if !context.sessionCaptures.isEmpty {
            lines.append("\nTHIS SESSION'S CAPTURES (the user's own material — quote as probes):")
            for capture in context.sessionCaptures.prefix(20) {
                lines.append("- \(capture.prefix(200))")
            }
        } else {
            lines.append("\nTHIS SESSION'S CAPTURES: (none — keep the interview to one gentle turn, then wrap)")
        }
        if let topic = context.topicTitle, let understanding = context.topicUnderstanding, !understanding.isEmpty {
            lines.append("\nTOPIC BACKGROUND — \(topic), built by OTHER sessions, orientation only, never present as this session's findings: \(understanding.prefix(300))")
        }
        lines.append("\nINTERVIEW SO FAR:")
        for turn in history {
            lines.append("\(turn.role == "user" ? "USER" : "COSMO"): \(turn.text)")
        }
        lines.append(forceWrap
            ? "\n---\nThis was the final probe. You MUST wrap now: JSON with wrap=true and updatedUnderstanding."
            : "\n---\nRespond with the JSON contract from the system prompt.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Parsing (pure, testable)

    nonisolated static func parseTurn(raw: String) -> InquiryDebriefTurn? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped: String
        if trimmed.hasPrefix("```") {
            stripped = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
                .dropFirst().dropLast().joined(separator: "\n")
        } else {
            stripped = trimmed
        }
        guard let data = stripped.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let say = (dict["say"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !say.isEmpty else { return nil }
        let wrap = (dict["wrap"] as? Bool) ?? false
        var understanding = (dict["updatedUnderstanding"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if understanding?.isEmpty == true { understanding = nil }
        return InquiryDebriefTurn(
            say: ConnectionSurfaceSerializer.removeEmDashes(say),
            wrap: wrap,
            updatedUnderstanding: understanding.map(ConnectionSurfaceSerializer.removeEmDashes)
        )
    }

    /// Offline wrap: the user's own words, longest answer first, lightly joined.
    nonisolated static func fallbackUnderstanding(history: [(role: String, text: String)]) -> String? {
        let answers = history.filter { $0.role == "user" }.map(\.text)
        guard !answers.isEmpty else { return nil }
        return answers.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
