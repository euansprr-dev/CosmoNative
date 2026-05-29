// CosmoOS/UI/CommandK/CommandKViewModel.swift
// ViewModel for Command-K overlay - manages search state and constellation
// Powers the NodeGraph OS Command-K interface
// Phase 4: Multi-select filters, HybridSearchEngine integration, filter counts

import SwiftUI
import Combine
import AppKit

// MARK: - CommandKTab

/// The domain tabs available in Command-K
public enum CommandKTab: String, CaseIterable, Equatable {
    case database
    case swipeGallery
    case ideas
    case readwise
    case inquiry

    public static var allCases: [CommandKTab] {
        [.database, .swipeGallery, .ideas, .readwise]
    }

    var title: String {
        switch self {
        case .database: return "Database"
        case .swipeGallery: return "Swipe File"
        case .ideas: return "Ideas"
        case .readwise: return "Library"
        case .inquiry: return "Inquiry"
        }
    }

    var icon: String {
        switch self {
        case .database: return "tray.full.fill"
        case .swipeGallery: return "bolt.fill"
        case .ideas: return "lightbulb.fill"
        case .readwise: return "books.vertical.fill"
        case .inquiry: return "circle.hexagongrid.circle.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .database: return DS.accent
        case .swipeGallery: return DS.entitySwipe
        case .ideas: return DS.entityIdea
        case .readwise: return DS.entityReadwise
        case .inquiry: return CosmoMentionColors.color(for: .deepDive)
        }
    }

    var searchPlaceholder: String {
        switch self {
        case .database: return "Search database..."
        case .swipeGallery: return "Search swipes..."
        case .ideas: return "Search ideas..."
        case .readwise: return "Search library..."
        case .inquiry: return "Search Deep Dives, questions, lexicon..."
        }
    }

    var compactSubtitle: String {
        switch self {
        case .database: return "All objects"
        case .swipeGallery: return "Captures & hooks"
        case .ideas: return "Sparks & notes"
        case .readwise: return "Books & sources"
        case .inquiry: return "Questions & evidence"
        }
    }

    var headerArtworkMode: CommandKHeaderArtworkMode {
        .contentBackedMasthead
    }

    var headerPersonality: CommandKHeaderPersonality {
        switch self {
        case .database, .inquiry: return .objectIndex
        case .swipeGallery: return .swipeThumbnails
        case .ideas: return .ideaSnippets
        case .readwise: return .libraryCovers
        }
    }

    var expandedBodyStyle: CommandKExpandedBodyStyle {
        switch self {
        case .swipeGallery: return .adaptive
        default: return .light
        }
    }
}

enum CommandKExpandedBodyStyle: Equatable {
    case light
    case adaptive
}

enum CommandKHeaderArtworkMode: Equatable {
    case contentBackedMasthead
}

enum CommandKHeaderPersonality: Equatable {
    case objectIndex
    case swipeThumbnails
    case ideaSnippets
    case libraryCovers
}

struct CommandKHeaderPreviewContent: Equatable {
    let tab: CommandKTab
    let signal: CommandKHeaderPersonality
    let items: [CommandKHeaderPreviewItem]
    let metrics: [CommandKHeaderPreviewMetric]
}

struct CommandKHeaderPreviewItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let detail: String?
    let thumbnailURL: String?
    let systemImage: String
}

struct CommandKHeaderPreviewMetric: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
}

enum CommandKHeaderPreviewComposer {
    static func build(
        recentItems: [RecentDisplayItem],
        swipeItems: [SwipeGalleryItem],
        ideaItems: [IdeaGalleryItem],
        readwiseBooks: [ReadwiseLibraryBook]
    ) -> [CommandKTab: CommandKHeaderPreviewContent] {
        [
            .database: databasePreview(from: recentItems),
            .swipeGallery: swipePreview(from: swipeItems),
            .ideas: ideaPreview(from: ideaItems),
            .readwise: readwisePreview(from: readwiseBooks)
        ]
    }

    static func fallback(for tab: CommandKTab) -> CommandKHeaderPreviewContent {
        CommandKHeaderPreviewContent(
            tab: tab,
            signal: tab.headerPersonality,
            items: [],
            metrics: []
        )
    }

    private static func databasePreview(from items: [RecentDisplayItem]) -> CommandKHeaderPreviewContent {
        let previewItems = items.prefix(4).map { item in
            CommandKHeaderPreviewItem(
                id: item.id,
                title: item.title,
                subtitle: item.type.displayName,
                detail: item.relativeDate,
                thumbnailURL: item.thumbnailURL,
                systemImage: item.type.iconName
            )
        }

        return CommandKHeaderPreviewContent(
            tab: .database,
            signal: .objectIndex,
            items: previewItems,
            metrics: [
                CommandKHeaderPreviewMetric(id: "recent", label: "Recent", value: "\(previewItems.count)")
            ]
        )
    }

    private static func swipePreview(from items: [SwipeGalleryItem]) -> CommandKHeaderPreviewContent {
        let previewItems = items.prefix(5).map { item in
            CommandKHeaderPreviewItem(
                id: item.atomUUID,
                title: item.title,
                subtitle: item.author ?? item.creatorName ?? item.platformName,
                detail: item.hookScore.map { String(format: "%.1f", $0) },
                thumbnailURL: item.thumbnailUrl,
                systemImage: item.platformIcon
            )
        }
        let averageScore = average(items.compactMap(\.hookScore)).map { String(format: "%.1f", $0) }

        return CommandKHeaderPreviewContent(
            tab: .swipeGallery,
            signal: .swipeThumbnails,
            items: previewItems,
            metrics: [
                CommandKHeaderPreviewMetric(id: "score", label: "Avg score", value: averageScore ?? "-"),
                CommandKHeaderPreviewMetric(id: "shown", label: "Showing", value: "\(previewItems.count)")
            ]
        )
    }

    private static func ideaPreview(from items: [IdeaGalleryItem]) -> CommandKHeaderPreviewContent {
        let previewItems = items.prefix(4).map { item in
            CommandKHeaderPreviewItem(
                id: item.atomUUID,
                title: item.title,
                subtitle: item.clientName ?? item.status.displayName,
                detail: item.contentFormat?.displayName ?? item.updatedAt,
                thumbnailURL: nil,
                systemImage: "text.badge.checkmark"
            )
        }

        return CommandKHeaderPreviewContent(
            tab: .ideas,
            signal: .ideaSnippets,
            items: previewItems,
            metrics: [
                CommandKHeaderPreviewMetric(id: "clients", label: "Clients", value: "\(Set(items.compactMap(\.clientName)).count)")
            ]
        )
    }

    private static func readwisePreview(from books: [ReadwiseLibraryBook]) -> CommandKHeaderPreviewContent {
        let previewItems = books.prefix(5).map { book in
            CommandKHeaderPreviewItem(
                id: "\(book.id)",
                title: book.title,
                subtitle: book.author ?? book.category.displayName,
                detail: "\(book.numHighlights) highlights",
                thumbnailURL: book.coverImageUrl,
                systemImage: book.category.icon
            )
        }

        return CommandKHeaderPreviewContent(
            tab: .readwise,
            signal: .libraryCovers,
            items: previewItems,
            metrics: [
                CommandKHeaderPreviewMetric(id: "highlights", label: "Highlights", value: "\(books.reduce(0) { $0 + $1.numHighlights })")
            ]
        )
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

struct CommandKDomainPresentation: Equatable {
    let counts: [CommandKTab: Int]
    let previews: [CommandKTab: CommandKHeaderPreviewContent]

    static let empty = CommandKDomainPresentation(
        counts: Dictionary(uniqueKeysWithValues: CommandKTab.allCases.map { ($0, 0) } + [(.inquiry, 0)]),
        previews: Dictionary(uniqueKeysWithValues: (CommandKTab.allCases + [.inquiry]).map {
            ($0, CommandKHeaderPreviewComposer.fallback(for: $0))
        })
    )

    static func build(
        databaseTotalCount: Int,
        swipeTotalCount: Int,
        ideaTotalCount: Int,
        deepDiveTotalCount: Int,
        recentItems: [RecentDisplayItem],
        swipeItems: [SwipeGalleryItem],
        ideaItems: [IdeaGalleryItem],
        readwiseBooks: [ReadwiseLibraryBook]
    ) -> CommandKDomainPresentation {
        let previews = CommandKHeaderPreviewComposer.build(
            recentItems: recentItems,
            swipeItems: swipeItems,
            ideaItems: ideaItems,
            readwiseBooks: readwiseBooks
        )

        return CommandKDomainPresentation(
            counts: [
                .database: databaseTotalCount,
                .swipeGallery: swipeItems.isEmpty ? swipeTotalCount : swipeItems.count,
                .ideas: ideaItems.isEmpty ? ideaTotalCount : ideaItems.count,
                .readwise: readwiseBooks.count,
                .inquiry: deepDiveTotalCount
            ],
            previews: previews
        )
    }
}

struct CommandKContentFormatFacet: Equatable {
    let format: ContentFormat
    let count: Int
}

struct CommandKNarrativeFacet: Equatable {
    let style: NarrativeStyle
    let count: Int
}

struct CommandKSwipeFacetSummary: Equatable {
    let topContentFormats: [CommandKContentFormatFacet]
    let topNarrativeStyles: [CommandKNarrativeFacet]
    let averageHookScore: Double?

    static let empty = CommandKSwipeFacetSummary(
        topContentFormats: [],
        topNarrativeStyles: [],
        averageHookScore: nil
    )

    static func build(
        allItems: [SwipeGalleryItem],
        filteredItems: [SwipeGalleryItem],
        contentLimit: Int = 7,
        narrativeLimit: Int = 6
    ) -> CommandKSwipeFacetSummary {
        let topContentFormats = ContentFormat.allCases.compactMap { format -> CommandKContentFormatFacet? in
            let count = allItems.reduce(0) { total, item in
                total + (item.swipeContentFormat == format ? 1 : 0)
            }
            guard count > 0 else { return nil }
            return CommandKContentFormatFacet(format: format, count: count)
        }
        .sorted { $0.count > $1.count }
        .prefix(contentLimit)
        .map { $0 }

        let topNarrativeStyles = NarrativeStyle.allCases.compactMap { style -> CommandKNarrativeFacet? in
            let count = allItems.reduce(0) { total, item in
                total + (item.primaryNarrative == style ? 1 : 0)
            }
            guard count > 0 else { return nil }
            return CommandKNarrativeFacet(style: style, count: count)
        }
        .sorted { $0.count > $1.count }
        .prefix(narrativeLimit)
        .map { $0 }

        let scores = filteredItems.compactMap(\.hookScore)
        let averageHookScore = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)

        return CommandKSwipeFacetSummary(
            topContentFormats: topContentFormats,
            topNarrativeStyles: topNarrativeStyles,
            averageHookScore: averageHookScore
        )
    }
}

// MARK: - CortexMode

/// The three interaction modes of the Cortex Command-K interface
public enum CortexMode: Equatable {
    /// Compact: search bar + domain bubbles + recents grid
    case compact
    /// Search results: grouped results by source
    case searchResults
    /// Expanded domain: full tab content (Database, Swipes, Ideas, Readwise)
    case expandedDomain(CommandKTab)
}

// MARK: - RecentDisplayItem

/// Lightweight model for recent items shown in compact mode
public struct RecentDisplayItem: Identifiable {
    public let id: String  // atom UUID
    let title: String
    let type: AtomType
    let entityId: Int64
    let relativeDate: String
    let thumbnailURL: String?
    let preview: String?
}

enum CommandKLibraryScope {
    static let databaseAtomTypes: [AtomType] = [
        .idea, .note, .task, .content, .research, .connection, .image
    ]

    static func databaseItemCount(atoms: [Atom], thinkspaceCount: Int) -> Int {
        atoms.filter { !$0.isDeleted && !$0.isSwipeFileAtom }.count + thinkspaceCount
    }
}

enum CommandKRecentComposer {
    struct OpenedAtom {
        let atom: Atom
        let openedAt: String
        let accessCount: Int
    }

    private struct Candidate {
        let atom: Atom
        let timestamp: String
        let accessCount: Int
    }

    static func compose(
        opened: [OpenedAtom],
        recentlyUpdated _: [Atom] = [],
        limit: Int
    ) -> [RecentDisplayItem] {
        return sortedOpenedCandidates(opened: opened)
            .prefix(limit)
            .map { candidate in
                let atom = candidate.atom
                let researchMeta = atom.metadata.flatMap { metaStr -> ResearchMetadata? in
                    guard let data = metaStr.data(using: .utf8) else { return nil }
                    return try? JSONDecoder().decode(ResearchMetadata.self, from: data)
                }

                return RecentDisplayItem(
                    id: atom.uuid,
                    title: atom.title ?? "Untitled",
                    type: atom.type,
                    entityId: atom.id ?? 0,
                    relativeDate: relativeTimeString(from: candidate.timestamp),
                    thumbnailURL: researchMeta?.thumbnailUrl,
                    preview: atom.body
                )
            }
    }

    static func rankedResults(
        opened: [OpenedAtom],
        recentlyUpdated _: [Atom] = [],
        limit: Int
    ) -> [RankedResult] {
        sortedOpenedCandidates(opened: opened)
            .prefix(limit)
            .map { candidate in
                let atom = candidate.atom
                return RankedResult(
                    atomUUID: atom.uuid,
                    atomType: atom.type,
                    title: atom.title ?? "Untitled",
                    snippet: atom.body?.prefix(100).description,
                    semanticWeight: 0.0,
                    structuralWeight: 0.5,
                    recencyWeight: WeightCalculator.recencyWeight(fromISO8601: candidate.timestamp),
                    usageWeight: 0.5,
                    updatedAt: candidate.timestamp,
                    accessCount: candidate.accessCount
                )
            }
    }

    private static func sortedOpenedCandidates(opened: [OpenedAtom]) -> [Candidate] {
        var candidates: [String: Candidate] = [:]

        for item in opened {
            consider(atom: item.atom, timestamp: item.openedAt, accessCount: item.accessCount, candidates: &candidates)
        }

        return candidates.values.sorted { lhs, rhs in
            let lhsDate = date(fromTimestamp: lhs.timestamp) ?? .distantPast
            let rhsDate = date(fromTimestamp: rhs.timestamp) ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.accessCount > rhs.accessCount
        }
    }

    private static func consider(
        atom: Atom,
        timestamp: String,
        accessCount: Int,
        candidates: inout [String: Candidate]
    ) {
        guard !atom.isDeleted, atom.type != .task else { return }

        let next = Candidate(atom: atom, timestamp: timestamp, accessCount: accessCount)
        guard let existing = candidates[atom.uuid] else {
            candidates[atom.uuid] = next
            return
        }

        let existingDate = date(fromTimestamp: existing.timestamp) ?? .distantPast
        let nextDate = date(fromTimestamp: timestamp) ?? .distantPast
        if nextDate > existingDate || (nextDate == existingDate && accessCount > existing.accessCount) {
            candidates[atom.uuid] = next
        }
    }

    private static func relativeTimeString(from timestamp: String) -> String {
        guard let date = date(fromTimestamp: timestamp) else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 3600 { return "\(max(1, Int(interval / 60)))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        if interval < 604800 { return "\(Int(interval / 86400))d" }
        return "\(Int(interval / 604800))w"
    }

    private static func date(fromTimestamp timestamp: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: timestamp) {
            return date
        }

        let sqliteFormatter = DateFormatter()
        sqliteFormatter.locale = Locale(identifier: "en_US_POSIX")
        sqliteFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        sqliteFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return sqliteFormatter.date(from: timestamp)
    }
}

// MARK: - SearchPhase
/// Current phase of the search process
public enum SearchPhase: Sendable {
    case idle           // No search active
    case instant        // Instant (cached) results shown
    case searching      // Full search in progress
    case complete       // Search complete
}

public enum CommandKSearchFeedback: Equatable, Sendable {
    case none
    case empty(query: String)

