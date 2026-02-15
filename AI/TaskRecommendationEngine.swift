//
//  TaskRecommendationEngine.swift
//  CosmoOS
//
//  Task recommendation engine that ranks tasks based on deadline urgency,
//  energy/focus match, priority, and context.
//

import Foundation
import SwiftUI
import Combine

// MARK: - TaskRecommendationEngine

/// Engine for recommending the best task to focus on based on multiple factors
/// Integrates with ReadinessCalculator for energy-aware suggestions
@MainActor
public final class TaskRecommendationEngine: ObservableObject {

    // MARK: - Singleton

    public static let shared = TaskRecommendationEngine()

    // MARK: - Scoring Weights

    private struct Weights {
        static let deadline: Double = 0.35       // Due date urgency (highest weight)
        static let energyMatch: Double = 0.25   // Matches current energy level
        static let priority: Double = 0.20      // User-set priority
        static let recency: Double = 0.10       // Recently created/touched
        static let projectFocus: Double = 0.10  // Active project alignment
    }

    // MARK: - Dependencies

    private let atomRepository: AtomRepository

    // MARK: - Initialization

    init(atomRepository: AtomRepository? = nil) {
        self.atomRepository = atomRepository ?? AtomRepository.shared
    }

    // MARK: - Main API

    /// Get task recommendations sorted by relevance
    /// - Parameters:
    ///   - currentEnergy: User's current energy level (0-100)
    ///   - currentFocus: User's current focus level (0-100)
    ///   - nextCommitmentAt: Time of next scheduled commitment (optional)
    ///   - limit: Maximum number of recommendations to return
    /// - Returns: Tuple of primary recommendation and alternatives
    public func getRecommendations(
        currentEnergy: Int,
        currentFocus: Int,
        nextCommitmentAt: Date? = nil,
        limit: Int = 5
    ) async throws -> (primary: TaskRecommendation?, alternatives: [TaskRecommendation]) {

        // Fetch incomplete tasks
        let tasks = try await fetchIncompleteTasks()

        guard !tasks.isEmpty else {
            return (nil, [])
        }

        // Score each task
        var scoredTasks: [(TaskViewModel, Double, RecommendationReason)] = []

        for task in tasks {
            let (score, reason) = calculateScore(
                task: task,
                currentEnergy: currentEnergy,
                currentFocus: currentFocus,
                nextCommitmentAt: nextCommitmentAt
            )
            scoredTasks.append((task, score, reason))
        }

        // Sort by score (descending)
        scoredTasks.sort { $0.1 > $1.1 }

        // Convert to recommendations
        let recommendations = scoredTasks.prefix(limit).map { task, score, reason in
            TaskRecommendation(
                task: TaskViewModel(
                    id: task.id,
                    uuid: task.uuid,
                    title: task.title,
                    body: task.body,
                    projectUuid: task.projectUuid,
                    projectName: task.projectName,
                    projectColor: task.projectColor,
                    dueDate: task.dueDate,
                    scheduledDate: task.scheduledDate,
                    scheduledTime: task.scheduledTime,
                    estimatedMinutes: task.estimatedMinutes,
                    priority: task.priority,
                    isCompleted: task.isCompleted,
                    completedAt: task.completedAt,
                    intent: task.intent,
                    linkedIdeaUUID: task.linkedIdeaUUID,
                    linkedContentUUID: task.linkedContentUUID,
                    linkedAtomUUID: task.linkedAtomUUID,
                    totalFocusMinutes: task.totalFocusMinutes,
                    sessionCount: task.sessionCount,
                    recurrenceParentUUID: task.recurrenceParentUUID,
                    isRecurring: task.isRecurring,
                    scheduledStart: task.scheduledStart,
                    scheduledEnd: task.scheduledEnd,
                    taskType: task.taskType,
                    energyLevel: task.energyLevel,
                    cognitiveLoad: task.cognitiveLoad,
                    recommendationScore: score,
                    recommendationReason: reason.displayMessage,
                    createdAt: task.createdAt,
                    updatedAt: task.updatedAt
                ),
                score: score,
                reason: reason
            )
        }

        guard let primary = recommendations.first else {
            return (nil, [])
        }

        return (primary, Array(recommendations.dropFirst()))
    }

    /// Get the single best task recommendation
    public func getTopRecommendation(
        currentEnergy: Int,
        currentFocus: Int
    ) async throws -> TaskRecommendation? {
        let (primary, _) = try await getRecommendations(
            currentEnergy: currentEnergy,
            currentFocus: currentFocus,
            limit: 1
        )
        return primary
    }

    // MARK: - Scoring

