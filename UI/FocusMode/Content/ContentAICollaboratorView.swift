// CosmoOS/UI/FocusMode/Content/ContentAICollaboratorView.swift
// Floating AI Collaborator popover for Content Focus Mode
// February 2026

import SwiftUI

// MARK: - ContentAICollaboratorView

/// Floating popover chat UI for the AI Collaborator.
/// Anchored to the bottom-right of the Content Focus Mode view.
/// Triggered by AI button in bottom bar or Cmd+J.
struct ContentAICollaboratorView: View {
    @ObservedObject var engine: UnifiedWritingEngine
    @Binding var isVisible: Bool
    let contentAtom: Atom
    @Binding var state: ContentFocusModeState

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var showCompletedSteps = false
    @State private var showStructuralAlignment = false
    @State private var showSlideAnalysis = false

    private let popoverWidth: CGFloat = 380
    private let popoverMaxHeight: CGFloat = 500

    @State private var visibleMessageLimit = 30

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().background(DS.border)
            quickActionPills
            Divider().background(DS.border)

            messageList
            Divider().background(DS.border)
            inputBar

            // Undo toast
            if state.showUndoToast {
                undoToast
            }
        }
        .frame(width: popoverWidth)
        .frame(maxHeight: popoverMaxHeight)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(DS.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DS.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 30, y: 15)
        .onAppear {
            isInputFocused = true
        }
        .onChange(of: state.showUndoToast) { _, newValue in
            if newValue {
                // Auto-dismiss after 5 seconds
                Task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    await MainActor.run {
                        withAnimation(.easeOut(duration: 0.3)) {
                            state.showUndoToast = false
                        }
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.accent)

            Text("AI COLLABORATOR")
                .dsSectionLabel()

            Spacer()

            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    isVisible = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 24, height: 24)
                    .background(DS.border, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Quick Action Pills

    private var isPolishPhase: Bool {
        state.currentStep == .polish
    }

    private var quickActionPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if isPolishPhase {
                    polishPills
                } else {
                    defaultPills
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var defaultPills: some View {
        quickActionButton("Write draft", icon: "doc.text") {
            Task { await engine.generateDraft() }
        }
        quickActionButton("Suggest outline", icon: "list.bullet") {
            Task { await engine.suggestOutline() }
        }
        quickActionPill("Improve hook", icon: "text.quote")
        quickActionPill("Research topic", icon: "magnifyingglass")
    }

    @ViewBuilder
    private var polishPills: some View {
        quickActionPill("Improve Hook", icon: "text.quote")
        quickActionPill("Fix Voice Drift", icon: "waveform")
        quickActionPill("Strengthen CTA", icon: "megaphone")
    }

    private func quickActionPill(_ label: String, icon: String) -> some View {
        Button {
            sendMessage(label)
        } label: {
            quickActionPillLabel(label, icon: icon)
        }
        .buttonStyle(.plain)
        .disabled(engine.isProcessing)
    }

    private func quickActionButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            quickActionPillLabel(label, icon: icon)
        }
        .buttonStyle(.plain)
        .disabled(engine.isProcessing)
    }

    private func quickActionPillLabel(_ label: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(DS.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(DS.border, lineWidth: 1)
        )
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if engine.messages.isEmpty && !isPolishPhase {
                        emptyStateView
                    }

                    if engine.messages.count > visibleMessageLimit {
                        Button("Show earlier messages") { visibleMessageLimit += 30 }
                            .buttonStyle(.plain)
                            .foregroundStyle(DS.accent)
                    }
                    ForEach(engine.messages.suffix(visibleMessageLimit)) { message in
                        WritingMessageBubble(message: message)
                            .id(message.id)
                    }

                    if engine.isProcessing {
                        inlineToolProgress
                            .id("inlineToolProgress")
                    }

                    if let error = engine.error {
                        errorBanner(error)
                    }
                }
                .padding(14)
            }
            .onChange(of: engine.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: engine.isProcessing) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: engine.toolChainSteps.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 24))
                .foregroundStyle(DS.accent.opacity(0.3))

            Text("Ask me anything about your content")
                .font(.system(size: 12))
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)

            Text(error)
                .font(.system(size: 11))
                .foregroundStyle(.orange.opacity(0.9))
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.spring(response: 0.3)) {
            if engine.isProcessing {
                proxy.scrollTo("inlineToolProgress", anchor: .bottom)
            } else if let lastId = engine.messages.last?.id {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }

    // MARK: - Inline Tool Progress (replaces old top-level toolChainView)

    /// Inline progress view shown at the bottom of the message list where the AI is about to reply.
    /// Groups completed steps in a collapsible dropdown, shows active step prominently in gray.
    private var inlineToolProgress: some View {
        let completedSteps = engine.toolChainSteps.filter { $0.status == .completed }
        let activeStep = engine.toolChainSteps.last(where: { $0.status == .executing })

        return VStack(alignment: .leading, spacing: 6) {
            // Completed steps — collapsible dropdown
            if !completedSteps.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCompletedSteps.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: showCompletedSteps ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                        Text("\(completedSteps.count) action\(completedSteps.count == 1 ? "" : "s") completed")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(DS.textMuted)
                }
                .buttonStyle(.plain)

                if showCompletedSteps {
                    completedStepsList(completedSteps)
                }
            }

            // Currently active step
            if let active = activeStep {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .tint(DS.textSecondary)
                    Text(active.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.textSecondary)
                }
                .transition(.opacity)
            } else {
                // No active tool call — show typing dots
                CollaboratorTypingIndicator()
            }

            // Cancel button
            Button {
                engine.cancel()
            } label: {
                Text("Cancel")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DS.surfaceElevated)
                    .clipShape(.rect(cornerRadius: DS.radiusSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .stroke(DS.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func completedStepsList(_ steps: [WritingToolChainStep]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(steps) { step in
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DS.textMuted)
                    Text(step.label)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.textMuted)
                }
            }
        }
        .padding(.leading, 4)
        .transition(.opacity)
    }

    // MARK: - Undo Toast

    private var undoToast: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(DS.accent)

            Text(state.undoToastMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.text)

            Spacer()

            Button(action: {
                undoLastAIEdit()
            }) {
                Text("Undo")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .fill(DS.accentSoft)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .stroke(DS.accent.opacity(0.2), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button(action: {
                withAnimation(.easeOut(duration: 0.3)) {
                    state.showUndoToast = false
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(DS.surfaceElevated)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func undoLastAIEdit() {
        if let edit = state.popAIUndo() {
            state.draftContent = edit.previousContent
            state.save()
            withAnimation(.easeOut(duration: 0.3)) {
                state.showUndoToast = false
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about your content…", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(DS.text)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .onSubmit {
                    if NSEvent.modifierFlags.contains(.command) {
                        sendCurrentMessage()
                    }
                }

            if engine.isProcessing {
                Button {
                    engine.cancel()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Cancel request")
            } else {
                Button {
                    sendCurrentMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? DS.textMuted
                                : DS.accent
                        )
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DS.surfaceElevated)
        .overlay(
            Rectangle()
                .fill(DS.border)
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Actions

    private func sendCurrentMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        sendMessage(text)
    }

    private func sendMessage(_ text: String) {
        Task {
            _ = await engine.sendMessage(text, phase: state.currentStep)
        }
    }

}

// MARK: - Writing Message Bubble

private struct WritingMessageBubble: View {
    let message: WritingMessage

    private var isUser: Bool { message.role == .user }
    private var isAssistant: Bool { message.role == .assistant }
    private var isSystem: Bool { message.role == .system }
    private var isToolResult: Bool { message.role == .toolResult }

    /// Whether this message should be hidden (tool results, empty assistant messages).
    private var isHidden: Bool {
        if isToolResult { return true }
        if isAssistant && message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && message.toolCalls == nil {
            return true
        }
        return false
    }

    var body: some View {
        // Use @ViewBuilder control flow instead of AnyView to preserve SwiftUI's
        // diffing cache. AnyView forces full view recreation on every re-render.
        if isHidden {
            EmptyView()
        } else {
            messageContent
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
            // Timestamp + role indicator
            HStack(spacing: 4) {
                if isAssistant {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.accent)
                }
                if isSystem {
                    Image(systemName: "arrow.right.arrow.left")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.textMuted)
                }
                Text(message.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(DS.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

            // Tool call badges (inline)
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                toolCallBadges(toolCalls)
            }

            // Message content
            if !message.content.isEmpty {
                Text(message.content)
                    .font(.system(size: 13))
                    .foregroundStyle(isSystem ? DS.textSecondary : DS.text)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .fill(isUser ? DS.accentSoft :
                                  isSystem ? DS.border.opacity(0.3) :
                                  DS.surfaceElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .stroke(DS.border, lineWidth: 1)
                    )
                    .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            }

            // Copy button for assistant messages
            if isAssistant && !message.content.isEmpty {
                assistantMessageActions
            }
        }
    }

    @ViewBuilder
    private func toolCallBadges(_ toolCalls: [WritingToolCall]) -> some View {
        HStack(spacing: 4) {
            ForEach(toolCalls) { call in
                HStack(spacing: 3) {
                    Image(systemName: iconForTool(call.toolName))
                        .font(.system(size: 9))
                    Text(labelForTool(call.toolName))
                        .font(.system(size: 10, weight: .medium))
                    statusIcon(call.status)
                }
                .foregroundStyle(DS.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(DS.accent.opacity(0.1))
                )
            }
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: WritingToolCall.ToolCallStatus) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.green)
        case .executing:
            ProgressView()
                .scaleEffect(0.4)
                .tint(DS.accent)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.red)
        case .pending:
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 6, height: 6)
        }
    }

    private func iconForTool(_ name: String) -> String {
        switch name {
        case "think": return "brain"
        case "update_outline": return "list.bullet"
        case "add_hooks": return "sparkles"
        case "set_description": return "doc.text"
        case "write_draft": return "pencil.and.outline"
        case "edit_section": return "scissors"
        case "search_swipes": return "magnifyingglass"
        case "get_client_profile": return "person.crop.circle"
        default: return "gear"
        }
    }

    private func labelForTool(_ name: String) -> String {
        switch name {
        case "think": return "Reasoning"
        case "update_outline": return "Outline"
        case "add_hooks": return "Hooks"
        case "set_description": return "Description"
        case "write_draft": return "Draft"
        case "edit_section": return "Edit"
        case "search_swipes": return "Search"
        case "get_client_profile": return "Profile"
        default: return name
        }
    }

    private var assistantMessageActions: some View {
        HStack(spacing: 10) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                    Text("Copy")
                        .font(.system(size: 10))
                }
                .foregroundStyle(DS.textMuted)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Typing Indicator

private struct CollaboratorTypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 10))
                .foregroundStyle(DS.accent.opacity(0.5))

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(DS.accent)
                        .frame(width: 5, height: 5)
                        .opacity(animating ? 1 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.15),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: DS.radiusSmall).fill(DS.surfaceElevated))

            Spacer()
        }
        .onAppear { animating = true }
    }
}

