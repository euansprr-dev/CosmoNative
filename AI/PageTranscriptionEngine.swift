// CosmoOS/AI/PageTranscriptionEngine.swift
// Vision-LLM digitization of physical pages — handwriting, whiteboards,
// printed matter. One page image in; a faithful transcript + thought units +
// ink-mark annotations out. The routing/typing authority stays with
// InquiryLiveRouter (sessions) and InboxClassificationEngine (inbox): this
// engine transcribes and *hints*, it never routes.
//
// PROMPT + CONTRACT PARITY: keep in lockstep with
// CosmoOS-iOS/CosmoCoreKit/Sources/AI/PageTranscriptionEngine.swift.

import Foundation

/// One transcribed page.
struct PageTranscription: Codable, Sendable, Equatable {
    struct Unit: Codable, Sendable, Equatable {
        var text: String
        /// Ink marks attached to this unit: star | question | box | arrow | underline
        var inkMarks: [String]?
    }
    struct Diagram: Codable, Sendable, Equatable {
        var description: String
        /// Rough page region: top | middle | bottom | top-left | … (display hint only)
        var region: String?
    }

    var pageTitle: String?
    /// Faithful markdown transcript. Unreadable words appear as ⟦guess?⟧.
    var transcript: String
    /// Suggested thought splits — HINTS for the router, never authoritative.
    var units: [Unit]
    var diagrams: [Diagram]?
    /// 0…1 self-assessed transcription confidence.
    var confidence: Double

