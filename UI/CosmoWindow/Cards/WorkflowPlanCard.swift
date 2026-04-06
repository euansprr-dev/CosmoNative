// CosmoOS/UI/CosmoWindow/Cards/WorkflowPlanCard.swift
// Multi-step workflow plan card for inline chat results

import SwiftUI

struct WorkflowPlanCard: View {
    let data: WorkflowPlanData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            workflowHeader
            stepsList
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

    private var workflowHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.caption)
                .foregroundStyle(DS.accent)
                .accessibilityLabel("Workflow plan")
            Text(data.description)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.text)
        }
    }

    private var stepsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(data.steps, id: \.index) { step in
                stepRow(step)
            }
        }
    }

    private func stepRow(_ step: WorkflowStepData) -> some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon(for: step.status)
                .frame(width: 20, height: 20)
            stepContent(step)
        }
    }

    private func stepContent(_ step: WorkflowStepData) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(step.tool)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DS.text)
            Text(step.description)
                .font(.caption)
                .foregroundStyle(DS.textSecondary)
        }
    }

    @ViewBuilder
    private func statusIcon(for status: String) -> some View {
        switch status.lowercased() {
        case "done":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(DS.green)
                .accessibilityLabel("Completed")
        case "running":
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Running")
        case "failed":
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(DS.red)
                .accessibilityLabel("Failed")
        default:
            Image(systemName: "circle")
                .foregroundStyle(DS.textMuted)
                .accessibilityLabel("Pending")
        }
    }
}
