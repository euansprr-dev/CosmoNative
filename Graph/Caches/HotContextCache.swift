// CosmoOS/Graph/Caches/HotContextCache.swift
// Tier 1 cache for NodeGraph OS - caches focus neighborhood (2-hop)
// Provides instant access to nodes near the current focus

import Foundation

// MARK: - HotContextCache
/// Tier 1 cache: Focus neighborhood cache
/// Caches the 2-hop neighborhood around the current focus atom
/// TTL: 60 seconds, Size: 50 entries max
public actor HotContextCache {

    // MARK: - Singleton
    public static let shared = HotContextCache()

    // MARK: - Configuration
    /// Time-to-live for cached entries
    public let ttl: TimeInterval = 60.0  // 60 seconds

    /// Maximum number of cached neighborhoods
    public let maxEntries = 50

    // MARK: - Storage
    private var cache: [String: CachedNeighborhood] = [:]
    private var accessOrder: [String] = []  // For LRU eviction

    // MARK: - Initialization
    private init() {}

    // MARK: - Cache Operations

    /// Get cached neighborhood for a focus atom
    /// - Parameter focusUUID: The UUID of the focus atom
    /// - Returns: Cached neighborhood if valid, nil otherwise
    public func get(for focusUUID: String) -> NeighborhoodResult? {
        guard let cached = cache[focusUUID] else { return nil }

        // Check TTL
        if Date().timeIntervalSince(cached.timestamp) > ttl {
            // Expired, remove it
            cache.removeValue(forKey: focusUUID)
            accessOrder.removeAll { $0 == focusUUID }
            return nil
        }

        // Update access order
        accessOrder.removeAll { $0 == focusUUID }
        accessOrder.append(focusUUID)

        return cached.neighborhood
    }

    /// Cache a neighborhood result
    /// - Parameters:
    ///   - neighborhood: The neighborhood to cache
    ///   - focusUUID: The UUID of the focus atom
    public func set(_ neighborhood: NeighborhoodResult, for focusUUID: String) {
        // Evict if at capacity
        while cache.count >= maxEntries && !accessOrder.isEmpty {
            let oldest = accessOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }

        cache[focusUUID] = CachedNeighborhood(
            neighborhood: neighborhood,
            timestamp: Date()
        )

        accessOrder.removeAll { $0 == focusUUID }
        accessOrder.append(focusUUID)
    }

    /// Invalidate cache for a specific focus
    /// - Parameter focusUUID: The UUID to invalidate
    public func invalidate(for focusUUID: String) {
        cache.removeValue(forKey: focusUUID)
        accessOrder.removeAll { $0 == focusUUID }
    }

    /// Invalidate cache entries containing a specific atom
    /// - Parameter atomUUID: The UUID of the updated atom
    public func invalidateContaining(atomUUID: String) {
        let keysToRemove = cache.keys.filter { key in
            guard let cached = cache[key] else { return false }
            return cached.neighborhood.allUUIDs.contains(atomUUID)
        }

        for key in keysToRemove {
            cache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
        }
    }

    /// Clear all cached entries
    public func clear() {
        cache.removeAll()
        accessOrder.removeAll()
    }

    /// Get cache statistics
    public func stats() -> CacheStats {
        let now = Date()
        let validCount = cache.values.filter { now.timeIntervalSince($0.timestamp) <= ttl }.count
        return CacheStats(
            totalEntries: cache.count,
            validEntries: validCount,
            maxEntries: maxEntries,
            ttl: ttl
        )
    }
}

// MARK: - Cached Neighborhood
private struct CachedNeighborhood {
    let neighborhood: NeighborhoodResult
    let timestamp: Date
}

// MARK: - Cache Stats
public struct CacheStats: Sendable {
    public let totalEntries: Int
    public let validEntries: Int
    public let maxEntries: Int
    public let ttl: TimeInterval

    public var utilizationPercent: Double {
        guard maxEntries > 0 else { return 0 }
        return Double(totalEntries) / Double(maxEntries) * 100
    }
}
