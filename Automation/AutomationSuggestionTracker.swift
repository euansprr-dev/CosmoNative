// CosmoOS/Automation/AutomationSuggestionTracker.swift
// Observes repeated manual actions and suggests automations
// Tracks (atomType, targetClusterId) movement pairs — suggests after 3+ in a week

import Foundation
import Combine
import SwiftUI

@MainActor
class AutomationSuggestionTracker: ObservableObject {
    static let shared = AutomationSuggestionTracker()

    /// Active suggestion for a cluster (clusterId → suggestion)
    @Published private(set) var activeSuggestions: [String: SuggestionData] = [:]

    /// Movement history: key = "atomType:clusterId", value = timestamps
    private var movementHistory: [String: [Date]] = [:]
    private var cancellables = Set<AnyCancellable>()

    private static let threshold = 3           // Movements needed to trigger suggestion
    private static let windowDays = 7          // Days to look back
    private static let dismissedKey = "automation_dismissed_suggestions"

    private init() {}

    // MARK: - Tracking

    /// Record a block movement to a cluster (called by CanvasClusterEngine when membership changes)
    func recordMovement(atomType: String, targetClusterId: String) {
        let key = "\(atomType):\(targetClusterId)"
        let now = Date()

        // Append timestamp
        movementHistory[key, default: []].append(now)

        // Prune old entries
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.windowDays, to: now) ?? now
        movementHistory[key] = movementHistory[key]?.filter { $0 > cutoff } ?? []

        // Check threshold
        let count = movementHistory[key]?.count ?? 0
        if count >= Self.threshold && !isDismissed(key: key) && activeSuggestions[targetClusterId] == nil {
            activeSuggestions[targetClusterId] = SuggestionData(
                clusterId: targetClusterId,
                atomType: atomType,
                count: count,
                message: "You've moved \(count) \(atomType)s here recently. Auto-collect new \(atomType)s?"
            )
        }
    }

    /// Accept a suggestion — creates an automation rule
    func acceptSuggestion(for clusterId: String) async {
        guard let suggestion = activeSuggestions[clusterId] else { return }

        let rule = AutomationRule.create(
            name: "Auto-collect \(suggestion.atomType)s",
            scope: .global,
            triggerType: .atomTypeCreated,
            triggerConfig: ["atomType": suggestion.atomType],
            actions: [
                AutomationAction(
                    type: .moveToCluster,
                    config: ["clusterId": .string(clusterId)],
                    label: "Move to cluster"
                )
            ]
        )

        try? await AutomationDispatcher.shared.createRule(rule)

        // Clear suggestion
        activeSuggestions.removeValue(forKey: clusterId)
        let key = "\(suggestion.atomType):\(clusterId)"
        movementHistory.removeValue(forKey: key)
    }

    /// Dismiss a suggestion (won't be shown again for this cluster+type combo)
    func dismissSuggestion(for clusterId: String) {
        guard let suggestion = activeSuggestions[clusterId] else { return }
        let key = "\(suggestion.atomType):\(clusterId)"

        // Persist dismissal
        var dismissed = UserDefaults.standard.stringArray(forKey: Self.dismissedKey) ?? []
        dismissed.append(key)
        UserDefaults.standard.set(dismissed, forKey: Self.dismissedKey)

        activeSuggestions.removeValue(forKey: clusterId)
    }

    /// Check if a suggestion has been previously dismissed
    private func isDismissed(key: String) -> Bool {
        let dismissed = UserDefaults.standard.stringArray(forKey: Self.dismissedKey) ?? []
        return dismissed.contains(key)
    }

    /// Get active suggestion for a specific cluster (if any)
    func suggestion(for clusterId: String) -> SuggestionData? {
        activeSuggestions[clusterId]
    }
}

// MARK: - Suggestion Data

struct SuggestionData: Identifiable {
    let clusterId: String
    let atomType: String
    let count: Int
    let message: String

    var id: String { clusterId }
}

// MARK: - Suggestion Banner View

/// Compact banner shown at the top of a cluster when a suggestion is active
struct AutomationSuggestionBanner: View {

    let suggestion: SuggestionData
    let clusterColor: Color
    let onAccept: () -> Void
    let onDismiss: () -> Void

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(clusterColor)

            Text(suggestion.message)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.text)
                .lineLimit(2)

            Spacer(minLength: 0)

            Button("Yes") {
                onAccept()
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(DS.accent))
            .buttonStyle(.plain)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DS.textMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss suggestion")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(clusterColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(clusterColor.opacity(0.2), lineWidth: 0.5)
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -4)
        .onAppear {
            withAnimation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.8)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
    }
}
