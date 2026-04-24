import SwiftUI

struct CosmoCollaboratorPaneView: View {
    let target: CollaborationTarget
    let presetId: String?
    let onClose: () -> Void

    @ObservedObject private var viewModel = CosmoWindowViewModel.shared
    @State private var isComposerFocused = false
    @State private var bottomAnchorID = "collaborator-bottom"

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            transcript
            divider
            composer
        }
        .background(DS.bg)
        .task(id: taskKey) {
            await viewModel.activateCollaborator(target: target, presetID: presetId)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            HStack(alignment: .top, spacing: DS.space8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("COSMO / \(viewModel.collaboratorPreset?.name.lowercased() ?? "deepen")")
                        .font(DS.smallCaps)
                        .foregroundStyle(DS.gilt)

                    Text(target.title)
                        .font(.system(size: 28, weight: .light, design: .serif))
                        .foregroundStyle(DS.text)
                        .lineLimit(2)

                    Text(target.displayTypeLabel.lowercased())
                        .font(DS.dateSerif)
                        .italic()
                        .foregroundStyle(DS.inkFaded)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    if let label = viewModel.activeToolLabel, viewModel.isProcessing {
                        Text(label.lowercased())
                            .font(DS.dateSerif)
                            .italic()
                            .foregroundStyle(DS.inkFaded)
                    }

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.textMuted)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: DS.space10) {
                Text("DEVELOPING")
                    .font(DS.smallCaps)
                    .foregroundStyle(DS.gilt)

                if !viewModel.activeContext.actions.isEmpty {
                    actionRow
                }
            }
        }
        .padding(.horizontal, DS.space16)
        .padding(.top, DS.space16)
        .padding(.bottom, DS.space12)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space16) {
                    if viewModel.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.messages) { message in
                            messageRow(message)
                        }
                    }

                    if viewModel.isProcessing {
                        Text("thinking...")
                            .font(DS.dateSerif)
                            .italic()
                            .foregroundStyle(DS.inkFaded)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.space16)
                .padding(.vertical, DS.space16)
            }
            .background(DS.bg)
            .onChange(of: viewModel.messages.count) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.isProcessing) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.toolActivityScrollTick) { _ in
                scrollToBottom(proxy)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Text("It can be messy. One sentence, a link, a half-formed question. Doesn't matter.")
                .font(DS.dateSerif)
                .italic()
                .foregroundStyle(DS.inkFaded)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: DS.space8) {
                ForEach(viewModel.currentPromptSuggestions, id: \.self) { prompt in
                    Button {
                        viewModel.inputText = prompt
                        focusComposer()
                    } label: {
                        Text(prompt)
                            .font(DS.dateSerif)
                            .italic()
                            .foregroundStyle(DS.inkFaded)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func messageRow(_ message: CosmoWindowMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch message.type {
            case .user:
                labelRow("EUAN")
                Text(message.content)
                    .font(DS.body)
                    .foregroundStyle(DS.text)
            case .assistant:
                labelRow("COSMO")
                Text(message.content)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(DS.text)
            case .system:
                Text(message.content)
                    .font(DS.dateSerif)
                    .italic()
                    .foregroundStyle(DS.inkFaded)
            case .actionButtons(let buttons):
                labelRow("COSMO")
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.system(size: 16, weight: .regular, design: .serif))
                        .foregroundStyle(DS.text)
                }
                HStack(spacing: 8) {
                    ForEach(buttons, id: \.label) { button in
                        Text(button.label)
                            .font(DS.caption)
                            .foregroundStyle(DS.inkFaded)
                    }
                }
            case .toolResult(_, let summary, let isError):
                Text(summary)
                    .font(DS.dateSerif)
                    .italic()
                    .foregroundStyle(isError ? DS.red : DS.inkFaded)
            case .contextTrace, .contextChange:
                EmptyView()
            }

            divider.opacity(message.type.isDividerVisible ? 1 : 0)
        }
    }

    private func labelRow(_ text: String) -> some View {
        Text(text)
            .font(DS.smallCaps)
            .foregroundStyle(DS.gilt)
    }

    private var actionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(viewModel.activeContext.actions.prefix(3))) { action in
                    Button {
                        let prompt = viewModel.inputText
                        Task {
                            await viewModel.performAction(action, prompt: prompt)
                            if !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                viewModel.inputText = ""
                            }
                        }
                    } label: {
                        Text(action.name)
                            .font(DS.caption)
                            .foregroundStyle(DS.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(DS.vellum, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: DS.space8) {
            if viewModel.showMentionOverlay {
                CosmoMentionOverlay(
                    isVisible: $viewModel.showMentionOverlay,
                    searchText: $viewModel.mentionSearchText,
                    onSelect: { atom in
                        viewModel.addMention(atom)
                        if let atIndex = viewModel.inputText.lastIndex(of: "@") {
                            let beforeAt = String(viewModel.inputText[viewModel.inputText.startIndex..<atIndex])
                            let title = atom.title ?? "Untitled"
                            viewModel.inputText = beforeAt + "@\(title) "
                        }
                    },
                    onDismiss: {
                        dismissMentionOverlay(trimMentionQuery: true)
                    }
                )
                .transition(.opacity)
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    openMentionOverlayFromComposer()
                } label: {
                    Text("@")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(viewModel.showMentionOverlay ? DS.gilt : DS.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(DS.vellum, in: Circle())
                }
                .buttonStyle(.plain)

                MentionComposerTextView(
                    text: $viewModel.inputText,
                    mentionedAtoms: viewModel.mentionedAtoms,
                    placeholder: "It can be messy. One sentence, a link, a half-formed question.",
                    isFocused: $isComposerFocused,
                    onSubmit: sendCurrentMessage,
                    onTextChange: { syncMentionSearch() }
                )
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: viewModel.inputText) { syncMentionSearch() }

                Button(action: sendOrStop) {
                    Image(systemName: viewModel.isProcessing ? "stop.fill" : "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(viewModel.isProcessing ? DS.textOnAccent : DS.textOnAccent)
                        .frame(width: 30, height: 30)
                        .background(viewModel.isProcessing ? DS.red : DS.gilt, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isProcessing && !canSend)
            }
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.vellum)
            )
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space16)
        .background(DS.bg)
    }

    private var divider: some View {
        Rectangle()
            .fill(DS.borderSubtle)
            .frame(height: 1)
    }

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isProcessing
    }

    private var taskKey: String {
        "\(target.atomUUID)::\(presetId ?? "deepen")"
    }

    private func focusComposer() {
        isComposerFocused = true
        NotificationCenter.default.post(name: .focusCosmoComposer, object: nil)
    }

    private func sendOrStop() {
        if viewModel.isProcessing {
            viewModel.cancelCurrentOperation()
        } else {
            sendCurrentMessage()
        }
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
            Task { await viewModel.sendEditedMessage(text) }
        } else {
            Task { await viewModel.sendMessage(text) }
        }
    }

    private func openMentionOverlayFromComposer() {
        if viewModel.inputText.lastIndex(of: "@") == nil {
            if !viewModel.inputText.isEmpty && !viewModel.inputText.hasSuffix(" ") {
                viewModel.inputText += " "
            }
            viewModel.inputText += "@"
        }
        viewModel.mentionSearchText = ""
        viewModel.showMentionOverlay = true
        focusComposer()
    }

    private func dismissMentionOverlay(trimMentionQuery: Bool) {
        if trimMentionQuery, let atIndex = viewModel.inputText.lastIndex(of: "@") {
            viewModel.inputText = String(viewModel.inputText[..<atIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        viewModel.showMentionOverlay = false
        viewModel.mentionSearchText = ""
    }

    private func syncMentionSearch() {
        if viewModel.inputText.hasSuffix("@") && !viewModel.showMentionOverlay {
            withAnimation(ProMotionSprings.snappy) {
                viewModel.showMentionOverlay = true
                viewModel.mentionSearchText = ""
            }
        }

        guard viewModel.showMentionOverlay else { return }

        guard let atIndex = viewModel.inputText.lastIndex(of: "@") else {
            dismissMentionOverlay(trimMentionQuery: false)
            return
        }

        let afterAt = String(viewModel.inputText[viewModel.inputText.index(after: atIndex)...])
        viewModel.mentionSearchText = afterAt
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(ProMotionSprings.snappy) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }
    }
}

private extension CosmoWindowMessageType {
    var isDividerVisible: Bool {
        switch self {
        case .contextTrace, .contextChange:
            return false
        default:
            return true
        }
    }
}
