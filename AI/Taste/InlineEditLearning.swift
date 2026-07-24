// CosmoOS/AI/Taste/InlineEditLearning.swift
// The edit-loop learning core: every inline-review verdict opens an EPISODE
// that watches what the user does next. Accept-then-tweak harvests the
// (AI version → human version) pair — the craft delta the user keeps
// supplying by hand. Reject-then-self-write harvests the same pair with a
// stronger negative. Episodes settle deterministically (quiet surface, doc
// close, overlapping re-edit, app resign) and emit TasteStore signals; the
// exemplar bank and distiller learn from them.
//
// This file is the PURE half (model, store, harvester) — fully testable
// without UI. The MainActor orchestration lives in InlineEditLearningLoop.
// July 2026

import Foundation
import GRDB

// MARK: - Episode

struct InlineEditEpisode: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    static let databaseTableName = "inline_edit_episodes"

    enum Verdict: String, Sendable {
        case accepted
        case rejected
    }

    enum Outcome: String, Sendable {
        /// Open — still watching the surface.
        case settling
        /// The AI text survived untouched: positive confirmation.
        case untouched
        /// The user reshaped the text: the money signal (pair stored).
        case tweak
        /// The user replaced the thought entirely — weak negative, no pair
        /// (a topic change teaches nothing about style).
        case rewrite
        /// Could not attribute confidently — silence over noise.
        case discarded
    }

    /// The reviewed operation's UUID — rollback deletes episodes by these ids.
    var id: String
    var surfaceId: String
    var targetId: String
    var clientUuid: String?
    var skillId: String
    /// The user ask that produced the proposal (for the distiller's context).
    var ask: String
    var verdict: String
    /// The staged text as applied (byte-exact for transaction steps).
    var aiText: String
    /// What the AI replaced (empty for insertions).
    var originalText: String?
    /// hook | body | cta — parsed from the governing SLIDE header.
    var slideRole: String?
    /// Neighboring lines captured at verdict time; the AI edit did not touch
    /// them, so they usually survive the user's tweaks and relocate the region.
    var anchorBefore: String?
    var anchorAfter: String?
    var outcome: String
    var settledText: String?
    /// 1 − token similarity, only for tweak outcomes — the improvement metric.
    var magnitude: Double?
    /// The user's next ask after rejecting — the labeled "why".
    var userReason: String?
    var createdAt: String
    var settledAt: String?

    enum CodingKeys: String, ColumnExpression, CodingKey {
        case id
        case surfaceId = "surface_id"
        case targetId = "target_id"
        case clientUuid = "client_uuid"
        case skillId = "skill_id"
        case ask
        case verdict
        case aiText = "ai_text"
        case originalText = "original_text"
        case slideRole = "slide_role"
        case anchorBefore = "anchor_before"
        case anchorAfter = "anchor_after"
        case outcome
        case settledText = "settled_text"
        case magnitude
        case userReason = "user_reason"
        case createdAt = "created_at"
        case settledAt = "settled_at"
    }

    var verdictKind: Verdict { Verdict(rawValue: verdict) ?? .accepted }
    var isOpen: Bool { outcome == Outcome.settling.rawValue }
}

// MARK: - Store

enum InlineEditEpisodeStore {
    static func insert(_ episode: InlineEditEpisode) async {
        try? await CosmoDatabase.shared.asyncWrite { db in
            guard (try? db.tableExists(InlineEditEpisode.databaseTableName)) ?? false else { return }
            var row = episode
            try row.save(db)
        }
    }

    static func openEpisodes(surfaceId: String? = nil) async -> [InlineEditEpisode] {
        (try? await CosmoDatabase.shared.asyncRead { db in
            guard (try? db.tableExists(InlineEditEpisode.databaseTableName)) ?? false else { return [] }
            var request = InlineEditEpisode
                .filter(Column("outcome") == InlineEditEpisode.Outcome.settling.rawValue)
            if let surfaceId {
                request = request.filter(InlineEditEpisode.CodingKeys.surfaceId == surfaceId)
            }
            return try request.order(Column("created_at")).fetchAll(db)
        }) ?? []
    }

