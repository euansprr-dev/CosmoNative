// CosmoOS/Canvas/Library/ThinkspaceLibraryModels.swift
// Data layer for the Thinkspace Library — the Finder-grade browser.
// Items and folders are derived from canvas blocks + clusters + the stored
// inventory; the preview store hydrates real atom content (body, metadata,
// dates) so every lens renders honest objects with honest provenance.

import SwiftUI

// The space's views (Canvas / Library / Deep Dive …) are `SpaceView` in
// Canvas/Spaces/SpaceModels.swift — per space, persisted, kind-shaped.

// MARK: - Library View Mode (the lenses)

enum ThinkspaceLibraryViewMode: String, CaseIterable, Identifiable, Codable {
    case icons
    case list
    case gallery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .icons: return "Grid"
        case .list: return "List"
        case .gallery: return "Gallery"
        }
    }

    var icon: String {
        switch self {
        case .icons: return "square.grid.2x2"
        case .list: return "list.bullet"
        case .gallery: return "rectangle"
        }
    }
}

// MARK: - Sort & Grouping

enum ThinkspaceLibrarySortField: String, CaseIterable, Identifiable, Codable {
    case name
    case kind
    case dateModified
    case dateAdded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Name"
        case .kind: return "Kind"
        case .dateModified: return "Date Modified"
        case .dateAdded: return "Date Added"
        }
    }

    /// Finder's convention: names ascend by default, dates descend (newest first).
    var defaultAscending: Bool {
        switch self {
        case .name, .kind: return true
        case .dateModified, .dateAdded: return false
        }
    }
}

enum ThinkspaceLibraryGrouping: String, CaseIterable, Identifiable, Codable {
    case none
    case kind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .kind: return "Kind"
        }
    }
}

// MARK: - Icon Scale

enum ThinkspaceLibraryIconScale: String, CaseIterable, Identifiable, Codable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    /// Fixed cell width — uniform cells are the strict-grid contract.
    var cellWidth: CGFloat {
        switch self {
        case .small: return 104
        case .medium: return 140
        case .large: return 188
        }
    }

    /// Fixed object-well height; every object centers inside it, so rows align.
    var wellHeight: CGFloat {
        switch self {
        case .small: return 72
        case .medium: return 104
        case .large: return 148
        }
    }

    var labelFont: Font {
        switch self {
        case .small: return DS.caption
        case .medium: return DS.footnote
        case .large: return DS.callout
        }
    }

    var objectCornerRadius: CGFloat {
        self == .large ? 10 : 8
    }

    var stepUp: ThinkspaceLibraryIconScale? {
        switch self {
        case .small: return .medium
        case .medium: return .large
        case .large: return nil
        }
    }

    var stepDown: ThinkspaceLibraryIconScale? {
        switch self {
        case .small: return nil
        case .medium: return .small
        case .large: return .medium
        }
    }
}

// MARK: - Persisted view preferences (per thinkspace)

struct ThinkspaceLibraryPrefs: Codable, Equatable {
    var viewMode: ThinkspaceLibraryViewMode = .icons
    var iconScale: ThinkspaceLibraryIconScale = .medium
    var sortField: ThinkspaceLibrarySortField = .name
    var sortAscending: Bool = true
    var grouping: ThinkspaceLibraryGrouping = .none

    private static func key(_ thinkspaceId: String) -> String {
        "thinkspace.library.prefs.\(thinkspaceId)"
    }

    static func load(thinkspaceId: String) -> ThinkspaceLibraryPrefs {
        guard let data = UserDefaults.standard.data(forKey: key(thinkspaceId)),
              let prefs = try? JSONDecoder().decode(ThinkspaceLibraryPrefs.self, from: data) else {
            return ThinkspaceLibraryPrefs()
        }
        return prefs
    }

    func save(thinkspaceId: String) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key(thinkspaceId))
    }
}

// MARK: - Models

