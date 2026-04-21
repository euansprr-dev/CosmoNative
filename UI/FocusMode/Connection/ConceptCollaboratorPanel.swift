// CosmoOS/UI/FocusMode/Connection/ConceptCollaboratorPanel.swift
// April 2026 — Connection Focus Mode V2 "The Crucible"
//
// The Socratic chat panel that lives at the top of The Atelier. Three seed chips
// above the composer ("What's the tension?", "What would make this wrong?",
// "Closest existing framework?"). When the assistant suggests content for a
// specific station, the bubble exposes a "Crystallize into [SECTION]" button.

import SwiftUI

struct ConceptCollaboratorPanel: View {

    // MARK: - Inputs

    @Binding var messages: [CollaboratorMessage]

    let frameworkTitle: String
    let conceptType: ConceptFrameworkType
    let isThinking: Bool

    /// Called when the user sends a prompt (chip or composer). The caller is
    /// responsible for appending the user message, calling the engine, and
    /// appending the assistant response.
    let onSend: (String) -> Void

    /// Called when the user taps "Crystallize into [SECTION]" on a bubble.
    let onCrystallize: (CollaboratorMessage) -> Void

    // MARK: - Local state

    @State private var composer: String = ""
    @FocusState private var composerFocused: Bool

    private let seedPrompts: [String] = [
        "What's the tension?",
        "What would make this wrong?",
        "Closest existing framework?"
    ]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            conversation
            composerArea
        }
        .background(DS.vellumDeep.opacity(0.32), in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.sepiaBorder.opacity(0.8), lineWidth: 0.5)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(DS.entityConnection.opacity(0.35))
                .frame(width: 6, height: 6)
            Text("CONCEPT COLLABORATOR")
                .font(DS.smallCaps)
                .tracking(1.8)
                .foregroundStyle(DS.giltMuted)
            Spacer()
            if isThinking {
                ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var hairline: some View {
        Rectangle().fill(DS.sepiaSubtle).frame(height: 0.5)
    }

    // MARK: - Conversation

    @ViewBuilder
    private var conversation: some View {
        if messages.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(messages) { message in
                            bubble(for: message)
                                .id(message.id)
                        }
                        if isThinking {
                            thinkingBubble
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 24)
            Text("Ready when you are.")
                .font(.system(size: 14, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(DS.inkFaded)
            Text("Ask what's unresolved about “\(frameworkTitle.isEmpty ? conceptType.displayName : frameworkTitle)”.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DS.inkFaded)
                .multilineTextAlignment(.center)
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    // MARK: - Bubble

    @ViewBuilder
    private func bubble(for message: CollaboratorMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 32)
                Text(message.text)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(DS.inkWash)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(DS.vellumDeep, in: .rect(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(DS.sepiaBorder, lineWidth: 0.5)
                    )
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                Text(message.text)
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .foregroundStyle(DS.inkWash)
                    .fixedSize(horizontal: false, vertical: true)

                if let target = message.crystallizeTarget, message.crystallizeContent != nil {
                    crystallizeButton(target: target, message: message)
                }
            }
        }
    }

    private func crystallizeButton(target: ConnectionSectionType, message: CollaboratorMessage) -> some View {
        Button {
            onCrystallize(message)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 9))
                Text("Crystallize into \(target.displayName.uppercased())")
                    .font(DS.smallCaps)
                    .tracking(1.4)
            }
            .foregroundStyle(target.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().stroke(target.accentColor.opacity(0.55), lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
    }

    private var thinkingBubble: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(DS.gilt.opacity(0.55))
                    .frame(width: 4, height: 4)
                    .scaleEffect(1.0)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever().delay(0.12 * Double(i)),
                        value: isThinking
                    )
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Composer

    private var composerArea: some View {
        VStack(spacing: 8) {
            seedChips
            composer_
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DS.vellumDeep.opacity(0.18))
        .overlay(alignment: .top) { hairline }
    }

    private var seedChips: some View {
        HStack(spacing: 6) {
            ForEach(seedPrompts, id: \.self) { prompt in
                Button {
                    send(prompt)
                } label: {
                    Text(prompt)
                        .font(.system(size: 10, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(DS.giltMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().stroke(DS.gilt.opacity(0.3), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composer_: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("ask the collaborator…", text: $composer, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .regular, design: .serif))
                .foregroundStyle(DS.inkWash)
                .focused($composerFocused)
                .lineLimit(1...5)
                .onSubmit { send(composer) }

            Button { send(composer) } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(composer.isEmpty ? DS.inkFaded : DS.entityConnection)
            }
            .buttonStyle(.plain)
            .disabled(composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DS.vellumDeep.opacity(0.45), in: .rect(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(DS.sepiaBorder, lineWidth: 0.5)
        )
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }
        onSend(trimmed)
        composer = ""
    }
}
