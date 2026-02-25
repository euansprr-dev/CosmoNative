// CosmoOS/Agent/Intelligence/SwipePatternMiner.swift
// Deep pattern analysis across the entire swipe file library

import Foundation

// MARK: - SwipePatternMiner

/// Analyzes the user's complete swipe file library to extract patterns, trends,
/// and actionable study recommendations. All data sourced from GRDB via AtomRepository.
@MainActor
class SwipePatternMiner {

    // MARK: - Singleton

    static let shared = SwipePatternMiner()

    // MARK: - Init

    private init() {}

    // MARK: - 1. Hook Distribution

    /// Counts swipes by hook type and returns both the raw distribution
    /// and a human-readable analysis string.
    func getHookDistribution() async -> (distribution: [String: Int], analysis: String) {
        let swipesWithAnalysis = await loadAllSwipesWithAnalysis()

        guard !swipesWithAnalysis.isEmpty else {
            return ([:], "Your swipe library is empty. Save some swipe files to start tracking hook patterns.")
        }

        // Count by hook type
        var distribution: [String: Int] = [:]
        var unclassifiedCount = 0

        for (_, analysis) in swipesWithAnalysis {
            if let hookType = analysis?.hookType {
                distribution[hookType.displayName, default: 0] += 1
            } else {
                unclassifiedCount += 1
            }
        }

        guard !distribution.isEmpty else {
            return ([:], "You have \(swipesWithAnalysis.count) swipes but none have been analyzed yet. Open them in Swipe Study mode to generate analysis.")
        }

        // Sort descending
        let sorted = distribution.sorted { $0.value > $1.value }
        let total = distribution.values.reduce(0, +)

        // Build analysis text
        var lines: [String] = []
        lines.append("HOOK TYPE DISTRIBUTION (\(total) analyzed swipes):")
        lines.append("")

        for (index, entry) in sorted.enumerated() {
            let percentage = Double(entry.value) / Double(total) * 100
            let bar = String(repeating: "#", count: Int(percentage / 5))  // Visual bar
            lines.append("  \(index + 1). \(entry.key): \(entry.value) (\(String(format: "%.0f", percentage))%) \(bar)")
        }

        if unclassifiedCount > 0 {
            lines.append("  Unclassified: \(unclassifiedCount)")
        }

        lines.append("")

        // Top-level insight
        if let top = sorted.first {
            let topPct = Double(top.value) / Double(total) * 100
            if topPct > 40 {
                lines.append("Your library is heavily weighted toward \(top.key) hooks (\(String(format: "%.0f", topPct))%). Consider diversifying to avoid creative tunnel vision.")
            } else if topPct < 20 && sorted.count >= 5 {
                lines.append("Your library is well-diversified across hook types. No single type dominates.")
            } else {
                lines.append("Your top hook type is \(top.key) with \(top.value) swipes. You have a healthy spread across \(sorted.count) different types.")
            }
        }

        // Identify gaps: hook types with zero swipes
        let allHookTypes = SwipeHookType.allCases.map { $0.displayName }
        let missingHooks = allHookTypes.filter { distribution[$0] == nil }
        if !missingHooks.isEmpty && missingHooks.count <= 5 {
            lines.append("Missing from your library: \(missingHooks.joined(separator: ", ")).")
        }

        return (distribution, lines.joined(separator: "\n"))
    }

    // MARK: - 2. Framework Effectiveness

