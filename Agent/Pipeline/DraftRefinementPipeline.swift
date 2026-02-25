// CosmoOS/Agent/Pipeline/DraftRefinementPipeline.swift
// Multi-turn draft refinement via Telegram
// Parses natural language feedback, applies AI writing operations,
// tracks revision history, and reports diffs

import Foundation

// MARK: - Revision Entry

/// A single revision in the refinement history
struct RevisionEntry: Codable, Sendable {
    let feedback: String
    let operation: String
    let wordCountBefore: Int
    let wordCountAfter: Int
    let timestamp: Date
}

// MARK: - Refinement Result

/// Result of a single refinement operation
struct RefinementResult: Sendable {
    let success: Bool
    let revisedText: String
    let diffSummary: String
    let operation: String
}

// MARK: - DraftRefinementPipeline

/// Multi-turn draft refinement pipeline driven by natural language feedback.
/// NOT a singleton — instantiate one per active refinement session.
///
/// Usage:
/// ```swift
/// let pipeline = DraftRefinementPipeline()
/// let intro = await pipeline.startSession(contentUUID: "abc-123", chatId: "456")
/// let result = await pipeline.refine(feedback: "make it more punchy")
/// ```
@MainActor
class DraftRefinementPipeline {

    // MARK: - Properties

    /// UUID of the content atom being refined
    private(set) var contentUUID: String = ""

    /// Telegram chat ID for sending updates
    private(set) var chatId: String = ""

    /// Full revision history for this session
    private(set) var revisionHistory: [RevisionEntry] = []

    /// Current working text (kept in memory between refinements)
    private var currentText: String = ""

    /// The original text when the session started, for cumulative diff
    private var originalText: String = ""

    /// Atom repository for persistence
    private let atomRepo = AtomRepository.shared

    // MARK: - Init

    init() {}

    // MARK: - Start Session

