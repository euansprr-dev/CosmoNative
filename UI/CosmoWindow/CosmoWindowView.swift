// CosmoOS/UI/CosmoWindow/CosmoWindowView.swift
// Premium floating Cosmo agent overlay
// March 2026

import SwiftUI

struct CosmoWindowView: View {
    @ObservedObject private var viewModel = CosmoWindowViewModel.shared
    @Binding var isVisible: Bool
    @AppStorage("cosmoWindowAnchor") private var anchor: CosmoWindowAnchor = .right
    @Environment(\.cosmoWindowIsFloating) private var isFloating
    @State private var isComposerFocused = false
    @State private var showModelPicker = false
    @State private var showAgentPicker = false
    @State private var showAgentManager = false

    @State private var bottomAnchorID = "bottom"
    @State private var pendingScrollWorkItem: DispatchWorkItem?

    var body: some View {
        if isFloating {
            panelShell
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
                .onAppear(perform: handleAppear)
        } else {
            HStack(spacing: 0) {
                if anchor == .right {
                    Spacer(minLength: 0)
                }

                panelShell
                    .dsFloatingShadow()
                    .frame(width: CosmoWindowMetrics.defaultWidth)
                    .padding(.vertical, 18)

                if anchor == .left {
                    Spacer(minLength: 0)
                }
            }
            .onAppear(perform: handleAppear)
        }
    }

