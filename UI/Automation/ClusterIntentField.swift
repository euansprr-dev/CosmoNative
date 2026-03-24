// CosmoOS/UI/Automation/ClusterIntentField.swift
// Compact NL intent field for the cluster inspector panel
// Typing a description auto-generates automation rules scoped to the cluster

import SwiftUI

struct ClusterIntentField: View {

    let clusterId: UUID
    let clusterColor: Color
    @Binding var intent: String
    let onIntentChanged: (String) -> Void

    @State private var isEditing = false
    @State private var editText = ""
    @State private var generatedRuleCount = 0
    @State private var parseTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("CLUSTER INTENT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.textMuted)
                    .tracking(0.8)

                Spacer(minLength: 0)

                if generatedRuleCount > 0 {
                    Text("\(generatedRuleCount) rule\(generatedRuleCount == 1 ? "" : "s") active")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DS.accent)
                }
            }

            intentEditor

            if intent.isEmpty {
                intentHint
            }
        }
        .onAppear {
            editText = intent
            updateRuleCount()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cluster intent")
    }

    // MARK: - Editor

    private var intentEditor: some View {
        HStack(spacing: 0) {
            Image(systemName: "sparkle")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(intent.isEmpty ? DS.textMuted.opacity(0.4) : clusterColor)
                .frame(width: 20)

            TextField(
                "e.g. Josh's content for review",
                text: $editText,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(DS.text)
            .lineLimit(1...2)
            .focused($isFocused)
            .onSubmit {
                commitIntent()
            }
            .onChange(of: isFocused) { _, focused in
                if !focused && editText != intent {
                    commitIntent()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DS.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isFocused ? clusterColor.opacity(0.4) : DS.borderSubtle, lineWidth: isFocused ? 1 : 0.5)
        )
    }

    private var intentHint: some View {
        Text("Describe what this cluster should collect — rules are auto-generated")
            .font(.system(size: 9, weight: .regular))
            .foregroundStyle(DS.textMuted.opacity(0.6))
            .lineSpacing(1)
    }

    // MARK: - Intent Processing

    private func commitIntent() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != intent else { return }

        intent = trimmed
        onIntentChanged(trimmed)

        guard !trimmed.isEmpty else {
            // Clear intent — remove auto-generated rules
            clearAutoRules()
            generatedRuleCount = 0
            return
        }

        // Parse intent into rules
        parseTask?.cancel()
        parseTask = Task {
            let rules = await IntentParser.parseClusterIntent(trimmed, clusterId: clusterId.uuidString)

            // Remove previous auto-generated intent rules for this cluster
            clearAutoRules()

            // Create new rules
            for rule in rules {
                try? await AutomationDispatcher.shared.createRule(rule)
            }

            generatedRuleCount = rules.count
        }
    }

    private func clearAutoRules() {
        let existing = AutomationDispatcher.shared.rules(for: clusterId.uuidString)
        let intentRules = existing.filter { $0.name.hasPrefix("Collect:") }
        Task {
            for rule in intentRules {
                try? await AutomationDispatcher.shared.deleteRule(uuid: rule.uuid)
            }
        }
    }

    private func updateRuleCount() {
        let existing = AutomationDispatcher.shared.rules(for: clusterId.uuidString)
        generatedRuleCount = existing.filter { $0.name.hasPrefix("Collect:") }.count
    }
}
