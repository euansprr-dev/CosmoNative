// CosmoOS/Data/Database/DatabaseActorCore.swift
// Sendable actor wrapper for database operations
// Used by FoundationModels tools which require Sendable conformance

import GRDB
import Foundation

/// A Sendable database actor that owns the GRDB queue.
/// Tools can depend on this actor (actors are inherently Sendable)
/// instead of the @MainActor CosmoDatabase which is not Sendable.
public actor DatabaseActorCore {
    private let dbQueue: DatabaseQueue

    /// Initialize with an existing database queue
    public init(queue: DatabaseQueue) {
        self.dbQueue = queue
    }

    /// Shared instance - initialized lazily from CosmoDatabase
    nonisolated(unsafe) public static var shared: DatabaseActorCore?

    // MARK: - Async Read/Write

    /// Perform an async read operation
    public func asyncRead<T: Sendable>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        return try await dbQueue.read(block)
    }

    /// Perform an async write operation
    public func asyncWrite<T: Sendable>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        return try await dbQueue.write(block)
    }

    // MARK: - Sync Read/Write (for special cases)

    /// Perform a synchronous read operation
    public func read<T>(_ block: (Database) throws -> T) throws -> T {
        return try dbQueue.read(block)
    }

    /// Perform a synchronous write operation
    public func write<T>(_ block: (Database) throws -> T) throws -> T {
        return try dbQueue.write(block)
    }
}