struct ThinkspaceLibraryItem: Identifiable, Equatable {
    let id: String
    let title: String
    let entityType: EntityType
    let entityId: Int64
    let entityUuid: String
    let isOnCanvas: Bool
    let block: CanvasBlock?
}

struct ThinkspaceLibraryFolder: Identifiable, Equatable {
    let id: UUID
    let title: String
    let colorIndex: Int
    let items: [ThinkspaceLibraryItem]

    var color: Color {
        let index = ((colorIndex % CanvasCluster.palette.count) + CanvasCluster.palette.count) % CanvasCluster.palette.count
        return CanvasCluster.palette[index]
    }

    /// The cluster's emoji identity mark (the App Store register) — folders
    /// carry their owner's identity as a badge, like Finder folder badges.
    var identityEmoji: String? {
        CollectionEmoji.resolve(name: title).emoji
    }

    /// The name with its leading identity mark lifted out — same law as the
    /// sidebar's capture lanes: an emoji typed into the name IS the badge, so
    /// the label sheds it and never prints the mark twice. Keyword-matched
    /// badges leave the name untouched, and `title` stays the editable truth
    /// (rename fields bind to it so the mark remains changeable).
    var displayLabel: String {
        CollectionEmoji.resolve(name: title).label
    }
}

struct ThinkspaceLibrarySnapshot: Equatable {
    let folders: [ThinkspaceLibraryFolder]
    let looseItems: [ThinkspaceLibraryItem]

    /// Every document in the thinkspace, foldered or loose — the search scope
    /// and the Recents shelf both read from here.
    var allItems: [ThinkspaceLibraryItem] {
        var seen: Set<String> = []
        return (looseItems + folders.flatMap(\.items)).filter { seen.insert($0.entityUuid).inserted }
    }

    /// Which folder an item lives in, for provenance columns and search results.
    func folderTitle(for itemID: String) -> String? {
        folders.first { folder in folder.items.contains { $0.id == itemID } }?.title
    }

    static func make(
        blocks: [CanvasBlock],
        clusters: [CanvasCluster],
        inventory: [ChildDoc],
        materialGroups: [SpaceMaterialGroup]? = nil
    ) -> ThinkspaceLibrarySnapshot {
        var itemsByUUID: [String: ThinkspaceLibraryItem] = [:]

        for doc in inventory where !doc.entityUuid.isEmpty {
            itemsByUUID[doc.entityUuid] = ThinkspaceLibraryItem(
                id: doc.entityUuid,
                title: doc.title,
                entityType: doc.entityType,
                entityId: doc.entityId,
                entityUuid: doc.entityUuid,
                isOnCanvas: false,
                block: nil
            )
        }

        for block in blocks where !block.entityUuid.isEmpty {
            itemsByUUID[block.entityUuid] = ThinkspaceLibraryItem(
                id: block.entityUuid,
                title: block.title.isEmpty ? block.entityType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized : block.title,
                entityType: block.entityType,
                entityId: block.entityId,
                entityUuid: block.entityUuid,
                isOnCanvas: true,
                block: block
            )
        }

        let groups = materialGroups ?? clusters.map {
            SpaceMaterialGroup(id: $0.id, name: $0.name, colorIndex: $0.colorIndex, itemUUIDs: $0.blockUUIDs)
        }
        let folders = groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }.map { group in
            ThinkspaceLibraryFolder(id: group.id, title: group.name, colorIndex: group.colorIndex,
                items: group.itemUUIDs.compactMap { itemsByUUID[$0] }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
        }
        let clusteredUUIDs = Set(groups.flatMap(\.itemUUIDs))
        let looseItems = itemsByUUID.values
            .filter { !clusteredUUIDs.contains($0.entityUuid) }
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        return ThinkspaceLibrarySnapshot(folders: folders, looseItems: looseItems)
    }
}

// MARK: - Atom Preview Store

