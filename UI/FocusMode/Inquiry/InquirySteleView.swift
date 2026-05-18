// CosmoOS/UI/FocusMode/Inquiry/InquirySteleView.swift
// Center "stele" — vellum card holding the active question (serif), live AI synthesis,
// activity counts, continue affordance, and a dim ambient quick-actions row.

import SwiftUI

@MainActor
struct InquirySteleView: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let onFocusDock: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: DS.space20) {
                Spacer(minLength: DS.space32)
                steleCard
                    .frame(maxWidth: 640)
                    .padding(.horizontal, DS.space20)
                InquiryAmbientQuickActionsRow(viewModel: viewModel)
                    .padding(.horizontal, DS.space20)
                Spacer(minLength: DS.space48)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }

    // MARK: - Stele card

    private var steleCard: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            questionTitle
            AkashicSectionDivider()
                .padding(.horizontal, -DS.space24)
            InquiryLiveUnderstandingView(viewModel: viewModel)
            countsLine
            continueAffordance
        }
        .padding(.horizontal, DS.space24)
        .padding(.vertical, DS.space24)
        .dsVellumCard(cornerRadius: DS.radiusLarge)
    }

    private var questionTitle: some View {
        Text(viewModel.activeQuestionTitle)
            .font(.system(.title, design: .serif).weight(.regular))
            .foregroundStyle(CosmoColors.textPrimary)
            .multilineTextAlignment(.leading)
            .lineSpacing(4)
            .accessibilityAddTraits(.isHeader)
    }

    private var countsLine: some View {
        let counts = viewModel.counts(for: viewModel.activeQuestionUUID)
        return HStack(spacing: DS.space12) {
            countPill(value: counts.claims, label: counts.claims == 1 ? "claim" : "claims", color: DS.accent)
            countPill(value: counts.notes, label: counts.notes == 1 ? "note" : "notes", color: CosmoColors.note)
            countPill(value: counts.sources, label: counts.sources == 1 ? "source" : "sources", color: DS.green)
            countPill(value: counts.children, label: counts.children == 1 ? "branch" : "branches", color: DS.accent.opacity(0.7))
            Spacer(minLength: 0)
        }
    }

    private func countPill(value: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(CosmoTypography.label)
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    private var continueAffordance: some View {
        Button {
            onFocusDock()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Continue exploring")
                    .font(CosmoTypography.caption)
            }
            .foregroundStyle(DS.accent)
            .padding(.horizontal, DS.space10)
            .padding(.vertical, 6)
            .background(DS.accent.opacity(0.06), in: Capsule())
            .overlay(Capsule().stroke(DS.accent.opacity(0.18), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue exploring — focus the thinking dock")
    }
}

// MARK: - Live Understanding

@MainActor
struct InquiryLiveUnderstandingView: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel

    @State private var dotPulse: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            header
            content
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(viewModel.liveUnderstandingIsForming ? "Forming understanding…" : "Current understanding")
                .dsSmallCapsLabel()
            if viewModel.liveUnderstandingIsForming {
                Circle()
                    .fill(DS.accent)
                    .frame(width: 6, height: 6)
                    .opacity(dotPulse ? 0.3 : 1)
                    .onAppear { startPulse() }
                    .accessibilityHidden(true)
            }
            Spacer()
            if viewModel.structured.currentUnderstandingDraft != nil {
                Button {
                    Task { await viewModel.regenerateLiveUnderstanding(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(CosmoColors.textTertiary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Regenerate understanding")
                .accessibilityLabel("Regenerate understanding")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let draft = viewModel.structured.currentUnderstandingDraft, !draft.text.isEmpty {
            Text(draft.text)
                .font(.system(.body, design: .serif))
                .foregroundStyle(CosmoColors.textPrimary.opacity(0.88))
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .transition(.opacity)
        } else if let error = viewModel.liveUnderstandingError {
            Text(error)
                .font(.system(.callout, design: .serif))
                .foregroundStyle(CosmoColors.textTertiary)
                .multilineTextAlignment(.leading)
        } else {
            Text("Capture a claim, paste a source, or ask a question — synthesis will form here as the inquiry grows.")
                .font(.system(.callout, design: .serif))
                .foregroundStyle(CosmoColors.textTertiary)
                .multilineTextAlignment(.leading)
        }
    }

    private func startPulse() {
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            dotPulse.toggle()
        }
    }
}

// MARK: - Ambient quick actions

@MainActor
struct InquiryAmbientQuickActionsRow: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel

    var body: some View {
        HStack(spacing: DS.space12) {
            quickAction(icon: "text.book.closed", label: "Summarize") {
                Task { await viewModel.runAIPrompt("Summarize the current state of inquiry on \(viewModel.activeQuestionTitle) into 4–5 sentences with hedges.") }
            }
            quickAction(icon: "exclamationmark.triangle", label: "Challenge") {
                Task { await viewModel.submitDockText("/challenge") }
            }
            quickAction(icon: "arrow.branch", label: "Branch") {
                Task { await viewModel.runAIPrompt("Propose 3 child branch questions that would advance the inquiry on \(viewModel.activeQuestionTitle).") }
            }
            quickAction(icon: "scope", label: "Find related") {
                Task { await viewModel.refreshSourceRecommendations(query: nil, mode: .quick) }
            }
            Spacer(minLength: 0)
        }
        .opacity(0.78)
    }

    private func quickAction(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .accessibilityHidden(true)
                Text(label)
                    .font(CosmoTypography.caption)
            }
            .foregroundStyle(CosmoColors.textSecondary)
            .padding(.horizontal, DS.space10)
            .padding(.vertical, 6)
            .overlay(Capsule().stroke(DS.borderSubtle, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
