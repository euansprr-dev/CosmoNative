// CosmoOS/UI/FocusMode/Inquiry/Panes/InquiryCopilotPane.swift
// AI Copilot pane (Pane C) — sectioned: Context · Suggestions · Map · Recent · Ask Cosmo.

import SwiftUI

@MainActor
struct InquiryCopilotPane: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space16) {
                    contextStrip
                    if !viewModel.structured.mapForming.branchSuggestions.isEmpty
                        || !viewModel.structured.mapForming.contradictions.isEmpty
                        || !viewModel.structured.mapForming.concepts.isEmpty {
                        suggestionsTray
                    }
                    mapForming
                    recentSection
                }
                .padding(.horizontal, DS.space12)
                .padding(.vertical, DS.space12)
            }
            Divider().background(DS.borderSubtle)
            askInput
        }
    }

    // MARK: - Context

    private var contextStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("CONTEXT")
            if let dd = viewModel.deepDive, let title = dd.title {
                contextLine(icon: "circle.hexagongrid.circle.fill", text: title)
            }
            if let q = viewModel.rootQuestion?.title {
                contextLine(icon: "questionmark.bubble", text: q)
            }
            if let activeQ = viewModel.activeQuestionUUID, activeQ != viewModel.rootQuestion?.uuid {
                contextLine(icon: "arrow.triangle.branch", text: "branch: \(activeQ.prefix(8))…")
            }
        }
    }

    private func contextLine(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(CosmoColors.textTertiary)
            Text(text)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textSecondary)
                .lineLimit(2)
        }
    }

    // MARK: - Suggestions tray

    private var suggestionsTray: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("SUGGESTIONS")
            ForEach(viewModel.structured.mapForming.branchSuggestions.prefix(3), id: \.id) { s in
                suggestionChip(icon: "arrow.triangle.branch", text: "New branch: \(s.proposedQuestion)")
            }
            ForEach(viewModel.structured.mapForming.contradictions.prefix(2), id: \.id) { c in
                suggestionChip(icon: "exclamationmark.triangle", text: c.description)
            }
        }
    }

    private func suggestionChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(DS.accent)
            Text(text)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, 6)
        .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
    }

    // MARK: - Map forming

    private var mapForming: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("MAP FORMING")
            let concepts = viewModel.structured.mapForming.concepts
            if concepts.isEmpty {
                Text("Nothing detected yet — keep capturing and the cartographer will surface terms.")
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary)
            } else {
                ForEach(concepts.prefix(6), id: \.id) { c in
                    HStack {
                        Circle().fill(DS.accent.opacity(0.6)).frame(width: 5, height: 5)
                        Text(c.label)
                            .font(CosmoTypography.caption)
                            .foregroundStyle(CosmoColors.textSecondary)
                        Spacer()
                        Text("\(c.mentionCount)")
                            .font(CosmoTypography.caption)
                            .foregroundStyle(CosmoColors.textTertiary)
                    }
                }
            }
            if !viewModel.structured.mapForming.openLoops.isEmpty {
                Text("OPEN LOOPS")
                    .font(CosmoTypography.labelSmall)
                    .foregroundStyle(CosmoColors.textTertiary)
                    .padding(.top, 4)
                ForEach(viewModel.structured.mapForming.openLoops.prefix(4), id: \.id) { loop in
                    Text("· \(loop.description)")
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textSecondary)
                }
            }
        }
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("RECENT")
            let recent = viewModel.structured.aiInteractions.suffix(3)
            if recent.isEmpty {
                Text("No AI conversation yet.")
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary)
            } else {
                ForEach(Array(recent), id: \.id) { interaction in
                    interactionRow(interaction)
                }
            }
        }
    }

    private func interactionRow(_ interaction: AIInteractionRef) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Q: \(interaction.prompt)")
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textPrimary)
                .lineLimit(2)
            Text(interaction.response)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textSecondary)
                .lineLimit(4)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Ask input

    private var askInput: some View {
        VStack(spacing: 4) {
            HStack {
                TextField("Ask Cosmo…", text: $viewModel.aiPromptDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(CosmoTypography.body)
                    .padding(DS.space10)
                    .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .stroke(DS.borderSubtle, lineWidth: 1)
                    )
                Button {
                    let prompt = viewModel.aiPromptDraft
                    Task { await viewModel.runAIPrompt(prompt) }
                } label: {
                    Image(systemName: viewModel.aiBusy ? "ellipsis" : "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(DS.accent)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.aiBusy || viewModel.aiPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack(spacing: 6) {
                quickPromptChip("Explain simply")
                quickPromptChip("What does this contradict?")
                quickPromptChip("How does this connect?")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space10)
    }

    private func quickPromptChip(_ text: String) -> some View {
        Button {
            viewModel.aiPromptDraft = text
        } label: {
            Text(text)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay(Capsule().stroke(DS.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(CosmoTypography.labelSmall)
            .tracking(2)
            .foregroundStyle(CosmoColors.textSecondary.opacity(0.78))
    }
}
