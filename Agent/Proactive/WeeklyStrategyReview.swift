// CosmoOS/Agent/Proactive/WeeklyStrategyReview.swift
// Sunday evening strategic review with performance analysis and next-week plan

import Foundation

@MainActor
class WeeklyStrategyReview {

    private let atomRepo = AtomRepository.shared

    // MARK: - Nested Types

    struct WeeklyStats {
        let publishedCount: Int
        let bestPerformingTitle: String?
        let bestPerformingHookType: String?
        let bestPerformingFramework: String?
        let swipesStudied: Int
        let ideasCaptured: Int
        let topHookTypeThisWeek: String?
        let contentStreak: Int
    }

    // MARK: - Public API

    /// Generate the full weekly review as structured plain text (for Telegram).
    func generate() async -> String {
        let stats = await getWeeklyStats()

        var review = "WEEKLY STRATEGY REVIEW\n"
        review += String(repeating: "-", count: 28) + "\n\n"

        // Published this week
        review += "Published: \(stats.publishedCount) piece\(stats.publishedCount == 1 ? "" : "s") this week\n"

        // Best performer
        if let bestTitle = stats.bestPerformingTitle {
            review += "\nBest Performer: \"\(bestTitle)\"\n"
            if let hookType = stats.bestPerformingHookType {
                review += "  Hook: \(hookType)\n"
            }
            if let framework = stats.bestPerformingFramework {
                review += "  Framework: \(framework)\n"
            }
        } else if stats.publishedCount > 0 {
            review += "\nNo performance data available yet for this week's content.\n"
        }

        // Swipes studied
        review += "\nSwipes Studied: \(stats.swipesStudied)\n"
        if let topHook = stats.topHookTypeThisWeek {
            review += "  Most-saved hook type: \(topHook)\n"
        }

        // Ideas captured
        review += "\nIdeas Captured: \(stats.ideasCaptured)\n"

        // Content streak
        if stats.contentStreak >= 2 {
            review += "\nStreak: \(stats.contentStreak) consecutive days publishing\n"
        }

        // Recommendations
        review += "\n" + String(repeating: "-", count: 28) + "\n"
        review += "RECOMMENDATIONS\n\n"

        let recommendations = buildRecommendations(stats: stats)
        for (index, rec) in recommendations.enumerated() {
            review += "\(index + 1). \(rec)\n"
        }

        if recommendations.isEmpty {
            review += "Keep building. More data means sharper insights next week.\n"
        }

        return review
    }

    /// Compute raw weekly statistics.
    func getWeeklyStats() async -> WeeklyStats {
        let published = await contentPublishedThisWeek()
        let swipes = await atomsCreatedThisWeek(type: .research, swipeOnly: true)
        let ideas = await atomsCreatedThisWeek(type: .idea)

        // Find best-performing piece
        var bestTitle: String?
        var bestHookType: String?
        var bestFramework: String?
        var bestEngagement: Double = 0

        let performanceAtoms = (try? await atomRepo.fetchAll(type: .contentPerformance)) ?? []
        let weekAgoStr = weekAgoPrefix()

        for contentAtom in published {
            let perfAtom = performanceAtoms.first { perf in
                guard let meta = perf.metadataDict else { return false }
                return meta["contentAtomUUID"] as? String == contentAtom.uuid
            }

            let engagement = extractEngagement(from: perfAtom)
            if engagement > bestEngagement {
                bestEngagement = engagement
                bestTitle = contentAtom.title
                if let meta = contentAtom.metadataDict {
                    if let hook = meta["hookType"] as? String,
                       let hookType = SwipeHookType(rawValue: hook) {
                        bestHookType = hookType.displayName
                    }
                    if let fw = meta["frameworkType"] as? String,
                       let framework = SwipeFrameworkType(rawValue: fw) {
                        bestFramework = framework.displayName
                    }
                }
            }
        }

        // Top hook type from swipes this week
        var swipeHookCounts: [String: Int] = [:]
        for swipe in swipes {
            if let analysis = swipe.swipeAnalysis,
               let hookType = analysis.hookType {
                swipeHookCounts[hookType.displayName, default: 0] += 1
            }
        }
        let topHookType = swipeHookCounts.max(by: { $0.value < $1.value })?.key

        // Calculate content streak
        let contentStreak = await calculateContentStreak()

        return WeeklyStats(
            publishedCount: published.count,
            bestPerformingTitle: bestTitle,
            bestPerformingHookType: bestHookType,
            bestPerformingFramework: bestFramework,
            swipesStudied: swipes.count,
            ideasCaptured: ideas.count,
            topHookTypeThisWeek: topHookType,
            contentStreak: contentStreak
        )
    }

    // MARK: - Private Helpers

