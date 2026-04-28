// CosmoOS/UI/FocusMode/Content/WritingAICardView.swift
// Floating Cosmo Writing AI card for Content Focus Mode.

import SwiftUI
import AppKit

struct WritingAICardView: View {
    @Binding var isPresented: Bool
    @ObservedObject var assistant: ContentWritingAssistant

    var contextTitle: String
    var baseContextChips: [WritingAIReferenceSource]
    var hasSelection: Bool
    var isPolishMode: Bool
    var onSubmitPrompt: (String) -> Void
    var onQuickAction: (WritingAIQuickAction) -> Void
    var onReplaceSelection: (String) -> Void
    var onInsertBelow: (String) -> Void
    var onOpenReference: (WritingAIReference) -> Void

    @State private var promptText = ""

    private var visibleActions: [WritingAIQuickAction] {
        WritingAIQuickAction.allCases.filter { action in
            if action.editTarget == .selection { return hasSelection }
            if !isPolishMode && action == .critique { return true }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(DS.borderSubtle)
            bodyContent
            Divider().background(DS.borderSubtle)
            inputBar
        }
        .frame(width: 440, height: 560)
        .background(cardBackground)
        .clipShape(.rect(cornerRadius: DS.radiusLarge))
        .shadow(color: DS.inkWash.opacity(0.28), radius: 28, x: 0, y: 18)
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusLarge)
                .stroke(DS.border.opacity(0.85), lineWidth: 1)
        )
        .transition(.scale(scale: 0.97, anchor: .topTrailing).combined(with: .opacity))
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    private var cardBackground: some ShapeStyle {
        LinearGradient(
            colors: [DS.surfaceElevated, DS.surface],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            HStack(spacing: DS.space8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.gilt)
                Text("Cosmo Writing Context")
                    .font(DS.buttonText)
                    .foregroundStyle(DS.text)
                Spacer()
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        isPresented = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.textMuted)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Writing AI")
            }

            Text(contextTitle)
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)

            chipRow(Array(Set(baseContextChips + assistant.activeReferences.map(\.source))))
        }
        .padding(DS.space16)
    }

    @ViewBuilder
    private var bodyContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space16) {
                switch assistant.phase {
                case .idle:
                    idleState
                case .retrieving:
                    activityState(title: "Gathering context", subtitle: "Client profile, draft, swipes, and sources.")
                case .thinking:
                    activityState(title: "Writing", subtitle: "Synthesizing the smallest useful answer.")
                case .answer:
                    if let response = assistant.currentResponse {
                        answerState(response)
                    } else {
                        idleState
                    }
                case .error(let message):
                    errorState(message)
                }
            }
            .padding(DS.space16)
        }
    }

    private var idleState: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            quickActionsGrid
            Text(hasSelection ? "Selection-aware actions are ready." : "Ask for a critique, examples, profile search, proof, or variations.")
                .font(DS.footnote)
                .foregroundStyle(DS.textMuted)
        }
    }

    private func activityState(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack(spacing: DS.space8) {
                ThinkingDots()
                Text(title)
                    .font(DS.buttonText)
                    .foregroundStyle(DS.text)
            }
            Text(subtitle)
                .font(DS.footnote)
                .foregroundStyle(DS.textSecondary)
            if !assistant.activeReferences.isEmpty {
                referencesSection(assistant.activeReferences)
            }
        }
    }

    private func answerState(_ response: WritingAIResponse) -> some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack(spacing: DS.space8) {
                Text(response.title)
                    .font(DS.navTitle)
                    .foregroundStyle(DS.text)
                Spacer()
                Text(response.modelTier.rawValue)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .padding(.horizontal, DS.space6)
                    .padding(.vertical, DS.space2)
                    .background(DS.borderSubtle, in: Capsule())
            }

            Text(response.body)
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(DS.text)
                .textSelection(.enabled)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            suggestionActions(response)

            if !response.references.isEmpty {
                referencesSection(response.references)
            }
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack(spacing: DS.space8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(DS.orange)
                Text("Cosmo could not finish")
                    .font(DS.buttonText)
                    .foregroundStyle(DS.text)
            }
            Text(message)
                .font(DS.footnote)
                .foregroundStyle(DS.textSecondary)
            Button("Try again") {
                Task { await assistant.retry() }
            }
            .buttonStyle(DSGhostButtonStyle())
        }
    }

    private var quickActionsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: DS.space8)], spacing: DS.space8) {
            ForEach(visibleActions) { action in
                Button {
                    onQuickAction(action)
                } label: {
                    HStack(spacing: DS.space6) {
                        Image(systemName: action.iconName)
                            .font(.system(size: 11, weight: .semibold))
                        Text(action.label)
                            .font(DS.caption)
                            .lineLimit(1)
                    }
                    .foregroundStyle(DS.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                    .padding(.horizontal, DS.space10)
                    .background(DS.surfaceHover.opacity(0.55), in: RoundedRectangle(cornerRadius: DS.radiusSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .stroke(DS.borderSubtle, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(assistant.isProcessing)
                .help(action.prompt)
            }
        }
    }

    private func suggestionActions(_ response: WritingAIResponse) -> some View {
        HStack(spacing: DS.space8) {
            if let replacement = response.proposedReplacement, response.canReplaceSelection {
                Button {
                    onReplaceSelection(replacement)
                } label: {
                    Label("Replace", systemImage: "checkmark")
                }
                .buttonStyle(DSPrimaryButtonStyle())
            }

            Button {
                onInsertBelow(response.proposedReplacement ?? response.body)
            } label: {
                Label("Insert below", systemImage: "text.insert")
            }
            .buttonStyle(DSGhostButtonStyle())

            Button {
                copy(response.proposedReplacement ?? response.body)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(DSGhostButtonStyle())

            Button {
                Task { await assistant.retry() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Try another")
            .help("Try another")
        }
    }

    private func referencesSection(_ references: [WritingAIReference]) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text("References")
                .font(DS.smallCaps)
                .tracking(1.2)
                .foregroundStyle(DS.giltMuted)
            ForEach(references.prefix(6)) { reference in
                Button {
                    onOpenReference(reference)
                } label: {
                    HStack(alignment: .top, spacing: DS.space8) {
                        Image(systemName: reference.source.iconName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.giltMuted)
                            .frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(reference.title)
                                .font(DS.caption)
                                .foregroundStyle(DS.text)
                                .lineLimit(1)
                            Text(reference.excerpt)
                                .font(DS.caption2)
                                .foregroundStyle(DS.textMuted)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(DS.space8)
                    .background(DS.borderSubtle.opacity(0.55), in: RoundedRectangle(cornerRadius: DS.radiusSmall))
                }
                .buttonStyle(.plain)
                .disabled(reference.atomUUID == nil && reference.url == nil)
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: DS.space10) {
            HStack(alignment: .bottom, spacing: DS.space8) {
                TextField("Ask, rewrite, search, or critique...", text: $promptText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .lineLimit(1...4)
                    .padding(.horizontal, DS.space12)
                    .padding(.vertical, DS.space10)
                    .background(DS.glassInputFill, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusMedium)
                            .stroke(DS.glassBorder, lineWidth: 1)
                    )
                    .onSubmit { submitPrompt() }

                Button {
                    submitPrompt()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.textOnAccent)
                        .frame(width: 34, height: 34)
                        .background(DS.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || assistant.isProcessing)
                .accessibilityLabel("Send to Writing AI")
            }
        }
        .padding(DS.space12)
    }

    private func chipRow(_ sources: [WritingAIReferenceSource]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.space6) {
                ForEach(sources) { source in
                    Label(source.label, systemImage: source.iconName)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textSecondary)
                        .padding(.horizontal, DS.space8)
                        .padding(.vertical, DS.space4)
                        .background(DS.borderSubtle, in: Capsule())
                }
            }
        }
    }

    private func submitPrompt() {
        let trimmed = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        promptText = ""
        onSubmitPrompt(trimmed)
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private struct ThinkingDots: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.28)) { timeline in
            let phase = Int(timeline.date.timeIntervalSinceReferenceDate / 0.28) % 3
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(DS.gilt.opacity(index == phase ? 0.95 : 0.35))
                        .frame(width: 5, height: 5)
                }
            }
        }
    }
}
