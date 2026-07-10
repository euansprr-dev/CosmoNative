// CosmoOS/AI/DailyBriefEngine.swift
// The Daily Return — a grounded morning brief for the Command Center
// masthead. Built ONLY from local data: yesterday's activity, today's
// commitments, and recall picks connecting existing knowledge to today's
// work (including one "resurfacing" pick — something mature you haven't
// touched in a month that's relevant again). One Haiku-tier call composes
// the prose; every line carries a tappable receipt. Thin data → fewer
// lines, or no brief at all — the silence law. Cached once per day.
// July 2026

import Foundation
import GRDB

// MARK: - Brief Model

struct DailyBrief: Codable, Equatable, Sendable {
    struct Line: Codable, Equatable, Sendable, Identifiable {
        var id: String { "\(text.hashValue)" }
        var text: String
        /// Optional receipt: an atom the line is grounded in.
        var atomUuid: String?
        var atomTitle: String?
    }

    var dateKey: String            // "2026-07-10" — one brief per local day
    var lines: [Line]
    var generatedAt: String
}

// MARK: - Engine

@MainActor
final class DailyBriefEngine {
    static let shared = DailyBriefEngine()

    private static let cacheKey = "dailyBrief.cached"
    private static let dismissedKey = "dailyBrief.dismissedDateKey"

    private init() {}

    // MARK: - Public API

    /// Today's brief: cached if already generated, freshly composed on the
    /// first Command Center open of the day. Returns nil when data is too
    /// thin to say anything grounded (silence law) or when dismissed.
    func briefForToday(regenerate: Bool = false) async -> DailyBrief? {
        let key = Self.localDayKey()
        if !regenerate {
            if UserDefaults.standard.string(forKey: Self.dismissedKey) == key { return nil }
            if let cached = loadCached(), cached.dateKey == key { return cached }
        }

        guard let brief = await compose(dateKey: key) else { return nil }
        saveCached(brief)
        UserDefaults.standard.removeObject(forKey: Self.dismissedKey)
        return brief
    }

    func dismissForToday() {
        UserDefaults.standard.set(Self.localDayKey(), forKey: Self.dismissedKey)
    }

    // MARK: - Composition

    private func compose(dateKey: String) async -> DailyBrief? {
        let context = await gatherContext()

        // Silence law: nothing worth saying → no brief, no filler.
        guard context.hasSubstance else { return nil }

        let recallLines = context.recallPicks.map { pick in
            DailyBrief.Line(
                text: pick.reason,
                atomUuid: pick.hit.atomUuid,
                atomTitle: pick.hit.title
            )
        }

        var lines: [DailyBrief.Line] = []
        if let summary = await composeSummary(context) {
            lines.append(DailyBrief.Line(text: summary, atomUuid: nil, atomTitle: nil))
        }
        lines.append(contentsOf: recallLines.prefix(3))

        guard !lines.isEmpty else { return nil }
        return DailyBrief(
            dateKey: dateKey,
            lines: lines,
            generatedAt: ISO8601.string(from: Date())
        )
    }

    // MARK: - Context Gathering (all local, all factual)

    struct RecallPick {
        let hit: RecallHit
        let reason: String
    }

    private struct BriefContext {
        var capturedYesterday = 0
        var completedYesterday = 0
        var dueTodayTasks: [String] = []
        var contentDueToday: [String] = []
        var recallPicks: [RecallPick] = []

        var hasSubstance: Bool {
            capturedYesterday > 0 || completedYesterday > 0
                || !dueTodayTasks.isEmpty || !contentDueToday.isEmpty
                || !recallPicks.isEmpty
        }
    }

    private func gatherContext() async -> BriefContext {
        var context = BriefContext()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!

        // Yesterday's activity + today's commitments in one read.
        let facts: (captured: Int, completed: Int, dueTasks: [String], dueContent: [(String, String)]) =
            (try? await CosmoDatabase.shared.asyncRead { db in
                let capturedTypes = RecallDocumentBuilder.indexedTypes.map { "'\($0.rawValue)'" }.joined(separator: ",")
                let captured = try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM atoms
                    WHERE is_deleted = 0 AND type IN (\(capturedTypes))
                      AND created_at >= ? AND created_at < ?
                    """, arguments: [ISO8601.string(from: yesterdayStart), ISO8601.string(from: todayStart)]) ?? 0

                let completed = try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM atoms
                    WHERE is_deleted = 0 AND type = 'task'
                      AND metadata LIKE '%"status":"completed"%'
                      AND updated_at >= ? AND updated_at < ?
                    """, arguments: [ISO8601.string(from: yesterdayStart), ISO8601.string(from: todayStart)]) ?? 0

                // Content scheduled for today (queue field).
                let todayPrefix = String(ISO8601.string(from: todayStart).prefix(10))
                let contentRows = try Row.fetchAll(db, sql: """
                    SELECT uuid, title FROM atoms
                    WHERE is_deleted = 0 AND type = 'content'
                      AND metadata LIKE '%"scheduledAt":"\(todayPrefix)%'
                    LIMIT 5
                    """)
                let dueContent = contentRows.compactMap { row -> (String, String)? in
                    guard let uuid: String = row["uuid"] else { return nil }
                    let title: String = row["title"] ?? "Untitled"
                    return (uuid, title)
                }

                return (captured, completed, [], dueContent)
            }) ?? (0, 0, [], [])

        context.capturedYesterday = facts.captured
        context.completedYesterday = facts.completed
        context.contentDueToday = facts.dueContent.map(\.1)

