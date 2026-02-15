// CosmoOS/Data/Repositories/AtomRepository.swift
// Unified repository for all Atom operations
// Replaces individual repositories (IdeasRepository, TasksRepository, etc.)

import GRDB
import Foundation
import Combine

@MainActor
class AtomRepository: ObservableObject {
    static let shared = AtomRepository()

    private let database = CosmoDatabase.shared
    private let changeTracker = ChangeTracker.shared

    @Published var atoms: [Atom] = []
    @Published var isLoading = false
    @Published var error: String?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        observeAtoms()
    }

    // MARK: - Observation

    private func observeAtoms() {
        guard database.isReady else {
            // Retry once database is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.observeAtoms()
            }
            return
        }

        database.observe { db in
            try Atom
                .filter(Atom.CodingKeys.isDeleted == false)
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchAll(db)
        }
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.error = error.localizedDescription
                }
            },
            receiveValue: { [weak self] atoms in
                self?.atoms = atoms
            }
        )
        .store(in: &cancellables)
    }

    // MARK: - Fetch Operations

    /// Fetch all atoms of a specific type
    func fetchAll(type: AtomType) async throws -> [Atom] {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == type.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchAll(db)
        }
    }

    /// Fetch a single atom by UUID
    func fetch(uuid: String) async throws -> Atom? {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.uuid == uuid)
                .filter(Atom.CodingKeys.isDeleted == false)
                .fetchOne(db)
        }
    }

    /// Fetch a single atom by ID (legacy compatibility)
    func fetch(id: Int64) async throws -> Atom? {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.id == id)
                .filter(Atom.CodingKeys.isDeleted == false)
                .fetchOne(db)
        }
    }

    /// Fetch atoms by type with custom filter
    func fetch(type: AtomType, where predicate: @escaping (Atom) -> Bool) async throws -> [Atom] {
        let all = try await fetchAll(type: type)
        return all.filter(predicate)
    }

    /// Fetch atoms linked to a specific project
    func fetchByProject(projectUuid: String) async throws -> [Atom] {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(sql: "links LIKE ?", arguments: ["%\(projectUuid)%"])
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchAll(db)
        }
    }

    /// Fetch atoms by multiple types
    func fetchAll(types: [AtomType]) async throws -> [Atom] {
        let typeStrings = types.map { $0.rawValue }
        return try await database.asyncRead { db in
            try Atom
                .filter(typeStrings.contains(Column("type")))
                .filter(Atom.CodingKeys.isDeleted == false)
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchAll(db)
        }
    }

    /// Fetch recent atoms (for Command-K hot context)
    /// Returns most recently updated atoms across all user-facing types
    func fetchRecent(limit: Int = 25) async throws -> [Atom] {
        // Only include user-facing atom types (exclude system types)
        let userTypes: [AtomType] = [.idea, .task, .research, .content, .connection, .project, .journalEntry]
        let typeStrings = userTypes.map { $0.rawValue }

        return try await database.asyncRead { db in
            try Atom
                .filter(typeStrings.contains(Column("type")))
                .filter(Atom.CodingKeys.isDeleted == false)
                .order(Atom.CodingKeys.updatedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Search atoms by title or body content (basic keyword search)
    func search(query: String, limit: Int = 50) async throws -> [Atom] {
        let userTypes: [AtomType] = [.idea, .task, .research, .content, .connection, .project, .journalEntry]
        let typeStrings = userTypes.map { $0.rawValue }
        let searchPattern = "%\(query)%"

        return try await database.asyncRead { db in
            try Atom
                .filter(typeStrings.contains(Column("type")))
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(
                    sql: "(title LIKE ? COLLATE NOCASE OR body LIKE ? COLLATE NOCASE)",
                    arguments: [searchPattern, searchPattern]
                )
                .order(Atom.CodingKeys.updatedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Create Operations

    /// Create a new atom
    @discardableResult
    func create(_ atom: Atom) async throws -> Atom {
        var preparedAtom = atom
        preparedAtom.createdAt = ISO8601DateFormatter().string(from: Date())
        preparedAtom.updatedAt = preparedAtom.createdAt

        // Capture prepared atom for Sendable closure
        let atomToInsert = preparedAtom
        let savedAtom = try await database.asyncWrite { db in
            var insertingAtom = atomToInsert
            try insertingAtom.insert(db)
            insertingAtom.id = db.lastInsertedRowID
            return insertingAtom
        }

        // Track for sync
        await changeTracker.trackInsert(table: Atom.databaseTableName, entity: savedAtom)

        // Sync to NodeGraph
        try? await NodeGraphEngine.shared.handleAtomCreated(savedAtom)

        return savedAtom
    }

    /// Create a new atom from type with basic fields
    @discardableResult
    func create(
        type: AtomType,
        title: String? = nil,
        body: String? = nil,
        structured: String? = nil,
        metadata: String? = nil,
        links: [AtomLink]? = nil
    ) async throws -> Atom {
        let atom = Atom.new(
            type: type,
            title: title,
            body: body,
            structured: structured,
            metadata: metadata,
            links: links
        )
        return try await create(atom)
    }

    // MARK: - Update Operations

    /// Update an existing atom
    @discardableResult
    func update(_ atom: Atom) async throws -> Atom {
        var updatedAtom = atom
        updatedAtom.updatedAt = ISO8601DateFormatter().string(from: Date())
        updatedAtom.localVersion += 1

        // Capture for Sendable closure
        let atomToUpdate = updatedAtom
        try await database.asyncWrite { db in
            try atomToUpdate.save(db)
        }

        // Track for sync
        await changeTracker.trackUpdate(table: Atom.databaseTableName, entity: updatedAtom)

        // Sync to NodeGraph
        try? await NodeGraphEngine.shared.handleAtomUpdated(updatedAtom, changedFields: ["title", "body", "links", "metadata"])

        return updatedAtom
    }

    /// Update specific fields of an atom by UUID
    func update(uuid: String, updates: (inout Atom) -> Void) async throws -> Atom? {
        guard var atom = try await fetch(uuid: uuid) else { return nil }
        updates(&atom)
        return try await update(atom)
    }

    // MARK: - Delete Operations

    /// Soft delete an atom by UUID
    func delete(uuid: String) async throws {
        try await database.asyncWrite { db in
            try db.execute(
                sql: """
                UPDATE atoms
                SET is_deleted = 1, updated_at = ?, _local_version = _local_version + 1
                WHERE uuid = ?
                """,
                arguments: [ISO8601DateFormatter().string(from: Date()), uuid]
            )
        }

        // Track for sync
        await changeTracker.trackDelete(table: Atom.databaseTableName, uuid: uuid, rowId: nil)

        // Sync to NodeGraph
        try? await NodeGraphEngine.shared.handleAtomDeleted(atomUUID: uuid)
    }

    /// Soft delete an atom
    func delete(_ atom: Atom) async throws {
        try await delete(uuid: atom.uuid)
    }

    /// Hard delete an atom (use with caution)
    func hardDelete(uuid: String) async throws {
        try await database.asyncWrite { db in
            try db.execute(
                sql: "DELETE FROM atoms WHERE uuid = ?",
                arguments: [uuid]
            )
        }
    }

    /// Soft delete a project (same as regular soft delete)
    func softDeleteProject(_ uuid: String) async throws {
        try await delete(uuid: uuid)
    }

    /// Restore a soft-deleted project
    func restoreProject(_ uuid: String) async throws {
        try await database.asyncWrite { db in
            try db.execute(
                sql: """
                UPDATE atoms
                SET is_deleted = 0, updated_at = ?, _local_version = _local_version + 1
                WHERE uuid = ?
                """,
                arguments: [ISO8601DateFormatter().string(from: Date()), uuid]
            )
        }

        // Track for sync - fetch the updated atom to track properly
        if let restoredAtom = try? await fetch(uuid: uuid) {
            await changeTracker.trackUpdate(table: Atom.databaseTableName, entity: restoredAtom)
        }
    }

    /// Permanently delete a project (hard delete)
    func permanentlyDeleteProject(_ uuid: String) async throws {
        try await hardDelete(uuid: uuid)
    }

    // MARK: - Batch Operations

    /// Create multiple atoms in a single transaction
    func createBatch(_ atoms: [Atom]) async throws -> [Atom] {
        let now = ISO8601DateFormatter().string(from: Date())
        let preparedAtoms = atoms.map { atom -> Atom in
            var a = atom
            a.createdAt = now
            a.updatedAt = now
            return a
        }

        let savedAtoms = try await database.asyncWrite { db -> [Atom] in
            var saved: [Atom] = []
            for atom in preparedAtoms {
                var insertingAtom = atom
                try insertingAtom.insert(db)
                insertingAtom.id = db.lastInsertedRowID
                saved.append(insertingAtom)
            }
            return saved
        }

        // Track for sync
        for atom in savedAtoms {
            await changeTracker.trackInsert(table: Atom.databaseTableName, entity: atom)
        }

        return savedAtoms
    }

    /// Update multiple atoms in a single transaction
    func updateBatch(_ atoms: [Atom]) async throws {
        let now = ISO8601DateFormatter().string(from: Date())

        try await database.asyncWrite { db in
            for var atom in atoms {
                atom.updatedAt = now
                atom.localVersion += 1
                try atom.update(db)
            }
        }

        // Track for sync
        for atom in atoms {
            await changeTracker.trackUpdate(table: Atom.databaseTableName, entity: atom)
        }
    }

    /// Soft delete multiple atoms
    func deleteBatch(uuids: [String]) async throws {
        let now = ISO8601DateFormatter().string(from: Date())

        try await database.asyncWrite { db in
            for uuid in uuids {
                try db.execute(
                    sql: """
                    UPDATE atoms
                    SET is_deleted = 1, updated_at = ?, _local_version = _local_version + 1
                    WHERE uuid = ?
                    """,
                    arguments: [now, uuid]
                )
            }
        }

        // Track for sync
        for uuid in uuids {
            await changeTracker.trackDelete(table: Atom.databaseTableName, uuid: uuid, rowId: nil)
        }
    }

    // MARK: - Search Operations

    /// Search atoms by title/body text
    func search(query: String, types: [AtomType]? = nil) async throws -> [Atom] {
        let pattern = "%\(query)%"

        return try await database.asyncRead { db in
            var request = Atom
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(
                    Column("title").like(pattern) ||
                    Column("body").like(pattern)
                )

            if let types = types {
                let typeStrings = types.map { $0.rawValue }
                request = request.filter(typeStrings.contains(Column("type")))
            }

            return try request
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchAll(db)
        }
    }

    /// Search atoms by metadata field value
    func search(metadataKey: String, value: String, type: AtomType? = nil) async throws -> [Atom] {
        // Use JSON path search
        let pattern = "%\"\(metadataKey)\":\"\(value)\"%"

        return try await database.asyncRead { db in
            var request = Atom
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(sql: "metadata LIKE ?", arguments: [pattern])

            if let type = type {
                request = request.filter(Atom.CodingKeys.type == type.rawValue)
            }

            return try request
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchAll(db)
        }
    }

    // MARK: - Convenience Typed Accessors

    /// Get all ideas
    func ideas() async throws -> [Atom] {
        try await fetchAll(type: .idea)
    }

    /// Get all tasks
    func tasks() async throws -> [Atom] {
        try await fetchAll(type: .task)
    }

    /// Get all projects
    func projects() async throws -> [Atom] {
        try await fetchAll(type: .project)
    }

    /// Get all content
    func content() async throws -> [Atom] {
        try await fetchAll(type: .content)
    }

    /// Get all research
    func research() async throws -> [Atom] {
        try await fetchAll(type: .research)
    }

    /// Get all connections
    func connections() async throws -> [Atom] {
        try await fetchAll(type: .connection)
    }

    /// Get all schedule blocks
    func scheduleBlocks() async throws -> [Atom] {
        try await fetchAll(type: .scheduleBlock)
    }

    /// Get all uncommitted items
    func uncommittedItems() async throws -> [Atom] {
        try await fetchAll(type: .uncommittedItem)
    }
}

// MARK: - Typed Convenience Methods

extension AtomRepository {

    /// Create a new idea atom
    @discardableResult
    func createIdea(title: String?, content: String, tags: [String] = [], projectUuid: String? = nil) async throws -> Atom {
        let metadata = IdeaMetadata(tags: tags, priority: "Medium", isPinned: false, pinnedAt: nil)
        var links: [AtomLink] = []
        if let projectUuid = projectUuid {
            links.append(.project(projectUuid))
        }

        return try await create(
            type: .idea,
            title: title,
            body: content,
            metadata: try? String(data: JSONEncoder().encode(metadata), encoding: .utf8),
            links: links.isEmpty ? nil : links
        )
    }

    /// Create a new task atom
    @discardableResult
    func createTask(title: String, status: String = "todo", projectUuid: String? = nil) async throws -> Atom {
        let metadata = TaskMetadata(status: status, priority: "medium")
        var links: [AtomLink] = []
        if let projectUuid = projectUuid {
            links.append(.project(projectUuid))
        }

        return try await create(
            type: .task,
            title: title,
            metadata: try? String(data: JSONEncoder().encode(metadata), encoding: .utf8),
            links: links.isEmpty ? nil : links
        )
    }

    /// Create a new project atom with auto-created root ThinkSpace
    /// Part 3 of Project System Architecture - every project gets a root ThinkSpace
    @discardableResult
    func createProject(title: String, description: String? = nil, color: String = "#8B5CF6") async throws -> Atom {
        // 1. Create the project first (without rootThinkspaceUuid)
        var projectMetadata = ProjectMetadata(color: color, status: "active", priority: "Medium")

        let project = try await create(
            type: .project,
            title: title,
            body: description,
            metadata: try? String(data: JSONEncoder().encode(projectMetadata), encoding: .utf8)
        )

        // 2. Create root ThinkSpace for the project
        let thinkspaceMetadata = ThinkspaceMetadata(
            name: title,  // Same name as project
            projectUuid: project.uuid,
            parentThinkspaceId: nil,
            isRootThinkspace: true
        )

        guard let thinkspaceMetadataJson = try? JSONEncoder().encode(thinkspaceMetadata),
              let thinkspaceMetadataString = String(data: thinkspaceMetadataJson, encoding: .utf8) else {
            print("⚠️ Failed to encode ThinkSpace metadata, project created without root ThinkSpace")
            return project
        }

        let rootThinkspace = Atom.new(
            type: .thinkspace,
            title: title,
            metadata: thinkspaceMetadataString
        )

        let savedThinkspace = try await create(rootThinkspace)

        // 3. Update project metadata with root ThinkSpace reference
        projectMetadata.rootThinkspaceUuid = savedThinkspace.uuid

        var updatedProject = project
        if let metadataJson = try? JSONEncoder().encode(projectMetadata),
           let metadataString = String(data: metadataJson, encoding: .utf8) {
            updatedProject.metadata = metadataString
        }
        updatedProject.updatedAt = ISO8601DateFormatter().string(from: Date())

        try await update(updatedProject)

        // 4. Notify ThinkspaceManager to reload (it observes thinkspaces)
        NotificationCenter.default.post(
            name: CosmoNotification.Canvas.thinkspaceChanged,
            object: nil,
            userInfo: ["action": "created", "thinkspaceId": savedThinkspace.uuid]
        )

        // 5. Notify Plannerum and other observers that atoms changed
        NotificationCenter.default.post(name: .atomsDidChange, object: nil)

        // 6. Notify about project creation (for voice routing, etc.)
        NotificationCenter.default.post(
            name: CosmoNotification.Project.created,
            object: nil,
            userInfo: ["projectUuid": updatedProject.uuid, "projectName": title]
        )

        print("✅ Project created with root ThinkSpace: \(title)")
        return updatedProject
    }

    /// Create a project from an existing ThinkSpace
    /// The ThinkSpace becomes the root ThinkSpace (no duplicate created)
    func createProjectFromThinkspace(thinkspaceUuid: String, thinkspaceName: String, color: String = "#8B5CF6") async throws -> Atom {
        // 1. Create the project with reference to existing thinkspace as root
        let projectMetadata = ProjectMetadata(
            color: color,
            status: "active",
            priority: "Medium",
            rootThinkspaceUuid: thinkspaceUuid  // Use existing thinkspace as root
        )

        let project = try await create(
            type: .project,
            title: thinkspaceName,
            body: "Created from ThinkSpace",
            metadata: try? String(data: JSONEncoder().encode(projectMetadata), encoding: .utf8)
        )

        // 2. Update the existing ThinkSpace to be the root of this project
        guard var thinkspaceAtom = try await fetch(uuid: thinkspaceUuid) else {
            throw NSError(domain: "AtomRepository", code: 404, userInfo: [NSLocalizedDescriptionKey: "ThinkSpace not found"])
        }

        // Update thinkspace metadata to mark it as root and assign to project
        var thinkspaceMetadata = thinkspaceAtom.metadataValue(as: ThinkspaceMetadata.self) ?? ThinkspaceMetadata()
        thinkspaceMetadata.projectUuid = project.uuid
        thinkspaceMetadata.isRootThinkspace = true
        thinkspaceMetadata.parentThinkspaceId = nil

        if let metadataJson = try? JSONEncoder().encode(thinkspaceMetadata),
           let metadataString = String(data: metadataJson, encoding: .utf8) {
            thinkspaceAtom.metadata = metadataString
        }
        thinkspaceAtom.updatedAt = ISO8601DateFormatter().string(from: Date())

        try await update(thinkspaceAtom)

        // 3. Notify ThinkspaceManager to reload
        NotificationCenter.default.post(
            name: CosmoNotification.Canvas.thinkspaceChanged,
            object: nil,
            userInfo: ["action": "updated", "thinkspaceId": thinkspaceUuid]
        )

        // 4. Notify Plannerum and other observers that atoms changed
        NotificationCenter.default.post(name: .atomsDidChange, object: nil)

        // 5. Create project inbox streams for Plannerum
        NotificationCenter.default.post(
            name: CosmoNotification.Project.created,
            object: nil,
            userInfo: ["projectUuid": project.uuid, "projectName": thinkspaceName]
        )

        print("✅ Project created from existing ThinkSpace: \(thinkspaceName)")
        return project
    }
}

// MARK: - Statistics

extension AtomRepository {

    /// Get counts by type
    func countsByType() async throws -> [AtomType: Int] {
        try await database.asyncRead { db in
            var counts: [AtomType: Int] = [:]

            for type in AtomType.allCases {
                let count = try Atom
                    .filter(Atom.CodingKeys.type == type.rawValue)
                    .filter(Atom.CodingKeys.isDeleted == false)
                    .fetchCount(db)
                counts[type] = count
            }

            return counts
        }
    }

    /// Get total atom count
    func totalCount() async throws -> Int {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.isDeleted == false)
                .fetchCount(db)
        }
    }

    /// Count atoms by type
    func count(type: AtomType) async throws -> Int {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == type.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .fetchCount(db)
        }
    }
}

// MARK: - Legacy Compatibility Extensions

extension AtomRepository {

    /// Fetch atoms by legacy project ID (for backward compatibility)
    /// Searches for atoms linked to project via old projectId field or links array
    func fetchByProjectId(_ projectId: Int64) async throws -> [Atom] {
        try await database.asyncRead { db in
            // Check both links array and structured data for projectId
            try Atom
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(
                    sql: "links LIKE ? OR structured LIKE ?",
                    arguments: ["%\"projectId\":\(projectId)%", "%\"projectId\":\(projectId)%"]
                )
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchAll(db)
        }
    }

    /// Fetch tasks by status (uses metadata JSON)
    func fetchTasksByStatus(_ status: String) async throws -> [Atom] {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == AtomType.task.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(sql: "metadata LIKE ?", arguments: ["%\"status\":\"\(status)\"%"])
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchAll(db)
        }
    }

    /// Fetch atoms by multiple types (convenience)
    func fetchByTypes(_ types: [AtomType]) async throws -> [Atom] {
        try await fetchAll(types: types)
    }

    /// Fuzzy find client profile by name or handle
    func fuzzyFindClient(query: String) async throws -> Atom? {
        let pattern = "%\(query)%"
        return try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == AtomType.clientProfile.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(
                    Column("title").like(pattern) ||
                    Column("metadata").like(pattern)
                )
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchOne(db)
        }
    }

    /// Fuzzy find project by name (for voice command routing)
    func fuzzyFindProject(query: String) async throws -> Atom? {
        let pattern = "%\(query)%"
        return try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == AtomType.project.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(Column("title").like(pattern))
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchOne(db)
        }
    }
}

