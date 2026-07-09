// CosmoOS/UI/CommandK/Forms/CommandKComposerDraft.swift
// The state of one Command-K composer panel — the Mac's answer to the iOS
// plus-orb sheets. Wraps the inline form model (field values + validation)
// and adds the list fields (hooks, outline) plus the query-sync contract:
// search-field text prefills the lead field only until the user edits it
// directly (manual wins, same rule as the iOS composers).

import Foundation

struct CommandKComposerDraft: Equatable {
    let kind: CommandKInlineFormKind
    /// Identity of the action row this draft belongs to. A selection landing
    /// on a different creation action mints a fresh draft; the same action
    /// keeps accumulated field edits.
    let actionID: String
    var form: CommandKInlineFormModel
    var hooks: [String] = []
    var outline: [String] = []
    var titleEditedManually = false
    /// Resolved client UUID once the brand menu picks a profile.
    var clientUUID: String?

    // MARK: Task facets (typed — the iOS TaskComposerView contract)

    /// Planned-for day (focusDate) when set independently of the due date.
    var focusDate: Date?
    /// Scheduling estimate in minutes (None/15/25/45/60/120 presets).
    var durationMinutes: Int?
    /// Timed-task goal — tracking this much time prompts completion.
    var timeGoalMinutes: Int?
    /// Subtasks captured at birth, encoded to TaskMetadata.checklist on save.
    var checklist: [ChecklistItem] = []
    /// Repeating-series rule; commit writes rule JSON + seriesAnchorDay.
    var recurrenceRule: RecurrenceRule?
    /// Parsed time of day ("at 3pm") — commit writes TaskMetadata.startTime.
    var scheduledTime: Date?
    /// Quick-add grammar result: the title with recognized phrases stripped.
    /// Set by the task form's live parse; nil means save the raw title.
    var cleanedTitle: String?
    /// The user dismissed the parsed habit chip — commit skips auto-attribution.
    var suppressHabit = false

    // MARK: Cross-shape extras

    /// "Inspired by" swipe for idea drafts (and the reverse: the idea a swipe
    /// capture sparks) — writes the linkedSwipeIds/originSwipeUUID contract.
    var linkedSwipeUUID: String?
    /// Swipe composer: the inline "spark an idea" disclosure state.
    var sparkIdea = false
    /// The sparked idea's fields (title falls back to the hook on commit).
    var sparkTitle = ""
    var sparkBody = ""

    var validation: CommandKFormValidation { form.validation }

    /// The field the search query syncs into while typing.
    var querySyncField: CommandKFormFieldID {
        kind == .captureInbox ? .body : .title
    }

    static func draft(for action: CommandKAction) -> CommandKComposerDraft? {
        guard let kind = composerKind(for: action.kind) else { return nil }
        var form = CommandKInlineFormModel(kind: kind)
        if let title = action.payload.title { form.setValue(title, for: .title) }
        if let body = action.payload.body { form.setValue(body, for: .body) }
        if let url = action.payload.url { form.setValue(url, for: .url) }
        if let client = action.payload.clientName { form.setValue(client, for: .client) }
        if let hook = action.payload.hook { form.setValue(hook, for: .hook) }
        return CommandKComposerDraft(kind: kind, actionID: action.id, form: form)
    }

    /// Which creation actions get a live composer in the detail pane.
    /// Navigation/open actions keep their static visual preview.
    static func composerKind(for kind: CommandKActionKind) -> CommandKInlineFormKind? {
        switch kind {
        case .createIdea: return .createIdea
        case .createTask: return .createTask
        case .createNote: return .createNote
        case .createContent: return .createContent
        case .createThinkspace: return .createThinkspace
        case .captureInbox: return .captureInbox
        case .captureSwipe: return .captureSwipe
        default: return nil
        }
    }

    /// Re-sync prefills from the latest parse of the search query. Fields the
    /// user already touched by hand are never clobbered.
    mutating func syncPrefills(from action: CommandKAction) {
        guard action.id == actionID else { return }
        if !titleEditedManually {
            let field = querySyncField
            let incoming = (field == .body ? action.payload.body : action.payload.title) ?? ""
            form.setValue(incoming, for: field)
        }
        if form.value(for: .client).isEmpty, let client = action.payload.clientName {
            form.setValue(client, for: .client)
        }
    }
}
