// CosmoOS/AI/WeeklyBriefEngine.swift
// Weekly Intelligence Brief — Sunday-generated summary combining all 6
// Sanctuary dimensions over the past 7 days.

import Foundation
import Combine
import SwiftUI

// MARK: - Data Structures

struct CrossInsight: Identifiable, Codable, Equatable {
    var id: String { "\(source)-\(target)" }
    let source: String
    let target: String
    let description: String
    let impact: String
}

struct StreakReport: Codable, Equatable {
    let activeStreaks: Int
    let longestStreak: Int
    let endangeredStreaks: Int
}

struct WeeklyBrief: Identifiable, Codable, Equatable {
    let id: String
    let weekOf: Date
    let overallIndex: Double
    let dimensionScores: [String: Double]
    let topWin: String
    let biggestChallenge: String
    let crossDimensionInsights: [CrossInsight]
    let recommendations: [String]
    let streakReport: StreakReport
    let dimensionTrends: [String: String]
    let generatedAt: Date
}

private struct DaySnapshot {
    let date: Date
    let scores: [String: Double]
}

// MARK: - WeeklyBriefEngine

@MainActor
class WeeklyBriefEngine: ObservableObject {
    @Published var currentBrief: WeeklyBrief?
    @Published var isGenerating = false
    @Published var lastError: String?
    private let atomRepository: AtomRepository
    private let dimensionWeights: [String: Double] = [
        "Cognitive": 0.20, "Creative": 0.20, "Physiological": 0.15,
        "Behavioral": 0.20, "Knowledge": 0.15, "Reflection": 0.10
    ]
    init(atomRepository: AtomRepository? = nil) {
        self.atomRepository = atomRepository ?? AtomRepository.shared
    }

    // MARK: - Generate Brief

    func generateBrief() async -> WeeklyBrief {
        isGenerating = true
        defer { isGenerating = false }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let weekAgo = cal.date(byAdding: .day, value: -7, to: today) else {
            return emptyBrief(weekOf: today)
        }

        let snapshots = await loadSnapshots(from: weekAgo, to: today)
        let (avgs, trends) = computeTrendsAndAverages(snapshots)
        let overall = computeWeightedIndex(avgs)
        let (win, challenge) = identifyWinAndChallenge(avgs, trends)
        let insights = generateCrossInsights(avgs, trends)
        let recs = buildRecommendations(avgs, trends)
        let streaks = await buildStreakReport()

        let trendStrings = trends.mapValues { $0 == .rising ? "improving" : $0 == .falling ? "declining" : "stable" }

        let brief = WeeklyBrief(
            id: UUID().uuidString, weekOf: weekAgo, overallIndex: overall,
            dimensionScores: avgs, topWin: win, biggestChallenge: challenge,
            crossDimensionInsights: insights, recommendations: recs,
            streakReport: streaks, dimensionTrends: trendStrings, generatedAt: Date()
        )
        currentBrief = brief
        await storeBrief(brief)
        return brief
    }

    /// Load the most recent stored weekly brief atom.
    func loadLastBrief() async {
        do {
            let atoms = try await atomRepository.fetchAll(type: .weeklySummary)
            guard let latest = atoms.first,
                  let str = latest.structured, let data = str.data(using: .utf8),
                  let brief = try? JSONDecoder().decode(WeeklyBrief.self, from: data) else { return }
            currentBrief = brief
        } catch {
            lastError = "Failed to load brief: \(error.localizedDescription)"
        }
    }

    // MARK: - Snapshot Loading

