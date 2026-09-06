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
    @State private var scrollMetrics = CortexScrollMetricsStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space16) {
                header
                if let draft = viewModel.composerDraft, draft.actionID == action.id {
                    if let kind = draft.kind.compositionKind {
                        CommandKComposerDestinationRow(viewModel: viewModel, kind: kind)
                    }
                    fields(for: draft.kind)
                        .disabled(viewModel.isExecutingAction || viewModel.createdCompositionUUID != nil)
                }
                // Keep the last rows reachable above the floating Save pill.
                Spacer(minLength: DS.space48)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CortexScrollViewIntrospector { [scrollMetrics] in scrollMetrics.publish($0) })
        }
        .scrollIndicators(.hidden)
        .cortexThinScrollbar(store: scrollMetrics)
        .overlay(alignment: .bottomTrailing) { floatingSave }
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

    /// The eyebrow — a quiet kind label above the hero title field. The hero
    /// of the pane is the title the user is typing, never this chrome.
    private var header: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: action.icon)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text((viewModel.composerDraft?.form.primaryTitle ?? action.title).uppercased())
                .font(DS.caption2.weight(.semibold))
                .kerning(0.8)
                .foregroundStyle(DS.textSecondary)
            Spacer(minLength: 0)
            Text(headerHint)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
        .accessibilityElement(children: .combine)
    }

    /// One floating Save pill — no bar, no echoed validation text. The form
    /// speaks for itself; an invalid draft just leaves the pill disabled.
    private var floatingSave: some View {
        Button("Save") { commit() }
            .buttonStyle(CommandKComposerSaveButtonStyle(accent: accent))
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.composerDraft?.validation.isValid != true || viewModel.isExecutingAction)
            .help(saveHelp)
            .padding(.trailing, DS.space16)
            .padding(.bottom, DS.space12)
    }

    private var saveHelp: String {
        if let message = viewModel.composerDraft?.validation.message {
            return "\(message) (⌘↩ to save)"
        }
        return "Save (⌘↩)"
    }

    private var headerHint: String {
        switch viewModel.composerDraft?.kind {
        case .captureInbox: return "Lands in your Inbox for triage"
        case .createNote, .createContent: return "Creates and opens the editor"
        case .createGroup: return "Collect originals together"
        case .createBook, .createCourse: return "Editable starter Pages"
        case .createThinkspace: return "Collect, think, and create"
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
            CommandKSwipeComposerFields(pane: self, clients: clients)
        case .createNote:
            CommandKNoteComposerFields(pane: self)
        case .createGroup, .createBook, .createCourse:
            CommandKCompositionComposerFields(pane: self, kind: kind.compositionKind ?? .page)
        case .createContent:
            CommandKContentComposerFields(pane: self)
        case .createThinkspace:
            CommandKThinkspaceComposerFields(pane: self)
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
            || viewModel.composerDraft?.kind == .captureSwipe
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
    case checklist
    case outline(Int)
    case sparkTitle  // swipe composer's inline "spark an idea"
    case sparkBody
}

private struct CommandKComposerSaveButtonStyle: ButtonStyle {
    let accent: Color
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.callout.weight(.semibold))
            .foregroundStyle(DS.textOnAccent)
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space8)
            .background(accent.opacity(fillOpacity(isPressed: configuration.isPressed)), in: .capsule)
            .dsFloatingShadow()
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(ProMotionSprings.press, value: configuration.isPressed)
            .animation(ProMotionSprings.snappy, value: isEnabled)
            .onHover { isHovered = $0 }
    }

    private func fillOpacity(isPressed: Bool) -> Double {
        if isPressed { return 0.85 }
        return isHovered ? 1.0 : 0.92
    }
}
