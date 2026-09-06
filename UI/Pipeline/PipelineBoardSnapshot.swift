// CosmoOS/UI/Pipeline/PipelineBoardSnapshot.swift
// The Pipeline board, derived ONCE per (data, filters) off the main actor.
// Columns consume flat arrays; nothing in a body sorts, filters or decodes.
// Pure and tested — ordering, the shipped window and filters are a
// contract, not a vibe.
//
// Board law (September 2026): a piece is on the board only when there is
// evidence of work. The loader derives the stage (explicit stage wins; a
// date, words or editing activity mean in progress; else not started) and
// the snapshot adds the one signal only it can see — a booked writing
// session. Not started is the backlog: collapsed by default, never a wall.
//
// Ordering: not started / in progress / review / ready newest edit first
// with missed dates ahead of everything; shipped newest publish first,
// inside the window.
//
// Published is a shelf, not a wall: a window (7/30/90 days or all time)
// bounds it, and a piece the user CLEARED from the board stays off it —
// while the ledger, the calendar, ⌘K and the client hub keep every
// publish. What the window and the clearing hide is counted, never lost.

import Foundation

struct PipelineBoardSnapshot: Equatable, Sendable {

    // MARK: - Columns

    enum Column: String, CaseIterable, Identifiable, Sendable {
        case notStarted, inProgress, review, ready, shipped
        var id: String { rawValue }
        var title: String { stage.title }
        var stage: ContentProductionStage {
            switch self {
            case .notStarted: return .notStarted
            case .inProgress: return .inProgress
            case .review: return .review
            case .ready: return .ready
            case .shipped: return .published
            }
        }
        static func column(for stage: ContentProductionStage) -> Column {
            switch stage {
            case .notStarted: return .notStarted
            case .inProgress: return .inProgress
            case .review: return .review
            case .ready: return .ready
            case .published: return .shipped
            }
        }
        /// Where a phase lands when nothing else is known: ideation has not
        /// started, shipped phases are shipped, archived is off the board.
        static func column(for phase: ContentPhase) -> Column? {
            if phase == .archived { return nil }
            if phase.isShipped { return .shipped }
            return phase == .ideation ? .notStarted : .inProgress
        }
        static let contentColumns = allCases
        /// The backlog reads as a count, not a wall.
        static let collapsedByDefault: Set<Column> = [.notStarted]
    }

    // MARK: - Cards

    struct ContentCard: Identifiable, Equatable, Sendable {
        let item: PipelineContentItem
        /// Soonest open writing session booked against this piece.
        let sessionDay: Date?
        /// Latest logged performance snapshot, when shipped.
        let perf: ContentPerfSnapshot?
        /// Scheduled for a day that has already passed.
        let isMissed: Bool

        var id: String { PipelineDropPayload.content(item.id).dragString }

        static func == (lhs: ContentCard, rhs: ContentCard) -> Bool {
            lhs.item == rhs.item
                && lhs.sessionDay == rhs.sessionDay
                && lhs.isMissed == rhs.isMissed
                && perfKey(lhs.perf) == perfKey(rhs.perf)
        }

        private static func perfKey(_ perf: ContentPerfSnapshot?) -> String? {
            guard let perf else { return nil }
            return "\(perf.contentUuid)|\(perf.platform)|\(perf.views)|\(perf.likes)|\(perf.comments)|\(perf.shares)|\(perf.saves)|\(perf.followsGained)|\(perf.capturedAt)"
        }
    }

    // MARK: - Output

    let cardsByColumn: [Column: [ContentCard]]
    let countsByColumn: [Column: Int]
    /// Archived rows handed in (the loader keeps them out of `load`, so this
    /// only counts what a caller deliberately passed).
    let archivedCount: Int
    /// Shipped pieces that passed the filters but went out before the window
    /// opened — what the Published foot row calls "older".
    let olderShippedCount: Int
    /// Shipped pieces the user cleared from the board — off the column unless
    /// it is showing them.
    let clearedShippedCount: Int
    /// Cards name their client only when the visible board mixes owners; a
    /// single-client board would repeat one name on every card.
    let showsClientNames: Bool
    /// Card ids per column in rendered order (`Column.allCases` order) — the
    /// keyboard cursor walks this and nothing else.
    let cursorOrder: [[String]]

    static let empty = PipelineBoardSnapshot(
        cardsByColumn: [:], countsByColumn: [:], archivedCount: 0,
        olderShippedCount: 0, clearedShippedCount: 0, showsClientNames: false,
        cursorOrder: Column.allCases.map { _ in [] }
    )

    func cards(in column: Column) -> [ContentCard] {
        cardsByColumn[column] ?? []
    }

