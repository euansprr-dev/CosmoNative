// CosmoOS/Services/ContextDetectionEngine.swift
// Intelligent context detection for auto-assigning uncommitted items to projects
// December 2025 - Extended with ThinkSpace context awareness

import Foundation
import SwiftUI

@MainActor
class ContextDetectionEngine: ObservableObject {
    static let shared = ContextDetectionEngine()

    // Active context state
    @Published var activeProjectId: Int64?
    @Published var activeProjectUuid: String?
    @Published var focusedInboxBlockId: UUID?
    @Published var lastFocusedEntityType: EntityType?
    @Published var recentCaptures: [(projectId: Int64, timestamp: Date)] = []

    // ThinkSpace context
    @Published var activeThinkspaceId: String?
    @Published var activeThinkspaceName: String?
    @Published var isInThinkspaceView: Bool = false

    private let atomRepo = AtomRepository.shared

    // MARK: - Context-Aware Item Creation

    /// Creates an uncommitted item with smart project inference
    func createWithContext(
        _ text: String,
        captureMethod: CaptureMethod
    ) async -> Atom? {
        // Run detection
        let detection = await detectContext(for: text)

        // Create item with inferred metadata using AtomRepository
        do {
            let atom = try await atomRepo.createUncommittedItem(
                rawText: text,
                captureMethod: captureMethod.rawValue,
                assignmentStatus: detection.assignmentStatus.rawValue,
                projectUuid: detection.projectUuid,
                inferredType: detection.inferredType,
                inferredProject: detection.inferredProjectName,
                inferredProjectConfidence: detection.confidence
            )

            // Track this capture for temporal patterns
            if let projectId = detection.projectId {
                trackCapture(projectId: projectId)
            }

            return atom
        } catch {
            print("❌ Failed to create uncommitted item: \(error)")
            return nil
        }
    }

    // MARK: - Context Detection

    struct ContextDetection {
        var projectId: Int64?
        var projectUuid: String?
        var inferredProjectName: String?
        var assignmentStatus: AssignmentStatus
        var confidence: Double
        var inferredType: String?
    }

    private func detectContext(for text: String) async -> ContextDetection {
        var totalConfidence: Double = 0.0
        var detectedProjectId: Int64?
        var detectedProjectName: String?
        var detectedProjectUuid: String?

        // Signal 1: Active Context (40% weight)
        let activeContextResult = detectActiveContext()
        if let projectId = activeContextResult.projectId {
            detectedProjectId = projectId
            detectedProjectName = activeContextResult.projectName
            detectedProjectUuid = activeContextResult.projectUuid
            totalConfidence += activeContextResult.confidence * 0.4
        }

        // Signal 2: Language Cues (35% weight)
        let languageResult = await detectLanguageCues(in: text)
        if languageResult.confidence > 0 {
            // Language cues can override active context if highly confident
            if languageResult.confidence > 0.8 {
                detectedProjectId = languageResult.projectId
                detectedProjectName = languageResult.projectName
                detectedProjectUuid = languageResult.projectUuid
                totalConfidence = languageResult.confidence * 0.35
            } else {
                totalConfidence += languageResult.confidence * 0.35
            }
        }

        // Signal 3: Temporal Context (25% weight)
        let temporalResult = detectTemporalPatterns()
        if temporalResult.projectId == detectedProjectId {
            // Reinforce if temporal matches active/language
            totalConfidence += temporalResult.confidence * 0.25
        }

        // Determine assignment status based on total confidence
        let assignmentStatus: AssignmentStatus
        if totalConfidence >= 0.75 {
            assignmentStatus = .assigned
        } else if totalConfidence >= 0.45 {
            assignmentStatus = .suggested
        } else {
            assignmentStatus = .unassigned
            detectedProjectId = nil
            detectedProjectName = nil
            detectedProjectUuid = nil
        }

        // Infer entity type from action words
        let inferredType = inferEntityType(from: text)

        return ContextDetection(
            projectId: detectedProjectId,
            projectUuid: detectedProjectUuid,
            inferredProjectName: detectedProjectName,
            assignmentStatus: assignmentStatus,
            confidence: totalConfidence,
            inferredType: inferredType
        )
    }

    // MARK: - Signal 1: Active Context Detection