    func matches(query: String) -> Bool {
        guard case .empty(let expectedQuery) = self else { return false }
        return expectedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CommandKSearchChromePolicy {
    static let showsTypingProgressIndicator = false
}

// MARK: - SwipeViewMode

enum SwipeViewMode: String, CaseIterable {
    case clustered
    case flat

    var displayName: String {
        switch self {
        case .clustered: return "Clustered"
        case .flat: return "Grid"
        }
    }

    var icon: String {
        switch self {
        case .clustered: return "folder.fill"
        case .flat: return "square.grid.2x2.fill"
        }
    }
}

// MARK: - CommandKSearchMatcher

enum CommandKSearchMatcher {
    static func normalize(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func normalizeQuery(_ query: String) -> String {
        normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func searchableText(from values: [String?]) -> String {
        values
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return normalize(value)
            }
            .joined(separator: " ")
    }

    static func matches(_ query: String, in value: String?) -> Bool {
        matches(normalizedQuery: normalizeQuery(query), in: value)
    }

    static func matches(normalizedQuery: String, in value: String?) -> Bool {
        guard !normalizedQuery.isEmpty, let value, !value.isEmpty else { return false }
        return normalize(value).contains(normalizedQuery)
    }

    static func matches(normalizedQuery: String, inNormalizedText normalizedText: String) -> Bool {
        guard !normalizedQuery.isEmpty, !normalizedText.isEmpty else { return false }
        return normalizedText.contains(normalizedQuery)
    }

    static func matches(_ query: String, inAny values: [String?]) -> Bool {
        let normalizedQuery = normalizeQuery(query)
        guard !normalizedQuery.isEmpty else { return false }
        return values.contains { matches(normalizedQuery: normalizedQuery, in: $0) }
    }
}

// MARK: - Unified Search Types

/// Source category for unified cross-library search results
enum UnifiedSearchSource: String, CaseIterable {
    case atoms       // HybridSearchEngine results (all atom types)
    case swipes      // Swipe gallery matches
    case ideas       // Idea gallery matches
    case readwise    // ReadwiseBookStore matches
    case browser     // Cosmo browser pinned pages

    var displayName: String {
        switch self {
        case .atoms: return "Database"
        case .swipes: return "Swipe File"
        case .ideas: return "Ideas"
        case .readwise: return "Library"
        case .browser: return "Browser Pins"
        }
    }

    var icon: String {
        switch self {
        case .atoms: return "tray.full.fill"
        case .swipes: return "bolt.fill"
        case .ideas: return "lightbulb.fill"
        case .readwise: return "books.vertical.fill"
        case .browser: return "pin.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .atoms: return DS.accent
        case .swipes: return DS.entitySwipe
        case .ideas: return DS.entityIdea
        case .readwise: return DS.entityReadwise
        case .browser: return DS.entityResearch
        }
    }
}

enum UnifiedSearchResultKind: String {
    case atom
    case project
    case thinkspace
    case readwise
    case browserPin
}

/// A single result in the unified cross-library search
struct UnifiedSearchResult: Identifiable {
    let id: String
    let source: UnifiedSearchSource
    let resultKind: UnifiedSearchResultKind
    let title: String
    let subtitle: String?
    let snippet: String?
    let icon: String
    let accentColor: Color
    let relevance: Double
    let atomUUID: String?
    let atomType: AtomType?
    let thinkspaceId: String?
    let projectUUID: String?
    let projectName: String?
    let thinkspaceNames: [String]
    let readwiseBookId: Int?
    let browserURL: URL?
    let browserTitle: String?

    init(
        id: String,
        source: UnifiedSearchSource,
        resultKind: UnifiedSearchResultKind,
        title: String,
        subtitle: String?,
        snippet: String?,
        icon: String,
        accentColor: Color,
        relevance: Double,
        atomUUID: String?,
        atomType: AtomType?,
        thinkspaceId: String?,
        projectUUID: String?,
        projectName: String?,
        thinkspaceNames: [String],
        readwiseBookId: Int?,
        browserURL: URL? = nil,
        browserTitle: String? = nil
    ) {
        self.id = id
        self.source = source
        self.resultKind = resultKind
        self.title = title
        self.subtitle = subtitle
        self.snippet = snippet
        self.icon = icon
        self.accentColor = accentColor
        self.relevance = relevance
        self.atomUUID = atomUUID
        self.atomType = atomType
        self.thinkspaceId = thinkspaceId
        self.projectUUID = projectUUID
        self.projectName = projectName
        self.thinkspaceNames = thinkspaceNames
        self.readwiseBookId = readwiseBookId
        self.browserURL = browserURL
        self.browserTitle = browserTitle
    }

    var selectionID: String {
        atomUUID ?? thinkspaceId ?? id
    }

    var libraryLookupKey: String? {
        switch resultKind {
        case .atom:
            return atomUUID
        case .project:
            return atomUUID
        case .thinkspace:
            return thinkspaceId
        case .readwise:
            return nil
        case .browserPin:
            return nil
        }
    }
}

enum UnifiedCardItem: Identifiable {
    case library(LibraryItem)
    case swipe(SwipeGalleryItem)
    case readwise(UnifiedSearchResult)

    var id: String {
        switch self {
        case .library(let item):
            return item.id
        case .swipe(let item):
            return item.id
        case .readwise(let result):
            return result.id
        }
    }

    var selectionID: String {
        switch self {
        case .library(let item):
            return item.uuid
        case .swipe(let item):
            return item.atomUUID
        case .readwise(let result):
            return result.id
        }
    }
}

struct UnifiedSearchOutput {
    let groupedResults: [(source: UnifiedSearchSource, results: [UnifiedSearchResult])]
    let flatResults: [UnifiedSearchResult]
}

enum CommandKUnifiedSearchComposer {
    private static let hybridLimit = 15
    private static let swipeLimit = 8
    private static let ideaLimit = 8
    private static let readwiseLimit = 8
    private static let browserPinLimit = 8

    static func buildOutput(
        query: String,
        hybridResults: [RankedResult],
        swipeGalleryItems: [SwipeGalleryItem],
        ideaGalleryItems: [IdeaGalleryItem],
        readwiseBooks: [ReadwiseLibraryBook],
        browserPins: [CosmoBrowserPinnedSite] = []
    ) -> UnifiedSearchOutput {
        let normalizedQuery = CommandKSearchMatcher.normalizeQuery(query)
        guard !normalizedQuery.isEmpty else {
            return UnifiedSearchOutput(groupedResults: [], flatResults: [])
        }

        let swipeItemsByUUID = Dictionary(uniqueKeysWithValues: swipeGalleryItems.map { ($0.atomUUID, $0) })
        var includedAtomUUIDs = Set<String>()
        var allResults: [UnifiedSearchResult] = []

        allResults.append(contentsOf: browserPinResults(for: browserPins, normalizedQuery: normalizedQuery))

        for result in hybridResults.prefix(hybridLimit) {
            if result.atomType == .idea { continue }
            includedAtomUUIDs.insert(result.atomUUID)

            if result.atomType == .research, let swipeItem = swipeItemsByUUID[result.atomUUID] {
                allResults.append(swipeResult(for: swipeItem, relevance: max(result.relevance, swipeRelevance(for: swipeItem))))
            } else {
                allResults.append(atomResult(for: result))
            }
        }

        var addedSwipes = 0
        for item in swipeGalleryItems where !includedAtomUUIDs.contains(item.atomUUID) {
            guard CommandKSearchMatcher.matches(normalizedQuery: normalizedQuery, inNormalizedText: item.searchableText) else {
                continue
            }
            allResults.append(swipeResult(for: item, relevance: swipeRelevance(for: item)))
            includedAtomUUIDs.insert(item.atomUUID)
            addedSwipes += 1
            if addedSwipes >= swipeLimit { break }
        }

        var addedIdeas = 0
        for item in ideaGalleryItems where !includedAtomUUIDs.contains(item.atomUUID) {
            guard IdeasTab.matchesSearch(item, query: query) else { continue }
            allResults.append(ideaResult(for: item))
            includedAtomUUIDs.insert(item.atomUUID)
            addedIdeas += 1
            if addedIdeas >= ideaLimit { break }
        }

        var addedBooks = 0
        for book in readwiseBooks where ReadwiseBookStore.matchesSearch(book, query: query) {
            let matchingHighlight = book.highlights.first {
                ReadwiseLibraryTab.matchesSearch($0, query: query)
            }
            let snippet = matchingHighlight?.text.prefix(120).description
                ?? "\(book.numHighlights) highlight\(book.numHighlights == 1 ? "" : "s")"

            allResults.append(UnifiedSearchResult(
                id: "readwise-\(book.id)",
                source: .readwise,
                resultKind: .readwise,
                title: "\(book.title)\(book.author.map { " — \($0)" } ?? "")",
                subtitle: book.category.displayName,
                snippet: snippet,
                icon: book.category.icon,
                accentColor: DS.entityReadwise,
                relevance: matchingHighlight != nil ? 0.5 : 0.35,
                atomUUID: nil,
                atomType: nil,
                thinkspaceId: nil,
                projectUUID: nil,
                projectName: nil,
                thinkspaceNames: [],
                readwiseBookId: book.id
            ))
            addedBooks += 1
            if addedBooks >= readwiseLimit { break }
        }

        let groupedResults = groupedResults(from: allResults)
        return UnifiedSearchOutput(
            groupedResults: groupedResults,
            flatResults: groupedResults.flatMap(\.results)
        )
    }

    static func buildCardItems(
        flatResults: [UnifiedSearchResult],
        libraryItemsByID: [String: LibraryItem],
        swipeItemsByUUID: [String: SwipeGalleryItem]
    ) -> [UnifiedCardItem] {
        flatResults.compactMap { result in
            switch result.source {
            case .swipes:
                guard let uuid = result.atomUUID, let item = swipeItemsByUUID[uuid] else { return nil }
                return .swipe(item)
            case .readwise:
                return .readwise(result)
            case .browser:
                return nil
            case .atoms, .ideas:
                guard let key = result.libraryLookupKey,
                      let item = libraryItemsByID[key] else { return nil }
                return .library(item)
            }
        }
    }

    static func regroup(_ results: [UnifiedSearchResult]) -> UnifiedSearchOutput {
        let groupedResults = groupedResults(from: results)
        return UnifiedSearchOutput(
            groupedResults: groupedResults,
            flatResults: groupedResults.flatMap(\.results)
        )
    }

    private static func groupedResults(from allResults: [UnifiedSearchResult]) -> [(source: UnifiedSearchSource, results: [UnifiedSearchResult])] {
        var grouped: [UnifiedSearchSource: [UnifiedSearchResult]] = [:]
        for result in allResults {
            grouped[result.source, default: []].append(result)
        }

        for key in grouped.keys {
            grouped[key]?.sort { $0.relevance > $1.relevance }
        }

        return grouped.sorted { lhs, rhs in
            let lhsBest = lhs.value.first?.relevance ?? 0
            let rhsBest = rhs.value.first?.relevance ?? 0
            return lhsBest > rhsBest
        }.map { (source: $0.key, results: $0.value) }
    }

    private static func browserPinResults(
        for pins: [CosmoBrowserPinnedSite],
        normalizedQuery: String
    ) -> [UnifiedSearchResult] {
        pins.compactMap { pin -> UnifiedSearchResult? in
            let normalizedText = CommandKSearchMatcher.normalize(pin.searchableText)
            guard CommandKSearchMatcher.matches(normalizedQuery: normalizedQuery, inNormalizedText: normalizedText) else {
                return nil
            }

            return UnifiedSearchResult(
                id: "browser-pin-\(pin.id.uuidString)",
                source: .browser,
                resultKind: .browserPin,
                title: "Open this page in browser",
                subtitle: "\(pin.displayName) · \(pin.host)",
                snippet: pin.url.absoluteString,
                icon: "safari",
                accentColor: DS.entityResearch,
                relevance: browserPinRelevance(for: pin, normalizedQuery: normalizedQuery),
                atomUUID: nil,
                atomType: nil,
                thinkspaceId: nil,
                projectUUID: nil,
                projectName: nil,
                thinkspaceNames: [],
                readwiseBookId: nil,
                browserURL: pin.url,
                browserTitle: pin.displayName
            )
        }
        .sorted { $0.relevance > $1.relevance }
        .prefix(browserPinLimit)
        .map { $0 }
    }

    private static func browserPinRelevance(for pin: CosmoBrowserPinnedSite, normalizedQuery: String) -> Double {
        let normalizedName = CommandKSearchMatcher.normalize(pin.displayName)
        let normalizedTitle = CommandKSearchMatcher.normalize(pin.title)
        let normalizedHost = CommandKSearchMatcher.normalize(pin.host)

        if normalizedName == normalizedQuery {
            return 1.4
        }
        if normalizedName.hasPrefix(normalizedQuery) {
            return 1.32
        }
        if normalizedName.contains(normalizedQuery) {
            return 1.22
        }
        if normalizedTitle.hasPrefix(normalizedQuery) {
            return 1.12
        }
        if normalizedHost.contains(normalizedQuery) {
            return 1.08
        }
        return 1.02
    }

    private static func atomResult(for result: RankedResult) -> UnifiedSearchResult {
        UnifiedSearchResult(
            id: "atom-\(result.atomUUID)",
            source: .atoms,
            resultKind: .atom,
            title: result.title,
            subtitle: result.atomType.displayName,
            snippet: result.snippet,
            icon: result.atomType.iconName,
            accentColor: accentColor(for: result.atomType),
            relevance: result.relevance,
            atomUUID: result.atomUUID,
            atomType: result.atomType,
            thinkspaceId: nil,
            projectUUID: nil,
            projectName: nil,
            thinkspaceNames: [],
            readwiseBookId: nil
        )
    }

    private static func swipeResult(for item: SwipeGalleryItem, relevance: Double) -> UnifiedSearchResult {
        let scoreText = item.hookScore.map { "Score: \(Int($0))" }
        return UnifiedSearchResult(
            id: "swipe-\(item.atomUUID)",
            source: .swipes,
            resultKind: .atom,
            title: item.title,
            subtitle: [item.platformName, scoreText].compactMap { $0 }.joined(separator: " · "),
            snippet: item.hookText,
            icon: "bolt.fill",
            accentColor: DS.entitySwipe,
            relevance: relevance,
            atomUUID: item.atomUUID,
            atomType: .research,
            thinkspaceId: nil,
            projectUUID: nil,
            projectName: nil,
            thinkspaceNames: [],
            readwiseBookId: nil
        )
    }

    private static func ideaResult(for item: IdeaGalleryItem) -> UnifiedSearchResult {
        UnifiedSearchResult(
            id: "idea-\(item.atomUUID)",
            source: .ideas,
            resultKind: .atom,
            title: item.title,
            subtitle: [item.status.displayName, item.contentFormat?.displayName].compactMap { $0 }.joined(separator: " · "),
            snippet: item.body?.prefix(120).description,
            icon: "lightbulb.fill",
            accentColor: DS.entityIdea,
            relevance: item.insightScore ?? 0.4,
            atomUUID: item.atomUUID,
            atomType: .idea,
            thinkspaceId: nil,
            projectUUID: nil,
            projectName: nil,
            thinkspaceNames: [],
            readwiseBookId: nil
        )
    }

    static func thinkspaceResult(for item: LibraryItem, relevance: Double) -> UnifiedSearchResult {
        UnifiedSearchResult(
            id: "thinkspace-\(item.uuid)",
            source: .atoms,
            resultKind: .thinkspace,
            title: item.title,
            subtitle: item.projectName ?? item.typeName,
            snippet: item.preview,
            icon: item.icon,
            accentColor: item.color,
            relevance: relevance,
            atomUUID: nil,
            atomType: .thinkspace,
            thinkspaceId: item.uuid,
            projectUUID: item.projectUUID,
            projectName: item.projectName,
            thinkspaceNames: item.thinkspaceNames,
            readwiseBookId: nil
        )
    }

    private static func swipeRelevance(for item: SwipeGalleryItem) -> Double {
        (item.hookScore ?? 50) / 100.0
    }
    private static func accentColor(for type: AtomType) -> Color {
        switch type {
        case .idea: return DS.entityIdea
        case .task: return DS.entityTask
        case .research: return DS.entityResearch
        case .content: return DS.entityContent
        case .connection: return DS.entityConnection
        default: return DS.textSecondary
        }
    }
}

// MARK: - CommandKViewModel
/// ViewModel for the Command-K overlay
/// Manages query state, results, and constellation visualization
struct CommandKInstantSwipeCapture {
    private let classifier = SwipeURLClassifier()

    func pendingAtom(for url: String, hook: String? = nil) throws -> Atom {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let classification = classifier.classify(trimmed)
        guard classification.isUrl else {
            throw CommandKInstantSwipeCaptureError.invalidURL
        }

        var atom = baseAtom(for: trimmed, classification: classification, hook: hook)
        atom.processingStatus = classification.sourceType == .rawNote ? "complete" : "pending"
        atom.isSwipeFile = true
        atom.updatedAt = ISO8601DateFormatter().string(from: Date())
        return atom
    }

    @MainActor
    func capture(url: String, hook: String? = nil) async throws -> Atom {
        let atom = try pendingAtom(for: url, hook: hook)
        let saved = try await AtomRepository.shared.create(atom)

        NotificationCenter.default.post(
            name: .researchCreated,
            object: nil,
            userInfo: ["research": saved, "uuid": saved.uuid]
        )

        if shouldProcessInBackground(saved) {
            SwipeProcessingService.shared.processSwipeInBackground(uuid: saved.uuid)
        }

        return saved
    }

    private func baseAtom(
        for url: String,
        classification: SwipeURLClassifier.Classification,
        hook: String?
    ) -> Atom {
        switch classification.sourceType {
        case .youtube, .youtubeShort:
            var atom = Research.swipeFromYouTube(
                videoId: classification.contentId ?? UUID().uuidString,
                url: url,
                hook: hook,
                isShort: classification.sourceType == .youtubeShort
            )
            let thumbnailURL = "https://img.youtube.com/vi/\(classification.contentId ?? "")/maxresdefault.jpg"
            if classification.contentId != nil {
                atom.thumbnailUrl = thumbnailURL
                var richContent = atom.richContent ?? ResearchRichContent()
                richContent.thumbnailUrl = thumbnailURL
                atom.setRichContent(richContent)
            }
            return atom

        case .instagram, .instagramReel, .instagramPost, .instagramCarousel:
            return instagramAtom(for: url, classification: classification, hook: hook)

        case .xPost, .twitter:
            return Research.swipeFromXPost(
                tweetId: classification.contentId ?? UUID().uuidString,
                url: url,
                hook: hook
            )

        case .threads:
            return Research.swipeFromThreads(
                threadId: classification.contentId ?? UUID().uuidString,
                url: url,
                hook: hook
            )

        case .loom:
            return Research.newSwipeFile(
                url: url,
                hook: hook,
                sourceType: .loom,
                contentSource: .clipboard
            )

        default:
            return Research.newSwipeFile(
                url: url,
                hook: hook,
                sourceType: .website,
                contentSource: .clipboard
            )
        }
    }

    private func instagramAtom(
        for url: String,
        classification: SwipeURLClassifier.Classification,
        hook: String?
    ) -> Atom {
        let igType: ResearchRichContent.InstagramContentType
        let title: String
        switch classification.sourceType {
        case .instagramReel:
            igType = .reel
            title = "Instagram Reel"
        case .instagramCarousel:
            igType = .carousel
            title = "Instagram Carousel"
        default:
            igType = .post
            title = "Instagram Post"
        }

        var atom = Research.swipeFromInstagram(
            instagramId: classification.contentId ?? UUID().uuidString,
            url: url,
            hook: hook,
            type: igType
        )
        if hook == nil {
            atom.title = title
        }

        var richContent = atom.richContent ?? ResearchRichContent()
        richContent.sourceType = classification.sourceType
        richContent.instagramType = igType.rawValue
        richContent.instagramId = classification.contentId
        if let originalURL = URL(string: url) {
            richContent.instagramData = InstagramData(
                originalURL: originalURL,
                contentType: instagramContentType(for: igType)
            )
        }
        atom.setRichContent(richContent)

        return atom
    }

    private func instagramContentType(
        for type: ResearchRichContent.InstagramContentType
    ) -> InstagramContentType {
        switch type {
        case .reel: return .reel
        case .carousel: return .carousel
        case .post: return .image
        case .story: return .story
        }
    }

    private func shouldProcessInBackground(_ atom: Atom) -> Bool {
        switch atom.richContent?.sourceType {
        case .instagram, .instagramReel, .instagramPost, .instagramCarousel:
            return atom.processingStatus == "pending"
        default:
            return false
        }
    }
}

enum CommandKInstantSwipeCaptureError: LocalizedError {
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Paste a valid URL to capture."
        }
    }
}

@MainActor
public final class CommandKViewModel: ObservableObject {