/// Loads the real document behind each library item — body prose, metadata
/// (thumbnails, platform hints), and the atom's dates — so cards render
/// actual content and the browser can sort by real modification times.
@MainActor
@Observable
final class ThinkspaceLibraryPreviewStore {
    struct AtomPreview: Equatable {
        var body: String?
        var metadata: [String: String]
        var updatedAt: Date?
        var createdAt: Date?
        /// A concept's populated board sections, decoded from `atom.structured`
        /// so connection objects render their real manuscript. nil for every
        /// other atom kind.
        var connectionSections: [ConnectionSection]?
        /// The concept's framework type ("Mental Model", …) for the manuscript
        /// masthead's small-caps line.
        var conceptTypeName: String?

        static let empty = AtomPreview(body: nil, metadata: [:], updatedAt: nil, createdAt: nil)
    }

    private(set) var previews: [String: AtomPreview] = [:]
    private var inFlight: Set<String> = []

    func ensureLoaded(_ snapshot: ThinkspaceLibrarySnapshot) {
        let uuids = snapshot.allItems.map(\.entityUuid)
        let missing = uuids.filter { previews[$0] == nil && !inFlight.contains($0) }
        guard !missing.isEmpty else { return }
        inFlight.formUnion(missing)
        Task {
            let atoms = (try? await AtomRepository.shared.fetchBatch(uuids: missing)) ?? []
            var loaded: [String: AtomPreview] = [:]
            for atom in atoms {
                var metadata: [String: String] = [:]
                if let dict = atom.metadataDict {
                    for (key, value) in dict {
                        if let string = value as? String { metadata[key] = string }
                    }
                }
                let body = (atom.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                var connectionSections: [ConnectionSection]?
                var conceptTypeName: String?
                if atom.type == .connection {
                    let structured = atom.structured.flatMap(ConnectionStructuredData.fromJSON)
                    connectionSections = structured?.sections.filter { !$0.items.isEmpty } ?? []
                    conceptTypeName = ConnectionFocusModeState.load(atomUUID: atom.uuid)?.conceptType.displayName
                }
                loaded[atom.uuid] = AtomPreview(
                    body: body.isEmpty ? nil : body,
                    metadata: metadata,
                    updatedAt: ISO8601.date(from: atom.updatedAt),
                    createdAt: ISO8601.date(from: atom.createdAt),
                    connectionSections: connectionSections,
                    conceptTypeName: conceptTypeName
                )
            }
            // Unresolved uuids still get an entry so they aren't refetched forever.
            for uuid in missing {
                previews[uuid] = loaded[uuid] ?? .empty
            }
            inFlight.subtract(missing)
        }
    }

    /// A rename or edit made from the browser stamps the store immediately —
    /// the next snapshot refresh reconciles with the database.
    func touch(uuid: String, date: Date = Date()) {
        previews[uuid]?.updatedAt = date
    }

    func modifiedDate(for uuid: String) -> Date? { previews[uuid]?.updatedAt }
    func addedDate(for uuid: String) -> Date? { previews[uuid]?.createdAt }
}

// MARK: - Card Model

enum ThinkspaceLibraryPreviewKind: Equatable {
    case media(source: String)
    case page(text: String?)
    /// A concept rendered as its manuscript page — real sections from
    /// `atom.structured`, never a mock board.
    case connection(sections: [ConnectionSection], conceptTypeName: String?)
    /// Non-document objects (portals, the live Cosmo block): an object motif
    /// well — a blank white "page" for something that isn't a page reads
    /// broken, not empty.
    case objectMotif(icon: String, tint: Color)
}

/// Everything a lens needs to draw an item, resolved from the canvas block's
/// metadata first and the stored atom second — on-canvas and stored items
/// render the same honest preview of their actual content.
struct ThinkspaceLibraryCardModel {
    let item: ThinkspaceLibraryItem
    let metadata: [String: String]
    let bodyText: String?
    let updatedAt: Date?
    let createdAt: Date?
    let connectionSections: [ConnectionSection]?
    let conceptTypeName: String?