    static func episode(id: String) async -> InlineEditEpisode? {
        (try? await CosmoDatabase.shared.asyncRead { db in
            guard (try? db.tableExists(InlineEditEpisode.databaseTableName)) ?? false else { return nil }
            return try InlineEditEpisode.fetchOne(db, key: id)
        }) ?? nil
    }

    static func markSettled(
        id: String,
        outcome: InlineEditEpisode.Outcome,
        settledText: String?,
        magnitude: Double?
    ) async {
        try? await CosmoDatabase.shared.asyncWrite { db in
            guard (try? db.tableExists(InlineEditEpisode.databaseTableName)) ?? false else { return }
            try db.execute(
                sql: """
                UPDATE inline_edit_episodes
                SET outcome = ?, settled_text = ?, magnitude = ?, settled_at = ?
                WHERE id = ? AND outcome = 'settling'
                """,
                arguments: [outcome.rawValue, settledText, magnitude, ISO8601.string(from: Date()), id]
            )
        }
    }

    static func attachReason(id: String, reason: String) async {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await CosmoDatabase.shared.asyncWrite { db in
            guard (try? db.tableExists(InlineEditEpisode.databaseTableName)) ?? false else { return }
            try db.execute(
                sql: "UPDATE inline_edit_episodes SET user_reason = ? WHERE id = ?",
                arguments: [String(trimmed.prefix(300)), id]
            )
        }
    }

    /// Rollback is not a verdict — a rolled-back run's episodes vanish.
    static func delete(ids: [String]) async {
        guard !ids.isEmpty else { return }
        try? await CosmoDatabase.shared.asyncWrite { db in
            guard (try? db.tableExists(InlineEditEpisode.databaseTableName)) ?? false else { return }
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            try db.execute(
                sql: "DELETE FROM inline_edit_episodes WHERE id IN (\(placeholders))",
                arguments: StatementArguments(ids)
            )
        }
    }

    /// Recent rejection reasons for a skill — the track-record render-back.
    static func recentReasons(skillId: String, limit: Int = 3) async -> [(rejectedText: String, reason: String)] {
        (try? await CosmoDatabase.shared.asyncRead { db in
            guard (try? db.tableExists(InlineEditEpisode.databaseTableName)) ?? false else { return [] }
            return try InlineEditEpisode
                .filter(InlineEditEpisode.CodingKeys.skillId == skillId)
                .filter(Column("verdict") == InlineEditEpisode.Verdict.rejected.rawValue)
                .filter(Column("user_reason") != nil)
                .order(Column("created_at").desc)
                .limit(limit)
                .fetchAll(db)
                .compactMap { episode in
                    episode.userReason.map { (rejectedText: episode.aiText, reason: $0) }
                }
        }) ?? []
    }

    /// The improvement metric: settled-episode counts + mean tweak magnitude,
    /// newest first, for the Studio learning panel.
    struct Metrics: Equatable, Sendable {
        var settledCount: Int
        var untouchedCount: Int
        var tweakCount: Int
        var rewriteCount: Int
        var meanTweakMagnitude: Double?

        var tweakRate: Double? {
            let decided = untouchedCount + tweakCount + rewriteCount
            guard decided > 0 else { return nil }
            return Double(tweakCount + rewriteCount) / Double(decided)
        }
    }

