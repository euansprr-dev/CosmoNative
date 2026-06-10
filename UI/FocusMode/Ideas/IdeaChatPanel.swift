// CosmoOS/UI/FocusMode/Ideas/IdeaChatPanel.swift
// Chat interface for brainstorm conversations.
// Premium redesign — April 2026

import SwiftUI

struct IdeaChatPanel: View {
    @Binding var messages: [IdeaChatMessage]
    let ideaContext: String

    @State private var inputText = ""
    @State private var isLoading = false
    @FocusState private var isInputFocused: Bool

    private let ideaGold = DS.entityIdea

    var body: some View {
        VStack(spacing: 0) {
            messageList
            chatDivider
            inputBar
        }
        .background(DS.bg.opacity(0.5), in: .rect(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(DS.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if messages.isEmpty {
                        emptyState
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        messageBubble(message, index: index)
                            .id(message.id)
                    }
                    if isLoading {
                        typingIndicator
                    }
                }
                .padding(12)
            }
            .scrollIndicators(.hidden)
            .onChange(of: messages.count) {
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Message Bubble

    @ViewBuilder
    private func messageBubble(_ message: IdeaChatMessage, index: Int) -> some View {
        if message.role == "user" {
            userBubble(message.content, index: index)
        } else {
            assistantBubble(message, index: index)
        }
    }

    private func userBubble(_ content: String, index: Int) -> some View {
        HStack {
            Spacer(minLength: 40)
            Text(content)
                .font(DS.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(ideaGold, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func assistantBubble(_ message: IdeaChatMessage, index: Int) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(message.content)
                    .font(DS.caption)
                    .foregroundStyle(DS.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 14))

                if let cards = message.actionCards, !cards.isEmpty {
                    actionCardsRow(cards)
                }
            }
            Spacer(minLength: 40)
        }
    }

    private func actionCardsRow(_ cards: [ChatActionCard]) -> some View {
        CodexFlowLayout(spacing: 6) {
            ForEach(cards) { card in
                actionCardButton(card)
            }
        }
        .padding(.leading, 4)
    }

    private func actionCardButton(_ card: ChatActionCard) -> some View {
        Button {
            // Action cards will be wired up in a future iteration
        } label: {
            HStack(spacing: 4) {
                Image(systemName: iconForCardType(card.type))
                    .font(.system(size: 9))
                    .accessibilityHidden(true)
                Text(card.title)
                    .font(DS.caption2)
            }
            .foregroundStyle(ideaGold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(ideaGold.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(ideaGold.opacity(0.2), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Divider

    private var chatDivider: some View {
        Rectangle()
            .fill(ideaGold.opacity(0.1))
            .frame(height: 1)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask about this idea...", text: $inputText)
                .font(DS.caption)
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                .onSubmit { sendMessage() }

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(canSend ? ideaGold : DS.textMuted)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Empty & Loading States

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 20))
                .foregroundStyle(ideaGold.opacity(0.3))
                .accessibilityHidden(true)
            Text("Chat about your idea")
                .font(DS.caption)
                .fontWeight(.medium)
                .foregroundStyle(DS.textSecondary)
            Text("Ask for hook ideas, angles, proof strategies, or audience insights")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var typingIndicator: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(ideaGold.opacity(0.4))
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 14))
            Spacer()
        }
    }

    // MARK: - Actions

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }

        let userMessage = IdeaChatMessage(
            id: UUID(),
            role: "user",
            content: text,
            timestamp: ISO8601.string(from: Date()),
            actionCards: nil
        )
        messages.append(userMessage)
        inputText = ""

        Task {
            isLoading = true
            do {
                let response = try await IdeaChatAgent.shared.chat(
                    message: text,
                    ideaContext: ideaContext,
                    history: messages
                )
                messages.append(response)
            } catch {
                let errorMessage = IdeaChatMessage(
                    id: UUID(),
                    role: "assistant",
                    content: "Something went wrong: \(error.localizedDescription)",
                    timestamp: ISO8601.string(from: Date()),
                    actionCards: nil
                )
                messages.append(errorMessage)
            }
            isLoading = false
        }
    }

    // MARK: - Helpers

    private func iconForCardType(_ type: String) -> String {
        switch type.lowercased() {
        case "swipe": return "doc.on.doc"
        case "codex": return "book"
        case "link": return "link"
        case "idea": return "lightbulb"
        default: return "sparkles"
        }
    }
}