    /// Fetch atoms of a given type created in the last 7 days.
    private func atomsCreatedThisWeek(type: AtomType, swipeOnly: Bool = false) async -> [Atom] {
        do {
            let allAtoms = try await atomRepo.fetchAll(type: type)
            let weekAgoStr = weekAgoPrefix()

            return allAtoms.filter { atom in
                guard atom.createdAt >= weekAgoStr else { return false }
                if swipeOnly {
                    return atom.isSwipeFileAtom
                }
                return true
            }
        } catch {
            return []
        }
    }

    /// Fetch content atoms that moved to published phase this week.
    private func contentPublishedThisWeek() async -> [Atom] {
        do {
            let contentAtoms = try await atomRepo.fetchAll(type: .content)
            let weekAgoStr = weekAgoPrefix()

            return contentAtoms.filter { atom in
                guard let meta = atom.metadataDict else { return false }
                let phase = meta["phase"] as? String
                let isPublished = phase == ContentPhase.published.rawValue
                    || phase == ContentPhase.analyzing.rawValue
                    || phase == ContentPhase.archived.rawValue

                // Check if published this week by looking at updatedAt or publishedAt
                let publishedAt = meta["publishedAt"] as? String ?? atom.updatedAt
                return isPublished && publishedAt >= weekAgoStr
            }
        } catch {
            return []
        }
    }

    /// Calculate consecutive days with published content, counting backwards from today.
    private func calculateContentStreak() async -> Int {
        do {
            let contentAtoms = try await atomRepo.fetchAll(type: .content)
            let publishedAtoms = contentAtoms.filter { atom in
                guard let meta = atom.metadataDict else { return false }
                let phase = meta["phase"] as? String
                return phase == ContentPhase.published.rawValue
                    || phase == ContentPhase.analyzing.rawValue
                    || phase == ContentPhase.archived.rawValue
            }

            guard !publishedAtoms.isEmpty else { return 0 }

            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"

            var streak = 0
            var checkDate = today

            for _ in 0..<30 {
                let dateStr = dateFormatter.string(from: checkDate)
                let hasContent = publishedAtoms.contains { atom in
                    guard let meta = atom.metadataDict else {
                        return atom.updatedAt.hasPrefix(dateStr)
                    }
                    let publishedAt = meta["publishedAt"] as? String ?? atom.updatedAt
                    return publishedAt.hasPrefix(dateStr)
                }

                if hasContent {
                    streak += 1
                    checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
                } else {
                    break
                }
            }

            return streak
        } catch {
            return 0
        }
    }

    /// Build 2-3 specific recommendations based on weekly stats.
    private func buildRecommendations(stats: WeeklyStats) -> [String] {
        var recommendations: [String] = []

        // Recommendation based on publishing volume
        if stats.publishedCount == 0 {
            recommendations.append("You didn't publish this week. Even one piece keeps the algorithm working for you.")
        } else if stats.publishedCount >= 5 {
            recommendations.append("Strong output this week. Focus on quality over quantity next week -- pick your best 3 ideas.")
        }

        // Recommendation based on swipe study
        if stats.swipesStudied == 0 {
            recommendations.append("Study 3-5 swipes this week to keep your creative inputs fresh.")
        } else if stats.swipesStudied >= 10 {
            if let topHook = stats.topHookTypeThisWeek {
                recommendations.append("You studied \(stats.swipesStudied) swipes, mostly \(topHook). Try writing a piece using that hook style.")
            }
        }

        // Recommendation based on best performer
        if let bestHook = stats.bestPerformingHookType, let bestFw = stats.bestPerformingFramework {
            recommendations.append("Your best combo this week was \(bestHook) + \(bestFw). Use it again next week with a fresh topic.")
        } else if let bestHook = stats.bestPerformingHookType {
            recommendations.append("Your \(bestHook) hook worked best. Double down on it next week.")
        }

        // Recommendation based on ideas
        if stats.ideasCaptured == 0 {
            recommendations.append("Capture at least 3 ideas this week. Voice notes count.")
        } else if stats.ideasCaptured >= 10 && stats.publishedCount < 3 {
            recommendations.append("You have \(stats.ideasCaptured) fresh ideas but only published \(stats.publishedCount). Pick the strongest and ship it.")
        }

        // Cap at 3 recommendations
        return Array(recommendations.prefix(3))
    }

    /// Extract engagement rate from a performance atom.
    private func extractEngagement(from atom: Atom?) -> Double {
        guard let atom = atom,
              let structuredStr = atom.structured,
              let data = structuredStr.data(using: .utf8) else {
            return 0
        }

        if let perfMeta = try? JSONDecoder().decode(ContentPerformanceMetadata.self, from: data) {
            return perfMeta.engagementRate
        }

        if let meta = atom.metadataDict,
           let rate = meta["engagementRate"] as? Double {
            return rate
        }

        return 0
    }

    /// ISO 8601 date string for 7 days ago.
    private func weekAgoPrefix() -> String {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: weekAgo)
    }
}
