// CosmoOS/Graph/Caches/EmbeddingCache.swift
// Tier 3 cache for NodeGraph OS - caches text to embedding mappings
// Avoids redundant embedding computations

import Foundation

// MARK: - EmbeddingCache
/// Tier 3 cache: Embedding cache
/// Caches text → embedding mappings to avoid redundant computation
/// TTL: 1 hour, Size: 1000 entries max
public actor EmbeddingCache {

    // MARK: - Singleton
    public static let shared = EmbeddingCache()

    // MARK: - Configuration
    /// Time-to-live for cached entries
    public let ttl: TimeInterval = 3600.0  // 1 hour

    /// Maximum number of cached embeddings
    public let maxEntries = 1000

    /// Hash prefix length for deduplication
    private let hashPrefixLength = 200

    // MARK: - Storage
    private var cache: [String: CachedEmbedding] = [:]
    private var accessOrder: [String] = []  // For LRU eviction

    // MARK: - Initialization
    private init() {}

    // MARK: - Hash Generation

    /// Generate cache key from text content
    /// Uses first N characters + hash for efficiency
    private func generateKey(for text: String) -> String {
        let prefix = String(text.prefix(hashPrefixLength))
        let hash = text.hashValue
        return "\(prefix.hashValue):\(hash)"
    }

    // MARK: - Cache Operations

    /// Get cached embedding for text
    /// - Parameter text: The source text
    /// - Returns: Cached embedding if valid, nil otherwise
    public func get(for text: String) -> [Float]? {
        let key = generateKey(for: text)

        guard let cached = cache[key] else { return nil }

        // Check TTL
        if Date().timeIntervalSince(cached.timestamp) > ttl {
            // Expired, remove it
            cache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
            return nil
        }

        // Verify text hash matches (collision check)
        guard cached.textHash == text.hashValue else {
            // Hash collision, return nil
            return nil
        }

        // Update access order
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)

        return cached.embedding
    }

    /// Get cached embedding by atom UUID
    /// - Parameter atomUUID: The UUID of the atom
    /// - Returns: Cached embedding if valid, nil otherwise
    public func get(byAtomUUID atomUUID: String) -> [Float]? {
        guard let cached = cache.values.first(where: { $0.atomUUID == atomUUID }) else {
            return nil
        }

        // Check TTL
        if Date().timeIntervalSince(cached.timestamp) > ttl {
            return nil
        }

        return cached.embedding
    }

    /// Cache embedding for text
    /// - Parameters:
    ///   - embedding: The computed embedding
    ///   - text: The source text
    ///   - atomUUID: Optional atom UUID for cross-reference
    public func set(_ embedding: [Float], for text: String, atomUUID: String? = nil) {
        let key = generateKey(for: text)

        // Evict if at capacity
        while cache.count >= maxEntries && !accessOrder.isEmpty {
            let oldest = accessOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }

        cache[key] = CachedEmbedding(
            embedding: embedding,
            textHash: text.hashValue,
            atomUUID: atomUUID,
            timestamp: Date()
        )

        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    /// Invalidate cache for specific text
    /// - Parameter text: The text to invalidate
    public func invalidate(for text: String) {
        let key = generateKey(for: text)
        cache.removeValue(forKey: key)
        accessOrder.removeAll { $0 == key }
    }

    /// Invalidate cache for specific atom
    /// - Parameter atomUUID: The atom UUID to invalidate
    public func invalidate(byAtomUUID atomUUID: String) {
        let keysToRemove = cache.filter { $0.value.atomUUID == atomUUID }.keys

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
    public func stats() -> EmbeddingCacheStats {
        let now = Date()
        let validCount = cache.values.filter { now.timeIntervalSince($0.timestamp) <= ttl }.count
        let totalEmbeddingSize = cache.values.reduce(0) { $0 + $1.embedding.count * MemoryLayout<Float>.size }

        return EmbeddingCacheStats(
            totalEntries: cache.count,
            validEntries: validCount,
            maxEntries: maxEntries,
            ttl: ttl,
            memoryUsageBytes: totalEmbeddingSize
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

// MARK: - Cached Embedding
private struct CachedEmbedding {
    let embedding: [Float]
    let textHash: Int
    let atomUUID: String?
    let timestamp: Date
}

// MARK: - Embedding Cache Stats
public struct EmbeddingCacheStats: Sendable {
    public let totalEntries: Int
    public let validEntries: Int
    public let maxEntries: Int
    public let ttl: TimeInterval
    public let memoryUsageBytes: Int

    public var utilizationPercent: Double {
        guard maxEntries > 0 else { return 0 }
        return Double(totalEntries) / Double(maxEntries) * 100
    }

    public var memoryUsageMB: Double {
        return Double(memoryUsageBytes) / (1024 * 1024)
    }
}