    private var panelShell: some View {
        VStack(spacing: 0) {
            headerBar

            if viewModel.activeContext.type != .none {
                contextSummarySection
            }

            ZStack(alignment: .bottom) {
                messageStage
                    .frame(minHeight: CosmoWindowMetrics.minimumMessageStageHeight)
                    .layoutPriority(1)

                if viewModel.showMentionOverlay {
                    CosmoMentionOverlay(
                        isVisible: $viewModel.showMentionOverlay,
                        searchText: $viewModel.mentionSearchText,
                        onSelect: { atom in
                            insertMention(atom)
                        },
                        onDismiss: {
                            dismissMentionOverlay(trimMentionQuery: true)
                        }
                    )
                    .frame(maxHeight: CosmoWindowMetrics.mentionOverlayMaxHeight)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 4)
                }
            }

            composerSection
        }
        .cosmoGlassPanel(
            sceneMaterial: .neutral,
            role: .floatingAssistant,
            cornerRadius: CosmoWindowMetrics.panelCornerRadius
        )
        .compositingGroup()
    }

    private var headerBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Cosmo")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(DS.text)

                Text(headerSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let error = viewModel.error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(error)
                        .lineLimit(1)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DS.red)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .cosmoWindowChip(activeFill: DS.redSoft, activeBorder: DS.red.opacity(0.18))
            } else if viewModel.isProcessing {
                ProcessingStatusPill(
                    startedAt: viewModel.processingStartedAt,
                    label: viewModel.activeToolLabel ?? "Thinking"
                )
            }

            HStack(spacing: 6) {
                agentSelector

                if !viewModel.isCollaboratorActive {
                    headerControlButton("plus.message") {
                        Task { await viewModel.startNewChat() }
                    }
                    .help("New Chat")

                    headerControlButton("clock.arrow.circlepath") {
                        viewModel.showChatHistory.toggle()
                    }
                    .help("Chat History")
                    .popover(isPresented: $viewModel.showChatHistory) {
                        chatHistoryPopover
                    }
                }

                if viewModel.isCurrentContextDockable {
                    headerControlButton("rectangle.split.2x1") {
                        guard let atomUUID = viewModel.dockableContextAtomUUID else { return }
                        NotificationCenter.default.post(
                            name: CosmoNotification.Navigation.openCollaboratorPane,
                            object: nil,
                            userInfo: CosmoNotification.Navigation.CollaboratorPanePayload(
                                atomUUID: atomUUID,
                                presetId: viewModel.currentCollaboratorPresetID ?? "deepen"
                            ).userInfo
                        )
                    }
                    .help("Dock Collaborator")
                }

                headerControlButton("xmark") {
                    CosmoWindowPanelController.shared.hide()
                }
                .help("Close")
            }
            .padding(4)
            .cosmoWindowGroupChrome(cornerRadius: 14)
        }
        .padding(.horizontal, CosmoWindowMetrics.contentPadding)
        .frame(height: CosmoWindowMetrics.headerHeight)
    }

    private var contextSummarySection: some View {
        CosmoContextBar(context: viewModel.activeContext)
            .padding(.horizontal, CosmoWindowMetrics.contentPadding)
            .padding(.bottom, 6)
    }

    private var messageStage: some View {
        ScrollViewReader { proxy in
            GeometryReader { stageProxy in
                ScrollView {
                    VStack(spacing: CosmoWindowMetrics.messageSpacing) {
                        if viewModel.messages.isEmpty {
                            CosmoEmptyStateCard(
                                context: viewModel.activeContext,
                                isCollaboratorMode: viewModel.isCollaboratorActive,
                                suggestions: promptSuggestions,
                                onSelectSuggestion: queuePrompt
                            )
                            .frame(maxWidth: CosmoWindowMetrics.readyStateMaxWidth)
                            .frame(maxWidth: .infinity)
                        } else {
                            ForEach(viewModel.messages) { message in
                                CosmoMessageBubble(
                                    message: message,
                                    onEdit: message.type == .user ? { msg in
                                        viewModel.editAndResend(messageId: msg.id)
                                        focusComposer()
                                    } : nil
                                )
                            }
                        }

                        if let plan = viewModel.pendingCanvasPlan {
                            CosmoCanvasPlanReviewCard(
                                plan: plan,
                                onApply: viewModel.applyPendingCanvasPlan,
                                onRevise: viewModel.revisePendingCanvasPlan,
                                onCancel: viewModel.cancelPendingCanvasPlan
                            )
                            .padding(.horizontal, CosmoWindowMetrics.contentPadding)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }

                        if viewModel.isProcessing {
                            CosmoThinkingCard(
                                activeLabel: viewModel.activeToolLabel ?? "Thinking",
                                startedAt: viewModel.processingStartedAt,
                                groups: viewModel.liveToolActivity,
                                onCancel: viewModel.cancelCurrentOperation
                            )
                            .padding(.horizontal, CosmoWindowMetrics.contentPadding)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorID)
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: viewModel.messages.isEmpty ? stageProxy.size.height : 0,
                        alignment: viewModel.messages.isEmpty ? .center : .top
                    )
                    .padding(.horizontal, 0)
                    .padding(.vertical, viewModel.messages.isEmpty ? 8 : 20)
                }
                .background(Color.clear)
            }
            .onChange(of: viewModel.messages.count) { _ in
                debouncedScrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.isProcessing) { _ in
                debouncedScrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.toolActivityScrollTick) { _ in
                debouncedScrollToBottom(proxy: proxy)
            }
        }
    }

    private var composerSection: some View {
        VStack(spacing: 10) {
            if viewModel.pendingEditIndex != nil {
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DS.accent)

                    Text("Editing earlier message")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.text)

                    Spacer(minLength: 0)

                    Button("Cancel") {
                        viewModel.pendingEditIndex = nil
                        viewModel.inputText = ""
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .cosmoWindowSectionChrome(cornerRadius: 14, shadow: false)
            }

            HStack(alignment: .center, spacing: 10) {
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        if viewModel.showMentionOverlay {
                            dismissMentionOverlay(trimMentionQuery: true)
                        } else {
                            openMentionOverlayFromComposer()
                        }
                    }
                } label: {
                    Image(systemName: "at")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(viewModel.showMentionOverlay ? DS.accent : DS.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(viewModel.showMentionOverlay ? DS.accentSoft : DS.glassSectionFill)
                        )
                }
                .buttonStyle(.plain)

                MentionComposerTextView(
                    text: $viewModel.inputText,
                    selection: $viewModel.inputSelectionRange,
                    mentionedAtoms: viewModel.mentionedAtoms,
                    placeholder: "Ask Cosmo anything...",
                    isFocused: $isComposerFocused,
                    isMentionOverlayVisible: viewModel.showMentionOverlay,
                    onSubmit: sendCurrentMessage,
                    onTextChange: { syncMentionSearch() },
                    onDismissMentionOverlayFromBackspace: {
                        dismissMentionOverlay(trimMentionQuery: false)
                    }
                )
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: viewModel.inputText) { syncMentionSearch() }

                modelSelector

                Button {
                    if viewModel.isProcessing {
                        viewModel.cancelCurrentOperation()
                    } else {
                        sendCurrentMessage()
                    }
                } label: {
                    Image(systemName: viewModel.isProcessing ? "stop.fill" : "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(sendButtonForeground)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(sendButtonBackground)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isProcessing && !canSend)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: CosmoWindowMetrics.composerCornerRadius, style: .continuous)
                    .fill(isComposerFocused ? DS.glassInputFillFocused : DS.glassInputFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CosmoWindowMetrics.composerCornerRadius, style: .continuous)
                    .stroke(isComposerFocused ? DS.glassBorderFocused : DS.glassBorder, lineWidth: 1)
            )
            .shadow(color: DS.sidebarMaterialShadow.opacity(0.8), radius: 9, x: 0, y: 3)
        }
        .padding(CosmoWindowMetrics.contentPadding)
        .background(
            LinearGradient(
                colors: [
                    Color.clear,
                    DS.glassSectionFill.opacity(0.32)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        )
    }

    private var agentSelector: some View {
        Button {
            showAgentPicker.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: viewModel.currentAgentIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(viewModel.selectedAgentProfile == nil ? DS.textSecondary : DS.accent)

                Text(viewModel.currentAgentLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: CosmoWindowMetrics.headerAgentLabelMaxWidth, alignment: .leading)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DS.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .cosmoWindowChip(isActive: viewModel.selectedAgentProfile != nil)
        }
        .buttonStyle(.plain)
        .help("Agent")
        .popover(isPresented: $showAgentPicker, arrowEdge: .top) {
            CosmoAgentPickerPopover(
                profiles: viewModel.agentProfiles.filter(\.isEnabled),
                selectedID: viewModel.selectedAgentProfileID,
                onSelect: { profile in
                    viewModel.selectAgentProfile(profile)
                    showAgentPicker = false
                },
                onManage: {
                    showAgentPicker = false
                    showAgentManager = true
                }
            )
        }
        .sheet(isPresented: $showAgentManager) {
            CosmoAgentManagerSheet(
                profiles: viewModel.agentProfiles,
                onSave: { profile in
                    Task { await viewModel.saveAgentProfile(profile) }
                },
                onDelete: { profile in
                    Task { await viewModel.deleteAgentProfile(profile) }
                },
                onClose: {
                    showAgentManager = false
                }
            )
        }
    }

    private var modelSelector: some View {
        Button {
            showModelPicker.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.currentModelLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.textSecondary)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(DS.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .cosmoWindowChip()
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showModelPicker, arrowEdge: .bottom) {
            CosmoModelPickerPopover(
                selectedTier: viewModel.modelOverride,
                onSelect: { tier in
                    viewModel.modelOverride = tier
                    showModelPicker = false
                }
            )
        }
    }

    private var chatHistoryPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chat History")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DS.text)

                    Text("Recent in-app conversations")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                }

                Spacer(minLength: 0)

                Button("New Chat") {
                    Task { await viewModel.startNewChat() }
                    viewModel.showChatHistory = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DS.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .cosmoWindowChip(isActive: true)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.textMuted)

                TextField("Search chats", text: $viewModel.historySearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.text)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DS.glassInputFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DS.glassBorder, lineWidth: 1)
            )

            if viewModel.filteredChatHistoryEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(DS.textMuted)

                    Text(viewModel.historySearchText.isEmpty ? "No past chats yet" : "No matching chats")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.filteredChatHistoryEntries) { entry in
                            chatHistoryRow(entry)
                        }
                    }
                }
                .frame(maxHeight: 340)
            }
        }
        .padding(16)
        .frame(width: 340)
        .cosmoGlassPanel(
            sceneMaterial: .neutral,
            role: .floatingAssistant,
            cornerRadius: 18
        )
        .onAppear {
            viewModel.historySearchText = ""
            Task { await viewModel.loadChatHistory() }
        }
    }

    private func chatHistoryRow(_ entry: ChatHistoryEntry) -> some View {
        Button {
            Task { await viewModel.switchToChat(id: entry.id) }
            viewModel.showChatHistory = false
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(entry.preview)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.text)
                        .lineLimit(2)

                    Spacer(minLength: 0)

                    if entry.isActive {
                        Text("Active")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(DS.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .cosmoWindowChip(isActive: true)
                    }
                }

                HStack(spacing: 8) {
                    Text("\(entry.messageCount) messages")
                    Text("·")
                    Text(entry.lastActivity, style: .relative)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(entry.isActive ? DS.accentSoft.opacity(0.74) : DS.glassCardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(entry.isActive ? DS.accent.opacity(0.18) : DS.glassBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var headerSubtitle: String {
        viewModel.currentHeaderSubtitle
    }

    private var promptSuggestions: [String] {
        viewModel.currentPromptSuggestions
    }

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isProcessing
    }

    private var sendButtonBackground: Color {
        if viewModel.isProcessing {
            return DS.red
        }
        return canSend ? DS.accent : DS.glassBorder
    }

    private var sendButtonForeground: Color {
        if viewModel.isProcessing {
            return DS.textOnAccent
        }
        return canSend ? DS.textOnAccent : DS.textMuted
    }

    private func focusComposer() {
        isComposerFocused = true
        NotificationCenter.default.post(name: .focusCosmoComposer, object: nil)
    }

    private func queuePrompt(_ prompt: String) {
        viewModel.inputText = prompt
        focusComposer()
    }

    private func sendCurrentMessage() {
        let text = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        viewModel.inputText = ""

        if viewModel.showMentionOverlay {
            viewModel.showMentionOverlay = false
            viewModel.mentionSearchText = ""
        }

        if viewModel.pendingEditIndex != nil {
            Task {
                await viewModel.sendEditedMessage(text)
            }
        } else {
            Task {
                await viewModel.sendMessage(text)
            }
        }
    }

    private func headerControlButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.textSecondary)
                .frame(width: CosmoWindowMetrics.controlSize, height: CosmoWindowMetrics.controlSize)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DS.glassSectionFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DS.glassBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func handleAppear() {
        Task {
            await viewModel.loadAgentProfiles()
            await viewModel.loadConversation()
        }
        DispatchQueue.main.async { focusComposer() }
    }

    private func openMentionOverlayFromComposer() {
        if let activeMention = MentionComposerMentionParser.activeMention(
            in: viewModel.inputText,
            selectedRange: viewModel.inputSelectionRange
        ) {
            viewModel.mentionSearchText = activeMention.query
        } else {
            let replacement = MentionComposerMentionParser.insertingMentionTrigger(
                in: viewModel.inputText,
                selectedRange: viewModel.inputSelectionRange
            )
            viewModel.inputText = replacement.text
            viewModel.inputSelectionRange = replacement.selection
            viewModel.mentionSearchText = ""
        }
        viewModel.showMentionOverlay = true
        focusComposer()
    }

    private func dismissMentionOverlay(trimMentionQuery: Bool) {
        if trimMentionQuery,
           let replacement = MentionComposerMentionParser.removingActiveMention(
                in: viewModel.inputText,
                selectedRange: viewModel.inputSelectionRange
           ) {
            viewModel.inputText = replacement.text
            viewModel.inputSelectionRange = replacement.selection
        }
        viewModel.showMentionOverlay = false
        viewModel.mentionSearchText = ""
    }

    private func syncMentionSearch() {
        guard let activeMention = MentionComposerMentionParser.activeMention(
            in: viewModel.inputText,
            selectedRange: viewModel.inputSelectionRange
        ) else {
            if viewModel.showMentionOverlay {
                dismissMentionOverlay(trimMentionQuery: false)
            }
            return
        }

        if isCompletedInsertedMention(activeMention) {
            if viewModel.showMentionOverlay {
                dismissMentionOverlay(trimMentionQuery: false)
            }
            return
        }

        if !viewModel.showMentionOverlay {
            withAnimation(ProMotionSprings.snappy) {
                viewModel.showMentionOverlay = true
            }
        }

        viewModel.mentionSearchText = activeMention.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func insertMention(_ atom: Atom) {
        viewModel.addMention(atom)
        let replacement = MentionComposerMentionParser.replacingActiveMention(
            in: viewModel.inputText,
            selectedRange: viewModel.inputSelectionRange,
            title: atom.title ?? "Untitled"
        )
        viewModel.inputText = replacement.text
        viewModel.inputSelectionRange = replacement.selection
        focusComposer()
    }

    private func isCompletedInsertedMention(_ activeMention: MentionComposerActiveMention) -> Bool {
        viewModel.mentionedAtoms.contains { atom in
            let title = atom.title ?? "Untitled"
            return activeMention.query == title
                || activeMention.query.hasPrefix("\(title) ")
                || activeMention.query.hasPrefix("\(title)\t")
        }
    }

    private func debouncedScrollToBottom(proxy: ScrollViewProxy) {
        pendingScrollWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            withAnimation(ProMotionSprings.snappy) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }
        pendingScrollWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }
}

enum CosmoWindowMetrics {
    static let defaultWidth: CGFloat = 440
    static let defaultHeight: CGFloat = 520
    static let minWidth: CGFloat = 380
    static let minHeight: CGFloat = 400
    static let maxWidth: CGFloat = 620
    static let maxHeight: CGFloat = 700

    static let panelCornerRadius: CGFloat = 20
    static let headerHeight: CGFloat = 56
    static let contentPadding: CGFloat = 18
    static let messageSpacing: CGFloat = 12
    static let controlSize: CGFloat = 32
    static let headerAgentLabelMaxWidth: CGFloat = 88
    static let cardCornerRadius: CGFloat = 14
    static let composerCornerRadius: CGFloat = 16
    static let maxMessageWidth: CGFloat = 332
    static let readyStateMaxWidth: CGFloat = 358
    static let minimumMessageStageHeight: CGFloat = 180
    static let mentionOverlayMaxHeight: CGFloat = 320
    static let collaboratorMentionOverlayBottomPadding: CGFloat = 104
}

enum CosmoWindowLayoutPolicy {
    static func readableTranscriptHeight(
        availableHeight: CGFloat,
        headerHeight: CGFloat,
        composerHeight: CGFloat,
        dividerHeight: CGFloat
    ) -> CGFloat {
        let remainingHeight = availableHeight - headerHeight - composerHeight - dividerHeight
        return max(CosmoWindowMetrics.minimumMessageStageHeight, remainingHeight)
    }
}

struct CosmoWindowSectionChromeModifier: ViewModifier {
    let cornerRadius: CGFloat
    let shadow: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DS.glassCardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DS.glassBorder, lineWidth: 1)
            )
            .modifier(CosmoWindowConditionalShadowModifier(enabled: shadow))
    }
}

struct CosmoWindowConditionalShadowModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.dsRestingShadow()
        } else {
            content
        }
    }
}

struct CosmoWindowChipModifier: ViewModifier {
    let isActive: Bool
    let activeFill: Color
    let activeBorder: Color

    func body(content: Content) -> some View {
        content
            .background(
                Capsule()
                    .fill(isActive ? activeFill : DS.glassSectionFill)
            )
            .overlay(
                Capsule()
                    .stroke(isActive ? activeBorder : DS.glassBorder, lineWidth: 1)
            )
    }
}

struct CosmoWindowGroupChromeModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DS.glassSectionFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DS.glassBorder, lineWidth: 1)
            )
    }
}

private struct CosmoCanvasPlanReviewCard: View {
    let plan: PendingCanvasPlan
    let onApply: () -> Void
    let onRevise: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.accent)
                    .frame(width: 32, height: 32)
                    .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.text)
                        .lineLimit(1)

                    Text("\(plan.affectedObjectCount) proposed operations")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.textSecondary)
                }

                Spacer(minLength: 0)
            }

            Text(plan.rationale)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(plan.operations.prefix(5)) { operation in
                    HStack(spacing: 8) {
                        Text(operation.kind.displayName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .cosmoWindowChip(isActive: true)

                        Text(operation.summary)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.text)
                            .lineLimit(1)
                    }
                }

                if plan.operations.count > 5 {
                    Text("+ \(plan.operations.count - 5) more")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.textMuted)
                }
            }

            HStack(spacing: 8) {
                Button("Apply", action: onApply)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.textOnAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(DS.accent, in: Capsule())

                Button("Revise", action: onRevise)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .cosmoWindowChip(isActive: true)

                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .cosmoWindowChip()

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .cosmoWindowSectionChrome(cornerRadius: 16)
    }
}