    var isEmpty: Bool {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Session vocabulary that helps the model transcribe domain terms correctly.
struct PageTranscriptionContext: Sendable {
    var deepDiveTitle: String?
    var activeQuestionTitle: String?
    var lexiconTerms: [String] = []
    var conceptNames: [String] = []
    /// The user's personal ink-notation legend (Settings → Ink grammar).
    var inkLegend: String?

    init(
        deepDiveTitle: String? = nil,
        activeQuestionTitle: String? = nil,
        lexiconTerms: [String] = [],
        conceptNames: [String] = [],
        inkLegend: String? = nil
    ) {
        self.deepDiveTitle = deepDiveTitle
        self.activeQuestionTitle = activeQuestionTitle
        self.lexiconTerms = lexiconTerms
        self.conceptNames = conceptNames
        self.inkLegend = inkLegend
    }
}

enum PageTranscriptionError: LocalizedError {
    case unparseableResponse
    case emptyPage

    var errorDescription: String? {
        switch self {
        case .unparseableResponse: return "The transcription response couldn't be read."
        case .emptyPage: return "No readable text was found on the page."
        }
    }
}

actor PageTranscriptionEngine {
    static let shared = PageTranscriptionEngine()

    private init() {}

    /// Transcribe one page image. Sonnet 5 owns handwriting — real-world
    /// pages (checklists, science notation, messy ink) came back with
    /// artifacts from the fast tiers, while Sonnet 5 reads them one-shot.
    /// Accuracy beats pennies here: a wrong transcript poisons routing,
    /// search, and the inbox text downstream.
    func transcribe(
        imageData: Data,
        context: PageTranscriptionContext = PageTranscriptionContext()
    ) async throws -> PageTranscription {
        let prompt = Self.buildPrompt(context: context)

        if let raw = try? await ResearchService.shared.analyze(
            prompt: prompt,
            images: [imageData],
            systemPrompt: Self.systemPrompt,
            tier: .sonnet5,
            maxTokens: 4000
        ), let parsed = Self.parse(raw), !parsed.isEmpty {
            return parsed
        }

        // One retry (transient failures, malformed JSON) — same model.
        let raw = try await ResearchService.shared.analyze(
            prompt: prompt,
            images: [imageData],
            systemPrompt: Self.systemPrompt,
            tier: .sonnet5,
            maxTokens: 4000
        )
        guard let parsed = Self.parse(raw) else {
            // Model answered but not in contract shape — salvage prose as a
            // low-confidence transcript rather than dropping the user's page.
            let salvaged = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !salvaged.isEmpty else { throw PageTranscriptionError.unparseableResponse }
            return PageTranscription(
                pageTitle: nil,
                transcript: salvaged,
                units: [PageTranscription.Unit(text: salvaged, inkMarks: nil)],
                diagrams: nil,
                confidence: 0.2
            )
        }
        guard !parsed.isEmpty else { throw PageTranscriptionError.emptyPage }
        return parsed
    }

    // MARK: - Prompt (parity with iOS)

    static let systemPrompt = """
    You are a meticulous transcriptionist digitizing a photographed physical page \
    (handwritten notes, whiteboard, book margin, or printed matter). Your job is \
    FAITHFUL TRANSCRIPTION — you never summarize, never paraphrase, never add ideas.

    Rules:
    1. Transcribe exactly what is written, preserving the author's wording, line \
    breaks between distinct thoughts, and list structure. Use markdown lists and \
    headings only where the page visibly has them. Checkboxes become markdown \
    checkboxes: `- [ ]` unticked, `- [x]` ticked. Scientific and mathematical \
    notation transcribes as Unicode exactly as written (H₂O, Δ, →, x², µ) — \
    never spell symbols out or approximate them.
    2. A word you cannot read confidently goes in ⟦double brackets⟧ with your best \
    guess: ⟦vagal?⟧. Never silently invent text.
    3. Detect ink marks the author used: star (★/asterisk), question (?), box \
    (checkbox/rectangle around text), arrow (→ causal/connection), underline. \
    Attach them to the unit they mark.
    4. Split the transcript into UNITS: distinct thoughts as the author wrote them \
    (a bullet line, a sentence block, a margin note). Do not merge separate \
    thoughts; do not split one sentence.
    5. Sketches/diagrams: describe each briefly and give its rough page region. \
    Do not transcribe a diagram as text.
    6. Respond with ONLY a JSON object, no code fences, matching:
    {"pageTitle": string|null, "transcript": string, "units": [{"text": string, \
    "inkMarks": [string]|null}], "diagrams": [{"description": string, "region": \
    string}]|null, "confidence": number}
    """

    static func buildPrompt(context: PageTranscriptionContext) -> String {
        var lines: [String] = ["Transcribe this page."]
        if let title = context.deepDiveTitle, !title.isEmpty {
            lines.append("The page belongs to a study of: \(title).")
        }
        if let question = context.activeQuestionTitle, !question.isEmpty {
            lines.append("The author is currently exploring: \(question).")
        }
        let vocabulary = (context.lexiconTerms + context.conceptNames).filter { !$0.isEmpty }
        if !vocabulary.isEmpty {
            lines.append("Domain terms that may appear (use these spellings when the ink matches): \(vocabulary.prefix(40).joined(separator: ", ")).")
        }
        if let legend = context.inkLegend, !legend.isEmpty {
            lines.append("The author's personal ink notation: \(legend)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Parsing (tolerant)

    static func parse(_ raw: String) -> PageTranscription? {
        guard let jsonString = extractJSONObject(from: raw),
              let data = jsonString.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        guard let transcript = object["transcript"] as? String else { return nil }

        var units: [PageTranscription.Unit] = []
        if let rawUnits = object["units"] as? [[String: Any]] {
            for rawUnit in rawUnits {
                guard let text = rawUnit["text"] as? String,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let marks = (rawUnit["inkMarks"] as? [String])?.filter { !$0.isEmpty }
                units.append(PageTranscription.Unit(text: text, inkMarks: (marks?.isEmpty == false) ? marks : nil))
            }
        }
        if units.isEmpty, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            units = [PageTranscription.Unit(text: transcript, inkMarks: nil)]
        }

        var diagrams: [PageTranscription.Diagram]?
        if let rawDiagrams = object["diagrams"] as? [[String: Any]] {
            let parsed = rawDiagrams.compactMap { raw -> PageTranscription.Diagram? in
                guard let description = raw["description"] as? String, !description.isEmpty else { return nil }
                return PageTranscription.Diagram(description: description, region: raw["region"] as? String)
            }
            diagrams = parsed.isEmpty ? nil : parsed
        }

        let confidence = (object["confidence"] as? Double)
            ?? (object["confidence"] as? Int).map(Double.init)
            ?? 0.5

        // Checkbox grammar: the transcript normalizes to the note glyphs
        // (☐/☑) every surface downstream understands, and a checkbox UNIT
        // sheds its marker for the "box" ink mark — the router reads it as
        // an action instead of choking on markdown syntax.
        let normalizedTranscript = CapturedChecklist.normalizeGlyphs(transcript)
        units = units.map { unit in
            guard let checkbox = CapturedChecklist.parseLine(Substring(unit.text)),
                  !checkbox.title.isEmpty else { return unit }
            var marks = unit.inkMarks ?? []
            if !marks.contains("box") { marks.append("box") }
            return PageTranscription.Unit(text: checkbox.title, inkMarks: marks)
        }

        return PageTranscription(
            pageTitle: (object["pageTitle"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            transcript: normalizedTranscript,
            units: units,
            diagrams: diagrams,
            confidence: min(max(confidence, 0), 1)
        )
    }

    /// First balanced `{…}` in the response — tolerates code fences and prose
    /// wrappers around the contract object.
    static func extractJSONObject(from raw: String) -> String? {
        guard let start = raw.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var previous: Character = " "
        for index in raw.indices[start...] {
            let char = raw[index]
            if inString {
                if char == "\"" && previous != "\\" { inString = false }
            } else {
                switch char {
                case "\"": inString = true
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 { return String(raw[start...index]) }
                default: break
                }
            }
            previous = char
        }
        return nil
    }
}
