// CosmoOS/UI/FocusMode/CosmoAI/CosmoAIConversationPanel.swift
// Message list component for Cosmo AI Focus Mode
// Displays conversation history with mode-aware bubbles, source cards, recall results, and actions

import SwiftUI

struct CosmoAIConversationPanel: View {
    @ObservedObject var viewModel: CosmoAIFocusModeViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        CosmoAIMessageBubble(message: message)
                            .id(message.id)
                    }

                    if viewModel.isGenerating {
                        TypingIndicator()
                    }
                }
                .padding(20)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastId = viewModel.messages.last?.id {
                    withAnimation(.spring(response: 0.3)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Message Bubble

private struct CosmoAIMessageBubble: View {
    let message: CosmoAIFocusModeViewModel.AIMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                ZStack {
                    Circle()
                        .fill(message.mode.color.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: message.mode.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(message.mode.color)
                }
            }

            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // Mode badge
                if message.role == .assistant {
                    HStack(spacing: 4) {
                        Text(message.mode.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(message.mode.color)
                        Text("\u{2022}")
                            .foregroundColor(.white.opacity(0.2))
                        Text(message.timestamp, style: .time)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }

                // Message content
                Text(message.content)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.9))
                    .textSelection(.enabled)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(message.role == .user
                                ? CosmoColors.thinkspacePurple.opacity(0.2)
                                : CosmoColors.thinkspaceSecondary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )

                // Research sources
                if let sources = message.sources, !sources.isEmpty {
                    SourceCards(sources: sources)
                }

                // Recall results
                if let results = message.recallResults, !results.isEmpty {
                    RecallCards(results: results)
                }

                // Action results
                if let actions = message.actionResults, !actions.isEmpty {
                    ActionCards(actions: actions)
                }

                // Action buttons for assistant messages
                if message.role == .assistant {
                    MessageActions(content: message.content)
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 60)
            }

            if message.role == .user {
                ZStack {
                    Circle()
                        .fill(CosmoColors.thinkspacePurple.opacity(0.2))
                        .frame(width: 28, height: 28)
                    Image(systemName: "person.fill")
                        .font(.system(size: 12))
                        .foregroundColor(CosmoColors.thinkspacePurple)
                }
            }
        }
    }
}

// MARK: - Source Cards

private struct SourceCards: View {
    let sources: [ResearchFinding]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sources")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))

            ForEach(Array(sources.prefix(3).enumerated()), id: \.offset) { _, source in
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 10))
                        .foregroundColor(CosmoMentionColors.research)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.source)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                        Text(source.title)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(CosmoColors.thinkspaceTertiary))
            }
        }
    }
}

// MARK: - Recall Cards

private struct RecallCards: View {
    let results: [RecallResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Related Knowledge")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))

            ForEach(results.prefix(5)) { result in
                let entityType = EntityType(rawValue: result.atom.type.rawValue) ?? .idea
                HStack(spacing: 8) {
                    Circle()
                        .fill(mentionColor(for: entityType))
                        .frame(width: 6, height: 6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.atom.title ?? "Untitled")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                        if let body = result.atom.body {
                            Text(body.prefix(80))
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if let sim = result.similarity {
                        Text("\(Int(sim * 100))%")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(CosmoColors.thinkspaceTertiary))
                .onTapGesture {
                    NotificationCenter.default.post(
                        name: .enterFocusMode,
                        object: nil,
                        userInfo: ["type": entityType, "id": result.atom.id ?? Int64(0)]
                    )
                }
            }
        }
    }

    private func mentionColor(for type: EntityType) -> Color {
        switch type {
        case .idea: return CosmoMentionColors.idea
        case .content: return CosmoMentionColors.content
        case .research: return CosmoMentionColors.research
        case .connection: return CosmoMentionColors.connection
        case .cosmoAI: return CosmoMentionColors.cosmoAI
        case .task: return CosmoMentionColors.task
        case .note: return CosmoMentionColors.note
        default: return .white
        }
    }
}

// MARK: - Action Cards

private struct ActionCards: View {
    let actions: [ActionResult]

    var body: some View {
        ForEach(actions) { action in
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(CosmoColors.emerald)

                Text(action.description)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))

                Spacer()
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(CosmoColors.emerald.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CosmoColors.emerald.opacity(0.2), lineWidth: 1))
        }
    }
}

// MARK: - Message Actions

private struct MessageActions: View {
    let content: String

    var body: some View {
        HStack(spacing: 12) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(content, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)

            Button {
                Task {
                    try? await AtomRepository.shared.create(type: .idea, title: "AI Note", body: content)
                }
            } label: {
                Label("Save as Note", systemImage: "square.and.arrow.down")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Typing Indicator

private struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(CosmoColors.lavender.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: "brain")
                    .font(.system(size: 12))
                    .foregroundColor(CosmoColors.lavender)
            }

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(CosmoColors.lavender)
                        .frame(width: 6, height: 6)
                        .opacity(animating ? 1 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.15),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(CosmoColors.thinkspaceSecondary))

            Spacer()
        }
        .onAppear { animating = true }
    }
}
