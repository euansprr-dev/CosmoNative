// CosmoOS/Canvas/CommandCenter/CommandCenterHabitEditor.swift
// The habit composer and library in the assistant-menu register: one compact
// glass panel, the leading-emoji identity contract (typed mark → curated
// keyword → picked SF icon fallback), curated accent dots, a segmented
// cadence, and power rules folded behind an Automation disclosure.
// July 2026 rebuild (was a scrolling 420pt form with an SF-icon grid).

import SwiftUI

// MARK: - Draft

struct CommandCenterHabitEditorDraft: Equatable {
    var title: String = ""
    var icon: String = "repeat"
    var accentColor: String = "2D6A4F"
    var dailyTargetCount: Int = 1
    /// "count" (N×/day) or "minutes" (N min/day of tracked focus time)
    var goalType: String = "count"
    var dailyTargetMinutes: Int = 30
    var allowManualCompletion: Bool = true
    var keywordInput: String = ""
    var mappedIntents: Set<TaskIntent> = []
    var defaultIntentUUID: String? = nil

    var isTimeBased: Bool { goalType == "minutes" }

    init() {}

    init(habit: HabitDefinition) {
        title = habit.title
        icon = habit.icon
        accentColor = habit.accentColor
        dailyTargetCount = habit.dailyTargetCount
        goalType = habit.goalType ?? "count"
        dailyTargetMinutes = habit.dailyTargetMinutes ?? 30
        allowManualCompletion = habit.allowManualCompletion
        keywordInput = habit.keywordTriggers.joined(separator: ", ")
        mappedIntents = Set(habit.taskIntents)
        defaultIntentUUID = habit.defaultIntentUUID
    }

    var keywords: [String] {
        keywordInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// The mark the user explicitly placed at the start of the title, if any.
    var explicitMark: String? {
        CollectionEmoji.resolve(name: title, matchKeywords: false).emoji
    }

    /// The mark the habit ring will actually render: typed emoji → curated
    /// keyword pass. Nil means the stored SF icon carries the identity.
    var effectiveMark: String? {
        CollectionEmoji.resolve(name: title).emoji
    }

    /// The title with any leading mark lifted out — what the name field shows.
    var displayLabel: String {
        CollectionEmoji.applying(mark: nil, to: title)
    }

    /// Rewrites the title's leading mark: an emoji replaces the current one,
    /// nil clears it. The bare label always survives untouched.
    mutating func applyMark(_ mark: String?) {
        title = CollectionEmoji.applying(mark: mark, to: title)
    }
}

// MARK: - Composer

struct CommandCenterHabitComposer: View {
    let habit: HabitDefinition?
    let onSave: (CommandCenterHabitEditorDraft) -> Void
    let onArchive: (() -> Void)?
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?
    let onDisable: (() -> Void)?
    let onOpenLibrary: (() -> Void)?
    let onDismiss: () -> Void
    private let availableIntents: [IntentDefinition]

    @State private var draft: CommandCenterHabitEditorDraft
    @State private var automationExpanded: Bool
    @FocusState private var titleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        habit: HabitDefinition?,
        onSave: @escaping (CommandCenterHabitEditorDraft) -> Void,
        onArchive: (() -> Void)? = nil,
        onMoveUp: (() -> Void)? = nil,
        onMoveDown: (() -> Void)? = nil,
        onDisable: (() -> Void)? = nil,
        onOpenLibrary: (() -> Void)? = nil,
        availableIntents: [IntentDefinition] = [],
        onDismiss: @escaping () -> Void
    ) {
        self.habit = habit
        self.onSave = onSave
        self.onArchive = onArchive
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onDisable = onDisable
        self.onOpenLibrary = onOpenLibrary
        self.availableIntents = availableIntents
        self.onDismiss = onDismiss
        let initial = habit.map(CommandCenterHabitEditorDraft.init(habit:)) ?? CommandCenterHabitEditorDraft()
        _draft = State(initialValue: initial)
        // Open with the rules visible only when the habit already has some.
        _automationExpanded = State(initialValue: !initial.mappedIntents.isEmpty || !initial.keywords.isEmpty)
    }

