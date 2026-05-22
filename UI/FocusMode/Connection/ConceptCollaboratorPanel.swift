// CosmoOS/UI/FocusMode/Connection/ConceptCollaboratorPanel.swift
// April 2026 — connection-native collaborator for The Atelier

import SwiftUI

struct ConceptCollaboratorPanel: View {

    @Binding var messages: [CollaboratorMessage]

    let frameworkTitle: String
    let conceptType: ConceptFrameworkType
    let isThinking: Bool
    var activeDraft: ConnectionDraftProposal? = nil
    var previewSourceMessageID: UUID? = nil
    var isPreviewPaused: Bool = false
    var linkedSourceCount: Int = 0
    let onSend: (String) -> Void
    var onCrystallize: ((CollaboratorMessage) -> Void)? = nil
    var onInsertDraft: ((ConnectionDraftProposal) -> Void)? = nil
    var onReviseDraft: ((ConnectionDraftProposal) -> Void)? = nil
    var onMoveDraft: ((ConnectionDraftProposal, ConnectionSectionType) -> Void)? = nil
    var onDismissDraft: ((ConnectionDraftProposal) -> Void)? = nil
    var onResumeDraft: ((ConnectionDraftProposal) -> Void)? = nil
    var onUseLinkedSources: (() -> Void)? = nil

    @State private var composer: String = ""
    @FocusState private var composerFocused: Bool

    private var lastAssistantQuestion: String? {
        messages.reversed().compactMap { message in
            guard message.role == .assistant else { return nil }
            return message.questionSuggestion?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.first { !$0.isEmpty }
    }

    private var actionChips: [QuickChip] {
        if let activeDraft {
            var chips: [QuickChip] = []
            let draftID = activeDraft.id.uuidString
            if isPreviewPaused, let onResumeDraft {
                chips.append(QuickChip(id: "draft-\(draftID)-resume", label: "Resume draft", action: { onResumeDraft(activeDraft) }))
                chips.append(QuickChip(id: "draft-\(draftID)-use-current", label: "Use my version", action: { onDismissDraft?(activeDraft) }))
            }
            chips.append(contentsOf: [
                QuickChip(id: "draft-\(draftID)-insert", label: "Insert", action: { onInsertDraft?(activeDraft) }),
                QuickChip(id: "draft-\(draftID)-revise", label: "Revise", action: { onReviseDraft?(activeDraft) })
            ])
            if !isPreviewPaused {
                chips.append(QuickChip(id: "draft-\(draftID)-dismiss", label: "Dismiss", action: { onDismissDraft?(activeDraft) }))
            }
            return chips
        }

        var chips: [QuickChip] = []
        if let question = lastAssistantQuestion {
            chips.append(QuickChip(id: "question-\(question)", label: question, action: { send(question) }))
        }
        if linkedSourceCount > 0, let onUseLinkedSources {
            chips.append(QuickChip(id: "linked-sources", label: "Use linked sources", action: onUseLinkedSources))
        }
        return chips
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            transcript
            composerArea
        }
        .background(DS.vellumDeep.opacity(0.24), in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.sepiaBorder.opacity(0.78), lineWidth: 0.5)
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(DS.entityConnection.opacity(0.38))
                    .frame(width: 6, height: 6)
                Text("CONCEPT COLLABORATOR")
                    .font(DS.smallCaps)
                    .tracking(1.8)
                    .foregroundStyle(DS.giltMuted)
                Spacer()
                statusLabel
            }

