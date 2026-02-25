// CosmoOS/Agent/Proactive/IntelligentAlertEngine.swift
// Event-driven intelligent alerts that push insights when they matter

import Foundation

@MainActor
class IntelligentAlertEngine {
    static let shared = IntelligentAlertEngine()

    // MARK: - Properties

    /// Track when each alert type was last sent (prevent spam).
    /// Persisted to UserDefaults so alerts don't spam on app restart.
    private var lastAlertTimes: [String: Date] = [:] {
        didSet { persistCooldowns() }
    }

    /// Minimum 1 hour between same alert type
    private let minimumAlertInterval: TimeInterval = 3600

    private let atomRepo = AtomRepository.shared

    private init() {
        loadPersistedCooldowns()
    }

    /// Load persisted cooldown times from UserDefaults.
    private func loadPersistedCooldowns() {
        guard let dict = UserDefaults.standard.dictionary(forKey: "intelligent_alert_cooldowns") as? [String: Double] else { return }
        for (key, interval) in dict {
            lastAlertTimes[key] = Date(timeIntervalSince1970: interval)
        }
    }

    /// Persist cooldown times to UserDefaults.
    private func persistCooldowns() {
        let dict = lastAlertTimes.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(dict, forKey: "intelligent_alert_cooldowns")
    }

    // MARK: - Alert Evaluation

    /// Run all checks and return any triggered alerts (respecting cooldown)
    func evaluateAll() async -> [String] {
        var alerts: [String] = []

        if let alert = await checkPatternDiscovery() {
            alerts.append(alert)
        }
        if let alert = await checkPerformanceAlert() {
            alerts.append(alert)
        }
        if let alert = await checkCreativeMomentum() {
            alerts.append(alert)
        }
        if let alert = await checkStaleContent() {
            alerts.append(alert)
        }
        if let alert = await checkSwipeInsight() {
            alerts.append(alert)
        }

        return alerts
    }

    // MARK: - Pattern Discovery

    /// Analyze last 20 published pieces for patterns.
    /// If one hook type outperforms average by 2x+, generate alert.
    func checkPatternDiscovery() async -> String? {
        guard shouldSendAlert(type: "pattern_discovery") else { return nil }

        do {
            let contentAtoms = try await atomRepo.fetchAll(type: .content)

            // Filter to published content that has metadata
            let publishedAtoms = contentAtoms.filter { atom in
                guard let meta = atom.metadataDict else { return false }
                let phase = meta["phase"] as? String
                return phase == ContentPhase.published.rawValue
                    || phase == ContentPhase.analyzing.rawValue
                    || phase == ContentPhase.archived.rawValue
            }

            let recentPublished = Array(publishedAtoms.prefix(20))
            guard recentPublished.count >= 5 else { return nil }

            // Load performance data for published content
            let performanceAtoms = try await atomRepo.fetchAll(type: .contentPerformance)

            // Build hook type -> engagement mapping
            var hookEngagements: [String: [Double]] = [:]
            for atom in recentPublished {
                guard let meta = atom.metadataDict,
                      let hookType = meta["hookType"] as? String else { continue }

                // Find matching performance atom
                let perfAtom = performanceAtoms.first { perf in
                    guard let perfMeta = perf.metadataDict else { return false }
                    return perfMeta["contentAtomUUID"] as? String == atom.uuid
                }

                let engagement = extractEngagementRate(from: perfAtom)
                hookEngagements[hookType, default: []].append(engagement)
            }

            guard !hookEngagements.isEmpty else { return nil }

            // Calculate averages per hook type
            var hookAverages: [String: Double] = [:]
            for (hook, engagements) in hookEngagements {
                guard !engagements.isEmpty else { continue }
                hookAverages[hook] = engagements.reduce(0, +) / Double(engagements.count)
            }

            // Overall average
            let allEngagements = hookEngagements.values.flatMap { $0 }
            guard !allEngagements.isEmpty else { return nil }
            let overallAverage = allEngagements.reduce(0, +) / Double(allEngagements.count)
            guard overallAverage > 0 else { return nil }

            // Find best performer
            guard let (bestHook, bestAvg) = hookAverages.max(by: { $0.value < $1.value }) else {
                return nil
            }

            let multiplier = bestAvg / overallAverage
            guard multiplier >= 2.0 else { return nil }

            // Find the weakest hook for contrast
            let (weakestHook, _) = hookAverages.min(by: { $0.value < $1.value }) ?? (bestHook, bestAvg)

            let formattedMultiplier = String(format: "%.1fx", multiplier)
            let bestDisplayName = hookTypeDisplayName(bestHook)
            let weakestDisplayName = hookTypeDisplayName(weakestHook)

            markAlertSent(type: "pattern_discovery")
            return "Your \(bestDisplayName) hooks get \(formattedMultiplier) more engagement than your \(weakestDisplayName) hooks. Consider leaning into this pattern."
        } catch {
            return nil
        }
    }

