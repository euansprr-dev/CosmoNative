// CosmoOS/Canvas/ThinkspaceManager.swift
// Manages Thinkspaces as saveable Atoms with layout/position data
// December 2025 - Thinkspace-as-Atom architecture

import SwiftUI
import AppKit
import Combine
import GRDB

// MARK: - Thinkspace Metadata

/// Metadata stored in a Thinkspace atom's metadata JSON
struct ThinkspaceMetadata: Codable, Sendable {
    var name: String
    var lastOpened: Date
    var zoomLevel: Double
    var panOffsetX: Double
    var panOffsetY: Double
    var blockIds: [String]  // UUIDs of blocks in this Thinkspace

    // Project hierarchy (Part 1 of Project System Architecture)
    var projectUuid: String?        // nil = unassigned to any project
    var parentThinkspaceId: String? // nil = root ThinkSpace (no parent)
    var isRootThinkspace: Bool      // true for auto-created project root ThinkSpaces
    var accentColorHex: String?     // Per-Thinkspace folder/glow color

    // Cluster zones (user-created, persistent)
    var clusters: [CodableCluster] = []

    // Inquiry/mastery profile attached one-to-one to this Thinkspace.
    // Older Thinkspaces decode nil and resolve lazily on open.
    var deepDiveProfileUUID: String?

    // Places — named saved camera positions (Cmd+D). Older Thinkspaces decode empty.
    var places: [CanvasPlace] = []

    // Flows — drawn cluster→output behaviors (Living Workflows). Older Thinkspaces decode empty.
    var flows: [CanvasFlow] = []

    // Space shape (September 2026). Stored as RAW strings — never typed enums —
    // so a value from a newer client can't make this whole struct throw on
    // decode (a nil metadata makes every writer rebuild `ThinkspaceMetadata(name:)`
    // and wipe clusters/places/flows). `SpaceViewResolver` interprets them.
    // Older spaces decode nil → the legacy three views, opening on the canvas.
    var kind: String?
    var emoji: String?
    var enabledViews: [String]?
    var defaultView: String?
    var lastView: String?
    var purpose: String? = nil
    var linkedClientUUID: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case name, lastOpened, zoomLevel, panOffsetX, panOffsetY, blockIds
        case projectUuid, parentThinkspaceId, isRootThinkspace, accentColorHex, clusters, deepDiveProfileUUID
        case places, flows
        case kind, emoji, enabledViews, defaultView, lastView, linkedClientUUID, purpose
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        lastOpened = try container.decodeIfPresent(Date.self, forKey: .lastOpened) ?? Date()
        zoomLevel = try container.decodeIfPresent(Double.self, forKey: .zoomLevel) ?? 1
        panOffsetX = try container.decodeIfPresent(Double.self, forKey: .panOffsetX) ?? 0
        panOffsetY = try container.decodeIfPresent(Double.self, forKey: .panOffsetY) ?? 0
        blockIds = try container.decodeIfPresent([String].self, forKey: .blockIds) ?? []
        projectUuid = try container.decodeIfPresent(String.self, forKey: .projectUuid)
        parentThinkspaceId = try container.decodeIfPresent(String.self, forKey: .parentThinkspaceId)
        isRootThinkspace = try container.decodeIfPresent(Bool.self, forKey: .isRootThinkspace) ?? false
        accentColorHex = try container.decodeIfPresent(String.self, forKey: .accentColorHex)
        clusters = try container.decodeIfPresent([CodableCluster].self, forKey: .clusters) ?? []
        deepDiveProfileUUID = try container.decodeIfPresent(String.self, forKey: .deepDiveProfileUUID)
        places = try container.decodeIfPresent([CanvasPlace].self, forKey: .places) ?? []
        flows = try container.decodeIfPresent([CanvasFlow].self, forKey: .flows) ?? []
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji)
        enabledViews = try container.decodeIfPresent([String].self, forKey: .enabledViews)
        defaultView = try container.decodeIfPresent(String.self, forKey: .defaultView)
        lastView = try container.decodeIfPresent(String.self, forKey: .lastView)
        purpose = try container.decodeIfPresent(String.self, forKey: .purpose)
        linkedClientUUID = try container.decodeIfPresent(String.self, forKey: .linkedClientUUID)
    }

    init(
        name: String = "Untitled Thinkspace",
        lastOpened: Date = Date(),
        zoomLevel: Double = 1.0,
        panOffsetX: Double = 0,
        panOffsetY: Double = 0,
        blockIds: [String] = [],
        projectUuid: String? = nil,
        parentThinkspaceId: String? = nil,
        isRootThinkspace: Bool = false,
        accentColorHex: String? = nil,
        clusters: [CodableCluster] = [],
        deepDiveProfileUUID: String? = nil,
        places: [CanvasPlace] = [],
        flows: [CanvasFlow] = [],
        kind: String? = nil,
        emoji: String? = nil,
        enabledViews: [String]? = nil,
        defaultView: String? = nil,
        lastView: String? = nil,
        linkedClientUUID: String? = nil,
        purpose: String? = nil
    ) {
        self.name = name
        self.lastOpened = lastOpened
        self.zoomLevel = zoomLevel
        self.panOffsetX = panOffsetX
        self.panOffsetY = panOffsetY
        self.blockIds = blockIds
        self.projectUuid = projectUuid
        self.parentThinkspaceId = parentThinkspaceId
        self.isRootThinkspace = isRootThinkspace
        self.accentColorHex = accentColorHex
        self.clusters = clusters
        self.deepDiveProfileUUID = deepDiveProfileUUID
        self.places = places
        self.flows = flows
        self.kind = kind
        self.emoji = emoji
        self.enabledViews = enabledViews
        self.defaultView = defaultView
        self.lastView = lastView
        self.purpose = purpose
        self.linkedClientUUID = linkedClientUUID
    }
}

/// The seven metadata keys a Space settings edit owns. Written with
/// `Atom.mergingMetadataKeys` so every other key in the blob — clusters,
/// places, flows, and anything the iPhone wrote that the Mac doesn't know —
/// survives untouched (the key-level merge law).
struct SpaceShapeMetadataPatch: Encodable, Sendable {
    var name: String
    var kind: String
    var emoji: String?
    var enabledViews: [String]
    var defaultView: String
    var parentThinkspaceId: String?
    var accentColorHex: String
    var purpose: String? = nil
    var linkedClientUUID: String?
}

// MARK: - Thinkspace Model

/// A Thinkspace is a saved canvas configuration
struct Thinkspace: Identifiable, Equatable {
    let id: String  // UUID from the Atom
    var name: String
    var lastOpened: Date
    var blockCount: Int
    var zoomLevel: Double
    var panOffset: CGSize

