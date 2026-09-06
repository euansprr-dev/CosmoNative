// CosmoOS/UI/Pipeline/PipelineScope.swift
// The Pipeline page's vocabulary: what slice of content is on the table
// (scope), how it is laid out (view), what narrows it (filters), and what a
// drag carries (payload). All pure, all tested — the loader, the board
// snapshot and the drop handlers speak these types and nothing else.
// September 2026

import Foundation

// MARK: - Scope

/// Which content the page holds. `.space` is the Phase 3 hook: content
/// whose block sits on a thinkspace canvas.
enum PipelineScope: Equatable, Hashable, Sendable {
    case all
    case client(uuid: String)
    case unassigned
    case space(thinkspaceId: String)

    var clientUUID: String? {
        if case .client(let uuid) = self { return uuid }
        return nil
    }
}

// MARK: - View

/// The three lenses over one scope (⌘1 / ⌘2 / ⌘3).
enum PipelineView: String, CaseIterable, Identifiable, Sendable {
    case board
    case calendar
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .board: return "Board"
        case .calendar: return "Calendar"
        case .list: return "List"
        }
    }

    var icon: String { cosmoIcon.systemName }

    var cosmoIcon: CosmoIcon {
        switch self {
        case .board: return .pipeline
        case .calendar: return .calendar
        case .list: return .system("list.bullet")
        }
    }

    var help: String {
        switch self {
        case .board: return "Board — stages as columns (⌘1)"
        case .calendar: return "Calendar — the month plan (⌘2)"
        case .list: return "List — every piece as a ledger (⌘3)"
        }
    }
}

// MARK: - Filters

/// Narrowing applied to every column and the list alike.
struct PipelineFilters: Equatable, Sendable {
    var platform: SocialPlatform?
    var format: ContentFormat?
    var query: String
    var showArchived: Bool

    init(
        platform: SocialPlatform? = nil,
        format: ContentFormat? = nil,
        query: String = "",
        showArchived: Bool = false
    ) {
        self.platform = platform
        self.format = format
        self.query = query
        self.showArchived = showArchived
    }

    var isEmpty: Bool {
        platform == nil && format == nil && queryTokens.isEmpty
    }

    /// Lowercased whitespace-split search tokens; every token must match,
    /// in any order.
    var queryTokens: [String] {
        query.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    /// The ONE predicate — the loader, the board snapshot and the list all
    /// decide "does this row pass" here. `platform`/`format` are exact
    /// matches when set; the query runs over title + client name.
    func matches(
        title: String,
        clientName: String?,
        platform: SocialPlatform?,
        format: ContentFormat?
    ) -> Bool {
        if let wanted = self.platform, platform != wanted { return false }
        if let wanted = self.format, format != wanted { return false }
        let tokens = queryTokens
        guard !tokens.isEmpty else { return true }
        let haystack = (title + " " + (clientName ?? "")).lowercased()
        return tokens.allSatisfy { haystack.contains($0) }
    }
}

// MARK: - Drop payload

/// What a drag onto a board column or calendar day carries.
///
/// LAW (UpcomingDropActions.swift): three vocabularies share the `String`
/// drop channel — `ContentShelfPayload` reads a bare string as CONTENT,
/// the sidebar and Today spine read one as a TASK uuid. Only a prefixed
/// payload is ours; a bare uuid is refused so another destination can
/// have it. Wire format is identical to `ContentShelfPayload.dragString`
/// ("idea:<uuid>" / "content:<uuid>") so board↔calendar drags need no
/// adapters.
enum PipelineDropPayload: Equatable, Hashable, Sendable {
    case idea(String)
    case content(String)

    static let ideaPrefix = "idea:"
    static let contentPrefix = "content:"

    /// Prefixed only; a non-empty uuid is required. Bare uuids → nil.
    static func parse(_ raw: String) -> PipelineDropPayload? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let uuid = trimmed.pipelineRemovingPrefix(ideaPrefix), !uuid.isEmpty {
            return .idea(uuid)
        }
        if let uuid = trimmed.pipelineRemovingPrefix(contentPrefix), !uuid.isEmpty {
            return .content(uuid)
        }
        return nil
    }

    /// A multi-select drag carries every piece in ONE provider, one payload
    /// per line — SwiftUI's `onDrag` hands over a single item, and the drop
    /// side has always received `[String]`. Readers split lines first, so a
    /// single-line payload behaves exactly as before.
    static let batchSeparator = "\n"

    static func batchDragString(_ payloads: [PipelineDropPayload]) -> String {
        payloads.map(\.dragString).joined(separator: batchSeparator)
    }

    /// Every recognised payload in a drop, in order, across providers and lines.
    static func all(in payloads: [String]) -> [PipelineDropPayload] {
        payloads.flatMap { $0.components(separatedBy: batchSeparator) }.compactMap(parse)
    }

    /// First recognised payload in a multi-item drop.
    static func first(in payloads: [String]) -> PipelineDropPayload? {
        all(in: payloads).first
    }

    var uuid: String {
        switch self {
        case .idea(let uuid), .content(let uuid): return uuid
        }
    }

    var dragString: String {
        switch self {
        case .idea(let uuid): return Self.ideaPrefix + uuid
        case .content(let uuid): return Self.contentPrefix + uuid
        }
    }
}

private extension String {
    func pipelineRemovingPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