private struct CosmoAgentPickerPopover: View {
    let profiles: [CustomAgentProfile]
    let selectedID: String?
    let onSelect: (CustomAgentProfile?) -> Void
    let onManage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agent")
                .dsSmallCapsLabel()
                .padding(.horizontal, 4)

            agentRow(nil)

            ForEach(profiles) { profile in
                agentRow(profile)
            }

            Divider()

            Button(action: onManage) {
                Label("Manage Agents", systemImage: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 292)
        .cosmoGlassPanel(sceneMaterial: .neutral, role: .floatingAssistant, cornerRadius: 16)
    }

    private func agentRow(_ profile: CustomAgentProfile?) -> some View {
        let isSelected = profile?.id == selectedID || (profile == nil && selectedID == nil)
        let icon = profile?.icon ?? "sparkles"
        let title = profile?.name ?? "Auto Cosmo"
        let subtitle = profile?.summary ?? "Let Cosmo choose the prompt, tools, and model"

        return Button {
            onSelect(profile)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? DS.accent : DS.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(isSelected ? DS.accentSoft : DS.glassSectionFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.text)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isSelected ? DS.accentSoft.opacity(0.68) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct CosmoAgentManagerSheet: View {
    let profiles: [CustomAgentProfile]
    let onSave: (CustomAgentProfile) -> Void
    let onDelete: (CustomAgentProfile) -> Void
    let onClose: () -> Void

    @State private var draft: CustomAgentProfile

    init(
        profiles: [CustomAgentProfile],
        onSave: @escaping (CustomAgentProfile) -> Void,
        onDelete: @escaping (CustomAgentProfile) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.profiles = profiles
        self.onSave = onSave
        self.onDelete = onDelete
        self.onClose = onClose
        _draft = State(initialValue: profiles.first ?? .blankCustom)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Custom Agents")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DS.text)
                    Text("Prompts, tools, context scopes, and model preference")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.textSecondary)
                }
                Spacer(minLength: 0)
                Button("Done", action: onClose)
                    .buttonStyle(.borderedProminent)
            }
            .padding(18)

            Divider()

            HStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        Button {
                            draft = .blankCustom
                        } label: {
                            Label("New Agent", systemImage: "plus")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .cosmoWindowChip(isActive: true)
                        }
                        .buttonStyle(.plain)

                        ForEach(profiles) { profile in
                            Button {
                                draft = profile
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: profile.icon)
                                    Text(profile.name).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(draft.id == profile.id ? DS.accent : DS.text)
                                .padding(10)
                                .background(draft.id == profile.id ? DS.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                }
                .frame(width: 190)

                Divider()

                agentEditor
                    .padding(18)
            }
        }
        .frame(width: 760, height: 560)
        .background(DS.surface)
    }

    private var agentEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    TextField("Name", text: $draft.name)
                    TextField("SF Symbol", text: $draft.icon)
                        .frame(width: 130)
                }
                .textFieldStyle(.roundedBorder)

                TextField("Summary", text: $draft.summary)
                    .textFieldStyle(.roundedBorder)

                Picker("Model", selection: Binding(
                    get: { draft.preferredModelTier?.rawValue ?? "auto" },
                    set: { draft.preferredModelTier = $0 == "auto" ? nil : AgentModelTier(rawValue: $0) }
                )) {
                    Text("Auto").tag("auto")
                    Text("Haiku").tag(AgentModelTier.sensor.rawValue)
                    Text("Sonnet").tag(AgentModelTier.strategist.rawValue)
                    Text("Opus").tag(AgentModelTier.writer.rawValue)
                }
                .pickerStyle(.segmented)

                Text("Prompt")
                    .dsSmallCapsLabel()
                TextEditor(text: $draft.runtimePrompt)
                    .font(.system(size: 12))
                    .frame(minHeight: 140)
                    .padding(8)
                    .background(DS.glassInputFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                suggestedPromptEditor

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Access")
                            .dsSmallCapsLabel()
                        Text("Hover a chip to see exactly what it unlocks")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.textMuted)
                    }

                    Spacer(minLength: 0)

                    Button {
                        draft.toolBundles = AgentToolBundle.allCases
                        draft.contextScopes = CustomAgentContextScope.allCases
                    } label: {
                        Label("Full Access", systemImage: "checkmark.seal")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .cosmoWindowChip(isActive: hasFullAccess)
                    .help("Enable every tool bundle and every context scope for this agent.")
                }

                toggleGrid(title: "Tools", items: AgentToolBundle.allCases, selection: $draft.toolBundles)
                toggleGrid(title: "Context", items: CustomAgentContextScope.allCases, selection: $draft.contextScopes)

                HStack {
                    Toggle("Enabled", isOn: $draft.isEnabled)
                    Spacer(minLength: 0)
                    if !draft.isBuiltin {
                        Button("Delete") { onDelete(draft) }
                            .foregroundStyle(DS.red)
                    }
                    Button("Save") { onSave(draft) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var hasFullAccess: Bool {
        Set(draft.toolBundles) == Set(AgentToolBundle.allCases)
            && Set(draft.contextScopes) == Set(CustomAgentContextScope.allCases)
    }

    private var suggestedPromptEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Suggested Prompts")
                    .dsSmallCapsLabel()
                Spacer(minLength: 0)
                Text("Shown in the ready state")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.textMuted)
            }

            VStack(spacing: 8) {
                promptField(index: 0, placeholder: "First suggestion")
                promptField(index: 1, placeholder: "Second suggestion")
                promptField(index: 2, placeholder: "Third suggestion")
            }
        }
    }

    private func promptField(index: Int, placeholder: String) -> some View {
        TextField(placeholder, text: promptBinding(index: index))
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(DS.glassInputFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DS.glassBorder, lineWidth: 1)
            )
    }

    private func promptBinding(index: Int) -> Binding<String> {
        Binding(
            get: {
                guard draft.seedPrompts.indices.contains(index) else { return "" }
                return draft.seedPrompts[index]
            },
            set: { newValue in
                while draft.seedPrompts.count <= index {
                    draft.seedPrompts.append("")
                }
                draft.seedPrompts[index] = newValue
            }
        )
    }

    private func toggleGrid<T: Identifiable & Hashable>(
        title: String,
        items: [T],
        selection: Binding<[T]>
    ) -> some View where T.ID == String {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).dsSmallCapsLabel()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], spacing: 8) {
                ForEach(items) { item in
                    let isOn = selection.wrappedValue.contains(item)
                    Button {
                        if isOn {
                            selection.wrappedValue.removeAll { $0 == item }
                        } else {
                            selection.wrappedValue.append(item)
                        }
                    } label: {
                        Text(displayName(for: item))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isOn ? DS.accent : DS.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .cosmoWindowChip(isActive: isOn)
                    }
                    .buttonStyle(.plain)
                    .help(accessDescription(for: item))
                }
            }
        }
    }

    private func displayName<T>(for item: T) -> String {
        if let item = item as? AgentToolBundle { return item.displayName }
        if let item = item as? CustomAgentContextScope { return item.displayName }
        return String(describing: item)
    }

    private func accessDescription<T>(for item: T) -> String {
        if let item = item as? AgentToolBundle { return item.accessDescription }
        if let item = item as? CustomAgentContextScope { return item.accessDescription }
        return ""
    }
}