    private func detectActiveContext() -> (projectId: Int64?, projectName: String?, projectUuid: String?, confidence: Double) {
        // Check if an inbox block is focused
        if focusedInboxBlockId != nil {
            // Would need to fetch the block's project info
            // For now, return moderate confidence
            return (activeProjectId, nil, nil, 0.7)
        }

        // Check if a project was recently active in Focus Mode
        if let projectId = activeProjectId {
            return (projectId, nil, nil, 0.6)
        }

        return (nil, nil, nil, 0.0)
    }

    // MARK: - Signal 2: Language Cues Detection

    private func detectLanguageCues(in text: String) async -> (projectId: Int64?, projectName: String?, projectUuid: String?, confidence: Double) {
        guard let projectAtoms = try? await atomRepo.projects() else {
            return (nil, nil, nil, 0.0)
        }

        var bestMatch: (atom: Atom, confidence: Double)?

        for projectAtom in projectAtoms {
            var confidence: Double = 0.0
            let title = projectAtom.title ?? ""

            // Check for exact project name match (case-insensitive)
            if text.localizedCaseInsensitiveContains(title) {
                confidence = 0.95
            }

            // Check for partial project name match
            let projectWords = title.components(separatedBy: .whitespaces)
            for word in projectWords where word.count > 3 {
                if text.localizedCaseInsensitiveContains(word) {
                    confidence = max(confidence, 0.75)
                }
            }

            // Check for common patterns in description (body field)
            if let description = projectAtom.body {
                let descWords = description.components(separatedBy: .whitespaces)
                for word in descWords where word.count > 4 {
                    if text.localizedCaseInsensitiveContains(word) {
                        confidence = max(confidence, 0.5)
                    }
                }
            }

            // Update best match
            if confidence > (bestMatch?.confidence ?? 0) {
                bestMatch = (projectAtom, confidence)
            }
        }

        if let match = bestMatch {
            return (match.atom.id, match.atom.title, match.atom.uuid, match.confidence)
        }

        return (nil, nil, nil, 0.0)
    }

    // MARK: - Signal 3: Temporal Patterns

    private func detectTemporalPatterns() -> (projectId: Int64?, confidence: Double) {
        // Look at recent captures (last 5)
        let recentWindow = recentCaptures.prefix(5)

        guard !recentWindow.isEmpty else {
            return (nil, 0.0)
        }

        // Count frequency of each project
        var projectFrequency: [Int64: Int] = [:]
        for capture in recentWindow {
            projectFrequency[capture.projectId, default: 0] += 1
        }

        // Find most frequent project
        if let mostFrequent = projectFrequency.max(by: { $0.value < $1.value }) {
            let confidence = Double(mostFrequent.value) / Double(recentWindow.count)
            return (mostFrequent.key, confidence * 0.7)  // Max 0.7 for temporal
        }

        return (nil, 0.0)
    }

    // MARK: - Entity Type Inference

    private func inferEntityType(from text: String) -> String? {
        let lowercased = text.lowercased()

        // Task patterns
        let taskKeywords = ["todo", "task", "remind", "remember", "call", "email", "send", "buy", "get", "fix", "update"]
        for keyword in taskKeywords {
            if lowercased.contains(keyword) {
                return "task"
            }
        }

        // Content patterns
        let contentKeywords = ["write", "draft", "post", "article", "blog", "document", "note"]
        for keyword in contentKeywords {
            if lowercased.contains(keyword) {
                return "content"
            }
        }

        // Research patterns
        let researchKeywords = ["research", "study", "learn", "read", "investigate"]
        for keyword in researchKeywords {
            if lowercased.contains(keyword) {
                return "research"
            }
        }

        // Default to idea if no strong signal
        return "idea"
    }

    // MARK: - Context Tracking

    private func trackCapture(projectId: Int64) {
        recentCaptures.insert((projectId, Date()), at: 0)

        // Keep only last 10 captures
        if recentCaptures.count > 10 {
            recentCaptures = Array(recentCaptures.prefix(10))
        }
    }

    /// Update active project (e.g., when entering Focus Mode)
    func setActiveProject(_ projectId: Int64?) {
        activeProjectId = projectId
    }

    /// Update active project by UUID (for Atom architecture)
    func setActiveProject(_ projectUuid: String?) {
        // For now, just clear the legacy projectId when using UUID
        // Full migration would store projectUuid separately
        activeProjectId = nil
    }

    /// Update focused inbox block (e.g., when clicking an inbox block)
    func setFocusedInboxBlock(_ blockId: UUID?) {
        focusedInboxBlockId = blockId
    }