    // MARK: - Cortex Mode State

    /// Current interaction mode (compact → searchResults → expandedDomain)
    @Published public var cortexMode: CortexMode = .compact

    /// Recent items for compact mode display
    @Published public var recentItems: [RecentDisplayItem] = []

    /// The initial tab passed from MainView (nil = start compact)
    var initialExpandedTab: CommandKTab?

    // MARK: - Published State

    /// Current search query. Live typing is kept non-published so each
    /// keystroke does not invalidate the entire Command-K surface.
    public var query: String = ""

    /// Bumped only when the view model changes the field programmatically.
    @Published public private(set) var querySyncToken: Int = 0

    /// Current search results
    @Published public private(set) var results: [RankedResult] = []

    /// Selected result/node UUID
    @Published public var selectedNodeId: String?

    /// Current search phase
    public private(set) var currentPhase: SearchPhase = .idle

    /// User-visible search feedback that is independent from background search phase.
    @Published public private(set) var searchFeedback: CommandKSearchFeedback = .none

    /// Whether voice input is active
    @Published public var isVoiceActive: Bool = false

    /// Multi-select type filters
    @Published public var selectedTypeFilters: Set<AtomType> = []

    /// Filter counts by type (computed from unfiltered results)
    @Published public private(set) var filterCounts: [AtomType: Int] = [:]

    /// Error message (if any)
    @Published public var errorMessage: String?

    // MARK: - Swipe Gallery State

    /// Swipe gallery items loaded from research atoms
    @Published public var swipeGalleryItems: [SwipeGalleryItem] = []

    /// Current grouping mode for swipe gallery
    @Published public var swipeGrouping: SwipeGrouping = .narrativeStyle

    /// Current sort mode for swipe gallery
    @Published public var swipeSortMode: SwipeSortMode = .recent

    /// Platform filter for swipe gallery (nil = all)
    @Published public var swipePlatformFilter: String?

    /// Hook type filter for swipe gallery (nil = all)
    @Published public var swipeHookTypeFilter: SwipeHookType?

    /// Narrative style filters for swipe gallery (multi-select)
    @Published var swipeNarrativeFilters: Set<NarrativeStyle> = []

    /// Content format filters for swipe gallery (multi-select)
    @Published var swipeContentFormatFilters: Set<ContentFormat> = []

    /// Niche filter for swipe gallery (nil = all)
    @Published var swipeNicheFilter: String?

    /// Creator filter for swipe gallery (nil = all)
    @Published var swipeCreatorFilter: String?

    /// Available niches extracted from swipe gallery items
    @Published var availableNiches: [String] = []

    /// Available creators extracted from swipe gallery items
    @Published var availableCreators: [(name: String, uuid: String)] = []

    /// Creator search query for autocomplete
    @Published var creatorSearchQuery: String = ""

    /// Whether swipe gallery has been loaded
    private var swipeGalleryLoaded = false

    /// Cached filtered swipes — recomputed only when filter inputs change
    @Published public private(set) var cachedFilteredSwipes: [SwipeGalleryItem] = []

    /// Cached clustered sections — recomputed from cachedFilteredSwipes
    @Published public private(set) var cachedClusteredSections: [FormatSection] = []

    /// View mode for swipe gallery: clustered folders or flat grid
    @Published var swipeViewMode: SwipeViewMode = .clustered

    /// Search query passed from SwipeGalleryTab for filtering
    @Published var swipeSearchQuery: String = ""

    /// Expansion state for Layer 1 format group sections
    @Published var expandedFormatGroups: Set<String> = Set(FormatGroup.allCases.map(\.rawValue))

    /// Expansion state for Layer 2 narrative clusters (collapsed by default)
    @Published var expandedClusters: Set<String> = []

    /// Precomputed swipe facets used by the command menu chrome.
    @Published private(set) var swipeFacetSummary: CommandKSwipeFacetSummary = .empty

    // MARK: - Multi-Select State

    /// UUIDs of cards selected via Shift+Click across gallery tabs
    @Published var selectedUUIDs: Set<String> = []

    /// Whether multi-select mode is active (at least one card selected)
    var isMultiSelectActive: Bool { !selectedUUIDs.isEmpty }

    /// Toggle a card's selection state (Shift+Click)
    func toggleSelection(_ uuid: String) {
        if selectedUUIDs.contains(uuid) {
            selectedUUIDs.remove(uuid)
        } else {
            selectedUUIDs.insert(uuid)
        }
    }

    /// Clear all card selections
    func clearSelection() {
        selectedUUIDs.removeAll()
    }

    // MARK: - Unified Search State

    /// Whether unified cross-library search is active (query is non-empty)
    @Published var isUnifiedSearchActive: Bool = false

    /// Grouped unified results by source
    @Published var unifiedGroupedResults: [(source: UnifiedSearchSource, results: [UnifiedSearchResult])] = []

    /// Flat ordered list for keyboard navigation across all unified groups
    @Published var unifiedFlatResults: [UnifiedSearchResult] = []

    /// Selected Readwise book ID for navigation from unified results
    @Published var selectedReadwiseBookId: Int?

    /// Card items for masonry grid display of unified search results
    @Published var unifiedCardItems: [UnifiedCardItem] = []

    /// Library items keyed by lookup key — used to render Database section with real library previews
    @Published var unifiedLibraryItemsByID: [String: LibraryItem] = [:]

    // MARK: - Idea Gallery State

    /// Idea gallery items loaded from idea atoms
    @Published var ideaGalleryItems: [IdeaGalleryItem] = []

    /// Whether idea gallery has been loaded
    private var ideaGalleryLoaded = false

    /// Lightweight counts for domains whose full content has not been loaded yet.
    @Published private(set) var swipeTotalCount: Int = 0
    @Published private(set) var ideaTotalCount: Int = 0

    /// Cached domain counts and masthead previews. Building this in `body` is too expensive.
    @Published private(set) var domainPresentation: CommandKDomainPresentation = .empty

    // MARK: - Configuration

    /// Debounce delay for search queries. Keep this close to a frame so local command rows feel instant.
    private let searchDebounce: TimeInterval = 0.03

    /// Delay only the expensive semantic search. Local indexed results still publish immediately.
    private let semanticSearchDelayNanoseconds: UInt64 = 120_000_000

    /// Maximum results to display
    private let maxResults = 25

    /// Whether we're showing recents (empty query)
    @Published var isShowingRecents: Bool = false

    /// Whether AI re-ranking has been applied
    @Published var isAIRanked: Bool = false

    /// Grouped results by atom type (ordered by best score)
    @Published var groupedResults: [(type: AtomType, results: [RankedResult])] = []

    /// Flat ordered list for keyboard navigation (across groups)
    @Published var flatNavigableResults: [RankedResult] = []

    /// Currently selected index in flatNavigableResults for keyboard nav
    @Published var selectedResultIndex: Int = -1

    /// Flat ordered list for keyboard navigation in expanded domain rail mode.
    @Published private(set) var expandedDomainSelectionIDs: [String] = []
    private var expandedDomainOpenTargets: [String: CommandKDomainOpenTarget] = [:]

    /// Active #type prefix filter parsed from query
    @Published var activeTypePrefix: AtomType? = nil

    /// Top fast action parsed from the current query, shown before search results.
    @Published var primaryAction: CommandKAction? = nil

    /// Saved quicklinks and user commands that match the current query.
    @Published var userCommandRows: [CommandKUserCommandRow] = []

    /// Whether a fast action is currently executing.
    @Published var isExecutingAction: Bool = false

    /// Inline status for the action preview row.
    @Published var actionStatusMessage: String? = nil

    private var executablePrimaryAction: CommandKAction? = nil

    var activeCommandAction: CommandKAction? {
        if let primaryAction,
           selectedNodeId == nil || selectedNodeId == primaryAction.id {
            return primaryAction
        }
        guard let selectedNodeId else { return nil }
        return userCommandRows.first { $0.id == selectedNodeId }?.action
    }

    private func setPrimaryAction(_ action: CommandKAction?) {
        executablePrimaryAction = action
        guard shouldPublishPrimaryActionUpdate(from: primaryAction, to: action) else {
            return
        }
        primaryAction = action
    }

    private func shouldPublishPrimaryActionUpdate(
        from current: CommandKAction?,
        to next: CommandKAction?
    ) -> Bool {
        guard current != next else { return false }
        guard let current, let next else { return true }
        if current.isStableScopedIdeaPreview(of: next),
           current.isExecutable == next.isExecutable {
            return false
        }
        return true
    }

    private func setActionStatusMessage(_ message: String?) {
        if actionStatusMessage != message {
            actionStatusMessage = message
        }
    }

    private func setUserCommandRows(_ rows: [CommandKUserCommandRow]) {
        if userCommandRows != rows {
            userCommandRows = rows
        }
    }

    private func setSearchFeedback(_ feedback: CommandKSearchFeedback) {
        if searchFeedback != feedback {
            searchFeedback = feedback
        }
    }

    private func refreshSearchFeedback(for query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setSearchFeedback(.none)
            return
        }

        let hasVisibleMatches =
            primaryAction != nil ||
            CommandKActionParser.parse(trimmed) != nil ||
            !userCommandRows.isEmpty ||
            unifiedGroupedResults.contains { !$0.results.isEmpty } ||
            !unifiedFlatResults.isEmpty

        setSearchFeedback(hasVisibleMatches ? .none : .empty(query: trimmed))
    }

    private func setCurrentPhase(_ phase: SearchPhase) {
        if currentPhase != phase {
            currentPhase = phase
        }
    }

    #if DEBUG
    func testingSetSearchFeedback(_ feedback: CommandKSearchFeedback) {
        setSearchFeedback(feedback)
    }

    func testingRefreshSearchFeedback(for query: String) {
        refreshSearchFeedback(for: query)
    }

    func testingSetSearchPhase(_ phase: SearchPhase) {
        setCurrentPhase(phase)
    }

    func testingApplyUnfilteredResults(_ rankedResults: [RankedResult]) {
        unfilteredResults = rankedResults
        applyFiltersToResults()
    }
    #endif

    private func setUnifiedSearchResults(
        active: Bool,
        grouped: [(source: UnifiedSearchSource, results: [UnifiedSearchResult])],
        flat: [UnifiedSearchResult],
        cards: [UnifiedCardItem]
    ) {
        if isUnifiedSearchActive != active {
            isUnifiedSearchActive = active
        }
        if unifiedGroupSignature(unifiedGroupedResults) != unifiedGroupSignature(grouped) {
            unifiedGroupedResults = grouped
        }
        if unifiedResultSignature(unifiedFlatResults) != unifiedResultSignature(flat) {
            unifiedFlatResults = flat
        }
        if unifiedCardSignature(unifiedCardItems) != unifiedCardSignature(cards) {
            unifiedCardItems = cards
        }
    }

    private func unifiedGroupSignature(_ groups: [(source: UnifiedSearchSource, results: [UnifiedSearchResult])]) -> [String] {
        groups.flatMap { group in
            [group.source.rawValue] + unifiedResultSignature(group.results)
        }
    }

    private func unifiedResultSignature(_ results: [UnifiedSearchResult]) -> [String] {
        results.map { result in
            [
                result.selectionID,
                result.id,
                result.source.rawValue,
                result.resultKind.rawValue,
                result.title,
                result.subtitle ?? "",
                result.snippet ?? "",
                result.atomUUID ?? "",
                result.thinkspaceId ?? "",
                result.readwiseBookId.map(String.init) ?? "",
                result.browserURL?.absoluteString ?? ""
            ].joined(separator: "\u{1F}")
        }
    }

    private func unifiedCardSignature(_ cards: [UnifiedCardItem]) -> [String] {
        cards.map { "\($0.selectionID)\u{1F}\($0.id)" }
    }

