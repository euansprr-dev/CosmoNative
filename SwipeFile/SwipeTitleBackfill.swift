// CosmoOS/SwipeFile/SwipeTitleBackfill.swift
// One-time library cleanup: swipes captured before the insight pass carry the
// whole first slide as their title (hook.prefix(120)) — thread-style hooks
// become paragraph-long titles. This pass rewrites them into short display
// headlines with a cheap batched Gemini Flash call, marking progress by
// writing `displayTitle` into each swipe's analysis so a swipe is never
// reprocessed. Same launch-drain grammar as the cloud mirrors.
// July 2026

import Foundation
import GRDB

@MainActor
enum SwipeTitleBackfill {

    /// Titles at or under this length are fine verbatim — only longer,
    /// hook-derived titles get rewritten.
    static let maxCleanTitleLength = 64

    /// Swipes per LLM call.
    static let batchSize = 20

    /// Batches per launch pass — 100 titles/launch drains any real library
    /// in a couple of launches without ever blocking anything.
    static let maxBatchesPerPass = 5

    static let backfillModel = "google/gemini-3-flash-preview"

    private static var hasRunThisLaunch = false

    static func runBackfillPassIfNeeded() async {
        guard !hasRunThisLaunch else { return }
        hasRunThisLaunch = true

        let candidates = await fetchCandidates()
        guard !candidates.isEmpty else { return }

        var rewrote = 0
        for batch in Array(candidates.prefix(batchSize * maxBatchesPerPass)).chunked(into: batchSize) {
            rewrote += await rewriteBatch(batch)
        }
        if rewrote > 0 {
            print("SwipeTitleBackfill: Rewrote \(rewrote) long titles")
            NotificationCenter.default.post(
                name: CosmoNotification.SwipeFile.libraryDidChange, object: nil
            )
        }
    }

    // MARK: - Candidates

    /// A candidate is a swipe whose title is still the auto-derived hook
    /// prefix AND too long, with no displayTitle recorded yet. A title the
    /// user typed themselves never matches the hook prefix, so it's skipped.
    static func isCandidate(title: String?, hook: String?, analysis: SwipeAnalysis?) -> Bool {
        guard let title, title.count > maxCleanTitleLength else { return false }
        guard analysis?.displayTitle == nil else { return false }
        guard let hook, !hook.isEmpty else { return false }
        let normalizedHook = hook
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedHook.hasPrefix(title) || title == String(normalizedHook.prefix(120))
    }

    private static func fetchCandidates() async -> [Atom] {
        let atoms = (try? await CosmoDatabase.shared.asyncRead { db in
            try Atom
                .filter(Column("type") == AtomType.research.rawValue)
                .filter(Column("is_deleted") == false)
                .fetchAll(db)
        }) ?? []
        return atoms.filter { atom in
            atom.isSwipeFileAtom
                && !AtomRepository.shared.isBeingEdited(atom.uuid)
                && isCandidate(title: atom.title, hook: atom.hook, analysis: atom.swipeAnalysis)
        }
    }

    // MARK: - Rewrite

    private static func rewriteBatch(_ atoms: [Atom]) async -> Int {
        let items = atoms.enumerated().map { index, atom in
            let hook = (atom.hook ?? atom.title ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .prefix(280)
            let niche = atom.swipeAnalysis?.niche ?? ""
            return "\(index + 1). \(hook)\(niche.isEmpty ? "" : " [niche: \(niche)]")"
        }.joined(separator: "\n")

        let prompt = """
        These are opening hooks of saved social-media posts. For each, write one short library headline, ≤60 characters, that keeps the creator's voice and the single most specific claim. Keep concrete numbers ("$75K", "90 days"). No quotation marks, no emoji, no trailing period, no editorializing ("Amazing thread about...").

        Example: "Housing didn't get expensive by accident. For decades, home prices ran way ahead of incomes, and now everyone wants to act surprised that young families can't buy" → "Housing didn't get expensive by accident"

        Hooks:
        \(items)

        Return ONLY valid JSON, no markdown fences:
        {"titles": [{"index": 1, "title": "..."}, {"index": 2, "title": "..."}]}
        """

        struct BatchResponse: Codable {
            struct Entry: Codable {
                let index: Int
                let title: String
            }
            let titles: [Entry]
        }

        do {
            let raw = try await ResearchService.shared.analyze(
                prompt: prompt,
                model: backfillModel,
                maxTokens: 2000,
                temperature: 0.2
            )
            var jsonStr = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if jsonStr.hasPrefix("```") {
                if let firstNewline = jsonStr.firstIndex(of: "\n") {
                    jsonStr = String(jsonStr[jsonStr.index(after: firstNewline)...])
                }
                if jsonStr.hasSuffix("```") { jsonStr = String(jsonStr.dropLast(3)) }
                jsonStr = jsonStr.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let data = jsonStr.data(using: .utf8),
                  let response = try? JSONDecoder().decode(BatchResponse.self, from: data) else {
                return 0
            }

            var rewritten = 0
            for entry in response.titles {
                guard entry.index >= 1, entry.index <= atoms.count else { continue }
                let atom = atoms[entry.index - 1]
                let title = entry.title
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\"", with: "")
                guard !title.isEmpty, title.count <= 90 else { continue }
                if await apply(title: title, to: atom) { rewritten += 1 }
            }
            return rewritten
        } catch {
            print("SwipeTitleBackfill: Batch failed: \(error)")
            return 0
        }
    }

    /// Write the new title + record displayTitle in the analysis so this swipe
    /// never re-qualifies. Field-level update only; skips swipes that opened
    /// for editing (or were retitled) during the LLM call.
    private static func apply(title: String, to atom: Atom) async -> Bool {
        guard !AtomRepository.shared.isBeingEdited(atom.uuid) else { return false }
        guard let fresh = try? await AtomRepository.shared.fetch(uuid: atom.uuid),
              isCandidate(title: fresh.title, hook: fresh.hook, analysis: fresh.swipeAnalysis)
        else { return false }

        var analysis = fresh.swipeAnalysis ?? SwipeAnalysis(analysisVersion: 0, isFullyAnalyzed: false)
        analysis.displayTitle = title
        let updated = fresh.withSwipeAnalysis(analysis)

        do {
            _ = try await AtomRepository.shared.updateFields(uuid: atom.uuid, columns: [
                "title": title,
                "structured": updated.structured,
            ])
            return true
        } catch {
            print("SwipeTitleBackfill: Persist failed for \(atom.uuid.prefix(8)): \(error)")
            return false
        }
    }
}

// MARK: - Chunking helper

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
