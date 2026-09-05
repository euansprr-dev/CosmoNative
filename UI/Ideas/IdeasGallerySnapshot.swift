import Foundation
import GRDB

/// A collection is a lens over the same ideas, never a second filing system.
struct IdeaClientCollection: Identifiable, Sendable {
    let clientUUID: String?
    let name: String
    let activeCount: Int
    let archivedCount: Int
    var id: String { clientUUID ?? "__personal__" }
    var scope: PipelineScope { clientUUID.map { .client(uuid: $0) } ?? .unassigned }
    func count(archived: Bool) -> Int { archived ? archivedCount : activeCount }

    static func load(clients: [(uuid: String, name: String)]) async throws -> [Self] {
        let counts = try await CosmoDatabase.shared.asyncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT COALESCE(CASE WHEN json_valid(metadata) THEN json_extract(metadata, '$.clientUUID') END, '') AS client,
                       MAX(CASE WHEN json_valid(metadata) THEN json_extract(metadata, '$.clientName') END) AS name,
                       SUM(CASE WHEN json_valid(metadata) AND json_extract(metadata, '$.ideaStatus') = 'archived' THEN 0 ELSE 1 END) AS active,
                       SUM(CASE WHEN json_valid(metadata) AND json_extract(metadata, '$.ideaStatus') = 'archived' THEN 1 ELSE 0 END) AS archived
                FROM atoms WHERE type = 'idea' AND is_deleted = 0 GROUP BY client
                """).map { row in
                    (row["client"] as String, row["name"] as String?, row["active"] as Int, row["archived"] as Int)
                }
        }
        let names = Dictionary(uniqueKeysWithValues: clients.map { ($0.uuid, $0.name) })
        var result = counts.filter { !$0.0.isEmpty }.map {
            Self(clientUUID: $0.0, name: names[$0.0] ?? $0.1 ?? "Former client", activeCount: $0.2, archivedCount: $0.3)
        }
        let existing = Set(result.compactMap(\.clientUUID))
        result += clients.filter { !existing.contains($0.uuid) }.map {
            Self(clientUUID: $0.uuid, name: $0.name, activeCount: 0, archivedCount: 0)
        }
        result.sort { $0.name == $1.name ? $0.id < $1.id : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let unnamed = result.filter { $0.name == "Former client" }.count
        if unnamed > 1 {
            var index = 0
            result = result.map { collection in
                guard collection.name == "Former client" else { return collection }
                index += 1
                return Self(clientUUID: collection.clientUUID, name: "Former client \(index)",
                            activeCount: collection.activeCount, archivedCount: collection.archivedCount)
            }
        }
        let personal = counts.first { $0.0.isEmpty }
        result.append(Self(clientUUID: nil, name: "Personal", activeCount: personal?.2 ?? 0, archivedCount: personal?.3 ?? 0))
        return result
    }
}

enum IdeasGallerySort: String, CaseIterable {
    case recent, oldest, title
    var label: String {
        switch self {
        case .recent: return "Recently edited"
        case .oldest: return "Oldest first"
        case .title: return "Title"
        }
    }
}

/// Precomputed once per data/filter/width change; card bodies never group or sort.
struct IdeasGallerySnapshot {
    struct Section: Identifiable {
        let id: String
        let title: String
        let scope: PipelineScope
        let items: [IdeaGalleryItem]
        let total: Int
    }
    struct Shelf: Identifiable {
        let sections: [Section]
        var id: String { sections.first?.id ?? "empty" }
    }
    let sections: [Section]
    let shelves: [Shelf]
    let total: Int
    let columns: Int
    let isOverview: Bool
    var items: [IdeaGalleryItem] { sections.flatMap(\.items) }
    static let empty = Self(sections: [], shelves: [], total: 0, columns: 1, isOverview: false)

    static func columnCount(width: CGFloat) -> Int { max(1, min(5, Int((max(0, width) + 16) / 272))) }

    static func make(items: [IdeaGalleryItem], scope: PipelineScope, collections: [IdeaClientCollection],
                     filters: PipelineFilters, pinnedOnly: Bool, sort: IdeasGallerySort, width: CGFloat) -> Self {
        let columns = columnCount(width: width)
        let matching = items.filter {
            (!pinnedOnly || $0.isPinned) && filters.matches(
                title: [$0.title, $0.body ?? "", $0.context ?? "", $0.hooks.joined(separator: " "), $0.tags.joined(separator: " ")].joined(separator: " "),
                clientName: $0.clientName, platform: $0.platform.flatMap { SocialPlatform(rawValue: $0.rawValue) }, format: $0.contentFormat)
        }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if sort == .title {
                let comparison = $0.title.localizedStandardCompare($1.title)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            }
            if $0.updatedAt == $1.updatedAt { return $0.atomUUID < $1.atomUUID }
            return sort == .oldest ? $0.updatedAt < $1.updatedAt : $0.updatedAt > $1.updatedAt
        }
        let overview = scope == .all && filters.isEmpty && !pinnedOnly
        if !overview {
            return Self(sections: matching.isEmpty ? [] : [Section(id: "__results__", title: "", scope: scope, items: matching, total: matching.count)],
                        shelves: [], total: matching.count, columns: columns, isOverview: false)
        }
        let grouped = Dictionary(grouping: matching) { $0.clientUUID?.isEmpty == false ? $0.clientUUID! : "__personal__" }
        var ordered = collections.filter { grouped[$0.id] != nil }
        let known = Set(ordered.map(\.id))
        // A deleted profile must never make its ideas disappear or masquerade as Personal.
        for id in grouped.keys.sorted() where !known.contains(id) {
            ordered.append(IdeaClientCollection(clientUUID: id == "__personal__" ? nil : id,
                name: grouped[id]?.first?.clientName ?? (id == "__personal__" ? "Personal" : "Former client"), activeCount: 0, archivedCount: 0))
        }
        // Recent activity orders the overview; the navigation rail stays alphabetical.
        // Use every item's edit date, since a years-old pin should not reorder clients.
        if sort != .title {
            let dates = grouped.mapValues { values in
                sort == .oldest ? values.map(\.updatedAt).min() ?? "" : values.map(\.updatedAt).max() ?? ""
            }
            ordered.sort {
                let a = dates[$0.id] ?? "", b = dates[$1.id] ?? ""
                if a == b { return $0.name == $1.name ? $0.id < $1.id : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                return sort == .oldest ? a < b : a > b
            }
        }
        let sections = ordered.map { collection in
            let all = grouped[collection.id] ?? []
            return Section(id: collection.id, title: collection.name, scope: collection.scope,
                           items: Array(all.prefix(columns)), total: all.count)
        }
        let shelves = pack(sections, columns: columns)
        return Self(sections: shelves.flatMap(\.sections), shelves: shelves, total: matching.count, columns: columns, isOverview: true)
    }

    /// Small collections share a shelf instead of leaving most of a wide window blank.
    /// The most recently active collection leads; another small collection can fill its gap.
    private static func pack(_ sections: [Section], columns: Int) -> [Shelf] {
        var remaining = sections
        var shelves: [Shelf] = []
        while !remaining.isEmpty {
            var row = [remaining.removeFirst()]
            var space = columns - row[0].items.count
            while space > 0, let index = remaining.firstIndex(where: { $0.items.count <= space }) {
                let next = remaining.remove(at: index)
                row.append(next)
                space -= next.items.count
            }
            shelves.append(Shelf(sections: row))
        }
        return shelves
    }

    enum Direction { case left, right, up, down }
    func nextID(from id: String?, direction: Direction) -> String? {
        let ids = items.map(\.atomUUID)
        guard !ids.isEmpty else { return nil }
        guard let id, let index = ids.firstIndex(of: id) else { return ids.first }
        switch direction {
        case .left: return ids[max(0, index - 1)]
        case .right: return ids[min(ids.count - 1, index + 1)]
        case .up, .down:
            let rows = isOverview ? shelves.map { $0.sections.flatMap { $0.items.map(\.atomUUID) } } : sections.flatMap { section in
                stride(from: 0, to: section.items.count, by: columns).map {
                    Array(section.items[$0..<min($0 + columns, section.items.count)]).map(\.atomUUID)
                }
            }
            guard let row = rows.firstIndex(where: { $0.contains(id) }), let column = rows[row].firstIndex(of: id) else { return id }
            let target = direction == .up ? max(0, row - 1) : min(rows.count - 1, row + 1)
            return rows[target][min(column, rows[target].count - 1)]
        }
    }

    static func excerpt(for idea: IdeaGalleryItem) -> String? {
        let title = normalized(idea.title)
        for candidate in [idea.context, idea.body] + idea.hooks.map(Optional.some) {
            guard let candidate else { continue }
            // Capture attribution is already represented by the linked source. Only
            // original writing belongs in an idea preview; never show raw URLs here.
            let lines = candidate.components(separatedBy: .newlines).filter { line in
                let lower = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return !["inspired by:", "reference:", "source:"].contains(where: lower.hasPrefix)
            }
            let cleaned = lines.joined(separator: " ")
                .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            let text = normalized(cleaned)
            guard !text.isEmpty, text.caseInsensitiveCompare(title) != .orderedSame else { continue }
            return String(text.prefix(600))
        }
        return nil
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
    }
}