    private func unifiedLibrarySignature(_ items: [String: LibraryItem]) -> [String] {
        items
            .map { key, item in
                [
                    key,
                    item.uuid,
                    item.title,
                    item.typeName,
                    item.relativeDate,
                    item.preview ?? "",
                    item.thumbnailURL ?? "",
                    item.projectUUID ?? "",
                    item.projectName ?? "",
                    item.thinkspaceUUIDs.joined(separator: ","),
                    item.thinkspaceNames.joined(separator: ","),
                    String(item.childCount),
                    String(item.blockCount),
                    String(item.nestedThinkspaceCount)
                ].joined(separator: "\u{1F}")
            }
            .sorted()
    }

    /// Monotonic request token so slower unified searches cannot overwrite newer ones.
    private var unifiedSearchRequestID: Int = 0

    // MARK: - Dependencies

    private let hybridSearch = HybridSearchEngine.shared
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    private var ideaGalleryReloadTask: Task<Void, Never>?
    private var commandKRefreshTask: Task<Void, Never>?
    private let searchPipeline = CommandKSearchPipeline()
    private var searchIndex = CommandKSearchIndex()
    private var searchIndexLoaded = false
    private var instantIndexSearchTask: Task<[RankedResult], Never>?
    private var instantIndexSearchGeneration = 0
    private var searchIndexTask: Task<Void, Never>?
    private var unifiedSearchEnrichmentTask: Task<Void, Never>?
    private var swipeFilterTask: Task<Void, Never>?
    private var queryDebounceTask: Task<Void, Never>?
    private var swipeFilterGeneration = 0
    private var isSurfaceActive = true
    private let userCommandStore: CommandKUserCommandStore
    private let userCommandComposer = CommandKUserCommandSearchComposer()
    private let systemCommandComposer = CommandKSystemCommandComposer()

    /// Unfiltered results for computing filter counts
    private var unfilteredResults: [RankedResult] = []

    // MARK: - Initialization

    public convenience init() {
        self.init(userCommandStore: CommandKUserCommandStore())
    }

    init(userCommandStore: CommandKUserCommandStore) {
        self.userCommandStore = userCommandStore
        setupFilterObserver()
        setupSwipeFilterPipeline()
        setupSwipeRefreshListener()
        setupIdeaRefreshListener()
        setupCommandKRefreshListener()
    }

    public func setSurfaceActive(_ active: Bool) {
        guard isSurfaceActive != active else { return }
        isSurfaceActive = active

        if active {
            prewarmSearchIndexIfNeeded()
        } else {
            searchTask?.cancel()
            queryDebounceTask?.cancel()
            instantIndexSearchTask?.cancel()
            ideaGalleryReloadTask?.cancel()
            commandKRefreshTask?.cancel()
            searchIndexTask?.cancel()
            unifiedSearchEnrichmentTask?.cancel()
            swipeFilterTask?.cancel()
            setCurrentPhase(.idle)
        }
    }

    // MARK: - Query Handling

