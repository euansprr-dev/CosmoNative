// CosmoOS/AI/Craft/CraftStatsBuilder.swift
// Computes the small evidence table the craft engine hands the model: format
// medians, the hook-mechanism leaderboard by real views, and the slide-count
// range of the best performers. All in Swift, all from SwipeAnalysis engagement
// fields — the model gets numbers it could never invent, for free.
// June 2026

import Foundation

struct CraftHookTypeStat: Equatable, Sendable {
    var hookType: String
    var count: Int
    var medianViews: Int
}

struct CraftFormatStats: Equatable, Sendable {
    var format: CraftFormat
    var sampleCount: Int
    var medianViews: Int?
    var topQuartileViews: Int?
    var medianEngagementRate: Double?
    var hookTypeLeaderboard: [CraftHookTypeStat]
    var typicalSlideRange: ClosedRange<Int>?

    var isEmpty: Bool { sampleCount == 0 }

    /// Rendered into the user turn — compact, deterministic ordering.
    var promptBlock: String {
        guard !isEmpty else {
            return "No engagement data recorded for \(format.displayName)s yet — judge on craft alone and say so."
        }
        var lines: [String] = ["Library stats for \(format.displayName)s (\(sampleCount) swipes with metrics):"]
        if let medianViews {
            lines.append("- Median views: \(CraftComparable.compact(medianViews))")
        }
        if let topQuartileViews {
            lines.append("- Top-quartile threshold: \(CraftComparable.compact(topQuartileViews)) views")
        }
        if let medianEngagementRate {
            lines.append(String(format: "- Median engagement rate: %.1f%%", medianEngagementRate))
        }
        if !hookTypeLeaderboard.isEmpty {
            let rows = hookTypeLeaderboard
                .map { "\($0.hookType) (\(CraftComparable.compact($0.medianViews)) median views, n=\($0.count))" }
                .joined(separator: ", ")
            lines.append("- Hook mechanisms by median views: \(rows)")
        }
        if let typicalSlideRange {
            lines.append("- Typical slide count of top performers: \(typicalSlideRange.lowerBound)–\(typicalSlideRange.upperBound)")
        }
        return lines.joined(separator: "\n")
    }
}

enum CraftStatsBuilder {
    /// Build stats from every same-format swipe with metrics — not just the
    /// selected comparables, so the medians describe the whole library.
    static func build(format: CraftFormat, swipeAtoms: [Atom]) -> CraftFormatStats {
        let matched = swipeAtoms.filter { atom in
            atom.isSwipeFileAtom && format.writingFormat.matchesSwipeAtom(atom)
        }

        let withViews = matched.compactMap { atom -> (atom: Atom, views: Int)? in
            guard let views = atom.swipeAnalysis?.viewsCount, views > 0 else { return nil }
            return (atom, views)
        }

        let viewCounts = withViews.map(\.views).sorted()
        let engagementRates = matched
            .compactMap { $0.swipeAnalysis?.engagementRate }
            .filter { $0 > 0 }
            .sorted()

        var hookGroups: [String: [Int]] = [:]
        for entry in withViews {
            guard let hookType = entry.atom.swipeAnalysis?.hookType?.rawValue else { continue }
            hookGroups[hookType, default: []].append(entry.views)
        }
        let leaderboard = hookGroups
            .compactMap { hookType, views -> CraftHookTypeStat? in
                guard views.count >= 2, let median = median(of: views.sorted()) else { return nil }
                return CraftHookTypeStat(hookType: hookType, count: views.count, medianViews: median)
            }
            .sorted {
                if $0.medianViews == $1.medianViews { return $0.hookType < $1.hookType }
                return $0.medianViews > $1.medianViews
            }
            .prefix(5)

        return CraftFormatStats(
            format: format,
            sampleCount: viewCounts.count,
            medianViews: median(of: viewCounts),
            topQuartileViews: percentile(of: viewCounts, fraction: 0.75),
            medianEngagementRate: median(of: engagementRates),
            hookTypeLeaderboard: Array(leaderboard),
            typicalSlideRange: slideRange(of: topPerformers(in: withViews))
        )
    }

    // MARK: - Internals

    /// Top half by views — "what do the winners look like structurally".
    private static func topPerformers(in entries: [(atom: Atom, views: Int)]) -> [Atom] {
        guard entries.count >= 4 else { return entries.map(\.atom) }
        let sorted = entries.sorted { $0.views > $1.views }
        return sorted.prefix(max(entries.count / 2, 2)).map(\.atom)
    }

    private static func slideRange(of atoms: [Atom]) -> ClosedRange<Int>? {
        let counts = atoms
            .compactMap { $0.swipeAnalysis?.transcriptSlides?.count }
            .filter { $0 > 0 }
            .sorted()
        guard counts.count >= 3,
              let low = percentile(of: counts, fraction: 0.25),
              let high = percentile(of: counts, fraction: 0.75),
              low <= high else {
            return nil
        }
        return low...high
    }

    static func median(of sorted: [Int]) -> Int? {
        guard !sorted.isEmpty else { return nil }
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    static func median(of sorted: [Double]) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    static func percentile(of sorted: [Int], fraction: Double) -> Int? {
        guard !sorted.isEmpty else { return nil }
        let position = fraction * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        if lower == upper { return sorted[lower] }
        let weight = position - Double(lower)
        return Int((Double(sorted[lower]) * (1 - weight) + Double(sorted[upper]) * weight).rounded())
    }
}