        // Recall picks: knowledge relevant to today's scheduled content.
        for (contentUuid, title) in facts.dueContent.prefix(2) {
            let hits = await RecallEngine.shared.query(RecallQuery(
                text: title,
                types: [.connection, .research],
                limit: 2,
                excludeUuids: [contentUuid],
                minScore: 0.32
            ))
            if let hit = hits.first {
                context.recallPicks.append(RecallPick(
                    hit: hit,
                    reason: "For “\(String(title.prefix(50)))”, you already have “\(hit.title)”."
                ))
            }
        }

        // One resurfacing pick: a mature connection untouched for 30+ days.
        if let resurfaced = await resurfacingPick(excluding: Set(context.recallPicks.map(\.hit.atomUuid))) {
            context.recallPicks.append(resurfaced)
        }

        return context
    }

    /// A connection you built and then stopped visiting — surfaced at most
    /// one per day, only when it's substantial (has a body worth rereading).
    private func resurfacingPick(excluding: Set<String>) async -> RecallPick? {
        let monthAgo = ISO8601.string(from: Date().addingTimeInterval(-30 * 86_400))
        let candidate: Atom? = (try? await CosmoDatabase.shared.asyncRead { db in
            try Atom
                .filter(Column("type") == AtomType.connection.rawValue)
                .filter(Column("is_deleted") == false)
                .filter(Column("updated_at") < monthAgo)
                .filter(sql: "LENGTH(COALESCE(body, '')) > 400")
                .order(sql: "RANDOM()")
                .fetchOne(db)
        }) ?? nil

        guard let candidate, !excluding.contains(candidate.uuid) else { return nil }
        let title = candidate.title ?? "Untitled"
        let age = ISO8601.date(from: candidate.updatedAt)
            .map { Int(Date().timeIntervalSince($0) / 86_400) } ?? 30
        return RecallPick(
            hit: RecallHit(
                atomUuid: candidate.uuid,
                atomType: .connection,
                title: title,
                matchedText: String((candidate.body ?? "").prefix(200)),
                page: nil,
                score: 1,
                vectorSimilarity: 0,
                keywordScore: 0,
                updatedAt: ISO8601.date(from: candidate.updatedAt)
            ),
            reason: "“\(title)” has been quiet for \(age) days — worth a reread?"
        )
    }

    // MARK: - Summary Line (the only LLM call, and only when there are facts)

    private func composeSummary(_ context: BriefContext) async -> String? {
        var facts: [String] = []
        if context.capturedYesterday > 0 {
            facts.append("captured \(context.capturedYesterday) new items yesterday")
        }
        if context.completedYesterday > 0 {
            facts.append("completed \(context.completedYesterday) tasks yesterday")
        }
        if !context.contentDueToday.isEmpty {
            facts.append("content due today: \(context.contentDueToday.joined(separator: ", "))")
        }
        guard !facts.isEmpty else { return nil }

        let prompt = """
        Compose ONE sentence (max 22 words) for a creator's morning dashboard from these facts. \
        Second person, plain and warm, no exclamation marks, no advice, just the state of play.

        FACTS: \(facts.joined(separator: "; "))
        """

        let composed = try? await ResearchService.shared.analyze(
            prompt: prompt,
            systemPrompt: "You compress dashboard facts into one grounded sentence. Never invent numbers or items.",
            tier: .sensor,
            maxTokens: 60
        )
        let cleaned = composed?.trimmingCharacters(in: .whitespacesAndNewlines)
        // LLM unavailable → fall back to the plain facts, still grounded.
        return (cleaned?.isEmpty == false ? cleaned : "Yesterday: " + facts.joined(separator: " · ") + ".")
    }

    // MARK: - Cache

    /// The brief's "day" starts at 4 a.m. local — a 1 a.m. open still shows
    /// yesterday's brief instead of composing tomorrow's early.
    private static func localDayKey(_ date: Date = Date()) -> String {
        let shifted = date.addingTimeInterval(-4 * 3600)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: shifted)
    }

    private func loadCached() -> DailyBrief? {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey) else { return nil }
        return try? JSONDecoder().decode(DailyBrief.self, from: data)
    }

    private func saveCached(_ brief: DailyBrief) {
        if let data = try? JSONEncoder().encode(brief) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }
}

// MARK: - Masthead Card

import SwiftUI

struct DailyBriefCard: View {
    @State private var brief: DailyBrief?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let brief {
                card(brief)
            }
        }
        .task {
            brief = await DailyBriefEngine.shared.briefForToday()
            isLoading = false
        }
    }

    private func card(_ brief: DailyBrief) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            HStack(spacing: DS.space6) {
                Image(systemName: "sunrise")
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(DS.gilt)
                    .accessibilityHidden(true)
                Text("TODAY'S BRIEF")
                    .font(DS.smallCaps)
                    .tracking(1.4)
                    .foregroundStyle(DS.textMuted)
                Spacer()
                Button {
                    DailyBriefEngine.shared.dismissForToday()
                    withAnimation(ProMotionSprings.gentle) { self.brief = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DS.textMuted)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Dismiss for today")
                .accessibilityLabel("Dismiss today's brief")
            }

            VStack(alignment: .leading, spacing: DS.space6) {
                ForEach(brief.lines) { line in
                    briefLine(line)
                }
            }
        }
        .padding(DS.space16)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.giltMuted.opacity(0.25), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func briefLine(_ line: DailyBrief.Line) -> some View {
        if let atomUuid = line.atomUuid {
            Button {
                NotificationCenter.default.post(
                    name: CosmoNotification.Navigation.openBlockInFocusMode,
                    object: nil,
                    userInfo: ["atomUUID": atomUuid]
                )
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: DS.space6) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(DS.gilt)
                        .accessibilityHidden(true)
                    Text(line.text)
                        .font(DS.callout)
                        .foregroundStyle(DS.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(line.text). Opens \(line.atomTitle ?? "the source")")
        } else {
            Text(line.text)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
