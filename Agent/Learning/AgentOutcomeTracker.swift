// CosmoOS/Agent/Learning/AgentOutcomeTracker.swift
// Tracks user accept/reject decisions to build taste profile

import Foundation

@MainActor
class AgentOutcomeTracker {
    static let shared = AgentOutcomeTracker()

    private let atomRepo = AtomRepository.shared

    private init() {}

    // MARK: - Track Event

    /// Save a learning event as an .agentLearning atom.
    func trackEvent(_ event: AgentLearningEvent) async {
        await saveEvent(event)
    }

    // MARK: - Shorthand Tracking Methods

    /// Track which hook was selected from a set of offered options.
    func trackHookSelection(offered: [String], selected: String, topic: String? = nil) async {
        var context: [String: String] = [:]
        if let topic = topic {
            context["topic"] = topic
        }
        context["allOffered"] = offered.joined(separator: ",")

        let event = AgentLearningEvent(
            category: .hookSelection,
            offered: offered.joined(separator: ", "),
            selected: selected,
            context: context
        )
        await saveEvent(event)
    }

    /// Track which framework was selected from a set of offered options.
    func trackFrameworkSelection(offered: [String], selected: String) async {
        let context: [String: String] = [
            "allOffered": offered.joined(separator: ",")
        ]

        let event = AgentLearningEvent(
            category: .frameworkSelection,
            offered: offered.joined(separator: ", "),
            selected: selected,
            context: context
        )
        await saveEvent(event)
    }

    /// Track feedback given during draft editing.
    func trackDraftFeedback(feedback: String, operation: String) async {
        let context: [String: String] = [
            "operation": operation
        ]

        let event = AgentLearningEvent(
            category: .draftFeedback,
            offered: operation,
            selected: feedback,
            context: context
        )
        await saveEvent(event)
    }

    /// Track whether a suggestion was accepted or rejected.
    func trackSuggestionAcceptance(suggestion: String, userFeedback: String = "", accepted: Bool, category: String) async {
        let context: [String: String] = [
            "category": category,
            "accepted": accepted ? "true" : "false",
            "userFeedback": userFeedback
        ]

        let event = AgentLearningEvent(
            category: .suggestionAcceptance,
            offered: suggestion,
            selected: accepted ? suggestion : nil,
            context: context
        )
        await saveEvent(event)
    }

    // MARK: - Query Events

    /// Load recent learning events, optionally filtered by category.
    func getRecentEvents(category: LearningCategory? = nil, limit: Int = 50) async -> [AgentLearningEvent] {
        let events = await loadEvents(limit: limit)

        if let category = category {
            return events.filter { $0.category == category }
        }
        return events
    }

    /// Calculate acceptance rate for a specific category.
    /// Returns a value between 0.0 (all rejected) and 1.0 (all accepted).
    func getAcceptanceRate(category: LearningCategory) async -> Double {
        let events = await getRecentEvents(category: category, limit: 100)
        guard !events.isEmpty else { return 0.5 } // Neutral when no data

        let acceptedCount = events.filter { $0.selected != nil }.count
        return Double(acceptedCount) / Double(events.count)
    }

    // MARK: - Private Helpers

    /// Persist a learning event as an .agentLearning atom.
    private func saveEvent(_ event: AgentLearningEvent) async {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let structuredData = try encoder.encode(event)
            let structuredStr = String(data: structuredData, encoding: .utf8)

            let metadataDict: [String: Any] = [
                "category": event.category.rawValue,
                "timestamp": ISO8601DateFormatter().string(from: event.timestamp),
                "hasSelection": event.selected != nil
            ]
            let metadataData = try JSONSerialization.data(withJSONObject: metadataDict)
            let metadataStr = String(data: metadataData, encoding: .utf8)

            // Build human-readable lesson description instead of raw offered text
            let lessonBody = buildLessonDescription(event)

            let atom = Atom.new(
                type: .agentLearning,
                title: "Learning: \(event.category.rawValue)",
                body: lessonBody,
                structured: structuredStr,
                metadata: metadataStr
            )
            _ = try await atomRepo.create(atom)
        } catch {
            // Silently fail -- learning tracking should never block the user
            print("[AgentOutcomeTracker] Failed to save event: \(error.localizedDescription)")
        }
    }

    /// Synthesize a human-readable lesson string from a learning event.
    private func buildLessonDescription(_ event: AgentLearningEvent) -> String {
        switch event.category {
        case .hookSelection:
            if let selected = event.selected {
                let others = event.offered
                    .components(separatedBy: ", ")
                    .filter { $0 != selected }
                if others.isEmpty {
                    return "Chose \"\(selected)\" hook"
                }
                return "Prefers \"\(selected)\" hook over \(others.joined(separator: ", "))"
            }
            return "Hook options offered: \(event.offered)"

        case .frameworkSelection:
            if let selected = event.selected {
                return "Prefers \"\(selected)\" framework"
            }
            return "Framework options offered: \(event.offered)"

        case .draftFeedback:
            let operation = event.context["operation"] ?? "editing"
            if let feedback = event.selected, !feedback.isEmpty {
                let preview = String(feedback.prefix(120))
                return "Feedback on \(operation): \"\(preview)\""
            }
            return "Gave feedback during \(operation)"

        case .suggestionAcceptance:
            let category = event.context["category"] ?? "general"
            let accepted = event.context["accepted"] == "true"
            let feedback = event.context["userFeedback"] ?? ""

            if accepted {
                return "Accepted \(category) suggestion"
            } else if !feedback.isEmpty {
                let preview = String(feedback.prefix(120))
                return "Rejected \(category) suggestion — \"\(preview)\""
            }
            return "Rejected \(category) suggestion"

        case .workflowApproval:
            if event.selected != nil {
                return "Approved workflow plan"
            }
            return "Rejected workflow plan"

        case .contentPerformance:
            return "Content performance tracked"
        }
    }

    /// Load learning events from .agentLearning atoms, sorted by most recent.
    private func loadEvents(limit: Int) async -> [AgentLearningEvent] {
        do {
            let atoms = try await atomRepo.fetchAll(type: .agentLearning)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            var events: [AgentLearningEvent] = []

            // Atoms come sorted by updatedAt desc from the repository
            for atom in atoms.prefix(limit) {
                guard let structuredStr = atom.structured,
                      let data = structuredStr.data(using: .utf8) else {
                    continue
                }

                if let event = try? decoder.decode(AgentLearningEvent.self, from: data) {
                    events.append(event)
                }
            }

            return events
        } catch {
            return []
        }
    }
}
