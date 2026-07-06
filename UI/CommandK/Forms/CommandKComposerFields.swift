// CosmoOS/UI/CommandK/Forms/CommandKComposerFields.swift
// Per-shape field stacks for the Command-K composer pane, mirroring the iOS
// plus-orb sheets (IdeaComposerView, TaskComposerView, CaptureSheet) with Mac
// manners: hover, tooltips, Tab chains, menus instead of sheets.

import SwiftUI

// MARK: - Idea (title · idea text · brand/format/platform · hooks · outline)

struct CommandKIdeaComposerFields: View {
    let pane: CommandKComposerPane
    let clients: [CommandKComposerClient]
    @Binding var hookDraft: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            CommandKComposerLeadField(pane: pane, placeholder: "Idea title")
            CommandKComposerTextEditor(
                pane: pane,
                field: .body,
                focusField: .body,
                placeholder: "What's the idea?",
                minHeight: 72
            )
            chipRow
            CommandKComposerHooksSection(pane: pane, hookDraft: $hookDraft)
            CommandKComposerOutlineSection(pane: pane)
        }
    }

    private var chipRow: some View {
        HStack(spacing: DS.space8) {
            CommandKComposerMenuChip(
                icon: "person.crop.square",
                label: brandLabel,
                isSet: !pane.binding(.client).wrappedValue.isEmpty,
                tint: DS.entityIdea,
                help: "Brand this idea belongs to"
            ) {
                Button("No brand") { setClient(nil) }
                ForEach(clients) { client in
                    Button(client.name) { setClient(client) }
                }
            }
            CommandKComposerMenuChip(
                icon: "rectangle.3.group",
                label: formatLabel,
                isSet: !pane.binding(.format).wrappedValue.isEmpty,
                tint: DS.entityIdea,
                help: "Content format"
            ) {
                Button("Any format") { pane.binding(.format, manualEdit: true).wrappedValue = "" }
                ForEach(ContentFormat.allCases, id: \.self) { candidate in
                    Button(candidate.displayName) {
                        pane.binding(.format, manualEdit: true).wrappedValue = candidate.rawValue
                    }
                }
            }
            CommandKComposerMenuChip(
                icon: "antenna.radiowaves.left.and.right",
                label: platformLabel,
                isSet: !pane.binding(.platform).wrappedValue.isEmpty,
                tint: DS.entityIdea,
                help: "Target platform"
            ) {
                Button("Any platform") { pane.binding(.platform, manualEdit: true).wrappedValue = "" }
                ForEach(IdeaPlatform.allCases, id: \.self) { candidate in
                    Button(candidate.displayName) {
                        pane.binding(.platform, manualEdit: true).wrappedValue = candidate.rawValue
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var brandLabel: String {
        let name = pane.binding(.client).wrappedValue
        return name.isEmpty ? "Brand" : name
    }

    private var formatLabel: String {
        ContentFormat(rawValue: pane.binding(.format).wrappedValue)?.displayName ?? "Format"
    }

    private var platformLabel: String {
        IdeaPlatform(rawValue: pane.binding(.platform).wrappedValue)?.displayName ?? "Platform"
    }

    private func setClient(_ client: CommandKComposerClient?) {
        pane.mutateDraft { draft in
            draft.form.setValue(client?.name ?? "", for: .client)
            draft.clientUUID = client?.uuid
        }
    }
}

// MARK: - Task (title · notes · schedule · priority · intent)

struct CommandKTaskComposerFields: View {
    let pane: CommandKComposerPane

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            CommandKComposerLeadField(pane: pane, placeholder: "Task title")
            CommandKComposerTextEditor(
                pane: pane,
                field: .notes,
                focusField: .notes,
                placeholder: "Notes",
                minHeight: 48
            )
            CommandKComposerScheduleSection(pane: pane)
            HStack(spacing: DS.space8) {
                CommandKComposerMenuChip(
                    icon: "flag",
                    label: priorityLabel,
                    isSet: !pane.binding(.priority).wrappedValue.isEmpty,
                    tint: DS.entityTask,
                    help: "Priority"
                ) {
                    ForEach(["low", "medium", "high"], id: \.self) { level in
                        Button(level.capitalized) {
                            pane.binding(.priority, manualEdit: true).wrappedValue = level
                        }
                    }
                }
                CommandKComposerMenuChip(
                    icon: "scope",
                    label: intentLabel,
                    isSet: !pane.binding(.intent).wrappedValue.isEmpty,
                    tint: DS.entityTask,
                    help: "Task intent"
                ) {
                    Button("General") { pane.binding(.intent, manualEdit: true).wrappedValue = "" }
                    ForEach(["write", "research", "plan", "design", "admin", "learn", "health"], id: \.self) { intent in
                        Button(intent.capitalized) {
                            pane.binding(.intent, manualEdit: true).wrappedValue = intent
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var priorityLabel: String {
        let raw = pane.binding(.priority).wrappedValue
        return raw.isEmpty ? "Priority" : raw.capitalized
    }

    private var intentLabel: String {
        let raw = pane.binding(.intent).wrappedValue
        return raw.isEmpty ? "Intent" : raw.capitalized
    }
}

/// Today/Tomorrow chips + a date row, storing ISO8601 in the `.date` field.
struct CommandKComposerScheduleSection: View {
    let pane: CommandKComposerPane

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: .now) }
    private var tomorrow: Date { calendar.date(byAdding: .day, value: 1, to: today) ?? today }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            HStack(spacing: DS.space8) {
                quickChip("Today", isOn: isDue(today)) { setDue(today) }
                quickChip("Tomorrow", isOn: isDue(tomorrow)) { setDue(tomorrow) }
                Spacer(minLength: 0)
                if dueDate != nil {
                    Button {
                        pane.binding(.date, manualEdit: true).wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DS.caption)
                            .foregroundStyle(DS.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Clear due date")
                    .accessibilityLabel("Clear due date")
                }
            }
            if let dueDate {
                DatePicker(
                    "Due",
                    selection: Binding(
                        get: { dueDate },
                        set: { setDue(calendar.startOfDay(for: $0)) }
                    ),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.compact)
                .font(DS.callout)
            }
        }
        .padding(DS.space10)
        .dsGlassSection()
    }

    private var dueDate: Date? {
        let raw = pane.binding(.date).wrappedValue
        guard !raw.isEmpty else { return nil }
        return ISO8601.date(from: raw)
    }

    private func isDue(_ day: Date) -> Bool {
        guard let dueDate else { return false }
        return calendar.isDate(dueDate, inSameDayAs: day)
    }

    private func setDue(_ day: Date) {
        pane.binding(.date, manualEdit: true).wrappedValue = ISO8601.string(from: day)
    }

    private func quickChip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(DS.caption.weight(isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? DS.textOnAccent : DS.entityTask)
                .padding(.horizontal, DS.space10)
                .padding(.vertical, DS.space6)
                .background(isOn ? DS.entityTask : DS.entityTask.opacity(0.10), in: .capsule)
        }
        .buttonStyle(.plain)
        .help("Due \(label.lowercased())")
    }
}

// MARK: - Inbox capture (one field, lane-alias aware)

struct CommandKInboxComposerFields: View {
    let pane: CommandKComposerPane

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            CommandKComposerTextEditor(
                pane: pane,
                field: .body,
                focusField: .lead,
                placeholder: "Capture anything — your Inbox sorts it",
                minHeight: 120
            )
            Label("Lands in your Inbox for triage", systemImage: "tray.and.arrow.down")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
    }
}

// MARK: - Swipe capture (URL · hook)

struct CommandKSwipeComposerFields: View {
    let pane: CommandKComposerPane

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            CommandKComposerTextField(
                pane: pane,
                field: .url,
                focusField: .lead,
                placeholder: "Paste a reel, post, or page URL"
            )
            if let badge = sourceBadge {
                Label(badge, systemImage: "checkmark.seal")
                    .font(DS.caption)
                    .foregroundStyle(DS.entitySwipe)
            }
            CommandKComposerTextField(
                pane: pane,
                field: .hook,
                focusField: .hook,
                placeholder: "Why it works (hook note, optional)"
            )
        }
    }

    private var sourceBadge: String? {
        let url = pane.binding(.url).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty,
              let preview = CommandKCaptureRouter().preview(for: url),
              preview.kind == .swipe else { return nil }
        return "Recognized \(preview.source.rawValue.capitalized) source"
    }
}

// MARK: - Note / Content / Thinkspace (title only)

struct CommandKTitleOnlyComposerFields: View {
    let pane: CommandKComposerPane

    var body: some View {
        CommandKComposerLeadField(pane: pane, placeholder: "Title")
    }
}

// MARK: - Field primitives

/// The hero field — the shape's title (or the capture body handled elsewhere).
struct CommandKComposerLeadField: View {
    let pane: CommandKComposerPane
    let placeholder: String

    var body: some View {
        TextField(placeholder, text: pane.binding(.title), axis: .vertical)
            .textFieldStyle(.plain)
            .font(DS.title2.weight(.semibold))
            .foregroundStyle(DS.text)
            .lineLimit(1...3)
            .padding(DS.space10)
            .dsGlassInput(isFocused: pane.focusBinding.wrappedValue == .lead)
            .focused(pane.focusBinding, equals: .lead)
            .onSubmit { pane.commit() }
    }
}

struct CommandKComposerTextField: View {
    let pane: CommandKComposerPane
    let field: CommandKFormFieldID
    let focusField: CommandKComposerField
    let placeholder: String

    var body: some View {
        TextField(placeholder, text: pane.binding(field, manualEdit: true))
            .textFieldStyle(.plain)
            .font(DS.callout)
            .foregroundStyle(DS.text)
            .padding(DS.space10)
            .dsGlassInput(isFocused: pane.focusBinding.wrappedValue == focusField)
            .focused(pane.focusBinding, equals: focusField)
            .onSubmit { pane.commit() }
    }
}

struct CommandKComposerTextEditor: View {
    let pane: CommandKComposerPane
    let field: CommandKFormFieldID
    let focusField: CommandKComposerField
    let placeholder: String
    let minHeight: CGFloat

    var body: some View {
        TextField(placeholder, text: pane.binding(field, manualEdit: true), axis: .vertical)
            .textFieldStyle(.plain)
            .font(DS.callout)
            .foregroundStyle(DS.text)
            .lineLimit(3...10)
            .frame(minHeight: minHeight, alignment: .topLeading)
            .padding(DS.space10)
            .dsGlassInput(isFocused: pane.focusBinding.wrappedValue == focusField)
            .focused(pane.focusBinding, equals: focusField)
    }
}

/// Menu chip in the iOS composer grammar: tinted capsule, chevron, set-state
/// fills with the entity tint.
struct CommandKComposerMenuChip<Items: View>: View {
    let icon: String
    let label: String
    let isSet: Bool
    let tint: Color
    let help: String
    @ViewBuilder let items: () -> Items

    @State private var isHovered = false

    var body: some View {
        Menu(content: items) {
            HStack(spacing: DS.space6) {
                Image(systemName: icon).font(DS.caption)
                Text(label).font(DS.caption.weight(isSet ? .semibold : .regular)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(isSet ? DS.textOnAccent : tint)
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space6)
            .background(isSet ? tint : tint.opacity(isHovered ? 0.16 : 0.10), in: .capsule)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Hooks

struct CommandKComposerHooksSection: View {
    let pane: CommandKComposerPane
    @Binding var hookDraft: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text("HOOKS")
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(DS.textMuted)
                .kerning(0.8)
            ForEach(Array((pane.viewModel.composerDraft?.hooks ?? []).enumerated()), id: \.offset) { index, hook in
                HStack(spacing: DS.space8) {
                    Image(systemName: "quote.opening")
                        .font(DS.caption2)
                        .foregroundStyle(DS.entityIdea)
                    Text(hook)
                        .font(DS.callout)
                        .foregroundStyle(DS.text)
                    Spacer(minLength: 0)
                    Button {
                        pane.mutateDraft { $0.hooks.remove(at: index) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DS.caption)
                            .foregroundStyle(DS.textMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove hook")
                }
                .padding(DS.space8)
                .dsGlassSection()
            }
            HStack(spacing: DS.space8) {
                TextField("Add a hook…", text: $hookDraft)
                    .textFieldStyle(.plain)
                    .font(DS.callout)
                    .focused(pane.focusBinding, equals: .hook)
                    .onSubmit(addHook)
                Button(action: addHook) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(DS.entityIdea)
                }
                .buttonStyle(.plain)
                .disabled(hookDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Add hook")
            }
            .padding(DS.space8)
            .dsGlassInput(isFocused: pane.focusBinding.wrappedValue == .hook)
        }
    }

    private func addHook() {
        let trimmed = hookDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pane.mutateDraft { $0.hooks.append(trimmed) }
        hookDraft = ""
    }
}

// MARK: - Outline

struct CommandKComposerOutlineSection: View {
    let pane: CommandKComposerPane

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            HStack(spacing: DS.space8) {
                Text("OUTLINE")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .kerning(0.8)
                Button {
                    pane.mutateDraft { $0.outline.append("") }
                } label: {
                    Label("Slide", systemImage: "plus")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Add slide")
            }
            ForEach(Array((pane.viewModel.composerDraft?.outline ?? []).indices), id: \.self) { index in
                outlineRow(index)
            }
        }
    }

    private func outlineRow(_ index: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.space8) {
            Text(CommandKComposerOutlineSection.romanNumeral(index + 1))
                .font(DS.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(DS.textMuted)
                .frame(width: 26, alignment: .trailing)
            TextField(
                "what should this slide do?",
                text: Binding(
                    get: { pane.viewModel.composerDraft?.outline[safe: index] ?? "" },
                    set: { newValue in
                        pane.mutateDraft { draft in
                            guard draft.outline.indices.contains(index) else { return }
                            draft.outline[index] = newValue
                        }
                    }
                )
            )
            .textFieldStyle(.plain)
            .font(DS.callout)
            .focused(pane.focusBinding, equals: .outline(index))
            .onSubmit {
                pane.mutateDraft { draft in
                    if index == draft.outline.count - 1 { draft.outline.append("") }
                }
            }
            Button {
                pane.mutateDraft { draft in
                    guard draft.outline.indices.contains(index) else { return }
                    draft.outline.remove(at: index)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DS.textMuted.opacity(0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove slide \(index + 1)")
        }
        .padding(.vertical, DS.space6)
        .padding(.horizontal, DS.space8)
        .dsGlassSection()
    }

    static func romanNumeral(_ number: Int) -> String {
        let values = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                      (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var remaining = max(1, number)
        var result = ""
        for (value, symbol) in values {
            while remaining >= value {
                result += symbol
                remaining -= value
            }
        }
        return result
    }
}

