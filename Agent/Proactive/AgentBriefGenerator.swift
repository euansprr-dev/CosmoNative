// CosmoOS/Agent/Proactive/AgentBriefGenerator.swift
// Strategic morning briefs and weekly reviews for Cosmo Agent v2

import Foundation

@MainActor
class AgentBriefGenerator {
    static let shared = AgentBriefGenerator()

    private let atomRepo = AtomRepository.shared

    private init() {}

    // MARK: - Strategic Morning Brief

    func generateMorningBrief() async -> String {
        let todayStr = todayPrefix()

        // 1. Schedule blocks for today
        let scheduleBlocks = (try? await atomRepo.fetchAll(type: .scheduleBlock)) ?? []
        let todayBlocks = scheduleBlocks.filter {
            ($0.metadata ?? "").contains(todayStr) || $0.createdAt.hasPrefix(todayStr)
        }

        // 2. Pipeline status
        let contentAtoms = (try? await atomRepo.fetchAll(type: .content)) ?? []
        let pipelineCounts = contentPhaseCounts(contentAtoms)
        let pipelineStr = pipelineCounts.map { "\($0.key): \($0.value)" }.joined(separator: ", ")

        // 3. Content streak
        let streak = await calculateContentStreak()

        // 4. Social data (if available)
        let followerNote = await getFollowerChangeNote()

        // 5. Today's recommended play
        let todayPlan = await generateTodayPlan(contentAtoms: contentAtoms, todayBlocks: todayBlocks)

        // 6. Strategic insight
        let insight = await generateInsight(contentAtoms: contentAtoms)

        // 7. Energy note (HealthKit if available)
        let energyNote = await getEnergyNote()

        return TelegramRichMessages.shared.formatMorningBrief(
            energyNote: energyNote,
            pipelineStatus: pipelineStr.isEmpty ? "Pipeline empty" : pipelineStr,
            streak: streak,
            followerChange: followerNote,
            todayPlan: todayPlan,
            insight: insight,
            questProgress: ""
        )
    }

    // MARK: - Today's Plan Generation

    private func generateTodayPlan(contentAtoms: [Atom], todayBlocks: [Atom]) async -> String {
        // Priority 1: Content in polish phase (closest to completion)
        let polishContent = contentAtoms.filter { atom in
            let meta = atom.metadataValue(as: ContentAtomMetadata.self)
            return meta?.phase == .polish
        }
        if let first = polishContent.first {
            let wordCount = first.metadataValue(as: ContentAtomMetadata.self)?.wordCount ?? 0
            let est = max(15, wordCount / 20) // Rough estimate: 20 words/min editing
            return "Finish polishing \"\(first.title ?? "Untitled")\" (est. \(est) min) then activate your next idea"
        }

        // Priority 2: Content in draft phase
        let draftContent = contentAtoms.filter { atom in
            let meta = atom.metadataValue(as: ContentAtomMetadata.self)
            return meta?.phase == .draft
        }
        if let first = draftContent.first {
            return "Continue drafting \"\(first.title ?? "Untitled")\" -- you're in the flow"
        }

        // Priority 3: Ready ideas to activate
        let ideas = (try? await atomRepo.fetchAll(type: .idea)) ?? []
        let readyIdeas = ideas.filter { atom in
            let status = atom.metadataDict?["ideaStatus"] as? String
            return status == "developing" || status == "validated"
        }
        if let first = readyIdeas.first {
            return "Activate idea \"\(first.title ?? "Untitled")\" -- it's ready for the pipeline"
        }

        // Priority 4: Check today's scheduled blocks
        if !todayBlocks.isEmpty {
            let blockNames = todayBlocks.prefix(2).map { $0.title ?? "Block" }.joined(separator: ", ")
            return "Focus on your scheduled blocks: \(blockNames)"
        }

        return "Open day! Capture a new idea or study some swipe files"
    }

    // MARK: - Strategic Insight

    private func generateInsight(contentAtoms: [Atom]) async -> String? {
        // Analyze recent content hook types
        let published = contentAtoms.filter { atom in
            let meta = atom.metadataValue(as: ContentAtomMetadata.self)
            return meta?.phase == .published
        }

        guard published.count >= 3 else { return nil }

        // Count hook types from recent published content
        var hookCounts: [String: Int] = [:]
        for atom in published.suffix(10) {
            if let hookType = atom.metadataDict?["hookType"] as? String {
                hookCounts[hookType, default: 0] += 1
            }
        }

        // Find dominant hook type
        if let (dominantHook, count) = hookCounts.max(by: { $0.value < $1.value }), count >= 3 {
            // Check swipe library for user's best-performing hook type
            let swipes = (try? await atomRepo.fetchAll(type: .research)) ?? []
            let swipeFiles = swipes.filter { $0.isSwipeFileAtom }

            var swipeHookCounts: [String: Int] = [:]
            for swipe in swipeFiles {
                if let structured = swipe.structured,
                   let data = structured.data(using: .utf8),
                   let analysis = try? JSONDecoder().decode(SwipeAnalysis.self, from: data) {
                    if let hookType = analysis.hookType {
                        swipeHookCounts[hookType.rawValue, default: 0] += 1
                    }
                }
            }

            // Find a hook type that's strong in swipes but underused in content
            let underusedHooks = swipeHookCounts.filter { hookCounts[$0.key] == nil && $0.value >= 3 }
            if let (underused, swipeCount) = underusedHooks.max(by: { $0.value < $1.value }) {
                let formatted = underused.replacingOccurrences(of: "_", with: " ")
                return "Your last \(count) posts used \(dominantHook.replacingOccurrences(of: "_", with: " ")) hooks. You have \(swipeCount) \(formatted) swipes you haven't tried yet -- consider experimenting."
            }
        }

        return nil
    }