// MARK: - Uncommitted Item Workflow

extension AtomRepository {

    /// Fetch uncommitted items (not archived, not deleted)
    func fetchUncommittedItems(archived: Bool = false) async throws -> [Atom] {
        try await database.asyncRead { db in
            var request = Atom
                .filter(Atom.CodingKeys.type == AtomType.uncommittedItem.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)

            if archived {
                request = request.filter(sql: "metadata LIKE '%\"isArchived\":true%'")
            } else {
                request = request.filter(sql: "metadata NOT LIKE '%\"isArchived\":true%' OR metadata IS NULL")
            }

            return try request
                .order(Atom.CodingKeys.createdAt.desc)
                .fetchAll(db)
        }
    }

    /// Fetch uncommitted items by assignment status
    func fetchUncommittedByAssignmentStatus(_ status: String) async throws -> [Atom] {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == AtomType.uncommittedItem.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(sql: "metadata NOT LIKE '%\"isArchived\":true%' OR metadata IS NULL")
                .filter(sql: "metadata LIKE ?", arguments: ["%\"assignmentStatus\":\"\(status)\"%"])
                .order(Atom.CodingKeys.createdAt.desc)
                .fetchAll(db)
        }
    }

    /// Fetch uncommitted items by inferred type
    func fetchUncommittedByInferredType(_ inferredType: String) async throws -> [Atom] {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == AtomType.uncommittedItem.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(sql: "metadata NOT LIKE '%\"isArchived\":true%' OR metadata IS NULL")
                .filter(sql: "metadata LIKE ?", arguments: ["%\"inferredType\":\"\(inferredType)\"%"])
                .order(Atom.CodingKeys.createdAt.desc)
                .fetchAll(db)
        }
    }

    /// Fetch recently promoted uncommitted items
    func fetchRecentlyPromoted(limit: Int = 10) async throws -> [Atom] {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == AtomType.uncommittedItem.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(sql: "metadata LIKE '%\"isArchived\":true%'")
                .filter(sql: "metadata LIKE '%\"promotedTo\":%'")
                .order(Atom.CodingKeys.updatedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Archive an uncommitted item
    func archiveUncommittedItem(uuid: String) async throws {
        guard var atom = try await fetch(uuid: uuid) else { return }

        // Parse existing metadata or create new
        var metadata: [String: Any] = [:]
        if let existingMetadata = atom.metadata,
           let data = existingMetadata.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            metadata = parsed
        }

        metadata["isArchived"] = true

        // Update atom with new metadata
        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            atom.metadata = jsonString
            _ = try await update(atom)
        }
    }

    /// Promote an uncommitted item (archive and link to new entity)
    func promoteUncommittedItem(uuid: String, toType: AtomType, entityUuid: String) async throws {
        guard var atom = try await fetch(uuid: uuid) else { return }

        // Parse existing metadata
        var metadata: [String: Any] = [:]
        if let existingMetadata = atom.metadata,
           let data = existingMetadata.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            metadata = parsed
        }

        metadata["isArchived"] = true
        metadata["promotedTo"] = toType.rawValue
        metadata["promotedEntityUuid"] = entityUuid

        // Update atom with new metadata
        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            atom.metadata = jsonString
            _ = try await update(atom)
        }
    }

    /// Restore an archived uncommitted item
    func restoreUncommittedItem(uuid: String) async throws {
        guard var atom = try await fetch(uuid: uuid) else { return }

        // Parse existing metadata
        var metadata: [String: Any] = [:]
        if let existingMetadata = atom.metadata,
           let data = existingMetadata.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            metadata = parsed
        }

        // Remove archived state
        metadata["isArchived"] = false
        metadata.removeValue(forKey: "promotedTo")
        metadata.removeValue(forKey: "promotedEntityUuid")
        metadata.removeValue(forKey: "promotedEntityId")

        // Update atom with new metadata
        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            atom.metadata = jsonString
            _ = try await update(atom)
        }
    }

    /// Update assignment status for uncommitted item
    func updateUncommittedAssignmentStatus(uuid: String, status: String, projectUuid: String?) async throws {
        guard var atom = try await fetch(uuid: uuid) else { return }

        // Parse existing metadata
        var metadata: [String: Any] = [:]
        if let existingMetadata = atom.metadata,
           let data = existingMetadata.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            metadata = parsed
        }

        metadata["assignmentStatus"] = status
        if let projectUuid = projectUuid {
            metadata["projectUuid"] = projectUuid
        }

        // Update atom with new metadata
        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            atom.metadata = jsonString
            _ = try await update(atom)
        }

        // Also update links if project assigned
        if let projectUuid = projectUuid {
            var links = atom.linksList
            // Remove existing project links
            links.removeAll { $0.type == "project" }
            // Add new project link
            links.append(AtomLink.project(projectUuid))
            atom.links = try? String(data: JSONEncoder().encode(links), encoding: .utf8)
            _ = try await update(atom)
        }
    }

    /// Count uncommitted items by assignment status
    func countUncommittedByAssignmentStatus(_ status: String) async throws -> Int {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == AtomType.uncommittedItem.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(sql: "metadata NOT LIKE '%\"isArchived\":true%' OR metadata IS NULL")
                .filter(sql: "metadata LIKE ?", arguments: ["%\"assignmentStatus\":\"\(status)\"%"])
                .fetchCount(db)
        }
    }

    /// Count all uncommitted items (not archived)
    func countUncommittedItems() async throws -> Int {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == AtomType.uncommittedItem.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(sql: "metadata NOT LIKE '%\"isArchived\":true%' OR metadata IS NULL")
                .fetchCount(db)
        }
    }
}

