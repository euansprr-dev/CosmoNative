// CosmoOS/Cosmo/CosmoChatView.swift
// Beautiful AI chat interface with entity cards and streaming
// Apple-level quality, matches iMessage/ChatGPT aesthetics

import SwiftUI

struct CosmoChatView: View {
    @StateObject private var cosmo = CosmoCore.shared
    @State private var inputText = ""
    @State private var isExpanded = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ChatHeader(
                isResearching: cosmo.isResearching,
                researchProgress: cosmo.researchProgress,
                onClear: { cosmo.clearConversation() }
            )

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(cosmo.messages) { message in
                            ChatMessageView(message: message)
                                .id(message.id)
                        }

                        // Processing indicator
                        if cosmo.isProcessing {
                            ProcessingIndicator()
                                .id("processing")
                        }
                    }
                    .padding()
                }
                .onChange(of: cosmo.messages.count) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        if let lastMessage = cosmo.messages.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        } else {
                            proxy.scrollTo("processing", anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input
            ChatInputBar(
                text: $inputText,
                isProcessing: cosmo.isProcessing,
                isFocused: $isInputFocused,
                onSend: sendMessage
            )
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func sendMessage() {
        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        inputText = ""

        Task {
            _ = await cosmo.process(message)
        }
    }
}

// MARK: - Chat Header
struct ChatHeader: View {
    let isResearching: Bool
    let researchProgress: Double
    let onClear: () -> Void

    var body: some View {
        HStack {
            // Cosmo avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)

                Image(systemName: "brain.head.profile")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Cosmo")
                    .font(.system(size: 16, weight: .semibold))

                if isResearching {
                    HStack(spacing: 4) {
                        ProgressView(value: researchProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 60)

                        Text("Researching...")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Your AI assistant")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Research indicator
            if isResearching {
                Image(systemName: "globe")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
                    .symbolEffect(.pulse.byLayer)
            }

            // Clear button
            Button(action: onClear) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear conversation")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Chat Message View
struct ChatMessageView: View {
    let message: CosmoMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                // Cosmo avatar
                CosmoAvatar()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // Message bubble
                MessageBubble(
                    content: message.content,
                    isUser: message.role == .user
                )

                // Entity cards
                if !message.entities.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(message.entities) { entity in
                                EntityCard(entity: entity)
                            }
                        }
                    }
                }

                // Suggested actions
                if !message.actions.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(message.actions.enumerated()), id: \.offset) { _, action in
                            ActionButton(action: action)
                        }
                    }
                }

                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 500, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user {
                // User avatar
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.accentColor)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

// MARK: - Cosmo Avatar
struct CosmoAvatar: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(0.8), .blue.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)

            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundColor(.white)
                .rotationEffect(.degrees(isAnimating ? 5 : -5))
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimating)
        }
        .onAppear { isAnimating = true }
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let content: String
    let isUser: Bool

    var body: some View {
        Text(try! AttributedString(markdown: content))
            .font(.system(size: 14))
            .foregroundColor(isUser ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isUser
                    ? AnyShapeStyle(Color.accentColor)
                    : AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

// MARK: - Entity Card
struct EntityCard: View {
    let entity: EntityReference

    var body: some View {
        Button(action: openEntity) {
            HStack(spacing: 8) {
                Image(systemName: entity.type.icon)
                    .font(.system(size: 12))
                    .foregroundColor(entity.type.color)

                Text(entity.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(entity.type.color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func openEntity() {
        NotificationCenter.default.post(
            name: .openEntity,
            object: nil,
            userInfo: [
                "type": entity.type,
                "id": entity.id
            ]
        )
    }
}

// MARK: - Action Button
struct ActionButton: View {
    let action: CosmoSuggestedAction

    var body: some View {
        Button(action: performAction) {
            HStack(spacing: 4) {
                Image(systemName: iconForAction)
                    .font(.system(size: 11))

                Text(labelForAction)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var iconForAction: String {
        switch action {
        case .openEntity: return "arrow.up.right.square"
        case .placeOnCanvas: return "square.on.square.dashed"
        case .createIdea: return "lightbulb"
        case .addToCalendar: return "calendar.badge.plus"
        case .openCalendar: return "calendar"
        case .startResearch: return "magnifyingglass"
        }
    }

    private var labelForAction: String {
        switch action {
        case .openEntity: return "Open"
        case .placeOnCanvas: return "Place on Canvas"
        case .createIdea: return "Create Idea"
        case .addToCalendar: return "Add to Calendar"
        case .openCalendar: return "Open Calendar"
        case .startResearch: return "Research"
        }
    }

    private func performAction() {
        switch action {
        case .openEntity(let type, let id):
            NotificationCenter.default.post(
                name: .openEntity,
                object: nil,
                userInfo: ["type": type, "id": id]
            )

        case .placeOnCanvas(let entityType, let count):
            NotificationCenter.default.post(
                name: .placeBlocksOnCanvas,
                object: nil,
                userInfo: ["entityType": entityType.rawValue, "quantity": count]
            )

        case .openCalendar:
            NotificationCenter.default.post(
                name: .navigateToSection,
                object: nil,
                userInfo: ["section": NavigationSection.calendar]
            )

        default:
            break
        }
    }
}

// MARK: - Processing Indicator
struct ProcessingIndicator: View {
    @State private var dots = 1

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CosmoAvatar()

            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .opacity(dots > index ? 1 : 0.3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 18))

            Spacer()
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                dots = (dots % 3) + 1
            }
        }
    }
}

// MARK: - Chat Input Bar
struct ChatInputBar: View {
    @Binding var text: String
    let isProcessing: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Text field
            TextField("Ask Cosmo anything...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(1...5)
                .focused(isFocused)
                .onSubmit {
                    if !text.isEmpty && !isProcessing {
                        onSend()
                    }
                }

            // Send button
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(text.isEmpty || isProcessing ? .secondary : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(text.isEmpty || isProcessing)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let openEntity = Notification.Name("openEntity")
}