    /// Cross-references framework types in the swipe library with published content
    /// performance to determine which frameworks drive the best results.
    func getFrameworkEffectiveness() async -> String {
        let swipesWithAnalysis = await loadAllSwipesWithAnalysis()
        let published = await fetchPublishedContent()
        let performanceAtoms = await fetchPerformanceAtoms()

        guard !swipesWithAnalysis.isEmpty else {
            return "Your swipe library is empty. Save swipe files to analyze framework effectiveness."
        }

        // Count frameworks in swipe library
        var swipeFrameworkCounts: [String: Int] = [:]
        for (_, analysis) in swipesWithAnalysis {
            if let fw = analysis?.frameworkType {
                swipeFrameworkCounts[fw.displayName, default: 0] += 1
            }
        }

        // Build performance map for published content by framework
        var frameworkEngagement: [String: [Double]] = [:]
        let contentEngagementMap = buildContentEngagementMap(performanceAtoms)

        for atom in published {
            guard let meta = atom.metadataValue(as: ContentAtomMetadata.self),
                  let fw = meta.inheritedFramework, !fw.isEmpty else { continue }

            let displayName = SwipeFrameworkType(rawValue: fw)?.displayName ?? fw

            if let rates = contentEngagementMap[atom.uuid], !rates.isEmpty {
                frameworkEngagement[displayName, default: []].append(contentsOf: rates)
            }
        }

        var lines: [String] = []
        lines.append("FRAMEWORK EFFECTIVENESS ANALYSIS:")
        lines.append("")

        // Report on frameworks with performance data
        if !frameworkEngagement.isEmpty {
            let averages = frameworkEngagement.mapValues { rates -> Double in
                rates.reduce(0, +) / Double(rates.count)
            }.sorted { $0.value > $1.value }

            let globalAvg = averages.map(\.value).reduce(0, +) / Double(averages.count)

            lines.append("Frameworks with published performance data:")
            for (fw, avgRate) in averages {
                let multiplier = globalAvg > 0 ? avgRate / globalAvg : 1.0
                let count = frameworkEngagement[fw]?.count ?? 0
                let indicator = multiplier >= 1.2 ? "+++" : multiplier >= 0.9 ? "+" : "---"
                lines.append("  \(fw): \(String(format: "%.1f", multiplier))x avg engagement (\(count) posts) \(indicator)")
            }
            lines.append("")
        } else {
            lines.append("No published content with framework data yet. Publish content with inherited frameworks to see effectiveness data.")
            lines.append("")
        }

        // Report on swipe library framework distribution
        let sortedSwipeFrameworks = swipeFrameworkCounts.sorted { $0.value > $1.value }
        let totalFrameworkSwipes = swipeFrameworkCounts.values.reduce(0, +)

        lines.append("Swipe library framework distribution (\(totalFrameworkSwipes) classified):")
        for (fw, count) in sortedSwipeFrameworks {
            let pct = Double(count) / Double(max(totalFrameworkSwipes, 1)) * 100
            lines.append("  \(fw): \(count) swipes (\(String(format: "%.0f", pct))%)")
        }

        // Identify frameworks studied but never used
        let usedFrameworks = Set(frameworkEngagement.keys)
        let studiedOnly = sortedSwipeFrameworks.filter { !usedFrameworks.contains($0.key) && $0.value >= 3 }
        if !studiedOnly.isEmpty {
            lines.append("")
            let names = studiedOnly.map { "\($0.key) (\($0.value) swipes)" }.joined(separator: ", ")
            lines.append("Studied but never published with: \(names). Consider testing these in your next content piece.")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - 3. Emerging Patterns

    /// Analyzes recently saved swipes to detect emerging interests and pattern shifts.
    func findEmergingPatterns(recentDays: Int = 7) async -> String {
        let recentSwipesData = await recentSwipes(days: recentDays)
        let allSwipesData = await loadAllSwipesWithAnalysis()

        guard !recentSwipesData.isEmpty else {
            return "No swipes saved in the last \(recentDays) days. Save new swipe files to detect emerging patterns."
        }

        guard allSwipesData.count > recentSwipesData.count else {
            return "All your swipes are from the last \(recentDays) days. Save more over time to detect emerging patterns."
        }

        var lines: [String] = []
        lines.append("EMERGING PATTERNS (last \(recentDays) days, \(recentSwipesData.count) new swipes):")
        lines.append("")

        // Compare recent hook distribution vs overall
        let recentHooks = countHookTypes(recentSwipesData)
        let overallHooks = countHookTypes(allSwipesData)

        let overallTotal = Double(max(overallHooks.values.reduce(0, +), 1))
        let recentTotal = Double(max(recentHooks.values.reduce(0, +), 1))

        var emergingHooks: [(hook: String, recentPct: Double, overallPct: Double)] = []

        for (hook, recentCount) in recentHooks {
            let recentPct = Double(recentCount) / recentTotal * 100
            let overallPct = Double(overallHooks[hook] ?? 0) / overallTotal * 100
            let delta = recentPct - overallPct

            if delta > 10 {
                emergingHooks.append((hook: hook, recentPct: recentPct, overallPct: overallPct))
            }
        }

        if !emergingHooks.isEmpty {
            let hookSummaries = emergingHooks
                .sorted { $0.recentPct > $1.recentPct }
                .map { "\($0.hook) (\(String(format: "%.0f", $0.recentPct))% recent vs \(String(format: "%.0f", $0.overallPct))% overall)" }
            lines.append("Emerging hook interest: " + hookSummaries.joined(separator: ", ") + ".")
        } else {
            lines.append("Hook type distribution is consistent with your overall library. No significant shifts detected.")
        }

        // Compare recent framework distribution vs overall
        let recentFrameworks = countFrameworkTypes(recentSwipesData)
        let overallFrameworks = countFrameworkTypes(allSwipesData)

        let overallFwTotal = Double(max(overallFrameworks.values.reduce(0, +), 1))
        let recentFwTotal = Double(max(recentFrameworks.values.reduce(0, +), 1))

        var emergingFrameworks: [(framework: String, recentPct: Double)] = []

        for (fw, recentCount) in recentFrameworks {
            let recentPct = Double(recentCount) / recentFwTotal * 100
            let overallPct = Double(overallFrameworks[fw] ?? 0) / overallFwTotal * 100
            if recentPct - overallPct > 10 {
                emergingFrameworks.append((framework: fw, recentPct: recentPct))
            }
        }

        if !emergingFrameworks.isEmpty {
            let fwNames = emergingFrameworks.map(\.framework).joined(separator: ", ")
            lines.append("Emerging framework interest: \(fwNames).")
        }

        // Check for new emotions appearing
        let recentEmotions = countEmotions(recentSwipesData)
        let overallEmotions = countEmotions(allSwipesData)

        let newEmotions = recentEmotions.keys.filter { overallEmotions[$0] == nil || overallEmotions[$0]! < 2 }
        if !newEmotions.isEmpty {
            lines.append("New emotional themes appearing: \(newEmotions.joined(separator: ", ")).")
        }

        // Average hook scores comparison
        let recentAvgScore = averageHookScore(recentSwipesData)
        let overallAvgScore = averageHookScore(allSwipesData)

        if recentAvgScore > 0 && overallAvgScore > 0 {
            let delta = recentAvgScore - overallAvgScore
            if abs(delta) > 0.5 {
                let direction = delta > 0 ? "higher" : "lower"
                lines.append(String(format: "Recent swipes have %.1f %@ average hook scores (%.1f vs %.1f overall).",
                                    abs(delta), direction, recentAvgScore, overallAvgScore))
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - 4. Persuasion Profile

    /// Analyzes persuasion technique distribution across the swipe library
    /// and identifies the user's persuasion preferences and blind spots.
    func getPersuasionProfile() async -> String {
        let swipesWithAnalysis = await loadAllSwipesWithAnalysis()

        guard !swipesWithAnalysis.isEmpty else {
            return "Your swipe library is empty. Save swipe files to build your persuasion profile."
        }

        // Count persuasion types across all swipes
        var persuasionCounts: [String: Int] = [:]
        var totalPersuasionInstances = 0

        for (_, analysis) in swipesWithAnalysis {
            guard let techniques = analysis?.persuasionTechniques else { continue }
            for technique in techniques {
                persuasionCounts[technique.type.displayName, default: 0] += 1
                totalPersuasionInstances += 1
            }
        }

        // Also aggregate from persuasionStack where available
        for (_, analysis) in swipesWithAnalysis {
            guard let stack = analysis?.persuasionStack else { continue }
            for (key, _) in stack {
                let displayName = PersuasionType(rawValue: key)?.displayName ?? key
                if persuasionCounts[displayName] == nil {
                    persuasionCounts[displayName, default: 0] += 1
                    totalPersuasionInstances += 1
                }
            }
        }

        guard totalPersuasionInstances > 0 else {
            return "No persuasion technique data found in your \(swipesWithAnalysis.count) swipes. Analyze your swipes in Swipe Study mode to detect persuasion patterns."
        }

        let sorted = persuasionCounts.sorted { $0.value > $1.value }

        var lines: [String] = []
        lines.append("PERSUASION PROFILE (\(totalPersuasionInstances) technique instances across \(swipesWithAnalysis.count) swipes):")
        lines.append("")

        // Distribution
        for (index, entry) in sorted.enumerated() {
            let pct = Double(entry.value) / Double(totalPersuasionInstances) * 100
            let bar = String(repeating: "#", count: Int(pct / 3))
            lines.append("  \(index + 1). \(entry.key): \(entry.value) (\(String(format: "%.0f", pct))%) \(bar)")
        }

        lines.append("")

        // Concentration analysis
        if let top = sorted.first {
            let topPct = Double(top.value) / Double(totalPersuasionInstances) * 100
            if topPct > 50 {
                lines.append("You lean heavily on \(top.key) (\(String(format: "%.0f", topPct))%). Consider studying scarcity, exclusivity, or other underrepresented techniques to broaden your persuasion toolkit.")
            } else if topPct > 30 {
                lines.append("Your strongest persuasion technique is \(top.key) (\(String(format: "%.0f", topPct))%). Solid preference, but keep exploring others.")
            } else {
                lines.append("Your persuasion profile is well-balanced. No single technique dominates.")
            }
        }

        // Identify gaps
        let allPersuasionTypes = PersuasionType.allCases.map { $0.displayName }
        let missing = allPersuasionTypes.filter { persuasionCounts[$0] == nil }
        if !missing.isEmpty {
            lines.append("Blind spots (not found in your library): \(missing.joined(separator: ", ")).")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - 5. Generate Swipe Study Plan

    /// Recommends 3-5 specific swipes to study this week based on gaps
    /// in the user's framework/hook knowledge.
    func generateSwipeStudyPlan() async -> String {
        let swipesWithAnalysis = await loadAllSwipesWithAnalysis()

        guard swipesWithAnalysis.count >= 5 else {
            return "You need at least 5 swipes in your library to generate a study plan. You currently have \(swipesWithAnalysis.count)."
        }

        // Find gap areas: underrepresented hooks and frameworks
        let hookCounts = countHookTypes(swipesWithAnalysis)
        let frameworkCounts = countFrameworkTypes(swipesWithAnalysis)

        // Sort by count ascending to find least-studied areas
        let weakHooks = hookCounts.sorted { $0.value < $1.value }
        let weakFrameworks = frameworkCounts.sorted { $0.value < $1.value }

        // Identify unstudied swipes (no studiedAt timestamp)
        let unstudied = swipesWithAnalysis.filter { (_, analysis) in
            analysis?.studiedAt == nil
        }

        // Prefer unstudied swipes in weak areas
        var studyPlan: [(atom: Atom, reason: String)] = []
        var usedUUIDs: Set<String> = []

        // Strategy 1: Find swipes in underrepresented hook types (up to 2)
        for (hookName, _) in weakHooks.prefix(3) {
            if studyPlan.count >= 2 { break }
            if let candidate = unstudied.first(where: { (atom, analysis) in
                analysis?.hookType?.displayName == hookName && !usedUUIDs.contains(atom.uuid)
            }) {
                studyPlan.append((
                    atom: candidate.atom,
                    reason: "Study \(hookName) hooks — you only have \(hookCounts[hookName] ?? 0) examples"
                ))
                usedUUIDs.insert(candidate.atom.uuid)
            }
        }

        // Strategy 2: Find swipes in underrepresented frameworks (up to 2)
        for (fwName, _) in weakFrameworks.prefix(3) {
            if studyPlan.count >= 4 { break }
            if let candidate = unstudied.first(where: { (atom, analysis) in
                analysis?.frameworkType?.displayName == fwName && !usedUUIDs.contains(atom.uuid)
            }) {
                studyPlan.append((
                    atom: candidate.atom,
                    reason: "Study \(fwName) framework — underrepresented in your library"
                ))
                usedUUIDs.insert(candidate.atom.uuid)
            }
        }

        // Strategy 3: Fill remaining with high-score unstudied swipes
        let highScoreUnstudied = unstudied
            .filter { !usedUUIDs.contains($0.atom.uuid) }
            .sorted { ($0.analysis?.hookScore ?? 0) > ($1.analysis?.hookScore ?? 0) }

        for candidate in highScoreUnstudied {
            if studyPlan.count >= 5 { break }
            let score = candidate.analysis?.hookScore ?? 0
            studyPlan.append((
                atom: candidate.atom,
                reason: "High hook score (\(String(format: "%.1f", score))/10) — learn from the best"
            ))
            usedUUIDs.insert(candidate.atom.uuid)
        }

        guard !studyPlan.isEmpty else {
            return "All your swipes have been studied. Great work! Save new swipe files to continue learning."
        }

        // Format the plan
        var lines: [String] = []
        lines.append("SWIPE STUDY PLAN FOR THIS WEEK (\(studyPlan.count) swipes):")
        lines.append("")

        for (index, entry) in studyPlan.enumerated() {
            let title = entry.atom.title ?? (entry.atom.body ?? "Untitled swipe")
            let truncatedTitle = String(title.prefix(60))
            let hookLabel = entry.atom.swipeAnalysis?.hookType?.displayName ?? "Unknown"
            let fwLabel = entry.atom.swipeAnalysis?.frameworkType?.displayName ?? "Unknown"

            lines.append("  \(index + 1). \"\(truncatedTitle)\"")
            lines.append("     Hook: \(hookLabel) | Framework: \(fwLabel)")
            lines.append("     Why: \(entry.reason)")
            lines.append("")
        }

        lines.append("Open each swipe in Swipe Study focus mode for the full teardown experience.")

        return lines.joined(separator: "\n")
    }

    // MARK: - 6. Library Summary

    /// Quick aggregate stats about the swipe library.
    func getLibrarySummary() async -> String {
        let swipesWithAnalysis = await loadAllSwipesWithAnalysis()

        guard !swipesWithAnalysis.isEmpty else {
            return "Your swipe library is empty. Start saving content examples that inspire you."
        }

        let total = swipesWithAnalysis.count
        let analyzed = swipesWithAnalysis.filter { $0.analysis?.isFullyAnalyzed == true }.count
        let studied = swipesWithAnalysis.filter { $0.analysis?.studiedAt != nil }.count

        // Top 3 hook types
        let hookCounts = countHookTypes(swipesWithAnalysis)
        let topHooks = hookCounts.sorted { $0.value > $1.value }.prefix(3)

        // Top 3 frameworks
        let frameworkCounts = countFrameworkTypes(swipesWithAnalysis)
        let topFrameworks = frameworkCounts.sorted { $0.value > $1.value }.prefix(3)

        // Average hook score
        let avgScore = averageHookScore(swipesWithAnalysis)

        // Date range
        let dateFormatter = ISO8601DateFormatter()
        let dates = swipesWithAnalysis.compactMap { (atom, _) -> Date? in
            dateFormatter.date(from: atom.createdAt)
        }.sorted()

        let displayDateFormatter = DateFormatter()
        displayDateFormatter.dateStyle = .medium

        // Creator distribution (from creatorUUID in analysis)
        var creatorCounts: [String: Int] = [:]
        for (_, analysis) in swipesWithAnalysis {
            if let creatorUUID = analysis?.creatorUUID, !creatorUUID.isEmpty {
                creatorCounts[creatorUUID, default: 0] += 1
            }
        }
        let topCreatorUUID = creatorCounts.max(by: { $0.value < $1.value })

        var lines: [String] = []
        lines.append("SWIPE LIBRARY SUMMARY:")
        lines.append("")
        lines.append("  Total swipes: \(total)")
        lines.append("  Fully analyzed: \(analyzed) (\(total > 0 ? String(format: "%.0f", Double(analyzed) / Double(total) * 100) : "0")%)")
        lines.append("  Studied: \(studied)")
        lines.append("  Average hook score: \(avgScore > 0 ? String(format: "%.1f", avgScore) : "N/A")/10")
        lines.append("")

        if !topHooks.isEmpty {
            let hookList = topHooks.map { "\($0.key) (\($0.value))" }.joined(separator: ", ")
            lines.append("  Top hooks: \(hookList)")
        }

        if !topFrameworks.isEmpty {
            let fwList = topFrameworks.map { "\($0.key) (\($0.value))" }.joined(separator: ", ")
            lines.append("  Top frameworks: \(fwList)")
        }

        if let oldest = dates.first, let newest = dates.last {
            lines.append("  Date range: \(displayDateFormatter.string(from: oldest)) — \(displayDateFormatter.string(from: newest))")
        }

        if let topCreator = topCreatorUUID {
            lines.append("  Most saved creator ID: \(topCreator.key) (\(topCreator.value) swipes)")
        }

        lines.append("")

        // Quick health check
        let hookDiversity = hookCounts.count
        let totalHookTypes = SwipeHookType.allCases.count
        let diversityPct = Double(hookDiversity) / Double(totalHookTypes) * 100

        if diversityPct >= 70 {
            lines.append("  Library health: Excellent diversity — you cover \(hookDiversity)/\(totalHookTypes) hook types.")
        } else if diversityPct >= 40 {
            lines.append("  Library health: Good — \(hookDiversity)/\(totalHookTypes) hook types covered. Keep expanding.")
        } else {
            lines.append("  Library health: Narrow focus — only \(hookDiversity)/\(totalHookTypes) hook types. Broaden your collection.")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private Data Loaders

    /// Fetch all research atoms that are swipe files and decode their SwipeAnalysis.
    private func loadAllSwipesWithAnalysis() async -> [(atom: Atom, analysis: SwipeAnalysis?)] {
        do {
            let allResearch = try await AtomRepository.shared.fetchAll(type: .research)
            return allResearch
                .filter { $0.isSwipeFileAtom }
                .map { atom in
                    (atom: atom, analysis: atom.swipeAnalysis)
                }
        } catch {
            return []
        }
    }

    /// Fetch swipes saved within the given number of days.
    private func recentSwipes(days: Int) async -> [(atom: Atom, analysis: SwipeAnalysis?)] {
        let allSwipes = await loadAllSwipesWithAnalysis()
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let dateFormatter = ISO8601DateFormatter()

        return allSwipes.filter { (atom, _) in
            if let date = dateFormatter.date(from: atom.createdAt) {
                return date >= cutoff
            }
            return false
        }
    }

    /// Fetch published content atoms for cross-referencing
    private func fetchPublishedContent() async -> [Atom] {
        do {
            let allContent = try await AtomRepository.shared.fetchAll(type: .content)
            return allContent.filter { atom in
                guard let meta = atom.metadataValue(as: ContentAtomMetadata.self) else { return false }
                return meta.phase == .published || meta.phase == .analyzing || meta.phase == .archived
            }
        } catch {
            return []
        }
    }

    /// Fetch content performance atoms
    private func fetchPerformanceAtoms() async -> [Atom] {
        do {
            return try await AtomRepository.shared.fetchAll(type: .contentPerformance)
        } catch {
            return []
        }
    }

    // MARK: - Private Counting Helpers

    /// Count hook types from an array of swipe tuples
    private func countHookTypes(_ swipes: [(atom: Atom, analysis: SwipeAnalysis?)]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for (_, analysis) in swipes {
            if let hookType = analysis?.hookType {
                counts[hookType.displayName, default: 0] += 1
            }
        }
        return counts
    }

    /// Count framework types from an array of swipe tuples
    private func countFrameworkTypes(_ swipes: [(atom: Atom, analysis: SwipeAnalysis?)]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for (_, analysis) in swipes {
            if let fw = analysis?.frameworkType {
                counts[fw.displayName, default: 0] += 1
            }
        }
        return counts
    }

    /// Count dominant emotions from an array of swipe tuples
    private func countEmotions(_ swipes: [(atom: Atom, analysis: SwipeAnalysis?)]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for (_, analysis) in swipes {
            if let emotion = analysis?.dominantEmotion {
                counts[emotion.displayName, default: 0] += 1
            }
        }
        return counts
    }

    /// Calculate average hook score across swipes
    private func averageHookScore(_ swipes: [(atom: Atom, analysis: SwipeAnalysis?)]) -> Double {
        let scores = swipes.compactMap { $0.analysis?.hookScore }
        guard !scores.isEmpty else { return 0 }
        return scores.reduce(0, +) / Double(scores.count)
    }

    /// Build a map from content atom UUID -> [engagement rates] from performance atoms
    private func buildContentEngagementMap(_ performanceAtoms: [Atom]) -> [String: [Double]] {
        var result: [String: [Double]] = [:]
        for perfAtom in performanceAtoms {
            if let meta = perfAtom.metadataValue(as: ContentPerformanceMetadata.self) {
                let parentUUID = perfAtom.metadataDict?["contentAtomUUID"] as? String ?? ""
                if !parentUUID.isEmpty {
                    result[parentUUID, default: []].append(meta.engagementRate)
                }
            }
        }
        return result
    }
}