// MARK: - FTS5 Search Integration

extension AtomRepository {

    /// Full-text search using FTS5 index (if available)
    func ftsSearch(query: String, types: [AtomType]? = nil, limit: Int = 50) async throws -> [Atom] {
        // First try FTS5 search via search_index table
        do {
            let results = try await database.asyncRead { db -> [Atom] in
                let typeFilter: String
                if let types = types, !types.isEmpty {
                    let typeList = types.map { "'\($0.rawValue)'" }.joined(separator: ",")
                    typeFilter = "AND a.type IN (\(typeList))"
                } else {
                    typeFilter = ""
                }

                let rows = try Row.fetchAll(db, sql: """
                    SELECT a.* FROM atoms a
                    JOIN atoms_fts s ON s.rowid = a.id
                    WHERE atoms_fts MATCH ? AND a.is_deleted = 0 \(typeFilter)
                    ORDER BY rank
                    LIMIT ?
                    """, arguments: [query, limit])

                return rows.compactMap { try? Atom(row: $0) }
            }
            return results
        } catch {
            // Fallback to LIKE search if FTS5 not available
            return try await search(query: query, types: types)
        }
    }
}

// MARK: - Convenience Create Methods

extension AtomRepository {

    /// Create a new uncommitted item
    @discardableResult
    func createUncommittedItem(
        rawText: String,
        captureMethod: String = "keyboard",
        assignmentStatus: String = "unassigned",
        projectUuid: String? = nil,
        inferredType: String? = nil,
        inferredProject: String? = nil,
        inferredProjectConfidence: Double? = nil
    ) async throws -> Atom {
        var metadata: [String: Any] = [
            "captureMethod": captureMethod,
            "assignmentStatus": assignmentStatus,
            "isArchived": false
        ]

        if let inferredType = inferredType {
            metadata["inferredType"] = inferredType
        }
        if let inferredProject = inferredProject {
            metadata["inferredProject"] = inferredProject
        }
        if let confidence = inferredProjectConfidence {
            metadata["inferredProjectConfidence"] = confidence
        }

        var links: [AtomLink] = []
        if let projectUuid = projectUuid {
            links.append(.project(projectUuid))
            metadata["projectUuid"] = projectUuid
        }

        let metadataString = try? String(
            data: JSONSerialization.data(withJSONObject: metadata),
            encoding: .utf8
        )

        return try await create(
            type: .uncommittedItem,
            title: nil,
            body: rawText,
            metadata: metadataString,
            links: links.isEmpty ? nil : links
        )
    }