    static func metrics(clientUuid: String?, since: Date? = nil) async -> Metrics {
        (try? await CosmoDatabase.shared.asyncRead { db in
            guard (try? db.tableExists(InlineEditEpisode.databaseTableName)) ?? false else {
                return Metrics(settledCount: 0, untouchedCount: 0, tweakCount: 0, rewriteCount: 0, meanTweakMagnitude: nil)
            }
            var conditions = ["outcome != 'settling'"]
            var arguments: [DatabaseValueConvertible] = []
            if let clientUuid {
                conditions.append("client_uuid = ?")
                arguments.append(clientUuid)
            }
            if let since {
                conditions.append("created_at >= ?")
                arguments.append(ISO8601.string(from: since))
            }
            let whereClause = conditions.joined(separator: " AND ")
            guard let row = try Row.fetchOne(db, sql: """
                SELECT COUNT(*) AS settled,
                       SUM(CASE WHEN outcome = 'untouched' THEN 1 ELSE 0 END) AS untouched,
                       SUM(CASE WHEN outcome = 'tweak' THEN 1 ELSE 0 END) AS tweaked,
                       SUM(CASE WHEN outcome = 'rewrite' THEN 1 ELSE 0 END) AS rewritten,
                       AVG(CASE WHEN outcome = 'tweak' THEN magnitude END) AS mean_magnitude
                FROM inline_edit_episodes WHERE \(whereClause)
                """, arguments: StatementArguments(arguments)) else {
                return Metrics(settledCount: 0, untouchedCount: 0, tweakCount: 0, rewriteCount: 0, meanTweakMagnitude: nil)
            }
            // SUM/AVG return NULL on empty sets — typed-optional reads only.
            let settled: Int? = row["settled"]
            let untouched: Int? = row["untouched"]
            let tweaked: Int? = row["tweaked"]
            let rewritten: Int? = row["rewritten"]
            let meanMagnitude: Double? = row["mean_magnitude"]
            return Metrics(
                settledCount: settled ?? 0,
                untouchedCount: untouched ?? 0,
                tweakCount: tweaked ?? 0,
                rewriteCount: rewritten ?? 0,
                meanTweakMagnitude: meanMagnitude
            )
        }) ?? Metrics(settledCount: 0, untouchedCount: 0, tweakCount: 0, rewriteCount: 0, meanTweakMagnitude: nil)
    }
}

// MARK: - Harvester (pure)

enum InlineEditHarvestOutcome: Equatable, Sendable {
    case untouched
    /// The pair. `magnitude` = 1 − token similarity; `punctuationOnly` marks
    /// word-identical rewrites (em-dash surgery and friends — real taste,
    /// invisible to token similarity).
    case tweak(settledText: String, magnitude: Double, punctuationOnly: Bool)
    case rewrite
    case discarded
}

/// Deterministic settle logic. Every threshold here is a wrong-lesson guard:
/// the bands separate typo-noise (untouched) from craft (tweak) from
/// topic changes (rewrite), and anything unattributable is discarded.
enum InlineEditHarvester {
    /// Token similarity below this = the user replaced the thought.
    static let acceptedTweakFloor = 0.35
    /// Rejected self-writes only pair while still about the same content.
    static let rejectedPairFloor = 0.15
    static let rejectedPairCeiling = 0.97
    /// At/above this (but not locate-verbatim) the words are identical —
    /// the change is punctuation/typography.
    static let punctuationOnlyThreshold = 0.97
    /// Settled text is prompt material — keep it slide-sized.
    static let maxSettledTextLength = 600

    struct Input {
        var verdict: InlineEditEpisode.Verdict
        /// The staged AI text (applied for accepts, offered for rejects).
        var aiText: String
        /// What the AI targeted — for rejects, its survival means "no self-write yet".
        var originalText: String?
        var anchorBefore: String?
        var anchorAfter: String?
        var currentText: String
    }

    static func harvest(_ input: Input) -> InlineEditHarvestOutcome {
        switch input.verdict {
        case .accepted:
            return harvestAccepted(input)
        case .rejected:
            return harvestRejected(input)
        }
    }

    private static func harvestAccepted(_ input: Input) -> InlineEditHarvestOutcome {
        if survivesVerbatim(input.aiText, in: input.currentText) {
            return .untouched
        }
        guard let region = resolveRegion(for: input.aiText, in: input) else {
            return .discarded
        }
        // Whitespace-only drift is not an edit.
        if foldedText(region) == foldedText(input.aiText) {
            return .untouched
        }
        guard hasSubstantialLine(region) else { return .discarded }

        let similarity = tokenSimilarity(input.aiText, region)
        guard similarity >= acceptedTweakFloor else { return .rewrite }
        return .tweak(
            settledText: String(region.prefix(maxSettledTextLength)),
            magnitude: (1 - similarity).rounded(toPlaces: 3),
            punctuationOnly: similarity >= punctuationOnlyThreshold
        )
    }

