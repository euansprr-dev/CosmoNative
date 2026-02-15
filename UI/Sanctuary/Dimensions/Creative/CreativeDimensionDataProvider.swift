// CosmoOS/UI/Sanctuary/Dimensions/Creative/CreativeDimensionDataProvider.swift
// Data provider that queries GRDB to build real CreativeDimensionData
// Phase 4: Creative Dashboard Integration
// Phase 5: DimensionScoring conformance, Creative Index, performance wiring

import Foundation
import SwiftUI
import GRDB

// Shared ISO8601 formatter — creating these is expensive, reuse one instance
private let _creativeISOFormatter = ISO8601DateFormatter()

@MainActor
class CreativeDimensionDataProvider: ObservableObject, DimensionScoring {
    nonisolated var dimensionId: String { "creative" }

    @Published var data: CreativeDimensionData = .empty
    @Published var isLoading = false
    @Published var funnelData: [(phase: ContentPhase, count: Int)] = []
    @Published var selectedProfileUUID: String?
    @Published var clientProfiles: [(uuid: String, name: String)] = []
    @Published var creativeIndex: DimensionIndex = .empty

    private let database: any DatabaseWriter

    init(database: (any DatabaseWriter)? = nil) {
        self.database = database ?? (CosmoDatabase.shared.dbQueue! as any DatabaseWriter)
    }

    // MARK: - DimensionScoring

    func computeIndex() async -> DimensionIndex {
        let velocity = await computePublishingVelocity()
        let pipeline = await computePipelineHealth()
        let sessionQuality = await computeCreativeSessionQuality()
        let engagement = await computeEngagementSubScore()
        let growth = await computeGrowthTrajectory()

        let hasSocialData = engagement != nil && growth != nil

        let score: Double
        var subScores: [String: Double] = [:]

        if hasSocialData {
            // Full scoring with social data
            subScores["publishingVelocity"] = velocity
            subScores["pipelineHealth"] = pipeline
            subScores["sessionQuality"] = sessionQuality
            subScores["engagementRate"] = engagement ?? 0
            subScores["growthTrajectory"] = growth ?? 0
            score = velocity * 0.25 + pipeline * 0.20 + sessionQuality * 0.20
                  + (engagement ?? 0) * 0.20 + (growth ?? 0) * 0.15
        } else {
            // Graceful degradation without social APIs
            subScores["publishingVelocity"] = velocity
            subScores["pipelineHealth"] = pipeline
            subScores["sessionQuality"] = sessionQuality
            score = velocity * 0.35 + pipeline * 0.30 + sessionQuality * 0.35
        }

        let confidence = hasSocialData ? 1.0 : 0.6
        let trend = await computeCreativeTrend()

        let index = DimensionIndex(
            score: min(100, max(0, score)),
            confidence: confidence,
            trend: trend,
            subScores: subScores,
            dataAge: 0
        )
        creativeIndex = index
        return index
    }

    func loadClientProfiles() async {
        do {
            let atoms = try await AtomRepository.shared.fetchAll(type: .clientProfile)
            clientProfiles = atoms.compactMap { atom in
                guard let meta = atom.metadataValue(as: ClientProfileMetadata.self) else { return nil }
                return (uuid: atom.uuid, name: meta.clientName)
            }
        } catch {
            clientProfiles = []
        }
    }