    /// Calculate score for a task based on multiple factors
    private func calculateScore(
        task: TaskViewModel,
        currentEnergy: Int,
        currentFocus: Int,
        nextCommitmentAt: Date?
    ) -> (Double, RecommendationReason) {

        var score = 0.0
        var primaryReason: RecommendationReason = .userPrioritized

        // 1. Deadline pressure (0-1, higher = more urgent)
        let deadlineScore = calculateDeadlineScore(dueDate: task.dueDate)
        score += deadlineScore * Weights.deadline

        if let hours = task.hoursUntilDue, hours <= 48 {
            primaryReason = .deadlinePressure(hoursUntilDue: hours)
        }

        // 2. Energy match (0-1, higher = better match)
        let energyScore = calculateEnergyMatch(
            taskType: task.taskType,
            cognitiveLoad: task.cognitiveLoad,
            currentEnergy: currentEnergy,
            currentFocus: currentFocus
        )
        score += energyScore * Weights.energyMatch

        if energyScore > 0.7 && primaryReason == .userPrioritized {
            primaryReason = .energyMatch(
                currentEnergy: currentEnergy,
                requiredEnergy: task.energyLevel ?? .medium
            )
        }

        // 3. Priority (0-1)
        let priorityScore = calculatePriorityScore(priority: task.priority)
        score += priorityScore * Weights.priority

        // 4. Recency (0-1, newer tasks get slight boost)
        let recencyScore = calculateRecencyScore(createdAt: task.createdAt)
        score += recencyScore * Weights.recency

        // 5. Time fit bonus (if next commitment exists)
        if let nextCommitment = nextCommitmentAt {
            let availableMinutes = Int(nextCommitment.timeIntervalSinceNow / 60)
            if task.estimatedMinutes <= availableMinutes && availableMinutes > 0 {
                score += 0.1  // Bonus for fitting in available time
                if primaryReason == .userPrioritized {
                    primaryReason = .timeAvailable(availableMinutes: availableMinutes)
                }
            }
        }

        // 6. Project focus bonus
        if task.projectUuid != nil {
            score += 0.05 * Weights.projectFocus
            if primaryReason == .userPrioritized, let projectName = task.projectName {
                primaryReason = .projectFocus(projectName: projectName)
            }
        }

        // 7. Intent-based boost (writeContent tasks get priority, especially when linked)
        if task.intent == .writeContent {
            score += 0.05
            // Additional boost when linked to a concrete idea or content (ready to act)
            if task.linkedIdeaUUID != nil || task.linkedContentUUID != nil {
                score += 0.03
            }
        }

        return (min(1.0, score), primaryReason)
    }

    /// Calculate deadline urgency score (0-1)
    private func calculateDeadlineScore(dueDate: Date?) -> Double {
        guard let dueDate = dueDate else {
            return 0.3  // No due date = moderate urgency
        }

        let hoursUntilDue = dueDate.timeIntervalSinceNow / 3600

        if hoursUntilDue < 0 { return 1.0 }       // Overdue
        if hoursUntilDue < 4 { return 0.95 }      // Due in 4 hours
        if hoursUntilDue < 8 { return 0.85 }      // Due in 8 hours
        if hoursUntilDue < 24 { return 0.75 }     // Due today
        if hoursUntilDue < 48 { return 0.6 }      // Due tomorrow
        if hoursUntilDue < 168 { return 0.4 }     // Due this week
        if hoursUntilDue < 336 { return 0.25 }    // Due in 2 weeks
        return 0.15                               // Due later
    }

    /// Calculate energy match score (0-1)
    private func calculateEnergyMatch(
        taskType: TaskCategoryType?,
        cognitiveLoad: CognitiveLoad?,
        currentEnergy: Int,
        currentFocus: Int
    ) -> Double {

        var energyMatchScore = 0.5  // Default neutral

        // Check task type energy requirements
        if let taskType = taskType {
            let idealRange = taskType.idealEnergyRange
            if idealRange.contains(currentEnergy) {
                let midpoint = (idealRange.lowerBound + idealRange.upperBound) / 2
                let distance = abs(currentEnergy - midpoint)
                energyMatchScore = 1.0 - (Double(distance) / 50.0)
            } else {
                // Outside ideal range - calculate penalty
                let lowerDist = idealRange.lowerBound - currentEnergy
                let upperDist = currentEnergy - idealRange.upperBound
                let distance = max(lowerDist, upperDist)
                energyMatchScore = max(0.1, 0.5 - (Double(distance) / 100.0))
            }
        }

        // Check cognitive load requirements
        if let cognitiveLoad = cognitiveLoad {
            let focusRange = cognitiveLoad.focusRequirement
            if focusRange.contains(currentFocus) {
                energyMatchScore = min(1.0, energyMatchScore + 0.2)
            } else if currentFocus < focusRange.lowerBound && cognitiveLoad == .deep {
                // Low focus but needs deep work - penalty
                energyMatchScore = max(0.1, energyMatchScore - 0.3)
            }
        }

        return energyMatchScore
    }

    /// Calculate priority score (0-1)
    private func calculatePriorityScore(priority: TaskPriority) -> Double {
        switch priority {
        case .critical: return 1.0
        case .high: return 0.75
        case .medium: return 0.5
        case .low: return 0.25
        }
    }

    /// Calculate recency score (0-1, newer = higher)
    private func calculateRecencyScore(createdAt: Date) -> Double {
        let daysSinceCreation = Date().timeIntervalSince(createdAt) / 86400

        if daysSinceCreation < 1 { return 0.8 }      // Created today
        if daysSinceCreation < 3 { return 0.6 }      // Created this week
        if daysSinceCreation < 7 { return 0.4 }      // Created recently
        if daysSinceCreation < 30 { return 0.3 }     // Created this month
        return 0.2                                    // Older task
    }

    // MARK: - Data Fetching

    /// Fetch incomplete tasks from repository
    private func fetchIncompleteTasks() async throws -> [TaskViewModel] {
        let atoms = try await atomRepository.fetchAll(type: .task)

        return atoms.compactMap { atom -> TaskViewModel? in
            // Filter out completed tasks
            let metadata = atom.metadataValue(as: TaskMetadata.self)
            if metadata?.isCompleted == true { return nil }

            return TaskViewModel.from(atom: atom)
        }
    }

    // MARK: - Context Messages

    /// Generate context message based on energy/focus levels
    public static func contextMessage(
        focus: Int,
        energy: Int
    ) -> String {
        // Energy-first messaging for the Today view
        if energy > 70 {
            return "High energy -- tackle your most demanding work"
        } else if energy >= 40 {
            return "Steady state -- good for routine work"
        } else {
            return "Low energy -- focus on lighter tasks"
        }
    }

    /// Generate context message when no health data available
    public static var defaultContextMessage: String {
        "Ready to focus? Here's your top priority."
    }
}

// Note: metadataValue(as:) extension is defined in Atom.swift
