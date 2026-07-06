// CosmoOS/UI/CommandK/Forms/CommandKComposerPane.swift
// The Command-K composer — the Mac's answer to the iOS plus-orb sheets,
// rendered live in the detail pane when a creation action is selected.
// One glass grammar: warm section fills on the preview paper, DS type only,
// the lead field is the hero, entity tint as punctuation.

import SwiftUI

struct CommandKComposerPane: View {
    @Bindable var viewModel: CommandKViewModel
    let action: CommandKAction

    @FocusState private var focusedField: CommandKComposerField?
    @State private var clients: [CommandKComposerClient] = []
    @State private var hookDraft = ""
    @State private var scrollMetrics = CortexScrollMetrics()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space16) {
                header
                if let draft = viewModel.composerDraft, draft.actionID == action.id {
                    fields(for: draft.kind)
                }
                Spacer(minLength: DS.space24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CortexScrollViewIntrospector { scrollMetrics = $0 })
        }
        .scrollIndicators(.hidden)
        .cortexThinScrollbar(metrics: scrollMetrics)
        .safeAreaInset(edge: .bottom) { footer }
        .task(id: action.id) {
            viewModel.ensureComposerDraft(for: action)
            if needsClients, clients.isEmpty { await loadClients() }
        }
        .onChange(of: viewModel.isComposerFocused) { _, wantsFocus in
            if wantsFocus, focusedField == nil {
                focusFirstField()
            } else if !wantsFocus {
                focusedField = nil
            }
        }
        .onChange(of: focusedField) { _, field in
            viewModel.isComposerFocused = field != nil
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: DS.space10) {
            Image(systemName: action.icon)
                .font(DS.subheadline.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .background(accent.opacity(0.12), in: .rect(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.composerDraft?.form.primaryTitle ?? action.title)
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                Text(headerHint)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack(spacing: DS.space10) {
            if let message = viewModel.composerDraft?.validation.message {
                Text(message)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
            Spacer(minLength: 0)
            Text("⌘↩")
                .font(DS.caption.monospaced())
                .foregroundStyle(DS.textMuted)
            Button("Save") { commit() }
                .buttonStyle(CommandKComposerSaveButtonStyle(accent: accent))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(viewModel.composerDraft?.validation.isValid != true)
                .help("Save (⌘↩)")
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space10)
        .background(CommandKPreviewPaper.fill.opacity(0.92))
        .overlay(alignment: .top) {
            Rectangle().fill(DS.glassBorder).frame(height: 0.5)
        }
    }

    private var headerHint: String {
        switch viewModel.composerDraft?.kind {
        case .captureInbox: return "Lands in your Inbox for triage"
        case .createNote, .createContent: return "Creates and opens the editor"
        case .createThinkspace: return "Names a fresh canvas"
        case .captureSwipe: return "Captured to your Swipe File"
        default: return "Tab to fill · Esc back to search"
        }
    }

    private var accent: Color {
        switch viewModel.composerDraft?.kind {
        case .createIdea: return DS.entityIdea
        case .createTask: return DS.entityTask
        case .createNote: return DS.entityNote
        case .createContent: return DS.entityContent
        case .captureSwipe: return DS.entitySwipe
        default: return DS.entityResearch
        }
    }

    // MARK: - Forms

    @ViewBuilder
    private func fields(for kind: CommandKInlineFormKind) -> some View {
        switch kind {
        case .createIdea:
            CommandKIdeaComposerFields(
                pane: self,
                clients: clients,
                hookDraft: $hookDraft
            )
        case .createTask:
            CommandKTaskComposerFields(pane: self)
        case .captureInbox:
            CommandKInboxComposerFields(pane: self)
        case .captureSwipe:
            CommandKSwipeComposerFields(pane: self)
        case .createNote, .createContent, .createThinkspace:
            CommandKTitleOnlyComposerFields(pane: self)
        default:
            EmptyView()
        }
    }

    // MARK: - Draft plumbing (shared with the per-shape field views)

    func binding(_ field: CommandKFormFieldID, manualEdit: Bool = false) -> Binding<String> {
        Binding(
            get: { viewModel.composerDraft?.form.rawValue(for: field) ?? "" },
            set: { newValue in
                guard var draft = viewModel.composerDraft else { return }
                draft.form.setValue(newValue, for: field)
                if manualEdit || field == draft.querySyncField {
                    draft.titleEditedManually = true
                }
                viewModel.composerDraft = draft
            }
        )
    }

    func mutateDraft(_ mutate: (inout CommandKComposerDraft) -> Void) {
        guard var draft = viewModel.composerDraft else { return }
        mutate(&draft)
        viewModel.composerDraft = draft
    }

    var focusBinding: FocusState<CommandKComposerField?>.Binding { $focusedField }

    func commit() {
        guard viewModel.composerDraft?.validation.isValid == true else {
            focusFirstField()
            return
        }
        Task { await viewModel.commitComposerDraft() }
    }

    private func focusFirstField() {
        let first = CommandKComposerField.lead
        focusedField = first
        // Animated pane swaps drop the first FocusState write — re-assert it
        // (the same retry the actions panel uses).
        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
            if viewModel.isComposerFocused, focusedField == nil {
                focusedField = first
            }
        }
    }

    private var needsClients: Bool {
        viewModel.composerDraft?.kind == .createIdea
    }

    private func loadClients() async {
        let atoms = (try? await AtomRepository.shared.clientProfiles()) ?? []
        clients = atoms.compactMap { atom in
            guard let name = atom.title, !name.isEmpty else { return nil }
            return CommandKComposerClient(uuid: atom.uuid, name: name)
        }
    }
}

// MARK: - Shared bits

struct CommandKComposerClient: Identifiable, Equatable {
    let uuid: String
    let name: String
    var id: String { uuid }
}

enum CommandKComposerField: Hashable {
    case lead        // title (or the capture body)
    case body
    case url
    case hook
    case notes
    case outline(Int)
}

private struct CommandKComposerSaveButtonStyle: ButtonStyle {
    let accent: Color
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.callout.weight(.semibold))
            .foregroundStyle(DS.textOnAccent)
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space6)
            .background(accent.opacity(configuration.isPressed ? 0.85 : (isHovered ? 1.0 : 0.92)), in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(ProMotionSprings.press, value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}