    /// Create a new content atom
    @discardableResult
    func createContent(title: String, body: String? = nil, contentType: String = "note") async throws -> Atom {
        let metadata = ContentMetadata(contentType: contentType)

        return try await create(
            type: .content,
            title: title,
            body: body,
            metadata: try? String(data: JSONEncoder().encode(metadata), encoding: .utf8)
        )
    }

    /// Create a new research atom
    @discardableResult
    func createResearch(
        title: String,
        url: String,
        summary: String? = nil,
        researchType: String = "article"
    ) async throws -> Atom {
        var metadata: [String: Any] = [
            "url": url,
            "researchType": researchType,
            "processingStatus": "pending"
        ]
        if let summary = summary {
            metadata["summary"] = summary
        }

        let metadataString = try? String(
            data: JSONSerialization.data(withJSONObject: metadata),
            encoding: .utf8
        )

        return try await create(
            type: .research,
            title: title,
            body: summary,
            metadata: metadataString
        )
    }

    /// Create a new connection (mental model link)
    @discardableResult
    func createConnection(
        title: String? = nil,
        sourceUuid: String,
        targetUuid: String,
        connectionType: String = "related"
    ) async throws -> Atom {
        let links: [AtomLink] = [
            AtomLink(type: "source", uuid: sourceUuid),
            AtomLink(type: "target", uuid: targetUuid)
        ]

        let metadata: [String: Any] = [
            "connectionType": connectionType,
            "sourceUuid": sourceUuid,
            "targetUuid": targetUuid
        ]

        let metadataString = try? String(
            data: JSONSerialization.data(withJSONObject: metadata),
            encoding: .utf8
        )

        return try await create(
            type: .connection,
            title: title,
            metadata: metadataString,
            links: links
        )
    }

