// CosmoOS/SwipeFile/Artifacts/SwipeGenreClassifier.swift
// The cheap, dedicated "what IS this?" call.
//
// Genre used to ride the Sonnet craft pass as a one-shot side effect: slow,
// failure-coupled, and never applied to anything captured before it existed.
// This classifier decouples filing from judging — one fast Flash call with
// the closed vocabulary, so a capture lands in its room in seconds even when
// (especially when) the expensive craft pass later fails.
//
// LADDER SEAT: URL seed → page-shape seed → THIS → craft verdict → user lock.
// Its writes are FILL-ONLY (genre nil, not locked); the craft verdict still
// refines it, and "File under →" still beats everything. Confidence below
// 0.5 answers nil — the structural fallback is a visible, fixable state, and
// wrong-but-confident is the one failure mode this system never accepts.

import Foundation
import AppKit

@MainActor
enum SwipeGenreClassifier {

    /// Same family the worker's classification uses; vision-capable, cents
    /// per call. The 2.0-flash sunset (silent 404s) is why the fallback tier
    /// exists — never "restore" a single hardcoded model.
    static let model = "google/gemini-3-flash-preview"
    static let fallbackModel = "google/gemini-2.5-flash"

    /// Below this the classifier keeps its mouth shut and the structural
    /// fallback stands.
    static let confidenceFloor = 0.5

    /// Images sent per call — the first frames carry the identity; ten
    /// screenshots of one funnel don't classify better than four.
    static let maxImages = 4

    struct Verdict: Equatable {
        var genre: SwipeGenre
        var confidence: Double
    }

    // MARK: - Entry points

    /// Classify a frame set (screenshots, rendered PDF pages) by looking at
    /// it. Unit copy and the collector's note ride along as context.
    static func classify(images: [Data], note: String?, unitCopy: [String]) async -> Verdict? {
        var content: [[String: Any]] = [["type": "text", "text": prompt(note: note, unitCopy: unitCopy)]]
        for data in images.prefix(maxImages) {
            guard let encoded = SwipeFrameAnalyzer.downscaledJPEGBase64(data) else { continue }
            content.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(encoded)"]
            ])
        }
        guard content.count > 1 else { return nil }
        return await complete(content: content)
    }

    /// Classify a page by its sliced text (title + headings + opening copy).
    static func classify(pageText: String, url: String?, note: String?) async -> Verdict? {
        let trimmed = String(pageText.prefix(2000)).trimmed
        guard !trimmed.isEmpty else { return nil }
        var body = prompt(note: note, unitCopy: [])
        if let url, !url.isEmpty { body += "\nThe page's address: \(url)" }
        body += "\n\nTHE PAGE'S TEXT:\n\(trimmed)"
        return await complete(content: [["type": "text", "text": body]])
    }

    // MARK: - Prompt

    static func prompt(note: String?, unitCopy: [String]) -> String {
        var text = """
        You are filing one saved marketing artifact into a swipe library. Decide what \
        it IS, from this closed list. Answer with the single key from the list — never \
        a word that is not on it.

        \(SwipeGenre.promptVocabulary)

        Tie-breaks:
        - One email issue is a newsletter. Several emails that form one sending \
        sequence are a funnel.
        - A page whose only ask is an email address, a booking, or a trial is a \
        landingPage. A page that names a price or drives to a checkout is a salesPage.
        - Screenshots OF an advertisement are ad, even when the ad points at a landing page.
        - A countdown, an RSVP, or a "save my spot" ask for a live event is a \
        landingPage unless a price is named.
        - When genuinely none of the specific genres fits, answer the structural \
        fallback for what you were shown: screenshot for images, page for a web page, \
        copy for text.
        """
        if let note = note?.trimmed, !note.isEmpty {
            text += "\n\nThe collector's own note (context, never the answer): \(note)"
        }
        let copy = unitCopy.map(\.trimmed).filter { !$0.isEmpty }
        if !copy.isEmpty {
            text += "\n\nTEXT ALREADY READ FROM THE ARTIFACT:\n" + copy.prefix(6).joined(separator: "\n---\n").prefix(1600)
        }
        text += """
        \n
        Return ONLY this JSON, no prose, no code fence:
        {"genre": "<key>", "confidence": <0.0-1.0>}
        """
        return text
    }

    // MARK: - Transport

    private static func complete(content: [[String: Any]]) async -> Verdict? {
        if let verdict = await complete(content: content, model: model) { return verdict }
        // Preview models 404/5xx without warning; the stable tier answers.
        return await complete(content: content, model: fallbackModel)
    }

    private static func complete(content: [[String: Any]], model: String) async -> Verdict? {
        guard let apiKey = APIKeys.openRouter, !apiKey.isEmpty else { return nil }
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": content]],
            "temperature": 0.1,
            "max_tokens": 120
        ]
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = payload["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let text = message["content"] as? String else { return nil }
            return parse(text)
        } catch {
            return nil
        }
    }

    // MARK: - Parse (pure, tested)

    /// Fence-tolerant JSON → Verdict, resolved onto the closed vocabulary.
    /// nil for: unparseable, unknown genre, or confidence under the floor.
    static func parse(_ raw: String) -> Verdict? {
        var text = raw.trimmed
        if text.hasPrefix("```") {
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
            if text.hasSuffix("```") { text = String(text.dropLast(3)) }
            text = text.trimmed
        }
        guard let data = text.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let genre = SwipeGenre.resolve(dict["genre"] as? String) else { return nil }
        let confidence = (dict["confidence"] as? NSNumber)?.doubleValue ?? 0
        guard confidence >= confidenceFloor else { return nil }
        return Verdict(genre: genre, confidence: confidence)
    }

    // MARK: - Fill-only persistence

    /// Write a verdict onto a swipe ONLY when nothing better exists: the
    /// envelope has no genre and no human lock. The craft verdict may later
    /// overwrite this; "File under →" always wins. Returns the genre written.
    @discardableResult
    static func fill(_ verdict: Verdict?, intoAtomWithUUID uuid: String) async -> SwipeGenre? {
        guard let verdict,
              let live = try? await AtomRepository.shared.fetch(uuid: uuid),
              let artifact = live.swipeArtifact,
              artifact.genre == nil,
              artifact.genreLockedByUser != true else { return nil }
        let updated = live.withSwipeGenre(verdict.genre, lockedByUser: false)
        _ = try? await AtomRepository.shared.update(updated)
        NotificationCenter.default.post(name: CosmoNotification.SwipeFile.libraryDidChange, object: nil)
        return verdict.genre
    }
}