    // MARK: - Performance Alert

    /// Find any recent content outperforming by 3x+ above average.
    func checkPerformanceAlert() async -> String? {
        guard shouldSendAlert(type: "performance_alert") else { return nil }

        do {
            let performanceAtoms = try await atomRepo.fetchAll(type: .contentPerformance)
            guard performanceAtoms.count >= 3 else { return nil }

            // Calculate average engagement across all performance atoms
            var engagements: [Double] = []
            for atom in performanceAtoms {
                let rate = extractEngagementRate(from: atom)
                if rate > 0 {
                    engagements.append(rate)
                }
            }

            guard !engagements.isEmpty else { return nil }
            let average = engagements.reduce(0, +) / Double(engagements.count)
            guard average > 0 else { return nil }

            // Check recent performance atoms (last 7 days)
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            let sevenDaysAgoStr = ISO8601DateFormatter().string(from: sevenDaysAgo)

            let recentPerf = performanceAtoms.filter { $0.createdAt >= sevenDaysAgoStr }

            for perfAtom in recentPerf {
                let rate = extractEngagementRate(from: perfAtom)
                let multiplier = rate / average
                guard multiplier >= 3.0 else { continue }

                // Find the parent content atom for title and hook info
                guard let meta = perfAtom.metadataDict,
                      let contentUUID = meta["contentAtomUUID"] as? String,
                      let contentAtom = try? await atomRepo.fetch(uuid: contentUUID) else {
                    continue
                }

                let title = contentAtom.title ?? "Untitled piece"
                let hookInfo: String
                if let contentMeta = contentAtom.metadataDict,
                   let hookType = contentMeta["hookType"] as? String {
                    hookInfo = " It used \(hookTypeDisplayName(hookType))."
                } else {
                    hookInfo = ""
                }

                let formattedMultiplier = String(format: "%.0fx", multiplier)
                markAlertSent(type: "performance_alert")
                return "\"\(title)\" is outperforming by \(formattedMultiplier).\(hookInfo)"
            }

            return nil
        } catch {
            return nil
        }
    }

    // MARK: - Creative Momentum

    /// Detect streaks of consecutive days with published content.
    /// If 3+ day streak, encourage.
    func checkCreativeMomentum() async -> String? {
        guard shouldSendAlert(type: "creative_momentum") else { return nil }

        do {
            let contentAtoms = try await atomRepo.fetchAll(type: .content)

            // Filter to published/analyzing/archived content
            let publishedAtoms = contentAtoms.filter { atom in
                guard let meta = atom.metadataDict else { return false }
                let phase = meta["phase"] as? String
                return phase == ContentPhase.published.rawValue
                    || phase == ContentPhase.analyzing.rawValue
                    || phase == ContentPhase.archived.rawValue
            }

            guard !publishedAtoms.isEmpty else { return nil }

            // Count consecutive days with published content (looking backwards from today)
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            var streakDays = 0
            var checkDate = today

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"

            for _ in 0..<30 {
                let dateStr = dateFormatter.string(from: checkDate)
                let hasContent = publishedAtoms.contains { atom in
                    guard let meta = atom.metadataDict,
                          let publishedAt = meta["publishedAt"] as? String else {
                        return atom.updatedAt.hasPrefix(dateStr)
                    }
                    return publishedAt.hasPrefix(dateStr)
                }

                if hasContent {
                    streakDays += 1
                    checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
                } else {
                    break
                }
            }

            guard streakDays >= 3 else { return nil }

            markAlertSent(type: "creative_momentum")
            return "You're on a \(streakDays)-day content streak. Momentum is building."
        } catch {
            return nil
        }
    }

    // MARK: - Stale Content

    /// Find content in draft phase for 7+ days.
    func checkStaleContent() async -> String? {
        guard shouldSendAlert(type: "stale_content") else { return nil }

        do {
            let contentAtoms = try await atomRepo.fetchAll(type: .content)

            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            let sevenDaysAgoStr = ISO8601DateFormatter().string(from: sevenDaysAgo)

            // Find draft-phase content older than 7 days
            let staleDrafts = contentAtoms.filter { atom in
                guard let meta = atom.metadataDict else { return false }
                let phase = meta["phase"] as? String
                let isDraft = phase == ContentPhase.draft.rawValue
                    || phase == ContentPhase.ideation.rawValue
                let isOld = atom.updatedAt < sevenDaysAgoStr
                return isDraft && isOld
            }

            guard !staleDrafts.isEmpty else { return nil }

            // Show the oldest ones
            let staleCount = staleDrafts.count
            let oldestTitle = staleDrafts.last?.title ?? "Untitled"

            markAlertSent(type: "stale_content")

            if staleCount == 1 {
                return "\"\(oldestTitle)\" has been in Draft for 7+ days. Ready to push it forward?"
            } else {
                return "\(staleCount) pieces have been in Draft for 7+ days. The oldest is \"\(oldestTitle)\"."
            }
        } catch {
            return nil
        }
    }