    /// Create a new schedule block
    @discardableResult
    func createScheduleBlock(
        title: String,
        startTime: String,
        endTime: String? = nil,
        blockType: String = "task"
    ) async throws -> Atom {
        var metadata: [String: Any] = [
            "startTime": startTime,
            "blockType": blockType
        ]
        if let endTime = endTime {
            metadata["endTime"] = endTime
        }

        let metadataString = try? String(
            data: JSONSerialization.data(withJSONObject: metadata),
            encoding: .utf8
        )

        return try await create(
            type: .scheduleBlock,
            title: title,
            metadata: metadataString
        )
    }
}

// MARK: - IdeaForge Convenience Methods

extension AtomRepository {

    /// Create an enriched idea with optional format, client, and capture source
    @discardableResult
    func createEnrichedIdea(
        title: String?,
        content: String,
        tags: [String] = [],
        contentFormat: ContentFormat? = nil,
        platform: IdeaPlatform? = nil,
        clientQuery: String? = nil,
        captureSource: String? = nil,
        originSwipeUUID: String? = nil,
        projectUuid: String? = nil
    ) async throws -> Atom {
        var metadata = IdeaMetadata(
            tags: tags,
            priority: "Medium",
            isPinned: false,
            ideaStatus: .spark,
            contentFormat: contentFormat,
            platform: platform,
            captureSource: captureSource,
            originSwipeUUID: originSwipeUUID
        )

        var links: [AtomLink] = []
        if let projectUuid = projectUuid {
            links.append(.project(projectUuid))
        }

        // Auto-link to client if query provided
        if let clientQuery = clientQuery {
            if let client = try await fuzzyFindClient(query: clientQuery) {
                metadata.clientUUID = client.uuid
                links.append(.ideaToClient(client.uuid))
            }
        }

        // Auto-link to origin swipe
        if let swipeUUID = originSwipeUUID {
            links.append(.ideaToSwipe(swipeUUID))
        }

        let idea = try await create(
            type: .idea,
            title: title,
            body: content,
            metadata: try? String(data: JSONEncoder().encode(metadata), encoding: .utf8),
            links: links.isEmpty ? nil : links
        )

        // Run quick insight in background (on-device, fast)
        Task {
            await IdeaInsightEngine.shared.quickEnrich(atom: idea)
        }

        return idea
    }

