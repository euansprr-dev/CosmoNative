// CosmoOS/UI/Pipeline/PipelineBoardSnapshot.swift
// The Pipeline board, derived ONCE per (data, filters, grouping) off the
// main actor. Columns consume flat arrays; nothing in a body sorts,
// filters or decodes. Pure and tested — ordering, the shipped window,
// filters and client grouping are a contract, not a vibe.
//
// Ordering: brainstorm/draft/polish newest edit first; scheduled soonest
// first with missed dates ahead of everything; shipped newest publish
// first, inside the window; ideas keep the desk's order untouched.
// September 2026

import Foundation

struct PipelineBoardSnapshot: Equatable, Sendable {

    // MARK: - Columns

    enum Column: String, CaseIterable, Identifiable, Sendable {
        case inProgress, review, ready, shipped
        var id: String { rawValue }
        var title: String { stage.title }
        var stage: ContentProductionStage {
            switch self {
            case .inProgress: return .inProgress
            case .review: return .review
            case .ready: return .ready
            case .shipped: return .published
            }
        }
        var phase: ContentPhase? {
            switch self {
            case .inProgress: return .draft
            case .review, .ready: return .polish
            case .shipped: return .published
            }
        }
        static func column(for stage: ContentProductionStage) -> Column {
            switch stage {
            case .inProgress: return .inProgress
            case .review: return .review
            case .ready: return .ready
            case .published: return .shipped
            }
        }
        static func column(for phase: ContentPhase) -> Column? {
            phase == .archived ? nil : (phase.isShipped ? .shipped : .inProgress)
        }
        static let contentColumns = allCases
    }

    // MARK: - Cards

    struct IdeaCard: Identifiable, Equatable, Sendable {
        let item: IdeaGalleryItem
        /// Soonest open writing session booked for this idea.
        let sessionDay: Date?

        var id: String { PipelineDropPayload.idea(item.atomUUID).dragString }

        /// `IdeaGalleryItem` is not Equatable; compare the fields a card paints.
        static func == (lhs: IdeaCard, rhs: IdeaCard) -> Bool {
            lhs.item.atomUUID == rhs.item.atomUUID
                && lhs.item.title == rhs.item.title
                && lhs.item.updatedAt == rhs.item.updatedAt
                && lhs.item.status == rhs.item.status
                && lhs.item.clientUUID == rhs.item.clientUUID
                && lhs.item.clientName == rhs.item.clientName
                && lhs.item.isPinned == rhs.item.isPinned
                && lhs.sessionDay == rhs.sessionDay
        }
    }

    struct ContentCard: Identifiable, Equatable, Sendable {
        let item: PipelineContentItem
        /// Soonest open writing session booked against this piece.
        let sessionDay: Date?
        /// Latest logged performance snapshot, when shipped.
        let perf: ContentPerfSnapshot?
        /// Scheduled for a day that has already passed.
        let isMissed: Bool
        /// Client name ("Unassigned" for none) when grouping is on; nil otherwise.
        let clientGroup: String?

        var id: String { PipelineDropPayload.content(item.id).dragString }

        static func == (lhs: ContentCard, rhs: ContentCard) -> Bool {
            lhs.item == rhs.item
                && lhs.sessionDay == rhs.sessionDay
                && lhs.isMissed == rhs.isMissed
                && lhs.clientGroup == rhs.clientGroup
                && perfKey(lhs.perf) == perfKey(rhs.perf)
        }

        private static func perfKey(_ perf: ContentPerfSnapshot?) -> String? {
            guard let perf else { return nil }
            return "\(perf.contentUuid)|\(perf.platform)|\(perf.views)|\(perf.likes)|\(perf.comments)|\(perf.shares)|\(perf.saves)|\(perf.followsGained)|\(perf.capturedAt)"
        }
    }

    // MARK: - Output

    let ideas: [IdeaCard]
    let cardsByColumn: [Column: [ContentCard]]
    let countsByColumn: [Column: Int]
    /// Archived rows handed in (the loader keeps them out of `load`, so this
    /// only counts what a caller deliberately passed).
    let archivedCount: Int
    /// Card ids per column in rendered order (`Column.allCases` order) — the
    /// keyboard cursor walks this and nothing else.
    let cursorOrder: [[String]]

    static let empty = PipelineBoardSnapshot(
        ideas: [], cardsByColumn: [:], countsByColumn: [:], archivedCount: 0,
        cursorOrder: Column.allCases.map { _ in [] }
    )

