// CosmoOS/UI/FocusMode/Inquiry/Study/StudyThinkingBar.swift
// The Study's instrument — the inline assistant bar's material with ONE
// stable shape: the composer and its action footer are always present, so
// nothing collapses, stretches, or pops in and out of sync. Focus is a
// whisper (border warms, shadow deepens a touch), never a layout event.
// The clip keeps a growing multi-line draft painting inside the surface.
// Successor of InquiryAssistantDock; the routing brain (submitDockText,
// prefix parser, suggestions) is untouched.

import SwiftUI

@MainActor
struct StudyThinkingBar: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    @Binding var draft: String
    @FocusState.Binding var isFocused: Bool
    /// Physical capture: wired by the shell — upload images from this Mac,
    /// or wake the iPhone as a wireless scanner.
    var onScanUpload: (() -> Void)?
    var onScanPhone: (() -> Void)?

    @State private var showSuggestions = false
    @State private var suggestionsHeight: CGFloat = 0

    private let barShape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    var body: some View {
        barBody
            // Real glass — the bar is chrome floating over the transcript, and
            // the material's lensing is what separates it from parchment pages
            // (a near-opaque parchment fill camouflaged it against DS.bg).
            .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 24)
            .overlay { barShape.stroke(borderColor, lineWidth: 1) }
            .frame(maxWidth: StudyMetrics.barMaxWidth)
            .overlay(alignment: .topLeading) { suggestionsOverlay }
            // Focus only warms the ring — the shape never moves.
            .animation(ProMotionSprings.hover, value: isFocused)
            .animation(ProMotionSprings.gentle, value: showSuggestions)
            .onChange(of: viewModel.dockFocusTick) {
                isFocused = true
            }
    }

    private var borderColor: Color {
        // The glass rim carries the resting edge; the stroke exists for focus.
        isFocused ? DS.accent.opacity(0.36) : .clear
    }

    // MARK: - Bar anatomy (one stable shape — nothing appears or collapses)

    private var barBody: some View {
        VStack(spacing: 0) {
            composerRow
            actionsFooter
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space10)
    }

    private var composerRow: some View {
        HStack(alignment: .center, spacing: DS.space10) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(DS.accent)
                .accessibilityHidden(true)

            if let activity = viewModel.sourceActivityLine, draft.isEmpty, !isFocused {
                activityLine(activity)
            } else {
                field
            }

            sendButton
        }
        .frame(minHeight: 32)
    }

    private var field: some View {
        TextField("Think out loud, paste a URL, or type / for commands", text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(DS.body)
            .foregroundStyle(DS.text)
            .focused($isFocused)
            .lineLimit(1...4)
            .onSubmit(submit)
            .onChange(of: draft) { _, newValue in
                showSuggestions = shouldShowSuggestions(for: newValue) && isFocused
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { showSuggestions = false }
            }
    }

    private func activityLine(_ activity: String) -> some View {
        HStack(spacing: DS.space8) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.6)
            Text(activity)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .transition(.opacity)
    }

    /// Where this thought lands — scope lives inside the instrument.
    private var scopeChip: some View {
        HStack(spacing: DS.space4) {
            Image(systemName: "arrow.turn.down.right")
                .font(DS.caption2.weight(.semibold))
                .accessibilityHidden(true)
            Text(scopeTitle)
                .font(DS.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(DS.accent)
        .padding(.horizontal, DS.space8)
        .padding(.vertical, 4)
        .background(DS.accentSoft, in: Capsule())
        .fixedSize()
        .help("Captures save to: \(viewModel.activeQuestionTitle)")
        .accessibilityLabel("Saving to \(viewModel.activeQuestionTitle)")
    }

    private var scopeTitle: String {
        let title = viewModel.activeQuestionTitle
        return title.count > 26 ? "\(title.prefix(24))…" : title
    }

    private var sendButton: some View {
        Button(action: submit) {
            Group {
                if viewModel.aiBusy {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.up")
                        .font(DS.caption.weight(.bold))
                }
            }
            .frame(width: 28, height: 28)
            .background(isDraftEmpty ? AnyShapeStyle(DS.glassInputFill) : AnyShapeStyle(DS.accent), in: Circle())
            .foregroundStyle(isDraftEmpty ? DS.textMuted : DS.textOnAccent)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDraftEmpty || viewModel.aiBusy)
        .keyboardShortcut(.return, modifiers: [])
        .help("Send")
        .accessibilityLabel(viewModel.aiBusy ? "Thinking" : "Send")
    }

    // MARK: - Action chips footer

    /// Small hover-lit chips along the bar's foot; the scope chip anchors the
    /// trailing end. Everything is sized so the row never crowds the surface.
    private var actionsFooter: some View {
        HStack(spacing: DS.space6) {
            StudyFooterActionChip(label: "Summarize", shortcut: "⌘⇧1") {
                Task { await viewModel.runAIPrompt("Summarize the current state of inquiry on \(viewModel.activeQuestionTitle) into 4–5 sentences with hedges.") }
            }
            StudyFooterActionChip(label: "Challenge", shortcut: "⌘⇧2") {
                Task { await viewModel.submitDockText("/challenge") }
            }
            StudyFooterActionChip(label: "Branch", shortcut: "⌘⇧3") {
                Task { await viewModel.runAIPrompt("Propose 3 child branch questions that would advance the inquiry on \(viewModel.activeQuestionTitle).") }
            }
            StudyFooterActionChip(label: "Scout", shortcut: "⌘⇧4") {
                Task { await viewModel.refreshSourceRecommendations(query: nil, mode: .deepScout) }
            }
            if onScanUpload != nil || onScanPhone != nil {
                scanMenu
            }
            Spacer(minLength: DS.space8)
            scopeChip
        }
        .padding(.top, DS.space8)
    }

    /// Physical pages into the session: a quiet menu chip in the same voice
    /// as its neighbors — upload from this Mac, or wake the iPhone camera.
    private var scanMenu: some View {
        Menu {
            if let onScanPhone {
                Button {
                    onScanPhone()
                } label: {
                    Label("Scan with iPhone", systemImage: "iphone.and.arrow.right.inward")
                }
            }
            if let onScanUpload {
                Button {
                    onScanUpload()
                } label: {
                    Label("Upload images…", systemImage: "photo.badge.plus")
                }
            }
        } label: {
            HStack(spacing: DS.space4) {
                Text("Scan")
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(DS.textSecondary)
                Text("⌘⇧5")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .opacity(0.5)
            }
            .padding(.horizontal, DS.space8)
            .padding(.vertical, 4)
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("Digitize a physical page (⌘⇧5)")
        .accessibilityLabel("Scan a physical page")
    }

    // MARK: - Slash suggestions (floats above the bar)

    @ViewBuilder
    private var suggestionsOverlay: some View {
        if showSuggestions && !suggestions.isEmpty {
            InquiryDockSuggestionsView(suggestions: suggestions, onSelect: applySuggestion)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                    suggestionsHeight = height
                }
                .offset(y: -(suggestionsHeight + DS.space8))
                .opacity(suggestionsHeight > 0 ? 1 : 0)
                .zIndex(1)
                .transition(.opacity)
        }
    }

    // MARK: - Logic (identical to the dock it replaces)

    private var isDraftEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        showSuggestions = false
        Task { await viewModel.submitDockText(text) }
    }

    private func shouldShowSuggestions(for draft: String) -> Bool {
        guard draft.hasPrefix("/") else { return false }
        return !draft.contains(" ") || draft.trimmingCharacters(in: .whitespaces) == "/"
    }

    private var slashFilter: String {
        guard draft.hasPrefix("/") else { return "" }
        return String(draft.dropFirst())
            .split(separator: " ").first.map(String.init) ?? ""
    }

    private var suggestions: [InquiryDockSuggestion] {
        Array(InquiryDockSuggestion.all.filter { $0.matchesSlashFilter(slashFilter) }.prefix(12))
    }

    private func applySuggestion(_ suggestion: InquiryDockSuggestion) {
        draft = "\(suggestion.token) "
        showSuggestions = false
        isFocused = true
    }
}

/// One small taught action: a quiet chip that lights on hover (wash + ink)
/// and whispers its shortcut beside the label.
@MainActor
private struct StudyFooterActionChip: View {
    let label: String
    let shortcut: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space4) {
                Text(label)
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(isHovered ? DS.text : DS.textSecondary)
                Text(shortcut)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .opacity(isHovered ? 1 : 0.5)
            }
            .padding(.horizontal, DS.space8)
            .padding(.vertical, 4)
            .background(isHovered ? DS.glassInputFill : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help("\(label) (\(shortcut))")
        .accessibilityLabel("\(label), shortcut \(shortcut)")
    }
}