    private var isBuiltIn: Bool { habit?.isBuiltIn == true }
    private var canSave: Bool { !draft.displayLabel.isEmpty && !isBuiltIn }
    private var previewTint: Color { Color(hex: draft.accentColor) }

    /// The curated accent dots, with the habit's current (possibly legacy)
    /// color appended so the selected state is always visible.
    static func accentSwatches(current: String) -> [(name: String, hex: String)] {
        let curated = DS.collectionAccentPalette
        if curated.contains(where: { $0.hex.caseInsensitiveCompare(current) == .orderedSame }) {
            return curated
        }
        return curated + [("Current", current)]
    }

    var body: some View {
        CosmoGlassPanel(role: .globalSidebar, cornerRadius: 16) {
            VStack(spacing: 0) {
                header
                CosmoGradientDivider()
                if isBuiltIn {
                    builtInSummary
                } else {
                    formBody
                }
                footerHairline
                footer
            }
        }
        .dsFloatingShadow()
        .onExitCommand(perform: onDismiss)
        .onAppear { if habit == nil { titleFocused = true } }
    }

    // MARK: Header — the mark well and the name, once

    private var header: some View {
        HStack(spacing: DS.space10) {
            identityWell

            if isBuiltIn {
                Text(draft.displayLabel)
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("Habit name", text: titleBinding)
                    .textFieldStyle(.plain)
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                    .focused($titleFocused)
                    .onSubmit { if canSave { onSave(draft) } }
            }

            closeButton
        }
        .padding(.horizontal, DS.space16)
        .padding(.top, DS.space12)
        .padding(.bottom, DS.space12)
    }

    /// The name field holds the bare label; a mark typed at its start is
    /// lifted into the well on the next keystroke (the leading-emoji contract).
    private var titleBinding: Binding<String> {
        Binding(
            get: { draft.displayLabel },
            set: { newValue in
                let typedMark = CollectionEmoji.resolve(name: newValue, matchKeywords: false).emoji
                draft.title = CollectionEmoji.applying(mark: typedMark ?? draft.explicitMark, to: newValue)
            }
        )
    }

    /// A live miniature of the habit ring — exactly what the panels render.
    private var identityWell: some View {
        ZStack {
            Circle()
                .stroke(previewTint.opacity(0.18), lineWidth: 3)

            if let mark = draft.effectiveMark {
                Text(mark)
                    .font(.system(size: 15))
            } else {
                Image(systemName: draft.icon)
                    .font(DS.callout.weight(.semibold))
                    .foregroundStyle(previewTint)
            }
        }
        .frame(width: 34, height: 34)
        .animation(ProMotionSprings.snappy, value: draft.accentColor)
        .help(isBuiltIn ? "The habit's mark" : "The habit's mark — type an emoji at the start of the name, or pick one below")
        .accessibilityHidden(true)
    }

