// CosmoOS/Settings/ProfileStudio/ProfileTasteSection.swift
// The TASTE section of the Profile Studio — the distilled beliefs the writing
// engines actually follow, surfaced for the user to own: edit (→ pinned),
// pin, strike (tombstone — never returns), and author rules directly.
// Provenance is honest: every belief shows how many signals ground it, and
// the section popover breaks the scope's signals down by kind.

import SwiftUI

struct ProfileTasteSection: View {
    @Bindable var store: ProfileStudioStore

    @State private var beliefs: [TasteBelief] = []
    @State private var profileVersion = 0
    @State private var signalCounts: [(kind: String, count: Int)] = []
    @State private var editingBeliefID: String?
    @State private var editingText = ""
    @State private var isAddingRule = false
    @State private var newRuleText = ""
    @State private var newRuleCategory = "voice"
    @State private var showStruck = false
    @State private var showProvenance = false

    private static let categories = ["voice", "structure", "hooks", "format", "cta"]

    private var clientUuid: String? { store.atom?.uuid }
    private var active: [TasteBelief] { beliefs.filter { !$0.struck } }
    private var struck: [TasteBelief] { beliefs.filter(\.struck) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            header
            SettingsGroupedBox {
                if active.isEmpty && !isAddingRule {
                    emptyTeachingRow
                } else {
                    beliefRows
                }
                SettingsRowDivider()
                addRuleRow
            }
            if !struck.isEmpty {
                struckFootnote
            }
        }
        .task(id: store.atom?.uuid) { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .cosmoTasteChanged)) { _ in
            Task { await reload() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.space8) {
            SettingsSectionHeader(label: "TASTE", detail: headerDetail)
            Button {
                showProvenance.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Where these beliefs come from")
            .accessibilityLabel("Taste provenance")
            .popover(isPresented: $showProvenance, arrowEdge: .bottom) {
                provenancePopover
            }
        }
    }

    private var headerDetail: String {
        if active.isEmpty { return "grown from your real signals" }
        return "\(active.count) beliefs · v\(profileVersion)"
    }

    private var provenancePopover: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text("Grounded in \(signalCounts.reduce(0) { $0 + $1.count }) signals")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(DS.text)
            ForEach(signalCounts, id: \.kind) { entry in
                HStack(spacing: DS.space8) {
                    Image(systemName: Self.icon(forKind: entry.kind))
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    Text(Self.label(forKind: entry.kind))
                        .font(DS.caption)
                        .foregroundStyle(DS.textSecondary)
                    Spacer(minLength: DS.space12)
                    Text("\(entry.count)")
                        .font(DS.caption.monospacedDigit())
                        .foregroundStyle(DS.textMuted)
                }
            }
            if signalCounts.isEmpty {
                Text("No signals yet — accepted edits, swipe studies, and performance entries land here.")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Pinned rules are yours — the distiller never rewrites them. Struck beliefs never return.")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.space4)
        }
        .padding(DS.space16)
        .frame(width: 300, alignment: .leading)
    }

    // MARK: - Belief rows

    private var beliefRows: some View {
        ForEach(Array(active.enumerated()), id: \.element.id) { index, belief in
            if index > 0 { SettingsRowDivider() }
            TasteBeliefRow(
                belief: belief,
                isEditing: editingBeliefID == belief.id,
                editingText: $editingText,
                onBeginEdit: {
                    editingBeliefID = belief.id
                    editingText = belief.text
                },
                onCommitEdit: { commitEdit(belief) },
                onCancelEdit: { editingBeliefID = nil },
                onTogglePin: {
                    Task { await TasteStore.setPinned(id: belief.id, pinned: !belief.pinned, clientUuid: clientUuid) }
                },
                onStrike: {
                    Task { await TasteStore.strikeBelief(id: belief.id, clientUuid: clientUuid) }
                }
            )
        }
    }

    private func commitEdit(_ belief: TasteBelief) {
        let text = editingText
        editingBeliefID = nil
        guard text.trimmingCharacters(in: .whitespacesAndNewlines) != belief.text else { return }
        Task { await TasteStore.editBelief(id: belief.id, newText: text, clientUuid: clientUuid) }
    }

    // MARK: - Empty + add-rule

    private var emptyTeachingRow: some View {
        HStack(spacing: DS.space10) {
            Image(systemName: "leaf")
                .font(DS.body)
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            Text("Taste grows from your edits, swipe studies, and published numbers — or add a rule to plant it deliberately.")
                .font(DS.callout)
                .foregroundStyle(DS.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DS.space10)
        .padding(.horizontal, DS.space12)
    }

    private var addRuleRow: some View {
        Group {
            if isAddingRule {
                addRuleEditor
            } else {
                Button {
                    withAnimation(ProMotionSprings.snappy) { isAddingRule = true }
                } label: {
                    Label("Add rule", systemImage: "plus")
                        .font(DS.callout)
                        .foregroundStyle(DS.textSecondary)
                        .padding(.vertical, DS.space8)
                        .padding(.horizontal, DS.space12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Author a pinned rule the writing engines follow strictly")
            }
        }
    }

    private var addRuleEditor: some View {
        HStack(spacing: DS.space8) {
            TextField("e.g. Never open with a rhetorical question", text: $newRuleText)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .onSubmit { commitNewRule() }
            Picker("Category", selection: $newRuleCategory) {
                ForEach(Self.categories, id: \.self) { Text($0.capitalized).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            Button("Add") { commitNewRule() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(newRuleText.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    isAddingRule = false
                    newRuleText = ""
                }
            } label: {
                Image(systemName: "xmark")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel("Cancel new rule")
        }
        .padding(.vertical, DS.space8)
        .padding(.horizontal, DS.space12)
    }

    private func commitNewRule() {
        let text = newRuleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 8 else { return }
        newRuleText = ""
        withAnimation(ProMotionSprings.snappy) { isAddingRule = false }
        Task { await TasteStore.addPinnedRule(text, category: newRuleCategory, clientUuid: clientUuid) }
    }

    // MARK: - Struck footnote

    private var struckFootnote: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Button {
                withAnimation(ProMotionSprings.snappy) { showStruck.toggle() }
            } label: {
                HStack(spacing: DS.space4) {
                    Image(systemName: showStruck ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Text("\(struck.count) struck")
                        .font(DS.caption)
                }
                .foregroundStyle(DS.textMuted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Beliefs you removed — they never return on their own")
            if showStruck {
                ForEach(struck) { belief in
                    HStack(spacing: DS.space8) {
                        Text(belief.text)
                            .font(DS.caption)
                            .strikethrough()
                            .foregroundStyle(DS.textMuted)
                            .lineLimit(2)
                        Spacer(minLength: DS.space8)
                        Button("Restore") {
                            Task {
                                await TasteStore.mutateBeliefs(clientUuid: clientUuid) { beliefs in
                                    guard let index = beliefs.firstIndex(where: { $0.id == belief.id }) else { return }
                                    beliefs[index].struck = false
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textSecondary)
                    }
                    .padding(.leading, DS.space16)
                }
            }
        }
        .padding(.leading, DS.space4)
    }

    // MARK: - Data

    private func reload() async {
        let scope = clientUuid
        let profile = await TasteStore.profile(clientUuid: scope)
        let counts = await TasteStore.signalKindCounts(clientUuid: scope)
        await MainActor.run {
            beliefs = profile?.beliefs ?? []
            profileVersion = profile?.version ?? 0
            signalCounts = counts
        }
    }

    static func icon(forKind kind: String) -> String {
        switch kind {
        case "edit_accepted": return "checkmark.circle"
        case "edit_rejected": return "xmark.circle"
        case "perf_entry": return "chart.line.uptrend.xyaxis"
        case "explicit_rule": return "pin"
        case "swipe_study": return "rectangle.stack"
        default: return "sparkle"
        }
    }

    static func label(forKind kind: String) -> String {
        switch kind {
        case "edit_accepted": return "Accepted edits"
        case "edit_rejected": return "Rejected suggestions"
        case "perf_entry": return "Performance entries"
        case "explicit_rule": return "Your rules"
        case "swipe_study": return "Swipe studies"
        default: return kind
        }
    }
}

// MARK: - Belief row

private struct TasteBeliefRow: View {
    let belief: TasteBelief
    let isEditing: Bool
    @Binding var editingText: String
    let onBeginEdit: () -> Void
    let onCommitEdit: () -> Void
    let onCancelEdit: () -> Void
    let onTogglePin: () -> Void
    let onStrike: () -> Void

    @State private var isHovered = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.space10) {
            categoryChip
            beliefBody
            Spacer(minLength: DS.space8)
            trailing
        }
        .padding(.vertical, DS.space8)
        .padding(.horizontal, DS.space12)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(ProMotionSprings.gentle) { isHovered = hovering }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(belief.category) belief: \(belief.text)\(belief.pinned ? ", pinned" : "")")
    }

    private var categoryChip: some View {
        Text(belief.category.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(DS.textMuted)
            .frame(width: 62, alignment: .leading)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var beliefBody: some View {
        if isEditing {
            TextField("Belief", text: $editingText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .focused($fieldFocused)
                .onSubmit(onCommitEdit)
                .onExitCommand(perform: onCancelEdit)
                .onAppear { fieldFocused = true }
        } else {
            Text(belief.text)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture(count: 2, perform: onBeginEdit)
                .help("Double-click to edit (editing pins the belief)")
        }
    }

    private var trailing: some View {
        HStack(spacing: DS.space6) {
            if belief.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(DS.accent)
                    .accessibilityHidden(true)
            } else {
                confidenceDot
            }
            if isHovered && !isEditing {
                hoverActions
            }
        }
        .frame(minWidth: 64, alignment: .trailing)
    }

    private var confidenceDot: some View {
        Circle()
            .fill(DS.accent.opacity(0.25 + belief.confidence * 0.55))
            .frame(width: 6, height: 6)
            .help(String(format: "Confidence %.0f%% · %d signals", belief.confidence * 100, belief.sources))
            .accessibilityHidden(true)
    }

    private var hoverActions: some View {
        HStack(spacing: DS.space4) {
            Button(action: onTogglePin) {
                Image(systemName: belief.pinned ? "pin.slash" : "pin")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(belief.pinned ? "Unpin — the distiller may refine it again" : "Pin — never auto-modified")
            .accessibilityLabel(belief.pinned ? "Unpin belief" : "Pin belief")

            Button(action: onStrike) {
                Image(systemName: "strikethrough")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Strike — removed for good, never re-derived")
            .accessibilityLabel("Strike belief")
        }
        .transition(.opacity)
    }
}