private struct CosmoModelPickerPopover: View {
    let selectedTier: AgentModelTier?
    let onSelect: (AgentModelTier?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model")
                .dsSmallCapsLabel()
                .padding(.horizontal, 4)

            VStack(spacing: 4) {
                ForEach(CosmoModelOption.all) { option in
                    modelRow(option)
                }
            }
        }
        .padding(12)
        .frame(width: 268)
        .cosmoGlassPanel(
            sceneMaterial: .neutral,
            role: .floatingAssistant,
            cornerRadius: 16
        )
    }

    private func modelRow(_ option: CosmoModelOption) -> some View {
        let isSelected = option.tier?.rawValue == selectedTier?.rawValue || (option.tier == nil && selectedTier == nil)

        return Button {
            onSelect(option.tier)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: option.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? DS.accent : DS.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(isSelected ? DS.accentSoft : DS.glassSectionFill)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.text)
                        .lineLimit(1)

                    Text(option.detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? DS.accentSoft.opacity(0.68) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? DS.accent.opacity(0.16) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension View {
    func cosmoWindowSectionChrome(
        cornerRadius: CGFloat = CosmoWindowMetrics.cardCornerRadius,
        shadow: Bool = true
    ) -> some View {
        modifier(CosmoWindowSectionChromeModifier(cornerRadius: cornerRadius, shadow: shadow))
    }

    func cosmoWindowChip(
        isActive: Bool = false,
        activeFill: Color = DS.accentSoft,
        activeBorder: Color = DS.accent.opacity(0.18)
    ) -> some View {
        modifier(
            CosmoWindowChipModifier(
                isActive: isActive,
                activeFill: activeFill,
                activeBorder: activeBorder
            )
        )
    }

    func cosmoWindowGroupChrome(cornerRadius: CGFloat = 14) -> some View {
        modifier(CosmoWindowGroupChromeModifier(cornerRadius: cornerRadius))
    }
}

private struct ProcessingStatusPill: View {
    let startedAt: Date?
    let label: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 8) {
                Circle()
                    .fill(DS.accent)
                    .frame(width: 8, height: 8)

                Text(label)
                    .lineLimit(1)

                if let elapsedText = elapsedText {
                    Text(elapsedText)
                        .foregroundColor(DS.textMuted)
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(DS.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .cosmoWindowChip(isActive: true)
        }
    }

    private var elapsedText: String? {
        guard let startedAt else { return nil }
        let elapsed = max(0, Int(Date().timeIntervalSince(startedAt)))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%01d:%02d", minutes, seconds)
    }
}

private struct CosmoThinkingCard: View {
    let activeLabel: String
    let startedAt: Date?
    let groups: [ToolActivityGroup]
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cosmo is working")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DS.text)

                    Text("Live context and tool activity")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                }

                Spacer(minLength: 0)

                ProcessingStatusPill(startedAt: startedAt, label: activeLabel)

                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .cosmoWindowChip(activeFill: DS.redSoft, activeBorder: DS.red.opacity(0.18))
            }

            ToolActivityStreamView(groups: groups, activeLabel: activeLabel)
        }
        .padding(14)
        .cosmoWindowSectionChrome(cornerRadius: 16)
    }
}