    // Project hierarchy
    var projectUuid: String?
    var parentThinkspaceId: String?
    var isRootThinkspace: Bool
    var accentColorHex: String?
    var deepDiveProfileUUID: String?

    // Space shape — resolved from the raw metadata strings (never nil-fragile).
    var kind: SpaceKind?
    var emoji: String?
    /// Never empty: legacy spaces resolve to the three classic views.
    var enabledViews: [SpaceView]
    var defaultView: SpaceView?
    var lastView: SpaceView?
    var purpose: String? = nil
    var linkedClientUUID: String?

    /// Whether this Thinkspace is assigned to a project
    var isAssigned: Bool { projectUuid != nil }

    /// Whether this Thinkspace has child ThinkSpaces (computed at load time)
    var hasChildren: Bool = false

    init(from atom: Atom) {
        self.id = atom.uuid

        // Parse metadata
        if let metadata = atom.metadataValue(as: ThinkspaceMetadata.self) {
            self.name = metadata.name
            self.lastOpened = metadata.lastOpened
            self.blockCount = metadata.blockIds.count
            self.zoomLevel = metadata.zoomLevel
            self.panOffset = CGSize(width: metadata.panOffsetX, height: metadata.panOffsetY)
            self.projectUuid = metadata.projectUuid
            self.parentThinkspaceId = metadata.parentThinkspaceId
            self.isRootThinkspace = metadata.isRootThinkspace
            self.accentColorHex = metadata.accentColorHex
            self.deepDiveProfileUUID = metadata.deepDiveProfileUUID
            let kind = metadata.kind.flatMap(SpaceKind.init(rawValue:))
            self.kind = kind
            self.emoji = metadata.emoji
            self.enabledViews = SpaceViewResolver.enabledViews(raw: metadata.enabledViews, kind: kind)
            self.defaultView = metadata.defaultView.flatMap(SpaceView.init(rawValue:))
            self.lastView = metadata.lastView.flatMap(SpaceView.init(rawValue:))
            self.purpose = metadata.purpose
            self.linkedClientUUID = metadata.linkedClientUUID
        } else {
            self.name = atom.title ?? "Untitled"
            self.lastOpened = ISO8601.date(from: atom.updatedAt) ?? Date()
            self.blockCount = 0
            self.zoomLevel = 1.0
            self.panOffset = .zero
            self.projectUuid = nil
            self.parentThinkspaceId = nil
            self.isRootThinkspace = false
            self.accentColorHex = nil
            self.deepDiveProfileUUID = nil
            self.kind = nil
            self.emoji = nil
            self.enabledViews = SpaceView.legacyDefault
            self.defaultView = nil
            self.lastView = nil
            self.linkedClientUUID = nil
        }
    }

    static func == (lhs: Thinkspace, rhs: Thinkspace) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.purpose == rhs.purpose &&
        lhs.projectUuid == rhs.projectUuid &&
        lhs.parentThinkspaceId == rhs.parentThinkspaceId &&
        lhs.accentColorHex == rhs.accentColorHex &&
        lhs.blockCount == rhs.blockCount &&
        lhs.deepDiveProfileUUID == rhs.deepDiveProfileUUID &&
        lhs.kind == rhs.kind &&
        lhs.emoji == rhs.emoji &&
        lhs.enabledViews == rhs.enabledViews &&
        lhs.defaultView == rhs.defaultView &&
        lhs.lastView == rhs.lastView &&
        lhs.linkedClientUUID == rhs.linkedClientUUID
    }

    var accentColor: Color {
        accentColorHex.map(Color.init(hex:)) ?? DS.accent
    }

    // MARK: Space shape

    /// The views this build can show, in switcher order. Never empty.
    var renderableViews: [SpaceView] { SpaceViewResolver.renderableViews(enabledViews) }

    /// Where the space opens: last visited → preferred → kind → first.
    var openingView: SpaceView {
        SpaceViewResolver.openingView(
            renderable: renderableViews,
            lastRaw: lastView?.rawValue,
            defaultRaw: defaultView?.rawValue,
            kind: kind
        )
    }

    /// The identity mark: an explicit emoji, else the one the name implies
    /// (a typed leading emoji, or a curated keyword match).
    var identityEmoji: String? {
        emoji ?? CollectionEmoji.resolve(name: name).emoji
    }

    /// The name with any leading identity emoji lifted out.
    var identityLabel: String {
        CollectionEmoji.resolve(name: name).label
    }
}

// MARK: - Child Doc Model

/// Lightweight model for displaying canvas blocks inside a thinkspace in the sidebar
struct ChildDoc: Identifiable, Equatable {
    let id: String          // CanvasBlockRecord.id
    let entityType: EntityType
    let entityId: Int64
    let entityUuid: String
    let title: String
    let outlineReferenceCount: Int
}

/// Sidebar/navigation payload for an expanded thinkspace.
struct ThinkspaceNavigationData: Equatable {
    let childThinkspaces: [Thinkspace]
    let blockInventory: [ChildDoc]
}

// MARK: - Thinkspace Navigation Cache Store

/// The sidebar/library navigation caches, split off ThinkspaceManager so a
/// cache fill doesn't invalidate every ThinkspaceManager observer — MainView
/// observes the manager, and these dictionaries change on every inventory
/// fetch (each expanded sidebar row, every library-mode entry). Only views
/// that render cache contents (ThinkspaceSidebar) observe this store.
@MainActor
final class ThinkspaceNavigationCacheStore: ObservableObject {
    static let shared = ThinkspaceNavigationCacheStore()

    /// Cached child docs per thinkspace ID
    @Published private(set) var childDocsCache: [String: [ChildDoc]] = [:]

    /// Cached thinkspace navigation payloads used by the unified sidebar.
    @Published private(set) var navigationCache: [String: ThinkspaceNavigationData] = [:]

    private init() {}

    func store(navigationData: ThinkspaceNavigationData, docs: [ChildDoc], for thinkspaceId: String) {
        navigationCache[thinkspaceId] = navigationData
        childDocsCache[thinkspaceId] = docs
    }

    func invalidate(thinkspaceId: String?) {
        if let id = thinkspaceId {
            childDocsCache.removeValue(forKey: id)
            navigationCache.removeValue(forKey: id)
        } else {
            childDocsCache.removeAll()
            navigationCache.removeAll()
        }
    }
}

// MARK: - Thinkspace Manager

/// Manages Thinkspace CRUD operations and switching
///
/// @Observable (July 2026): consumers hold plain references and SwiftUI
/// tracks only the specific properties each body actually reads — an
/// ObservableObject here re-evaluated MainView's entire body on every
/// published mutation during a thinkspace switch.
@MainActor
@Observable
class ThinkspaceManager {
    static let shared = ThinkspaceManager()

    /// Well-known UUID for the Command Center thinkspace
    static let commandCenterUUID = "00000000-CC00-4000-A000-COMMANDCENTER"

