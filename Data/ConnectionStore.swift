// CosmoOS/Data/ConnectionStore.swift
// Shared observable state for Connection entities
// Provides instant sync across floating blocks, focus mode, and lists

import SwiftUI
import GRDB
import Combine

/// Shared store for Connection state management.
/// Ensures instant reactivity across all views with background persistence.
@MainActor
final class ConnectionStore: ObservableObject {
    static let shared = ConnectionStore()
    
    /// In-memory cache of connections for instant access
    @Published private(set) var connections: [Int64: Connection] = [:]
    
    /// Currently editing connection (for focus mode sync)
    @Published var activeConnectionId: Int64? = nil
    
    /// Loading state
    @Published private(set) var isLoading = false
    
    private let database = CosmoDatabase.shared
    private var cancellables = Set<AnyCancellable>()
    private var observationTask: Task<Void, Never>?
    
    // Auto-save debouncing
    private var saveTask: Task<Void, Never>?
    private let saveDelay: TimeInterval = 0.5
    
    private init() {
        setupDatabaseObservation()
    }
    
    // MARK: - Database Observation
    
    private func setupDatabaseObservation() {
        // Observe all connections for changes
        observationTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                let observation = ValueObservation.tracking { db -> [Connection] in
                    try Atom
                        .filter(Column("type") == AtomType.connection.rawValue)
                        .filter(Column("is_deleted") == false)
                        .order(Column("updated_at").desc)
                        .fetchAll(db)
                        .map { ConnectionWrapper(atom: $0) }
                }
                
                for try await connections in observation.values(in: database.dbQueue) {
                    await MainActor.run {
                        // Update cache, preserving any unsaved local changes
                        var newCache: [Int64: Connection] = [:]
                        for connection in connections {
                            if let id = connection.id {
                                // Only update from DB if we don't have local unsaved changes
                                if let existing = self.connections[id],
                                   existing.updatedAt > connection.updatedAt {
                                    // Keep local version (has newer changes)
                                    newCache[id] = existing
                                } else {
                                    newCache[id] = connection
                                }
                            }
                        }
                        self.connections = newCache
                    }
                }
            } catch {
                print("❌ ConnectionStore observation error: \(error)")
            }
        }
    }
    
    // MARK: - Public API
    
    /// Get a connection by ID (instant from cache)
    func connection(for id: Int64) -> Connection? {
        return connections[id]
    }
    
    /// Load a connection if not in cache
    func loadConnection(_ id: Int64) async {
        guard connections[id] == nil else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            if let connection = try await database.asyncRead({ db in
                try Atom
                    .filter(Column("type") == AtomType.connection.rawValue)
                    .filter(Column("id") == id)
                    .fetchOne(db)
                    .map { ConnectionWrapper(atom: $0) }
            }) {
                connections[id] = connection
            }
        } catch {
            print("❌ Failed to load connection \(id): \(error)")
        }
    }
    
    /// Update a connection (instant UI update + background save)
    func update(_ connection: Connection) {
        guard let id = connection.id else { return }
        
        // Instant UI update
        var updatedConnection = connection
        updatedConnection.updatedAt = ISO8601DateFormatter().string(from: Date())
        connections[id] = updatedConnection
        
        // Debounced background save
        saveTask?.cancel()
        saveTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(saveDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await saveToDatabase(updatedConnection)
            } catch {
                // Task was cancelled, that's fine
            }
        }
    }
    
    /// Update a specific section of the mental model
    func updateSection(_ id: Int64, keyPath: WritableKeyPath<ConnectionMentalModel, String?>, value: String?) {
        guard var connection = connections[id] else { return }

        var model = connection.mentalModelOrNew
        model[keyPath: keyPath] = value
        connection.setMentalModel(model)

        update(connection)
    }
    
    /// Force save immediately (e.g., when leaving view)
    func forceSave(_ id: Int64) async {
        guard let connection = connections[id] else { return }
        saveTask?.cancel()
        await saveToDatabase(connection)
    }

    /// Get all connections as an array
    var allConnections: [Connection] {
        Array(connections.values).sorted { ($0.updatedAt) > ($1.updatedAt) }
    }

    /// Add a new connection (insert into DB and cache)
    func add(_ connection: Connection) {
        Task {
            await addAsync(connection)
        }
    }

    /// Add a new connection asynchronously
    func addAsync(_ connection: Connection) async {
        do {
            var newConnection = connection
            newConnection.localVersion = 1

            // Capture as local let for Sendable closure
            let connToInsert = newConnection
            let insertedConnection = try await database.asyncWrite { db -> Connection in
                var inserting = connToInsert
                try inserting.insert(db)
                inserting.id = db.lastInsertedRowID
                return inserting
            }

            if let id = insertedConnection.id {
                connections[id] = insertedConnection
            }

            GlobalStatusService.shared.showSaved()
        } catch {
            print("❌ Failed to add connection: \(error)")
        }
    }

    // MARK: - Private Helpers
    
    private func saveToDatabase(_ connection: Connection) async {
        do {
            var connectionToSave = connection
            connectionToSave.localVersion += 1

            // Capture as immutable value for Sendable closure
            let connToWrite = connectionToSave
            try await database.asyncWrite { db in
                try connToWrite.save(db)
            }

            GlobalStatusService.shared.showSaved()
        } catch {
            print("❌ Failed to save connection: \(error)")
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        observationTask?.cancel()
        saveTask?.cancel()
    }
}

