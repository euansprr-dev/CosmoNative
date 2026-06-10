// CosmoOS/Agent/Intelligence/AudienceIntelligenceEngine.swift
// Synthesizes social platform data into actionable audience insights
// Correlates engagement patterns with content types, hook styles, and timing.

import Foundation

@MainActor
class AudienceIntelligenceEngine {
    static let shared = AudienceIntelligenceEngine()

    private let atomRepo = AtomRepository.shared
    private let syncService = SocialSyncService.shared

    private init() {}

    // MARK: - Engagement Patterns

    /// Analyze content performance by hook type, day of week, and format.
    /// Returns a formatted analysis string.
    func getEngagementPatterns() async -> String {
        let contentWithPerf = await fetchContentWithPerformance()

        guard !contentWithPerf.isEmpty else {
            return "Not enough published content to analyze engagement patterns. Publish more content to unlock insights."
        }

        var lines: [String] = ["## Engagement Patterns"]

        // 1. By hook type
        let hookEngagement = analyzeByHookType(contentWithPerf)
        if !hookEngagement.isEmpty {
            lines.append("")
            lines.append("**By Hook Type:**")
            let sorted = hookEngagement.sorted { $0.value > $1.value }
            for (hook, avgEngagement) in sorted.prefix(5) {
                let hookName = formatHookName(hook)
                lines.append("- \(hookName): \(String(format: "%.1f%%", avgEngagement * 100)) avg engagement")
            }
        }

        // 2. By day of week
        let dayEngagement = analyzeByDayOfWeek(contentWithPerf)
        if !dayEngagement.isEmpty {
            lines.append("")
            lines.append("**By Day of Week:**")
            let dayOrder = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
            let sorted = dayEngagement.sorted { day1, day2 in
                let idx1 = dayOrder.firstIndex(of: day1.key) ?? 0
                let idx2 = dayOrder.firstIndex(of: day2.key) ?? 0
                return day1.value > day2.value || (day1.value == day2.value && idx1 < idx2)
            }
            for (day, avgEngagement) in sorted.prefix(3) {
                lines.append("- \(day): \(String(format: "%.1f%%", avgEngagement * 100)) avg engagement")
            }
        }

        // 3. By format/platform
        let platformEngagement = analyzeByPlatform(contentWithPerf)
        if !platformEngagement.isEmpty {
            lines.append("")
            lines.append("**By Platform:**")
            let sorted = platformEngagement.sorted { $0.value > $1.value }
            for (platform, avgEngagement) in sorted {
                lines.append("- \(platform.capitalized): \(String(format: "%.1f%%", avgEngagement * 100)) avg engagement")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Growth Drivers

    /// Correlate growth spikes with content types.
    func getGrowthDrivers() async -> String {
        let platforms = syncService.connectedPlatforms
        guard !platforms.isEmpty else {
            return "No social platforms connected. Connect a platform in Settings to unlock growth insights."
        }

        var lines: [String] = ["## Growth Drivers"]

        let contentWithPerf = await fetchContentWithPerformance()
        let recentContent = contentWithPerf.filter { item in
            guard let dateStr = item.atom.metadataDict?["activatedAt"] as? String ??
                    Optional(item.atom.createdAt),
                  let date = ISO8601.date(from: dateStr) else {
                return false
            }
            return date > Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        }

        if recentContent.isEmpty {
            lines.append("No recent published content to correlate with growth. Publish more to see drivers.")
            return lines.joined(separator: "\n")
        }

        // Find top-performing recent content
        let sorted = recentContent.sorted { item1, item2 in
            let eng1 = (item1.performance?["engagementRate"] as? Double) ?? 0
            let eng2 = (item2.performance?["engagementRate"] as? Double) ?? 0
            return eng1 > eng2
        }

        let topPerformers = sorted.prefix(3)
        if !topPerformers.isEmpty {
            lines.append("")
            lines.append("**Top-performing recent content:**")
            for item in topPerformers {
                let title = item.atom.title ?? "Untitled"
                let engRate = (item.performance?["engagementRate"] as? Double) ?? 0
                var detail = "\(title) (\(String(format: "%.1f%%", engRate * 100)) engagement)"

                if let analysis = item.atom.swipeAnalysis, let hookType = analysis.hookType {
                    detail += " -- \(hookType.displayName) hook"
                }
                lines.append("- \(detail)")
            }
        }

        // Identify common traits in top content
        var hookCounts: [String: Int] = [:]
        var frameworkCounts: [String: Int] = [:]
        for item in topPerformers {
            if let analysis = item.atom.swipeAnalysis {
                if let hook = analysis.hookType {
                    hookCounts[hook.displayName, default: 0] += 1
                }
                if let fw = analysis.frameworkType {
                    frameworkCounts[fw.displayName, default: 0] += 1
                }
            }
        }

        if let topHook = hookCounts.max(by: { $0.value < $1.value }) {
            lines.append("")
            lines.append("Your recent growth correlated with \(topHook.key) hooks.")
        }
        if let topFw = frameworkCounts.max(by: { $0.value < $1.value }) {
            lines.append("Best-performing framework: \(topFw.key).")
        }

        // Platform-level growth snapshot
        lines.append("")
        lines.append("**Platform Snapshot:**")
        for platform in platforms {
            if let result = syncService.lastSyncResults[platform] {
                lines.append("- \(platform.displayName): \(result.followerCount) followers, \(String(format: "%.1f%%", result.engagementRate * 100)) engagement rate")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Audience Profile

    /// Synthesize engagement patterns into an audience persona description.
    func getAudienceProfile() async -> String {
        let platforms = syncService.connectedPlatforms
        let contentWithPerf = await fetchContentWithPerformance()

        var lines: [String] = ["## Audience Profile"]

        if contentWithPerf.isEmpty && platforms.isEmpty {
            lines.append("Connect platforms and publish content to build your audience profile.")
            return lines.joined(separator: "\n")
        }

        // Engagement ratio analysis: saves vs shares vs likes
        var totalLikes = 0
        var totalComments = 0
        var totalSaves = 0
        var totalShares = 0

        for platform in platforms {
            if let result = syncService.lastSyncResults[platform] {
                for post in result.recentPosts {
                    totalLikes += post.likes
                    totalComments += post.comments
                    totalSaves += post.saves
                    totalShares += post.shares
                }
            }
        }

        let totalEngagements = totalLikes + totalComments + totalSaves + totalShares
        if totalEngagements > 0 {
            lines.append("")
            lines.append("**Engagement Breakdown:**")
            lines.append("- Likes: \(String(format: "%.0f%%", Double(totalLikes) / Double(totalEngagements) * 100))")
            lines.append("- Comments: \(String(format: "%.0f%%", Double(totalComments) / Double(totalEngagements) * 100))")
            lines.append("- Saves: \(String(format: "%.0f%%", Double(totalSaves) / Double(totalEngagements) * 100))")
            lines.append("- Shares: \(String(format: "%.0f%%", Double(totalShares) / Double(totalEngagements) * 100))")

            // Interpret the ratios
            let saveRatio = Double(totalSaves) / Double(totalEngagements)
            let shareRatio = Double(totalShares) / Double(totalEngagements)
            let commentRatio = Double(totalComments) / Double(totalEngagements)

            lines.append("")
            if saveRatio > 0.3 {
                lines.append("High save rate indicates your audience values your content as a reference. They are learners and note-takers.")
            } else if shareRatio > 0.2 {
                lines.append("High share rate suggests your content resonates emotionally. Your audience are advocates who want to spread your message.")
            } else if commentRatio > 0.15 {
                lines.append("High comment rate shows strong community engagement. Your audience wants to participate in the conversation.")
            } else {
                lines.append("Balanced engagement suggests a broad appeal across different audience segments.")
            }
        }

        // Topic preferences from top content
        let topContent = contentWithPerf
            .sorted { item1, item2 in
                let eng1 = (item1.performance?["engagementRate"] as? Double) ?? 0
                let eng2 = (item2.performance?["engagementRate"] as? Double) ?? 0
                return eng1 > eng2
            }
            .prefix(10)

        let topTopics = topContent.compactMap { $0.atom.title }
        if !topTopics.isEmpty {
            lines.append("")
            lines.append("**Topics your audience responds to:**")
            for topic in topTopics.prefix(5) {
                lines.append("- \(topic)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Best Posting Times

    /// Per-platform best posting times based on historical performance.
    func getBestPostingTimes() async -> [String: String] {
        var result: [String: String] = [:]
        let contentWithPerf = await fetchContentWithPerformance()

        guard !contentWithPerf.isEmpty else { return result }

        let isoFormatter = ISO8601DateFormatter()
        let calendar = Calendar.current
        let hourFormatter = DateFormatter()
        hourFormatter.dateFormat = "ha"

        // Group by platform and find best-performing hours
        var platformHourPerformance: [String: [Int: [Double]]] = [:]

        for item in contentWithPerf {
            let platform: String
            if let meta = item.atom.metadataValue(as: ContentAtomMetadata.self),
               let p = meta.platform {
                platform = p.rawValue
            } else {
                platform = "general"
            }

            guard let dateStr = item.atom.metadataDict?["activatedAt"] as? String ??
                    Optional(item.atom.createdAt),
                  let date = isoFormatter.date(from: dateStr) else {
                continue
            }

            let hour = calendar.component(.hour, from: date)
            let engagement = (item.performance?["engagementRate"] as? Double) ?? 0

            platformHourPerformance[platform, default: [:]][hour, default: []].append(engagement)
        }

        for (platform, hourData) in platformHourPerformance {
            // Average engagement per hour
            let hourAvg = hourData.mapValues { values in
                values.reduce(0, +) / Double(values.count)
            }

            if let bestHour = hourAvg.max(by: { $0.value < $1.value }) {
                var components = DateComponents()
                components.hour = bestHour.key
                if let date = calendar.date(from: components) {
                    result[platform] = hourFormatter.string(from: date).lowercased()
                } else {
                    result[platform] = "\(bestHour.key):00"
                }
            }
        }

        return result
    }

    // MARK: - Performance Summary

    /// Quick performance overview for the last N days.
    func getPerformanceSummary(days: Int = 30) async -> String {
        let platforms = syncService.connectedPlatforms
        var lines: [String] = ["## Performance Summary (Last \(days) Days)"]

        if platforms.isEmpty {
            lines.append("No platforms connected. Connect a social platform in Settings.")
            return lines.joined(separator: "\n")
        }

        // Platform-level stats
        for platform in platforms {
            guard let result = syncService.lastSyncResults[platform] else { continue }

            lines.append("")
            lines.append("**\(platform.displayName)**")
            lines.append("- Followers: \(result.followerCount)")
            lines.append("- Engagement Rate: \(String(format: "%.2f%%", result.engagementRate * 100))")
            lines.append("- Total Reach: \(result.totalReach)")
            lines.append("- Recent Posts: \(result.recentPosts.count)")

            if !result.recentPosts.isEmpty {
                let avgLikes = result.recentPosts.map { $0.likes }.reduce(0, +) / result.recentPosts.count
                let avgComments = result.recentPosts.map { $0.comments }.reduce(0, +) / result.recentPosts.count
                lines.append("- Avg Likes: \(avgLikes)")
                lines.append("- Avg Comments: \(avgComments)")
            }
        }

        // Content pipeline throughput
        do {
            let contentAtoms = try await atomRepo.fetchAll(type: .content)
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let isoFormatter = ISO8601DateFormatter()

            let recentContent = contentAtoms.filter { atom in
                guard let date = isoFormatter.date(from: atom.createdAt) else { return false }
                return date > cutoff
            }

            let published = recentContent.filter { atom in
                guard let meta = atom.metadataValue(as: ContentAtomMetadata.self) else { return false }
                return meta.phase == .published || meta.phase == .analyzing || meta.phase == .archived
            }

            lines.append("")
            lines.append("**Content Pipeline (\(days)d):**")
            lines.append("- Total pieces created: \(recentContent.count)")
            lines.append("- Published: \(published.count)")
            lines.append("- Publish rate: \(String(format: "%.0f%%", recentContent.isEmpty ? 0 : Double(published.count) / Double(recentContent.count) * 100))")
        } catch {
            // Content stats unavailable
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    /// Fetch content atoms paired with their performance data (if available).
    private func fetchContentWithPerformance() async -> [(atom: Atom, performance: [String: Any]?)] {
        do {
            let contentAtoms = try await atomRepo.fetchAll(type: .content)
            let performanceAtoms = try await atomRepo.fetchAll(type: .contentPerformance)

            // Build a lookup: content UUID -> performance metadata
            var performanceLookup: [String: [String: Any]] = [:]
            for perfAtom in performanceAtoms {
                // Performance atoms link to content via links or metadata
                if let dict = perfAtom.metadataDict,
                   let contentUUID = dict["contentAtomUUID"] as? String {
                    performanceLookup[contentUUID] = dict
                }
                // Also check links
                for link in perfAtom.linksList {
                    if performanceLookup[link.uuid] == nil {
                        performanceLookup[link.uuid] = perfAtom.metadataDict
                    }
                }
            }

            return contentAtoms.map { atom in
                let perf = performanceLookup[atom.uuid]
                return (atom: atom, performance: perf)
            }
        } catch {
            return []
        }
    }

    /// Compute per-platform engagement rates from SocialSyncService.
    private func platformEngagementRates() async -> [String: Double] {
        var rates: [String: Double] = [:]
        for platform in syncService.connectedPlatforms {
            if let result = syncService.lastSyncResults[platform] {
                rates[platform.rawValue] = result.engagementRate
            }
        }
        return rates
    }

    /// Group content performance by hook type and compute average engagement.
    private func analyzeByHookType(_ items: [(atom: Atom, performance: [String: Any]?)]) -> [String: Double] {
        var hookEngagements: [String: [Double]] = [:]

        for item in items {
            guard let analysis = item.atom.swipeAnalysis,
                  let hookType = analysis.hookType,
                  let perf = item.performance,
                  let engagement = perf["engagementRate"] as? Double else { continue }

            hookEngagements[hookType.rawValue, default: []].append(engagement)
        }

        return hookEngagements.mapValues { values in
            values.reduce(0, +) / Double(values.count)
        }
    }

    /// Group content performance by day of week.
    private func analyzeByDayOfWeek(_ items: [(atom: Atom, performance: [String: Any]?)]) -> [String: Double] {
        let isoFormatter = ISO8601DateFormatter()
        let calendar = Calendar.current
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"

        var dayEngagements: [String: [Double]] = [:]

        for item in items {
            guard let dateStr = item.atom.metadataDict?["activatedAt"] as? String ??
                    Optional(item.atom.createdAt),
                  let date = isoFormatter.date(from: dateStr),
                  let perf = item.performance,
                  let engagement = perf["engagementRate"] as? Double else { continue }

            let dayName = dayFormatter.string(from: date)
            dayEngagements[dayName, default: []].append(engagement)
        }

        return dayEngagements.mapValues { values in
            values.reduce(0, +) / Double(values.count)
        }
    }

    /// Group content performance by platform.
    private func analyzeByPlatform(_ items: [(atom: Atom, performance: [String: Any]?)]) -> [String: Double] {
        var platformEngagements: [String: [Double]] = [:]

        for item in items {
            guard let perf = item.performance,
                  let engagement = perf["engagementRate"] as? Double else { continue }

            let platform: String
            if let meta = item.atom.metadataValue(as: ContentAtomMetadata.self),
               let p = meta.platform {
                platform = p.rawValue
            } else {
                platform = "unknown"
            }

            platformEngagements[platform, default: []].append(engagement)
        }

        return platformEngagements.mapValues { values in
            values.reduce(0, +) / Double(values.count)
        }
    }

    /// Format a hook type raw value into a display name.
    private func formatHookName(_ rawValue: String) -> String {
        if let hookType = SwipeHookType(rawValue: rawValue) {
            return hookType.displayName
        }
        return rawValue
            .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .capitalized
    }
}
