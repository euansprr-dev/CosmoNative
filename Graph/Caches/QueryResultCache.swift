// CosmoOS/Graph/Caches/QueryResultCache.swift
// Tier 2 cache for NodeGraph OS - LRU cache for search results
// Caches query results keyed by query + context

import Foundation

// MARK: - QueryResultCache
/// Tier 2 cache: Query result cache (LRU)
/// Caches search results by query + context combination
/// TTL: 5 minutes, Size: 100 entries max
public actor QueryResultCache {

    // MARK: - Singleton
    public static let shared = QueryResultCache()

    // MARK: - Configuration
    /// Time-to-live for cached entries
    public let ttl: TimeInterval = 300.0  // 5 minutes

    /// Maximum number of cached queries
    public let maxEntries = 100

    // MARK: - Storage
    private var cache: [String: CachedQueryResult] = [:]
    private var accessOrder: [String] = []  // For LRU eviction

    // MARK: - Initialization
    private init() {}

    // MARK: - Cache Key Generation

    /// Generate cache key from query parameters
    public static func cacheKey(
        query: String,
        contextType: String?,
        focusAtomUUID: String?,
        typeFilter: [AtomType]?
    ) -> String {
        var components: [String] = [query.lowercased().trimmingCharacters(in: .whitespaces)]

        if let context = contextType {
            components.append("ctx:\(context)")
        }

        if let focus = focusAtomUUID {
            components.append("focus:\(focus)")
        }

        if let types = typeFilter, !types.isEmpty {
            components.append("types:\(types.map { $0.rawValue }.sorted().joined(separator: ","))")
        }

        return components.joined(separator: "|")
    }

    // MARK: - Cache Operations

    /// Get cached results for a query
    /// - Parameter key: The cache key
    /// - Returns: Cached results if valid, nil otherwise
    public func get(for key: String) -> [RankedResult]? {
        guard let cached = cache[key] else { return nil }

        // Check TTL
        if Date().timeIntervalSince(cached.timestamp) > ttl {
            // Expired, remove it
            cache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
            return nil
        }

        // Update access order
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)

        return cached.results
    }

    /// Cache results for a query
    /// - Parameters:
    ///   - results: The search results to cache
    ///   - key: The cache key
    public func set(_ results: [RankedResult], for key: String) {
        // Evict if at capacity
        while cache.count >= maxEntries && !accessOrder.isEmpty {
            let oldest = accessOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }

        cache[key] = CachedQueryResult(
            results: results,
            timestamp: Date()
        )

        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    /// Invalidate cache entries containing a specific atom
    /// - Parameter atomUUID: The UUID of the updated atom
    public func invalidateContaining(atomUUID: String) {
        let keysToRemove = cache.keys.filter { key in
            guard let cached = cache[key] else { return false }
            return cached.results.contains { $0.atomUUID == atomUUID }
        }

        for key in keysToRemove {
            cache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
        }
    }

    /// Invalidate cache entries matching a query prefix
    /// - Parameter prefix: The query prefix to match
    public func invalidateMatching(prefix: String) {
        let lowercased = prefix.lowercased()
        let keysToRemove = cache.keys.filter { $0.hasPrefix(lowercased) }

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

    /// Prune expired entries
    public func prune() {
        let now = Date()
        let expiredKeys = cache.keys.filter { key in
            guard let cached = cache[key] else { return true }
            return now.timeIntervalSince(cached.timestamp) > ttl
        }

        for key in expiredKeys {
            cache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
        }
    }
}

// MARK: - Cached Query Result
private struct CachedQueryResult {
    let results: [RankedResult]
    let timestamp: Date
}