    /// Get all client profile atoms
    func clientProfiles() async throws -> [Atom] {
        try await fetchAll(type: .clientProfile)
    }

    /// Create a client profile atom
    @discardableResult
    func createClientProfile(
        name: String,
        handles: [String: String]? = nil,
        niche: String? = nil,
        color: String? = nil
    ) async throws -> Atom {
        let metadata = ClientMetadata(
            handles: handles,
            niche: niche,
            color: color,
            isActive: true
        )

        return try await create(
            type: .clientProfile,
            title: name,
            metadata: try? String(data: JSONEncoder().encode(metadata), encoding: .utf8)
        )
    }
}

// MARK: - Swipe Intelligence Taxonomy Methods

extension AtomRepository {

    /// Create a content creator atom
    @discardableResult
    func createCreator(name: String, handle: String, platform: String) async throws -> Atom {
        let metadata = CreatorMetadata(
            handle: handle,
            platform: platform,
            swipeCount: 0,
            isActive: true
        )

        return try await create(
            type: .creator,
            title: name,
            metadata: try? String(data: JSONEncoder().encode(metadata), encoding: .utf8)
        )
    }

    /// Fetch creator atoms with optional platform/niche filters
    func fetchCreators(platform: String? = nil, niche: String? = nil) async throws -> [Atom] {
        return try await database.asyncRead { db in
            var request = Atom
                .filter(Atom.CodingKeys.type == AtomType.creator.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)

            if let platform = platform {
                request = request.filter(
                    sql: "metadata LIKE ?",
                    arguments: ["%\"platform\":\"\(platform)\"%"]
                )
            }

            if let niche = niche {
                request = request.filter(
                    sql: "metadata LIKE ?",
                    arguments: ["%\"niche\":\"\(niche)\"%"]
                )
            }

            return try request
                .order(Column("title").asc)
                .fetchAll(db)
        }
    }