    // MARK: - Swipe Insight

    /// Detect recent swipe patterns the user hasn't used in their own content.
    /// If 3+ swipes share a hook/framework the user hasn't recently used, alert.
    func checkSwipeInsight() async -> String? {
        guard shouldSendAlert(type: "swipe_insight") else { return nil }

        do {
            let researchAtoms = try await atomRepo.fetchAll(type: .research)

            // Get swipes from last 7 days
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            let sevenDaysAgoStr = ISO8601DateFormatter().string(from: sevenDaysAgo)

            let recentSwipes = researchAtoms.filter { atom in
                atom.isSwipeFileAtom && atom.createdAt >= sevenDaysAgoStr
            }

            guard recentSwipes.count >= 3 else { return nil }

            // Group swipes by hook type
            var swipeHookCounts: [String: Int] = [:]
            for swipe in recentSwipes {
                if let analysis = swipe.swipeAnalysis,
                   let hookType = analysis.hookType {
                    swipeHookCounts[hookType.rawValue, default: 0] += 1
                }
            }

            // Group swipes by framework type
            var swipeFrameworkCounts: [String: Int] = [:]
            for swipe in recentSwipes {
                if let analysis = swipe.swipeAnalysis,
                   let framework = analysis.frameworkType {
                    swipeFrameworkCounts[framework.rawValue, default: 0] += 1
                }
            }

            // Get user's recent content hook/framework usage
            let contentAtoms = try await atomRepo.fetchAll(type: .content)
            let recentContent = contentAtoms.filter { $0.createdAt >= sevenDaysAgoStr }

            var usedHooks: Set<String> = []
            var usedFrameworks: Set<String> = []
            for atom in recentContent {
                if let meta = atom.metadataDict {
                    if let hook = meta["hookType"] as? String {
                        usedHooks.insert(hook)
                    }
                    if let framework = meta["frameworkType"] as? String {
                        usedFrameworks.insert(framework)
                    }
                }
            }

            // Find patterns in swipes that user hasn't used
            // Check hooks first
            for (hookType, count) in swipeHookCounts where count >= 3 {
                if !usedHooks.contains(hookType) {
                    let displayName = hookTypeDisplayName(hookType)
                    markAlertSent(type: "swipe_insight")
                    return "You saved \(count) swipes this week using \(displayName), but you haven't used it in your recent content. Worth experimenting with?"
                }
            }

            // Check frameworks
            for (framework, count) in swipeFrameworkCounts where count >= 3 {
                if !usedFrameworks.contains(framework) {
                    let displayName = frameworkDisplayName(framework)
                    markAlertSent(type: "swipe_insight")
                    return "You saved \(count) swipes this week using \(displayName), but you haven't tried it recently. Could be a good fit."
                }
            }

            return nil
        } catch {
            return nil
        }
    }

    // MARK: - Cooldown Management

    /// Check whether enough time has passed since the last alert of this type.
    func shouldSendAlert(type: String) -> Bool {
        guard let lastTime = lastAlertTimes[type] else {
            return true
        }
        return Date().timeIntervalSince(lastTime) >= minimumAlertInterval
    }

    /// Record that an alert was sent, resetting its cooldown.
    private func markAlertSent(type: String) {
        lastAlertTimes[type] = Date()
    }

    // MARK: - Private Helpers

    /// Extract engagement rate from a contentPerformance atom.
    private func extractEngagementRate(from atom: Atom?) -> Double {
        guard let atom = atom,
              let structuredStr = atom.structured,
              let data = structuredStr.data(using: .utf8) else {
            return 0
        }

        // Try to decode ContentPerformanceMetadata from structured JSON
        if let perfMeta = try? JSONDecoder().decode(ContentPerformanceMetadata.self, from: data) {
            return perfMeta.engagementRate
        }

        // Fallback: check metadata dict
        if let meta = atom.metadataDict,
           let rate = meta["engagementRate"] as? Double {
            return rate
        }

        // Fallback: compute from raw numbers in metadata
        if let meta = atom.metadataDict,
           let impressions = meta["impressions"] as? Int,
           let engagement = meta["engagement"] as? Int,
           impressions > 0 {
            return Double(engagement) / Double(impressions)
        }

        return 0
    }

    /// Convert a raw hook type string to its display name.
    private func hookTypeDisplayName(_ rawValue: String) -> String {
        if let hookType = SwipeHookType(rawValue: rawValue) {
            return hookType.displayName
        }
        // Fallback: capitalize and space the raw value
        return rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .capitalized
    }

    /// Convert a raw framework type string to its display name.
    private func frameworkDisplayName(_ rawValue: String) -> String {
        if let framework = SwipeFrameworkType(rawValue: rawValue) {
            return framework.displayName
        }
        return rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .capitalized
    }
}