    /// Start a refinement session for a content atom.
    /// Loads the current draft, sends it to Telegram, and returns an intro message.
    func startSession(contentUUID: String, chatId: String) async -> String {
        self.contentUUID = contentUUID
        self.chatId = chatId
        self.revisionHistory = []

        // Load the content atom
        do {
            guard let atom = try await atomRepo.fetch(uuid: contentUUID) else {
                return "Content not found (UUID: \(contentUUID.prefix(8))...)"
            }

            let title = atom.title ?? "Untitled"
            let body = atom.body ?? ""

            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "Draft is empty. Write something first, then come back for refinement."
            }

            currentText = body
            originalText = body
            let wordCount = body.split(separator: " ").count

            // Send the current draft to Telegram
            let draftPreview: String
            if body.count > 1500 {
                draftPreview = String(body.prefix(1500)) + "\n\n... (\(wordCount) words total)"
            } else {
                draftPreview = body
            }

            await notifyTelegram(text: "Draft: \"\(title)\" (\(wordCount) words)\n\n\(draftPreview)")
            await notifyTelegram(text: "Refinement session started. Send feedback like:\n- \"more punchy\"\n- \"shorter\"\n- \"expand the opening\"\n- \"add a statistic about X\"\n- \"rephrase paragraph 2\"\n\nSend \"done\" to end the session.")

            return "Refinement session started for \"\(title)\" (\(wordCount) words). Awaiting your feedback."
        } catch {
            return "Failed to load content: \(error.localizedDescription)"
        }
    }

    // MARK: - Refine

    /// Apply a single refinement based on natural language feedback.
    /// Classifies the feedback intent, applies the appropriate AI writing operation,
    /// tracks the revision, and saves back to the content atom.
    func refine(feedback: String) async -> RefinementResult {
        let cleanFeedback = feedback.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !currentText.isEmpty else {
            return RefinementResult(
                success: false,
                revisedText: "",
                diffSummary: "No active draft. Start a session first.",
                operation: "none"
            )
        }

        guard !cleanFeedback.isEmpty else {
            return RefinementResult(
                success: false,
                revisedText: currentText,
                diffSummary: "Empty feedback — no changes applied.",
                operation: "none"
            )
        }

        let wordCountBefore = currentText.split(separator: " ").count
        let (operation, target) = classifyFeedback(cleanFeedback)

        await notifyTelegram(text: "Applying: \(operation)...")

        // Determine the text to operate on
        let textToProcess: String
        if let target = target {
            textToProcess = extractTargetSection(text: currentText, target: target)
        } else {
            textToProcess = currentText
        }

        // Apply the appropriate AI operation
        let assistant = AIWritingAssistant()
        var revisedText: String? = nil

        switch operation {
        case "expand":
            let result = await assistant.expand(text: textToProcess, context: cleanFeedback)
            revisedText = result?.suggestedText

        case "condense":
            let result = await assistant.condense(text: textToProcess, context: cleanFeedback)
            revisedText = result?.suggestedText

        case "rephrase":
            let result = await assistant.rephrase(text: textToProcess, context: cleanFeedback)
            // For rephrase, take the first variant if available
            if let variants = result?.variants, let first = variants.first {
                revisedText = first
            } else {
                revisedText = result?.suggestedText
            }

        case "continue":
            let result = await assistant.continueWriting(text: textToProcess)
            revisedText = result?.suggestedText

        case "add_data":
            // Search swipe library for relevant data points, then expand with context
            let dataPoints = await searchForDataPoints(topic: cleanFeedback)
            let contextNote = dataPoints.isEmpty
                ? cleanFeedback
                : "\(cleanFeedback)\n\nRelevant data: \(dataPoints.joined(separator: "; "))"
            let result = await assistant.expand(text: textToProcess, context: contextNote)
            revisedText = result?.suggestedText

        default:
            // Fallback: use rephrase for unclassified feedback
            let result = await assistant.rephrase(text: textToProcess, context: cleanFeedback)
            revisedText = result?.suggestedText
        }

        guard let revised = revisedText, !revised.isEmpty else {
            return RefinementResult(
                success: false,
                revisedText: currentText,
                diffSummary: "AI could not generate a revision. Try rephrasing your feedback.",
                operation: operation
            )
        }

        // If we operated on a section, splice it back into the full text
        let fullRevised: String
        if target != nil && textToProcess != currentText {
            fullRevised = currentText.replacingOccurrences(of: textToProcess, with: revised)
        } else {
            fullRevised = revised
        }

        let wordCountAfter = fullRevised.split(separator: " ").count

        // Track the revision
        let entry = RevisionEntry(
            feedback: cleanFeedback,
            operation: operation,
            wordCountBefore: wordCountBefore,
            wordCountAfter: wordCountAfter,
            timestamp: Date()
        )
        revisionHistory.append(entry)

        // Update the working text
        let previousText = currentText
        currentText = fullRevised

        // Save back to the content atom
        do {
            _ = try await atomRepo.update(uuid: contentUUID) { atom in
                atom.body = fullRevised
            }
        } catch {
            print("[DraftRefinementPipeline] Failed to save revision: \(error.localizedDescription)")
        }

        // Build diff summary
        let diffSummary = getDiffSummary(original: previousText, revised: fullRevised)

        // Notify Telegram
        let preview: String
        if fullRevised.count > 2000 {
            preview = String(fullRevised.prefix(2000)) + "\n\n... (\(wordCountAfter) words total)"
        } else {
            preview = fullRevised
        }
        await notifyTelegram(text: "\(diffSummary)\n\n---\n\n\(preview)")

        return RefinementResult(
            success: true,
            revisedText: fullRevised,
            diffSummary: diffSummary,
            operation: operation
        )
    }

    // MARK: - Diff Summary

    /// Compare two texts and return a human-readable summary of changes.
    func getDiffSummary(original: String, revised: String) -> String {
        let originalWords = original.split(separator: " ").count
        let revisedWords = revised.split(separator: " ").count
        let wordDiff = revisedWords - originalWords

        let originalSentences = countSentences(in: original)
        let revisedSentences = countSentences(in: revised)
        let sentenceDiff = revisedSentences - originalSentences

        // Rough "sentences changed" estimate via line-level comparison
        let originalLines = original.components(separatedBy: ". ")
        let revisedLines = revised.components(separatedBy: ". ")
        let changedSentences = estimateChangedSentences(original: originalLines, revised: revisedLines)

        var parts: [String] = []

        // Word count change
        if wordDiff > 0 {
            parts.append("Expanded from \(originalWords) to \(revisedWords) words (+\(wordDiff))")
        } else if wordDiff < 0 {
            parts.append("Shortened from \(originalWords) to \(revisedWords) words (\(wordDiff))")
        } else {
            parts.append("Same length: \(revisedWords) words")
        }

        // Sentence structure
        if sentenceDiff != 0 {
            let sentenceLabel = sentenceDiff > 0 ? "+\(sentenceDiff)" : "\(sentenceDiff)"
            parts.append("Sentences: \(originalSentences) -> \(revisedSentences) (\(sentenceLabel))")
        }

        if changedSentences > 0 {
            parts.append("~\(changedSentences) sentence(s) restructured")
        }

        return parts.joined(separator: ". ") + "."
    }

    // MARK: - Revision History

    /// Format the full revision history for display.
    func getRevisionHistory() -> String {
        guard !revisionHistory.isEmpty else {
            return "No revisions yet."
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        var lines: [String] = ["Revision History (\(revisionHistory.count) changes):"]
        lines.append("")

        for (index, entry) in revisionHistory.enumerated() {
            let time = formatter.string(from: entry.timestamp)
            let wordChange: String
            let diff = entry.wordCountAfter - entry.wordCountBefore
            if diff > 0 {
                wordChange = "+\(diff) words"
            } else if diff < 0 {
                wordChange = "\(diff) words"
            } else {
                wordChange = "same length"
            }

            lines.append("\(index + 1). [\(time)] \(entry.operation): \"\(truncate(entry.feedback, to: 40))\" (\(wordChange))")
        }

        // Cumulative summary
        if revisionHistory.count > 1 {
            let totalOriginalWords = originalText.split(separator: " ").count
            let totalCurrentWords = currentText.split(separator: " ").count
            let netDiff = totalCurrentWords - totalOriginalWords
            let netLabel = netDiff >= 0 ? "+\(netDiff)" : "\(netDiff)"
            lines.append("")
            lines.append("Net change: \(totalOriginalWords) -> \(totalCurrentWords) words (\(netLabel))")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private: Feedback Classification

    /// Classify natural language feedback into an operation type and optional target section.
    /// Returns (operation, target) where operation is one of:
    /// "expand", "condense", "rephrase", "continue", "add_data", or "general".
    private func classifyFeedback(_ text: String) -> (operation: String, target: String?) {
        let lowered = text.lowercased()

        // Target extraction: look for "paragraph N", "opening", "closing", "intro", etc.
        let target = extractTarget(from: lowered)

        // Expansion signals
        let expandPatterns = [
            "expand", "elaborate", "more detail", "flesh out", "add more",
            "deeper", "go deeper", "develop", "more about", "build on",
            "longer", "extend"
        ]
        for pattern in expandPatterns {
            if lowered.contains(pattern) {
                return ("expand", target)
            }
        }

        // Condensation signals
        let condensePatterns = [
            "shorter", "condense", "tighten", "cut", "trim", "concise",
            "brief", "shorten", "reduce", "less verbose", "too long",
            "too wordy", "streamline"
        ]
        for pattern in condensePatterns {
            if lowered.contains(pattern) {
                return ("condense", target)
            }
        }

        // Rephrase signals
        let rephrasePatterns = [
            "rephrase", "rewrite", "reword", "different way", "another way",
            "more punchy", "punchier", "stronger", "more engaging",
            "more conversational", "less formal", "more formal",
            "more casual", "change tone", "sharpen"
        ]
        for pattern in rephrasePatterns {
            if lowered.contains(pattern) {
                return ("rephrase", target)
            }
        }

        // Continue writing signals
        let continuePatterns = [
            "continue", "keep going", "finish", "complete", "write more",
            "next section", "what comes next"
        ]
        for pattern in continuePatterns {
            if lowered.contains(pattern) {
                return ("continue", target)
            }
        }

        // Data/statistic insertion signals
        let dataPatterns = [
            "add statistic", "add stat", "add data", "add number",
            "find a stat", "include data", "add evidence", "add proof",
            "add example", "find example", "reference", "cite"
        ]
        for pattern in dataPatterns {
            if lowered.contains(pattern) {
                return ("add_data", target)
            }
        }

        // Fallback: treat as general rephrase
        return ("rephrase", target)
    }

    /// Extract a target section reference from feedback (e.g., "paragraph 2", "opening").
    private func extractTarget(from text: String) -> String? {
        // Paragraph references
        if let range = text.range(of: #"paragraph\s*(\d+)"#, options: .regularExpression) {
            return String(text[range])
        }

        // Named sections
        let sectionNames = ["opening", "intro", "introduction", "closing", "conclusion",
                            "hook", "headline", "title", "first paragraph", "last paragraph",
                            "beginning", "ending"]
        for name in sectionNames {
            if text.contains(name) {
                return name
            }
        }

        return nil
    }

    /// Extract the target section from the full text based on the target descriptor.
    private func extractTargetSection(text: String, target: String) -> String {
        let paragraphs = text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        // Paragraph number reference
        if target.contains("paragraph") {
            let digits = target.filter(\.isNumber)
            if let num = Int(digits), num > 0, num <= paragraphs.count {
                return paragraphs[num - 1]
            }
        }

        // Named section references
        let lowTarget = target.lowercased()
        if lowTarget.contains("opening") || lowTarget.contains("intro") ||
           lowTarget.contains("first") || lowTarget.contains("beginning") || lowTarget.contains("hook") {
            return paragraphs.first ?? text
        }

        if lowTarget.contains("closing") || lowTarget.contains("conclusion") ||
           lowTarget.contains("last") || lowTarget.contains("ending") {
            return paragraphs.last ?? text
        }

        // Fallback: return entire text
        return text
    }

    // MARK: - Private: Data Point Search

    /// Search the swipe library for relevant statistics, data points, or examples.
    private func searchForDataPoints(topic: String) async -> [String] {
        // Extract the actual topic from the feedback (strip instruction words)
        let cleanTopic = topic
            .replacingOccurrences(of: "add statistic about", with: "")
            .replacingOccurrences(of: "add stat about", with: "")
            .replacingOccurrences(of: "add data about", with: "")
            .replacingOccurrences(of: "find a stat about", with: "")
            .replacingOccurrences(of: "add evidence for", with: "")
            .replacingOccurrences(of: "add example of", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanTopic.isEmpty else { return [] }

        do {
            let results = try await HybridSearchEngine.shared.search(
                query: cleanTopic,
                limit: 5,
                entityTypes: [.research]
            )

            var dataPoints: [String] = []
            for result in results.prefix(3) {
                let preview = result.preview.trimmingCharacters(in: .whitespacesAndNewlines)
                if !preview.isEmpty {
                    // Truncate to a usable snippet
                    let snippet = preview.count > 200 ? String(preview.prefix(197)) + "..." : preview
                    dataPoints.append(snippet)
                }
            }

            return dataPoints
        } catch {
            print("[DraftRefinementPipeline] Data point search failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Private: Text Utilities

    /// Count sentences in a text (rough heuristic via period/question/exclamation marks).
    private func countSentences(in text: String) -> Int {
        let terminators = CharacterSet(charactersIn: ".!?")
        let count = text.unicodeScalars.filter { terminators.contains($0) }.count
        return max(count, 1)
    }

    /// Estimate how many sentences were changed between original and revised splits.
    private func estimateChangedSentences(original: [String], revised: [String]) -> Int {
        let originalSet = Set(original.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let revisedSet = Set(revised.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })

        // Count sentences in revised that are not in original (new or changed)
        let newSentences = revisedSet.subtracting(originalSet).count
        // Count sentences in original that are not in revised (removed or changed)
        let removedSentences = originalSet.subtracting(revisedSet).count

        return max(newSentences, removedSentences)
    }

    /// Truncate a string to a maximum length, appending "..." if truncated.
    private func truncate(_ text: String, to length: Int) -> String {
        if text.count <= length { return text }
        return String(text.prefix(length - 3)) + "..."
    }

    /// Send a message to the active Telegram chat.
    private func notifyTelegram(text: String) async {
        guard !chatId.isEmpty else { return }
        await TelegramBridgeService.shared.sendMessage(
            chatId: chatId,
            text: text,
            parseMode: nil,
            replyMarkup: nil
        )
    }
}