    // MARK: - Observable State

    /// All available Thinkspaces
    private(set) var thinkspaces: [Thinkspace] = []

    /// Currently active Thinkspace (nil = default/global canvas)
    private(set) var currentThinkspace: Thinkspace?

    /// Loading state
    private(set) var isLoading = false

    /// Non-reactive forwarding accessors — reactive readers observe
    /// ThinkspaceNavigationCacheStore.shared directly.
    var childDocsCache: [String: [ChildDoc]] { ThinkspaceNavigationCacheStore.shared.childDocsCache }
    var navigationCache: [String: ThinkspaceNavigationData] { ThinkspaceNavigationCacheStore.shared.navigationCache }

    /// Sidebar visibility state - shared for coordinating UI elements
    var isSidebarVisible: Bool = false

    // MARK: - Private Properties

    @ObservationIgnored private let repository = AtomRepository.shared
    @ObservationIgnored private let database = CosmoDatabase.shared
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    /// Deferred per-switch bookkeeping (Deep Dive profile warm-up + recency
    /// persistence). Owned by the manager — deliberately unstructured so the
    /// caller's cancelled navigation task can't drop the recency write.
    @ObservationIgnored private var deferredSwitchBookkeepingTask: Task<Void, Never>?

    static let accentColorPalette: [String] = [
        "#2D6A4F", "#4A7B9D", "#C7623F", "#8B6BAB",
        "#B08C5A", "#4A8B72", "#B06B6B", "#5B84B0"
    ]

    // UserDefaults key for last opened Thinkspace
    private let lastThinkspaceKey = "com.cosmo.lastThinkspaceId"

    // MARK: - Initialization

    private init() {
        Task {
            await ensureCommandCenterExists()
            await migrateLegacyProjectsIfNeeded()
            await loadThinkspaces()
            await openLastThinkspace()
        }
    }

    private func nextAccentColorHex() -> String {
        let usedColors = Set(thinkspaces.compactMap(\.accentColorHex))
        return Self.accentColorPalette.first { !usedColors.contains($0) }
            ?? Self.accentColorPalette[thinkspaces.count % Self.accentColorPalette.count]
    }

    /// The colour a new space would receive — the composer shows it preselected.
    func suggestedAccentColorHex() -> String {
        nextAccentColorHex()
    }

    /// One in-flight Deep Dive profile resolution per space. `resolveDeepDiveProfile`
    /// both CREATES the profile atom on first visit and WRITES the thinkspace atom,
    /// so two concurrent callers (the switch bookkeeping and the embedded Deep Dive
    /// view) must share one task or they would mint two profiles.
    @ObservationIgnored private var profileResolutionTasks: [String: Task<String?, Never>] = [:]

    private func migrateLegacyProjectsIfNeeded() async {
        do {
            try await repository.migrateProjectsToThinkspaces()
        } catch {
            print("❌ Failed to migrate legacy projects: \(error)")
        }
    }

    // MARK: - Public API

    /// Load all Thinkspaces from database
    func loadThinkspaces() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let atoms = try await repository.fetchAll(type: .thinkspace)
            var loaded = atoms
                .filter { !$0.isDeleted }
                .map { Thinkspace(from: $0) }
                .sorted { $0.lastOpened > $1.lastOpened }

            // Query real block counts from canvas_blocks table
            let realCounts = await fetchRealBlockCounts()
            for i in loaded.indices {
                loaded[i].blockCount = realCounts[loaded[i].id] ?? 0
            }

            let parentIds = Set(loaded.compactMap(\.parentThinkspaceId))
            for i in loaded.indices {
                loaded[i].hasChildren = parentIds.contains(loaded[i].id)
            }

            thinkspaces = loaded

            // Invalidate child docs cache so expanded thinkspaces refresh
            invalidateChildDocsCache()