            if !frameworkTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(frameworkTitle)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(DS.inkWash)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var statusLabel: some View {
        if let activeDraft, activeDraft.status == .streaming {
            Text("writing into \(activeDraft.targetSection.displayName.lowercased())")
                .font(.system(size: 10, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(activeDraft.targetSection.accentColor.opacity(0.9))
        } else if isThinking {
            Text("thinking")
                .font(.system(size: 10, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(DS.inkFaded)
        } else if linkedSourceCount > 0 {
            Text("\(linkedSourceCount) linked source\(linkedSourceCount == 1 ? "" : "s")")
                .font(.system(size: 10, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(DS.inkFaded)
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(messages) { message in
                            messageRow(message)
                        }
                    }

                    if isThinking, messages.isEmpty {
                        thinkingLine
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("collaborator-bottom")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("collaborator-bottom", anchor: .bottom)
                }
            }
            .onChange(of: activeDraft?.id) { _, _ in
                if isPreviewPaused {
                    proxy.scrollTo("collaborator-bottom", anchor: .bottom)
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("collaborator-bottom", anchor: .bottom)
                    }
                }
            }
            .onChange(of: activeDraft?.status) { _, _ in
                guard activeDraft != nil else { return }
                proxy.scrollTo("collaborator-bottom", anchor: .bottom)
            }
        }
        .layoutPriority(1)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.sepiaSubtle)
                .frame(height: 0.5)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 28)
            Text("Send the core idea.")
                .font(.system(size: 14, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(DS.inkFaded)
            Text("It can be messy. One sentence, a link, a half-formed question. Doesn't matter.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DS.inkFaded)
                .multilineTextAlignment(.center)
            if linkedSourceCount > 0 {
                Text("\(linkedSourceCount) linked source\(linkedSourceCount == 1 ? "" : "s") available.")
                    .font(.system(size: 10, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(DS.giltMuted)
            }
            Spacer(minLength: 28)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func messageRow(_ message: CollaboratorMessage) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 36)
                Text(message.text)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(DS.inkWash)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(DS.vellumDeep.opacity(0.72), in: .rect(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(DS.sepiaBorder, lineWidth: 0.5)
                    )
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(message.observationKind?.label.uppercased() ?? "COSMO")
                        .font(DS.smallCaps)
                        .tracking(1.5)
                        .foregroundStyle(message.observationKind == nil ? DS.giltMuted : DS.gilt)

                    if let recommendation = message.recommendedAction,
                       !recommendation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(recommendation)
                            .font(.system(size: 10, weight: .regular, design: .serif))
                            .italic()
                            .foregroundStyle(DS.inkFaded)
                            .lineLimit(1)
                    }
                }

                Text(message.text)
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .foregroundStyle(DS.inkWash)
                    .fixedSize(horizontal: false, vertical: true)

                if let draft = resolvedDraft(for: message) {
                    draftRow(draft, legacyMessage: message)
                }
            }
        }
    }

    private func resolvedDraft(for message: CollaboratorMessage) -> ConnectionDraftProposal? {
        if let activeDraft,
           previewSourceMessageID == message.id || message.draftProposals.contains(where: { $0.id == activeDraft.id }) {
            return activeDraft
        }
        return message.draftProposals.first { draft in
            draft.status != .accepted && draft.status != .dismissed
        } ?? message.draftProposal
    }

    @ViewBuilder
    private func draftRow(_ draft: ConnectionDraftProposal, legacyMessage: CollaboratorMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(draft.targetSection.displayName.uppercased())
                    .font(DS.smallCaps)
                    .tracking(1.4)
                    .foregroundStyle(draft.targetSection.accentColor)

                Text(draft.statusLabel)
                    .font(.system(size: 10, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(DS.inkFaded)
            }

            Text(draft.renderedText.isEmpty ? "Preparing the draft…" : draft.renderedText)
                .font(.system(size: 12, weight: .regular, design: .serif))
                .foregroundStyle(DS.inkWash)
                .fixedSize(horizontal: false, vertical: true)

            if !draft.rationale.isEmpty {
                Text(draft.rationale)
                    .font(.system(size: 10, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(DS.inkFaded)
            }

            if onInsertDraft != nil {
                draftActionRow(draft: draft, isPausedPreview: isPreviewPaused && activeDraft?.id == draft.id)
            } else if legacyMessage.draftProposal != nil {
                legacyCrystallizeButton(legacyMessage)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DS.vellumDeep.opacity(0.42), in: .rect(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(draft.targetSection.accentColor.opacity(0.25), lineWidth: 0.6)
        )
    }

    private func draftActionRow(draft: ConnectionDraftProposal, isPausedPreview: Bool) -> some View {
        HStack(spacing: 10) {
            if isPausedPreview, let onResumeDraft {
                Button("Resume") { onResumeDraft(draft) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(draft.targetSection.accentColor)
            }

            if let onInsertDraft, draft.status != .accepted && draft.status != .dismissed {
                Button("Insert") { onInsertDraft(draft) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(draft.targetSection.accentColor)
            }

            if let onReviseDraft, draft.status != .accepted && draft.status != .dismissed {
                Button("Revise") { onReviseDraft(draft) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(DS.giltMuted)
            }

            if let onMoveDraft, draft.status != .accepted && draft.status != .dismissed {
                Menu {
                    ForEach(ConnectionSectionType.allCases, id: \.self) { section in
                        Button(section.displayName) {
                            onMoveDraft(draft, section)
                        }
                    }
                } label: {
                    Text("Move")
                        .font(.system(size: 10, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(DS.giltMuted)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            if let onDismissDraft, draft.status != .accepted && draft.status != .dismissed {
                Button(isPausedPreview ? "Use my version" : "Dismiss") { onDismissDraft(draft) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(DS.inkFaded)
            }
        }
    }

    private func legacyCrystallizeButton(_ message: CollaboratorMessage) -> some View {
        Button {
            onCrystallize?(message)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 9))
                Text("Crystallize")
                    .font(DS.smallCaps)
                    .tracking(1.2)
            }
            .foregroundStyle(DS.entityConnection)
        }
        .buttonStyle(.plain)
    }

    private var thinkingLine: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(DS.gilt.opacity(0.6))
                    .frame(width: 4, height: 4)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever().delay(0.12 * Double(index)),
                        value: isThinking
                    )
            }
        }
        .padding(.vertical, 4)
    }

    private var composerArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !actionChips.isEmpty {
                chipRow
            }
            composerField
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DS.vellumDeep.opacity(0.14))
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(actionChips) { chip in
                    Button(action: chip.action) {
                        Text(chip.label)
                            .font(.system(size: 10, weight: .regular, design: .serif))
                            .italic()
                            .foregroundStyle(DS.giltMuted)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().stroke(DS.gilt.opacity(0.28), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var composerField: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("One sentence, a link, a half-formed question.", text: $composer, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .regular, design: .serif))
                .foregroundStyle(DS.inkWash)
                .focused($composerFocused)
                .lineLimit(1...5)
                .onSubmit { send(composer) }

            Button { send(composer) } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? DS.inkFaded : DS.entityConnection)
            }
            .buttonStyle(.plain)
            .disabled(composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DS.vellumDeep.opacity(0.46), in: .rect(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(DS.sepiaBorder, lineWidth: 0.5)
        )
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }
        composer = ""
        onSend(trimmed)
    }
}

private struct QuickChip: Identifiable {
    let id: String
    let label: String
    let action: () -> Void

    init(id: String? = nil, label: String, action: @escaping () -> Void) {
        self.id = id ?? label
        self.label = label
        self.action = action
    }
}

private extension ConnectionDraftProposal {
    var statusLabel: String {
        switch status {
        case .streaming: return "Drafting"
        case .pending: return "Pending"
        case .accepted: return "Inserted"
        case .dismissed: return "Dismissed"
        }
    }
}