    func refreshData() async {
        isLoading = true
        defer { isLoading = false }

        let profileFilter = selectedProfileUUID
        let reach = await calculateTotalReach(timeRange: .month, profileUUID: profileFilter)
        let engagement = await calculateEngagementRate(timeRange: .month, profileUUID: profileFilter)
        let timeSeries = await buildPerformanceTimeSeries(timeRange: .month, profileUUID: profileFilter)
        let posts = await loadRecentPosts(limit: 10, profileUUID: profileFilter)
        let funnel = await buildPipelineFunnel(profileUUID: profileFilter)

        let contentPosts = posts.map { atom -> ContentPost in
            let perf = atom.metadataValue(as: ContentPerformanceMetadata.self)
            let contentMeta = atom.metadataValue(as: ContentAtomMetadata.self)

            let platform: ContentPlatform = {
                guard let sp = perf?.platform ?? contentMeta?.platform else { return .instagram }
                switch sp {
                case .instagram: return .instagram
                case .youtube: return .youtube
                case .tiktok: return .tiktok
                case .twitter: return .twitter
                case .linkedin: return .linkedin
                case .threads: return .threads
                default: return .instagram
                }
            }()

            let postedAt: Date = {
                if let date = _creativeISOFormatter.date(from: atom.createdAt) {
                    return date
                }
                return Date()
            }()

            return ContentPost(
                id: atom.uuid,
                platform: platform,
                type: .post,
                postedAt: postedAt,
                caption: atom.title,
                reach: perf?.reach ?? 0,
                impressions: perf?.impressions ?? 0,
                likes: perf?.likes ?? 0,
                comments: perf?.comments ?? 0,
                shares: perf?.shares ?? 0,
                saves: perf?.saves ?? 0,
                engagementRate: perf?.engagementRate ?? 0,
                performanceVsAverage: (perf?.vsAveragePerformance ?? 1.0 - 1.0) * 100,
                isViral: perf?.isViral ?? false,
                peakTime: 0
            )
        }

        data = CreativeDimensionData(
            totalReach: reach,
            engagementRate: engagement,
            performanceTimeSeries: timeSeries,
            recentPosts: contentPosts
        )
        funnelData = funnel
    }

    // MARK: - Query Methods