            print("📚 Loaded \(thinkspaces.count) Thinkspaces")
        } catch {
            print("❌ Failed to load Thinkspaces: \(error)")
        }
    }

    /// Thinkspaces visible in the sidebar (excludes Command Center)
    var sidebarThinkspaces: [Thinkspace] {
        thinkspaces.filter { $0.id != Self.commandCenterUUID }
    }

    /// The thinkspace id persisted by the last `switchTo` — the space the user
    /// is most likely to open first this session. Used by the launch prewarm.
    var persistedLastThinkspaceId: String? {
        UserDefaults.standard.string(forKey: lastThinkspaceKey)
    }

    /// Ensure the Command Center thinkspace exists in the database.
    /// Auto-creates it with the unified dashboard zone on first launch.
    /// Migrates existing users from the old 4-zone layout to the single dashboard.
    func ensureCommandCenterExists() async {
        do {
            if let existing = try await repository.fetch(uuid: Self.commandCenterUUID),
               !existing.isDeleted {
                // Existing CC — check if it needs migration from legacy 4-zone layout
                await migrateCommandCenterIfNeeded(existing)
                return
            }

            // New user — create single dashboard zone
            let dashboardZone = makeDashboardCluster()

            let metadata = ThinkspaceMetadata(
                name: "Command Center",
                zoomLevel: 0.55,
                clusters: [dashboardZone]
            )

            guard let metadataJson = try? JSONEncoder().encode(metadata),
                  let metadataString = String(data: metadataJson, encoding: .utf8) else {
                return
            }

            var atom = Atom.new(
                type: .thinkspace,
                title: "Command Center",
                metadata: metadataString
            )
            atom.uuid = Self.commandCenterUUID

            _ = try await repository.create(atom)
            print("🏠 Created Command Center thinkspace")
        } catch {
            print("❌ Failed to ensure Command Center: \(error)")
        }
    }

    /// Build the single unified dashboard cluster
    private func makeDashboardCluster() -> CodableCluster {
        let zoneType = CommandCenterZoneType.dashboard
        let size = zoneType.defaultSize
        let pos = zoneType.defaultPosition
        return CodableCluster(
            id: UUID().uuidString,
            name: zoneType.displayName,
            blockUUIDs: [],
            colorIndex: 0,
            originX: Double(pos.x - size.width / 2),
            originY: Double(pos.y - size.height / 2),
            rectWidth: Double(size.width),
            rectHeight: Double(size.height),
            manualWidth: Double(size.width),
            manualHeight: Double(size.height),
            isZone: true,
            zoneType: zoneType.rawValue
        )
    }

    /// Migrate from legacy 4-zone layout to single dashboard zone
    private func migrateCommandCenterIfNeeded(_ atom: Atom) async {
        guard let metadataString = atom.metadata,
              let metadataData = metadataString.data(using: .utf8),
              var metadata = try? JSONDecoder().decode(ThinkspaceMetadata.self, from: metadataData) else {
            return
        }

        // Check if any legacy zone types exist
        let hasLegacyZones = metadata.clusters.contains { cluster in
            CommandCenterZoneType.legacyZoneTypes.contains(cluster.zoneType ?? "")
        }

        // Check if dashboard zone already exists
        let hasDashboard = metadata.clusters.contains { $0.zoneType == "dashboard" }

        guard hasLegacyZones && !hasDashboard else { return }

        // Replace legacy zones with single dashboard
        metadata.clusters.removeAll { cluster in
            CommandCenterZoneType.legacyZoneTypes.contains(cluster.zoneType ?? "")
        }
        metadata.clusters.append(makeDashboardCluster())
        metadata.zoomLevel = 0.55

        // Save updated metadata
        guard let newMetadataJson = try? JSONEncoder().encode(metadata),
              let newMetadataString = String(data: newMetadataJson, encoding: .utf8) else {
            return
        }

        var updatedAtom = atom
        updatedAtom.metadata = metadata.mergedJSON(into: atom.metadata)

        do {
            try await repository.update(updatedAtom)
            print("🔄 Migrated Command Center to unified dashboard")
        } catch {
            print("❌ Failed to migrate Command Center: \(error)")
        }
    }

    /// Switch to the Command Center thinkspace
    func switchToCommandCenter() async {
        do {
            if let atom = try await repository.fetch(uuid: Self.commandCenterUUID) {
                let ts = Thinkspace(from: atom)
                await switchTo(ts)
            }
        } catch {
            print("❌ Failed to switch to Command Center: \(error)")
        }
    }

    /// Create a new Thinkspace
    /// - Parameters:
    ///   - name: Display name for the Thinkspace
    ///   - projectUuid: Optional project to assign this Thinkspace to
    ///   - parentThinkspaceId: Optional parent Thinkspace (for sub-ThinkSpaces)
    ///   - isRoot: Whether this is a root ThinkSpace for a project
    @discardableResult
    func createThinkspace(
        name: String,
        projectUuid: String? = nil,
        parentThinkspaceId: String? = nil,
        isRoot: Bool = false,
        accentColorHex: String? = nil
    ) async -> Thinkspace? {
        // Title-only callers (⌘K, the agent, the Inbox) get the legacy shape:
        // today's three views, opening on the canvas.
        let draft = SpaceDraft.programmaticDefault(
            name: name,
            parentId: parentThinkspaceId,
            accentHex: accentColorHex ?? nextAccentColorHex()
        )
        return await createThinkspace(draft: draft, projectUuid: projectUuid, isRoot: isRoot)
    }

    /// Create a space from a composer draft — kind, emoji, views, colour, parent.
    @discardableResult
    func createThinkspace(
        draft rawDraft: SpaceDraft,
        projectUuid: String? = nil,
        isRoot: Bool = false
    ) async -> Thinkspace? {
        let draft = rawDraft.normalized()
        guard !draft.name.isEmpty else { return nil }
        let metadata = ThinkspaceMetadata(
            name: draft.name,
            projectUuid: projectUuid,
            parentThinkspaceId: draft.parentThinkspaceId,
            isRootThinkspace: isRoot,
            accentColorHex: draft.accentColorHex,
            kind: draft.kind.rawValue,
            emoji: draft.emoji,
            enabledViews: draft.enabledViews.map(\.rawValue),
            defaultView: draft.defaultView.rawValue,
            linkedClientUUID: draft.linkedClientUUID,
            purpose: draft.purpose
        )

        guard let metadataJson = try? JSONEncoder().encode(metadata),
              let metadataString = String(data: metadataJson, encoding: .utf8) else {
            print("❌ Failed to encode Thinkspace metadata")
            return nil
        }

        let atom = Atom.new(
            type: .thinkspace,
            title: draft.name,
            metadata: metadataString
        )

        do {
            let savedAtom = try await repository.create(atom)
            await loadThinkspaces()

            // Find and return the new Thinkspace
            if let newThinkspace = thinkspaces.first(where: { $0.id == savedAtom.uuid }) {
                let context = isRoot ? " (root)" : projectUuid != nil ? " (assigned)" : ""
                print("✨ Created Space: \(draft.name) [\(draft.kind.rawValue)]\(context)")
                return newThinkspace
            }
        } catch {
            print("❌ Failed to create Thinkspace: \(error)")
        }

        return nil
    }

    /// A deliberate settings edit (name, kind, emoji, views, colour, parent):
    /// full-row update that bumps the version, like `updateColor`. Only the
    /// keys the composer owns are written — `mergingMetadataKeys` keeps
    /// clusters, places, flows and any foreign key intact.
    func updateSpaceSettings(_ thinkspace: Thinkspace, draft rawDraft: SpaceDraft) async {
        let draft = rawDraft.normalized()
        guard !draft.name.isEmpty, !draft.enabledViews.isEmpty else { return }
        if let parent = draft.parentThinkspaceId,
           parent != thinkspace.parentThinkspaceId,
           !canNest(thinkspace.id, under: parent) {
            print("⚠️ Refused to nest \(thinkspace.name) under \(parent): would form a cycle")
            return
        }
        do {
            guard var atom = try await repository.fetch(uuid: thinkspace.id) else {
                print("❌ Thinkspace not found for settings update")
                return
            }
            // The default view is the first enabled one; a remembered last
            // view that is no longer enabled must not keep winning the ladder.
            let patch = SpaceShapeMetadataPatch(
                name: draft.name,
                kind: draft.kind.rawValue,
                emoji: draft.emoji,
                enabledViews: draft.enabledViews.map(\.rawValue),
                defaultView: draft.defaultView.rawValue,
                parentThinkspaceId: draft.parentThinkspaceId,
                accentColorHex: draft.accentColorHex,
                purpose: draft.purpose,
                linkedClientUUID: draft.linkedClientUUID
            )
            atom = atom.mergingMetadataKeys(patch)
            var removals: [String] = []
            if draft.emoji == nil { removals.append("emoji") }
            if draft.parentThinkspaceId == nil { removals.append("parentThinkspaceId") }
            if draft.linkedClientUUID == nil { removals.append("linkedClientUUID") }
            if let last = thinkspace.lastView, !draft.enabledViews.contains(last) {
                removals.append("lastView")
            }
            if !removals.isEmpty { atom = atom.removingMetadataKeys(removals) }
            atom.title = draft.name
            atom.updatedAt = ISO8601.string(from: Date())
            try await repository.update(atom)
            await loadThinkspaces()
            if currentThinkspace?.id == thinkspace.id {
                currentThinkspace = thinkspaces.first { $0.id == thinkspace.id }
            }
            if let refreshed = thinkspaces.first(where: { $0.id == thinkspace.id }) {
                SpaceViewStore.shared.reconcile(refreshed)
            }
            invalidateChildDocsCache()
        } catch {
            print("❌ Failed to update Space settings: \(error)")
        }
    }

    /// Remember the view the user left a space on. Field-level like
    /// `saveCurrentState` — one metadata column, no title churn, no reload
    /// (a reload re-queries block counts and drops the child-doc cache on
    /// every view switch). Patches the in-memory copies instead.
    func updateLastView(_ view: SpaceView, for thinkspaceId: String) async {
        if currentThinkspace?.id == thinkspaceId { currentThinkspace?.lastView = view }
        if let index = thinkspaces.firstIndex(where: { $0.id == thinkspaceId }) {
            thinkspaces[index].lastView = view
        }
        do {
            guard let atom = try await repository.fetch(uuid: thinkspaceId) else { return }
            let merged = atom.mergingMetadataKeys(LastViewPatch(lastView: view.rawValue))
            guard let metadataString = merged.metadata else { return }
            try await repository.updateFields(uuid: thinkspaceId, columns: ["metadata": metadataString])
        } catch {
            print("❌ Failed to save last view: \(error)")
        }
    }

    private struct LastViewPatch: Encodable {
        let lastView: String
    }

    func updateColor(_ thinkspace: Thinkspace, to colorHex: String) async {
        do {
            guard var atom = try await repository.fetch(uuid: thinkspace.id) else {
                print("❌ Thinkspace not found for color update")
                return
            }

            var metadata = atom.metadataValue(as: ThinkspaceMetadata.self) ?? ThinkspaceMetadata(name: thinkspace.name)
            metadata.accentColorHex = colorHex
            atom.metadata = metadata.mergedJSON(into: atom.metadata)

            try await repository.update(atom)
            await loadThinkspaces()

            if currentThinkspace?.id == thinkspace.id {
                currentThinkspace = self.thinkspaces.first { $0.id == thinkspace.id }
            }
        } catch {
            print("❌ Failed to update Thinkspace color: \(error)")
        }
    }

    /// Switch to a Thinkspace
    func switchTo(_ thinkspace: Thinkspace) async {
        guard !Task.isCancelled else { return }
        currentThinkspace = thinkspace

        // Save as last opened
        UserDefaults.standard.set(thinkspace.id, forKey: lastThinkspaceKey)

        // Post notification for CanvasView to load blocks
        NotificationCenter.default.post(
            name: CosmoNotification.Canvas.thinkspaceChanged,
            object: nil,
            userInfo: ["thinkspaceId": thinkspace.id]
        )

        print("🔄 Switched to Thinkspace: \(thinkspace.name)")

        // Bookkeeping trails the switch animation entirely (~700ms): every
        // atoms write wakes canvas observations and the sync pipeline, so the
        // switch window must stay free of DB writes. A superseding switch
        // still persists the pending recency stamp (never lost), it only
        // skips the profile warm-up — consumers resolve profiles on demand
        // via InquiryRepository.
        deferredSwitchBookkeepingTask?.cancel()
        deferredSwitchBookkeepingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self else { return }
            if Task.isCancelled {
                await updateLastOpened(thinkspace)
                return
            }

            // Resolve the Deep Dive profile AFTER publishing the route — it is a
            // DB round-trip that can even create the profile atom on a first
            // visit; navigation must never wait on storage. The uuid is patched
            // in once resolved (nothing reads it synchronously at switch time).
            if thinkspace.id != Self.commandCenterUUID {
                _ = await ensureDeepDiveProfileUUID(for: thinkspace.id)
            }

            // Persist recency after publishing the visible route so navigation does not wait on storage.
            await updateLastOpened(thinkspace)
        }
    }

    /// Resolve (or create) the Deep Dive profile attached to a space, sharing
    /// one in-flight task per space so concurrent callers never race
    /// `createDeepDive` into two profiles. Patches `currentThinkspace` so the
    /// embedded Deep Dive view can read the uuid without a reload.
    @discardableResult
    func ensureDeepDiveProfileUUID(for thinkspaceId: String) async -> String? {
        if let known = currentThinkspace?.id == thinkspaceId ? currentThinkspace?.deepDiveProfileUUID : nil {
            return known
        }
        if let inFlight = profileResolutionTasks[thinkspaceId] {
            return await inFlight.value
        }
        let title = thinkspaces.first(where: { $0.id == thinkspaceId })?.name
            ?? currentThinkspace?.name
            ?? "Thinkspace"
        let task = Task<String?, Never> { @MainActor [weak self] in
            do {
                let profile = try await InquiryRepository.shared.resolveDeepDiveProfile(
                    forThinkspace: thinkspaceId,
                    title: title
                )
                guard let self else { return profile.uuid }
                if currentThinkspace?.id == thinkspaceId,
                   currentThinkspace?.deepDiveProfileUUID != profile.uuid {
                    currentThinkspace?.deepDiveProfileUUID = profile.uuid
                }
                if let index = thinkspaces.firstIndex(where: { $0.id == thinkspaceId }),
                   thinkspaces[index].deepDiveProfileUUID != profile.uuid {
                    thinkspaces[index].deepDiveProfileUUID = profile.uuid
                }
                return profile.uuid
            } catch {
                print("⚠️ Failed to resolve DeepDiveProfile for Thinkspace \(title): \(error)")
                return nil
            }
        }
        profileResolutionTasks[thinkspaceId] = task
        let uuid = await task.value
        profileResolutionTasks[thinkspaceId] = nil
        return uuid
    }

    /// Switch to default/global canvas (no Thinkspace)
    func switchToDefault() {
        currentThinkspace = nil
        UserDefaults.standard.removeObject(forKey: lastThinkspaceKey)

        NotificationCenter.default.post(
            name: CosmoNotification.Canvas.thinkspaceChanged,
            object: nil,
            userInfo: ["thinkspaceId": NSNull()]
        )

        print("🔄 Switched to default canvas")
    }

    /// Rename a Thinkspace
    func rename(_ thinkspace: Thinkspace, to newName: String) async {
        do {
            guard var atom = try await repository.fetch(uuid: thinkspace.id) else {
                print("❌ Thinkspace not found for rename")
                return
            }

            // Update title and metadata
            atom.title = newName

            if var metadata = atom.metadataValue(as: ThinkspaceMetadata.self) {
                metadata.name = newName
                if let metadataJson = try? JSONEncoder().encode(metadata),
                   let metadataString = String(data: metadataJson, encoding: .utf8) {
                    atom.metadata = metadata.mergedJSON(into: atom.metadata)
                }
            }

            atom.updatedAt = ISO8601.string(from: Date())

            try await repository.update(atom)
            try? await InquiryRepository.shared.handleThinkspaceDeleted(thinkspace.id)
            await loadThinkspaces()

            // Update current if it's the one being renamed
            if currentThinkspace?.id == thinkspace.id {
                currentThinkspace = thinkspaces.first { $0.id == thinkspace.id }
            }

            print("✏️ Renamed Thinkspace to: \(newName)")
        } catch {
            print("❌ Failed to rename Thinkspace: \(error)")
        }
    }

    /// Both Space menus use the same native confirmation sheet.
    func confirmDelete(_ thinkspace: Thinkspace) async {
        let alert = NSAlert()
        alert.messageText = "Delete “\(thinkspace.name)”?"
        alert.informativeText = "Keep the contents in your library, or delete them everywhere, including from other spaces. Child spaces are kept unless you delete the contents."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Keep Contents")
        alert.addButton(withTitle: "Delete Contents").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            response = await alert.beginSheetModal(for: window)
        } else {
            response = alert.runModal()
        }
        switch response {
        case .alertFirstButtonReturn: await delete(thinkspace, contents: .keep)
        case .alertSecondButtonReturn: await delete(thinkspace, contents: .delete)
        default: break
        }
    }

    /// Programmatic deletion preserves originals unless explicitly requested.
    func delete(_ thinkspace: Thinkspace, contents: SpaceDeletionService.Contents = .keep) async {
        do {
            let change = try await CosmoDatabase.shared.asyncWrite { db in
                try SpaceDeletionService.delete(thinkspace.id, contents: contents, db: db)
            }
            await SpaceDeletionService.publish(change)
            await loadThinkspaces()
            if let current = currentThinkspace, change.deletedUUIDs.contains(current.id) {
                switchToDefault()
            }
            CosmoUndoManager.shared.register(InlineUndoAction(
                actionDescription: "Delete Space",
                undo: { [weak self] in await self?.applySpaceDeletion(change, undo: true) },
                redo: { [weak self] in await self?.applySpaceDeletion(change, undo: false) }
            ))
        } catch {
            showSpaceDeletionError(error)
        }
    }

    private func applySpaceDeletion(_ change: SpaceDeletionService.Change, undo: Bool) async {
        do {
            try await CosmoDatabase.shared.asyncWrite { db in
                try SpaceDeletionService.apply(change, undo: undo, db: db)
            }
            await SpaceDeletionService.publish(change, undo: undo)
            await loadThinkspaces()
            if !undo, let current = currentThinkspace, change.deletedUUIDs.contains(current.id) { switchToDefault() }
        } catch {
            showSpaceDeletionError(error)
        }
    }

    private func showSpaceDeletionError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t update the space"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    /// Soft delete a Thinkspace by ID
    func softDelete(_ thinkspaceId: String) async {
        do {
            try await repository.delete(uuid: thinkspaceId)
            await loadThinkspaces()

            // Switch to default if deleted current
            if currentThinkspace?.id == thinkspaceId {
                switchToDefault()
            }

            print("🗑️ Soft deleted Thinkspace: \(thinkspaceId)")
        } catch {
            print("❌ Failed to soft delete Thinkspace: \(error)")
        }
    }

    /// Restore a soft-deleted Thinkspace
    func restoreThinkspace(_ thinkspaceId: String) async {
        do {
            guard var atom = try await repository.fetch(uuid: thinkspaceId) else {
                print("❌ Thinkspace not found for restoration")
                return
            }

            atom.isDeleted = false
            atom.updatedAt = ISO8601.string(from: Date())

            try await repository.update(atom)
            await loadThinkspaces()

            print("♻️ Restored Thinkspace: \(thinkspaceId)")
        } catch {
            print("❌ Failed to restore Thinkspace: \(error)")
        }
    }

    /// Permanently delete a Thinkspace (hard delete)
    func permanentlyDelete(_ thinkspaceId: String) async {
        do {
            try await repository.hardDelete(uuid: thinkspaceId, confirmed: true)
            await loadThinkspaces()

            print("🗑️ Permanently deleted Thinkspace: \(thinkspaceId)")
        } catch {
            print("❌ Failed to permanently delete Thinkspace: \(error)")
        }
    }

    /// Save current canvas state to Thinkspace
    func saveCurrentState(
        zoomLevel: Double,
        panOffset: CGSize,
        blockIds: [String]
    ) async {
        guard let thinkspace = currentThinkspace else { return }

        do {
            guard let atom = try await repository.fetch(uuid: thinkspace.id) else {
                return
            }

            var metadata = atom.metadataValue(as: ThinkspaceMetadata.self) ?? ThinkspaceMetadata()
            metadata.zoomLevel = zoomLevel
            metadata.panOffsetX = panOffset.width
            metadata.panOffsetY = panOffset.height
            metadata.blockIds = blockIds
            metadata.lastOpened = Date()

            guard let metadataJson = try? JSONEncoder().encode(metadata),
                  let metadataString = String(data: metadataJson, encoding: .utf8) else { return }

            // Use field-level update — only writes metadata column, avoiding
            // full-row update that bumps version and triggers heavy sync for
            // every viewport change.
            try await repository.updateFields(
                uuid: thinkspace.id,
                columns: ["metadata": metadata.mergedJSON(into: atom.metadata) ?? metadataString]
            )

            print("💾 Saved Thinkspace state")
        } catch {
            print("❌ Failed to save Thinkspace state: \(error)")
        }
    }

    // MARK: - Places (saved camera positions)

    /// Synchronous cache of the open canvas's Places — lets Command-K offer
    /// them without an async fetch. CanvasView refreshes it on load/save.
    /// Deliberately unobserved: its only consumer (the ⌘K action registry)
    /// reads it imperatively, and an observed write here re-rendered UI in
    /// the middle of every thinkspace switch.
    @ObservationIgnored private(set) var currentPlaces: [CanvasPlace] = []

    func updateCurrentPlaces(_ places: [CanvasPlace]) {
        currentPlaces = places
    }

    /// Load the saved Places for a thinkspace.
    func places(for thinkspaceId: String) async -> [CanvasPlace] {
        guard let atom = try? await repository.fetch(uuid: thinkspaceId),
              let metadata = atom.metadataValue(as: ThinkspaceMetadata.self) else {
            return []
        }
        return metadata.places
    }

    // MARK: - Flows (Living Workflows)

    /// Load the saved Flows for a thinkspace.
    func flows(for thinkspaceId: String) async -> [CanvasFlow] {
        guard let atom = try? await repository.fetch(uuid: thinkspaceId),
              let metadata = atom.metadataValue(as: ThinkspaceMetadata.self) else {
            return []
        }
        return metadata.flows
    }

    /// Persist the full Flows list for a thinkspace (field-level metadata update).
    func saveFlows(_ flows: [CanvasFlow], for thinkspaceId: String) async {
        do {
            guard let atom = try await repository.fetch(uuid: thinkspaceId) else { return }
            var metadata = atom.metadataValue(as: ThinkspaceMetadata.self) ?? ThinkspaceMetadata()
            metadata.flows = flows

            guard let metadataJson = try? JSONEncoder().encode(metadata),
                  let metadataString = String(data: metadataJson, encoding: .utf8) else { return }

            try await repository.updateFields(
                uuid: thinkspaceId,
                columns: ["metadata": metadata.mergedJSON(into: atom.metadata) ?? metadataString]
            )
        } catch {
            print("❌ Failed to save Flows: \(error)")
        }
    }

    /// Persist the full Places list for a thinkspace (field-level metadata update).
    func savePlaces(_ places: [CanvasPlace], for thinkspaceId: String) async {
        do {
            guard let atom = try await repository.fetch(uuid: thinkspaceId) else { return }
            var metadata = atom.metadataValue(as: ThinkspaceMetadata.self) ?? ThinkspaceMetadata()
            metadata.places = places

            guard let metadataJson = try? JSONEncoder().encode(metadata),
                  let metadataString = String(data: metadataJson, encoding: .utf8) else { return }

            try await repository.updateFields(
                uuid: thinkspaceId,
                columns: ["metadata": metadata.mergedJSON(into: atom.metadata) ?? metadataString]
            )
        } catch {
            print("❌ Failed to save Places: \(error)")
        }
    }

    /// Get block IDs for a Thinkspace
    func getBlockIds(for thinkspace: Thinkspace) async -> [String] {
        do {
            guard let atom = try await repository.fetch(uuid: thinkspace.id),
                  let metadata = atom.metadataValue(as: ThinkspaceMetadata.self) else {
                return []
            }
            return metadata.blockIds
        } catch {
            print("❌ Failed to get block IDs: \(error)")
            return []
        }
    }

    // MARK: - Project-ThinkSpace Methods

    /// Get all ThinkSpaces assigned to a specific project
    func thinkspacesForProject(_ projectUuid: String) -> [Thinkspace] {
        thinkspaces.filter { $0.projectUuid == projectUuid }
            .sorted { ts1, ts2 in
                // Root ThinkSpaces first, then by lastOpened
                if ts1.isRootThinkspace != ts2.isRootThinkspace {
                    return ts1.isRootThinkspace
                }
                return ts1.lastOpened > ts2.lastOpened
            }
    }

    /// Get all unassigned ThinkSpaces (not linked to any project)
    func unassignedThinkspaces() -> [Thinkspace] {
        thinkspaces.filter { $0.projectUuid == nil }
            .sorted { $0.lastOpened > $1.lastOpened }
    }

    /// Get root-level unassigned ThinkSpaces (no parent, no project)
    func rootUnassignedThinkspaces() -> [Thinkspace] {
        thinkspaces.filter { $0.projectUuid == nil && $0.parentThinkspaceId == nil }
            .sorted { $0.lastOpened > $1.lastOpened }
    }

    /// Get child ThinkSpaces of a parent ThinkSpace
    func childThinkspaces(of parentId: String) -> [Thinkspace] {
        thinkspaces.filter { $0.parentThinkspaceId == parentId }
            .sorted { $0.lastOpened > $1.lastOpened }
    }

    /// Get root-level ThinkSpaces for a project (no parent)
    func rootThinkspacesForProject(_ projectUuid: String) -> [Thinkspace] {
        thinkspaces.filter {
            $0.projectUuid == projectUuid && $0.parentThinkspaceId == nil
        }.sorted { ts1, ts2 in
            if ts1.isRootThinkspace != ts2.isRootThinkspace {
                return ts1.isRootThinkspace
            }
            return ts1.lastOpened > ts2.lastOpened
        }
    }

    /// Assign a ThinkSpace to a project
    func assignThinkspace(_ thinkspaceId: String, to projectUuid: String) async {
        do {
            guard var atom = try await repository.fetch(uuid: thinkspaceId) else {
                print("❌ ThinkSpace not found for assignment")
                return
            }

            if var metadata = atom.metadataValue(as: ThinkspaceMetadata.self) {
                metadata.projectUuid = projectUuid
                metadata.parentThinkspaceId = nil  // Reset parent when assigning to new project
                if let metadataJson = try? JSONEncoder().encode(metadata),
                   let metadataString = String(data: metadataJson, encoding: .utf8) {
                    atom.metadata = metadata.mergedJSON(into: atom.metadata)
                }
            }

            atom.updatedAt = ISO8601.string(from: Date())
            try await repository.update(atom)
            await loadThinkspaces()

            print("📎 Assigned ThinkSpace to project")
        } catch {
            print("❌ Failed to assign ThinkSpace: \(error)")
        }
    }

    /// Unassign a ThinkSpace from its project
    func unassignThinkspace(_ thinkspaceId: String) async {
        do {
            guard var atom = try await repository.fetch(uuid: thinkspaceId) else {
                print("❌ ThinkSpace not found for unassignment")
                return
            }

            if var metadata = atom.metadataValue(as: ThinkspaceMetadata.self) {
                metadata.projectUuid = nil
                metadata.parentThinkspaceId = nil
                if let metadataJson = try? JSONEncoder().encode(metadata),
                   let metadataString = String(data: metadataJson, encoding: .utf8) {
                    atom.metadata = metadata.mergedJSON(into: atom.metadata)
                }
            }

            atom.updatedAt = ISO8601.string(from: Date())
            try await repository.update(atom)
            await loadThinkspaces()

            print("📎 Unassigned ThinkSpace from project")
        } catch {
            print("❌ Failed to unassign ThinkSpace: \(error)")
        }
    }

    /// Create a sub-ThinkSpace as a child of another ThinkSpace
    @discardableResult
    func createSubThinkspace(name: String, parent: Thinkspace) async -> Thinkspace? {
        await createThinkspace(
            name: name,
            parentThinkspaceId: parent.id,
            isRoot: false
        )
    }

    /// Reparent a ThinkSpace to become a child of another ThinkSpace
    func reparentThinkspace(_ thinkspaceId: String, to newParentId: String?) async {
        // Self-nesting guard
        if thinkspaceId == newParentId { return }

        // Circular reference guard
        if let newParentId = newParentId, isDescendant(newParentId, of: thinkspaceId) {
            print("⚠️ Cannot reparent: would create circular reference")
            return
        }

        do {
            guard var atom = try await repository.fetch(uuid: thinkspaceId) else {
                print("❌ ThinkSpace not found for reparenting")
                return
            }

            if var metadata = atom.metadataValue(as: ThinkspaceMetadata.self) {
                if let newParentId = newParentId,
                   thinkspaces.contains(where: { $0.id == newParentId }) {
                    metadata.parentThinkspaceId = newParentId
                    metadata.projectUuid = nil
                } else {
                    metadata.parentThinkspaceId = nil
                    metadata.projectUuid = nil
                }

                if let metadataJson = try? JSONEncoder().encode(metadata),
                   let metadataString = String(data: metadataJson, encoding: .utf8) {
                    atom.metadata = metadata.mergedJSON(into: atom.metadata)
                }
            }

            atom.updatedAt = ISO8601.string(from: Date())
            try await repository.update(atom)
            await loadThinkspaces()

            print("🔄 Reparented ThinkSpace")
        } catch {
            print("❌ Failed to reparent ThinkSpace: \(error)")
        }
    }

    /// Whether `thinkspaceId` may be nested under `newParentId` — rejects
    /// self-nesting and any move that would create a cycle (dropping a parent
    /// into one of its own descendants). Used by the sidebar to decide whether
    /// a drop target should light up. `reparentThinkspace` enforces the same
    /// rules on commit.
    func canNest(_ thinkspaceId: String, under newParentId: String) -> Bool {
        guard thinkspaceId != newParentId else { return false }
        return !isDescendant(newParentId, of: thinkspaceId)
    }

    /// Check if `candidateId` is a descendant of `ancestorId` by walking the parent chain
    private func isDescendant(_ candidateId: String, of ancestorId: String) -> Bool {
        var currentId: String? = candidateId
        var visited = Set<String>()
        while let id = currentId {
            if id == ancestorId { return true }
            if visited.contains(id) { break }  // Break infinite loops from corrupted data
            visited.insert(id)
            currentId = thinkspaces.first(where: { $0.id == id })?.parentThinkspaceId
        }
        return false
    }

    // MARK: - Child Docs

    /// Fetch child docs (canvas blocks) for a thinkspace, joining atoms for fresh titles
    func fetchChildDocs(for thinkspaceId: String) async {
        await fetchNavigationData(for: thinkspaceId)
    }

    /// Fetch child thinkspaces plus block inventory for sidebar/navigation surfaces.
    func fetchNavigationData(for thinkspaceId: String) async {
        do {
            let tsId = thinkspaceId
            let rows: [Row] = try await database.asyncRead { db in
                try Row.fetchAll(db, sql: """
                    SELECT MIN(cb.id) AS id, cb.entity_type, cb.entity_id, cb.entity_uuid,
                           a.metadata AS atom_metadata,
                           COALESCE(a.title, cb.entity_title, 'Untitled') AS live_title
                    FROM canvas_blocks cb
                    LEFT JOIN atoms a ON a.uuid = cb.entity_uuid
                    WHERE cb.thinkspace_id = ? AND cb.is_deleted = 0
                      AND (a.uuid IS NULL OR a.is_deleted = 0)
                    GROUP BY CASE WHEN cb.entity_uuid IS NOT NULL AND cb.entity_uuid != ''
                                 THEN cb.entity_uuid ELSE cb.id END
                    ORDER BY live_title
                """, arguments: [tsId])
            }

            let docs = rows.compactMap { row -> ChildDoc? in
                guard let id: String = row["id"],
                      let entityTypeStr: String = row["entity_type"],
                      let type = EntityType(rawValue: entityTypeStr),
                      let entityId: Int64 = row["entity_id"] else { return nil }
                let entityUuid: String = row["entity_uuid"] ?? ""
                let title: String = row["live_title"] ?? "Untitled"
                let metadata: String? = row["atom_metadata"]
                return ChildDoc(
                    id: id,
                    entityType: type,
                    entityId: entityId,
                    entityUuid: entityUuid,
                    title: title,
                    outlineReferenceCount: Atom.decodeOutlineReferences(from: metadata).count
                )
            }

            let childThinkspaces = childThinkspaces(of: thinkspaceId)
            ThinkspaceNavigationCacheStore.shared.store(
                navigationData: ThinkspaceNavigationData(
                    childThinkspaces: childThinkspaces,
                    blockInventory: docs
                ),
                docs: docs,
                for: thinkspaceId
            )
        } catch {
            print("❌ Failed to fetch child docs: \(error)")
        }
    }

    /// Refresh child docs for a set of expanded thinkspace IDs
    func refreshChildDocs(for thinkspaceIds: Set<String>) async {
        for id in thinkspaceIds {
            await fetchNavigationData(for: id)
        }
    }

    /// Invalidate child docs cache (called after thinkspace data changes)
    func invalidateChildDocsCache(for thinkspaceId: String? = nil) {
        ThinkspaceNavigationCacheStore.shared.invalidate(thinkspaceId: thinkspaceId)
    }

    // MARK: - Private Methods

    /// Query the canvas_blocks table for real block counts per thinkspace
    private func fetchRealBlockCounts() async -> [String: Int] {
        do {
            let rows: [Row] = try await database.asyncRead { db in
                try Row.fetchAll(db, sql: """
                    SELECT thinkspace_id, COUNT(DISTINCT
                        CASE WHEN entity_uuid IS NOT NULL AND entity_uuid != ''
                             THEN entity_uuid ELSE id END
                    ) as block_count
                    FROM canvas_blocks
                    WHERE is_deleted = 0 AND thinkspace_id IS NOT NULL
                    GROUP BY thinkspace_id
                """)
            }

            var counts: [String: Int] = [:]
            for row in rows {
                if let tsId: String = row["thinkspace_id"],
                   let count: Int = row["block_count"] {
                    counts[tsId] = count
                }
            }
            return counts
        } catch {
            print("❌ Failed to fetch real block counts: \(error)")
            return [:]
        }
    }

    private func openLastThinkspace() async {
        guard let lastId = UserDefaults.standard.string(forKey: lastThinkspaceKey),
              let thinkspace = thinkspaces.first(where: { $0.id == lastId }) else {
            return
        }

        await switchTo(thinkspace)
    }

    private func updateLastOpened(_ thinkspace: Thinkspace) async {
        do {
            guard var atom = try await repository.fetch(uuid: thinkspace.id) else {
                return
            }

            if var metadata = atom.metadataValue(as: ThinkspaceMetadata.self) {
                metadata.lastOpened = Date()
                if let metadataJson = try? JSONEncoder().encode(metadata),
                   let metadataString = String(data: metadataJson, encoding: .utf8) {
                    atom.metadata = metadata.mergedJSON(into: atom.metadata)
                }
            }

            atom.updatedAt = ISO8601.string(from: Date())

            try await repository.update(atom)
        } catch {
            print("❌ Failed to update last opened: \(error)")
        }
    }
}

// MARK: - Notification Extension

extension CosmoNotification.Canvas {
    /// Posted when the active Thinkspace changes
    static let thinkspaceChanged = Notification.Name("com.cosmo.canvas.thinkspaceChanged")
}

// MARK: - Time Formatting Extension

extension Thinkspace {
    /// Human-readable time since last opened
    var lastOpenedFormatted: String {
        CosmoDateFormatters.relative.localizedString(for: lastOpened, relativeTo: Date())
    }
}
