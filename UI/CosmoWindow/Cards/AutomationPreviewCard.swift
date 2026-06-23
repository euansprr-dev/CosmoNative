// CosmoOS/UI/CosmoWindow/Cards/AutomationPreviewCard.swift
// Automation rule visualization card for inline chat results

import SwiftUI

struct AutomationPreviewCard: View {
    let data: AutomationPreviewData
    @State private var isEnabled: Bool

    init(data: AutomationPreviewData) {
        self.data = data
        self._isEnabled = State(initialValue: data.isEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            triggerRow
            actionRows
        }
        .padding(16)
        .background(DS.surfaceElevated)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.border, lineWidth: 1)
        )
        .shadow(color: DS.text.opacity(0.06), radius: 8, y: 4)
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack {
            Image(systemName: "gearshape.2.fill")
                .font(.caption)
                .foregroundStyle(DS.accent)
                .accessibilityLabel("Automation")
            Text(data.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.text)
            Spacer()
            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
    }

    private var triggerRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.caption)
                .foregroundStyle(DS.orange)
                .frame(width: 16)
                .accessibilityLabel("Trigger")
            Text("When: \(data.triggerDescription)")
                .font(.caption)
                .foregroundStyle(DS.textSecondary)
        }
    }

    private var actionRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(data.actionDescriptions.enumerated()), id: \.offset) { _, action in
                actionRow(action)
            }
        }
    }

    private func actionRow(_ action: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(DS.green)
                .frame(width: 16)
                .accessibilityLabel("Action")
            Text("Then: \(action)")
                .font(.caption)
                .foregroundStyle(DS.textSecondary)
        }
    }
}