    /// Fetch taxonomy value atoms for a specific dimension
    func fetchTaxonomyValues(dimension: String) async throws -> [Atom] {
        return try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == AtomType.taxonomyValue.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(
                    sql: "metadata LIKE ?",
                    arguments: ["%\"dimension\":\"\(dimension)\"%"]
                )
                .order(sql: "json_extract(metadata, '$.sortOrder') ASC")
                .fetchAll(db)
        }
    }

    /// Create a taxonomy value atom
    @discardableResult
    func createTaxonomyValue(dimension: String, value: String, sortOrder: Int = 0, isDefault: Bool = false) async throws -> Atom {
        let metadata = TaxonomyValueMetadata(
            dimension: dimension,
            value: value,
            sortOrder: sortOrder,
            isDefault: isDefault
        )

        return try await create(
            type: .taxonomyValue,
            title: value,
            metadata: try? String(data: JSONEncoder().encode(metadata), encoding: .utf8)
        )
    }

    /// Query swipe files by taxonomy dimensions. All parameters are optional;
    /// nil parameters are ignored (partial matching). Results ordered by hookScore descending.
    func fetchSwipesByTaxonomy(
        contentType: ContentFormat? = nil,
        narrative: NarrativeStyle? = nil,
        niche: String? = nil,
        creatorUUID: String? = nil
    ) async throws -> [Atom] {
        // Fetch all swipe file atoms, then filter in-memory by swipeAnalysis fields
        let allSwipes = try await database.asyncRead { db in
            var request = Atom
                .filter(Atom.CodingKeys.type == AtomType.research.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(sql: "metadata LIKE '%\"isSwipeFile\":true%'")

            // Pre-filter by creatorUUID in structured JSON if provided
            if let creatorUUID = creatorUUID {
                request = request.filter(
                    sql: "structured LIKE ?",
                    arguments: ["%\"creatorUUID\":\"\(creatorUUID)\"%"]
                )
            }

            // Pre-filter by niche in structured JSON if provided
            if let niche = niche {
                request = request.filter(
                    sql: "structured LIKE ?",
                    arguments: ["%\"niche\":\"\(niche)\"%"]
                )
            }

            // Pre-filter by narrative in structured JSON if provided
            if let narrative = narrative {
                request = request.filter(
                    sql: "structured LIKE ?",
                    arguments: ["%\"primaryNarrative\":\"\(narrative.rawValue)\"%"]
                )
            }

            // Pre-filter by content format in structured JSON if provided
            if let contentType = contentType {
                request = request.filter(
                    sql: "structured LIKE ?",
                    arguments: ["%\"swipeContentFormat\":\"\(contentType.rawValue)\"%"]
                )
            }

            return try request.fetchAll(db)
        }

        // Sort by hookScore descending (from swipeAnalysis)
        let sorted = allSwipes.sorted { a, b in
            let scoreA = a.swipeAnalysis?.hookScore ?? 0
            let scoreB = b.swipeAnalysis?.hookScore ?? 0
            return scoreA > scoreB
        }

        return sorted
    }
}