    func calculateTotalReach(timeRange: CreativeTimeRange, profileUUID: String? = nil) async -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -timeRange.days, to: Date()) ?? Date()
        let cutoffString = _creativeISOFormatter.string(from: cutoff)

        do {
            return try await database.read { db in
                var request = Atom
                    .filter(Column("type") == AtomType.contentPerformance.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(Column("created_at") >= cutoffString)
                    .filter(sql: "json_extract(metadata, '$.impressions') IS NOT NULL")

                if let uuid = profileUUID {
                    request = request.filter(sql: "json_extract(metadata, '$.clientProfileUUID') = ?", arguments: [uuid])
                }

                let rows = try request.fetchAll(db)

                return rows.reduce(0) { total, atom in
                    let perf = atom.metadataValue(as: ContentPerformanceMetadata.self)
                    return total + (perf?.reach ?? 0)
                }
            }
        } catch {
            return 0
        }
    }

    func calculateEngagementRate(timeRange: CreativeTimeRange, profileUUID: String? = nil) async -> Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -timeRange.days, to: Date()) ?? Date()
        let cutoffString = _creativeISOFormatter.string(from: cutoff)

        do {
            return try await database.read { db in
                var request = Atom
                    .filter(Column("type") == AtomType.contentPerformance.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(Column("created_at") >= cutoffString)

                if let uuid = profileUUID {
                    request = request.filter(sql: "json_extract(metadata, '$.clientProfileUUID') = ?", arguments: [uuid])
                }

                let rows = try request.fetchAll(db)

                guard !rows.isEmpty else { return 0.0 }

                var totalWeightedEngagement = 0.0
                var totalImpressions = 0

                for atom in rows {
                    if let perf = atom.metadataValue(as: ContentPerformanceMetadata.self) {
                        totalWeightedEngagement += perf.engagementRate * Double(perf.impressions)
                        totalImpressions += perf.impressions
                    }
                }

                return totalImpressions > 0 ? totalWeightedEngagement / Double(totalImpressions) : 0.0
            }
        } catch {
            return 0.0
        }
    }

    func buildPerformanceTimeSeries(timeRange: CreativeTimeRange, profileUUID: String? = nil) async -> [PerformanceDataPoint] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -timeRange.days, to: Date()) ?? Date()
        let cutoffString = _creativeISOFormatter.string(from: cutoff)

        do {
            return try await database.read { db in
                var request = Atom
                    .filter(Column("type") == AtomType.contentPerformance.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(Column("created_at") >= cutoffString)
                    .order(Column("created_at").asc)

                if let uuid = profileUUID {
                    request = request.filter(sql: "json_extract(metadata, '$.clientProfileUUID') = ?", arguments: [uuid])
                }

                let rows = try request.fetchAll(db)

                let calendar = Calendar.current
                var grouped: [Date: (reach: Int, engagement: Double, count: Int)] = [:]

                for atom in rows {
                    guard let date = _creativeISOFormatter.date(from: atom.createdAt) else { continue }

                    let dayStart = calendar.startOfDay(for: date)
                    let perf = atom.metadataValue(as: ContentPerformanceMetadata.self)
                    let existing = grouped[dayStart] ?? (reach: 0, engagement: 0, count: 0)
                    grouped[dayStart] = (
                        reach: existing.reach + (perf?.reach ?? 0),
                        engagement: existing.engagement + (perf?.engagementRate ?? 0),
                        count: existing.count + 1
                    )
                }

                return grouped.sorted { $0.key < $1.key }.map { date, values in
                    PerformanceDataPoint(
                        date: date,
                        reach: values.reach,
                        engagement: values.count > 0 ? values.engagement / Double(values.count) : 0,
                        followers: 0
                    )
                }
            }
        } catch {
            return []
        }
    }

    func buildPostingCalendar(month: Date) async -> [Date: PostingDay] {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            return [:]
        }

        let startString = _creativeISOFormatter.string(from: monthStart)
        let endString = _creativeISOFormatter.string(from: monthEnd)

        do {
            return try await database.read { db in
                let rows = try Atom
                    .filter(Column("type") == AtomType.contentPublish.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(Column("created_at") >= startString)
                    .filter(Column("created_at") < endString)
                    .fetchAll(db)

                var dayMap: [Date: Int] = [:]
                for atom in rows {
                    guard let date = _creativeISOFormatter.date(from: atom.createdAt) else { continue }
                    let dayStart = calendar.startOfDay(for: date)
                    dayMap[dayStart, default: 0] += 1
                }

                let today = calendar.startOfDay(for: Date())
                return dayMap.reduce(into: [Date: PostingDay]()) { result, entry in
                    let status: PostingDayStatus = entry.value > 0 ? .posted : .skipped
                    result[entry.key] = PostingDay(
                        date: entry.key,
                        status: status,
                        postCount: entry.value,
                        isToday: entry.key == today
                    )
                }
            }
        } catch {
            return [:]
        }
    }

    func loadRecentPosts(limit: Int, profileUUID: String? = nil) async -> [Atom] {
        do {
            return try await database.read { db in
                var request = Atom
                    .filter(Column("type") == AtomType.content.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(sql: "json_extract(metadata, '$.phase') IN (?, ?)",
                            arguments: [ContentPhase.published.rawValue, ContentPhase.analyzing.rawValue])

                if let uuid = profileUUID {
                    request = request.filter(sql: "json_extract(metadata, '$.clientProfileUUID') = ?", arguments: [uuid])
                }

                return try request
                    .order(Column("updated_at").desc)
                    .limit(limit)
                    .fetchAll(db)
            }
        } catch {
            return []
        }
    }

    func buildPipelineFunnel(profileUUID: String? = nil) async -> [(phase: ContentPhase, count: Int)] {
        var results: [(phase: ContentPhase, count: Int)] = []

        for phase in ContentPhase.allCases {
            let count = await countContentInPhase(phase, profileUUID: profileUUID)
            results.append((phase: phase, count: count))
        }

        return results
    }

    private func countContentInPhase(_ phase: ContentPhase, profileUUID: String? = nil) async -> Int {
        do {
            return try await database.read { db in
                var request = Atom
                    .filter(Column("type") == AtomType.content.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(sql: "json_extract(metadata, '$.phase') = ?", arguments: [phase.rawValue])

                if let uuid = profileUUID {
                    request = request.filter(sql: "json_extract(metadata, '$.clientProfileUUID') = ?", arguments: [uuid])
                }

                return try request.fetchCount(db)
            }
        } catch {
            return 0
        }
    }

    // MARK: - Creative Index Sub-Scores

    /// Publishing Velocity (25%): Published content this week / target (4), capped at 100
    private func computePublishingVelocity() async -> Double {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let cutoff = _creativeISOFormatter.string(from: weekAgo)
        let target = 4.0

        do {
            let count = try await database.read { db -> Int in
                try Atom
                    .filter(Column("type") == AtomType.content.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(Column("created_at") >= cutoff)
                    .filter(sql: "json_extract(metadata, '$.phase') IN (?, ?, ?)",
                            arguments: [ContentPhase.published.rawValue,
                                        ContentPhase.analyzing.rawValue,
                                        ContentPhase.archived.rawValue])
                    .fetchCount(db)
            }
            return min(100, (Double(count) / target) * 100)
        } catch {
            return 0
        }
    }

    /// Pipeline Health (20%): Phases with content / total phases * 100, bonus for 3+ in Ideation
    private func computePipelineHealth() async -> Double {
        let funnel = await buildPipelineFunnel()
        let totalPhases = Double(ContentPhase.allCases.count)
        let phasesWithContent = Double(funnel.filter { $0.count > 0 }.count)
        var score = (phasesWithContent / totalPhases) * 100

        // Bonus for healthy ideation pipeline (3+ ideas in ideation)
        if let ideation = funnel.first(where: { $0.phase == .ideation }), ideation.count >= 3 {
            score = min(100, score + 15)
        }

        return score
    }

    /// Creative Session Quality (20%): Avg focusScore of .writeContent sessions
    private func computeCreativeSessionQuality() async -> Double {
        let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let cutoff = _creativeISOFormatter.string(from: monthAgo)

        do {
            return try await database.read { db -> Double in
                let rows = try Atom
                    .filter(Column("type") == AtomType.deepWorkBlock.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(Column("created_at") >= cutoff)
                    .filter(sql: "json_extract(metadata, '$.intent') = ?",
                            arguments: [TaskIntent.writeContent.rawValue])
                    .fetchAll(db)

                guard !rows.isEmpty else { return 50 } // Default baseline if no sessions

                var totalScore = 0.0
                var count = 0
                for atom in rows {
                    if let meta = atom.metadataValue(as: DeepWorkSessionMetadata.self),
                       let focusScore = meta.focusScore {
                        totalScore += focusScore
                        count += 1
                    }
                }

                return count > 0 ? totalScore / Double(count) : 50
            }
        } catch {
            return 50
        }
    }

    /// Engagement Rate sub-score (20%): From contentPerformance atoms. Returns nil if no data.
    private func computeEngagementSubScore() async -> Double? {
        let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let cutoff = _creativeISOFormatter.string(from: monthAgo)

        do {
            return try await database.read { db -> Double? in
                let rows = try Atom
                    .filter(Column("type") == AtomType.contentPerformance.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(Column("created_at") >= cutoff)
                    .fetchAll(db)

                guard !rows.isEmpty else { return nil }

                var totalEngagement = 0.0
                var count = 0
                for atom in rows {
                    if let perf = atom.metadataValue(as: ContentPerformanceMetadata.self) {
                        totalEngagement += perf.engagementRate
                        count += 1
                    }
                }

                guard count > 0 else { return nil }
                let avgRate = totalEngagement / Double(count)
                // Normalize: 5% engagement = 100 score, linear scale
                return min(100, (avgRate / 5.0) * 100)
            }
        } catch {
            return nil
        }
    }

    /// Growth Trajectory (15%): Week-over-week reach change. Returns nil if no data.
    private func computeGrowthTrajectory() async -> Double? {
        let now = Date()
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now

        let thisWeekReach = await calculateTotalReach(timeRange: .week)
        let lastWeekReach = await reachInRange(from: twoWeeksAgo, to: oneWeekAgo)

        guard lastWeekReach > 0 else {
            return thisWeekReach > 0 ? 60 : nil // Some credit for any reach, nil if no data at all
        }

        let growthPct = (Double(thisWeekReach) - Double(lastWeekReach)) / Double(lastWeekReach) * 100
        // Map: -50% = 0, 0% = 50, +50% = 100
        return min(100, max(0, 50 + growthPct))
    }

    /// Compute creative trend based on last two index computations
    private func computeCreativeTrend() async -> DimensionTrend {
        let thisWeekVelocity = await computePublishingVelocity()
        // Simple heuristic: above 60 = rising, below 30 = falling
        if thisWeekVelocity >= 60 { return .rising }
        if thisWeekVelocity <= 30 { return .falling }
        return .stable
    }

    /// Helper: reach in a specific date range
    private func reachInRange(from: Date, to: Date) async -> Int {
        let fromStr = _creativeISOFormatter.string(from: from)
        let toStr = _creativeISOFormatter.string(from: to)

        do {
            return try await database.read { db in
                let rows = try Atom
                    .filter(Column("type") == AtomType.contentPerformance.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(Column("created_at") >= fromStr)
                    .filter(Column("created_at") < toStr)
                    .fetchAll(db)

                return rows.reduce(0) { total, atom in
                    let perf = atom.metadataValue(as: ContentPerformanceMetadata.self)
                    return total + (perf?.reach ?? 0)
                }
            }
        } catch {
            return 0
        }
    }

    // MARK: - Posting Calendar Data

    /// Build posting calendar data with streak and stats
    func buildPostingCalendarData() async -> (calendar: [Date: PostingDay], streak: Int, bestDay: Weekday, avgPerWeek: Double) {
        let cal = Calendar.current
        let now = Date()
        let threeMonthsAgo = cal.date(byAdding: .month, value: -3, to: now) ?? now
        let cutoff = _creativeISOFormatter.string(from: threeMonthsAgo)

        do {
            let publishedAtoms = try await database.read { db in
                try Atom
                    .filter(Column("type") == AtomType.content.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(Column("created_at") >= cutoff)
                    .filter(sql: "json_extract(metadata, '$.phase') IN (?, ?, ?)",
                            arguments: [ContentPhase.published.rawValue,
                                        ContentPhase.analyzing.rawValue,
                                        ContentPhase.archived.rawValue])
                    .order(Column("created_at").desc)
                    .fetchAll(db)
            }

            // Group by day
            var dayMap: [Date: Int] = [:]
            var weekdayCounts: [Int: Int] = [:]

            for atom in publishedAtoms {
                guard let date = _creativeISOFormatter.date(from: atom.createdAt) else { continue }
                let dayStart = cal.startOfDay(for: date)
                dayMap[dayStart, default: 0] += 1
                let weekday = cal.component(.weekday, from: date) // 1=Sun, 7=Sat
                weekdayCounts[weekday, default: 0] += 1
            }

            // Build PostingDay map
            let today = cal.startOfDay(for: now)
            var postingDays: [Date: PostingDay] = [:]
            for (date, count) in dayMap {
                postingDays[date] = PostingDay(
                    date: date,
                    status: count > 0 ? .posted : .skipped,
                    postCount: count,
                    isToday: date == today
                )
            }

            // Compute streak (consecutive days with posts, ending today or yesterday)
            var streak = 0
            var checkDate = today
            while dayMap[checkDate] != nil && dayMap[checkDate]! > 0 {
                streak += 1
                checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            }
            // If streak is 0, check if yesterday had a post
            if streak == 0 {
                let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today
                checkDate = yesterday
                while dayMap[checkDate] != nil && dayMap[checkDate]! > 0 {
                    streak += 1
                    checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
                }
            }

            // Best posting day of week
            let bestWeekday = weekdayCounts.max(by: { $0.value < $1.value })?.key ?? 4 // Default Wed
            let bestDay: Weekday = {
                // Convert Calendar weekday (1=Sun) to Weekday enum (1=Mon)
                switch bestWeekday {
                case 1: return .sunday
                case 2: return .monday
                case 3: return .tuesday
                case 4: return .wednesday
                case 5: return .thursday
                case 6: return .friday
                case 7: return .saturday
                default: return .wednesday
                }
            }()

            // Average posts per week over 3 months (~13 weeks)
            let weeks = max(1.0, Double(cal.dateComponents([.weekOfYear], from: threeMonthsAgo, to: now).weekOfYear ?? 13))
            let avgPerWeek = Double(publishedAtoms.count) / weeks

            return (calendar: postingDays, streak: streak, bestDay: bestDay, avgPerWeek: avgPerWeek)
        } catch {
            return (calendar: [:], streak: 0, bestDay: .wednesday, avgPerWeek: 0)
        }
    }

    // MARK: - Performance Graph (Native Fallback)

    /// Build native performance time series when no social API data exists.
    /// Uses Posts Published, Writing Minutes, Ideas Generated as metrics.
    func buildNativePerformanceTimeSeries(days: Int) async -> [PerformanceDataPoint] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let cutoffString = _creativeISOFormatter.string(from: cutoff)
        let cal = Calendar.current

        do {
            // Fetch published content atoms grouped by day
            let contentAtoms = try await database.read { db in
                try Atom
                    .filter(Column("type") == AtomType.content.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(Column("created_at") >= cutoffString)
                    .filter(sql: "json_extract(metadata, '$.phase') IN (?, ?, ?)",
                            arguments: [ContentPhase.published.rawValue,
                                        ContentPhase.analyzing.rawValue,
                                        ContentPhase.archived.rawValue])
                    .order(Column("created_at").asc)
                    .fetchAll(db)
            }

            // Fetch writing sessions for writing minutes
            let writingSessions = try await database.read { db in
                try Atom
                    .filter(Column("type") == AtomType.deepWorkBlock.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(Column("created_at") >= cutoffString)
                    .filter(sql: "json_extract(metadata, '$.intent') = ?",
                            arguments: [TaskIntent.writeContent.rawValue])
                    .fetchAll(db)
            }

            // Fetch ideas generated
            let ideas = try await database.read { db in
                try Atom
                    .filter(Column("type") == AtomType.idea.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(Column("created_at") >= cutoffString)
                    .fetchAll(db)
            }

            // Group by day
            var dayData: [Date: (posts: Int, writingMinutes: Int, ideas: Int)] = [:]

            for atom in contentAtoms {
                guard let date = _creativeISOFormatter.date(from: atom.createdAt) else { continue }
                let day = cal.startOfDay(for: date)
                dayData[day, default: (0, 0, 0)].posts += 1
            }

            for atom in writingSessions {
                guard let date = _creativeISOFormatter.date(from: atom.createdAt) else { continue }
                let day = cal.startOfDay(for: date)
                if let meta = atom.metadataValue(as: DeepWorkSessionMetadata.self),
                   let minutes = meta.actualMinutes {
                    dayData[day, default: (0, 0, 0)].writingMinutes += minutes
                }
            }

            for atom in ideas {
                guard let date = _creativeISOFormatter.date(from: atom.createdAt) else { continue }
                let day = cal.startOfDay(for: date)
                dayData[day, default: (0, 0, 0)].ideas += 1
            }

            return dayData.sorted { $0.key < $1.key }.map { date, values in
                PerformanceDataPoint(
                    date: date,
                    reach: values.posts * 100 + values.writingMinutes,  // Composite metric
                    engagement: Double(values.ideas),
                    followers: values.writingMinutes
                )
            }
        } catch {
            return []
        }
    }

    // MARK: - Pipeline Velocity

    /// Average days from Ideation to Published over last 10 pieces
    func computePipelineVelocity() async -> Double? {
        do {
            // Fetch recent published content
            let publishedContent = try await database.read { db in
                try Atom
                    .filter(Column("type") == AtomType.content.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(sql: "json_extract(metadata, '$.phase') IN (?, ?, ?)",
                            arguments: [ContentPhase.published.rawValue,
                                        ContentPhase.analyzing.rawValue,
                                        ContentPhase.archived.rawValue])
                    .order(Column("updated_at").desc)
                    .limit(10)
                    .fetchAll(db)
            }

            guard !publishedContent.isEmpty else { return nil }

            var totalDays = 0.0
            var validCount = 0

            let isoFormatter = _creativeISOFormatter

            for atom in publishedContent {
                guard let createdDate = isoFormatter.date(from: atom.createdAt) else { continue }

                // Check for activatedAt in metadata for more accurate start time
                var startDate = createdDate
                if let meta = atom.metadataValue(as: ContentAtomMetadata.self),
                   let activated = meta.activatedAt,
                   let activatedDate = isoFormatter.date(from: activated) {
                    startDate = activatedDate
                }

                // Use updated_at as proxy for publish date
                if let updatedDate = isoFormatter.date(from: atom.updatedAt) {
                    let days = updatedDate.timeIntervalSince(startDate) / 86400
                    if days >= 0 {
                        totalDays += days
                        validCount += 1
                    }
                }
            }

            return validCount > 0 ? totalDays / Double(validCount) : nil
        } catch {
            return nil
        }
    }

    // MARK: - Content to Social Post Auto-Linking

    /// Auto-link published content to social posts by caption similarity.
    /// When social posts are synced, match by caption text (>80% similarity).
    func autoLinkContentToSocialPosts() async {
        do {
            let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            let cutoff = _creativeISOFormatter.string(from: weekAgo)

            // Fetch recent published content
            let recentContent = try await database.read { db in
                try Atom
                    .filter(Column("type") == AtomType.content.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(Column("created_at") >= cutoff)
                    .filter(sql: "json_extract(metadata, '$.phase') IN (?, ?)",
                            arguments: [ContentPhase.published.rawValue,
                                        ContentPhase.analyzing.rawValue])
                    .fetchAll(db)
            }

            // Fetch recent social post atoms (when social sync creates them)
            let socialPosts = try await database.read { db in
                try Atom
                    .filter(Column("type") == AtomType.contentPerformance.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(Column("created_at") >= cutoff)
                    .fetchAll(db)
            }

            guard !recentContent.isEmpty && !socialPosts.isEmpty else { return }

            for content in recentContent {
                guard let contentTitle = content.title, !contentTitle.isEmpty else { continue }

                for post in socialPosts {
                    guard let postBody = post.body, !postBody.isEmpty else { continue }

                    let similarity = stringSimilarity(contentTitle, postBody)
                    if similarity > 0.8 {
                        // Create bidirectional link via AtomLinks
                        let link = AtomLink(type: "contentToSocialPost", uuid: post.uuid, entityType: "contentPerformance")
                        let reverseLink = AtomLink(type: "socialPostToContent", uuid: content.uuid, entityType: "content")

                        try await database.write { db in
                            // Add link to content atom
                            var contentAtom = content
                            var existingLinks = contentAtom.linksList
                            if !existingLinks.contains(where: { $0.uuid == post.uuid }) {
                                existingLinks.append(link)
                                if let data = try? JSONEncoder().encode(existingLinks) {
                                    contentAtom.links = String(data: data, encoding: .utf8)
                                }
                                try contentAtom.update(db)
                            }

                            // Add reverse link to social post atom
                            var postAtom = post
                            var postLinks = postAtom.linksList
                            if !postLinks.contains(where: { $0.uuid == content.uuid }) {
                                postLinks.append(reverseLink)
                                if let data = try? JSONEncoder().encode(postLinks) {
                                    postAtom.links = String(data: data, encoding: .utf8)
                                }
                                try postAtom.update(db)
                            }
                        }
                    }
                }
            }
        } catch {
            // Silently fail — linking is non-critical
        }
    }

    /// Simple string similarity using Jaccard index on word sets
    private func stringSimilarity(_ a: String, _ b: String) -> Double {
        let wordsA = Set(a.lowercased().split(separator: " ").map(String.init))
        let wordsB = Set(b.lowercased().split(separator: " ").map(String.init))
        guard !wordsA.isEmpty || !wordsB.isEmpty else { return 0 }
        let intersection = wordsA.intersection(wordsB).count
        let union = wordsA.union(wordsB).count
        return union > 0 ? Double(intersection) / Double(union) : 0
    }
}