    public func updateQuery(_ newQuery: String) {
        guard query != newQuery else { return }
        query = newQuery

        queryDebounceTask?.cancel()
        let debounce = UInt64(searchDebounce * 1_000_000_000)
        queryDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: debounce)
            guard let self, !Task.isCancelled, self.isSurfaceActive else { return }
            await self.performSearch(query: newQuery)
        }
    }

    private func setQueryProgrammatically(_ newQuery: String) {
        queryDebounceTask?.cancel()
        guard query != newQuery else {
            querySyncToken &+= 1
            return
        }
        query = newQuery
        querySyncToken &+= 1
    }

    private func setupFilterObserver() {
        $selectedTypeFilters
            .dropFirst()
            .sink { [weak self] _ in
                self?.applyFiltersToResults()
            }
            .store(in: &cancellables)
    }

    private func prewarmSearchIndexIfNeeded(force: Bool = false) {
        guard isSurfaceActive else { return }
        guard force || !searchIndexLoaded else { return }

        searchIndexTask?.cancel()
        searchIndexTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let signpost = CommandKPerformanceInstrumentation.signposter.beginInterval("prewarm-search-index")
            defer {
                CommandKPerformanceInstrumentation.signposter.endInterval("prewarm-search-index", signpost)
            }
            do {
                let atoms = try await AtomRepository.shared.fetchRecent(limit: 10_000)
                guard !Task.isCancelled, self.isSurfaceActive else { return }
                self.searchIndex.replace(atoms: atoms)
                self.searchIndexLoaded = true
            } catch {
                CommandKPerformanceInstrumentation.logger.error("Command-K search index prewarm failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Parse #type prefix from query and return (stripped query, type filter)
    private func parseTypePrefix(_ rawQuery: String) -> (query: String, typeFilter: AtomType?) {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespaces)
        let prefixMap: [String: AtomType] = [
            "#idea": .idea,
            "#task": .task,
            "#swipe": .research,
            "#content": .content,
            "#research": .research,
            "#connection": .connection,
            "#project": .project,
        ]
        for (prefix, type) in prefixMap {
            if trimmed.lowercased().hasPrefix(prefix) {
                let stripped = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                return (stripped, type)
            }
        }
        return (trimmed, nil)
    }

    /// Perform search with current query using HybridSearchEngine
    public func performSearch(query: String) async {
        // Cancel previous search
        searchTask?.cancel()
        instantIndexSearchTask?.cancel()
        instantIndexSearchGeneration &+= 1
        guard isSurfaceActive else { return }
        let requestID = await searchPipeline.nextRequestID()
        let signpost = CommandKPerformanceInstrumentation.signposter.beginInterval("perform-search")
        defer {
            CommandKPerformanceInstrumentation.signposter.endInterval("perform-search", signpost)
        }

        // Parse #type prefix
        let parsed = parseTypePrefix(query)
        let searchQuery = parsed.query
        let prefixType = parsed.typeFilter

        let parsedAction = CommandKActionParser.parse(query)
        setPrimaryAction(parsedAction)
        setActionStatusMessage(nil)
        setSearchFeedback(.none)

        if parsedAction != nil {
            activeTypePrefix = nil
            selectedTypeFilters.removeAll()
        }

        // Update prefix filter state
        if parsedAction == nil, let pt = prefixType {
            activeTypePrefix = pt
            if !selectedTypeFilters.contains(pt) {
                selectedTypeFilters = [pt]
            }
        } else if parsedAction == nil {
            activeTypePrefix = nil
        }

        // Handle empty query - show recents
        if searchQuery.isEmpty && prefixType == nil && parsedAction == nil {
            setSearchFeedback(.none)
            setUnifiedSearchResults(active: false, grouped: [], flat: [], cards: [])
            setUserCommandRows([])
            // Auto-return to compact when query cleared (unless in expanded domain)
            if cortexMode == .searchResults {
                cortexMode = .compact
                await loadRecentsForCompact()
            }
            if case .expandedDomain = cortexMode {
                setCurrentPhase(.idle)
                return
            }
            await showRecents()
            return
        }

        if case .expandedDomain = cortexMode {
            setPrimaryAction(nil)
            setUserCommandRows([])
            results = []
            unfilteredResults = []
            groupedResults = []
            flatNavigableResults = []
            setUnifiedSearchResults(active: false, grouped: [], flat: [], cards: [])
            setCurrentPhase(.idle)
            return
        }

        results = []
        unfilteredResults = []
        groupedResults = []
        flatNavigableResults = []

        let matchedUserCommandRows = prefixType == nil
            ? await loadUserCommandRows(for: searchQuery)
            : []
        guard await searchPipeline.isCurrent(requestID) else { return }
        setUserCommandRows(matchedUserCommandRows)
        updateActiveSearchSelection()

        // Auto-transition to search results when typing in compact mode
        if cortexMode == .compact {
            cortexMode = .searchResults
        }
        // Reset phase so CortexSearchResultsView shows loading, not premature "no results"
        setCurrentPhase(.searching)

        // Skip search in task creation mode
        if isTaskCreationMode {
            results = []
            unfilteredResults = []
            groupedResults = []
            flatNavigableResults = []
            filterCounts = [:]
            setUnifiedSearchResults(active: false, grouped: [], flat: [], cards: [])
            updateActiveSearchSelection()
            isShowingRecents = false
            setCurrentPhase(.idle)
            return
        }

        isShowingRecents = false
        setCurrentPhase(.searching)
        results = []
        unfilteredResults = []
        groupedResults = []
        flatNavigableResults = []
        filterCounts = [:]
        isAIRanked = false

        let effectiveQuery = searchQuery.isEmpty ? "" : searchQuery
        let queryForSearch = effectiveQuery.isEmpty ? query : effectiveQuery
        let maxInstantResults = maxResults
        let searchIndexSnapshot = searchIndex
        let instantSearchGeneration = instantIndexSearchGeneration
        let instantSearchTask = Task.detached(priority: .userInitiated) {
            searchIndexSnapshot.search(queryForSearch, limit: maxInstantResults) {
                Task.isCancelled
            }
        }
        instantIndexSearchTask = instantSearchTask
        let instantIndexedResults = await instantSearchTask.value
        if instantIndexSearchGeneration == instantSearchGeneration {
            instantIndexSearchTask = nil
        }
        guard await searchPipeline.isCurrent(requestID), isSurfaceActive else { return }
        if !instantIndexedResults.isEmpty {
            unfilteredResults = instantIndexedResults
            computeFilterCounts()
            applyFiltersToResults()
            await performInstantUnifiedSearch(query: queryForSearch)
            setCurrentPhase(.instant)
        } else {
            await performInstantUnifiedSearch(
                query: queryForSearch,
                preserveVisibleResultsWhenEmpty: true
            )
        }

        // Check cache first
        let cacheKey = QueryResultCache.cacheKey(
            query: effectiveQuery,
            contextType: FocusContextDetector.shared.currentContext.type.rawValue,
            focusAtomUUID: FocusContextDetector.shared.currentContext.focusAtomUUID,
            typeFilter: nil  // Cache unfiltered, apply filters client-side
        )

        if let cached = await QueryResultCache.shared.get(for: cacheKey) {
            guard await searchPipeline.isCurrent(requestID), isSurfaceActive else { return }
            unfilteredResults = cached
            computeFilterCounts()
            applyFiltersToResults()
            await performInstantUnifiedSearch(query: queryForSearch)
            scheduleUnifiedSearchEnrichment(for: queryForSearch)
            setCurrentPhase(.instant)
            return
        }

        // Perform hybrid search (BM25 + vector similarity)
        let semanticDelay = semanticSearchDelayNanoseconds
        searchTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: semanticDelay)
                try Task.checkCancellation()
                guard isSurfaceActive,
                      await searchPipeline.isCurrent(requestID) else {
                    return
                }

                let hybridSignpost = CommandKPerformanceInstrumentation.signposter.beginInterval("hybrid-search")
                // Use HybridSearchEngine for semantic + keyword search
                let hybridResults = try await hybridSearch.search(
                    query: queryForSearch,
                    context: nil,
                    limit: maxResults * 2,  // Get more for filtering
                    entityTypes: nil  // Don't filter at search level, do it client-side for counts
                )
                CommandKPerformanceInstrumentation.signposter.endInterval("hybrid-search", hybridSignpost)
                try Task.checkCancellation()

                // Convert HybridSearchEngine.SearchResult to RankedResult
                var rankedResults: [RankedResult] = []
                for result in hybridResults {
                    try Task.checkCancellation()
                    // Map EntityType to AtomType
                    let atomType = entityTypeToAtomType(result.entityType)

                    // Use UUID directly from atoms_fts (no legacy ID resolution needed)
                    let atomUUID = result.entityUUID ?? "\(result.entityType.rawValue)-\(result.entityId)"

                    rankedResults.append(RankedResult(
                        atomUUID: atomUUID,
                        atomType: atomType,
                        title: result.title,
                        snippet: result.preview,
                        semanticWeight: result.vectorSimilarity,
                        structuralWeight: result.bm25Score / 25.0,  // Normalize
                        recencyWeight: 0.5,  // Default
                        usageWeight: 0.5,    // Default
                        updatedAt: ISO8601DateFormatter().string(from: Date()),
                        accessCount: 0
                    ))
                }

                // Apply context boosts
                let context = FocusContextDetector.shared.currentContext
                let typeBoosts = FocusContextDetector.shared.getTypeBoosts()
                rankedResults = ContextAwareSearchAdapter.applyContextBoosts(
                    to: rankedResults,
                    context: context,
                    typeBoosts: typeBoosts
                )

                // Sort by combined score
                rankedResults.sort()

                // Update state
                if !Task.isCancelled,
                   isSurfaceActive,
                   await searchPipeline.isCurrent(requestID) {
                    isAIRanked = false
                    unfilteredResults = rankedResults
                    computeFilterCounts()
                    applyFiltersToResults()
                    await performInstantUnifiedSearch(query: queryForSearch)
                    scheduleUnifiedSearchEnrichment(for: queryForSearch)
                    setCurrentPhase(.complete)

                    // Cache unfiltered results
                    await QueryResultCache.shared.set(rankedResults, for: cacheKey)

                    // Fire AI re-ranker asynchronously (results reorder after 1-2s)
                    let queryForReRank = queryForSearch
                    let reRankInputs = rankedResults.prefix(25).map { r in
                        ReRankInput(
                            uuid: r.atomUUID,
                            type: r.atomType.rawValue,
                            title: r.title,
                            preview: r.snippet ?? "",
                            score: r.relevance
                        )
                    }
                    Task { @MainActor in
                        guard !Task.isCancelled,
                              isSurfaceActive,
                              await searchPipeline.isCurrent(requestID) else {
                            return
                        }
                        let rerankSignpost = CommandKPerformanceInstrumentation.signposter.beginInterval("ai-rerank")
                        if let reRanked = await SearchReRanker.shared.reRank(
                            query: queryForReRank,
                            results: reRankInputs
                        ), isSurfaceActive,
                           await searchPipeline.isCurrent(requestID) {
                            // Rebuild results with AI-boosted semantic weights
                            let aiScoreMap = Dictionary(uniqueKeysWithValues: reRanked.map { ($0.uuid, $0.blendedScore) })
                            let reRankedResults = unfilteredResults.map { r in
                                if let aiScore = aiScoreMap[r.atomUUID] {
                                    return RankedResult(
                                        atomUUID: r.atomUUID,
                                        atomType: r.atomType,
                                        title: r.title,
                                        snippet: r.snippet,
                                        semanticWeight: aiScore,
                                        structuralWeight: r.structuralWeight,
                                        recencyWeight: r.recencyWeight,
                                        usageWeight: r.usageWeight,
                                        updatedAt: r.updatedAt,
                                        accessCount: r.accessCount
                                    )
                                }
                                return r
                            }
                            unfilteredResults = reRankedResults.sorted()
                            applyFiltersToResults()
                            await performInstantUnifiedSearch(query: queryForReRank)
                            scheduleUnifiedSearchEnrichment(for: queryForReRank)
                            isAIRanked = true
                        }
                        CommandKPerformanceInstrumentation.signposter.endInterval("ai-rerank", rerankSignpost)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled,
                   isSurfaceActive,
                   await searchPipeline.isCurrent(requestID) {
                    // Fallback to graph-based search if hybrid fails
                    await fallbackToGraphSearch(query: query)
                }
            }
        }
    }

    private func loadUserCommandRows(for query: String) async -> [CommandKUserCommandRow] {
        let primaryActionID = primaryAction?.id
        let systemRows = systemCommandComposer.rows(for: query)
            .filter { $0.action.id != primaryActionID }
        do {
            let quicklinks = try await userCommandStore.searchQuicklinks(query)
            return systemRows + userCommandComposer.rows(for: quicklinks)
        } catch {
            return systemRows
        }
    }

    /// Fallback to direct atom search if HybridSearchEngine fails
    private func fallbackToGraphSearch(query: String) async {
        do {
            // Search atoms directly by title/body containing query
            let atoms = try await AtomRepository.shared.search(query: query, limit: maxResults * 2)

            var rankedResults: [RankedResult] = []
            for atom in atoms {
                rankedResults.append(RankedResult(
                    atomUUID: atom.uuid,
                    atomType: atom.type,
                    title: atom.title ?? "Untitled",
                    snippet: atom.body?.prefix(100).description,
                    semanticWeight: 0.0,
                    structuralWeight: 0.5,
                    recencyWeight: WeightCalculator.recencyWeight(fromISO8601: atom.updatedAt),
                    usageWeight: 0.5,
                    updatedAt: atom.updatedAt,
                    accessCount: 0
                ))
            }

            rankedResults.sort()
            unfilteredResults = rankedResults
            computeFilterCounts()
            applyFiltersToResults()
            setCurrentPhase(.complete)

        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            setCurrentPhase(.idle)
        }
    }

    /// Compute filter counts from unfiltered results
    private func computeFilterCounts() {
        var counts: [AtomType: Int] = [:]
        for result in unfilteredResults {
            counts[result.atomType, default: 0] += 1
        }
        filterCounts = counts
    }

    /// Apply current filters to unfiltered results
    private func applyFiltersToResults() {
        if selectedTypeFilters.isEmpty {
            results = Array(unfilteredResults.prefix(maxResults))
        } else {
            results = Array(unfilteredResults
                .filter { selectedTypeFilters.contains($0.atomType) }
                .prefix(maxResults))
        }
        buildGroupedResults()
    }

    /// Fetch atom UUID from entity type and ID
    private func fetchAtomUUID(entityType: EntityType, entityId: Int64) async -> String? {
        // Try to fetch the atom to get its UUID
        if let atom = try? await AtomRepository.shared.fetch(id: entityId) {
            return atom.uuid
        }
        return nil
    }

    /// Map EntityType to AtomType
    private func entityTypeToAtomType(_ entityType: EntityType) -> AtomType {
        switch entityType {
        case .idea: return .idea
        case .task: return .task
        case .research: return .research
        case .content: return .content
        case .connection: return .connection
        case .project: return .project
        case .journal: return .journalEntry
        case .note: return .idea  // Map notes to ideas
        default: return .idea
        }
    }


    /// Show recent atoms when query is empty
    private func showRecents() async {
        setCurrentPhase(.searching)
        isShowingRecents = true

        do {
            let openedAtoms = try await AtomRepository.shared.fetchRecentlyOpened(limit: 24)
            let opened = openedAtoms.map {
                CommandKRecentComposer.OpenedAtom(
                    atom: $0.atom,
                    openedAt: $0.openedAt,
                    accessCount: $0.accessCount
                )
            }

            var combinedResults = CommandKRecentComposer.rankedResults(
                opened: opened,
                limit: 8
            )
            combinedResults.sort()
            unfilteredResults = combinedResults
            computeFilterCounts()
            applyFiltersToResults()
            setCurrentPhase(.complete)

        } catch {
            errorMessage = "Failed to load recents: \(error.localizedDescription)"
            setCurrentPhase(.idle)
        }
    }

    /// Build grouped results from current filtered results
    private func buildGroupedResults() {
        // Group by atom type
        var groups: [AtomType: [RankedResult]] = [:]
        for result in results {
            groups[result.atomType, default: []].append(result)
        }

        // Sort each group by relevance descending (already sorted, but ensure)
        for key in groups.keys {
            groups[key]?.sort()
        }

        // Order sections by highest-scoring result in each group
        let sorted = groups.sorted { lhs, rhs in
            let lhsBest = lhs.value.first?.relevance ?? 0
            let rhsBest = rhs.value.first?.relevance ?? 0
            return lhsBest > rhsBest
        }

        groupedResults = sorted.map { (type: $0.key, results: $0.value) }

        // Build flat navigable list (for keyboard navigation across groups)
        flatNavigableResults = sorted.flatMap { $0.value }
    }

    /// Quick-create an atom from search query
    func quickCreate(type: AtomType) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let parsed = parseTypePrefix(trimmed)
        let name = parsed.query.isEmpty ? trimmed : parsed.query
        guard !name.isEmpty else { return }

        Task {
            let atom: Atom
            switch type {
            case .idea:
                atom = Atom.new(type: .idea, title: name, body: nil, metadata: nil)
            case .task:
                var taskMeta = TaskMetadata()
                taskMeta.intent = TaskIntent.general.rawValue
                var metadataString: String?
                if let data = try? JSONEncoder().encode(taskMeta),
                   let json = String(data: data, encoding: .utf8) {
                    metadataString = json
                }
                atom = Atom.new(type: .task, title: name, body: nil, metadata: metadataString)
            case .connection:
                atom = Atom.new(type: .connection, title: name, body: nil, metadata: nil)
            default:
                atom = Atom.new(type: type, title: name, body: nil, metadata: nil)
            }

            let _ = try? await AtomRepository.shared.create(atom)
        }

        // Clear query and close
        setQueryProgrammatically("")
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
    }


    // MARK: - Selection

    /// Select a result by UUID
    public func select(uuid: String) {
        selectedNodeId = uuid

        // Record access
        Task {
            try? await NodeGraphEngine.shared.recordAccess(atomUUID: uuid, type: .view)
        }
    }

    func updateExpandedDomainNavigation(items: [CommandKDomainRailItem]) {
        let ids = items.map(\.selectionID)
        expandedDomainSelectionIDs = ids
        expandedDomainOpenTargets = Dictionary(uniqueKeysWithValues: items.map { ($0.selectionID, $0.openTarget) })

        guard case .expandedDomain = cortexMode else { return }
        guard !ids.isEmpty else {
            selectedResultIndex = -1
            selectedNodeId = nil
            return
        }

        if let selectedNodeId, let index = ids.firstIndex(of: selectedNodeId) {
            selectedResultIndex = index
        } else {
            selectedResultIndex = 0
            selectedNodeId = ids[0]
        }
    }

    // MARK: - Task Quick-Create

    /// Whether the current query is a "task:" creation command
    public var isTaskCreationMode: Bool {
        query.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("task:")
    }

    /// Extract task name from "task: [name]" query
    private var taskNameFromQuery: String {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard let colonIndex = trimmed.firstIndex(of: ":") else { return "" }
        let afterColon = trimmed[trimmed.index(after: colonIndex)...]
        return afterColon.trimmingCharacters(in: .whitespaces)
    }

    /// Create a task atom from the "task:" query and close Command-K
    public func createTaskFromQuery() {
        let name = taskNameFromQuery
        guard !name.isEmpty else { return }

        Task {
            var taskMeta = TaskMetadata()
            taskMeta.intent = TaskIntent.general.rawValue

            var metadataString: String?
            if let data = try? JSONEncoder().encode(taskMeta),
               let json = String(data: data, encoding: .utf8) {
                metadataString = json
            }

            let atom = Atom.new(
                type: .task,
                title: name,
                body: nil,
                metadata: metadataString
            )

            let _ = try? await AtomRepository.shared.create(atom)
        }

        // Clear query and close
        setQueryProgrammatically("")
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
    }

    /// Open the selected result in the split-pane column.
    public func openSelectedAsPane() async {
        if let primaryAction,
           selectedNodeId == nil || selectedNodeId == primaryAction.id {
            return
        }

        if let selectedNodeId,
           userCommandRows.contains(where: { $0.id == selectedNodeId }) {
            return
        }

        guard !isTaskCreationMode else { return }

        if let selectedNodeId,
           let item = recentItems.first(where: { $0.id == selectedNodeId }),
           openRecentItemAsPane(item) {
            return
        }

        if case .expandedDomain = cortexMode,
           let selectedNodeId,
           let target = expandedDomainOpenTargets[selectedNodeId] {
            await openExpandedDomainTargetAsPane(target)
            return
        }

        if let result = selectedUnifiedSearchResultForPaneOpen() {
            await openUnifiedSearchResultAsPane(result)
            return
        }

        guard let uuid = selectedNodeId else { return }
        try? await CommandKActionExecutor().execute(.openAsPane(uuid: uuid))
    }

    private func openRecentItemAsPane(_ item: RecentDisplayItem) -> Bool {
        openEntityAsPane(type: item.type, id: item.entityId)
    }

    private func openEntityAsPane(type: AtomType, id: Int64) -> Bool {
        guard id > 0, let entityType = EntityType(rawValue: type.rawValue) else { return false }
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openAsPane,
            object: nil,
            userInfo: ["type": entityType, "id": id]
        )
        closeCommandKAfterPaneOpen()
        return true
    }

    private func openThinkspaceAsPane(id: String) {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openAsPane,
            object: nil,
            userInfo: CosmoNotification.Navigation.ThinkspacePayload(thinkspaceId: id).userInfo
        )
        closeCommandKAfterPaneOpen()
    }

    private func closeCommandKAfterPaneOpen() {
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
    }

    private func selectedUnifiedSearchResultForPaneOpen() -> UnifiedSearchResult? {
        guard isUnifiedSearchActive else { return nil }
        if let selectedNodeId,
           let result = unifiedFlatResults.first(where: { $0.selectionID == selectedNodeId }) {
            return result
        }
        guard selectedResultIndex >= 0, selectedResultIndex < unifiedFlatResults.count else { return nil }
        return unifiedFlatResults[selectedResultIndex]
    }

    private func openUnifiedSearchResultAsPane(_ result: UnifiedSearchResult) async {
        if result.resultKind == .browserPin, let browserURL = result.browserURL {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openWebBrowserPane,
                object: nil,
                userInfo: [
                    "url": browserURL,
                    "title": result.browserTitle ?? result.subtitle ?? "Browser"
                ]
            )
            finishAction()
        } else if result.resultKind == .thinkspace, let thinkspaceId = result.thinkspaceId {
            openThinkspaceAsPane(id: thinkspaceId)
        } else if let atomUUID = result.atomUUID {
            try? await CommandKActionExecutor().execute(.openAsPane(uuid: atomUUID))
        }
    }

    private func openExpandedDomainTargetAsPane(_ target: CommandKDomainOpenTarget) async {
        switch target {
        case .atom(let uuid):
            try? await CommandKActionExecutor().execute(.openAsPane(uuid: uuid))
        case .thinkspace(let id):
            openThinkspaceAsPane(id: id)
        case .readwiseBook:
            break
        }
    }

    /// Open the selected result
    public func openSelected() {
        if let primaryAction,
           selectedNodeId == nil || selectedNodeId == primaryAction.id {
            performPrimaryAction()
            return
        }

        if let selectedNodeId,
           let row = userCommandRows.first(where: { $0.id == selectedNodeId }) {
            performAction(row.action)
            return
        }

        // Intercept task creation mode
        if isTaskCreationMode {
            createTaskFromQuery()
            return
        }

        if case .expandedDomain = cortexMode,
           let selectedNodeId,
           let target = expandedDomainOpenTargets[selectedNodeId] {
            openExpandedDomainTarget(target)
            return
        }

        // Unified search mode
        if isUnifiedSearchActive,
           let selectedNodeId,
           let result = unifiedFlatResults.first(where: { $0.selectionID == selectedNodeId }) {
            openUnifiedSearchResult(result)
            return
        }

        if isUnifiedSearchActive, selectedResultIndex >= 0,
           selectedResultIndex < unifiedFlatResults.count {
            openUnifiedSearchResult(unifiedFlatResults[selectedResultIndex])
            return
        }

        guard let uuid = selectedNodeId else { return }

        // Record access
        Task {
            try? await NodeGraphEngine.shared.recordAccess(atomUUID: uuid, type: .view)
        }

        // Post notification to open
        NotificationCenter.default.post(
            name: CosmoNotification.NodeGraph.openAtomFromCommandK,
            object: nil,
            userInfo: ["atomUUID": uuid]
        )

        // Hide Command-K (keep alive behind focus mode)
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
    }

    private func openUnifiedSearchResult(_ result: UnifiedSearchResult) {
        if result.resultKind == .browserPin, let browserURL = result.browserURL {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openWebBrowserPane,
                object: nil,
                userInfo: [
                    "url": browserURL,
                    "title": result.browserTitle ?? result.subtitle ?? "Browser"
                ]
            )
            finishAction()
        } else if result.resultKind == .thinkspace, let thinkspaceId = result.thinkspaceId {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.navigateToThinkspaceById,
                object: nil,
                userInfo: CosmoNotification.Navigation.ThinkspacePayload(thinkspaceId: thinkspaceId).userInfo
            )
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
        } else if let atomUUID = result.atomUUID {
            Task {
                try? await NodeGraphEngine.shared.recordAccess(atomUUID: atomUUID, type: .view)
            }
            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.openAtomFromCommandK,
                object: nil,
                userInfo: ["atomUUID": atomUUID]
            )
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
        } else if let bookId = result.readwiseBookId {
            selectedReadwiseBookId = bookId
        }
    }

    private func openExpandedDomainTarget(_ target: CommandKDomainOpenTarget) {
        switch target {
        case .atom(let uuid):
            Task {
                try? await NodeGraphEngine.shared.recordAccess(atomUUID: uuid, type: .view)
            }
            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.openAtomFromCommandK,
                object: nil,
                userInfo: ["atomUUID": uuid]
            )
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
        case .thinkspace(let id):
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.navigateToThinkspaceById,
                object: nil,
                userInfo: CosmoNotification.Navigation.ThinkspacePayload(thinkspaceId: id).userInfo
            )
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
        case .readwiseBook(let id):
            selectedReadwiseBookId = id
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
        }
    }

    public func performPrimaryAction() {
        let action = executablePrimaryAction ?? primaryAction
        guard let action, !isExecutingAction else { return }
        performAction(action)
    }

    private func performAction(_ action: CommandKAction) {
        guard !isExecutingAction else { return }
        if !action.isExecutable {
            actionStatusMessage = "Add the missing detail first."
            return
        }

        isExecutingAction = true
        actionStatusMessage = "Working..."

        Task { @MainActor in
            do {
                try await execute(action)
                isExecutingAction = false
            } catch {
                isExecutingAction = false
                actionStatusMessage = error.localizedDescription
            }
        }
    }

    private func execute(_ action: CommandKAction) async throws {
        switch action.kind {
        case .captureSwipe:
            guard let url = action.payload.url else { return }
            _ = try await CommandKInstantSwipeCapture().capture(url: url, hook: action.payload.hook)
            finishAction()

        case .captureSwipeWithIdea:
            guard let url = action.payload.url else { return }
            var arguments: [String: Any] = ["url": url]
            if let title = action.payload.title { arguments["title"] = title }
            if let clientName = action.payload.clientName { arguments["clientName"] = clientName }
            if let ideaContext = action.payload.ideaContext { arguments["ideaContext"] = ideaContext }
            if let hook = action.payload.hook { arguments["hook"] = hook }
            _ = try await AgentToolExecutor.shared.execute(toolName: "capture_swipe_with_idea", arguments: arguments)
            finishAction()

        case .captureLane:
            guard let rawText = action.payload.rawText else { return }
            _ = await TelegramCaptureRouter.shared.routeTelegramCapture(
                text: rawText,
                chatId: "command-k",
                messageId: nil,
                sender: "Command-K"
            )
            finishAction()

        case .createCaptureLane:
            guard let destinationName = action.payload.destinationName else { return }
            _ = try await CaptureDestinationRepository.shared.createLane(named: destinationName)
            finishAction()

        case .createIdea:
            let title = action.payload.title ?? action.payload.body ?? ""
            if let clientName = action.payload.clientName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !clientName.isEmpty {
                try await captureScopedIdea(title: title, body: action.payload.body, clientName: clientName)
                finishScopedIdeaCapture()
            } else {
                _ = try await AgentToolExecutor.shared.execute(toolName: "create_idea", arguments: ["title": title])
                finishAction()
            }

        case .createTask:
            let title = action.payload.title ?? action.payload.body ?? ""
            _ = try await AgentToolExecutor.shared.execute(toolName: "create_task", arguments: ["title": title])
            finishAction()

        case .captureResearch:
            let title = action.payload.title ?? action.payload.body ?? action.payload.url ?? "Research"
            var arguments: [String: Any] = ["title": title]
            if let url = action.payload.url { arguments["url"] = url }
            if let body = action.payload.body { arguments["body"] = body }
            _ = try await AgentToolExecutor.shared.execute(toolName: "capture_research", arguments: arguments)
            finishAction()

        case .createContent:
            let title = action.payload.title ?? action.payload.body ?? ""
            _ = try await AgentToolExecutor.shared.execute(toolName: "create_content", arguments: ["title": title])
            finishAction()

        case .createThinkspace:
            let title = action.payload.title ?? action.payload.body ?? ""
            _ = try await AgentToolExecutor.shared.execute(toolName: "create_thinkspace", arguments: ["title": title])
            finishAction()

        case .navigateCommandCenter:
            NotificationCenter.default.post(name: CosmoNotification.Navigation.navigateToCommandCenter, object: nil)
            finishAction()

        case .navigateLastThinkspace:
            NotificationCenter.default.post(
                name: .voiceNavigationRequested,
                object: nil,
                userInfo: ["destination": "thinkspace"]
            )
            finishAction()

        case .openBrowser:
            let queryText = action.payload.queryText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let targetURL = action.payload.url.flatMap(URL.init(string:))
                ?? queryText.flatMap(CosmoBrowserURLResolver.resolve)
                ?? CosmoBrowserURLResolver.defaultHomeURL
            let title: String
            if let queryText, !queryText.isEmpty {
                title = "Search: \(queryText)"
            } else {
                title = "Browser"
            }
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openWebBrowserPane,
                object: nil,
                userInfo: [
                    "url": targetURL,
                    "title": title
                ]
            )
            finishAction()

        case .openDomain:
            if let domain = action.payload.domain,
               let tab = CommandKTab(rawValue: domain) {
                transitionToExpanded(tab)
                setQueryProgrammatically("")
                setPrimaryAction(nil)
                actionStatusMessage = nil
            }

        case .openAtom:
            guard let uuid = action.payload.atomUUID else { return }
            Task {
                try? await NodeGraphEngine.shared.recordAccess(atomUUID: uuid, type: .view)
            }
            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.openAtomFromCommandK,
                object: nil,
                userInfo: ["atomUUID": uuid]
            )
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
            finishAction()

        case .openThinkspace:
            guard let thinkspaceID = action.payload.thinkspaceID else { return }
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.navigateToThinkspaceById,
                object: nil,
                userInfo: CosmoNotification.Navigation.ThinkspacePayload(thinkspaceId: thinkspaceID).userInfo
            )
            finishAction()

        case .savedSearch:
            guard let savedQuery = action.payload.queryText else { return }
            setPrimaryAction(nil)
            actionStatusMessage = nil
            setQueryProgrammatically(savedQuery)
            await performSearch(query: savedQuery)

        case .openApp:
            guard let appName = action.payload.title else { return }
            try openApplication(named: appName)
            finishAction()

        case .openCosmoPane:
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openCosmoWindowPane,
                object: nil
            )
            finishAction()

        case .openCosmoWindow:
            CosmoWindowPanelController.shared.show()
            finishAction()

        case .askCosmo:
            guard let body = action.payload.body else { return }
            CosmoWindowPanelController.shared.show()
            await CosmoWindowViewModel.shared.sendMessage(body)
            finishAction()
        }
    }

    private func openApplication(named appName: String) throws {
        let workspace = NSWorkspace.shared
        let normalizedName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return }

        let searchRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications", isDirectory: true)
        ]

        for root in searchRoots {
            let directURL = root.appendingPathComponent("\(normalizedName).app", isDirectory: true)
            if FileManager.default.fileExists(atPath: directURL.path) {
                workspace.openApplication(at: directURL, configuration: NSWorkspace.OpenConfiguration())
                return
            }
        }

        for root in searchRoots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let candidate as URL in enumerator where candidate.pathExtension == "app" {
                let displayName = candidate.deletingPathExtension().lastPathComponent
                if displayName.localizedCaseInsensitiveContains(normalizedName) {
                    workspace.openApplication(at: candidate, configuration: NSWorkspace.OpenConfiguration())
                    return
                }
            }
        }

        throw CommandKActionExecutionError.appNotFound(normalizedName)
    }

    private func finishAction() {
        actionStatusMessage = nil
        setQueryProgrammatically("")
        setPrimaryAction(nil)
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
    }

    private func finishScopedIdeaCapture() {
        activeTypePrefix = nil
        selectedTypeFilters.removeAll()
        actionStatusMessage = nil
        setQueryProgrammatically("")
        setPrimaryAction(nil)
        userCommandRows = []
        results = []
        unfilteredResults = []
        groupedResults = []
        flatNavigableResults = []
        filterCounts = [:]
        isUnifiedSearchActive = false
        unifiedGroupedResults = []
        unifiedFlatResults = []
        unifiedCardItems = []
        selectedReadwiseBookId = nil
        isShowingRecents = false
        setCurrentPhase(.idle)

        transitionToExpanded(.ideas, loadDataImmediately: false)
    }

    // MARK: - Cortex Mode Transitions

    /// Transition to expanded domain view for a specific tab
    public func transitionToExpanded(_ tab: CommandKTab, loadDataImmediately: Bool = true) {
        cortexMode = .expandedDomain(tab)
        selectedResultIndex = -1
        selectedNodeId = nil
        expandedDomainSelectionIDs = []
        expandedDomainOpenTargets = [:]

        guard loadDataImmediately else { return }
        ensureExpandedDomainDataLoaded(tab)
    }

    public func ensureExpandedDomainDataLoaded(_ tab: CommandKTab) {
        // Ensure tab data is loaded
        switch tab {
        case .swipeGallery:
            if swipeGalleryItems.isEmpty {
                Task { await loadSwipeGallery() }
            }
        case .ideas:
            if ideaGalleryItems.isEmpty {
                Task { await loadIdeaGallery() }
            }
        default:
            break
        }
    }

    /// Return to compact mode from expanded or search
    public func returnToCompact(refreshRecents: Bool = true) {
        setQueryProgrammatically("")
        cortexMode = .compact
        isUnifiedSearchActive = false
        selectedResultIndex = -1
        selectedNodeId = nil
        expandedDomainSelectionIDs = []
        expandedDomainOpenTargets = [:]
        clearSelection()
        if refreshRecents, isSurfaceActive {
            Task { await loadRecentsForCompact() }
        }
    }

    /// Load recent atoms for compact mode display
    public func loadRecentsForCompact() async {
        guard isSurfaceActive else { return }
        do {
            let openedAtoms = try await AtomRepository.shared.fetchRecentlyOpened(limit: 24)
            let opened = openedAtoms.map {
                CommandKRecentComposer.OpenedAtom(
                    atom: $0.atom,
                    openedAt: $0.openedAt,
                    accessCount: $0.accessCount
                )
            }
            recentItems = CommandKRecentComposer.compose(
                opened: opened,
                limit: 8
            )
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               cortexMode == .compact || cortexMode == .searchResults {
                selectedResultIndex = recentItems.isEmpty ? -1 : 0
                selectedNodeId = recentItems.first?.id
            }
            refreshDomainPresentation()
        } catch {
            recentItems = []
            refreshDomainPresentation()
        }
    }

    /// Open a recent item from compact mode
    public func openRecent(_ item: RecentDisplayItem) {
        Task {
            try? await NodeGraphEngine.shared.recordAccess(atomUUID: item.id, type: .view)
        }
        NotificationCenter.default.post(
            name: CosmoNotification.NodeGraph.openAtomFromCommandK,
            object: nil,
            userInfo: ["atomUUID": item.id]
        )
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
    }

    public func deleteRecent(_ item: RecentDisplayItem) {
        Task {
            try? await AtomRepository.shared.delete(uuid: item.id)
            await MainActor.run {
                recentItems.removeAll { $0.id == item.id }
                refreshDomainPresentation()
            }
        }
    }

    /// Cached total database atom count (loaded on init)
    @Published public var databaseTotalCount: Int = 0

    /// Domain item counts for bubbles
    public var domainCounts: [CommandKTab: Int] {
        domainPresentation.counts
    }

    var headerPreviews: [CommandKTab: CommandKHeaderPreviewContent] {
        domainPresentation.previews
    }

    @Published public var deepDiveTotalCount: Int = 0

    private func refreshDomainPresentation() {
        domainPresentation = CommandKDomainPresentation.build(
            databaseTotalCount: databaseTotalCount,
            swipeTotalCount: swipeTotalCount,
            ideaTotalCount: ideaTotalCount,
            deepDiveTotalCount: deepDiveTotalCount,
            recentItems: recentItems,
            swipeItems: swipeGalleryItems,
            ideaItems: ideaGalleryItems,
            readwiseBooks: ReadwiseBookStore.shared.books
        )
    }

    /// Load the total database atom count for bubble display
    private func loadDatabaseCount() async {
        guard isSurfaceActive else { return }
        do {
            if ThinkspaceManager.shared.thinkspaces.isEmpty {
                await ThinkspaceManager.shared.loadThinkspaces()
            }
            async let atomsRequest = AtomRepository.shared.fetchAll(types: CommandKLibraryScope.databaseAtomTypes)
            async let swipeCountRequest = AtomRepository.shared.countSwipeFiles()
            async let ideaCountRequest = AtomRepository.shared.count(type: .idea)
            async let deepDiveRequest = InquiryRepository.shared.fetchAllDeepDives()
            let (atoms, swipeCount, ideaCount, deepDives) = try await (
                atomsRequest,
                swipeCountRequest,
                ideaCountRequest,
                deepDiveRequest
            )
            databaseTotalCount = CommandKLibraryScope.databaseItemCount(
                atoms: atoms,
                thinkspaceCount: ThinkspaceManager.shared.sidebarThinkspaces.count
            )
            swipeTotalCount = swipeCount
            ideaTotalCount = ideaCount
            deepDiveTotalCount = deepDives.count
            refreshDomainPresentation()
        } catch {
            databaseTotalCount = 0
            swipeTotalCount = 0
            ideaTotalCount = 0
            deepDiveTotalCount = 0
            refreshDomainPresentation()
        }
    }

    /// Initialize cortex mode based on initial tab from MainView
    public func initializeCortexMode() {
        guard isSurfaceActive else { return }
        prewarmSearchIndexIfNeeded()
        if let tab = initialExpandedTab {
            transitionToExpanded(tab, loadDataImmediately: false)
        } else {
            cortexMode = .compact
            Task {
                async let recents: Void = loadRecentsForCompact()
                async let counts: Void = loadDatabaseCount()
                _ = await (recents, counts)
            }
        }
    }

    /// Relative time string from stored access timestamps.
    private static func relativeTimeString(from iso: String) -> String {
        guard let date = date(fromTimestamp: iso) else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 3600 { return "\(max(1, Int(interval / 60)))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        if interval < 604800 { return "\(Int(interval / 86400))d" }
        return "\(Int(interval / 604800))w"
    }

    private static func date(fromTimestamp timestamp: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: timestamp) {
            return date
        }

        let sqliteFormatter = DateFormatter()
        sqliteFormatter.locale = Locale(identifier: "en_US_POSIX")
        sqliteFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        sqliteFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return sqliteFormatter.date(from: timestamp)
    }

    /// Navigate selection up
    public func selectPrevious() {
        if navigateExpandedDomainSelection(delta: -1) { return }
        if navigateRecentSelection(delta: -1) { return }
        if navigateActiveSearchSelection(delta: -1) { return }

        if isUnifiedSearchActive {
            guard !unifiedFlatResults.isEmpty else { return }
            if selectedResultIndex > 0 {
                selectedResultIndex -= 1
            } else {
                selectedResultIndex = unifiedFlatResults.count - 1
            }
            let result = unifiedFlatResults[selectedResultIndex]
            selectedNodeId = result.selectionID
            return
        }

        guard !flatNavigableResults.isEmpty else { return }

        if selectedResultIndex > 0 {
            selectedResultIndex -= 1
        } else {
            selectedResultIndex = flatNavigableResults.count - 1
        }
        selectedNodeId = flatNavigableResults[selectedResultIndex].atomUUID
    }

    /// Navigate selection down
    public func selectNext() {
        if navigateExpandedDomainSelection(delta: 1) { return }
        if navigateRecentSelection(delta: 1) { return }
        if navigateActiveSearchSelection(delta: 1) { return }

        if isUnifiedSearchActive {
            guard !unifiedFlatResults.isEmpty else { return }
            if selectedResultIndex < unifiedFlatResults.count - 1 {
                selectedResultIndex += 1
            } else {
                selectedResultIndex = 0
            }
            let result = unifiedFlatResults[selectedResultIndex]
            selectedNodeId = result.selectionID
            return
        }

        guard !flatNavigableResults.isEmpty else { return }

        if selectedResultIndex < flatNavigableResults.count - 1 {
            selectedResultIndex += 1
        } else {
            selectedResultIndex = 0
        }
        selectedNodeId = flatNavigableResults[selectedResultIndex].atomUUID
    }

    private func navigateExpandedDomainSelection(delta: Int) -> Bool {
        guard case .expandedDomain = cortexMode else { return false }
        return navigateSelection(in: expandedDomainSelectionIDs, delta: delta)
    }

    private func navigateRecentSelection(delta: Int) -> Bool {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              cortexMode == .compact || cortexMode == .searchResults else {
            return false
        }
        return navigateSelection(in: recentItems.map(\.id), delta: delta)
    }

    private func navigateActiveSearchSelection(delta: Int) -> Bool {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              cortexMode == .compact || cortexMode == .searchResults else {
            return false
        }
        return navigateSelection(in: activeSearchSelectionIDs, delta: delta)
    }

    private func navigateSelection(in ids: [String], delta: Int) -> Bool {
        guard !ids.isEmpty else { return false }
        let currentIndex = selectedNodeId.flatMap { ids.firstIndex(of: $0) } ?? selectedResultIndex
        let safeIndex = ids.indices.contains(currentIndex) ? currentIndex : 0
        let nextIndex = (safeIndex + delta + ids.count) % ids.count
        selectedResultIndex = nextIndex
        selectedNodeId = ids[nextIndex]
        return true
    }

    private var activeSearchSelectionIDs: [String] {
        (primaryAction.map { [$0.id] } ?? []) + userCommandRows.map(\.id) + unifiedFlatResults.map(\.selectionID)
    }

    private func updateActiveSearchSelection() {
        let ids = activeSearchSelectionIDs
        guard !ids.isEmpty else {
            if selectedResultIndex != -1 {
                selectedResultIndex = -1
            }
            if selectedNodeId != nil {
                selectedNodeId = nil
            }
            return
        }

        let nextID = ids[0]
        if selectedResultIndex != 0 {
            selectedResultIndex = 0
        }
        if selectedNodeId != nextID {
            selectedNodeId = nextID
        }
    }

    // MARK: - Filter

    /// Toggle a type filter (multi-select)
    public func toggleTypeFilter(_ type: AtomType) {
        if selectedTypeFilters.contains(type) {
            selectedTypeFilters.remove(type)
        } else {
            selectedTypeFilters.insert(type)
        }
    }

    /// Clear all type filters
    public func clearTypeFilters() {
        selectedTypeFilters.removeAll()
    }

    /// Check if a type filter is active
    public func isTypeFilterActive(_ type: AtomType) -> Bool {
        selectedTypeFilters.contains(type)
    }

    /// Available filter types with their display info
    public var filterTypes: [AtomType] {
        [.idea, .task, .research, .content, .connection, .templateInstance]
    }

    /// Get count for a specific filter type
    public func countForType(_ type: AtomType) -> Int {
        filterCounts[type] ?? 0
    }

    /// Total count across all types
    public var totalCount: Int {
        unfilteredResults.count
    }

    // MARK: - Swipe Gallery

    /// Load all swipe file atoms into gallery items
    public func loadSwipeGallery() async {
        guard isSurfaceActive else { return }
        guard !swipeGalleryLoaded else { return }

        do {
            // Fetch all research atoms
            let researchAtoms = try await AtomRepository.shared.search(query: "", types: [.research])

            // Filter to swipe files and convert
            var items: [SwipeGalleryItem] = []
            for atom in researchAtoms {
                if atom.isSwipeFileAtom, let galleryItem = atom.toSwipeGalleryItem() {
                    items.append(galleryItem)
                }
            }

            Self.sortSwipeGalleryItems(&items, by: .recent)

            swipeGalleryItems = items
            swipeTotalCount = items.count
            swipeGalleryLoaded = true

            // Extract available niches
            let niches = Set(items.compactMap(\.niche)).sorted()
            availableNiches = niches

            // Extract available creators from gallery items
            var creatorSet: [String: String] = [:] // name -> atomUUID (deduplicate)
            for item in items {
                if let name = item.creatorName, !name.isEmpty {
                    if creatorSet[name] == nil {
                        creatorSet[name] = item.atomUUID
                    }
                }
            }
            // Also fetch from creator atoms
            if let creators = try? await AtomRepository.shared.fetchCreators() {
                for creator in creators {
                    let name = creator.title ?? "Unknown"
                    creatorSet[name] = creator.uuid
                }
            }
            availableCreators = creatorSet.map { (name: $0.key, uuid: $0.value) }.sorted { $0.name < $1.name }
            refreshDomainPresentation()
        } catch {
            errorMessage = "Failed to load swipe gallery: \(error.localizedDescription)"
        }
    }

    // MARK: - Swipe Filter Pipeline

    /// Sets up Combine pipeline to memoize filtered swipes + clustered sections.
    /// Recomputes only when a filter input changes (debounced 50ms).
    private func setupSwipeFilterPipeline() {
        // Observe all filter inputs and recompute when any change
        Publishers.CombineLatest4(
            $swipeGalleryItems,
            $swipePlatformFilter,
            $swipeHookTypeFilter,
            $swipeSortMode
        )
        .combineLatest(
            Publishers.CombineLatest4(
                $swipeNarrativeFilters,
                $swipeContentFormatFilters,
                $swipeNicheFilter,
                $swipeCreatorFilter
            )
        )
        .combineLatest($swipeSearchQuery)
        .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.recomputeFilteredSwipes()
        }
        .store(in: &cancellables)
    }

    /// Recompute cached filtered swipes and clustered sections from current filter state.
    func recomputeFilteredSwipes() {
        // Capture filter state for background work
        let sourceItems = swipeGalleryItems
        let query = swipeSearchQuery
        let platformFilter = swipePlatformFilter
        let hookFilter = swipeHookTypeFilter
        let narrativeFilters = swipeNarrativeFilters
        let formatFilters = swipeContentFormatFilters
        let nicheFilter = swipeNicheFilter
        let creatorFilter = swipeCreatorFilter
        let sortMode = swipeSortMode

        swipeFilterGeneration += 1
        let generation = swipeFilterGeneration
        swipeFilterTask?.cancel()
        swipeFilterTask = Task.detached(priority: .userInitiated) { [weak self] in
            var items = sourceItems

            if !query.isEmpty {
                let normalizedQuery = CommandKSearchMatcher.normalizeQuery(query)
                items = items.filter { Self.matchesSwipeGallerySearch($0, normalizedQuery: normalizedQuery) }
            }

            if let platformFilter {
                items = items.filter { $0.platformName == platformFilter }
            }

            if let hookFilter {
                items = items.filter { $0.hookType == hookFilter }
            }

            if !narrativeFilters.isEmpty {
                items = items.filter { item in
                    guard let narrative = item.primaryNarrative else { return false }
                    return narrativeFilters.contains(narrative)
                }
            }

            if !formatFilters.isEmpty {
                items = items.filter { item in
                    guard let format = item.swipeContentFormat else { return false }
                    return formatFilters.contains(format)
                }
            }

            if let nicheFilter {
                items = items.filter { $0.niche == nicheFilter }
            }

            if let creatorFilter {
                items = items.filter { $0.creatorName == creatorFilter }
            }

            Self.sortSwipeGalleryItems(&items, by: sortMode)

            let sections = buildClusteredSections(from: items)
            let facetSummary = CommandKSwipeFacetSummary.build(
                allItems: sourceItems,
                filteredItems: items
            )
            let filteredItems = items
            let clusteredSections = sections

            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self, filteredItems, clusteredSections, facetSummary] in
                guard let self,
                      self.swipeFilterGeneration == generation else {
                    return
                }
                self.cachedFilteredSwipes = filteredItems
                self.cachedClusteredSections = clusteredSections
                self.swipeFacetSummary = facetSummary
            }
        }
    }

    nonisolated static func matchesSwipeGallerySearch(_ item: SwipeGalleryItem, query: String) -> Bool {
        matchesSwipeGallerySearch(item, normalizedQuery: CommandKSearchMatcher.normalizeQuery(query))
    }

    nonisolated static func matchesSwipeGallerySearch(_ item: SwipeGalleryItem, normalizedQuery: String) -> Bool {
        CommandKSearchMatcher.matches(normalizedQuery: normalizedQuery, inNormalizedText: item.searchableText)
    }

    nonisolated static func sortSwipeGalleryItems(_ items: inout [SwipeGalleryItem], by sortMode: SwipeSortMode) {
        switch sortMode {
        case .recent:
            items.sort { isNewerSwipe($0, than: $1) }
        case .oldest:
            items.sort { isNewerSwipe($1, than: $0) }
        case .alphabetical:
            items.sort { lhs, rhs in
                let comparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return isNewerSwipe(lhs, than: rhs)
            }
        case .creator:
            items.sort { lhs, rhs in
                let leftCreator = lhs.creatorName ?? lhs.author ?? ""
                let rightCreator = rhs.creatorName ?? rhs.author ?? ""
                let comparison = leftCreator.localizedCaseInsensitiveCompare(rightCreator)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return isNewerSwipe(lhs, than: rhs)
            }
        }
    }

    private nonisolated static func isNewerSwipe(_ lhs: SwipeGalleryItem, than rhs: SwipeGalleryItem) -> Bool {
        if let leftDate = ISO8601.date(from: lhs.createdAt),
           let rightDate = ISO8601.date(from: rhs.createdAt),
           leftDate != rightDate {
            return leftDate > rightDate
        }

        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }

        if lhs.entityId != rhs.entityId {
            return lhs.entityId > rhs.entityId
        }

        return lhs.atomUUID > rhs.atomUUID
    }

    /// Listen for new swipe creation to auto-refresh gallery
    private func setupSwipeRefreshListener() {
        NotificationCenter.default.publisher(for: .researchCreated)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.isSurfaceActive else { return }
                self.swipeGalleryLoaded = false
                Task { await self.loadSwipeGallery() }
            }
            .store(in: &cancellables)
    }

    /// Listen for idea lifecycle changes so the gallery stays in sync while Command-K is open.
    private func setupIdeaRefreshListener() {
        let entityNotifications = [
            CosmoNotification.Entity.created,
            CosmoNotification.Entity.updated,
            CosmoNotification.Entity.deleted,
        ]

        for name in entityNotifications {
            NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    guard let self, self.isSurfaceActive, Self.notificationTargetsIdeaGallery(notification) else { return }
                    Task { @MainActor [weak self] in
                        self?.handleIdeaGalleryNotification(notification)
                    }
                }
                .store(in: &cancellables)
        }

        for name in [Self.legacyIdeaDeletedNotification, Self.legacyIdeaActivatedNotification] {
            NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    guard let self, self.isSurfaceActive else { return }
                    Task { @MainActor [weak self] in
                        self?.handleIdeaGalleryNotification(notification)
                    }
                }
                .store(in: &cancellables)
        }

        NotificationCenter.default.publisher(for: CosmoNotification.Sync.atomsPulled)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard self?.isSurfaceActive == true else { return }
                    self?.scheduleIdeaGalleryReload()
                }
            }
            .store(in: &cancellables)
    }

    /// Keep compact recents, database counts, and the instant search index fresh while Command-K stays open.
    private func setupCommandKRefreshListener() {
        let refreshNotifications: [Notification.Name] = [
            CosmoNotification.Entity.created,
            CosmoNotification.Entity.updated,
            CosmoNotification.Entity.deleted,
            CosmoNotification.Entity.modified,
            CosmoNotification.Sync.atomsPulled,
            .atomsDidChange,
            .researchCreated,
            Self.legacyIdeaDeletedNotification,
            Self.legacyIdeaActivatedNotification,
            Self.legacySwipeDeletedNotification
        ]

        for name in refreshNotifications {
            NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    self?.handleCommandKRefreshNotification(notification)
                }
                .store(in: &cancellables)
        }
    }

    private func handleCommandKRefreshNotification(_ notification: Notification) {
        if notification.name == Self.legacySwipeDeletedNotification,
           let uuid = Self.swipeUUID(from: notification) {
            removeDeletedSwipeFromMemory(uuid: uuid)
        }

        scheduleCommandKRefresh(for: notification)
    }

    private func scheduleCommandKRefresh(for notification: Notification) {
        guard isSurfaceActive else { return }

        if Self.notificationTargetsType(notification, .research)
            || notification.name == .researchCreated
            || notification.name == Self.legacySwipeDeletedNotification {
            swipeGalleryLoaded = false
        }

        commandKRefreshTask?.cancel()
        commandKRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self, !Task.isCancelled, self.isSurfaceActive else { return }

            await self.loadDatabaseCount()
            self.prewarmSearchIndexIfNeeded(force: true)

            let trimmedQuery = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedQuery.isEmpty {
                if self.cortexMode == .compact {
                    await self.loadRecentsForCompact()
                }
            } else {
                await self.performSearch(query: self.query)
            }
        }
    }

    private func removeDeletedSwipeFromMemory(uuid: String) {
        let hadLoadedSwipe = swipeGalleryItems.contains { $0.atomUUID == uuid }
            || cachedFilteredSwipes.contains { $0.atomUUID == uuid }
            || unifiedCardItems.contains { item in
                if case .swipe(let swipe) = item {
                    return swipe.atomUUID == uuid
                }
                return false
            }

        guard hadLoadedSwipe else { return }

        swipeGalleryItems.removeAll { $0.atomUUID == uuid }
        cachedFilteredSwipes.removeAll { $0.atomUUID == uuid }
        cachedClusteredSections = buildClusteredSections(from: cachedFilteredSwipes)
        swipeFacetSummary = CommandKSwipeFacetSummary.build(
            allItems: swipeGalleryItems,
            filteredItems: cachedFilteredSwipes
        )
        swipeTotalCount = swipeGalleryItems.count
        selectedUUIDs.remove(uuid)

        if selectedNodeId == uuid {
            selectedNodeId = nil
        }

        unifiedGroupedResults = unifiedGroupedResults
            .map { group in
                (source: group.source, results: group.results.filter { $0.atomUUID != uuid })
            }
            .filter { !$0.results.isEmpty }
        unifiedFlatResults.removeAll { $0.atomUUID == uuid }
        unifiedCardItems.removeAll { item in
            if case .swipe(let swipe) = item {
                return swipe.atomUUID == uuid
            }
            return false
        }

        refreshDomainPresentation()
    }

    @MainActor
    private func handleIdeaGalleryNotification(_ notification: Notification) {
        guard isSurfaceActive else { return }
        if let uuid = Self.ideaUUID(from: notification),
           Self.notificationRemovesIdeaFromGallery(notification) {
            ideaGalleryItems.removeAll { $0.atomUUID == uuid }
            ideaTotalCount = ideaGalleryItems.count
            refreshDomainPresentation()
        }

        scheduleIdeaGalleryReload()
    }

    @MainActor
    private func scheduleIdeaGalleryReload() {
        guard isSurfaceActive else { return }
        ideaGalleryReloadTask?.cancel()
        ideaGalleryReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self, !Task.isCancelled, self.isSurfaceActive else { return }
            await self.loadIdeaGallery(forceReload: true)
        }
    }

    static let legacyIdeaDeletedNotification = Notification.Name("ideaDeleted")
    static let legacyIdeaActivatedNotification = Notification.Name("ideaActivated")
    static let legacySwipeDeletedNotification = Notification.Name("swipeDeleted")

    static func notificationTargetsIdeaGallery(_ notification: Notification) -> Bool {
        if notification.name == legacyIdeaDeletedNotification || notification.name == legacyIdeaActivatedNotification {
            return true
        }

        if let atom = notification.userInfo?["atom"] as? Atom {
            return atom.type == .idea
        }

        if let type = notification.userInfo?["type"] as? AtomType {
            return type == .idea
        }

        if let type = notification.userInfo?["type"] as? String {
            return type == AtomType.idea.rawValue
        }

        return false
    }

    static func notificationTargetsType(_ notification: Notification, _ atomType: AtomType) -> Bool {
        if let atom = notification.userInfo?["atom"] as? Atom {
            return atom.type == atomType
        }

        if let type = notification.userInfo?["type"] as? AtomType {
            return type == atomType
        }

        if let type = notification.userInfo?["type"] as? String {
            return type == atomType.rawValue
        }

        return false
    }

    static func ideaUUID(from notification: Notification) -> String? {
        if let atom = notification.userInfo?["atom"] as? Atom {
            return atom.uuid
        }

        return notification.userInfo?["uuid"] as? String
    }

    static func swipeUUID(from notification: Notification) -> String? {
        if let atom = notification.userInfo?["atom"] as? Atom, atom.isSwipeFileAtom {
            return atom.uuid
        }

        return notification.userInfo?["uuid"] as? String
    }

    static func notificationRemovesIdeaFromGallery(_ notification: Notification) -> Bool {
        notification.name == legacyIdeaDeletedNotification
            || notification.name == legacyIdeaActivatedNotification
            || notification.name == CosmoNotification.Entity.deleted
    }

    // MARK: - Idea Gallery

    /// Load all idea atoms into gallery items
    /// - Parameter forceReload: If true, reloads even if already loaded (for after quick capture)
    public func loadIdeaGallery(forceReload: Bool = false) async {
        guard isSurfaceActive else { return }
        guard !ideaGalleryLoaded || forceReload else { return }

        do {
            // Fetch all idea atoms (fetchAll avoids LIKE filter that can miss NULL title/body)
            let ideaAtoms = try await AtomRepository.shared.fetchAll(type: .idea)

            // Build a client name cache for display
            var clientNameCache: [String: String] = [:]
            let clientUUIDs = Set(ideaAtoms.compactMap { $0.ideaClientUUID })
            for clientUUID in clientUUIDs {
                if let clientAtom = try? await AtomRepository.shared.fetch(uuid: clientUUID) {
                    clientNameCache[clientUUID] = clientAtom.title ?? "Unknown Client"
                }
            }

            // Convert to gallery items — exclude activated ideas (they're content pieces now)
            let activatedStatuses: Set<IdeaStatus> = [.inProduction, .published, .archived]
            var items: [IdeaGalleryItem] = []
            for atom in ideaAtoms {
                let clientName = atom.ideaClientUUID.flatMap { clientNameCache[$0] }
                if let galleryItem = atom.toIdeaGalleryItem(clientName: clientName),
                   !activatedStatuses.contains(galleryItem.status) {
                    items.append(galleryItem)
                }
            }

            // Sort by updated date descending
            items.sort { $0.updatedAt > $1.updatedAt }

            ideaGalleryItems = items
            ideaTotalCount = items.count
            ideaGalleryLoaded = true
            refreshDomainPresentation()
        } catch {
            errorMessage = "Failed to load idea gallery: \(error.localizedDescription)"
        }
    }

    // MARK: - Idea Quick Actions

    /// Quick-analyze an idea from the gallery card hover bar
    func quickAnalyzeIdea(_ item: IdeaGalleryItem) {
        Task {
            guard let atom = try? await AtomRepository.shared.fetch(uuid: item.atomUUID) else { return }
            let ideaText = [atom.title, atom.body].compactMap { $0 }.joined(separator: "\n")
            let _ = IdeaInsightEngine.shared.quickInsight(ideaText: ideaText)
            await loadIdeaGallery(forceReload: true)
        }
    }

    @discardableResult
    private func captureScopedIdea(title rawTitle: String, body rawBody: String?, clientName rawClientName: String) async throws -> Atom {
        let clientName = rawClientName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client = try await AtomRepository.shared.fuzzyFindClient(query: clientName) else {
            throw CommandKActionExecutionError.clientNotFound(clientName)
        }

        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = rawBody?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ideaTitle = trimmedTitle.isEmpty ? (trimmedBody ?? "") : trimmedTitle
        let ideaBody = (trimmedBody?.isEmpty == false) ? trimmedBody : ideaTitle

        return try await createIdeaForClientAtom(
            title: ideaTitle,
            body: ideaBody,
            clientUUID: client.uuid,
            clientName: client.title ?? clientName,
            captureSource: "command_k"
        )
    }

    @discardableResult
    private func createIdeaForClientAtom(
        title rawTitle: String,
        body rawBody: String?,
        clientUUID: String?,
        clientName: String?,
        captureSource: String? = nil
    ) async throws -> Atom {
        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw CommandKActionExecutionError.missingIdeaText }

        let trimmedBody = rawBody?.trimmingCharacters(in: .whitespacesAndNewlines)
        var atom = Atom.new(
            type: .idea,
            title: trimmedTitle,
            body: trimmedBody?.isEmpty == false ? trimmedBody : nil,
            metadata: nil
        )

        if clientUUID != nil || captureSource != nil {
            atom = atom.withUpdatedIdeaMetadata { meta in
                if let clientUUID {
                    meta.clientUUID = clientUUID
                }
                if let captureSource {
                    meta.captureSource = captureSource
                }
            }
        }

        if let clientUUID {
            atom = atom.addingLink(.ideaToClient(clientUUID))
        }

        let created = try await AtomRepository.shared.create(atom)
        insertCreatedIdeaIntoGallery(created, clientName: clientName)

        if let clientUUID,
           var client = try? await AtomRepository.shared.fetch(uuid: clientUUID) {
            client = client.addingLink(.clientToIdea(created.uuid))
            client.updatedAt = ISO8601DateFormatter().string(from: Date())
            client.localVersion += 1
            _ = try? await AtomRepository.shared.update(client)
        }

        NotificationCenter.default.post(
            name: CosmoNotification.Entity.created,
            object: nil,
            userInfo: ["atom": created, "uuid": created.uuid, "type": "idea"]
        )

        return created
    }

    private func insertCreatedIdeaIntoGallery(_ atom: Atom, clientName: String?) {
        guard let galleryItem = atom.toIdeaGalleryItem(clientName: clientName) else { return }

        ideaGalleryItems.removeAll { $0.atomUUID == galleryItem.atomUUID }
        ideaGalleryItems.insert(galleryItem, at: 0)
        ideaGalleryItems.sort { $0.updatedAt > $1.updatedAt }
        ideaTotalCount = ideaGalleryItems.count
        ideaGalleryLoaded = true
        refreshDomainPresentation()
    }

    /// Create an idea pre-assigned to a client profile (used by board view inline add)
    func createIdeaForClient(title: String, clientUUID: String?) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try await createIdeaForClientAtom(
                title: trimmed,
                body: nil,
                clientUUID: clientUUID,
                clientName: await clientName(for: clientUUID)
            )
        } catch {
            errorMessage = "Failed to capture idea: \(error.localizedDescription)"
            return
        }

        await loadIdeaGallery(forceReload: true)
    }

    private func clientName(for clientUUID: String?) async -> String? {
        guard let clientUUID else { return nil }
        guard let client = try? await AtomRepository.shared.fetch(uuid: clientUUID) else { return nil }
        return client.title
    }

    // MARK: - Unified Search

    static func preloadUnifiedSearchSupportData(
        swipeGalleryLoaded: Bool,
        ideaGalleryLoaded: Bool,
        loadSwipeGallery: @escaping () async -> Void,
        loadIdeaGallery: @escaping () async -> Void
    ) async {
        async let swipeTask: Void = {
            guard !swipeGalleryLoaded else { return }
            await loadSwipeGallery()
        }()
        async let ideaTask: Void = {
            guard !ideaGalleryLoaded else { return }
            await loadIdeaGallery()
        }()
        _ = await (swipeTask, ideaTask)
    }

    /// Ensure swipe and idea galleries are loaded before unified search composes results.
    private func preloadUnifiedSearchSupportData() async {
        await Self.preloadUnifiedSearchSupportData(
            swipeGalleryLoaded: swipeGalleryLoaded,
            ideaGalleryLoaded: ideaGalleryLoaded,
            loadSwipeGallery: { await self.loadSwipeGallery() },
            loadIdeaGallery: { await self.loadIdeaGallery() }
        )
    }

    private func nextUnifiedSearchRequestID() -> Int {
        unifiedSearchRequestID += 1
        return unifiedSearchRequestID
    }

    private func isCurrentUnifiedSearchRequest(_ requestID: Int) -> Bool {
        requestID == unifiedSearchRequestID
    }

    /// Publish a fast unified result set from already-loaded local data.
    private func performInstantUnifiedSearch(
        query: String,
        preserveVisibleResultsWhenEmpty: Bool = false
    ) async {
        await updateUnifiedSearch(
            query: query,
            preloadSupportData: false,
            includeThinkspaces: false,
            preserveVisibleResultsWhenEmpty: preserveVisibleResultsWhenEmpty
        )
    }

    /// Perform unified search across all libraries
    func performUnifiedSearch(query: String) async {
        await updateUnifiedSearch(
            query: query,
            preloadSupportData: false,
            includeThinkspaces: true
        )
        scheduleUnifiedSearchEnrichment(for: query)
    }

    private func scheduleUnifiedSearchEnrichment(for query: String) {
        unifiedSearchEnrichmentTask?.cancel()
        let expectedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !expectedQuery.isEmpty else { return }

        unifiedSearchEnrichmentTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard let self,
                  !Task.isCancelled,
                  self.isSurfaceActive,
                  self.query.trimmingCharacters(in: .whitespaces) == expectedQuery else {
                return
            }

            await self.updateUnifiedSearch(
                query: query,
                preloadSupportData: true,
                includeThinkspaces: true
            )
        }
    }

    private func updateUnifiedSearch(
        query: String,
        preloadSupportData: Bool,
        includeThinkspaces: Bool,
        preserveVisibleResultsWhenEmpty: Bool = false
    ) async {
        guard isSurfaceActive else { return }
        let signpost = CommandKPerformanceInstrumentation.signposter.beginInterval("unified-search")
        defer {
            CommandKPerformanceInstrumentation.signposter.endInterval("unified-search", signpost)
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let requestID = nextUnifiedSearchRequestID()

        guard !trimmed.isEmpty, !isTaskCreationMode else {
            setSearchFeedback(.none)
            setUnifiedSearchResults(active: false, grouped: [], flat: [], cards: [])
            updateActiveSearchSelection()
            return
        }

        // If #prefix is active, don't show unified — let the existing tab filter handle it
        if activeTypePrefix != nil {
            setSearchFeedback(.none)
            setUnifiedSearchResults(active: false, grouped: [], flat: [], cards: [])
            updateActiveSearchSelection()
            return
        }

        if !isUnifiedSearchActive {
            isUnifiedSearchActive = true
        }
        if preloadSupportData {
            await preloadUnifiedSearchSupportData()
        }
        if includeThinkspaces, ThinkspaceManager.shared.thinkspaces.isEmpty {
            await ThinkspaceManager.shared.loadThinkspaces()
        }
        guard isCurrentUnifiedSearchRequest(requestID) else { return }

        let browserPins = await CosmoBrowserStore.shared.allPins()
        guard isCurrentUnifiedSearchRequest(requestID) else { return }

        let output = CommandKUnifiedSearchComposer.buildOutput(
            query: trimmed,
            hybridResults: unfilteredResults,
            swipeGalleryItems: swipeGalleryItems,
            ideaGalleryItems: ideaGalleryItems,
            readwiseBooks: ReadwiseBookStore.shared.books,
            browserPins: browserPins
        )
        guard isCurrentUnifiedSearchRequest(requestID) else { return }

        let projectsByUUID: [String: Atom] = [:]
        let thinkspaceLibraryItems: [LibraryItem]
        let matchingThinkspaceResults: [UnifiedSearchResult]
        if includeThinkspaces {
            thinkspaceLibraryItems = ThinkspaceManager.shared.sidebarThinkspaces.map { thinkspace in
                LibraryItem(
                    thinkspace: thinkspace,
                    project: nil,
                    nestedThinkspaceCount: ThinkspaceManager.shared.childThinkspaces(of: thinkspace.id).count
                )
            }
            matchingThinkspaceResults = thinkspaceLibraryItems
                .filter { matchesUnifiedLibrarySearch($0, query: trimmed) }
                .prefix(8)
                .map { item in
                    CommandKUnifiedSearchComposer.thinkspaceResult(
                        for: item,
                        relevance: thinkspaceRelevance(for: item, query: trimmed)
                    )
                }
        } else {
            thinkspaceLibraryItems = []
            matchingThinkspaceResults = []
        }

        let combinedResults = output.flatResults + matchingThinkspaceResults
        let atomUUIDs = combinedResults.compactMap { result -> String? in
            guard result.resultKind != .thinkspace,
                  result.atomType != .project,
                  result.source != .swipes else { return nil }
            return result.atomUUID
        }
        let thinkspacesByID = includeThinkspaces
            ? Dictionary(uniqueKeysWithValues: ThinkspaceManager.shared.sidebarThinkspaces.map { ($0.id, $0) })
            : [:]
        var libraryItemsByID = await buildUnifiedAtomLibraryItems(
            atomUUIDs: atomUUIDs,
            projectsByUUID: projectsByUUID,
            thinkspacesByID: thinkspacesByID
        )
        for item in thinkspaceLibraryItems {
            libraryItemsByID[item.uuid] = item
        }

        let enrichedResults = combinedResults.map { result in
            enrichUnifiedSearchResult(result, with: result.libraryLookupKey.flatMap { libraryItemsByID[$0] })
        }
        let regrouped = CommandKUnifiedSearchComposer.regroup(enrichedResults)
        guard isCurrentUnifiedSearchRequest(requestID) else { return }

        if preserveVisibleResultsWhenEmpty,
           regrouped.flatResults.isEmpty,
           hasVisibleUnifiedSearchResults {
            setSearchFeedback(.none)
            if !isUnifiedSearchActive {
                isUnifiedSearchActive = true
            }
            return
        }

        if unifiedLibrarySignature(unifiedLibraryItemsByID) != unifiedLibrarySignature(libraryItemsByID) {
            unifiedLibraryItemsByID = libraryItemsByID
        }

        let swipeItemsByUUID = Dictionary(uniqueKeysWithValues: swipeGalleryItems.map { ($0.atomUUID, $0) })
        let cardItems = CommandKUnifiedSearchComposer.buildCardItems(
            flatResults: regrouped.flatResults,
            libraryItemsByID: libraryItemsByID,
            swipeItemsByUUID: swipeItemsByUUID
        )

        setUnifiedSearchResults(
            active: true,
            grouped: regrouped.groupedResults,
            flat: regrouped.flatResults,
            cards: cardItems
        )

        updateActiveSearchSelection()
        refreshSearchFeedback(for: query)
    }

    private var hasVisibleUnifiedSearchResults: Bool {
        !unifiedFlatResults.isEmpty || !unifiedGroupedResults.isEmpty || !unifiedCardItems.isEmpty
    }

    private func buildUnifiedAtomLibraryItems(
        atomUUIDs: [String],
        projectsByUUID: [String: Atom],
        thinkspacesByID: [String: Thinkspace]
    ) async -> [String: LibraryItem] {
        guard !atomUUIDs.isEmpty else { return [:] }

        let atoms = (try? await AtomRepository.shared.fetchBatch(uuids: atomUUIDs)) ?? []
        let memberships = (try? await AtomRepository.shared.fetchThinkspaceMembership(for: atomUUIDs)) ?? [:]

        return atoms.reduce(into: [String: LibraryItem]()) { result, atom in
            guard atom.type != .project else { return }
            let atomThinkspaces = (memberships[atom.uuid] ?? []).compactMap { thinkspacesByID[$0] }
            let project = resolveProject(
                for: atom,
                thinkspaces: atomThinkspaces,
                projectsByUUID: projectsByUUID
            )
            result[atom.uuid] = LibraryItem(
                atom: atom,
                project: project,
                thinkspaces: atomThinkspaces
            )
        }
    }

    private func resolveProject(
        for atom: Atom,
        thinkspaces: [Thinkspace],
        projectsByUUID: [String: Atom]
    ) -> Atom? {
        return nil
    }

    private func matchesUnifiedLibrarySearch(_ item: LibraryItem, query: String) -> Bool {
        CommandKSearchMatcher.matches(query, inAny: [item.title, item.preview, item.typeName, item.provenanceSummary])
    }

    private func thinkspaceRelevance(for item: LibraryItem, query: String) -> Double {
        let normalizedQuery = CommandKSearchMatcher.normalizeQuery(query)
        let normalizedTitle = CommandKSearchMatcher.normalize(item.title)
        if normalizedTitle == normalizedQuery {
            return 0.98
        }
        if normalizedTitle.hasPrefix(normalizedQuery) {
            return 0.82
        }
        return 0.62
    }

    private func enrichUnifiedSearchResult(_ result: UnifiedSearchResult, with item: LibraryItem?) -> UnifiedSearchResult {
        guard let item else { return result }

        let resultKind: UnifiedSearchResultKind
        switch item.kind {
        case .atom:
            resultKind = .atom
        case .project:
            resultKind = .project
        case .thinkspace:
            resultKind = .thinkspace
        }

        return UnifiedSearchResult(
            id: result.id,
            source: result.source,
            resultKind: resultKind,
            title: result.title,
            subtitle: result.subtitle ?? item.typeName,
            snippet: result.snippet ?? item.preview,
            icon: result.icon,
            accentColor: item.color,
            relevance: result.relevance,
            atomUUID: result.atomUUID,
            atomType: result.atomType,
            thinkspaceId: result.thinkspaceId ?? (item.kind == .thinkspace ? item.uuid : nil),
            projectUUID: item.projectUUID,
            projectName: item.projectName,
            thinkspaceNames: item.thinkspaceNames,
            readwiseBookId: result.readwiseBookId
        )
    }

    // MARK: - Cleanup

    /// Clear search state
    public func clear() {
        instantIndexSearchTask?.cancel()
        unifiedSearchEnrichmentTask?.cancel()
        swipeFilterTask?.cancel()
        setQueryProgrammatically("")
        results = []
        unfilteredResults = []
        filterCounts = [:]
        selectedNodeId = nil
        setCurrentPhase(.idle)
        errorMessage = nil
        selectedTypeFilters.removeAll()
        swipeGalleryItems = []
        swipeGalleryLoaded = false
        swipeTotalCount = 0
        swipeFacetSummary = .empty
        swipePlatformFilter = nil
        swipeHookTypeFilter = nil
        swipeNarrativeFilters = []
        swipeContentFormatFilters = []
        swipeNicheFilter = nil
        swipeCreatorFilter = nil
        swipeSortMode = .recent
        selectedUUIDs.removeAll()
        ideaGalleryItems = []
        ideaGalleryLoaded = false
        ideaTotalCount = 0
        isShowingRecents = false
        groupedResults = []
        flatNavigableResults = []
        selectedResultIndex = -1
        activeTypePrefix = nil
        setPrimaryAction(nil)
        isExecutingAction = false
        actionStatusMessage = nil
        isUnifiedSearchActive = false
        unifiedGroupedResults = []
        unifiedFlatResults = []
        selectedReadwiseBookId = nil
        expandedDomainSelectionIDs = []
        expandedDomainOpenTargets = [:]
        domainPresentation = .empty
    }
}

private extension CommandKAction {
    func isStableScopedIdeaPreview(of next: CommandKAction) -> Bool {
        kind == .createIdea &&
        next.kind == .createIdea &&
        scopedIdeaClientName != nil &&
        id == next.id &&
        title == next.title &&
        icon == next.icon
    }
}

// MARK: - Swipe Gallery Enums

/// Grouping mode for the swipe gallery
public enum SwipeGrouping: String, CaseIterable {
    case narrativeStyle
    case contentType
    case hookType
    case platform
    case creator
    case niche
    case recent
    case score

    public var displayName: String {
        switch self {
        case .narrativeStyle: return "Narrative"
        case .contentType: return "Format"
        case .hookType: return "Hook Type"
        case .platform: return "Platform"
        case .creator: return "Creator"
        case .niche: return "Niche"
        case .recent: return "Recent"
        case .score: return "Score"
        }
    }
}

/// Sort mode for the swipe gallery
public enum SwipeSortMode: String, CaseIterable {
    case recent
    case oldest
    case alphabetical
    case creator

    public var displayName: String {
        switch self {
        case .recent: return "Most Recent"
        case .oldest: return "Oldest First"
        case .alphabetical: return "A–Z"
        case .creator: return "By Creator"
        }
    }
}