    func count(in column: Column) -> Int {
        countsByColumn[column] ?? 0
    }

    var isEmpty: Bool {
        cardsByColumn.values.allSatisfy(\.isEmpty)
    }

    // MARK: - Build

    /// `shippedWindowDays` nil = all time. `showsCleared` puts cleared
    /// pieces back on the Published column (dimmed) so they can be returned.
    static func build(
        content: [PipelineContentItem],
        sessionDaysByContent: [String: Date] = [:],
        perf: [String: ContentPerfSnapshot] = [:],
        filters: PipelineFilters = PipelineFilters(),
        shippedWindowDays: Int? = 30,
        showsCleared: Bool = false,
        today: Date = Calendar.current.startOfDay(for: Date()),
        calendar: Calendar = .current
    ) -> PipelineBoardSnapshot {
        let archivedCount = content.count { $0.phase == .archived }
        let dayStart = calendar.startOfDay(for: today)
        let windowStart: Date? = shippedWindowDays.map { days in
            calendar.date(byAdding: .day, value: -max(0, days), to: dayStart) ?? dayStart
        }

        var buckets: [Column: [ContentCard]] = [:]
        var older = 0
        var cleared = 0
        var owners = Set<String?>()
        for item in content {
            guard item.phase != .archived,
                  filters.matches(title: item.title, clientName: item.clientName,
                                  platform: item.platform, format: item.contentFormat) else { continue }
            let sessionDay = sessionDaysByContent[item.id]
            let column = Column.column(for: stage(of: item, hasSession: sessionDay != nil))
            if column == .shipped {
                if item.isClearedFromBoard {
                    cleared += 1
                    if !showsCleared { continue }
                } else if let windowStart, let shipped = item.shippedAt, shipped < windowStart {
                    older += 1
                    continue
                }
            }
            owners.insert(item.clientUUID)
            buckets[column, default: []].append(ContentCard(
                item: item,
                sessionDay: sessionDay,
                perf: perf[item.id],
                isMissed: isMissed(item, dayStart: dayStart, calendar: calendar)
            ))
        }

        var cardsByColumn: [Column: [ContentCard]] = [:]
        for (column, cards) in buckets {
            cardsByColumn[column] = sorted(cards, in: column)
        }

        var counts: [Column: Int] = [:]
        for column in Column.contentColumns {
            counts[column] = cardsByColumn[column]?.count ?? 0
        }

        let cursorOrder = Column.allCases.map { column -> [String] in
            (cardsByColumn[column] ?? []).map(\.id)
        }

        return PipelineBoardSnapshot(
            cardsByColumn: cardsByColumn,
            countsByColumn: counts,
            archivedCount: archivedCount,
            olderShippedCount: older,
            clearedShippedCount: cleared,
            showsClientNames: owners.count > 1,
            cursorOrder: cursorOrder
        )
    }

    // MARK: - Rules

    /// A booked writing session is evidence of work the loader cannot see.
    /// It lifts an UNSTAGED backlog piece into In progress; an explicit
    /// stage is never overridden.
    static func stage(of item: PipelineContentItem, hasSession: Bool) -> ContentProductionStage {
        let derived = item.productionStage
        guard derived == .notStarted, item.editorialStage == nil, hasSession else { return derived }
        return .inProgress
    }

    private static func isMissed(_ item: PipelineContentItem, dayStart: Date, calendar: Calendar) -> Bool {
        guard !item.isShipped, let scheduled = item.scheduledAt else { return false }
        return calendar.startOfDay(for: scheduled) < dayStart
    }

    private static func sorted(_ cards: [ContentCard], in column: Column) -> [ContentCard] {
        switch column {
        case .notStarted, .inProgress, .review, .ready:
            return cards.sorted { lhs, rhs in
                if lhs.isMissed != rhs.isMissed { return lhs.isMissed }
                if lhs.item.updatedAt != rhs.item.updatedAt { return lhs.item.updatedAt > rhs.item.updatedAt }
                return tieBreak(lhs, rhs)
            }
        case .shipped:
            return cards.sorted { lhs, rhs in
                let lhsDay = lhs.item.shippedAt ?? .distantPast
                let rhsDay = rhs.item.shippedAt ?? .distantPast
                if lhsDay != rhsDay { return lhsDay > rhsDay }
                return tieBreak(lhs, rhs)
            }
        }
    }

    /// Deterministic order for equal keys — title, then uuid.
    private static func tieBreak(_ lhs: ContentCard, _ rhs: ContentCard) -> Bool {
        let byTitle = lhs.item.title.localizedCaseInsensitiveCompare(rhs.item.title)
        if byTitle != .orderedSame { return byTitle == .orderedAscending }
        return lhs.item.id < rhs.item.id
    }
}