    func cards(in column: Column) -> [ContentCard] {
        cardsByColumn[column] ?? []
    }

    func count(in column: Column) -> Int {
        countsByColumn[column] ?? 0
    }

    var isEmpty: Bool {
        ideas.isEmpty && cardsByColumn.values.allSatisfy(\.isEmpty)
    }

    // MARK: - Build

    static func build(
        content: [PipelineContentItem],
        ideas: [IdeaGalleryItem],
        sessionDaysByIdea: [String: Date] = [:],
        sessionDaysByContent: [String: Date] = [:],
        perf: [String: ContentPerfSnapshot] = [:],
        filters: PipelineFilters = PipelineFilters(),
        groupByClient: Bool = false,
        shippedWindowDays: Int = 30,
        today: Date = Calendar.current.startOfDay(for: Date()),
        calendar: Calendar = .current
    ) -> PipelineBoardSnapshot {
        let archivedCount = content.count { $0.phase == .archived }
        let dayStart = calendar.startOfDay(for: today)
        let windowStart = calendar.date(byAdding: .day, value: -max(0, shippedWindowDays), to: dayStart) ?? dayStart

        let ideaCards = ideas
            .filter { ideaPasses($0, filters: filters) }
            .map { IdeaCard(item: $0, sessionDay: sessionDaysByIdea[$0.atomUUID]) }

        var buckets: [Column: [ContentCard]] = [:]
        for item in content {
            guard item.phase != .archived,
                  filters.matches(title: item.title, clientName: item.clientName,
                                  platform: item.platform, format: item.contentFormat) else { continue }
            let column = Column.column(for: item.productionStage)
            if column == .shipped, let shipped = item.shippedAt, shipped < windowStart { continue }
            buckets[column, default: []].append(ContentCard(
                item: item,
                sessionDay: sessionDaysByContent[item.id],
                perf: perf[item.id],
                isMissed: isMissed(item, dayStart: dayStart, calendar: calendar),
                clientGroup: groupByClient ? (item.clientName ?? unassignedGroup) : nil
            ))
        }

        var cardsByColumn: [Column: [ContentCard]] = [:]
        for (column, cards) in buckets {
            let ordered = sorted(cards, in: column)
            cardsByColumn[column] = groupByClient ? partitionedByClient(ordered) : ordered
        }

        var counts: [Column: Int] = [:]
        for column in Column.contentColumns {
            counts[column] = cardsByColumn[column]?.count ?? 0
        }

        let cursorOrder = Column.allCases.map { column -> [String] in
            (cardsByColumn[column] ?? []).map(\.id)
        }

        return PipelineBoardSnapshot(
            ideas: ideaCards,
            cardsByColumn: cardsByColumn,
            countsByColumn: counts,
            archivedCount: archivedCount,
            cursorOrder: cursorOrder
        )
    }

    static let unassignedGroup = "Unassigned"

    // MARK: - Rules

    private static func ideaPasses(_ idea: IdeaGalleryItem, filters: PipelineFilters) -> Bool {
        filters.matches(
            title: idea.title,
            clientName: idea.clientName,
            platform: idea.platform.flatMap { SocialPlatform(rawValue: $0.rawValue) },
            format: idea.contentFormat
        )
    }

    private static func isMissed(_ item: PipelineContentItem, dayStart: Date, calendar: Calendar) -> Bool {
        guard !item.isShipped, let scheduled = item.scheduledAt else { return false }
        return calendar.startOfDay(for: scheduled) < dayStart
    }

    private static func sorted(_ cards: [ContentCard], in column: Column) -> [ContentCard] {
        switch column {
        case .inProgress, .review, .ready:
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

    /// Stable partition by client name: clients alphabetically, Unassigned
    /// last, and the column's own order preserved inside each group.
    private static func partitionedByClient(_ cards: [ContentCard]) -> [ContentCard] {
        cards.enumerated().sorted { lhs, rhs in
            let lhsGroup = groupRank(lhs.element)
            let rhsGroup = groupRank(rhs.element)
            if lhsGroup.isUnassigned != rhsGroup.isUnassigned { return !lhsGroup.isUnassigned }
            let byName = lhsGroup.name.localizedCaseInsensitiveCompare(rhsGroup.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func groupRank(_ card: ContentCard) -> (isUnassigned: Bool, name: String) {
        guard let name = card.item.clientName else { return (true, unassignedGroup) }
        return (false, name)
    }
}
