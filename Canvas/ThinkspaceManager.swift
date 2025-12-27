// CosmoOS/Canvas/ThinkspaceManager.swift
// Manages Thinkspaces as saveable Atoms with layout/position data
// December 2025 - Thinkspace-as-Atom architecture

import SwiftUI
import Combine

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

    init(
        name: String = "Untitled Thinkspace",
        lastOpened: Date = Date(),
        zoomLevel: Double = 1.0,
        panOffsetX: Double = 0,
        panOffsetY: Double = 0,
        blockIds: [String] = [],
        projectUuid: String? = nil,
        parentThinkspaceId: String? = nil,
        isRootThinkspace: Bool = false
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
        } else {
            self.name = atom.title ?? "Untitled"
            self.lastOpened = ISO8601DateFormatter().date(from: atom.updatedAt) ?? Date()
            self.blockCount = 0
            self.zoomLevel = 1.0
            self.panOffset = .zero
            self.projectUuid = nil
            self.parentThinkspaceId = nil
            self.isRootThinkspace = false
        }
    }

    static func == (lhs: Thinkspace, rhs: Thinkspace) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Thinkspace Manager

/// Manages Thinkspace CRUD operations and switching
@MainActor
class ThinkspaceManager: ObservableObject {
    static let shared = ThinkspaceManager()

    // MARK: - Published State

    /// All available Thinkspaces
    @Published private(set) var thinkspaces: [Thinkspace] = []

    /// Currently active Thinkspace (nil = default/global canvas)
    @Published private(set) var currentThinkspace: Thinkspace?

    /// Loading state
    @Published private(set) var isLoading = false

    /// Sidebar visibility state - shared for coordinating UI elements
    @Published var isSidebarVisible: Bool = false

    // MARK: - Private Properties

    private let repository = AtomRepository.shared
    private var cancellables = Set<AnyCancellable>()

    // UserDefaults key for last opened Thinkspace
    private let lastThinkspaceKey = "com.cosmo.lastThinkspaceId"

    // MARK: - Initialization

    private init() {
        Task {
            await loadThinkspaces()
            await openLastThinkspace()
        }
    }

    // MARK: - Public API

    /// Load all Thinkspaces from database
    func loadThinkspaces() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let atoms = try await repository.fetchAll(type: .thinkspace)
            thinkspaces = atoms
                .filter { !$0.isDeleted }
                .map { Thinkspace(from: $0) }
                .sorted { $0.lastOpened > $1.lastOpened }

            print("📚 Loaded \(thinkspaces.count) Thinkspaces")
        } catch {
            print("❌ Failed to load Thinkspaces: \(error)")
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
        isRoot: Bool = false
    ) async -> Thinkspace? {
        let metadata = ThinkspaceMetadata(
            name: name,
            projectUuid: projectUuid,
            parentThinkspaceId: parentThinkspaceId,
            isRootThinkspace: isRoot
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

    /// Switch to a Thinkspace
    func switchTo(_ thinkspace: Thinkspace) async {
        // Update last opened time
        await updateLastOpened(thinkspace)

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
            guard var atom = try await repository.fetch(uuid: thinkspace.id) else {
                print("❌ Thinkspace not found for deletion")
                return
            }

            atom.isDeleted = true
            atom.updatedAt = ISO8601DateFormatter().string(from: Date())

            try await repository.update(atom)
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
            guard var atom = try await repository.fetch(uuid: thinkspaceId) else {
                print("❌ Thinkspace not found for soft deletion")
                return
            }

            atom.isDeleted = true
            atom.updatedAt = ISO8601DateFormatter().string(from: Date())

            try await repository.update(atom)
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
            try await repository.hardDelete(uuid: thinkspaceId)
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
            guard var atom = try await repository.fetch(uuid: thinkspace.id) else {
                return
            }

            var metadata = atom.metadataValue(as: ThinkspaceMetadata.self) ?? ThinkspaceMetadata()
            metadata.zoomLevel = zoomLevel
            metadata.panOffsetX = panOffset.width
            metadata.panOffsetY = panOffset.height
            metadata.blockIds = blockIds
            metadata.lastOpened = Date()

            if let metadataJson = try? JSONEncoder().encode(metadata),
               let metadataString = String(data: metadataJson, encoding: .utf8) {
                atom.metadata = metadataString
            }

            atom.updatedAt = ISO8601DateFormatter().string(from: Date())

            try await repository.update(atom)

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

            // Check if it's a root ThinkSpace - cannot unassign
            if let metadata = atom.metadataValue(as: ThinkspaceMetadata.self),
               metadata.isRootThinkspace {
                print("⚠️ Cannot unassign root ThinkSpace from project")
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
            projectUuid: parent.projectUuid,  // Inherit project from parent
            parentThinkspaceId: parent.id,
            isRoot: false
        )
    }

    /// Reparent a ThinkSpace to become a child of another ThinkSpace
    func reparentThinkspace(_ thinkspaceId: String, to newParentId: String?) async {
        do {
            guard var atom = try await repository.fetch(uuid: thinkspaceId) else {
                print("❌ ThinkSpace not found for reparenting")
                return
            }

            // Cannot reparent root ThinkSpaces
            if let metadata = atom.metadataValue(as: ThinkspaceMetadata.self),
               metadata.isRootThinkspace {
                print("⚠️ Cannot reparent root ThinkSpace")
                return
            }

            if var metadata = atom.metadataValue(as: ThinkspaceMetadata.self) {
                // If new parent is specified, inherit its project
                if let newParentId = newParentId,
                   let parentThinkspace = thinkspaces.first(where: { $0.id == newParentId }) {
                    metadata.parentThinkspaceId = newParentId
                    metadata.projectUuid = parentThinkspace.projectUuid
                } else {
                    metadata.parentThinkspaceId = nil
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

    // MARK: - Private Methods

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
