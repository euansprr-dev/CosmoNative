// CosmoOS/Agent/Proactive/AgentBriefGenerator.swift
// Generates morning briefs and weekly reviews

import Foundation

@MainActor
class AgentBriefGenerator {
    static let shared = AgentBriefGenerator()

    private let atomRepo = AtomRepository.shared

    private init() {}

    // MARK: - Morning Brief

    func generateMorningBrief() async -> String {
        // 1. Query today's data
        let todayStr = todayPrefix()

        // Schedule blocks for today
        let scheduleBlocks = (try? await atomRepo.fetchAll(type: .scheduleBlock)) ?? []
        let todayBlocks = scheduleBlocks.filter {
            ($0.metadata ?? "").contains(todayStr) || $0.createdAt.hasPrefix(todayStr)
        }

        // Incomplete tasks
        let tasks = (try? await atomRepo.fetchAll(type: .task)) ?? []
        let incompleteTasks = tasks.filter {
            !($0.metadata ?? "").contains("\"status\":\"completed\"")
        }

        // Pipeline status
        let contentAtoms = (try? await atomRepo.fetchAll(type: .content)) ?? []

        // Recent ideas (last 3 days)
        let ideas = (try? await atomRepo.fetchAll(type: .idea)) ?? []
        let recentIdeas = Array(ideas.prefix(5))

        // 2. Build brief text
        var brief = "Good morning! Here's your creative brief:\n\n"

        // Schedule
        if todayBlocks.isEmpty {
            brief += "Schedule: Clear day -- perfect for deep work\n"
        } else {
            brief += "Schedule: \(todayBlocks.count) block\(todayBlocks.count == 1 ? "" : "s") planned\n"
            for block in todayBlocks.prefix(3) {
                brief += "  - \(block.title ?? "Untitled")\n"
            }
        }

        // Tasks
        brief += "\nTasks: \(incompleteTasks.count) open\n"
        for task in incompleteTasks.prefix(3) {
            brief += "  - \(task.title ?? "Untitled")\n"
        }

        // Pipeline
        brief += "\nContent Pipeline: \(contentAtoms.count) piece\(contentAtoms.count == 1 ? "" : "s") in progress\n"

        // Ideas
        if !recentIdeas.isEmpty {
            brief += "\nRecent Ideas: \(recentIdeas.count) spark\(recentIdeas.count == 1 ? "" : "s")\n"
            for idea in recentIdeas.prefix(3) {
                brief += "  - \(idea.title ?? "Untitled")\n"
            }
        }

        brief += "\nWhat would you like to focus on today?"

        return brief
    }

    // MARK: - Weekly Review

    func generateWeeklyReview() async -> String {
        let weekAgoStr = weekAgoPrefix()

        // Count completed tasks this week
        let allTasks = (try? await atomRepo.fetchAll(type: .task)) ?? []
        let completedThisWeek = allTasks.filter {
            ($0.metadata ?? "").contains("\"status\":\"completed\"") && $0.updatedAt >= weekAgoStr
        }

        // Content pieces
        let contentAtoms = (try? await atomRepo.fetchAll(type: .content)) ?? []

        // XP earned (dimension snapshots)
        let snapshots = (try? await atomRepo.fetchAll(type: .dimensionSnapshot)) ?? []
        let recentSnapshots = snapshots.filter { $0.createdAt >= weekAgoStr }

        // New ideas
        let ideas = (try? await atomRepo.fetchAll(type: .idea)) ?? []
        let newIdeas = ideas.filter { $0.createdAt >= weekAgoStr }

        var review = "Weekly Review\n\n"
        review += "Tasks completed: \(completedThisWeek.count)\n"
        review += "New ideas captured: \(newIdeas.count)\n"
        review += "Content pieces: \(contentAtoms.count) total\n"
        review += "Dimension snapshots: \(recentSnapshots.count)\n"
        review += "\nGreat week! Keep the momentum going."

        return review
    }

    // MARK: - Streak Alert

    func generateStreakAlert(questTitle: String, currentStreak: Int) -> String {
        "Streak Alert! Your \"\(questTitle)\" streak is at \(currentStreak) days. Don't forget to complete it today!"
    }

    // MARK: - Helpers

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