    private func loadSnapshots(from start: Date, to end: Date) async -> [DaySnapshot] {
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFallback = ISO8601DateFormatter(); isoFallback.formatOptions = [.withInternetDateTime]
        let dayFmt = DateFormatter(); dayFmt.dateFormat = "yyyy-MM-dd"
        do {
            let atoms = try await atomRepository.fetchAll(type: .dimensionSnapshot)
            var buckets: [String: [[String: Double]]] = [:]

            for atom in atoms {
                guard let date = iso.date(from: atom.createdAt) ?? isoFallback.date(from: atom.createdAt),
                      date >= start && date <= end,
                      let metaStr = atom.metadata, let metaData = metaStr.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any] else { continue }

                var scores: [String: Double] = [:]
                for dim in LevelDimension.allCases {
                    let key = dim.rawValue
                    if let s = dict[key] as? Double { scores[dim.displayName] = s }
                    else if let s = dict[key + "Score"] as? Double { scores[dim.displayName] = s }
                    else if let s = dict["score"] as? Double, dict["dimension"] as? String == key { scores[dim.displayName] = s }
                }
                buckets[dayFmt.string(from: date), default: []].append(scores)
            }

            return buckets.compactMap { key, entries -> DaySnapshot? in
                guard let date = dayFmt.date(from: key) else { return nil }
                var agg: [String: [Double]] = [:]
                for entry in entries { for (d, s) in entry { agg[d, default: []].append(s) } }
                let averaged = agg.mapValues { $0.reduce(0, +) / Double(max($0.count, 1)) }
                return DaySnapshot(date: date, scores: averaged)
            }.sorted { $0.date < $1.date }
        } catch {
            lastError = "Failed to load snapshots: \(error.localizedDescription)"
            return []
        }
    }

    // MARK: - Trends & Averages

    private func computeTrendsAndAverages(_ snapshots: [DaySnapshot]) -> ([String: Double], [String: DimensionTrend]) {
        var avgs: [String: Double] = [:]
        var trends: [String: DimensionTrend] = [:]

        for dim in LevelDimension.allCases {
            let name = dim.displayName
            let daily = snapshots.compactMap { $0.scores[name] }
            guard !daily.isEmpty else { avgs[name] = 0; trends[name] = .stable; continue }

            avgs[name] = daily.reduce(0, +) / Double(daily.count)

            if daily.count >= 2 {
                let mid = daily.count / 2
                let firstAvg = daily.prefix(mid).reduce(0, +) / Double(max(mid, 1))
                let secondAvg = daily.suffix(from: mid).reduce(0, +) / Double(max(daily.count - mid, 1))
                let delta = secondAvg - firstAvg
                trends[name] = delta > 3.0 ? .rising : delta < -3.0 ? .falling : .stable
            } else {
                trends[name] = .stable
            }
        }
        return (avgs, trends)
    }

    // MARK: - Weighted Harmonic Mean (matches DimensionIndexEngine)

    private func computeWeightedIndex(_ avgs: [String: Double]) -> Double {
        var wSum = 0.0, rSum = 0.0
        for (name, score) in avgs where score > 0 {
            let w = dimensionWeights[name] ?? 0.15
            wSum += w; rSum += w / max(score, 0.01)
        }
        return rSum > 0 ? min(100, wSum / rSum) : 0
    }

    // MARK: - Win & Challenge

    private func identifyWinAndChallenge(_ avgs: [String: Double], _ trends: [String: DimensionTrend]) -> (String, String) {
        let rising = trends.filter { $0.value == .rising }
        let win: String
        if let best = rising.max(by: { (avgs[$0.key] ?? 0) < (avgs[$1.key] ?? 0) }) {
            win = "\(best.key) trending up at \(Int(avgs[best.key] ?? 0))/100 — great momentum"
        } else if let top = avgs.max(by: { $0.value < $1.value }), top.value > 0 {
            win = "\(top.key) led the way at \(Int(top.value))/100"
        } else { win = "Getting started — first week of tracking" }

        let falling = trends.filter { $0.value == .falling }
        let challenge: String
        if let worst = falling.min(by: { (avgs[$0.key] ?? 100) < (avgs[$1.key] ?? 100) }) {
            challenge = "\(worst.key) declined to \(Int(avgs[worst.key] ?? 0))/100 — needs attention"
        } else if let low = avgs.filter({ $0.value > 0 }).min(by: { $0.value < $1.value }) {
            challenge = "\(low.key) is the weakest area at \(Int(low.value))/100"
        } else { challenge = "No data yet — complete daily activities to build your baseline" }

        return (win, challenge)
    }

    // MARK: - Cross-Dimension Insights

    private func generateCrossInsights(_ avgs: [String: Double], _ trends: [String: DimensionTrend]) -> [CrossInsight] {
        let pairs: [(String, String, String)] = [
            ("Physiological", "Cognitive", "Sleep/recovery quality influenced focus capacity"),
            ("Behavioral", "Creative", "Routine consistency supported creative output"),
            ("Reflection", "Behavioral", "Journaling awareness improved habit adherence"),
            ("Cognitive", "Knowledge", "Deep work sessions expanded the knowledge graph"),
            ("Knowledge", "Creative", "Research depth enriched content quality"),
            ("Physiological", "Behavioral", "Physical readiness supported routine execution"),
        ]
        var out: [CrossInsight] = []
        for (src, tgt, template) in pairs {
            guard (avgs[src] ?? 0) > 0 && (avgs[tgt] ?? 0) > 0 else { continue }
            let st = trends[src] ?? .stable, tt = trends[tgt] ?? .stable

            if st == .rising && tt == .rising {
                out.append(CrossInsight(source: src, target: tgt,
                    description: "\(src) and \(tgt) both improved this week", impact: template))
            } else if st == .falling && tt == .falling {
                out.append(CrossInsight(source: src, target: tgt,
                    description: "\(src) and \(tgt) both declined — investigate shared cause",
                    impact: "Addressing \(src.lowercased()) may lift \(tgt.lowercased()) too"))
            } else if st == .rising && tt == .falling {
                out.append(CrossInsight(source: src, target: tgt,
                    description: "\(src) improved but \(tgt) dropped — unexpected divergence",
                    impact: "Check if \(tgt.lowercased()) decline has a separate root cause"))
            }
            if out.count >= 4 { break }
        }
        return out
    }

    // MARK: - Recommendations

    private func buildRecommendations(_ avgs: [String: Double], _ trends: [String: DimensionTrend]) -> [String] {
        let actions: [String: (strong: String, light: String)] = [
            "Cognitive": ("Schedule a 30-minute deep work block each morning",
                          "Reduce context switches by batching communication windows"),
            "Creative": ("Draft one piece of content and advance it through the pipeline",
                         "Review your swipe file for hook inspiration"),
            "Physiological": ("Prioritize 7+ hours of sleep with consistent bed/wake times",
                              "Add a short workout or walk to your daily routine"),
            "Behavioral": ("Set up recurring tasks for your most important daily habits",
                           "Use time-blocking to protect your key routines"),
            "Knowledge": ("Save and annotate one new research source this week",
                          "Create connections between recent research and existing ideas"),
            "Reflection": ("Write a 5-minute journal entry each evening",
                           "Review last week's journal for patterns and recurring themes"),
        ]
        var recs: [String] = []
        for (name, score) in avgs.sorted(by: { $0.value < $1.value }) {
            guard recs.count < 5, let a = actions[name] else { continue }
            let t = trends[name] ?? .stable
            if score < 30 || t == .falling { recs.append(a.strong) }
            else if score < 60 { recs.append(a.light) }
        }
        if recs.isEmpty { recs.append("Maintain your current momentum — all dimensions are performing well") }
        return recs
    }

    // MARK: - Streak Report

    private func buildStreakReport() async -> StreakReport {
        do {
            let atoms = try await atomRepository.fetchAll(type: .dimensionSnapshot)
            let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoFB = ISO8601DateFormatter(); isoFB.formatOptions = [.withInternetDateTime]
            let dayFmt = DateFormatter(); dayFmt.dateFormat = "yyyy-MM-dd"
            var questDates: [String: Set<String>] = [:]
            for atom in atoms {
                guard let ms = atom.metadata, let d = ms.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      dict["type"] as? String == "questCompletion",
                      let qid = dict["questId"] as? String else { continue }
                let ds: String
                if let ca = dict["completedAt"] as? String, let dt = iso.date(from: ca) ?? isoFB.date(from: ca) {
                    ds = dayFmt.string(from: dt)
                } else if let dt = iso.date(from: atom.createdAt) ?? isoFB.date(from: atom.createdAt) {
                    ds = dayFmt.string(from: dt)
                } else { continue }
                questDates[qid, default: []].insert(ds)
            }

            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let todayStr = dayFmt.string(from: today)
            var active = 0, longest = 0, endangered = 0

            for (_, dates) in questDates {
                var streak = 0, check = today
                while true {
                    let cs = dayFmt.string(from: check)
                    if dates.contains(cs) {
                        streak += 1
                        guard let prev = cal.date(byAdding: .day, value: -1, to: check) else { break }
                        check = prev
                    } else if cal.isDateInToday(check) {
                        guard let prev = cal.date(byAdding: .day, value: -1, to: check) else { break }
                        check = prev
                    } else { break }
                }
                if streak > 0 {
                    active += 1; longest = max(longest, streak)
                    if !dates.contains(todayStr) { endangered += 1 }
                }
            }
            return StreakReport(activeStreaks: active, longestStreak: longest, endangeredStreaks: endangered)
        } catch {
            return StreakReport(activeStreaks: 0, longestStreak: 0, endangeredStreaks: 0)
        }
    }

    // MARK: - Persistence

    private func storeBrief(_ brief: WeeklyBrief) async {
        guard let encoded = try? JSONEncoder().encode(brief),
              let structured = String(data: encoded, encoding: .utf8) else { return }
        let meta: [String: Any] = [
            "briefType": "weeklyBrief",
            "weekOf": ISO8601DateFormatter().string(from: brief.weekOf),
            "overallIndex": brief.overallIndex
        ]
        guard let md = try? JSONSerialization.data(withJSONObject: meta),
              let ms = String(data: md, encoding: .utf8) else { return }
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d"
        do {
            try await atomRepository.create(
                type: .weeklySummary, title: "Weekly Brief — \(fmt.string(from: brief.weekOf))",
                body: "Overall Index: \(Int(brief.overallIndex))/100 | Win: \(brief.topWin)",
                structured: structured, metadata: ms
            )
        } catch { lastError = "Failed to store brief: \(error.localizedDescription)" }
    }

    private static let emptyStreak = StreakReport(activeStreaks: 0, longestStreak: 0, endangeredStreaks: 0)

    private func emptyBrief(weekOf: Date) -> WeeklyBrief {
        WeeklyBrief(id: UUID().uuidString, weekOf: weekOf, overallIndex: 0, dimensionScores: [:],
            topWin: "Getting started — first week of tracking",
            biggestChallenge: "No data yet — complete daily activities to build your baseline",
            crossDimensionInsights: [], recommendations: ["Complete one daily quest to begin building data"],
            streakReport: Self.emptyStreak, dimensionTrends: [:], generatedAt: Date())
    }
}