    init(item: ThinkspaceLibraryItem, preview: ThinkspaceLibraryPreviewStore.AtomPreview?) {
        self.item = item
        var merged = preview?.metadata ?? [:]
        if let blockMetadata = item.block?.metadata {
            merged.merge(blockMetadata) { _, fromBlock in fromBlock }
        }
        self.metadata = merged
        let blockText = ((item.block?.metadata["content"]) ?? item.block?.subtitle ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.bodyText = blockText.isEmpty ? preview?.body : blockText
        self.updatedAt = preview?.updatedAt
        self.createdAt = preview?.createdAt
        self.connectionSections = preview?.connectionSections
        self.conceptTypeName = preview?.conceptTypeName
    }

    /// Remote URL or local path for a visual preview; derives YouTube thumbnails from the source URL.
    var thumbnailSource: String? {
        if let thumb = metadata["thumbnail"], !thumb.isEmpty { return thumb }
        if let path = metadata["imagePath"], !path.isEmpty { return path }
        if let videoId = Self.youTubeVideoID(from: metadata["url"]) {
            return "https://img.youtube.com/vi/\(videoId)/hqdefault.jpg"
        }
        return nil
    }

    var previewKind: ThinkspaceLibraryPreviewKind {
        if item.entityType == .connection {
            return .connection(sections: connectionSections ?? [], conceptTypeName: conceptTypeName)
        }
        if let source = thumbnailSource { return .media(source: source) }
        switch item.entityType {
        case .portal:
            return .objectMotif(icon: "rectangle.portrait.on.rectangle.portrait", tint: item.entityType.color)
        case .cosmoAI, .cosmo:
            return .objectMotif(icon: "circle.hexagongrid.circle", tint: DS.gilt)
        default:
            return .page(text: bodyText)
        }
    }

    /// Object aspect ratio (width / height) — videos full 16:9, reels tall,
    /// posts portrait; text documents are always a portrait page.
    var previewAspect: CGFloat {
        switch previewKind {
        case .media: return mediaAspect
        // A concept's manuscript is a page — it stands on the same shelf
        // baseline as every other document.
        case .page, .connection: return 90.0 / 116.0
        case .objectMotif: return 4.0 / 5.0
        }
    }

    private var mediaAspect: CGFloat {
        if item.entityType == .image { return 4.0 / 5.0 }
        let platform = (metadata["platform"] ?? "").lowercased()
        let url = (metadata["url"] ?? "").lowercased()
        if platform.contains("reel") || platform.contains("short") || platform.contains("tiktok") {
            return 9.0 / 16.0
        }
        if url.contains("/shorts/") { return 9.0 / 16.0 }
        if platform.contains("carousel") || platform == "instagram" || platform.contains("instagram_post") {
            return 4.0 / 5.0
        }
        return 16.0 / 9.0
    }

    /// Short kind label for metadata columns — platform when known, entity type otherwise.
    var kindLabel: String {
        let platform = (metadata["platform"] ?? "").lowercased()
        let url = (metadata["url"] ?? "").lowercased()
        if platform.contains("youtube") || url.contains("youtube") || url.contains("youtu.be") { return "YouTube" }
        if platform.contains("instagram") { return "Instagram" }
        if platform.contains("tiktok") { return "TikTok" }
        if platform.contains("twitter") || platform.contains("x_post") { return "X" }
        switch item.entityType {
        case .research: return metadata["isSwipeFile"] == "true" ? "Swipe" : "Research"
        case .stickyNote: return "Sticky Note"
        case .cosmoAI: return "Cosmo"
        default:
            return item.entityType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// The kind mark for icon-territory rows (list view) — identity outranks
    /// type, so media rows show thumbnails and everything else gets its kind
    /// glyph in the entity tint.
    var cosmoIcon: CosmoIcon {
        if item.entityType == .research, metadata["isSwipeFile"] == "true" {
            return .swipe
        }
        return item.entityType.cosmoIcon
    }

    /// True for video-bearing media — gets a small play badge on the object.
    var isVideoMedia: Bool {
        let platform = (metadata["platform"] ?? "").lowercased()
        let url = (metadata["url"] ?? "").lowercased()
        return platform.contains("youtube") || platform.contains("reel") || platform.contains("short")
            || platform.contains("tiktok") || url.contains("youtube") || url.contains("youtu.be")
    }

    static func youTubeVideoID(from urlString: String?) -> String? {
        guard let urlString, !urlString.isEmpty, let url = URL(string: urlString) else { return nil }
        let host = (url.host ?? "").lowercased()
        guard host.contains("youtube.com") || host.contains("youtu.be") else { return nil }
        if host.contains("youtu.be") {
            let id = url.pathComponents.dropFirst().first ?? ""
            return id.isEmpty ? nil : id
        }
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let v = items.first(where: { $0.name == "v" })?.value, !v.isEmpty {
            return v
        }
        let components = url.pathComponents
        if let index = components.firstIndex(where: { $0 == "shorts" || $0 == "embed" }),
           index + 1 < components.count {
            return components[index + 1]
        }
        return nil
    }
}

// MARK: - Actions

/// Everything the library can do to the canvas and store, bundled so the
/// lenses stay declarative. CanvasView owns the implementations.
struct ThinkspaceLibraryActions {
    var openItem: (ThinkspaceLibraryItem) -> Void
    var revealOnCanvas: (ThinkspaceLibraryItem) -> Void
    var fileIntoFolder: (String, UUID) -> Void
    var removeFromFolder: (String, UUID) -> Void
    var renameFolder: (UUID, String) -> Void
    var recolorFolder: (UUID, Int) -> Void
    var deleteFolder: (UUID) -> Void
    /// Rename the document itself (atom title + canvas block title).
    var renameItem: (ThinkspaceLibraryItem, String) -> Void
    /// Delete the document: tombstones the atom (restorable via Recently
    /// Deleted) and removes any canvas block.
    var deleteItem: (ThinkspaceLibraryItem) -> Void
    /// A member without a position (waiting in the tray) gets a spot at the
    /// camera. Optional so older call sites keep compiling.
    var placeOnCanvas: (ThinkspaceLibraryItem) -> Void = { _ in }
    var removeFromSpace: (ThinkspaceLibraryItem) -> Void = { _ in }
    var startInquiry: ([String]) -> Void = { _ in }
}

// MARK: - Sorting

enum ThinkspaceLibrarySorter {
    /// Sorts items by the active field. Date fields read through the preview
    /// store (loaded async from atoms); items without a date sink to the end
    /// regardless of direction, so unresolved rows never float above real data.
    static func sort(
        _ items: [ThinkspaceLibraryItem],
        field: ThinkspaceLibrarySortField,
        ascending: Bool,
        kindLabel: (ThinkspaceLibraryItem) -> String,
        date: (ThinkspaceLibraryItem) -> Date?
    ) -> [ThinkspaceLibraryItem] {
        switch field {
        case .name:
            return items.sorted { lhs, rhs in
                orderedNames(lhs, rhs, ascending: ascending)
            }
        case .kind:
            return items.sorted { lhs, rhs in
                let lhsKind = kindLabel(lhs)
                let rhsKind = kindLabel(rhs)
                if lhsKind != rhsKind {
                    return ascending ? lhsKind < rhsKind : lhsKind > rhsKind
                }
                return orderedNames(lhs, rhs, ascending: true)
            }
        case .dateModified, .dateAdded:
            return items.sorted { lhs, rhs in
                switch (date(lhs), date(rhs)) {
                case let (lhsDate?, rhsDate?):
                    if lhsDate != rhsDate {
                        return ascending ? lhsDate < rhsDate : lhsDate > rhsDate
                    }
                    return orderedNames(lhs, rhs, ascending: true)
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return orderedNames(lhs, rhs, ascending: true)
                }
            }
        }
    }

    private static func orderedNames(
        _ lhs: ThinkspaceLibraryItem,
        _ rhs: ThinkspaceLibraryItem,
        ascending: Bool
    ) -> Bool {
        let comparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
    }
}
