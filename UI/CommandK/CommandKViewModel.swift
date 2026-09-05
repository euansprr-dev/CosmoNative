// CosmoOS/UI/CommandK/CommandKViewModel.swift
// ViewModel for Command-K overlay - manages search state and constellation
// Powers the NodeGraph OS Command-K interface
// Phase 4: Multi-select filters, HybridSearchEngine integration, filter counts

import SwiftUI
import Combine
import AppKit
import Observation

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
        case .database: return "Search database…"
        case .swipeGallery: return "Search swipes…"
        case .ideas: return "Search ideas…"
        case .readwise: return "Search library…"
        case .inquiry: return "Search Deep Dives, questions, lexicon…"
        }
    }

    var compactSubtitle: String {
        switch self {
        case .database: return "All objects"
        case .swipeGallery: return "Captures & hooks"
        case .ideas: return "Ideas for your content"
        case .readwise: return "Books & sources"
        case .inquiry: return "Questions & evidence"
        }
    }

    var headerArtworkMode: CommandKHeaderArtworkMode {
        .contentBackedMasthead
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

// The expanded-domain masthead preview system (header personalities,
// preview composer) was deleted July 2026 with the dead masthead shell —
// the presentation now carries only the live per-domain counts.
struct CommandKDomainPresentation: Equatable {
    let counts: [CommandKTab: Int]

    static let empty = CommandKDomainPresentation(
        counts: Dictionary(uniqueKeysWithValues: CommandKTab.allCases.map { ($0, 0) } + [(.inquiry, 0)])
    )

    static func build(
        databaseTotalCount: Int,
        swipeTotalCount: Int,
        ideaTotalCount: Int,
        deepDiveTotalCount: Int,
        swipeItems: [SwipeGalleryItem],
        ideaItems: [IdeaGalleryItem],
        readwiseBooks: [ReadwiseLibraryBook]
    ) -> CommandKDomainPresentation {
        CommandKDomainPresentation(
            counts: [
                .database: databaseTotalCount,
                .swipeGallery: swipeItems.isEmpty ? swipeTotalCount : swipeItems.count,
                .ideas: ideaItems.isEmpty ? ideaTotalCount : ideaItems.count,
                .readwise: readwiseBooks.count,
                .inquiry: deepDiveTotalCount
            ]
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
    /// Known at compose time so the detail pane can render the swipe stage on
    /// the first frame instead of reflowing when the atom fetch lands.
    var isSwipeFile: Bool = false
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
                    // 500 chars fills a 4pt thumbnail page — a full body
                    // (e.g. a video transcript) freezes Text layout.
                    preview: CommandKPreviewExcerpt.clampOptional(
                        atom.body,
                        limit: CommandKPreviewExcerpt.thumbnailLimit
                    ),
                    isSwipeFile: atom.type == .research && (researchMeta?.isSwipeFile ?? false)
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
        if let date = ISO8601.date(from: timestamp) {
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
            // Double quotes are query grammar ("exact phrase"), not content —
            // strip them on BOTH sides so a quoted query still phrase-matches
            // text that happens to contain quotation marks.
            .replacingOccurrences(of: "\"", with: " ")
            .replacingOccurrences(of: "\u{201C}", with: " ")
            .replacingOccurrences(of: "\u{201D}", with: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Normalized contents of explicitly-quoted segments in a raw query.
    /// A quoted segment is a hard requirement: sources that can't satisfy
    /// every phrase must not match at all.
    static func quotedPhrases(in rawQuery: String) -> [String] {
        HybridSearchEngine.parseQueryGrammar(rawQuery).quotedPhrases
            .map { normalize($0) }
            .filter { !$0.isEmpty }
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
        return matches(normalizedQuery: normalizedQuery, inNormalizedText: normalize(value))
    }

    /// Spotlight-style matching: the full phrase matches anywhere, or every
    /// query token matches somewhere in the text regardless of word order.
    static func matches(normalizedQuery: String, inNormalizedText normalizedText: String) -> Bool {
        guard !normalizedQuery.isEmpty, !normalizedText.isEmpty else { return false }
        if normalizedText.contains(normalizedQuery) { return true }
        let queryTokens = normalizedQuery.split(separator: " ")
        guard queryTokens.count > 1 else { return false }
        return queryTokens.allSatisfy { normalizedText.contains($0) }
    }

    static func matches(_ query: String, inAny values: [String?]) -> Bool {
        matches(normalizedQuery: normalizeQuery(query), inAny: values)
    }

    /// Pre-normalized overload — filter loops normalize the query ONCE, not
    /// once per candidate.
    static func matches(normalizedQuery: String, inAny values: [String?]) -> Bool {
        guard !normalizedQuery.isEmpty else { return false }
        if values.contains(where: { matches(normalizedQuery: normalizedQuery, in: $0) }) {
            return true
        }
        // Multi-word queries may span fields (e.g. one token in the title,
        // another in the body), so also match against the joined text.
        return matches(normalizedQuery: normalizedQuery, inNormalizedText: searchableText(from: values))
    }

    /// Lexical tier + match-quality score shared by every Command-K source so
    /// ranking is comparable across atoms, swipes, ideas, and books. The tier
    /// is the primary sort key (keyword evidence first); quality orders
    /// results within a tier. `.semanticOnly` with quality 0 means no match.
    static func lexicalMatch(
        normalizedQuery: String,
        normalizedTitle: String,
        normalizedFullText: String
    ) -> (tier: LexicalTier, quality: Double) {
        guard matches(normalizedQuery: normalizedQuery, inNormalizedText: normalizedFullText) else {
            return (.semanticOnly, 0)
        }
        if normalizedTitle == normalizedQuery { return (.exactTitle, 1.0) }
        if normalizedTitle.hasPrefix(normalizedQuery) { return (.titlePrefix, 0.88) }
        if normalizedTitle.contains(normalizedQuery) { return (.titleMatch, 0.72) }
        let queryTokens = normalizedQuery.split(separator: " ")
        if !queryTokens.isEmpty, queryTokens.allSatisfy({ normalizedTitle.contains($0) }) {
            return (.titleMatch, 0.64)
        }
        // A multi-word query appearing verbatim in the body is "that exact
        // sentence" evidence — stronger than the same words scattered.
        if queryTokens.count > 1, normalizedFullText.contains(normalizedQuery) {
            return (.phraseInBody, 0.55)
        }
        return (.keywordInBody, 0.42)
    }

    /// Match-quality score in 0...1; 0 means no match. Kept for callers that
    /// only need the scalar — the ladder lives in `lexicalMatch`.
    static func matchQuality(
        normalizedQuery: String,
        normalizedTitle: String,
        normalizedFullText: String
    ) -> Double {
        lexicalMatch(
            normalizedQuery: normalizedQuery,
            normalizedTitle: normalizedTitle,
            normalizedFullText: normalizedFullText
        ).quality
    }
}

// MARK: - CommandKHybridResultMapper

/// Maps HybridSearchEngine results into RankedResults, assigning the lexical
/// tier so keyword evidence survives into tier-first ordering.
enum CommandKHybridResultMapper {
    static func rankedResult(
        from result: HybridSearchEngine.SearchResult,
        atomType: AtomType,
        normalizedQuery: String
    ) -> RankedResult {
        RankedResult(
            atomUUID: result.entityUUID ?? "\(result.entityType.rawValue)-\(result.entityId)",
            atomType: atomType,
            title: result.title,
            snippet: result.preview,
            matchedExcerpt: result.matchedExcerpt,
            semanticWeight: result.vectorSimilarity,
            structuralWeight: result.bm25Score / 25.0,  // Normalize
            recencyWeight: result.updatedAt.map(WeightCalculator.recencyWeight(fromISO8601:)) ?? 0.5,
            usageWeight: 0.5,  // No usage data collected yet — constant, ordering-neutral
            lexicalTier: lexicalTier(for: result, normalizedQuery: normalizedQuery),
            updatedAt: result.updatedAt ?? ISO8601.string(from: Date()),
            accessCount: 0
        )
    }

    /// Query-token coverage above which a broad any-term partial still
    /// counts as keyword evidence: misremembering one word of an eight-word
    /// sentence shouldn't demote the hit to the semantic layer.
    static let partialCoverageFloor = 0.7

    static func lexicalTier(
        for result: HybridSearchEngine.SearchResult,
        normalizedQuery: String
    ) -> LexicalTier {
        // Pure-vector results (bm25Score == 0) can carry a chunk field name as
        // their title — no keyword evidence, so never award title tiers.
        guard result.bm25Score > 0 else { return .semanticOnly }
        let (matcherTier, _) = CommandKSearchMatcher.lexicalMatch(
            normalizedQuery: normalizedQuery,
            normalizedTitle: CommandKSearchMatcher.normalize(result.title),
            normalizedFullText: CommandKSearchMatcher.searchableText(
                from: [result.title, result.preview, result.matchedExcerpt]
            )
        )
        // Retrieval-ladder evidence for matches beyond the preview window:
        // FTS5 saw the whole document, the matcher only saw excerpts.
        let ladderTier: LexicalTier
        if result.matchedPhrase {
            ladderTier = .phraseInBody
        } else if result.matchedAllTerms {
            ladderTier = .keywordInBody
        } else if result.termCoverage >= partialCoverageFloor {
            // High-coverage partial (e.g. 7 of 8 terms): keyword evidence,
            // not semantic confetti.
            ladderTier = .keywordInBody
        } else {
            ladderTier = .semanticOnly
        }
        return min(matcherTier, ladderTier)
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
        case .browser: return "Browser Favorites"
        }
    }

    var icon: String {
        switch self {
        case .atoms: return "tray.full.fill"
        case .swipes: return "rectangle.stack.fill"
        case .ideas: return "lightbulb.fill"
        case .readwise: return "books.vertical.fill"
        case .browser: return "bookmark.fill"
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
    /// Verbatim context window around the matched body text. Drives the
    /// excerpt line on body-evidence rows and the match-centered preview;
    /// rebuild sites (enrichment, context boosts) must copy it, same law as
    /// `lexicalTier`.
    let matchedExcerpt: String?
    let icon: String
    let accentColor: Color
    let relevance: Double
    /// Keyword-evidence tier — primary sort key within and across groups.
    let lexicalTier: LexicalTier
    let atomUUID: String?
    let atomType: AtomType?
    let thinkspaceId: String?
    let projectUUID: String?
    let projectName: String?
    let thinkspaceNames: [String]
    let readwiseBookId: Int?
    let browserURL: URL?
    let browserTitle: String?
    /// Display identity for the rail's thumbnail > favicon > chip ladder.
    /// Populated at enrichment from the hydrated LibraryItem (research atoms
    /// wear their captured page); never consulted for open routing — that
    /// gates on `resultKind`. Rebuild sites must copy both, same law as
    /// `matchedExcerpt`/`lexicalTier`.
    let thumbnailURL: String?
    let faviconHost: String?

    init(
        id: String,
        source: UnifiedSearchSource,
        resultKind: UnifiedSearchResultKind,
        title: String,
        subtitle: String?,
        snippet: String?,
        matchedExcerpt: String? = nil,
        icon: String,
        accentColor: Color,
        relevance: Double,
        lexicalTier: LexicalTier = .semanticOnly,
        atomUUID: String?,
        atomType: AtomType?,
        thinkspaceId: String?,
        projectUUID: String?,
        projectName: String?,
        thinkspaceNames: [String],
        readwiseBookId: Int?,
        browserURL: URL? = nil,
        browserTitle: String? = nil,
        thumbnailURL: String? = nil,
        faviconHost: String? = nil
    ) {
        self.id = id
        self.source = source
        self.resultKind = resultKind
        self.title = title
        self.subtitle = subtitle
        self.snippet = snippet
        self.matchedExcerpt = matchedExcerpt
        self.icon = icon
        self.accentColor = accentColor
        self.relevance = relevance
        self.lexicalTier = lexicalTier
        self.atomUUID = atomUUID
        self.atomType = atomType
        self.thinkspaceId = thinkspaceId
        self.projectUUID = projectUUID
        self.projectName = projectName
        self.thinkspaceNames = thinkspaceNames
        self.readwiseBookId = readwiseBookId
        self.browserURL = browserURL
        self.browserTitle = browserTitle
        self.thumbnailURL = thumbnailURL
        self.faviconHost = faviconHost
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

    /// Tier-first ordering shared by within-group sorting and section
    /// ordering: keyword evidence beats relevance across every source.
    static func ranksHigher(_ lhs: UnifiedSearchResult, _ rhs: UnifiedSearchResult) -> Bool {
        if lhs.lexicalTier != rhs.lexicalTier {
            return lhs.lexicalTier < rhs.lexicalTier
        }
        return lhs.relevance > rhs.relevance
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
        let ideaItemsByUUID = Dictionary(uniqueKeysWithValues: ideaGalleryItems.map { ($0.atomUUID, $0) })
        var includedAtomUUIDs = Set<String>()
        var allResults: [UnifiedSearchResult] = []

        allResults.append(contentsOf: browserPinResults(for: browserPins, normalizedQuery: normalizedQuery))

        for result in hybridResults.prefix(hybridLimit) {
            includedAtomUUIDs.insert(result.atomUUID)

            if result.atomType == .idea {
                if let ideaItem = ideaItemsByUUID[result.atomUUID] {
                    let rank = bestRank(
                        (result.lexicalTier, result.relevance),
                        ideaRelevance(for: ideaItem, normalizedQuery: normalizedQuery)
                    )
                    allResults.append(ideaResult(
                        for: ideaItem,
                        relevance: rank.relevance,
                        lexicalTier: rank.tier,
                        matchedExcerpt: result.matchedExcerpt
                    ))
                } else {
                    // Gallery not loaded yet — surface the engine match directly
                    // instead of dropping an exact hit.
                    allResults.append(ideaResult(for: result))
                }
            } else if result.atomType == .research, let swipeItem = swipeItemsByUUID[result.atomUUID] {
                let rank = bestRank(
                    (result.lexicalTier, result.relevance),
                    swipeRelevance(for: swipeItem, normalizedQuery: normalizedQuery)
                )
                allResults.append(swipeResult(for: swipeItem, relevance: rank.relevance, lexicalTier: rank.tier))
            } else {
                allResults.append(atomResult(for: result))
            }
        }

        var addedSwipes = 0
        for item in swipeGalleryItems where !includedAtomUUIDs.contains(item.atomUUID) {
            let (tier, relevance) = swipeRelevance(for: item, normalizedQuery: normalizedQuery)
            guard relevance > 0 else { continue }
            allResults.append(swipeResult(for: item, relevance: relevance, lexicalTier: tier))
            includedAtomUUIDs.insert(item.atomUUID)
            addedSwipes += 1
            if addedSwipes >= swipeLimit { break }
        }

        var addedIdeas = 0
        for item in ideaGalleryItems where !includedAtomUUIDs.contains(item.atomUUID) {
            guard IdeasTab.matchesSearch(item, query: query) else { continue }
            let (tier, relevance) = ideaRelevance(for: item, normalizedQuery: normalizedQuery)
            allResults.append(ideaResult(
                for: item,
                relevance: relevance,
                lexicalTier: tier,
                matchedExcerpt: tier >= .phraseInBody
                    ? CommandKMatchExcerpt.excerpt(from: item.body, query: query)
                    : nil
            ))
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
            let (titleTier, titleQuality) = CommandKSearchMatcher.lexicalMatch(
                normalizedQuery: normalizedQuery,
                normalizedTitle: CommandKSearchMatcher.normalize(book.title),
                normalizedFullText: CommandKSearchMatcher.searchableText(from: [book.title, book.author])
            )
            // The book matched ReadwiseBookStore.matchesSearch, so a
            // non-title match still carries keyword evidence (highlight or
            // metadata) — a within-tier floor, never a cross-tier lift.
            let tier = min(titleTier, .keywordInBody)

            allResults.append(UnifiedSearchResult(
                id: "readwise-\(book.id)",
                source: .readwise,
                resultKind: .readwise,
                title: "\(book.title)\(book.author.map { " — \($0)" } ?? "")",
                subtitle: book.category.displayName,
                snippet: snippet,
                icon: book.category.icon,
                accentColor: DS.entityReadwise,
                relevance: max(titleQuality, matchingHighlight != nil ? 0.5 : 0.35),
                lexicalTier: tier,
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

    /// Spotlight order contract: once a result list has been readable past the
    /// settle window, later pipeline waves (enrichment, background refreshes,
    /// late gallery loads) must not move rows the user can already see — the
    /// row they are about to press Return on has to stay where it is.
    /// Visible rows keep their visible positions while their CONTENT refreshes
    /// from `incoming`; rows and sections that are genuinely new append below
    /// the ones already shown; rows absent from `incoming` drop out.
    static func stabilizeOrder(
        visible: [(source: UnifiedSearchSource, results: [UnifiedSearchResult])],
        incoming: [(source: UnifiedSearchSource, results: [UnifiedSearchResult])]
    ) -> [(source: UnifiedSearchSource, results: [UnifiedSearchResult])] {
        guard !visible.isEmpty else { return incoming }
        var incomingBySource: [UnifiedSearchSource: [UnifiedSearchResult]] = [:]
        for section in incoming {
            incomingBySource[section.source, default: []] += section.results
        }

        var stabilized: [(source: UnifiedSearchSource, results: [UnifiedSearchResult])] = []
        var placedSources = Set<UnifiedSearchSource>()
        for section in visible {
            placedSources.insert(section.source)
            guard let incomingRows = incomingBySource[section.source] else { continue }
            let rows = stabilizeRowOrder(visible: section.results, incoming: incomingRows)
            if !rows.isEmpty {
                stabilized.append((source: section.source, results: rows))
            }
        }
        for section in incoming where !placedSources.contains(section.source) {
            placedSources.insert(section.source)
            if !section.results.isEmpty {
                stabilized.append(section)
            }
        }
        return stabilized
    }

    private static func stabilizeRowOrder(
        visible: [UnifiedSearchResult],
        incoming: [UnifiedSearchResult]
    ) -> [UnifiedSearchResult] {
        // Anchor on selectionID, not id: an idea surfaced from the engine and
        // the same idea rebuilt from its gallery item carry different ids but
        // the same atomUUID, and the row must stay pinned across that swap.
        var incomingByID: [String: UnifiedSearchResult] = [:]
        for row in incoming where incomingByID[row.selectionID] == nil {
            incomingByID[row.selectionID] = row
        }
        var rows: [UnifiedSearchResult] = []
        var placed = Set<String>()
        for row in visible {
            guard placed.insert(row.selectionID).inserted,
                  let fresh = incomingByID[row.selectionID] else { continue }
            rows.append(fresh)
        }
        for row in incoming where placed.insert(row.selectionID).inserted {
            rows.append(row)
        }
        return rows
    }

    private static func groupedResults(from allResults: [UnifiedSearchResult]) -> [(source: UnifiedSearchSource, results: [UnifiedSearchResult])] {
        var grouped: [UnifiedSearchSource: [UnifiedSearchResult]] = [:]
        for result in allResults {
            grouped[result.source, default: []].append(result)
        }

        for key in grouped.keys {
            grouped[key]?.sort(by: UnifiedSearchResult.ranksHigher)
        }

        // Order sections by their best result, tier first — one fuzzy
        // semantic hit must not lift a whole section above keyword matches.
        // On equal tiers the database outranks the swipe file: someone whose
        // query matches their own atoms is almost always looking for those,
        // and swipe-only browsing has its own section. Swipes lead only when
        // their match carries strictly better keyword evidence than anything
        // in the database.
        return grouped.sorted { lhs, rhs in
            guard let lhsBest = lhs.value.first else { return false }
            guard let rhsBest = rhs.value.first else { return true }
            if lhsBest.lexicalTier != rhsBest.lexicalTier {
                return lhsBest.lexicalTier < rhsBest.lexicalTier
            }
            if (lhs.key == .swipes) != (rhs.key == .swipes) {
                return rhs.key == .swipes
            }
            return lhsBest.relevance > rhsBest.relevance
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

            let rank = browserPinRelevance(for: pin, normalizedQuery: normalizedQuery)
            return UnifiedSearchResult(
                id: "browser-pin-\(pin.id.uuidString)",
                source: .browser,
                resultKind: .browserPin,
                title: pin.displayName,
                subtitle: "\(pin.host) · Browser Favorite",
                snippet: pin.url.absoluteString,
                icon: "bookmark.fill",
                accentColor: DS.entityResearch,
                relevance: rank.relevance,
                lexicalTier: rank.tier,
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
        .sorted(by: UnifiedSearchResult.ranksHigher)
        .prefix(browserPinLimit)
        .map { $0 }
    }

    /// Pins score 1.0 within their tier so an exact custom name still wins
    /// ties against atoms — but never jumps a tier on relevance alone.
    private static func browserPinRelevance(
        for pin: CosmoBrowserPinnedSite,
        normalizedQuery: String
    ) -> (tier: LexicalTier, relevance: Double) {
        let normalizedName = CommandKSearchMatcher.normalize(pin.displayName)
        let normalizedTitle = CommandKSearchMatcher.normalize(pin.title)
        let normalizedHost = CommandKSearchMatcher.normalize(pin.host)

        if normalizedName == normalizedQuery {
            return (.exactTitle, 1.0)
        }
        if normalizedName.hasPrefix(normalizedQuery) {
            return (.titlePrefix, 1.0)
        }
        if normalizedName.contains(normalizedQuery) {
            return (.titleMatch, 1.0)
        }
        if normalizedTitle.hasPrefix(normalizedQuery) {
            return (.titlePrefix, 0.9)
        }
        if normalizedHost.contains(normalizedQuery) {
            return (.keywordInBody, 0.8)
        }
        return (.keywordInBody, 0.6)
    }

    private static func atomResult(for result: RankedResult) -> UnifiedSearchResult {
        UnifiedSearchResult(
            id: "atom-\(result.atomUUID)",
            source: .atoms,
            resultKind: .atom,
            title: result.title,
            subtitle: result.atomType.displayName,
            snippet: result.snippet,
            matchedExcerpt: result.matchedExcerpt,
            icon: result.atomType.iconName,
            accentColor: accentColor(for: result.atomType),
            relevance: result.relevance,
            lexicalTier: result.lexicalTier,
            atomUUID: result.atomUUID,
            atomType: result.atomType,
            thinkspaceId: nil,
            projectUUID: nil,
            projectName: nil,
            thinkspaceNames: [],
            readwiseBookId: nil
        )
    }

    private static func swipeResult(
        for item: SwipeGalleryItem,
        relevance: Double,
        lexicalTier: LexicalTier
    ) -> UnifiedSearchResult {
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
            lexicalTier: lexicalTier,
            atomUUID: item.atomUUID,
            atomType: .research,
            thinkspaceId: nil,
            projectUUID: nil,
            projectName: nil,
            thinkspaceNames: [],
            readwiseBookId: nil
        )
    }

    private static func ideaResult(
        for item: IdeaGalleryItem,
        relevance: Double,
        lexicalTier: LexicalTier,
        matchedExcerpt: String? = nil
    ) -> UnifiedSearchResult {
        UnifiedSearchResult(
            id: "idea-\(item.atomUUID)",
            source: .ideas,
            resultKind: .atom,
            title: item.title,
            subtitle: [item.status.displayName, item.contentFormat?.displayName].compactMap { $0 }.joined(separator: " · "),
            snippet: item.body?.prefix(120).description,
            matchedExcerpt: matchedExcerpt,
            icon: "lightbulb.fill",
            accentColor: DS.entityIdea,
            relevance: relevance,
            lexicalTier: lexicalTier,
            atomUUID: item.atomUUID,
            atomType: .idea,
            thinkspaceId: nil,
            projectUUID: nil,
            projectName: nil,
            thinkspaceNames: [],
            readwiseBookId: nil
        )
    }

    /// Idea result built straight from an engine match, for when the idea
    /// gallery has not been loaded yet.
    private static func ideaResult(for result: RankedResult) -> UnifiedSearchResult {
        UnifiedSearchResult(
            id: "idea-\(result.atomUUID)",
            source: .ideas,
            resultKind: .atom,
            title: result.title,
            subtitle: AtomType.idea.displayName,
            snippet: result.snippet?.prefix(120).description,
            matchedExcerpt: result.matchedExcerpt,
            icon: "lightbulb.fill",
            accentColor: DS.entityIdea,
            relevance: result.relevance,
            lexicalTier: result.lexicalTier,
            atomUUID: result.atomUUID,
            atomType: .idea,
            thinkspaceId: nil,
            projectUUID: nil,
            projectName: nil,
            thinkspaceNames: [],
            readwiseBookId: nil
        )
    }

    static func thinkspaceResult(
        for item: LibraryItem,
        relevance: Double,
        lexicalTier: LexicalTier
    ) -> UnifiedSearchResult {
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
            lexicalTier: lexicalTier,
            atomUUID: nil,
            atomType: .thinkspace,
            thinkspaceId: item.uuid,
            projectUUID: item.projectUUID,
            projectName: item.projectName,
            thinkspaceNames: item.thinkspaceNames,
            readwiseBookId: nil
        )
    }

    /// Swipes are all curated, high-quality captures — rank them by how well
    /// they match the query, never by hook score.
    private static func swipeRelevance(
        for item: SwipeGalleryItem,
        normalizedQuery: String
    ) -> (tier: LexicalTier, relevance: Double) {
        let (tier, quality) = CommandKSearchMatcher.lexicalMatch(
            normalizedQuery: normalizedQuery,
            normalizedTitle: CommandKSearchMatcher.normalize(item.title),
            normalizedFullText: item.searchableText
        )
        return (tier, quality)
    }

    private static func ideaRelevance(
        for item: IdeaGalleryItem,
        normalizedQuery: String
    ) -> (tier: LexicalTier, relevance: Double) {
        let (tier, quality) = CommandKSearchMatcher.lexicalMatch(
            normalizedQuery: normalizedQuery,
            normalizedTitle: CommandKSearchMatcher.normalize(item.title),
            normalizedFullText: CommandKSearchMatcher.searchableText(
                from: [item.title, item.body, item.clientName] + item.tags.map(Optional.some)
            )
        )
        // Items can reach this path via IdeasTab.matchesSearch with field-level
        // matches the joined text scorer might miss — keep a floor, but within
        // the keyword-in-body tier so it never lifts above title matches.
        return (min(tier, .keywordInBody), max(quality, 0.4))
    }

    /// The better of two (tier, relevance) rankings — tier first.
    private static func bestRank(
        _ lhs: (tier: LexicalTier, relevance: Double),
        _ rhs: (tier: LexicalTier, relevance: Double)
    ) -> (tier: LexicalTier, relevance: Double) {
        if lhs.tier != rhs.tier { return lhs.tier < rhs.tier ? lhs : rhs }
        return lhs.relevance >= rhs.relevance ? lhs : rhs
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
        atom.updatedAt = ISO8601.string(from: Date())
        return atom
    }

    @MainActor
    func capture(
        url: String,
        hook: String? = nil,
        notes: String? = nil,
        clientUUID: String? = nil
    ) async throws -> Atom {
        var atom = try pendingAtom(for: url, hook: hook)

        // Notes land the way the capture_swipe agent tool writes them.
        if let notes, !notes.isEmpty {
            if (atom.body ?? "").isEmpty {
                atom.body = notes
            } else {
                atom.body = (atom.body ?? "") + "\n\n--- Notes ---\n" + notes
            }
        }

        let saved = try await AtomRepository.shared.create(atom)
        // Inherit the front door's completion: flow append + library refresh +
        // a receipt naming the kind (⌘K has no toast of its own).
        SwipeIntakeRouter.noteExternallyCreatedSwipe(saved)

        // Client tag: swipeToClient link + clientUUID in the swipe analysis —
        // the same contract the capture_swipe agent tool writes.
        if let clientUUID {
            _ = try? await AtomRepository.shared.update(uuid: saved.uuid) { current in
                var links = current.linksList
                if !links.contains(where: { $0.linkType == .swipeToClient && $0.uuid == clientUUID }) {
                    links.append(AtomLink.swipeToClient(clientUUID))
                    current.links = try? String(data: JSONEncoder().encode(links), encoding: .utf8)
                }
                if let structured = current.structured,
                   let data = structured.data(using: .utf8),
                   var analysis = try? JSONDecoder().decode(SwipeAnalysis.self, from: data) {
                    analysis.clientUUID = clientUUID
                    current.structured = try? String(data: JSONEncoder().encode(analysis), encoding: .utf8)
                }
            }
        }

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
@Observable
public final class CommandKViewModel {

    // MARK: - Cortex Mode State

    /// Current interaction mode (compact → searchResults → expandedDomain)
    public var cortexMode: CortexMode = .compact

    /// Recent items for compact mode display
    public var recentItems: [RecentDisplayItem] = []

    /// The initial tab passed from MainView (nil = start compact)
    var initialExpandedTab: CommandKTab?

    // MARK: - Published State

    /// Current search query. Live typing is kept out of observation tracking
    /// so each keystroke does not invalidate the entire Command-K surface.
    @ObservationIgnored public var query: String = ""

    /// Observation-tracked mirror of `query`, published for the one surface
    /// that filters LOCALLY instead of through `performSearch`: the expanded
    /// domain rail (Swipe File / Database / Library scopes). Those scopes
    /// return early out of `performSearch`, so a keystroke there changes
    /// nothing else SwiftUI can see — the rail's cached rows never refresh
    /// and the list stays unfiltered. Any body or `onChange` that must
    /// re-evaluate as the user types reads THIS, never `query`.
    public private(set) var domainFilterQuery: String = ""

    /// Bumped only when the view model changes the field programmatically.
    public private(set) var querySyncToken: Int = 0

    /// Current search results
    public private(set) var results: [RankedResult] = []

    /// Selected result/node UUID
    public var selectedNodeId: String?

    /// Whether the contextual actions panel (second ⌘K) is showing. Lives here
    /// rather than in the view so MainView's global escape monitor can peel the
    /// panel before closing the whole palette.
    public var isActionPanelPresented = false

    /// The live composer form shown in the detail pane when a creation action
    /// is selected (the Mac's plus-orb sheets). Lives on the view model for
    /// the same reason as `isActionPanelPresented`: MainView's escape monitor
    /// and the keyboard layer need to see it.
    var composerDraft: CommandKComposerDraft?

    /// Live Ask-Cortex session shown in the detail pane. Set when an
    /// `?<question>` action executes; Escape peels it before the palette
    /// closes (same layer contract as the composer).
    var askSession: CommandKAskSession?

    /// True while keyboard focus is inside the composer form. Escape peels
    /// this layer first (returns focus to the search field, palette stays).
    public var isComposerFocused = false

    /// Current search phase. Kept out of observation tracking so background
    /// phase changes do not invalidate the Command-K surface.
    @ObservationIgnored public private(set) var currentPhase: SearchPhase = .idle

    /// User-visible search feedback that is independent from background search phase.
    public private(set) var searchFeedback: CommandKSearchFeedback = .none

    /// Multi-select type filters
    public var selectedTypeFilters: Set<AtomType> = [] {
        didSet { applyFiltersToResults() }
    }

    /// Filter counts by type (computed from unfiltered results)
    public private(set) var filterCounts: [AtomType: Int] = [:]

    /// Error message (if any)
    public var errorMessage: String?

    // MARK: - Swipe Gallery State

    /// Swipe gallery items loaded from research atoms
    public var swipeGalleryItems: [SwipeGalleryItem] = [] {
        didSet { scheduleSwipeFilterRecompute() }
    }

    /// Current grouping mode for swipe gallery
    public var swipeGrouping: SwipeGrouping = .narrativeStyle

    /// Current sort mode for swipe gallery
    public var swipeSortMode: SwipeSortMode = .recent {
        didSet { scheduleSwipeFilterRecompute() }
    }

    /// Platform filter for swipe gallery (nil = all)
    public var swipePlatformFilter: String? {
        didSet { scheduleSwipeFilterRecompute() }
    }

    /// Hook type filter for swipe gallery (nil = all)
    public var swipeHookTypeFilter: SwipeHookType? {
        didSet { scheduleSwipeFilterRecompute() }
    }

    /// Narrative style filters for swipe gallery (multi-select)
    var swipeNarrativeFilters: Set<NarrativeStyle> = [] {
        didSet { scheduleSwipeFilterRecompute() }
    }

    /// Content format filters for swipe gallery (multi-select)
    var swipeContentFormatFilters: Set<ContentFormat> = [] {
        didSet { scheduleSwipeFilterRecompute() }
    }

    /// Niche filter for swipe gallery (nil = all)
    var swipeNicheFilter: String? {
        didSet { scheduleSwipeFilterRecompute() }
    }

    /// Creator filter for swipe gallery (nil = all)
    var swipeCreatorFilter: String? {
        didSet { scheduleSwipeFilterRecompute() }
    }

    /// Available niches extracted from swipe gallery items
    var availableNiches: [String] = []

    /// Available creators extracted from swipe gallery items
    var availableCreators: [(name: String, uuid: String)] = []

    /// Creator search query for autocomplete
    var creatorSearchQuery: String = ""

    /// Whether swipe gallery has been loaded
    private var swipeGalleryLoaded = false

    /// Cached filtered swipes — recomputed only when filter inputs change
    public private(set) var cachedFilteredSwipes: [SwipeGalleryItem] = []

    /// Cached clustered sections — recomputed from cachedFilteredSwipes
    public private(set) var cachedClusteredSections: [FormatSection] = []

    /// View mode for swipe gallery: clustered folders or flat grid
    var swipeViewMode: SwipeViewMode = .clustered

    /// Search query passed from SwipeGalleryTab for filtering
    var swipeSearchQuery: String = "" {
        didSet { scheduleSwipeFilterRecompute() }
    }

    /// Expansion state for Layer 1 format group sections
    var expandedFormatGroups: Set<String> = Set(FormatGroup.allCases.map(\.rawValue))

    /// Expansion state for Layer 2 narrative clusters (collapsed by default)
    var expandedClusters: Set<String> = []

    /// Precomputed swipe facets used by the command menu chrome.
    private(set) var swipeFacetSummary: CommandKSwipeFacetSummary = .empty

    // MARK: - Multi-Select State

    /// UUIDs of cards selected via Shift+Click across gallery tabs
    var selectedUUIDs: Set<String> = []

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
    var isUnifiedSearchActive: Bool = false

    /// Grouped unified results by source
    var unifiedGroupedResults: [(source: UnifiedSearchSource, results: [UnifiedSearchResult])] = []

    /// Flat ordered list for keyboard navigation across all unified groups
    var unifiedFlatResults: [UnifiedSearchResult] = []

    /// Selected Readwise book ID for navigation from unified results
    var selectedReadwiseBookId: Int?

    /// Card items for masonry grid display of unified search results
    var unifiedCardItems: [UnifiedCardItem] = []

    /// Library items keyed by lookup key — used to render Database section with real library previews
    var unifiedLibraryItemsByID: [String: LibraryItem] = [:]

    // MARK: - Idea Gallery State

    /// Idea gallery items loaded from idea atoms
    var ideaGalleryItems: [IdeaGalleryItem] = []

    /// Whether idea gallery has been loaded
    private var ideaGalleryLoaded = false

    /// Lightweight counts for domains whose full content has not been loaded yet.
    private(set) var swipeTotalCount: Int = 0
    private(set) var ideaTotalCount: Int = 0

    /// Cached domain counts and masthead previews. Building this in `body` is too expensive.
    private(set) var domainPresentation: CommandKDomainPresentation = .empty

    // MARK: - Configuration

    /// Debounce delay for search queries. Keep this close to a frame so local command rows feel instant.
    private let searchDebounce: TimeInterval = 0.03

    /// Delay only the expensive semantic search. Local indexed results still publish immediately.
    private let semanticSearchDelayNanoseconds: UInt64 = 120_000_000

    /// Maximum results to display
    private let maxResults = 25

    /// Whether we're showing recents (empty query)
    var isShowingRecents: Bool = false

    /// Whether AI re-ranking has been applied
    var isAIRanked: Bool = false

    /// Grouped results by atom type (ordered by best score)
    var groupedResults: [(type: AtomType, results: [RankedResult])] = []

    /// Flat ordered list for keyboard navigation (across groups)
    var flatNavigableResults: [RankedResult] = []

    /// Currently selected index in flatNavigableResults for keyboard nav
    var selectedResultIndex: Int = -1

    /// Flat ordered list for keyboard navigation in expanded domain rail mode.
    private(set) var expandedDomainSelectionIDs: [String] = []
    private var expandedDomainOpenTargets: [String: CommandKDomainOpenTarget] = [:]

    /// Active #type prefix filter parsed from query
    var activeTypePrefix: AtomType? = nil

    /// Top fast action parsed from the current query, shown before search results.
    var primaryAction: CommandKAction? = nil

    /// The other capture verb for a pasted URL (swipe ↔ research) — rendered
    /// as a second COMMANDS row so the URL's source type only ever picks the
    /// default, never removes an option.
    var secondaryAction: CommandKAction? = nil

    /// Saved quicklinks and user commands that match the current query.
    var userCommandRows: [CommandKUserCommandRow] = []

    /// Whether a fast action is currently executing.
    var isExecutingAction: Bool = false

    /// Inline status for the action preview row.
    var actionStatusMessage: String? = nil

    private var executablePrimaryAction: CommandKAction? = nil

    var activeCommandAction: CommandKAction? {
        if let primaryAction,
           selectedNodeId == nil || selectedNodeId == primaryAction.id {
            return primaryAction
        }
        guard let selectedNodeId else { return nil }
        if let secondaryAction, secondaryAction.id == selectedNodeId {
            return secondaryAction
        }
        return userCommandRows.first { $0.id == selectedNodeId }?.action
    }

    private func setPrimaryAction(_ action: CommandKAction?) {
        executablePrimaryAction = action
        if let action { syncComposerDraftPrefills(from: action) }
        let alternate = CommandKActionParser.alternateAction(for: action)
        if secondaryAction != alternate {
            secondaryAction = alternate
        }
        guard shouldPublishPrimaryActionUpdate(from: primaryAction, to: action) else {
            return
        }
        primaryAction = action
    }

    /// Whether the current selection is a creation action whose detail pane
    /// is a live composer — the keyboard layer routes Tab into it.
    var isComposerSubjectSelected: Bool {
        guard let id = selectedNodeId else { return false }
        let action: CommandKAction?
        if let primary = primaryAction, primary.id == id {
            action = primary
        } else if let secondary = secondaryAction, secondary.id == id {
            action = secondary
        } else if let row = userCommandRows.first(where: { $0.id == id }) {
            action = row.action
        } else {
            action = nil
        }
        guard let action else { return false }
        return CommandKComposerDraft.composerKind(for: action.kind) != nil
    }

    /// Mint or refresh the composer draft when the selection lands on a
    /// creation action. The same action id keeps accumulated field edits;
    /// a different creation action mints a fresh draft.
    func ensureComposerDraft(for action: CommandKAction) {
        if composerDraft?.actionID == action.id {
            syncComposerDraftPrefills(from: action)
        } else if let draft = CommandKComposerDraft.draft(for: action) {
            composerDraft = draft
            isComposerFocused = false
        }
    }

    /// Live query→lead-field sync: typing after the keyword updates the
    /// draft's title/body until the user edits that field by hand.
    private func syncComposerDraftPrefills(from action: CommandKAction) {
        guard var draft = composerDraft, draft.actionID == action.id else { return }
        draft.syncPrefills(from: action)
        if draft != composerDraft { composerDraft = draft }
    }

    private func resetComposerState() {
        composerDraft = nil
        isComposerFocused = false
        askSession = nil
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

    func testingNextSearchRequestID() async -> CommandKSearchRequestID {
        await searchPipeline.nextRequestID()
    }

    func testingUpdateUnifiedSearch(query: String, searchRequestID: CommandKSearchRequestID) async {
        // Behaves like a fresh user-initiated search: the settle window is
        // open, so this publish may rank freely. Tests that exercise the
        // order lock close the window explicitly via
        // testingCloseResultOrderSettleWindow().
        foregroundSearchStartedAt = Date()
        await updateUnifiedSearch(
            query: query,
            preloadSupportData: false,
            includeThinkspaces: false,
            searchRequestID: searchRequestID
        )
    }

    /// Publish without reopening the settle window — simulates a late wave
    /// (enrichment, AI re-rank, background refresh) landing on a list the
    /// user has already been reading.
    func testingUpdateUnifiedSearchAsLateWave(query: String, searchRequestID: CommandKSearchRequestID) async {
        await updateUnifiedSearch(
            query: query,
            preloadSupportData: false,
            includeThinkspaces: false,
            searchRequestID: searchRequestID
        )
    }

    func testingCloseResultOrderSettleWindow() {
        foregroundSearchStartedAt = .distantPast
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

    private func setResults(_ nextResults: [RankedResult]) {
        if rankedResultSignature(results) != rankedResultSignature(nextResults) {
            results = nextResults
        }
    }

    private func setGroupedResults(_ nextGroups: [(type: AtomType, results: [RankedResult])]) {
        if rankedGroupSignature(groupedResults) != rankedGroupSignature(nextGroups) {
            groupedResults = nextGroups
        }
    }

    private func setFlatNavigableResults(_ nextResults: [RankedResult]) {
        if rankedResultSignature(flatNavigableResults) != rankedResultSignature(nextResults) {
            flatNavigableResults = nextResults
        }
    }

    private func rankedGroupSignature(_ groups: [(type: AtomType, results: [RankedResult])]) -> [String] {
        groups.flatMap { group in
            [group.type.rawValue] + rankedResultSignature(group.results)
        }
    }

    private func rankedResultSignature(_ results: [RankedResult]) -> [String] {
        results.map { result in
            [
                result.atomUUID,
                result.atomType.rawValue,
                result.title,
                result.snippet ?? "",
                String(result.relevance),
                result.updatedAt,
                String(result.accessCount)
            ].joined(separator: "\u{1F}")
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
    /// Newest `updatedAt` the index has seen — force refreshes fetch only rows
    /// at/after this stamp and merge, instead of re-reading 10k full atoms.
    private var searchIndexLastIndexedAt: String?
    private var instantIndexSearchTask: Task<[RankedResult], Never>?
    private var instantIndexSearchGeneration = 0
    private var searchIndexTask: Task<Void, Never>?
    private var unifiedSearchEnrichmentTask: Task<Void, Never>?
    private var swipeFilterTask: Task<Void, Never>?
    private var swipeFilterDebounceTask: Task<Void, Never>?
    private var queryDebounceTask: Task<Void, Never>?
    private var swipeFilterGeneration = 0
    private var isSurfaceActive = true
    private let userCommandStore: CommandKUserCommandStore
    private let userCommandComposer = CommandKUserCommandSearchComposer()
    private let systemCommandComposer = CommandKSystemCommandComposer()

    /// Unfiltered results for computing filter counts.
    ///
    /// Tasks are dropped on the way in. ⌘K searches the knowledge database;
    /// tasks live on Today/Plannerum and are not part of it. Gating in the
    /// setter rather than at each assignment site keeps every path task-free —
    /// instant index, `QueryResultCache` replay (including entries written
    /// before this gate existed), hybrid merge, graph fallback, and recents —
    /// and every downstream reader (filter counts, the unified DATABASE
    /// section, landing-excerpt lookup) inherits it.
    private var unfilteredResults: [RankedResult] {
        get { unfilteredResultsStorage }
        set { unfilteredResultsStorage = newValue.filter { $0.atomType != .task } }
    }

    private var unfilteredResultsStorage: [RankedResult] = []

    /// Query that produced the current search state. A background refresh for
    /// the same query keeps the visible results and swaps them in place.
    private var lastSearchedQuery: String?

    /// Monotonic token for live text edits. It lets in-flight searches notice
    /// that the field changed before a debounced replacement search starts.
    private var liveQueryGeneration = 0

    /// When the current foreground (user-initiated) search started. Publishes
    /// that land within `resultOrderSettleWindow` of this instant may re-rank
    /// freely — they read as results streaming in. Anything later is
    /// order-locked: the list a user is reading, and about to press Return
    /// on, never rearranges (Spotlight contract).
    private var foregroundSearchStartedAt: Date = .distantPast

    /// How long after a keystroke the result order may still settle. Sized to
    /// cover the instant → cache → hybrid → enrichment waves on a normal run;
    /// a wave that misses the window still lands, but merges in place.
    private var resultOrderSettleWindow: TimeInterval = 0.4

    // MARK: - Initialization

    public convenience init() {
        self.init(userCommandStore: CommandKUserCommandStore())
    }

    init(userCommandStore: CommandKUserCommandStore) {
        self.userCommandStore = userCommandStore
        scheduleSwipeFilterRecompute()
        setupSwipeRefreshListener()
        setupIdeaRefreshListener()
        setupCommandKRefreshListener()
    }

    public func setSurfaceActive(_ active: Bool) {
        guard isSurfaceActive != active else { return }
        isSurfaceActive = active

        if active {
            prewarmSearchIndexIfNeeded()
            // Warm the swipe/idea galleries so the first keystroke's unified
            // pass can match against them instead of waiting for enrichment.
            Task { @MainActor [weak self] in
                // When the index is already warm this preload is a background
                // refinement — hold it past the open spring so its result
                // application can't drop animation frames.
                if self?.searchIndexLoaded == true {
                    try? await Task.sleep(for: .milliseconds(320))
                }
                guard let self, self.isSurfaceActive else { return }
                await self.preloadUnifiedSearchSupportData()
                // Thinkspaces ride the instant unified pass now — warm them
                // so the first keystroke never awaits a load.
                if ThinkspaceManager.shared.thinkspaces.isEmpty {
                    await ThinkspaceManager.shared.loadThinkspaces()
                }
            }
        } else {
            searchTask?.cancel()
            queryDebounceTask?.cancel()
            instantIndexSearchTask?.cancel()
            ideaGalleryReloadTask?.cancel()
            commandKRefreshTask?.cancel()
            searchIndexTask?.cancel()
            unifiedSearchEnrichmentTask?.cancel()
            swipeFilterTask?.cancel()
            swipeFilterDebounceTask?.cancel()
            resetComposerState()
            setCurrentPhase(.idle)
        }
    }

    // MARK: - Query Handling

    public func updateQuery(_ newQuery: String) {
        guard query != newQuery else { return }
        writeQuery(newQuery)
        liveQueryGeneration &+= 1
        let queryGeneration = liveQueryGeneration

        queryDebounceTask?.cancel()
        cancelActiveSearchWork()

        if newQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clearVisibleSearchStateForEmptyQuery()
            queryDebounceTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard let self,
                      !Task.isCancelled,
                      self.isSurfaceActive,
                      self.isCurrentLiveQueryGeneration(queryGeneration) else {
                    return
                }
                await self.performSearch(query: newQuery, queryGeneration: queryGeneration)
            }
            return
        }

        let debounce = UInt64(searchDebounce * 1_000_000_000)
        queryDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: debounce)
            guard let self,
                  !Task.isCancelled,
                  self.isSurfaceActive,
                  self.isCurrentLiveQueryGeneration(queryGeneration) else {
                return
            }
            await self.performSearch(query: newQuery, queryGeneration: queryGeneration)
        }
    }

    private func setQueryProgrammatically(_ newQuery: String) {
        queryDebounceTask?.cancel()
        liveQueryGeneration &+= 1
        cancelActiveSearchWork()
        guard query != newQuery else {
            querySyncToken &+= 1
            return
        }
        writeQuery(newQuery)
        querySyncToken &+= 1
    }

    /// The single write point for the query. Both the untracked field the
    /// search pipeline reads and its tracked mirror move together — a write
    /// that skips this leaves the domain rail filtering on a stale string.
    private func writeQuery(_ newQuery: String) {
        query = newQuery
        domainFilterQuery = newQuery
    }

    private func cancelActiveSearchWork() {
        searchTask?.cancel()
        searchTask = nil
        instantIndexSearchTask?.cancel()
        instantIndexSearchTask = nil
        instantIndexSearchGeneration &+= 1
        unifiedSearchEnrichmentTask?.cancel()
        unifiedSearchEnrichmentTask = nil
    }

    private func isCurrentLiveQueryGeneration(_ generation: Int?) -> Bool {
        guard let generation else { return true }
        return generation == liveQueryGeneration
    }

    private func clearVisibleSearchStateForEmptyQuery() {
        lastSearchedQuery = nil
        setSearchFeedback(.none)
        setPrimaryAction(nil)
        setActionStatusMessage(nil)
        setUserCommandRows([])
        results = []
        unfilteredResults = []
        groupedResults = []
        flatNavigableResults = []
        filterCounts = [:]
        activeTypePrefix = nil
        selectedTypeFilters.removeAll()
        setUnifiedSearchResults(active: false, grouped: [], flat: [], cards: [])
        selectedReadwiseBookId = nil
        isShowingRecents = false
        isAIRanked = false
        selectedNodeId = nil
        selectedResultIndex = -1
        resetComposerState()
        setCurrentPhase(.idle)
    }

    private func prewarmSearchIndexIfNeeded(force: Bool = false, ignoringSurface: Bool = false) {
        guard isSurfaceActive || ignoringSurface else { return }
        guard force || !searchIndexLoaded else { return }

        searchIndexTask?.cancel()
        searchIndexTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let signpost = CommandKPerformanceInstrumentation.signposter.beginInterval("prewarm-search-index")
            defer {
                CommandKPerformanceInstrumentation.signposter.endInterval("prewarm-search-index", signpost)
            }
            do {
                // Refresh path: fetch only rows at/after the stamp and merge
                // by uuid — a force refresh used to re-read 10k full atoms.
                if force, self.searchIndexLoaded, let stamp = self.searchIndexLastIndexedAt {
                    let changed = try await AtomRepository.shared.fetchUserSearchableUpdatedSince(stamp)
                    guard !Task.isCancelled, self.isSurfaceActive || ignoringSurface else { return }
                    guard !changed.isEmpty else { return }
                    let existing = self.searchIndex.entries
                    let merged = await Task.detached(priority: .userInitiated) {
                        () -> (entries: [CommandKSearchIndex.Entry], newestStamp: String?) in
                        let deleted = Set(changed.filter(\.isDeleted).map(\.uuid))
                        let live = changed.filter { !$0.isDeleted }
                        let fresh = CommandKSearchIndex.entries(for: live)
                        let freshByUUID = Set(fresh.map(\.atomUUID))
                        var entries = existing.filter {
                            !deleted.contains($0.atomUUID) && !freshByUUID.contains($0.atomUUID)
                        }
                        entries.append(contentsOf: fresh)
                        // Same shape the full path produces: newest-first,
                        // capped at the full fetch's 10k.
                        entries.sort { $0.updatedAt > $1.updatedAt }
                        if entries.count > 10_000 {
                            entries.removeLast(entries.count - 10_000)
                        }
                        return (entries, changed.map(\.updatedAt).max())
                    }.value
                    guard !Task.isCancelled, self.isSurfaceActive || ignoringSurface else { return }
                    self.searchIndex.replace(merged.entries)
                    if let newestStamp = merged.newestStamp {
                        self.searchIndexLastIndexedAt = newestStamp
                    }
                    return
                }

                let atoms = try await AtomRepository.shared.fetchRecent(limit: 10_000)
                guard !Task.isCancelled, self.isSurfaceActive || ignoringSurface else { return }
                // Normalizing 10k full-text bodies is too heavy for the main
                // actor — build the entries on a background task.
                let entries = await Task.detached(priority: .userInitiated) {
                    CommandKSearchIndex.entries(for: atoms)
                }.value
                guard !Task.isCancelled, self.isSurfaceActive || ignoringSurface else { return }
                self.searchIndex.replace(entries)
                self.searchIndexLoaded = true
                // fetchRecent is updatedAt-desc — the first row is the stamp.
                self.searchIndexLastIndexedAt = atoms.first?.updatedAt
            } catch {
                CommandKPerformanceInstrumentation.logger.error("Command-K search index prewarm failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Merge two ranked result lists, deduping by atom UUID and keeping the
    /// entry that ranks higher (lexical tier first, then relevance), sorted.
    static func mergeRankedResults(primary: [RankedResult], additional: [RankedResult]) -> [RankedResult] {
        guard !additional.isEmpty else { return primary }
        var merged = primary
        var bestByUUID: [String: RankedResult] = [:]
        for result in primary {
            if let existing = bestByUUID[result.atomUUID], existing < result {
                continue
            }
            bestByUUID[result.atomUUID] = result
        }
        for result in additional {
            // `<` ranks better-first: only replace when the additional entry
            // is strictly better (better tier, or same tier + relevance) —
            // ties keep the primary entry.
            if let existing = bestByUUID[result.atomUUID], !(result < existing) {
                continue
            }
            merged.removeAll { $0.atomUUID == result.atomUUID }
            merged.append(result)
            bestByUUID[result.atomUUID] = result
        }
        return merged.sorted()
    }

    /// Parse #type prefix from query and return (stripped query, type filter)
    private func parseTypePrefix(_ rawQuery: String) -> (query: String, typeFilter: AtomType?) {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespaces)
        let prefixMap: [String: AtomType] = [
            "#idea": .idea,
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
    /// - Parameter isBackgroundRefresh: true when re-running because atom data
    ///   changed (sync pull, agent write) rather than a user keystroke. A
    ///   same-query refresh keeps the visible results and selection on screen
    ///   and swaps them in place once fresh results arrive.
    public func performSearch(
        query: String,
        isBackgroundRefresh: Bool = false,
        queryGeneration: Int? = nil
    ) async {
        guard isSurfaceActive, isCurrentLiveQueryGeneration(queryGeneration) else { return }
        // Cancel previous search
        searchTask?.cancel()
        instantIndexSearchTask?.cancel()
        instantIndexSearchGeneration &+= 1
        let preserveVisibleResults = isBackgroundRefresh && query == lastSearchedQuery
        let requestID = await searchPipeline.nextRequestID()
        guard isSurfaceActive, isCurrentLiveQueryGeneration(queryGeneration) else { return }
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
            lastSearchedQuery = nil
            setSearchFeedback(.none)
            setUnifiedSearchResults(active: false, grouped: [], flat: [], cards: [])
            setUserCommandRows([])
            // Auto-return to compact when query cleared (unless in expanded domain)
            if cortexMode == .searchResults {
                cortexMode = .compact
                await loadRecentsForCompact()
            }
            guard await searchPipeline.isCurrent(requestID),
                  isSurfaceActive,
                  isCurrentLiveQueryGeneration(queryGeneration) else {
                return
            }
            if case .expandedDomain = cortexMode {
                setCurrentPhase(.idle)
                return
            }
            await showRecents(searchRequestID: requestID, queryGeneration: queryGeneration)
            return
        }

        if case .expandedDomain = cortexMode {
            lastSearchedQuery = nil
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

        if !preserveVisibleResults {
            results = []
            unfilteredResults = []
            groupedResults = []
            flatNavigableResults = []
        }

        let matchedUserCommandRows = prefixType == nil
            ? await loadUserCommandRows(for: searchQuery)
            : []
        guard await searchPipeline.isCurrent(requestID),
              isCurrentLiveQueryGeneration(queryGeneration) else {
            return
        }
        setUserCommandRows(matchedUserCommandRows)
        if !preserveVisibleResults {
            updateActiveSearchSelection()
        }

        // Auto-transition to search results when typing in compact mode
        if cortexMode == .compact {
            cortexMode = .searchResults
        }
        // Reset phase so CortexSearchResultsView shows loading, not premature "no results".
        // A same-query background refresh keeps its visible results, so no loading phase.
        if !preserveVisibleResults {
            setCurrentPhase(.searching)
        }

        // Skip search in task creation mode
        if isTaskCreationMode {
            lastSearchedQuery = nil
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
        lastSearchedQuery = query
        if !isBackgroundRefresh {
            // Reopen the order-settle window only for user-initiated searches.
            // Background refreshes (sync pulls, agent writes) must merge into
            // the visible order, never reopen the right to rearrange it.
            foregroundSearchStartedAt = Date()
        }
        if !preserveVisibleResults {
            setCurrentPhase(.searching)
            results = []
            unfilteredResults = []
            groupedResults = []
            flatNavigableResults = []
            filterCounts = [:]
        }
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
        guard await searchPipeline.isCurrent(requestID),
              isSurfaceActive,
              isCurrentLiveQueryGeneration(queryGeneration) else {
            return
        }
        if !instantIndexedResults.isEmpty {
            // On a background refresh, merge into the visible set so the list
            // is not truncated to the instant subset while hybrid re-runs.
            unfilteredResults = preserveVisibleResults
                ? Self.mergeRankedResults(primary: unfilteredResults, additional: instantIndexedResults)
                : instantIndexedResults
            computeFilterCounts()
            applyFiltersToResults()
            await performInstantUnifiedSearch(
                query: queryForSearch,
                preserveSelection: preserveVisibleResults,
                searchRequestID: requestID,
                queryGeneration: queryGeneration
            )
            setCurrentPhase(.instant)
        } else {
            await performInstantUnifiedSearch(
                query: queryForSearch,
                preserveVisibleResultsWhenEmpty: true,
                preserveSelection: preserveVisibleResults,
                searchRequestID: requestID,
                queryGeneration: queryGeneration
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
            guard await searchPipeline.isCurrent(requestID),
                  isSurfaceActive,
                  isCurrentLiveQueryGeneration(queryGeneration) else {
                return
            }
            // Merge fresh instant-index matches so atoms created or edited
            // after the cache entry was written still appear.
            // The badge is honest here: the re-ranker refines cache entries
            // in place, so a cache hit may carry AI-refined ordering.
            isAIRanked = SearchReRanker.shared.hasCachedRanking(for: queryForSearch)
            unfilteredResults = Self.mergeRankedResults(primary: cached, additional: instantIndexedResults)
            computeFilterCounts()
            applyFiltersToResults()
            await performInstantUnifiedSearch(
                query: queryForSearch,
                preserveSelection: preserveVisibleResults,
                searchRequestID: requestID,
                queryGeneration: queryGeneration
            )
            scheduleUnifiedSearchEnrichment(
                for: queryForSearch,
                preserveSelection: preserveVisibleResults,
                searchRequestID: requestID,
                queryGeneration: queryGeneration
            )
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
                      isCurrentLiveQueryGeneration(queryGeneration),
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

                // Convert HybridSearchEngine.SearchResult to RankedResult,
                // assigning each result's lexical tier from the query.
                let normalizedQueryForTiers = CommandKSearchMatcher.normalizeQuery(queryForSearch)
                var rankedResults: [RankedResult] = []
                for result in hybridResults {
                    try Task.checkCancellation()
                    rankedResults.append(CommandKHybridResultMapper.rankedResult(
                        from: result,
                        atomType: entityTypeToAtomType(result.entityType),
                        normalizedQuery: normalizedQueryForTiers
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

                // Merge instant keyword matches instead of replacing them —
                // an exact-title hit outside BM25's candidate window must not
                // vanish when the hybrid pass lands.
                let mergedResults = Self.mergeRankedResults(
                    primary: rankedResults,
                    additional: instantIndexedResults
                )

                // Update state
                if !Task.isCancelled,
                   isSurfaceActive,
                   isCurrentLiveQueryGeneration(queryGeneration),
                   await searchPipeline.isCurrent(requestID) {
                    isAIRanked = false
                    unfilteredResults = mergedResults
                    computeFilterCounts()
                    applyFiltersToResults()
                    await performInstantUnifiedSearch(
                        query: queryForSearch,
                        preserveSelection: preserveVisibleResults,
                        searchRequestID: requestID,
                        queryGeneration: queryGeneration
                    )
                    scheduleUnifiedSearchEnrichment(
                        for: queryForSearch,
                        preserveSelection: preserveVisibleResults,
                        searchRequestID: requestID,
                        queryGeneration: queryGeneration
                    )
                    setCurrentPhase(.complete)

                    // Cache the merged list so cache hits carry the
                    // instant-derived lexical tiers too.
                    await QueryResultCache.shared.set(mergedResults, for: cacheKey)

                    // Fire the AI re-ranker asynchronously — but it NEVER
                    // touches the live list. Once results are on screen their
                    // order is frozen (Spotlight contract); the model's
                    // judgment flows into the query cache instead, so the
                    // NEXT identical query paints in the refined order from
                    // its first frame. Only body/semantic tiers go to the
                    // model — title matches are ordered lexically and must
                    // not be demoted.
                    let queryForReRank = queryForSearch
                    let reRankInputs = mergedResults
                        .filter { $0.lexicalTier >= .phraseInBody }
                        .prefix(25)
                        .map { r in
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
                              isCurrentLiveQueryGeneration(queryGeneration) else {
                            return
                        }
                        let rerankSignpost = CommandKPerformanceInstrumentation.signposter.beginInterval("ai-rerank")
                        if let reRanked = await SearchReRanker.shared.reRank(
                            query: queryForReRank,
                            results: reRankInputs
                        ) {
                            // Rebuild with AI-boosted semantic weights and
                            // refresh the cache entry in place.
                            // Build keyed on uuid from model-derived output —
                            // never `uniqueKeysWithValues:`, which traps on the
                            // duplicate keys the re-ranker can still produce if
                            // two results share a uuid. Keep the first (highest-
                            // ranked) score on collision.
                            let aiScoreMap = Dictionary(
                                reRanked.map { ($0.uuid, $0.blendedScore) },
                                uniquingKeysWith: { first, _ in first }
                            )
                            let reRankedResults = mergedResults.map { r in
                                if let aiScore = aiScoreMap[r.atomUUID] {
                                    return RankedResult(
                                        atomUUID: r.atomUUID,
                                        atomType: r.atomType,
                                        title: r.title,
                                        snippet: r.snippet,
                                        matchedExcerpt: r.matchedExcerpt,
                                        semanticWeight: aiScore,
                                        structuralWeight: r.structuralWeight,
                                        recencyWeight: r.recencyWeight,
                                        usageWeight: r.usageWeight,
                                        lexicalTier: r.lexicalTier,
                                        updatedAt: r.updatedAt,
                                        accessCount: r.accessCount
                                    )
                                }
                                return r
                            }
                            await QueryResultCache.shared.set(reRankedResults.sorted(), for: cacheKey)
                        }
                        CommandKPerformanceInstrumentation.signposter.endInterval("ai-rerank", rerankSignpost)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled,
                   isSurfaceActive,
                   isCurrentLiveQueryGeneration(queryGeneration),
                   await searchPipeline.isCurrent(requestID) {
                    // Fallback to graph-based search if hybrid fails
                    await fallbackToGraphSearch(
                        query: query,
                        searchRequestID: requestID,
                        queryGeneration: queryGeneration
                    )
                }
            }
        }
    }

    private func loadUserCommandRows(for query: String) async -> [CommandKUserCommandRow] {
        let systemRows = systemCommandComposer.rows(for: query)
        let quicklinkRows: [CommandKUserCommandRow]
        do {
            quicklinkRows = userCommandComposer.rows(for: try await userCommandStore.searchQuicklinks(query))
        } catch {
            quicklinkRows = []
        }
        return Self.dedupedCommandRows(
            primaryAction: primaryAction,
            systemRows: systemRows,
            quicklinkRows: quicklinkRows
        )
    }

    /// One row per destination: the parsed primary action claims its target
    /// first, then system commands, then quicklinks — so a quicklink (or a
    /// second system command) that navigates somewhere already listed never
    /// renders a duplicate row.
    static func dedupedCommandRows(
        primaryAction: CommandKAction?,
        systemRows: [CommandKUserCommandRow],
        quicklinkRows: [CommandKUserCommandRow]
    ) -> [CommandKUserCommandRow] {
        var seenTargets = Set<String>()
        if let key = primaryAction?.navigationTargetKey {
            seenTargets.insert(key)
        }
        let primaryID = primaryAction?.id

        func claims(_ row: CommandKUserCommandRow) -> Bool {
            if row.action.id == primaryID { return false }
            guard let key = row.action.navigationTargetKey else { return true }
            return seenTargets.insert(key).inserted
        }

        return systemRows.filter(claims) + quicklinkRows.filter(claims)
    }

    /// Fallback to direct atom search if HybridSearchEngine fails
    private func fallbackToGraphSearch(
        query: String,
        searchRequestID: CommandKSearchRequestID? = nil,
        queryGeneration: Int? = nil
    ) async {
        do {
            // Search atoms directly by title/body containing query
            let atoms = try await AtomRepository.shared.search(query: query, limit: maxResults * 2)
            guard await isCurrentSearchRequest(searchRequestID),
                  isSurfaceActive,
                  isCurrentLiveQueryGeneration(queryGeneration) else {
                return
            }

            let normalizedQuery = CommandKSearchMatcher.normalizeQuery(query)
            var rankedResults: [RankedResult] = []
            for atom in atoms {
                let title = atom.title ?? "Untitled"
                let (tier, quality) = CommandKSearchMatcher.lexicalMatch(
                    normalizedQuery: normalizedQuery,
                    normalizedTitle: CommandKSearchMatcher.normalize(title),
                    normalizedFullText: CommandKSearchMatcher.searchableText(from: [title, atom.body])
                )
                rankedResults.append(RankedResult(
                    atomUUID: atom.uuid,
                    atomType: atom.type,
                    title: title,
                    snippet: atom.body?.prefix(100).description,
                    matchedExcerpt: tier >= .phraseInBody
                        ? CommandKMatchExcerpt.excerpt(from: atom.body, query: query)
                        : nil,
                    semanticWeight: 0.0,
                    structuralWeight: max(quality, 0.42),
                    recencyWeight: WeightCalculator.recencyWeight(fromISO8601: atom.updatedAt),
                    usageWeight: 0.5,
                    // These atoms came from a keyword search — even when the
                    // match is in body text beyond the snippet, floor at
                    // keyword-in-body rather than semantic-only.
                    lexicalTier: min(tier, .keywordInBody),
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
            guard await isCurrentSearchRequest(searchRequestID),
                  isSurfaceActive,
                  isCurrentLiveQueryGeneration(queryGeneration) else {
                return
            }
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
        if filterCounts != counts {
            filterCounts = counts
        }
    }

    /// Apply current filters to unfiltered results
    private func applyFiltersToResults() {
        let nextResults: [RankedResult]
        if selectedTypeFilters.isEmpty {
            nextResults = Array(unfilteredResults.prefix(maxResults))
        } else {
            nextResults = Array(unfilteredResults
                .filter { selectedTypeFilters.contains($0.atomType) }
                .prefix(maxResults))
        }
        setResults(nextResults)
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
    private func showRecents(
        searchRequestID: CommandKSearchRequestID? = nil,
        queryGeneration: Int? = nil
    ) async {
        setCurrentPhase(.searching)
        isShowingRecents = true

        do {
            let openedAtoms = try await AtomRepository.shared.fetchRecentlyOpened(limit: 24)
            guard await isCurrentSearchRequest(searchRequestID),
                  isSurfaceActive,
                  isCurrentLiveQueryGeneration(queryGeneration) else {
                return
            }
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
            guard await isCurrentSearchRequest(searchRequestID),
                  isSurfaceActive,
                  isCurrentLiveQueryGeneration(queryGeneration) else {
                return
            }
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

        // Order sections by each group's best result — tier first, so a
        // fuzzy semantic hit can't lift its section above keyword matches.
        let sorted = groups.sorted { lhs, rhs in
            guard let lhsBest = lhs.value.first else { return false }
            guard let rhsBest = rhs.value.first else { return true }
            return lhsBest < rhsBest
        }

        let nextGroupedResults = sorted.map { (type: $0.key, results: $0.value) }
        setGroupedResults(nextGroupedResults)

        // Build flat navigable list (for keyboard navigation across groups)
        setFlatNavigableResults(sorted.flatMap { $0.value })
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
        if let action = activeCommandAction,
           await openCommandActionAsPaneIfSupported(action) {
            return
        }

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

    /// Place the selected result on the nearest canvas (⌥↵) — the quick
    /// keyboard form of the actions panel's "Add to Canvas". Resolution
    /// ladder mirrors `openSelectedAsPane()`; non-atom rows (thinkspaces,
    /// browser pins, readwise, commands) are a deliberate no-op.
    public func placeSelectedOnCanvas() {
        guard !isTaskCreationMode else { return }

        if let primaryAction,
           selectedNodeId == nil || selectedNodeId == primaryAction.id {
            return
        }

        if let selectedNodeId,
           userCommandRows.contains(where: { $0.id == selectedNodeId }) {
            return
        }

        if let selectedNodeId,
           recentItems.contains(where: { $0.id == selectedNodeId }) {
            placeAtomOnCurrentCanvas(uuid: selectedNodeId)
            return
        }

        if case .expandedDomain = cortexMode,
           let selectedNodeId,
           let target = expandedDomainOpenTargets[selectedNodeId] {
            if case .atom(let uuid) = target {
                placeAtomOnCurrentCanvas(uuid: uuid)
            }
            return
        }

        if let result = selectedUnifiedSearchResultForPaneOpen() {
            guard result.resultKind != .thinkspace,
                  result.resultKind != .browserPin,
                  let uuid = result.atomUUID else { return }
            placeAtomOnCurrentCanvas(uuid: uuid)
            return
        }

        if let uuid = selectedNodeId {
            placeAtomOnCurrentCanvas(uuid: uuid)
        }
    }

    /// Same notification shape as LibraryTab's single-click add: research and
    /// connection focus modes consume it for their own canvases, MainView
    /// covers every other surface.
    private func placeAtomOnCurrentCanvas(uuid: String) {
        Task { @MainActor in
            var userInfo: [String: Any] = ["atomUUID": uuid]
            if let atom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                userInfo["atomType"] = atom.type.rawValue
                userInfo["title"] = atom.title ?? "Untitled"
            }
            try? await NodeGraphEngine.shared.recordAccess(atomUUID: uuid, type: .view)
            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.addItemToCurrentCanvas,
                object: nil,
                userInfo: userInfo
            )
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
        }
    }

    private func openCommandActionAsPaneIfSupported(_ action: CommandKAction) async -> Bool {
        switch action.kind {
        case .openSwipeGallery:
            try? await CommandKActionExecutor().execute(.openSwipeGalleryAsPane)
            return true
        case .openDomain where action.payload.domain == "swipeGallery":
            try? await CommandKActionExecutor().execute(.openSwipeGalleryAsPane)
            return true
        default:
            return false
        }
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

    private func openBrowserPaneAfterCommandKDismissal(
        url: URL,
        title: String,
        disposition: BrowserOpenDisposition = .reuse
    ) {
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
        actionStatusMessage = nil
        setQueryProgrammatically("")
        setPrimaryAction(nil)
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openWebBrowserPane,
            object: nil,
            userInfo: [
                "url": url,
                "title": title,
                "disposition": disposition.rawValue
            ]
        )
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
            // The explicit open-as-pane gesture (⌘⏎) always earns a new pane.
            openBrowserPaneAfterCommandKDismissal(
                url: browserURL,
                title: result.browserTitle ?? result.subtitle ?? "Browser",
                disposition: .newPane
            )
        } else if result.resultKind == .thinkspace, let thinkspaceId = result.thinkspaceId {
            openThinkspaceAsPane(id: thinkspaceId)
        } else if result.atomType == .research, result.source != .swipes,
                  let atomUUID = result.atomUUID,
                  let target = await Self.researchBrowserTarget(atomUUID: atomUUID) {
            // A research link's pane IS the browser pane.
            openBrowserPaneAfterCommandKDismissal(
                url: target.url,
                title: target.title,
                disposition: .newPane
            )
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
        case .ideasBoard, .pipeline, .clients:
            // Destinations, not atoms — nothing to open as a pane.
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

        if let secondaryAction, selectedNodeId == secondaryAction.id {
            performAction(secondaryAction)
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

        // Body-evidence hits land ON the matched passage.
        if let ranked = unfilteredResults.first(where: { $0.atomUUID == uuid }),
           let excerpt = ranked.matchedExcerpt, !excerpt.isEmpty {
            CommandKSearchLandingStore.shared.stage(atomUUID: uuid, excerpt: excerpt, query: query)
        }

        // Research links divert to the browser pane; everything else opens
        // its focus mode (Command-K stays alive behind it).
        Task { @MainActor in
            if let target = await Self.researchBrowserTarget(atomUUID: uuid) {
                openBrowserPaneAfterCommandKDismissal(url: target.url, title: target.title)
            } else {
                postAtomOpenFromCommandK(uuid)
            }
        }
    }

    private func openUnifiedSearchResult(_ result: UnifiedSearchResult) {
        if result.resultKind == .browserPin, let browserURL = result.browserURL {
            openBrowserPaneAfterCommandKDismissal(
                url: browserURL,
                title: result.browserTitle ?? result.subtitle ?? "Browser"
            )
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
            // Body-evidence hits land ON the matched passage: stage the
            // jump-to-sentence request for the destination surface.
            if let excerpt = result.matchedExcerpt, !excerpt.isEmpty {
                CommandKSearchLandingStore.shared.stage(
                    atomUUID: atomUUID,
                    excerpt: excerpt,
                    query: query
                )
            }
            // A captured link lives on the web: non-swipe research with an
            // http(s) URL opens the in-app browser pane, not a focus mode.
            if result.atomType == .research, result.source != .swipes {
                Task { @MainActor in
                    if let target = await Self.researchBrowserTarget(atomUUID: atomUUID) {
                        openBrowserPaneAfterCommandKDismissal(url: target.url, title: target.title)
                    } else {
                        postAtomOpenFromCommandK(atomUUID)
                    }
                }
                return
            }
            postAtomOpenFromCommandK(atomUUID)
        } else if let bookId = result.readwiseBookId {
            selectedReadwiseBookId = bookId
        }
    }

    private func postAtomOpenFromCommandK(_ atomUUID: String) {
        NotificationCenter.default.post(
            name: CosmoNotification.NodeGraph.openAtomFromCommandK,
            object: nil,
            userInfo: ["atomUUID": atomUUID]
        )
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
    }

    /// Where a research atom opens: its captured URL when it is a genuine
    /// link capture (never a swipe, never a plain research note). Nil means
    /// the caller falls back to focus mode.
    static func researchBrowserTarget(atomUUID: String) async -> (url: URL, title: String)? {
        guard let atom = try? await AtomRepository.shared.fetch(uuid: atomUUID),
              atom.type == .research,
              !atom.isSwipeFileAtom,
              let urlString = atom.url
                ?? atom.richContent?.videoId.map({ "https://www.youtube.com/watch?v=\($0)" }),
              let url = URL(string: urlString),
              url.scheme == "http" || url.scheme == "https" else { return nil }
        return (url, atom.title ?? urlString)
    }

    private func openExpandedDomainTarget(_ target: CommandKDomainOpenTarget) {
        switch target {
        case .atom(let uuid):
            Task {
                try? await NodeGraphEngine.shared.recordAccess(atomUUID: uuid, type: .view)
            }
            // Research links divert to the browser pane; everything else
            // (and any fetch miss) opens its focus mode as before.
            Task { @MainActor in
                if let target = await Self.researchBrowserTarget(atomUUID: uuid) {
                    openBrowserPaneAfterCommandKDismissal(url: target.url, title: target.title)
                } else {
                    postAtomOpenFromCommandK(uuid)
                }
            }
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
        case .ideasBoard(let clientUUID):
            var userInfo: [AnyHashable: Any] = [:]
            if let clientUUID { userInfo["clientUUID"] = clientUUID }
            // MainView lands on the Ideas destination and closes the palette.
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openIdeas,
                object: nil,
                userInfo: userInfo
            )
        case .pipeline(let view):
            // MainView lands on the Pipeline in that view and closes the palette.
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openPipeline,
                object: nil,
                userInfo: ["view": view.rawValue]
            )
        case .clients:
            NotificationCenter.default.post(name: CosmoNotification.Navigation.openClients, object: nil)
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
            // A creation action with nothing typed yet isn't an error — Enter
            // drops you into its composer form instead.
            if CommandKComposerDraft.composerKind(for: action.kind) != nil {
                ensureComposerDraft(for: action)
                isComposerFocused = true
            } else {
                actionStatusMessage = "Add the missing detail first."
            }
            return
        }

        isExecutingAction = true
        actionStatusMessage = "Working…"

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
            if let url = action.payload.url {
                // A link captures instantly as a research atom (url +
                // thumbnail + async title) — never through the transcript
                // pipeline; any prose around the link rides as a note.
                _ = try await CommandKInstantResearchCapture().capture(
                    url: url,
                    note: action.payload.rawText ?? action.payload.body
                )
            } else {
                let title = action.payload.title ?? action.payload.body ?? "Research"
                var arguments: [String: Any] = ["title": title]
                if let body = action.payload.body { arguments["body"] = body }
                _ = try await AgentToolExecutor.shared.execute(toolName: "capture_research", arguments: arguments)
            }
            finishAction()

        case .createNote:
            let title = action.payload.title ?? action.payload.body ?? ""
            _ = try await AgentToolExecutor.shared.execute(toolName: "create_note", arguments: ["title": title])
            finishAction()

        case .captureInbox:
            guard let body = action.payload.body ?? action.payload.rawText else { return }
            _ = await TelegramCaptureRouter.shared.routeTelegramCapture(
                text: body,
                chatId: "command-k",
                messageId: nil,
                sender: "Command-K"
            )
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
            openBrowserPaneAfterCommandKDismissal(url: targetURL, title: title)

        case .openSwipeGallery:
            NotificationCenter.default.post(name: CosmoNotification.Navigation.openSwipeGallery, object: nil)
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
            await performSearch(query: savedQuery, queryGeneration: liveQueryGeneration)

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
            // One Cosmo: the floating chat window is gone — open the assistant pane.
            CosmoInlineAssistantStore.shared.openPane()
            finishAction()

        case .askCosmo:
            guard let body = action.payload.body else { return }
            CosmoInlineAssistantStore.shared.openPane()
            CosmoInlineAssistantStore.shared.submitPrompt(body)
            finishAction()

        case .calculator:
            // The Raycast contract: ⏎ puts the answer on the clipboard and
            // gets out of the way.
            guard let result = action.payload.resultText, !result.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result, forType: .string)
            finishAction()

        case .askCortex:
            guard let question = action.payload.body else { return }
            // Keep the palette open — the answer renders in the detail pane.
            Task { [weak self] in
                await CommandKAskEngine.run(question: question) { session in
                    self?.askSession = session
                }
            }
        }
    }

    /// Follow-up in the open Cortex conversation: the finished turn joins the
    /// prior-turn stack and retrieval reruns with the conversation's context.
    func askCortexFollowUp(_ text: String) {
        guard let current = askSession, current.phase == .answered else { return }
        let turns = current.priorTurns + [
            CommandKAskSession.CompletedTurn(question: current.question, answer: current.answer)
        ]
        Task { [weak self] in
            await CommandKAskEngine.run(question: text, priorTurns: turns) { session in
                self?.askSession = session
            }
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

    // MARK: - Composer Commit

    /// Commit the composer draft — the deep-capture path behind the
    /// detail-pane forms. One choke point per shape, reusing the same write
    /// paths as the quick colon-grammar actions.
    func commitComposerDraft() async {
        guard let draft = composerDraft, draft.validation.isValid else { return }
        do {
            try await commitComposer(draft)
            resetComposerState()
        } catch {
            actionStatusMessage = error.localizedDescription
        }
    }

    private func commitComposer(_ draft: CommandKComposerDraft) async throws {
        let form = draft.form
        switch draft.kind {
        case .createIdea:
            try await commitComposerIdea(draft)
            finishAction()

        case .createTask:
            try await commitComposerTask(draft)
            finishAction()

        case .captureInbox:
            // Same ingest choke point as the capture lanes — alias prefixes
            // in the text still route to their lane.
            _ = await TelegramCaptureRouter.shared.routeTelegramCapture(
                text: form.value(for: .body),
                chatId: "command-k",
                messageId: nil,
                sender: "Command-K"
            )
            finishAction()

        case .captureSwipe:
            let hook = form.value(for: .hook)
            let notes = form.value(for: .notes)
            // Resolve a typed-but-unpicked client name the idea composer's way.
            var swipeClientUUID = draft.clientUUID
            var swipeClientName = form.value(for: .client)
            if swipeClientUUID == nil, !swipeClientName.isEmpty {
                guard let client = try await AtomRepository.shared.fuzzyFindClient(query: swipeClientName) else {
                    throw CommandKActionExecutionError.clientNotFound(swipeClientName)
                }
                swipeClientUUID = client.uuid
                swipeClientName = client.title ?? swipeClientName
            }
            let swipe = try await CommandKInstantSwipeCapture().capture(
                url: form.value(for: .url),
                hook: hook.isEmpty ? nil : hook,
                notes: notes.isEmpty ? nil : notes,
                clientUUID: swipeClientUUID
            )
            // "Spark an idea" — one Save, two atoms, linked both ways.
            if draft.sparkIdea {
                let sparkTitle = draft.sparkTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                let sparkBody = draft.sparkBody.trimmingCharacters(in: .whitespacesAndNewlines)
                let ideaTitle = !sparkTitle.isEmpty ? sparkTitle
                    : (!hook.isEmpty ? hook : (swipe.hook ?? "Idea from swipe"))
                _ = try await createIdeaForClientAtom(
                    title: ideaTitle,
                    body: sparkBody.isEmpty ? nil : sparkBody,
                    clientUUID: swipeClientUUID,
                    clientName: swipeClientName.isEmpty ? nil : swipeClientName,
                    captureSource: "command_k_swipe_spark",
                    context: sparkBody.isEmpty ? nil : sparkBody,
                    linkedSwipeUUID: swipe.uuid
                )
            }
            finishAction()

        case .createNote, .createContent:
            // Creating IS editing (the iOS EditorCreationFlow model): make
            // the atom, then open it — hideCommandK, never blanket-close.
            // The note's opening paragraph rides atom.body (plain text is the
            // block editor's lenient-decoding path); content's core idea is
            // metadata the way ContentFocusMode reads it back.
            let composedBody = form.value(for: .body)
            var contentMetadata: String?
            if draft.kind == .createContent {
                var dict: [String: Any] = [:]
                if !composedBody.isEmpty { dict["coreIdea"] = composedBody }
                let format = form.value(for: .format)
                if !format.isEmpty { dict["contentType"] = format }
                if !dict.isEmpty,
                   let data = try? JSONSerialization.data(withJSONObject: dict),
                   let json = String(data: data, encoding: .utf8) {
                    contentMetadata = json
                }
            }
            let created = try await AtomRepository.shared.create(Atom.new(
                type: draft.kind == .createNote ? .note : .content,
                title: form.value(for: .title),
                body: draft.kind == .createNote && !composedBody.isEmpty ? composedBody : nil,
                metadata: contentMetadata
            ))
            NotificationCenter.default.post(
                name: CosmoNotification.Entity.created,
                object: nil,
                userInfo: ["atom": created, "uuid": created.uuid, "type": created.type.rawValue]
            )
            actionStatusMessage = nil
            setQueryProgrammatically("")
            setPrimaryAction(nil)
            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.openAtomFromCommandK,
                object: nil,
                userInfo: ["atomUUID": created.uuid]
            )
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)

        case .createThinkspace:
            _ = try await AgentToolExecutor.shared.execute(
                toolName: "create_thinkspace",
                arguments: ["title": form.value(for: .title)]
            )
            finishAction()

        default:
            break
        }
    }

    /// Create a task with everything the composer captured — the same
    /// TaskMetadata contract the Command Center detail panel writes: day pins
    /// move together (dueDate/focusDate/whenDate), a recurrence writes rule
    /// JSON + a timezone-safe seriesAnchorDay so the atom IS the series
    /// template, and habit/intent attribution resolves the dashboard's way.
    private func commitComposerTask(_ draft: CommandKComposerDraft) async throws {
        let form = draft.form
        // Quick-add phrases leave the title on save — "Gym tomorrow at 3pm"
        // becomes the task "Gym"; if the whole title was schedule grammar,
        // keep the raw text over an empty name.
        let rawTitle = form.value(for: .title)
        let title = draft.cleanedTitle?.isEmpty == false ? draft.cleanedTitle! : rawTitle

        var metadata = TaskMetadata()
        let priorityRaw = form.value(for: .priority)
        metadata.priority = priorityRaw.isEmpty ? "medium" : priorityRaw

        let intentRaw = form.value(for: .intent)
        let resolvedIntent = TaskIntent(rawValue: intentRaw)
        if let resolvedIntent {
            metadata.intent = resolvedIntent.rawValue
            metadata.intentUUID = CommandCenterIntentEngine.shared.seedID(for: resolvedIntent)
        }

        // One date. All three day pins move together — the separate
        // planned-for facet is gone (July 2026 unification).
        let dueDate = ISO8601.date(from: form.value(for: .date)).map { Calendar.current.startOfDay(for: $0) }
        if let dueDate {
            let iso = PlannerumFormatters.iso8601.string(from: dueDate)
            metadata.dueDate = iso
            metadata.focusDate = iso
            metadata.whenDate = iso
        } else {
            metadata.isUnscheduled = true
        }

        metadata.durationMinutes = draft.durationMinutes
        metadata.timeGoalMinutes = draft.timeGoalMinutes

        // A parsed time of day ("at 3pm") lands the same field the dashboard's
        // scheduledTime edit writes.
        if let time = draft.scheduledTime {
            metadata.startTime = PlannerumFormatters.iso8601.string(from: time)
        }

        if !draft.checklist.isEmpty,
           let data = try? JSONEncoder().encode(draft.checklist),
           let json = String(data: data, encoding: .utf8) {
            metadata.checklist = json
        }

        if let rule = draft.recurrenceRule, let ruleJSON = rule.toJSON() {
            // The atom is born as the series template (recurrence != nil,
            // no recurrenceParentUUID) — mirror createRecurringTemplate.
            metadata.recurrence = ruleJSON
            metadata.isUnscheduled = nil
            let anchor = dueDate ?? Calendar.current.startOfDay(for: .now)
            if metadata.dueDate == nil {
                let iso = PlannerumFormatters.iso8601.string(from: anchor)
                metadata.dueDate = iso
                metadata.focusDate = iso
                metadata.whenDate = iso
            }
            metadata.seriesAnchorDay = RecurringSeriesEngine.dayKey(for: anchor)
        }

        // Habit attribution — same resolution rule as Dashboard.updateTask.
        // A dismissed habit chip means explicit "no habit".
        if draft.suppressHabit {
            metadata.habitAssignmentSource = HabitAssignmentSource.manual.rawValue
        } else if let resolution = CommandCenterHabitEngine.shared.resolveHabit(title: title, intent: resolvedIntent) {
            metadata.habitUUID = resolution.definition.id
            metadata.habitAssignmentSource = resolution.source.rawValue
            if metadata.intentUUID == nil {
                metadata.intentUUID = resolution.definition.defaultIntentUUID
            }
        }

        let notes = form.value(for: .notes)
        var metadataJSON: String?
        if let data = try? JSONEncoder().encode(metadata) {
            metadataJSON = String(data: data, encoding: .utf8)
        }

        _ = try await AtomRepository.shared.create(Atom.new(
            type: .task,
            title: title,
            body: notes.isEmpty ? nil : notes,
            metadata: metadataJSON
        ))
    }

    private func commitComposerIdea(_ draft: CommandKComposerDraft) async throws {
        let form = draft.form
        // Resolve a typed-but-unpicked brand name the scoped grammar's way.
        var clientUUID = draft.clientUUID
        var clientName = form.value(for: .client)
        if clientUUID == nil, !clientName.isEmpty {
            guard let client = try await AtomRepository.shared.fuzzyFindClient(query: clientName) else {
                throw CommandKActionExecutionError.clientNotFound(clientName)
            }
            clientUUID = client.uuid
            clientName = client.title ?? clientName
        }

        let title = form.value(for: .title)
        let body = form.value(for: .body)
        try await createIdeaForClientAtom(
            title: title.isEmpty ? body : title,
            body: body.isEmpty ? nil : body,
            clientUUID: clientUUID,
            clientName: clientName.isEmpty ? nil : clientName,
            captureSource: "command_k_composer",
            contentFormat: form.value(for: .format),
            platform: form.value(for: .platform),
            hooks: draft.hooks,
            context: body,
            outline: draft.outline,
            linkedSwipeUUID: draft.linkedSwipeUUID
        )
    }

    private func finishScopedIdeaCapture() {
        activeTypePrefix = nil
        selectedTypeFilters.removeAll()
        actionStatusMessage = nil
        setQueryProgrammatically("")
        setPrimaryAction(nil)
        userCommandRows = []
        lastSearchedQuery = nil
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
    public func loadRecentsForCompact(ignoringSurface: Bool = false) async {
        guard isSurfaceActive || ignoringSurface else { return }
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
        if item.type == .research, !item.isSwipeFile {
            Task { @MainActor in
                if let target = await Self.researchBrowserTarget(atomUUID: item.id) {
                    openBrowserPaneAfterCommandKDismissal(url: target.url, title: target.title)
                } else {
                    postAtomOpenFromCommandK(item.id)
                }
            }
            return
        }
        postAtomOpenFromCommandK(item.id)
    }

    public func deleteRecent(_ item: RecentDisplayItem) {
        Task {
            try? await AtomRepository.shared.delete(uuid: item.id)
            await MainActor.run {
                recentItems.removeAll { $0.id == item.id }
                refreshDomainPresentation()
                CosmoUndoManager.shared.registerAtomDeletion(
                    uuid: item.id, actionDescription: "Delete Item"
                )
            }
        }
    }

    /// Cached total database atom count (loaded on init)
    public var databaseTotalCount: Int = 0

    /// Whether recents/counts have completed at least one full load (launch
    /// prewarm or a prior open), making the on-open reload a quiet refresh.
    private var hasWarmDomainData = false

    /// Domain item counts for bubbles
    public var domainCounts: [CommandKTab: Int] {
        domainPresentation.counts
    }

    public var deepDiveTotalCount: Int = 0

    private func refreshDomainPresentation() {
        domainPresentation = CommandKDomainPresentation.build(
            databaseTotalCount: databaseTotalCount,
            swipeTotalCount: swipeTotalCount,
            ideaTotalCount: ideaTotalCount,
            deepDiveTotalCount: deepDiveTotalCount,
            swipeItems: swipeGalleryItems,
            ideaItems: ideaGalleryItems,
            readwiseBooks: ReadwiseBookStore.shared.books
        )
    }

    /// Load the total database atom count for bubble display
    private func loadDatabaseCount(ignoringSurface: Bool = false) async {
        guard isSurfaceActive || ignoringSurface else { return }
        do {
            if ThinkspaceManager.shared.thinkspaces.isEmpty {
                await ThinkspaceManager.shared.loadThinkspaces()
            }
            async let databaseAtomCountRequest = AtomRepository.shared.count(types: CommandKLibraryScope.databaseAtomTypes)
            async let swipeCountRequest = AtomRepository.shared.countSwipeFiles()
            async let ideaCountRequest = AtomRepository.shared.count(type: .idea)
            async let deepDiveRequest = InquiryRepository.shared.fetchAllDeepDives()
            let (databaseAtomCount, swipeCount, ideaCount, deepDives) = try await (
                databaseAtomCountRequest,
                swipeCountRequest,
                ideaCountRequest,
                deepDiveRequest
            )
            // Swipe files are research atoms, so they're inside databaseAtomCount;
            // the library bubble excludes them (they have their own domain tab).
            databaseTotalCount = max(0, databaseAtomCount - swipeCount)
                + ThinkspaceManager.shared.sidebarThinkspaces.count
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
                // Stale-while-revalidate: when warm data is already on screen
                // (launch prewarm or a previous open), hold the refresh until
                // the open spring has settled so no @Observable mutation —
                // recents, counts, domain previews — lands mid-animation.
                if hasWarmDomainData {
                    try? await Task.sleep(for: .milliseconds(320))
                    guard isSurfaceActive else { return }
                }
                async let recents: Void = loadRecentsForCompact()
                async let counts: Void = loadDatabaseCount()
                _ = await (recents, counts)
                hasWarmDomainData = true
            }
        }
    }

    /// Warm the search index, recents, and domain counts once at app launch so
    /// the first Command-K open animates over preloaded state instead of
    /// running its initial queries during the open spring.
    public func prewarmForAppLaunch() async {
        guard !hasWarmDomainData else { return }
        prewarmSearchIndexIfNeeded(ignoringSurface: true)
        async let recents: Void = loadRecentsForCompact(ignoringSurface: true)
        async let counts: Void = loadDatabaseCount(ignoringSurface: true)
        _ = await (recents, counts)
        hasWarmDomainData = true
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
        if let date = ISO8601.date(from: timestamp) {
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
        (primaryAction.map { [$0.id] } ?? [])
            + (secondaryAction.map { [$0.id] } ?? [])
            + userCommandRows.map(\.id)
            + unifiedFlatResults.map(\.selectionID)
    }

    func searchSelectionIndex(for selectionID: String) -> Int {
        activeSearchSelectionIDs.firstIndex(of: selectionID) ?? -1
    }

    private func updateActiveSearchSelection(preservingSelection: Bool = false) {
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

        // Background refreshes keep the user's selection (and therefore their
        // scroll position) as long as the selected row still exists.
        if preservingSelection,
           let selectedNodeId,
           let currentIndex = ids.firstIndex(of: selectedNodeId) {
            if selectedResultIndex != currentIndex {
                selectedResultIndex = currentIndex
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
        [.idea, .research, .content, .connection]
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
            // Narrow SQL pre-filter; `isSwipeFileAtom` below stays the authority.
            let researchAtoms = try await AtomRepository.shared.fetchSwipeFileAtoms()

            // Filter to swipe files and convert — several JSON decodes per
            // atom, so the map runs off the main actor (Atom is Sendable).
            let items = await Task.detached(priority: .userInitiated) {
                var items: [SwipeGalleryItem] = []
                for atom in researchAtoms {
                    if atom.isSwipeFileAtom, let galleryItem = atom.toSwipeGalleryItem() {
                        items.append(galleryItem)
                    }
                }
                Self.sortSwipeGalleryItems(&items, by: .recent)
                return items
            }.value

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

    /// Memoizes filtered swipes + clustered sections. Called from `didSet`
    /// on every swipe filter input; coalesces rapid changes (debounced 150ms).
    private func scheduleSwipeFilterRecompute() {
        swipeFilterDebounceTask?.cancel()
        swipeFilterDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self, !Task.isCancelled else { return }
            self.recomputeFilteredSwipes()
        }
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
        if let leftDate = lhs.createdAtDate,
           let rightDate = rhs.createdAtDate,
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

        // Atom data changed — cached query results are stale now, even if
        // Command-K is closed and reopened within the cache TTL.
        Task { await QueryResultCache.shared.clear() }

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
            // Trailing debounce. Sync pulls and agent loops can post one
            // notification per atom; 300ms coalesces near-misses that a
            // 120ms window would re-run the full pipeline for.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, !Task.isCancelled, self.isSurfaceActive else { return }

            await self.loadDatabaseCount()
            self.prewarmSearchIndexIfNeeded(force: true)

            let trimmedQuery = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedQuery.isEmpty {
                if self.cortexMode == .compact {
                    await self.loadRecentsForCompact()
                }
            } else {
                await self.performSearch(
                    query: self.query,
                    isBackgroundRefresh: true,
                    queryGeneration: self.liveQueryGeneration
                )
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
            var items: [IdeaGalleryItem] = []
            for atom in ideaAtoms {
                let clientName = atom.ideaClientUUID.flatMap { clientNameCache[$0] }
                if let galleryItem = atom.toIdeaGalleryItem(clientName: clientName),
                   galleryItem.status != .archived {
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
        captureSource: String? = nil,
        contentFormat: String? = nil,
        platform: String? = nil,
        hooks: [String] = [],
        context: String? = nil,
        outline: [String] = [],
        linkedSwipeUUID: String? = nil
    ) async throws -> Atom {
        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw CommandKActionExecutionError.missingIdeaText }

        let trimmedBody = rawBody?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHooks = hooks.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let trimmedOutline = outline.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let trimmedContext = context?.trimmingCharacters(in: .whitespacesAndNewlines)
        var atom = Atom.new(
            type: .idea,
            title: trimmedTitle,
            body: trimmedBody?.isEmpty == false ? trimmedBody : nil,
            metadata: nil
        )

        let hasRichMetadata = contentFormat?.isEmpty == false || platform?.isEmpty == false
            || !trimmedHooks.isEmpty || trimmedContext?.isEmpty == false || !trimmedOutline.isEmpty
            || linkedSwipeUUID != nil
        if clientUUID != nil || captureSource != nil || hasRichMetadata {
            atom = atom.withUpdatedIdeaMetadata { meta in
                if let clientUUID {
                    meta.clientUUID = clientUUID
                }
                if let clientName, !clientName.isEmpty {
                    meta.clientName = clientName
                }
                if let captureSource {
                    meta.captureSource = captureSource
                }
                // Same field contract the iOS composer writes (AtomCreation.createIdea).
                if let contentFormat, let format = ContentFormat(rawValue: contentFormat) {
                    meta.contentFormat = format
                }
                if let platform, let ideaPlatform = IdeaPlatform(rawValue: platform) {
                    meta.platform = ideaPlatform
                }
                if !trimmedHooks.isEmpty {
                    meta.hooks = trimmedHooks
                }
                if let trimmedContext, !trimmedContext.isEmpty {
                    meta.context = trimmedContext
                }
                // Inspired-by swipe: the iOS AtomCreation field contract.
                if let linkedSwipeUUID {
                    meta.originSwipeUUID = linkedSwipeUUID
                    var ids = meta.linkedSwipeIds ?? []
                    if !ids.contains(linkedSwipeUUID) { ids.append(linkedSwipeUUID) }
                    meta.linkedSwipeIds = ids
                }
                if !trimmedOutline.isEmpty {
                    let model = CodexOutlineModel(
                        arcShape: nil,
                        slides: trimmedOutline.enumerated().map { index, note in
                            CodexOutlineSlide(
                                id: UUID(),
                                position: index + 1,
                                speechAct: nil,
                                readerDeltas: [],
                                frame: nil,
                                distance: nil,
                                techniques: [],
                                transition: nil,
                                note: note
                            )
                        }
                    )
                    if let data = try? JSONEncoder().encode(model),
                       let json = String(data: data, encoding: .utf8) {
                        meta.codexOutline = json
                    }
                }
            }
        }

        if let clientUUID {
            atom = atom.addingLink(.ideaToClient(clientUUID))
        }
        if let linkedSwipeUUID {
            atom = atom.addingLink(.ideaToSwipe(linkedSwipeUUID))
        }

        let created = try await AtomRepository.shared.create(atom)
        insertCreatedIdeaIntoGallery(created, clientName: clientName)

        if let clientUUID,
           var client = try? await AtomRepository.shared.fetch(uuid: clientUUID) {
            client = client.addingLink(.clientToIdea(created.uuid))
            client.updatedAt = ISO8601.string(from: Date())
            client.localVersion += 1
            _ = try? await AtomRepository.shared.update(client)
        }

        // Reverse link on the swipe (idempotent — idea side already linked),
        // mirroring iOS SwipeIdeaLinkService.linkExistingIdea.
        if let linkedSwipeUUID,
           var swipe = try? await AtomRepository.shared.fetch(uuid: linkedSwipeUUID),
           !swipe.linksList.contains(where: { $0.linkType == .swipeToIdea && $0.uuid == created.uuid }) {
            swipe = swipe.addingLink(.swipeToIdea(created.uuid))
            swipe.updatedAt = ISO8601.string(from: Date())
            swipe.localVersion += 1
            _ = try? await AtomRepository.shared.update(swipe)
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

    private func isCurrentSearchRequest(_ requestID: CommandKSearchRequestID?) async -> Bool {
        guard let requestID else { return true }
        return await searchPipeline.isCurrent(requestID)
    }

    /// Publish a fast unified result set from already-loaded local data.
    private func performInstantUnifiedSearch(
        query: String,
        preserveVisibleResultsWhenEmpty: Bool = false,
        preserveSelection: Bool = false,
        searchRequestID: CommandKSearchRequestID? = nil,
        queryGeneration: Int? = nil
    ) async {
        await updateUnifiedSearch(
            query: query,
            preloadSupportData: false,
            // Thinkspaces must be in the FIRST paint: any hit that only
            // arrives in the late enrichment wave gets append-merged under
            // the order lock instead of ranking where it belongs.
            includeThinkspaces: true,
            preserveVisibleResultsWhenEmpty: preserveVisibleResultsWhenEmpty,
            preserveSelection: preserveSelection,
            searchRequestID: searchRequestID,
            queryGeneration: queryGeneration
        )
    }

    /// Perform unified search across all libraries
    func performUnifiedSearch(query: String) async {
        await updateUnifiedSearch(
            query: query,
            preloadSupportData: false,
            includeThinkspaces: true,
            searchRequestID: nil
        )
        scheduleUnifiedSearchEnrichment(for: query, searchRequestID: nil)
    }

    private func scheduleUnifiedSearchEnrichment(
        for query: String,
        preserveSelection: Bool = false,
        searchRequestID: CommandKSearchRequestID? = nil,
        queryGeneration: Int? = nil
    ) {
        unifiedSearchEnrichmentTask?.cancel()
        let expectedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !expectedQuery.isEmpty else { return }

        unifiedSearchEnrichmentTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard let self,
                  !Task.isCancelled,
                  self.isSurfaceActive,
                  self.isCurrentLiveQueryGeneration(queryGeneration),
                  await self.isCurrentSearchRequest(searchRequestID),
                  self.query.trimmingCharacters(in: .whitespaces) == expectedQuery else {
                return
            }

            await self.updateUnifiedSearch(
                query: query,
                preloadSupportData: true,
                includeThinkspaces: true,
                preserveSelection: preserveSelection,
                searchRequestID: searchRequestID,
                queryGeneration: queryGeneration
            )
        }
    }

    private func updateUnifiedSearch(
        query: String,
        preloadSupportData: Bool,
        includeThinkspaces: Bool,
        preserveVisibleResultsWhenEmpty: Bool = false,
        preserveSelection: Bool = false,
        searchRequestID: CommandKSearchRequestID? = nil,
        queryGeneration: Int? = nil
    ) async {
        guard isSurfaceActive,
              isCurrentLiveQueryGeneration(queryGeneration),
              await isCurrentSearchRequest(searchRequestID) else {
            return
        }
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
        guard isCurrentLiveQueryGeneration(queryGeneration),
              await isCurrentSearchRequest(searchRequestID) else {
            return
        }
        if includeThinkspaces, ThinkspaceManager.shared.thinkspaces.isEmpty {
            await ThinkspaceManager.shared.loadThinkspaces()
        }
        guard isCurrentUnifiedSearchRequest(requestID),
              isCurrentLiveQueryGeneration(queryGeneration),
              await isCurrentSearchRequest(searchRequestID) else { return }

        let browserPins = await CosmoBrowserStore.shared.allPins()
        guard isCurrentUnifiedSearchRequest(requestID),
              isCurrentLiveQueryGeneration(queryGeneration),
              await isCurrentSearchRequest(searchRequestID) else { return }

        let output = CommandKUnifiedSearchComposer.buildOutput(
            query: trimmed,
            hybridResults: unfilteredResults,
            swipeGalleryItems: swipeGalleryItems,
            ideaGalleryItems: ideaGalleryItems,
            readwiseBooks: ReadwiseBookStore.shared.books,
            browserPins: browserPins
        )
        guard isCurrentUnifiedSearchRequest(requestID),
              isCurrentLiveQueryGeneration(queryGeneration),
              await isCurrentSearchRequest(searchRequestID) else { return }

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
                    let rank = thinkspaceRelevance(for: item, query: trimmed)
                    return CommandKUnifiedSearchComposer.thinkspaceResult(
                        for: item,
                        relevance: rank.relevance,
                        lexicalTier: rank.tier
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
        guard isCurrentUnifiedSearchRequest(requestID),
              isCurrentLiveQueryGeneration(queryGeneration),
              await isCurrentSearchRequest(searchRequestID) else { return }
        for item in thinkspaceLibraryItems {
            libraryItemsByID[item.uuid] = item
        }

        let enrichedResults = combinedResults.map { result in
            enrichUnifiedSearchResult(result, with: result.libraryLookupKey.flatMap { libraryItemsByID[$0] })
        }
        let regrouped = CommandKUnifiedSearchComposer.regroup(enrichedResults)
        guard isCurrentUnifiedSearchRequest(requestID),
              isCurrentLiveQueryGeneration(queryGeneration),
              await isCurrentSearchRequest(searchRequestID) else { return }

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

        // Order lock: reorders are only allowed while the query is still
        // settling. Once the visible list has been readable past the settle
        // window, later waves merge in place — visible rows keep their
        // positions, genuinely new rows append below (Spotlight contract).
        let orderLocked = hasVisibleUnifiedSearchResults
            && Date().timeIntervalSince(foregroundSearchStartedAt) > resultOrderSettleWindow
        let groupedOutput = orderLocked
            ? CommandKUnifiedSearchComposer.stabilizeOrder(
                visible: unifiedGroupedResults,
                incoming: regrouped.groupedResults
            )
            : regrouped.groupedResults
        let flatOutput = groupedOutput.flatMap(\.results)

        let swipeItemsByUUID = Dictionary(uniqueKeysWithValues: swipeGalleryItems.map { ($0.atomUUID, $0) })
        let cardItems = CommandKUnifiedSearchComposer.buildCardItems(
            flatResults: flatOutput,
            libraryItemsByID: libraryItemsByID,
            swipeItemsByUUID: swipeItemsByUUID
        )

        setUnifiedSearchResults(
            active: true,
            grouped: groupedOutput,
            flat: flatOutput,
            cards: cardItems
        )

        // A locked publish must also keep the user's highlight where it is —
        // Return has to act on the row that was lit when they pressed it.
        updateActiveSearchSelection(preservingSelection: preserveSelection || orderLocked)
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

    private func thinkspaceRelevance(
        for item: LibraryItem,
        query: String
    ) -> (tier: LexicalTier, relevance: Double) {
        let normalizedQuery = CommandKSearchMatcher.normalizeQuery(query)
        let normalizedTitle = CommandKSearchMatcher.normalize(item.title)
        if normalizedTitle == normalizedQuery {
            return (.exactTitle, 0.98)
        }
        if normalizedTitle.hasPrefix(normalizedQuery) {
            return (.titlePrefix, 0.82)
        }
        if normalizedTitle.contains(normalizedQuery) {
            return (.titleMatch, 0.62)
        }
        // Matched via matchesUnifiedLibrarySearch on preview/type text.
        return (.keywordInBody, 0.62)
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
            matchedExcerpt: result.matchedExcerpt,
            icon: result.icon,
            accentColor: item.color,
            relevance: result.relevance,
            lexicalTier: result.lexicalTier,
            atomUUID: result.atomUUID,
            atomType: result.atomType,
            thinkspaceId: result.thinkspaceId ?? (item.kind == .thinkspace ? item.uuid : nil),
            projectUUID: item.projectUUID,
            projectName: item.projectName,
            thinkspaceNames: item.thinkspaceNames,
            readwiseBookId: result.readwiseBookId,
            browserURL: result.browserURL,
            browserTitle: result.browserTitle,
            thumbnailURL: result.thumbnailURL ?? item.thumbnailURL,
            faviconHost: result.faviconHost ?? item.faviconHost
        )
    }

    // MARK: - Cleanup

    /// Clear search state
    public func clear() {
        instantIndexSearchTask?.cancel()
        unifiedSearchEnrichmentTask?.cancel()
        swipeFilterTask?.cancel()
        swipeFilterDebounceTask?.cancel()
        setQueryProgrammatically("")
        lastSearchedQuery = nil
        results = []
        unfilteredResults = []
        filterCounts = [:]
        selectedNodeId = nil
        isActionPanelPresented = false
        resetComposerState()
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
