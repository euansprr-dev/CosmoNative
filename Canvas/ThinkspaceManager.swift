// CosmoOS/Canvas/ThinkspaceManager.swift
// Manages Thinkspaces as saveable Atoms with layout/position data
// December 2025 - Thinkspace-as-Atom architecture

import SwiftUI
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

    enum CodingKeys: String, CodingKey {
        case name, lastOpened, zoomLevel, panOffsetX, panOffsetY, blockIds
        case projectUuid, parentThinkspaceId, isRootThinkspace, accentColorHex, clusters, deepDiveProfileUUID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        lastOpened = try container.decode(Date.self, forKey: .lastOpened)
        zoomLevel = try container.decode(Double.self, forKey: .zoomLevel)
        panOffsetX = try container.decode(Double.self, forKey: .panOffsetX)
        panOffsetY = try container.decode(Double.self, forKey: .panOffsetY)
        blockIds = try container.decode([String].self, forKey: .blockIds)
        projectUuid = try container.decodeIfPresent(String.self, forKey: .projectUuid)
        parentThinkspaceId = try container.decodeIfPresent(String.self, forKey: .parentThinkspaceId)
        isRootThinkspace = try container.decodeIfPresent(Bool.self, forKey: .isRootThinkspace) ?? false
        accentColorHex = try container.decodeIfPresent(String.self, forKey: .accentColorHex)
        clusters = try container.decodeIfPresent([CodableCluster].self, forKey: .clusters) ?? []
        deepDiveProfileUUID = try container.decodeIfPresent(String.self, forKey: .deepDiveProfileUUID)
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
        deepDiveProfileUUID: String? = nil
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
    }
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
        } else {
            self.name = atom.title ?? "Untitled"
            self.lastOpened = ISO8601DateFormatter().date(from: atom.updatedAt) ?? Date()
            self.blockCount = 0
            self.zoomLevel = 1.0
            self.panOffset = .zero
            self.projectUuid = nil
            self.parentThinkspaceId = nil
            self.isRootThinkspace = false
            self.accentColorHex = nil
            self.deepDiveProfileUUID = nil
        }
    }

    static func == (lhs: Thinkspace, rhs: Thinkspace) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.projectUuid == rhs.projectUuid &&
        lhs.parentThinkspaceId == rhs.parentThinkspaceId &&
        lhs.accentColorHex == rhs.accentColorHex &&
        lhs.blockCount == rhs.blockCount &&
        lhs.deepDiveProfileUUID == rhs.deepDiveProfileUUID
    }

    var accentColor: Color {
        accentColorHex.map(Color.init(hex:)) ?? DS.accent
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

// MARK: - Thinkspace Manager

/// Manages Thinkspace CRUD operations and switching
@MainActor
class ThinkspaceManager: ObservableObject {
    static let shared = ThinkspaceManager()

    /// Well-known UUID for the Command Center thinkspace
    static let commandCenterUUID = "00000000-CC00-4000-A000-COMMANDCENTER"

    // MARK: - Published State

    /// All available Thinkspaces
    @Published private(set) var thinkspaces: [Thinkspace] = []

    /// Currently active Thinkspace (nil = default/global canvas)
    @Published private(set) var currentThinkspace: Thinkspace?

    /// Loading state
    @Published private(set) var isLoading = false

    /// Cached child docs per thinkspace ID
    @Published private(set) var childDocsCache: [String: [ChildDoc]] = [:]

    /// Cached thinkspace navigation payloads used by the unified sidebar.
    @Published private(set) var navigationCache: [String: ThinkspaceNavigationData] = [:]

    /// Sidebar visibility state - shared for coordinating UI elements
    @Published var isSidebarVisible: Bool = false

    // MARK: - Private Properties

    private let repository = AtomRepository.shared
    private let database = CosmoDatabase.shared
    private var cancellables = Set<AnyCancellable>()

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
        updatedAtom.metadata = newMetadataString

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
        let metadata = ThinkspaceMetadata(
            name: name,
            projectUuid: projectUuid,
            parentThinkspaceId: parentThinkspaceId,
            isRootThinkspace: isRoot,
            accentColorHex: accentColorHex ?? nextAccentColorHex()
        )

        guard let metadataJson = try? JSONEncoder().encode(metadata),
              let metadataString = String(data: metadataJson, encoding: .utf8) else {
            print("❌ Failed to encode Thinkspace metadata")
            return nil
        }

        let atom = Atom.new(
            type: .thinkspace,
            title: name,
            metadata: metadataString
        )

        do {
            let savedAtom = try await repository.create(atom)
            await loadThinkspaces()

            // Find and return the new Thinkspace
            if let newThinkspace = thinkspaces.first(where: { $0.id == savedAtom.uuid }) {
                let context = isRoot ? " (root)" : projectUuid != nil ? " (assigned)" : ""
                print("✨ Created Thinkspace: \(name)\(context)")
                return newThinkspace
            }
        } catch {
            print("❌ Failed to create Thinkspace: \(error)")
        }

        return nil
    }

    func updateColor(_ thinkspace: Thinkspace, to colorHex: String) async {
        do {
            guard var atom = try await repository.fetch(uuid: thinkspace.id) else {
                print("❌ Thinkspace not found for color update")
                return
            }

            var metadata = atom.metadataValue(as: ThinkspaceMetadata.self) ?? ThinkspaceMetadata(name: thinkspace.name)
            metadata.accentColorHex = colorHex
            atom = atom.withMetadata(metadata)

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
        var resolvedThinkspace = thinkspace
        if thinkspace.id != Self.commandCenterUUID {
            do {
                let profile = try await InquiryRepository.shared.resolveDeepDiveProfile(
                    forThinkspace: thinkspace.id,
                    title: thinkspace.name
                )
                resolvedThinkspace.deepDiveProfileUUID = profile.uuid
            } catch {
                print("⚠️ Failed to resolve DeepDiveProfile for Thinkspace \(thinkspace.name): \(error)")
            }
        }

        // Update last opened time
        await updateLastOpened(resolvedThinkspace)

        currentThinkspace = resolvedThinkspace

        // Save as last opened
        UserDefaults.standard.set(resolvedThinkspace.id, forKey: lastThinkspaceKey)

        // Post notification for CanvasView to load blocks
        NotificationCenter.default.post(
            name: CosmoNotification.Canvas.thinkspaceChanged,
            object: nil,
            userInfo: ["thinkspaceId": resolvedThinkspace.id]
        )

        print("🔄 Switched to Thinkspace: \(resolvedThinkspace.name)")
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
                    atom.metadata = metadataString
                }
            }

            atom.updatedAt = ISO8601DateFormatter().string(from: Date())

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

    /// Delete a Thinkspace (soft delete)
    func delete(_ thinkspace: Thinkspace) async {
        do {
            try await repository.delete(uuid: thinkspace.id)
            try? await InquiryRepository.shared.handleThinkspaceDeleted(thinkspace.id)
            await loadThinkspaces()

            // Switch to default if deleted current
            if currentThinkspace?.id == thinkspace.id {
                switchToDefault()
            }

            print("🗑️ Deleted Thinkspace: \(thinkspace.name)")
        } catch {
            print("❌ Failed to delete Thinkspace: \(error)")
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
            atom.updatedAt = ISO8601DateFormatter().string(from: Date())

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
                columns: ["metadata": metadataString]
            )

            print("💾 Saved Thinkspace state")
        } catch {
            print("❌ Failed to save Thinkspace state: \(error)")
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
                    atom.metadata = metadataString
                }
            }

            atom.updatedAt = ISO8601DateFormatter().string(from: Date())
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
                    atom.metadata = metadataString
                }
            }

            atom.updatedAt = ISO8601DateFormatter().string(from: Date())
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
                    atom.metadata = metadataString
                }
            }

            atom.updatedAt = ISO8601DateFormatter().string(from: Date())
            try await repository.update(atom)
            await loadThinkspaces()

            print("🔄 Reparented ThinkSpace")
        } catch {
            print("❌ Failed to reparent ThinkSpace: \(error)")
        }
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
            navigationCache[thinkspaceId] = ThinkspaceNavigationData(
                childThinkspaces: childThinkspaces,
                blockInventory: docs
            )
            childDocsCache[thinkspaceId] = docs
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
        if let id = thinkspaceId {
            childDocsCache.removeValue(forKey: id)
            navigationCache.removeValue(forKey: id)
        } else {
            childDocsCache.removeAll()
            navigationCache.removeAll()
        }
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
                    atom.metadata = metadataString
                }
            }

            atom.updatedAt = ISO8601DateFormatter().string(from: Date())

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
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastOpened, relativeTo: Date())
    }
}