    // MARK: - Content Streak

    private func calculateContentStreak() async -> Int {
        let contentAtoms = (try? await atomRepo.fetchAll(type: .content)) ?? []
        let published = contentAtoms.filter { atom in
            let meta = atom.metadataValue(as: ContentAtomMetadata.self)
            return meta?.phase == .published
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let publishDates = published.compactMap { atom -> Date? in
            ISO8601DateFormatter().date(from: atom.updatedAt)
        }.map { calendar.startOfDay(for: $0) }

        let uniqueDays = Set(publishDates).sorted(by: >)

        var streak = 0
        var checkDate = today

        for day in uniqueDays {
            if calendar.isDate(day, inSameDayAs: checkDate) {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else if day < checkDate {
                break
            }
        }

        return streak
    }

    // MARK: - Social Data

    private func getFollowerChangeNote() async -> String? {
        let syncResults = SocialSyncService.shared.lastSyncResults
        guard !syncResults.isEmpty else { return nil }

        var notes: [String] = []
        for (platform, result) in syncResults {
            if result.followerCount > 0 {
                notes.append("\(platform.displayName): \(TelegramRichMessages.shared.formatCount(result.followerCount)) followers")
            }
        }

        return notes.isEmpty ? nil : notes.joined(separator: " | ")
    }

    // MARK: - Energy Note

    private func getEnergyNote() async -> String? {
        // Try to get HRV from HealthKit if available
        do {
            if let hrv = try await HealthKitQueryService.shared.fetchLatestHRV() {
                let avgHRV = 55.0 // Baseline assumption
                let status: String
                if hrv > avgHRV * 1.1 {
                    status = "above average -- great day for deep creative work"
                } else if hrv < avgHRV * 0.85 {
                    status = "below average -- consider lighter tasks today"
                } else {
                    status = "normal range"
                }
                return "HRV: \(Int(hrv))ms (\(status))"
            }
        } catch {
            // HealthKit not available, skip energy note
        }
        return nil
    }

    // MARK: - Weekly Review (Legacy Support)

    func generateWeeklyReview() async -> String {
        let weekAgoStr = weekAgoPrefix()

        let allTasks = (try? await atomRepo.fetchAll(type: .task)) ?? []
        let completedThisWeek = allTasks.filter {
            ($0.metadata ?? "").contains("\"status\":\"completed\"") && $0.updatedAt >= weekAgoStr
        }

        let contentAtoms = (try? await atomRepo.fetchAll(type: .content)) ?? []
        let ideas = (try? await atomRepo.fetchAll(type: .idea)) ?? []
        let newIdeas = ideas.filter { $0.createdAt >= weekAgoStr }

        let swipes = (try? await atomRepo.fetchAll(type: .research)) ?? []
        let newSwipes = swipes.filter { $0.isSwipeFileAtom && $0.createdAt >= weekAgoStr }

        // Find best performing piece
        let published = contentAtoms.filter { atom in
            let meta = atom.metadataValue(as: ContentAtomMetadata.self)
            return meta?.phase == .published && atom.updatedAt >= weekAgoStr
        }

        var bestPiece: (title: String, hookType: String, framework: String, metric: String)?
        var weakestPiece: (title: String, hookType: String, reason: String)?

        if published.count >= 2 {
            // Simple: use first as best, last as weakest (rough heuristic)
            if let best = published.first {
                let hookType = best.metadataDict?["hookType"] as? String ?? "Unknown"
                let framework = best.metadataDict?["framework"] as? String ?? "Unknown"
                bestPiece = (
                    title: best.title ?? "Untitled",
                    hookType: hookType.replacingOccurrences(of: "_", with: " "),
                    framework: framework.replacingOccurrences(of: "_", with: " "),
                    metric: "Top performer this week"
                )
            }
            if let worst = published.last, published.count > 1 {
                let hookType = worst.metadataDict?["hookType"] as? String ?? "Unknown"
                weakestPiece = (
                    title: worst.title ?? "Untitled",
                    hookType: hookType.replacingOccurrences(of: "_", with: " "),
                    reason: "Lowest engagement this week"
                )
            }
        }

        // Pattern detection
        var pattern: String? = nil
        var hookCounts: [String: Int] = [:]
        for atom in published {
            if let hookType = atom.metadataDict?["hookType"] as? String {
                hookCounts[hookType, default: 0] += 1
            }
        }
        if let (topHook, count) = hookCounts.max(by: { $0.value < $1.value }), count >= 2 {
            pattern = "Your \(topHook.replacingOccurrences(of: "_", with: " ")) content outperformed this week. Double down next week."
        }

        // Recommendations
        var recommendations: [String] = []
        if published.count < 3 {
            recommendations.append("Increase publishing cadence -- aim for 3+ pieces next week")
        }
        if newSwipes.count < 5 {
            recommendations.append("Study more swipe files -- aim for 5+ per week to keep your strategy fresh")
        }
        if newIdeas.count == 0 {
            recommendations.append("Capture more ideas -- even quick voice notes count")
        }

        return TelegramRichMessages.shared.formatWeeklyReview(
            publishedCount: published.count,
            bestPiece: bestPiece,
            weakestPiece: weakestPiece,
            swipesStudied: newSwipes.count,
            ideasCaptured: newIdeas.count,
            pattern: pattern,
            recommendations: recommendations
        )
    }

    // MARK: - Helpers

    private func contentPhaseCounts(_ atoms: [Atom]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for atom in atoms {
            let meta = atom.metadataValue(as: ContentAtomMetadata.self)
            let phase = meta?.phase.displayName ?? "Ideation"
            counts[phase, default: 0] += 1
        }
        return counts
    }

    private func todayPrefix() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func weekAgoPrefix() -> String {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: weekAgo)
    }
}