    private var closeButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .frame(width: 26, height: 26)
                .background(DS.glassInputFill, in: Circle())
                .overlay(Circle().stroke(DS.glassBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help("Close (Esc)")
        .accessibilityLabel("Close habit editor")
    }

    // MARK: Form body

    private var formBody: some View {
        ViewThatFits(in: .vertical) {
            formColumn
            ScrollView(.vertical, showsIndicators: false) { formColumn }
        }
    }

    private var formColumn: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            markRow
            accentRow
            goalSection
            automationSection
            checkInsRow
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space16)
    }

    // MARK: Identity — one-tap marks + accent dots

    private var markRow: some View {
        HStack(spacing: DS.space6) {
            ForEach(CollectionEmoji.suggestions(for: draft.displayLabel), id: \.self) { emoji in
                markChip(emoji)
            }
            if draft.explicitMark != nil {
                removeMarkChip
            }
            Spacer(minLength: 0)
        }
    }

    private func markChip(_ emoji: String) -> some View {
        let isCurrent = draft.explicitMark == emoji
        return HabitComposerChip(
            isSelected: isCurrent,
            help: isCurrent ? "Remove mark" : "Mark \(emoji)",
            accessibilityLabel: "Mark \(emoji)",
            action: { draft.applyMark(isCurrent ? nil : emoji) }
        ) {
            Text(emoji)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
        }
    }

    private var removeMarkChip: some View {
        HabitComposerChip(
            isSelected: false,
            help: "Remove mark",
            accessibilityLabel: "Remove mark",
            action: { draft.applyMark(nil) }
        ) {
            Image(systemName: "xmark")
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(DS.textMuted)
                .frame(width: 28, height: 28)
        }
    }

    private var accentRow: some View {
        HStack(spacing: DS.space8) {
            ForEach(Self.accentSwatches(current: draft.accentColor), id: \.hex) { swatch in
                accentDot(swatch)
            }
            Spacer(minLength: 0)
        }
    }

    private func accentDot(_ swatch: (name: String, hex: String)) -> some View {
        let tint = Color(hex: swatch.hex)
        let isSelected = draft.accentColor.caseInsensitiveCompare(swatch.hex) == .orderedSame
        return Button {
            draft.accentColor = swatch.hex
        } label: {
            Circle()
                .fill(tint)
                .frame(width: 18, height: 18)
                .overlay(
                    // The Reminders register: color, a paper gap, then a ring
                    // in the same color when selected.
                    Circle()
                        .stroke(DS.surface, lineWidth: 2)
                        .padding(1)
                )
                .overlay(
                    Circle()
                        .stroke(tint.opacity(isSelected ? 0.9 : 0), lineWidth: 1.5)
                        .padding(-3)
                )
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(swatch.name)
        .accessibilityLabel("Accent \(swatch.name)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: Goal

    private enum CadenceKind: CaseIterable {
        case count
        case time

        var title: String { self == .count ? "Count" : "Time" }
        var icon: String { self == .count ? "checkmark.circle" : "timer" }
        var help: String {
            self == .count
                ? "Ring fills from completions"
                : "Ring fills from tracked focus time on linked tasks"
        }
    }

    private var cadenceBinding: Binding<CadenceKind> {
        Binding(
            get: { draft.isTimeBased ? .time : .count },
            set: { draft.goalType = $0 == .time ? "minutes" : "count" }
        )
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            HabitComposerSectionLabel("GOAL")

            CosmoSegmentedSwitcher(
                options: CadenceKind.allCases,
                label: { $0.title },
                icon: { .system($0.icon) },
                help: { $0.help },
                selection: cadenceBinding
            )

            targetRow
            quickTargetRow
        }
    }

    private var targetRow: some View {
        HStack(spacing: DS.space10) {
            Text(draft.isTimeBased ? "Minutes per day" : "Times per day")
                .font(DS.callout)
                .foregroundStyle(DS.text)

            Spacer(minLength: 0)

            stepButton(systemImage: "minus", enabled: canDecrement, help: "Lower the target") {
                if draft.isTimeBased {
                    draft.dailyTargetMinutes = max(5, draft.dailyTargetMinutes - 5)
                } else {
                    draft.dailyTargetCount = max(1, draft.dailyTargetCount - 1)
                }
            }

            Text("\(draft.isTimeBased ? draft.dailyTargetMinutes : draft.dailyTargetCount)")
                .font(DS.headline)
                .monospacedDigit()
                .foregroundStyle(DS.text)
                .contentTransition(.numericText())
                .animation(ProMotionSprings.snappy, value: draft.dailyTargetCount)
                .animation(ProMotionSprings.snappy, value: draft.dailyTargetMinutes)
                .frame(minWidth: 30)

            stepButton(systemImage: "plus", enabled: canIncrement, help: "Raise the target") {
                if draft.isTimeBased {
                    draft.dailyTargetMinutes = min(480, draft.dailyTargetMinutes + 5)
                } else {
                    draft.dailyTargetCount = min(12, draft.dailyTargetCount + 1)
                }
            }
        }
    }

    private var canDecrement: Bool {
        draft.isTimeBased ? draft.dailyTargetMinutes > 5 : draft.dailyTargetCount > 1
    }

    private var canIncrement: Bool {
        draft.isTimeBased ? draft.dailyTargetMinutes < 480 : draft.dailyTargetCount < 12
    }

    private func stepButton(
        systemImage: String,
        enabled: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(enabled ? DS.text : DS.textMuted.opacity(0.5))
                .frame(width: 24, height: 24)
                .background(DS.glassInputFill, in: Circle())
                .overlay(Circle().stroke(DS.glassBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
    }

    private var quickTargetRow: some View {
        HStack(spacing: DS.space6) {
            if draft.isTimeBased {
                ForEach([15, 30, 60, 90], id: \.self) { minutes in
                    quickChip("\(minutes)m", isSelected: draft.dailyTargetMinutes == minutes) {
                        draft.dailyTargetMinutes = minutes
                    }
                }
            } else {
                ForEach([1, 2, 3, 5], id: \.self) { count in
                    quickChip("\(count)×", isSelected: draft.dailyTargetCount == count) {
                        draft.dailyTargetCount = count
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func quickChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        HabitComposerChip(
            isSelected: isSelected,
            help: "Set the target to \(label)",
            accessibilityLabel: "Target \(label)",
            isAccessibilitySelected: isSelected,
            action: action
        ) {
            Text(label)
                .font(DS.caption)
                .monospacedDigit()
                .foregroundStyle(isSelected ? DS.text : DS.textSecondary)
                .padding(.horizontal, DS.space10)
                .frame(height: 24)
        }
    }

    // MARK: Automation (folded rules)

    private var automationSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            automationDisclosureRow
            if automationExpanded {
                automationFields
            }
        }
    }

    private var automationDisclosureRow: some View {
        Button {
            // Discrete, never tweened: the disclosure changes the glass
            // panel's layout height, and a glassEffect container's size must
            // move in one invalidation (the glass-layer latch). Only the
            // chevron — a transform — animates.
            automationExpanded.toggle()
        } label: {
            HStack(spacing: DS.space6) {
                Image(systemName: "chevron.right")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .rotationEffect(.degrees(automationExpanded ? 90 : 0))
                    .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: automationExpanded)

                HabitComposerSectionLabel("AUTOMATION")

                Spacer(minLength: 0)

                Text(automationSummary)
                    .font(DS.caption2)
                    .monospacedDigit()
                    .foregroundStyle(DS.textMuted)
                    .contentTransition(.numericText())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Rules that feed this habit from tasks and focus sessions")
        .accessibilityLabel("Automation rules")
        .accessibilityValue(automationSummary)
        .accessibilityAddTraits(automationExpanded ? [.isSelected] : [])
    }

    private var automationSummary: String {
        var parts: [String] = []
        if !draft.mappedIntents.isEmpty { parts.append("\(draft.mappedIntents.count) intents") }
        if !draft.keywords.isEmpty { parts.append("\(draft.keywords.count) words") }
        if draft.defaultIntentUUID != nil { parts.append("default set") }
        return parts.isEmpty ? "None" : parts.joined(separator: " · ")
    }

    private var automationFields: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            VStack(alignment: .leading, spacing: DS.space6) {
                automationFieldLabel("Counts toward")
                intentGrid
            }

            VStack(alignment: .leading, spacing: DS.space6) {
                automationFieldLabel("Trigger words")
                keywordField
            }

            VStack(alignment: .leading, spacing: DS.space6) {
                automationFieldLabel("Default intent")
                defaultIntentMenu
            }

            Text("Tasks carrying these intents or words feed the ring automatically.")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func automationFieldLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.caption.weight(.medium))
            .foregroundStyle(DS.textSecondary)
    }

    private var intentGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: DS.space6)], spacing: DS.space6) {
            ForEach(TaskIntent.allCases.filter { $0 != .general && $0 != .custom }, id: \.self) { intent in
                intentChip(intent)
            }
        }
    }

    private func intentChip(_ intent: TaskIntent) -> some View {
        let isSelected = draft.mappedIntents.contains(intent)
        return Button {
            if isSelected {
                draft.mappedIntents.remove(intent)
            } else {
                draft.mappedIntents.insert(intent)
            }
        } label: {
            HStack(spacing: DS.space4) {
                Image(systemName: intent.iconName)
                    .font(DS.caption2.weight(.medium))
                Text(intent.displayName)
                    .font(DS.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? DS.text : DS.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(isSelected ? intent.color.opacity(0.10) : DS.glassInputFill, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? intent.color.opacity(0.28) : DS.glassBorder, lineWidth: 0.5)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isSelected ? "Stop counting \(intent.displayName) tasks" : "Count \(intent.displayName) tasks")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var keywordField: some View {
        TextField("write, draft, article", text: $draft.keywordInput)
            .textFieldStyle(.plain)
            .font(DS.callout)
            .foregroundStyle(DS.text)
            .padding(.horizontal, DS.space10)
            .frame(height: 30)
            .dsGlassInput(cornerRadius: 8)
            .help("Comma-separated words — any of them in a task title links the task here")
    }

    private var defaultIntentMenu: some View {
        Menu {
            Button("Unassigned") { draft.defaultIntentUUID = nil }
            ForEach(availableIntents, id: \.id) { intent in
                Button(intent.title) { draft.defaultIntentUUID = intent.id }
            }
        } label: {
            HStack(spacing: DS.space6) {
                let selected = availableIntents.first(where: { $0.id == draft.defaultIntentUUID })
                Text(selected?.title ?? "Unassigned")
                    .font(DS.callout)
                    .foregroundStyle(selected == nil ? DS.textMuted : DS.text)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
            .padding(.horizontal, DS.space10)
            .frame(height: 30)
            .dsGlassInput(cornerRadius: 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("The intent stamped on tasks created from this habit")
    }

    // MARK: Check-ins

    private var checkInsRow: some View {
        Toggle(isOn: $draft.allowManualCompletion) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Manual check-ins")
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                Text("Log progress without a linked task.")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textSecondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(DS.accent)
    }

    // MARK: Built-in summary (read-only)

    private var builtInSummary: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            builtInFactRow(icon: "target", text: builtInGoalSummary)
            builtInFactRow(icon: "bolt", text: "Completes from tasks and focus sessions.")

            Text("Built-in habits keep their core identity fixed so the command center stays coherent.")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space16)
    }

    private var builtInGoalSummary: String {
        if draft.isTimeBased { return "\(draft.dailyTargetMinutes) minutes per day." }
        if draft.dailyTargetCount == 1 { return "Once per day." }
        return "\(draft.dailyTargetCount) times per day."
    }

    private func builtInFactRow(icon: String, text: String) -> some View {
        HStack(spacing: DS.space8) {
            Image(systemName: icon)
                .font(DS.caption.weight(.medium))
                .foregroundStyle(DS.textMuted)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(text)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
        }
    }

    // MARK: Footer (pinned — never scrolls, never wraps)

    private var footerHairline: some View {
        Rectangle()
            .fill(DS.sepiaBorder.opacity(0.7))
            .frame(height: 1)
    }

    private var footer: some View {
        HStack(spacing: DS.space10) {
            if isBuiltIn {
                if let onDisable {
                    Button("Disable", action: onDisable)
                        .buttonStyle(.plain)
                        .font(DS.callout)
                        .foregroundStyle(DS.textSecondary)
                        .help("Hide this built-in habit")
                }
            } else if habit != nil {
                overflowMenu
            }

            Spacer(minLength: 0)

            Button(isBuiltIn ? "Done" : "Cancel", action: onDismiss)
                .buttonStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .fixedSize()
                .help("Close without saving (Esc)")

            if !isBuiltIn {
                saveButton
            }
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space12)
    }

    private var saveButton: some View {
        Button(action: { onSave(draft) }) {
            Text(habit == nil ? "Create" : "Save")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(canSave ? DS.textOnAccent : DS.textMuted)
                .padding(.horizontal, DS.space16)
                .frame(height: 30)
                .background(canSave ? DS.accent : DS.glassInputFill, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(canSave ? Color.clear : DS.glassBorder, lineWidth: 0.5)
                )
                .fixedSize()
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .keyboardShortcut(.return, modifiers: .command)
        .help(habit == nil ? "Create habit (⌘↩)" : "Save changes (⌘↩)")
    }

    private var overflowMenu: some View {
        Menu {
            Button("Move Up", systemImage: "arrow.up") { onMoveUp?() }
            Button("Move Down", systemImage: "arrow.down") { onMoveDown?() }
            if let onOpenLibrary {
                Divider()
                Button("Habit Library…", systemImage: "books.vertical") { onOpenLibrary() }
            }
            Divider()
            Button("Archive Habit", systemImage: "archivebox", role: .destructive) { onArchive?() }
        } label: {
            Image(systemName: "ellipsis")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 26, height: 26)
                .background(DS.glassInputFill, in: Circle())
                .overlay(Circle().stroke(DS.glassBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More actions")
        .accessibilityLabel("More actions")
    }
}

// MARK: - Shared chip chassis

/// One selectable chip voice for the composer: soft accent wash + hairline
/// when selected, warm input fill otherwise, a hover lift on the pointer —
/// never a solid fill (Law 11).
private struct HabitComposerChip<Content: View>: View {
    let isSelected: Bool
    let help: String
    let accessibilityLabel: String
    var isAccessibilitySelected: Bool? = nil
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            content()
                .background(isSelected ? DS.accentSoft : DS.glassInputFill, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? DS.accent.opacity(0.42) : DS.glassBorder, lineWidth: 0.5)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.04 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits((isAccessibilitySelected ?? isSelected) ? [.isSelected] : [])
    }
}

/// The assistant-menu section voice (CosmoAssistantMenuSectionHeader's type,
/// without its list insets — the composer manages its own spacing).
private struct HabitComposerSectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(DS.caption2.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(DS.textMuted)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Library

struct CommandCenterHabitLibraryComposer: View {
    let customHabits: [HabitDefinition]
    let builtInHabits: [(definition: HabitDefinition, isEnabled: Bool)]
    let onToggleBuiltIn: (String, Bool) -> Void
    let onCreate: () -> Void
    let onEdit: (HabitDefinition) -> Void
    let onClose: () -> Void

    var body: some View {
        CosmoGlassPanel(role: .globalSidebar, cornerRadius: 16) {
            VStack(spacing: 0) {
                header
                CosmoGradientDivider()
                ViewThatFits(in: .vertical) {
                    listColumn
                    ScrollView(.vertical, showsIndicators: false) { listColumn }
                }
            }
        }
        .dsFloatingShadow()
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        HStack(spacing: DS.space10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DS.accentSoft)
                    .frame(width: 26, height: 26)
                Image(systemName: "repeat")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.accent)
            }
            .accessibilityHidden(true)

            Text("Habit Library")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(DS.text)

            Spacer(minLength: 0)

            Text("\(customHabits.count + builtInHabits.count)")
                .font(DS.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(DS.textMuted)
                .contentTransition(.numericText())
                .accessibilityLabel("\(customHabits.count + builtInHabits.count) habits")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(DS.glassInputFill, in: Circle())
                    .overlay(Circle().stroke(DS.glassBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .accessibilityLabel("Close habit library")
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space10)
    }

    private var listColumn: some View {
        VStack(spacing: 0) {
            CosmoAssistantMenuSectionHeader(title: "CUSTOM")

            if customHabits.isEmpty {
                emptyCustomRow
            } else {
                ForEach(customHabits, id: \.id) { habit in
                    HabitLibraryRow(habit: habit) { onEdit(habit) }
                }
            }

            newHabitRow

            CosmoAssistantMenuSectionHeader(title: "BUILT-IN")

            ForEach(builtInHabits, id: \.definition.id) { item in
                builtInRow(item)
            }
        }
        .padding(.vertical, DS.space6)
    }

    private var emptyCustomRow: some View {
        Text("Start one and map it to the kinds of work you want to reinforce.")
            .font(DS.caption)
            .foregroundStyle(DS.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space6)
    }

    private var newHabitRow: some View {
        HabitLibraryActionRow(
            icon: "plus",
            title: "New Habit",
            help: "Create a habit",
            action: onCreate
        )
    }

    private func builtInRow(_ item: (definition: HabitDefinition, isEnabled: Bool)) -> some View {
        HStack(spacing: DS.space10) {
            HabitLibraryMark(habit: item.definition, dimmed: !item.isEnabled)

            Text(item.definition.displayTitle)
                .font(DS.callout.weight(.medium))
                .foregroundStyle(item.isEnabled ? DS.text : DS.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Toggle(
                "",
                isOn: Binding(
                    get: { item.isEnabled },
                    set: { onToggleBuiltIn(item.definition.id, $0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(item.definition.accent)
            .labelsHidden()
            .help(item.isEnabled ? "Hide \(item.definition.displayTitle)" : "Show \(item.definition.displayTitle)")
            .accessibilityLabel("Show \(item.definition.displayTitle)")
        }
        .padding(.horizontal, DS.space12)
        .frame(height: 34)
        .accessibilityElement(children: .combine)
    }
}

/// One dense library row: identity mark, label, a mono cadence hint, and the
/// chevron door — the assistant-menu row grammar with a habit's marks.
private struct HabitLibraryRow: View {
    let habit: HabitDefinition
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space10) {
                HabitLibraryMark(habit: habit)

                Text(habit.displayTitle)
                    .font(DS.callout.weight(.medium))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(cadenceHint)
                    .font(DS.caption.monospaced())
                    .foregroundStyle(DS.textMuted.opacity(0.8))

                Image(systemName: "chevron.right")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
            }
            .padding(.horizontal, DS.space10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? DS.accentSoft : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isHovered ? DS.accent.opacity(0.22) : Color.clear, lineWidth: 1)
                    )
                    .padding(.horizontal, DS.space6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Edit \(habit.displayTitle)")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var cadenceHint: String {
        if habit.isTimeBased { return "\(habit.dailyTargetMinutes ?? 30)m/day" }
        return "\(habit.dailyTargetCount)×/day"
    }
}

private struct HabitLibraryActionRow: View {
    let icon: String
    let title: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space10) {
                Image(systemName: icon)
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.accent)
                    .frame(width: 20)

                Text(title)
                    .font(DS.callout.weight(.medium))
                    .foregroundStyle(DS.accent)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.space10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? DS.accentSoft : Color.clear)
                    .padding(.horizontal, DS.space6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

/// The 20pt identity slot: typed/keyword emoji, else the picked SF icon in
/// the habit's accent — the same resolution order every habit surface uses.
private struct HabitLibraryMark: View {
    let habit: HabitDefinition
    var dimmed: Bool = false

    var body: some View {
        Group {
            if let emoji = habit.identityMark {
                Text(emoji)
                    .font(.system(size: 13))
            } else {
                Image(systemName: habit.icon)
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(habit.accent.opacity(dimmed ? 0.5 : 1))
            }
        }
        .frame(width: 20, alignment: .center)
        .opacity(dimmed ? 0.6 : 1)
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Habit Composer") {
    CommandCenterHabitComposer(
        habit: HabitDefinition.previewHabit(),
        onSave: { _ in },
        onOpenLibrary: {},
        onDismiss: {}
    )
    .frame(width: 360)
    .padding()
    .background(DS.bg)
}

#Preview("Habit Library") {
    CommandCenterHabitLibraryComposer(
        customHabits: [HabitDefinition.previewHabit()],
        builtInHabits: [(HabitDefinition.previewHabit(), true)],
        onToggleBuiltIn: { _, _ in },
        onCreate: {},
        onEdit: { _ in },
        onClose: {}
    )
    .frame(width: 340, height: 480)
    .padding()
    .background(DS.bg)
}