    /// Clear all context
    func clearContext() {
        activeProjectId = nil
        activeProjectUuid = nil
        focusedInboxBlockId = nil
        lastFocusedEntityType = nil
        activeThinkspaceId = nil
        activeThinkspaceName = nil
        isInThinkspaceView = false
    }

    // MARK: - ThinkSpace Context

    /// Update active ThinkSpace context (called when user navigates to a ThinkSpace)
    func setActiveThinkspace(id: String?, name: String?, projectUuid: String?) {
        activeThinkspaceId = id
        activeThinkspaceName = name
        isInThinkspaceView = id != nil

        // Also update project context if ThinkSpace belongs to a project
        if let projectUuid = projectUuid {
            activeProjectUuid = projectUuid
        }
    }

    /// Clear ThinkSpace context (called when leaving ThinkSpace view)
    func clearThinkspaceContext() {
        activeThinkspaceId = nil
        activeThinkspaceName = nil
        isInThinkspaceView = false
    }

    /// Get ThinkSpace for voice routing based on project name
    func findThinkspaceForProject(named projectName: String) async -> (thinkspaceId: String, projectUuid: String)? {
        guard let projects = try? await atomRepo.projects() else {
            return nil
        }

        // Fuzzy match project name
        let lowercasedName = projectName.lowercased()
        for project in projects {
            let title = project.title?.lowercased() ?? ""

            // Exact match or partial match
            if title == lowercasedName || title.contains(lowercasedName) || lowercasedName.contains(title) {
                // Get root ThinkSpace for this project
                if let metadata = project.metadataValue(as: ProjectMetadata.self),
                   let rootThinkspaceUuid = metadata.rootThinkspaceUuid {
                    return (rootThinkspaceUuid, project.uuid)
                }
            }
        }

        return nil
    }

    /// Detect if voice capture should route to ThinkSpace
    func shouldRouteToThinkspace(text: String) -> Bool {
        let lowercased = text.lowercased()
        let thinkspaceKeywords = ["thinkspace", "canvas", "add to", "spatial", "block"]

        for keyword in thinkspaceKeywords {
            if lowercased.contains(keyword) {
                return true
            }
        }

        // Also route if we're currently in ThinkSpace view
        return isInThinkspaceView
    }

    /// Get destination for voice capture based on context
    func getVoiceDestination(for text: String) async -> VoiceDestination {
        // Check for explicit ThinkSpace mentions
        if shouldRouteToThinkspace(text: text) {
            // Try to extract project name from "add to [project] thinkspace"
            if let projectMatch = extractProjectName(from: text),
               let result = await findThinkspaceForProject(named: projectMatch) {
                return .thinkspace(id: result.thinkspaceId, projectUuid: result.projectUuid)
            }

            // Default to active ThinkSpace if in view
            if let activeId = activeThinkspaceId {
                return .thinkspace(id: activeId, projectUuid: activeProjectUuid)
            }
        }

        // Check for project inbox routing
        if let projectUuid = activeProjectUuid {
            return .projectInbox(projectUuid: projectUuid)
        }

        // Default to global inbox
        return .globalInbox
    }

    /// Extract project name from text patterns like "add to Michael thinkspace"
    private func extractProjectName(from text: String) -> String? {
        let patterns = [
            #"add\s+(?:this\s+)?to\s+(.+?)\s*(?:think\s*space|canvas)"#,
            #"in\s+(.+?)\s*(?:think\s*space|canvas)"#,
            #"for\s+(.+?)\s*(?:think\s*space|canvas)"#
        ]

        let lowercased = text.lowercased()

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: lowercased, options: [], range: NSRange(lowercased.startIndex..., in: lowercased)),
               let range = Range(match.range(at: 1), in: lowercased) {
                return String(lowercased[range]).trimmingCharacters(in: .whitespaces)
            }
        }

        return nil
    }
}

// MARK: - Voice Destination

/// Destination for voice-captured content
enum VoiceDestination {
    case globalInbox
    case projectInbox(projectUuid: String)
    case thinkspace(id: String, projectUuid: String?)

    var description: String {
        switch self {
        case .globalInbox:
            return "Global Inbox"
        case .projectInbox(let uuid):
            return "Project Inbox (\(uuid.prefix(8))...)"
        case .thinkspace(let id, _):
            return "ThinkSpace (\(id.prefix(8))...)"
        }
    }
}