// MARK: - Mental Model Section Definition

/// Represents a section in the Mental Model framework
/// @unchecked Sendable because keyPath is immutable and constant
struct MentalModelSection: Identifiable, Equatable, @unchecked Sendable {
    let id: String
    let name: String
    let shortName: String
    let icon: String
    let color: Color
    let placeholder: String
    let subtitle: String
    let keyPath: WritableKeyPath<ConnectionMentalModel, String?>

    static func == (lhs: MentalModelSection, rhs: MentalModelSection) -> Bool {
        lhs.id == rhs.id
    }

    /// All mental model sections in order
    static let allSections: [MentalModelSection] = [
        MentalModelSection(
            id: "goal",
            name: "Goal",
            shortName: "G",
            icon: "target",
            color: CosmoColors.emerald,
            placeholder: "What is the desired outcome?",
            subtitle: "What is the desired outcome?",
            keyPath: \.goal
        ),
        MentalModelSection(
            id: "problem",
            name: "Problem",
            shortName: "P",
            icon: "exclamationmark.triangle",
            color: CosmoColors.coral,
            placeholder: "Describe the problem this solves...",
            subtitle: "What friction does this solve?",
            keyPath: \.problem
        ),
        MentalModelSection(
            id: "benefits",
            name: "Benefits",
            shortName: "B",
            icon: "star",
            color: CosmoColors.skyBlue,
            placeholder: "List the benefits...",
            subtitle: "Why is this valuable?",
            keyPath: \.benefits
        ),
        MentalModelSection(
            id: "beliefs",
            name: "Beliefs",
            shortName: "O",
            icon: "bubble.left.and.bubble.right",
            color: CosmoColors.amber,
            placeholder: "Common limiting beliefs...",
            subtitle: "What holds you back?",
            keyPath: \.beliefsObjections
        ),
        MentalModelSection(
            id: "example",
            name: "Example",
            shortName: "E",
            icon: "lightbulb",
            color: CosmoColors.lavender,
            placeholder: "Describe a concrete application...",
            subtitle: "Concrete application",
            keyPath: \.example
        ),
        MentalModelSection(
            id: "process",
            name: "Process",
            shortName: "S",
            icon: "arrow.triangle.branch",
            color: CosmoColors.slate,
            placeholder: "1. First step...\n2. Second step...",
            subtitle: "Actionable steps",
            keyPath: \.process
        )
    ]
    
    /// Get section by ID
    static func section(for id: String) -> MentalModelSection? {
        allSections.first { $0.id == id }
    }
}

// MARK: - Connection Mental Model Helpers

extension ConnectionMentalModel {
    /// Get content for a specific section
    func content(for section: MentalModelSection) -> String? {
        self[keyPath: section.keyPath]
    }
    
    /// Check if a section has content
    func hasContent(for section: MentalModelSection) -> Bool {
        guard let content = self[keyPath: section.keyPath] else { return false }
        return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Count of filled sections
    var filledSections: [MentalModelSection] {
        MentalModelSection.allSections.filter { hasContent(for: $0) }
    }
}