/// Compact inline context bar — shows the active focus mode context
/// without eating vertical space. No nested card chrome.
private struct CosmoContextBar: View {
    let context: CosmoActiveContext

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: context.type.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 26, height: 26)
                .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(context.type.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                if let title = context.data.currentAtomTitle, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if let count = context.data.visibleItemCount {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .cosmoWindowChip()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.glassSectionFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.glassBorder, lineWidth: 1)
        )
    }
}

private struct CosmoEmptyStateCard: View {
    let context: CosmoActiveContext
    let isCollaboratorMode: Bool
    let suggestions: [String]
    let onSelectSuggestion: (String) -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(DS.accentSoft)
                    .frame(width: 58, height: 58)
                    .overlay(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(DS.accent.opacity(0.12), lineWidth: 1)
                    )

                Image(systemName: context.type == .none ? "sparkles" : context.type.icon)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundColor(DS.accent)
            }

            VStack(spacing: 7) {
                Text(headlineText)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(DS.text)
                    .multilineTextAlignment(.center)

                Text(descriptionText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FlowSuggestionsView(items: suggestions, onSelect: onSelectSuggestion)

            if !isCollaboratorMode {
                HStack(spacing: 10) {
                    Text("Option+A")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(DS.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                            .cosmoWindowChip(isActive: true)

                    Text("Opens Cosmo from anywhere")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, CosmoWindowMetrics.contentPadding)
    }

    private var headlineText: String {
        if isCollaboratorMode {
            return "Whenever you have a thought"
        }
        return context.type == .none ? "Ask Cosmo anything" : "Ready with your current context"
    }

    private var descriptionText: String {
        if isCollaboratorMode {
            return "It can be messy. One sentence, a link, a half-formed question. Doesn't matter."
        }

        if context.type == .none {
            return "Cosmo can help you think, summarize, plan, and write. Add @ references or just start typing."
        }

        if let current = context.data.currentAtomTitle, !current.isEmpty {
            return "Cosmo already sees \(current) and the surrounding workspace, so you can jump straight into the work."
        }

        return "Cosmo is reading your active workspace and can use that context immediately."
    }
}

private struct FlowSuggestionsView: View {
    let items: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try asking")
                .dsSmallCapsLabel()
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Button(item) {
                        onSelect(item)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DS.glassInputFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(DS.glassBorder, lineWidth: 1)
                    )
                }
            }
        }
    }
}

struct FlexibleFactRow: View {
    let items: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DS.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .cosmoWindowChip()
            }
        }
    }
}

#if DEBUG
struct CosmoWindowView_Previews: PreviewProvider {
    struct PreviewWrapper: View {
        @State private var isVisible = true

        var body: some View {
            ZStack {
                DS.bg.ignoresSafeArea()

                if isVisible {
                    CosmoWindowView(isVisible: $isVisible)
                        .frame(width: CosmoWindowMetrics.defaultWidth, height: CosmoWindowMetrics.defaultHeight)
                        .padding(30)
                }
            }
        }
    }

    static var previews: some View {
        PreviewWrapper()
            .frame(width: 1200, height: 900)
    }
}
#endif
