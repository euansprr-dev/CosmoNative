// CosmoOS/Data/Models/LevelSystem/ContentAnalyticsEngine.swift
// Content Analytics Engine - Calculates metrics from performance Atoms
// ALL data flows through Atoms. Queries aggregate Atom data.

import Foundation
import GRDB

// MARK: - Content Analytics Engine

/// Calculates content performance metrics by querying Atoms.
/// No external state - all data comes from `.contentPerformance`, `.contentPublish` atoms.
actor ContentAnalyticsEngine {

    // MARK: - Dependencies

    private let database: any DatabaseWriter

    // MARK: - Initialization

    @MainActor
    init(database: (any DatabaseWriter)? = nil) {
        self.database = database ?? (CosmoDatabase.shared.dbQueue! as any DatabaseWriter)
    }

    // MARK: - Aggregate Metrics

    /// Calculate total reach for the past 7 days from performance Atoms
    func calculateWeeklyReach() async throws -> Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

        return try await database.read { db in
            let atoms = try Atom
                .filter(Column("type") == AtomType.contentPerformance.rawValue)
                .filter(Column("created_at") >= weekAgo.ISO8601Format())
                .fetchAll(db)

            return atoms.reduce(0) { total, atom in
                guard let metadata = atom.metadataValue(as: ContentPerformanceMetadata.self) else {
                    return total
                }
                return total + metadata.impressions
            }
        }
    }

    /// Calculate monthly viral content count
    func calculateMonthlyViralCount() async throws -> Int {
        let monthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date())!

        return try await database.read { db in
            try Atom
                .filter(Column("type") == AtomType.contentPerformance.rawValue)
                .filter(Column("created_at") >= monthAgo.ISO8601Format())
                .filter(sql: "json_extract(metadata, '$.isViral') = true")
                .fetchCount(db)
        }
    }

    /// Calculate average engagement rate across all performance Atoms
    func calculateAverageEngagementRate() async throws -> Double {
        let monthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date())!

        return try await database.read { db in
            let atoms = try Atom
                .filter(Column("type") == AtomType.contentPerformance.rawValue)
                .filter(Column("created_at") >= monthAgo.ISO8601Format())
                .fetchAll(db)

            guard !atoms.isEmpty else { return 0 }

            let totalEngagement = atoms.reduce(0.0) { total, atom in
                guard let metadata = atom.metadataValue(as: ContentPerformanceMetadata.self) else {
                    return total
                }
                return total + metadata.engagementRate
            }

            return totalEngagement / Double(atoms.count)
        }
    }

    /// Calculate average performance for a specific platform
    func calculateAveragePerformance(for platform: SocialPlatform) async -> Double {
        let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date())!

        do {
            return try await database.read { db in
                let atoms = try Atom
                    .filter(Column("type") == AtomType.contentPerformance.rawValue)
                    .filter(Column("created_at") >= threeMonthsAgo.ISO8601Format())
                    .filter(sql: "json_extract(metadata, '$.platform') = ?", arguments: [platform.rawValue])
                    .fetchAll(db)

                guard !atoms.isEmpty else { return 0 }

                let totalImpressions = atoms.reduce(0) { total, atom in
                    guard let metadata = atom.metadataValue(as: ContentPerformanceMetadata.self) else {
                        return total
                    }
                    return total + metadata.impressions
                }

                return Double(totalImpressions) / Double(atoms.count)
            }
        } catch {
            return 0
        }
    }

    // MARK: - Virality Calculation

    /// Calculate virality score (0-100) based on impressions and engagement
    func calculateViralityScore(
        impressions: Int,
        engagementRate: Double,
        platform: SocialPlatform
    ) -> Double {
        let threshold = platform.viralityThreshold

        // Calculate impression score (0-50 points)
        let impressionRatio = min(Double(impressions) / Double(threshold.impressions), 2.0)
        let impressionScore = impressionRatio * 25  // Max 50 points

        // Calculate engagement score (0-50 points)
        let engagementRatio = min(engagementRate / threshold.engagementRate, 2.0)
        let engagementScore = engagementRatio * 25  // Max 50 points

        return min(100, impressionScore + engagementScore)
    }

    // MARK: - Platform Analytics

    /// Get performance breakdown by platform
    func getPerformanceByPlatform() async throws -> [PlatformPerformance] {
        let monthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date())!

        return try await database.read { db in
            let atoms = try Atom
                .filter(Column("type") == AtomType.contentPerformance.rawValue)
                .filter(Column("created_at") >= monthAgo.ISO8601Format())
                .fetchAll(db)

            var platformStats: [SocialPlatform: PlatformStats] = [:]

            for atom in atoms {
                guard let metadata = atom.metadataValue(as: ContentPerformanceMetadata.self) else {
                    continue
                }

                if var stats = platformStats[metadata.platform] {
                    stats.totalImpressions += metadata.impressions
                    stats.totalEngagement += metadata.engagement
                    stats.postCount += 1
                    stats.viralCount += metadata.isViral ? 1 : 0
                    platformStats[metadata.platform] = stats
                } else {
                    platformStats[metadata.platform] = PlatformStats(
                        totalImpressions: metadata.impressions,
                        totalEngagement: metadata.engagement,
                        postCount: 1,
                        viralCount: metadata.isViral ? 1 : 0
                    )
                }
            }

            return platformStats.map { platform, stats in
                PlatformPerformance(
                    platform: platform,
                    totalImpressions: stats.totalImpressions,
                    totalEngagement: stats.totalEngagement,
                    postCount: stats.postCount,
                    viralCount: stats.viralCount,
                    avgEngagementRate: stats.postCount > 0
                        ? Double(stats.totalEngagement) / Double(stats.totalImpressions)
                        : 0
                )
            }.sorted { $0.totalImpressions > $1.totalImpressions }
        }
    }

    // MARK: - Trending Analysis

    /// Analyze reach trend over time
    func calculateReachTrend(days: Int = 30) async throws -> [DailyReachPoint] {
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        return try await database.read { db in
            let atoms = try Atom
                .filter(Column("type") == AtomType.contentPerformance.rawValue)
                .filter(Column("created_at") >= startDate.ISO8601Format())
                .order(Column("created_at").asc)
                .fetchAll(db)

            // Group by date
            var dailyReach: [String: Int] = [:]
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"

            for atom in atoms {
                guard let metadata = atom.metadataValue(as: ContentPerformanceMetadata.self) else {
                    continue
                }

                let dateKey = dateFormatter.string(from: metadata.publishedAt)

                if let existing = dailyReach[dateKey] {
                    dailyReach[dateKey] = existing + metadata.impressions
                } else {
                    dailyReach[dateKey] = metadata.impressions
                }
            }

            // Convert to sorted array
            return dailyReach.map { date, reach in
                DailyReachPoint(date: date, reach: reach)
            }.sorted { $0.date < $1.date }
        }
    }

    // MARK: - Top Content Analysis

    /// Get top performing content by impressions
    func getTopContent(limit: Int = 10) async throws -> [TopContentItem] {
        try await database.read { db in
            let performanceAtoms = try Atom
                .filter(Column("type") == AtomType.contentPerformance.rawValue)
                .order(sql: "json_extract(metadata, '$.impressions') DESC")
                .limit(limit)
                .fetchAll(db)

            return performanceAtoms.compactMap { atom -> TopContentItem? in
                guard let metadata = atom.metadataValue(as: ContentPerformanceMetadata.self) else {
                    return nil
                }

                // Find the linked content atom
                let contentUUID = atom.link(ofType: "content")?.uuid

                return TopContentItem(
                    performanceAtom: atom,
                    contentUUID: contentUUID,
                    platform: metadata.platform,
                    impressions: metadata.impressions,
                    engagementRate: metadata.engagementRate,
                    isViral: metadata.isViral,
                    viralityScore: metadata.viralityScore ?? 0
                )
            }
        }
    }

    // MARK: - Client Analytics

    /// Calculate aggregate metrics for a specific client
    func getClientPerformance(clientUUID: String) async throws -> ClientPerformanceData {
        try await database.read { db in
            // Find all content linked to this client
            let contentAtoms = try Atom
                .filter(Column("type") == AtomType.content.rawValue)
                .filter(sql: "links LIKE ?", arguments: ["%\(clientUUID)%"])
                .fetchAll(db)

            let contentUUIDs = contentAtoms.map { $0.uuid }

            // Find all performance atoms for this content
            var totalImpressions = 0
            var totalEngagement = 0
            var viralCount = 0
            var postCount = 0

            for contentUUID in contentUUIDs {
                let performanceAtoms = try Atom
                    .filter(Column("type") == AtomType.contentPerformance.rawValue)
                    .filter(sql: "links LIKE ?", arguments: ["%\(contentUUID)%"])
                    .fetchAll(db)

                for atom in performanceAtoms {
                    guard let metadata = atom.metadataValue(as: ContentPerformanceMetadata.self) else {
                        continue
                    }
                    totalImpressions += metadata.impressions
                    totalEngagement += metadata.engagement
                    if metadata.isViral { viralCount += 1 }
                    postCount += 1
                }
            }

            return ClientPerformanceData(
                clientUUID: clientUUID,
                totalReach: totalImpressions,
                totalEngagement: totalEngagement,
                contentCount: contentAtoms.count,
                viralCount: viralCount,
                avgEngagementRate: totalImpressions > 0
                    ? Double(totalEngagement) / Double(totalImpressions)
                    : 0
            )
        }
    }

    // MARK: - Creative Dimension Metrics

    /// Calculate all metrics needed for the Creative dimension
    func calculateCreativeDimensionMetrics() async throws -> LevelCreativeData {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let monthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date())!

        return try await database.read { db in
            // Weekly reach
            let weeklyAtoms = try Atom
                .filter(Column("type") == AtomType.contentPerformance.rawValue)
                .filter(Column("created_at") >= weekAgo.ISO8601Format())
                .fetchAll(db)

            let weeklyReach = weeklyAtoms.reduce(0) { total, atom in
                guard let metadata = atom.metadataValue(as: ContentPerformanceMetadata.self) else {
                    return total
                }
                return total + metadata.impressions
            }

            // Monthly viral count
            let monthlyAtoms = try Atom
                .filter(Column("type") == AtomType.contentPerformance.rawValue)
                .filter(Column("created_at") >= monthAgo.ISO8601Format())
                .fetchAll(db)

            let viralCount = monthlyAtoms.filter { atom in
                atom.metadataValue(as: ContentPerformanceMetadata.self)?.isViral == true
            }.count

            // Average engagement rate
            var totalEngagementRate = 0.0
            for atom in monthlyAtoms {
                if let metadata = atom.metadataValue(as: ContentPerformanceMetadata.self) {
                    totalEngagementRate += metadata.engagementRate
                }
            }
            let avgEngagement = monthlyAtoms.isEmpty ? 0 : totalEngagementRate / Double(monthlyAtoms.count)

            // Published per month
            let publishedCount = try Atom
                .filter(Column("type") == AtomType.contentPublish.rawValue)
                .filter(Column("created_at") >= monthAgo.ISO8601Format())
                .fetchCount(db)

            return LevelCreativeData(
                weeklyReach: weeklyReach,
                viralPostsPerMonth: viralCount,
                engagementRate: avgEngagement * 100,  // Convert to percentage
                publishedPerMonth: publishedCount
            )
        }
    }
}

// MARK: - Supporting Types

private struct PlatformStats {
    var totalImpressions: Int
    var totalEngagement: Int
    var postCount: Int
    var viralCount: Int
}

struct PlatformPerformance: Sendable {
    let platform: SocialPlatform
    let totalImpressions: Int
    let totalEngagement: Int
    let postCount: Int
    let viralCount: Int
    let avgEngagementRate: Double
}

struct DailyReachPoint: Sendable {
    let date: String
    let reach: Int
}

struct TopContentItem: Sendable {
    let performanceAtom: Atom
    let contentUUID: String?
    let platform: SocialPlatform
    let impressions: Int
    let engagementRate: Double
    let isViral: Bool
    let viralityScore: Double
}

struct ClientPerformanceData: Sendable {
    let clientUUID: String
    let totalReach: Int
    let totalEngagement: Int
    let contentCount: Int
    let viralCount: Int
    let avgEngagementRate: Double
}

/// Creative dimension data for level system (internal to analytics)
/// Note: Different from UI's CreativeDimensionData in CreativeDimensionData.swift
struct LevelCreativeData: Sendable {
    let weeklyReach: Int
    let viralPostsPerMonth: Int
    let engagementRate: Double  // Percentage (0-100)
    let publishedPerMonth: Int
}