    private static func harvestRejected(_ input: Input) -> InlineEditHarvestOutcome {
        // The original text still standing means the user never self-wrote —
        // the rejection's value is its userReason, captured separately.
        if let original = input.originalText,
           !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           survivesVerbatim(original, in: input.currentText) {
            return .untouched
        }
        guard let region = resolveRegion(for: input.aiText, in: input),
              hasSubstantialLine(region) else {
            return .discarded
        }
        let similarity = tokenSimilarity(input.aiText, region)
        // Outside the band the region is either the AI text itself (bad
        // relocation) or a different thought — neither is a lesson.
        guard similarity >= rejectedPairFloor, similarity <= rejectedPairCeiling else {
            return .discarded
        }
        return .tweak(
            settledText: String(region.prefix(maxSettledTextLength)),
            magnitude: (1 - similarity).rounded(toPlaces: 3),
            punctuationOnly: false
        )
    }

    // MARK: Region resolution

    /// Finds where the episode's text lives NOW: between its untouched
    /// neighbor lines first, line-vote fallback second, nil when ambiguous.
    private static func resolveRegion(for aiText: String, in input: Input) -> String? {
        let aiLineCount = max(lines(of: aiText).count, 1)
        let maxRegionLines = aiLineCount * 4 + 8

        let beforeRange = input.anchorBefore.flatMap { anchor in
            CosmoInlineDiffLocator.range(of: anchor, in: input.currentText)
        }
        let afterRange = input.anchorAfter.flatMap { anchor in
            CosmoInlineDiffLocator.range(of: anchor, in: input.currentText)
        }

        if let beforeRange, let afterRange, beforeRange.upperBound <= afterRange.lowerBound {
            let region = String(input.currentText[beforeRange.upperBound..<afterRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !region.isEmpty, lines(of: region).count <= maxRegionLines {
                return region
            }
            // Anchors drifted apart — fall through to line voting inside the span.
            if !region.isEmpty, let voted = lineVoteRegion(for: aiText, in: region) {
                return voted
            }
            return nil
        }

        if let beforeRange {
            let tail = String(input.currentText[beforeRange.upperBound...])
            return boundedLeadingRegion(of: tail, lineBudget: aiLineCount + 3)
        }
        if let afterRange {
            let head = String(input.currentText[..<afterRange.lowerBound])
            return boundedTrailingRegion(of: head, lineBudget: aiLineCount + 3)
        }
        return lineVoteRegion(for: aiText, in: input.currentText)
    }

    /// Anchor-free fallback: each substantial AI line votes for its best
    /// current line; a majority within a tight window pins the region.
    private static func lineVoteRegion(for aiText: String, in currentText: String) -> String? {
        let aiLines = lines(of: aiText).filter { CosmoInlineLineDiff.isSubstantialContentLine($0) }
        guard !aiLines.isEmpty else { return nil }
        let currentLines = lines(of: currentText)
        guard !currentLines.isEmpty else { return nil }

        var matchedIndices: [Int] = []
        for aiLine in aiLines {
            var bestIndex: Int?
            var bestScore = 0.45 // floor: below this a line has no vote
            for (index, currentLine) in currentLines.enumerated() {
                let score = tokenSimilarity(aiLine, currentLine)
                if score > bestScore {
                    bestScore = score
                    bestIndex = index
                }
            }
            if let bestIndex { matchedIndices.append(bestIndex) }
        }
        // Majority of AI lines must find a home, in a window that reads as
        // one region — otherwise attribution is guesswork.
        guard matchedIndices.count * 2 >= aiLines.count,
              let low = matchedIndices.min(),
              let high = matchedIndices.max(),
              high - low <= aiLines.count * 2 + 4 else {
            return nil
        }
        return currentLines[low...high].joined(separator: "\n")
    }

    private static func boundedLeadingRegion(of text: String, lineBudget: Int) -> String? {
        let regionLines = Array(lines(of: text).prefix(lineBudget))
        guard !regionLines.isEmpty else { return nil }
        return regionLines.joined(separator: "\n")
    }

    private static func boundedTrailingRegion(of text: String, lineBudget: Int) -> String? {
        let regionLines = Array(lines(of: text).suffix(lineBudget))
        guard !regionLines.isEmpty else { return nil }
        return regionLines.joined(separator: "\n")
    }

    // MARK: Text primitives

    static func lines(of text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func hasSubstantialLine(_ text: String) -> Bool {
        lines(of: text).contains { CosmoInlineLineDiff.isSubstantialContentLine($0) }
    }

    /// The STRICT survival test: whitespace/typography-folded containment,
    /// punctuation intact. The locator is deliberately NOT used here — its
    /// fuzzy fallbacks exist to FIND drifted text, and would classify
    /// punctuation surgery (em-dash removal) as "untouched", silently
    /// discarding exactly the taste signal this system exists to catch.
    static func survivesVerbatim(_ needle: String, in haystack: String) -> Bool {
        let foldedNeedle = foldedText(needle)
        guard !foldedNeedle.isEmpty else { return false }
        return foldedText(haystack).contains(foldedNeedle)
    }

    /// Whole-text fold using the shared per-line match key (whitespace
    /// collapsed, typography folded) — punctuation stays significant.
    private static func foldedText(_ text: String) -> String {
        lines(of: text).map { CosmoInlineLineDiff.matchKey($0) }.joined(separator: "\n")
    }

    /// Symmetric token-multiset similarity over word tokens (letters/digits
    /// only, lowercased): 2·|common| / (|a| + |b|). Punctuation-only changes
    /// score ~1.0 by design — the punctuationOnly flag carries that case.
    static func tokenSimilarity(_ a: String, _ b: String) -> Double {
        let tokensA = wordTokens(a)
        let tokensB = wordTokens(b)
        guard !tokensA.isEmpty || !tokensB.isEmpty else { return 1 }
        guard !tokensA.isEmpty, !tokensB.isEmpty else { return 0 }

        var counts: [String: Int] = [:]
        for token in tokensA { counts[token, default: 0] += 1 }
        var common = 0
        for token in tokensB {
            if let remaining = counts[token], remaining > 0 {
                counts[token] = remaining - 1
                common += 1
            }
        }
        return Double(2 * common) / Double(tokensA.count + tokensB.count)
    }

    private static func wordTokens(_ text: String) -> [String] {
        text.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }
}

// MARK: - Slide role

/// Where in a carousel the edit landed — hooks and CTAs obey different craft
/// rules, so lessons carry their position.
enum InlineEditSlideRole {
    /// Parses the governing "SLIDE N" header above `location` in `text`.
    /// Slide 1 = hook, the last slide = cta, anything else = body; documents
    /// without slide headers get nil (notes, ideas, plain drafts).
    static func role(inText text: String, atLocation location: String.Index) -> String? {
        let slideNumbers = allSlideNumbers(in: text)
        guard let maxSlide = slideNumbers.max(), slideNumbers.count >= 2 else { return nil }
        let head = String(text[..<location])
        guard let governing = allSlideNumbers(in: head).last else { return nil }
        if governing <= 1 { return "hook" }
        if governing == maxSlide { return "cta" }
        return "body"
    }

    private static func allSlideNumbers(in text: String) -> [Int] {
        InlineEditHarvester.lines(of: text).compactMap { line in
            guard let match = line.range(
                of: #"^(?:-{2,}\s*)?SLIDE\s+(\d+)\b"#,
                options: [.regularExpression, .caseInsensitive]
            ) else { return nil }
            let digits = line[match].filter(\.isNumber)
            return Int(digits)
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
