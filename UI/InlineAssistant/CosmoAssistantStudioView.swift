// CosmoOS/UI/InlineAssistant/CosmoAssistantStudioView.swift
// The Assistant Studio — skills, the personality character sheet, and the
// assistant's scorecard, spoken in the Settings surface grammar: flat header
// over a hairline, small-caps section headers with quiet counts, grouped
// boxes with inset dividers, and an in-place editor face (no stacked sheets).

import SwiftUI

// MARK: - Metrics

/// Session-scoped scorecard for the inline assistant. These numbers are the
/// definition of "most efficient assistant" — not vibes: time-to-first-token,
/// proposal latency, accept/conflict rates, and the prompt-cache read ratio.
@MainActor
@Observable
final class CosmoInlineAssistantMetrics {
    static let shared = CosmoInlineAssistantMetrics()

    private(set) var requestCount = 0
    private(set) var ttftSamplesMs: [Int] = []
    private(set) var proposalLatencySamplesMs: [Int] = []
    private(set) var proposalsStaged = 0
    private(set) var operationsAccepted = 0
    private(set) var operationsRejected = 0
    private(set) var operationsConflicted = 0
    private(set) var paneAnswers = 0

    private var activeRequestStart: Date?
    private var recordedFirstTokenForActiveRequest = false

    func requestStarted() {
        requestCount += 1
        activeRequestStart = Date()
        recordedFirstTokenForActiveRequest = false
    }

    func firstAnswerTokenArrived() {
        guard let start = activeRequestStart, !recordedFirstTokenForActiveRequest else { return }
        recordedFirstTokenForActiveRequest = true
        ttftSamplesMs.append(Int(Date().timeIntervalSince(start) * 1000))
    }

    func proposalStaged() {
        proposalsStaged += 1
        if let start = activeRequestStart {
            proposalLatencySamplesMs.append(Int(Date().timeIntervalSince(start) * 1000))
        }
    }

    func paneAnswerDelivered() {
        paneAnswers += 1
    }

    func operationResolved(status: CosmoProposalStatus) {
        switch status {
        case .accepted, .applied: operationsAccepted += 1
        case .rejected: operationsRejected += 1
        case .conflicted: operationsConflicted += 1
        case .pending, .reverted: break
        }
    }

    var averageTTFTMs: Int? {
        ttftSamplesMs.isEmpty ? nil : ttftSamplesMs.reduce(0, +) / ttftSamplesMs.count
    }

    var averageProposalLatencyMs: Int? {
        proposalLatencySamplesMs.isEmpty ? nil : proposalLatencySamplesMs.reduce(0, +) / proposalLatencySamplesMs.count
    }

    /// Accepted / (accepted + rejected). Conflicts are tracked separately —
    /// they measure locator staleness, not output quality.
    var acceptRate: Double? {
        let decided = operationsAccepted + operationsRejected
        guard decided > 0 else { return nil }
        return Double(operationsAccepted) / Double(decided)
    }

    var conflictRate: Double? {
        let total = operationsAccepted + operationsRejected + operationsConflicted
        guard total > 0 else { return nil }
        return Double(operationsConflicted) / Double(total)
    }
}

// MARK: - Studio shell

struct CosmoAssistantStudioView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case skills = "Skills"
        case personality = "Personality"
        case metrics = "Metrics"

        var id: String { rawValue }
    }

    /// A prefilled skill draft ("promote this run to a skill") — the shell
    /// opens straight into the editor face with it.
    var initialSkillDraft: CosmoInlineSkillDefinition? = nil
    let onDismiss: () -> Void

    @State private var selectedTab: Tab = .skills
    @State private var skills: [CosmoInlineSkillDefinition] = []
    @State private var acceptStats: [String: (accepted: Int, total: Int)] = [:]
    @State private var editingSkill: CosmoInlineSkillDefinition?
    @State private var didPresentInitialDraft = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let store = CosmoInlineSkillStore.defaultForRuntime()

    private var isEditing: Bool { editingSkill != nil }

    var body: some View {
        ZStack {
            listFace
                .opacity(isEditing ? 0 : 1)
                .scaleEffect(isEditing ? 0.98 : 1)
                .allowsHitTesting(!isEditing)

            if let editingSkill {
                editorFace(for: editingSkill)
                    .transition(reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 1.02)))
            }
        }
        .frame(width: 920, height: 680)
        .background(DS.bg)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : ProMotionSprings.gentle, value: editingSkill?.id)
        .task {
            reload()
            if let initialSkillDraft, !didPresentInitialDraft {
                didPresentInitialDraft = true
                editingSkill = initialSkillDraft
            }
        }
    }

    // MARK: List face

    private var listFace: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(DS.sidebarMaterialBorder.opacity(0.45))
                .frame(height: 1)
            tabContent
        }
    }

    private var header: some View {
        HStack(spacing: DS.space12) {
            Text("Assistant Studio")
                .font(DS.headline)
                .foregroundStyle(DS.text)
                .lineLimit(1)

            Spacer()

            CosmoAssistantStudioTabSwitcher(selectedTab: $selectedTab)

            FloatingOverlayCloseButton(action: onDismiss)
                .keyboardShortcut(isEditing ? nil : KeyboardShortcut(.escape, modifiers: []))
                .help("Close Assistant Studio (Esc)")
                .accessibilityLabel("Close Assistant Studio")
        }
        .padding(.horizontal, DS.space24)
        .padding(.vertical, DS.space16)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .skills:
            CosmoStudioSkillListTab(
                customSkills: skills.filter { !$0.isBuiltin },
                builtinSkills: skills.filter(\.isBuiltin),
                acceptStats: acceptStats,
                store: store,
                onEdit: { editingSkill = $0 },
                onCreate: { createSkill() },
                onToggleEnabled: { skill, enabled in setEnabled(skill, enabled) },
                onDelete: { skill in
                    store.delete(id: skill.id)
                    reload()
                }
            )
        case .personality:
            CosmoStudioPersonalityTab()
        case .metrics:
            CosmoStudioMetricsTab()
        }
    }

    // MARK: Editor face

    private func editorFace(for skill: CosmoInlineSkillDefinition) -> some View {
        CosmoStudioSkillEditorFace(
            skill: skill,
            onSave: { updated in
                var saved = updated
                saved.updatedAt = Date()
                store.save(saved)
                editingSkill = nil
                reload()
            },
            onCancel: { editingSkill = nil }
        )
    }

    // MARK: Data

    private func reload() {
        let registry = CosmoInlineSkillRegistry(store: store)
        skills = store.customSkills() + registry.builtInSkills
        Task { await loadAcceptStats() }
    }

    private func loadAcceptStats() async {
        let events = await AgentOutcomeTracker.shared.getRecentEvents(
            category: .suggestionAcceptance,
            limit: 300
        )
        var stats: [String: (accepted: Int, total: Int)] = [:]
        for event in events {
            guard let category = event.context["category"],
                  category.hasPrefix("skill:") else { continue }
            let skillID = String(category.dropFirst("skill:".count))
            var entry = stats[skillID] ?? (0, 0)
            entry.total += 1
            if event.context["accepted"] == "true" { entry.accepted += 1 }
            stats[skillID] = entry
        }
        acceptStats = stats
    }

    private func setEnabled(_ skill: CosmoInlineSkillDefinition, _ enabled: Bool) {
        var updated = skill
        updated.isEnabled = enabled
        updated.updatedAt = Date()
        store.save(updated)
        reload()
    }

    private func createSkill() {
        guard editingSkill == nil else { return }
        editingSkill = Self.newSkillTemplate()
    }

    static func editableCopy(of builtin: CosmoInlineSkillDefinition) -> CosmoInlineSkillDefinition {
        var copy = builtin
        copy.id = UUID().uuidString
        copy.name = "\(builtin.name) Copy"
        copy.isBuiltin = false
        copy.createdAt = Date()
        copy.updatedAt = Date()
        return copy
    }

    static func newSkillTemplate() -> CosmoInlineSkillDefinition {
        CosmoInlineSkillDefinition.custom(
            name: "Untitled Skill",
            icon: "wand.and.stars",
            summary: "Describe what this skill does in one sentence.",
            triggerPhrases: [],
            route: .action,
            preferredModelTier: .gemini35Flash,
            requiredContext: [.activeSurface],
            toolBundles: [.workspaceEditing, .writing],
            instructions: [
                "Use the active surface and the skill examples before producing output.",
                "Stage visible workspace changes as reviewed diffs."
            ],
            outputContract: "reviewed_diff",
            tokenBudget: 1600,
            requiresReviewedDiff: true,
            panePolicy: .neverForAction,
            triggerDescription: "Use this skill when the user asks for this exact workflow.",
            examples: [
                CosmoInlineSkillExample(
                    input: "Paste one realistic request this skill should handle.",
                    idealOutput: "Paste or write the shape of a great result."
                )
            ],
            verification: "The output matches the example shape and does not invent missing facts."
        )
    }
}

// MARK: - Tab switcher

private struct CosmoAssistantStudioTabSwitcher: View {
    @Binding var selectedTab: CosmoAssistantStudioView.Tab

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(CosmoAssistantStudioView.Tab.allCases.enumerated()), id: \.element.id) { index, tab in
                segment(tab, index: index)
            }
        }
        .padding(3)
        .background(DS.glassSectionFill, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(DS.glassBorder, lineWidth: 1))
        .animation(ProMotionSprings.snappy, value: selectedTab)
    }

    private func segment(_ tab: CosmoAssistantStudioView.Tab, index: Int) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            Text(tab.rawValue)
                .font(DS.callout)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? DS.text : DS.textMuted)
                .frame(width: 92)
                .padding(.vertical, DS.space6)
                .background(
                    isSelected ? AnyShapeStyle(DS.surfaceElevated) : AnyShapeStyle(Color.clear),
                    in: Capsule(style: .continuous)
                )
                .overlay {
                    if isSelected {
                        Capsule(style: .continuous)
                            .stroke(DS.border, lineWidth: 0.5)
                    }
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
        .help("\(tab.rawValue) (⌘\(index + 1))")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Skills tab

private struct CosmoStudioSkillListTab: View {
    let customSkills: [CosmoInlineSkillDefinition]
    let builtinSkills: [CosmoInlineSkillDefinition]
    let acceptStats: [String: (accepted: Int, total: Int)]
    let store: CosmoInlineSkillStore
    let onEdit: (CosmoInlineSkillDefinition) -> Void
    let onCreate: () -> Void
    let onToggleEnabled: (CosmoInlineSkillDefinition, Bool) -> Void
    let onDelete: (CosmoInlineSkillDefinition) -> Void

    @State private var hasAppeared = false
    @State private var routerTestPhrase = ""
    @State private var routerResults: [String] = []
    @State private var isRouting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.space24) {
                customSection
                    .studioCascade(hasAppeared: hasAppeared, index: 0, reduceMotion: reduceMotion)
                builtinSection
                    .studioCascade(hasAppeared: hasAppeared, index: 1, reduceMotion: reduceMotion)
                routerSection
                    .studioCascade(hasAppeared: hasAppeared, index: 2, reduceMotion: reduceMotion)
            }
            .padding(DS.space24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .onAppear {
            // Flip one frame after mount so the cascade actually animates.
            Task { @MainActor in
                withAnimation(ProMotionSprings.gentle) { hasAppeared = true }
            }
        }
    }

    // MARK: Custom skills

    private var customSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            SettingsSectionHeader(label: "CUSTOM SKILLS", detail: "\(customSkills.count)")
            SettingsGroupedBox {
                if customSkills.isEmpty {
                    emptyTeachingRow
                } else {
                    customRows
                }
                SettingsRowDivider(inset: 0)
                addRow
            }
        }
    }

    private var customRows: some View {
        let lastID = customSkills.last?.id
        return VStack(spacing: 0) {
            ForEach(customSkills) { skill in
                CosmoStudioSkillRow(
                    skill: skill,
                    detail: rowDetail(for: skill),
                    isBuiltin: false,
                    onTap: { onEdit(skill) },
                    onToggleEnabled: { onToggleEnabled(skill, $0) },
                    onDelete: { onDelete(skill) }
                )
                if skill.id != lastID {
                    SettingsRowDivider()
                }
            }
        }
    }

    private var emptyTeachingRow: some View {
        VStack(spacing: DS.space6) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            Text("Teach Cosmo a workflow")
                .font(DS.callout.weight(.medium))
                .foregroundStyle(DS.textSecondary)
            Text("A skill is a routable mini-agent: trigger language, context, an example, and a verification rule. Create one here or promote a great run from the assistant.")
                .font(DS.footnote)
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space24)
        .padding(.horizontal, DS.space16)
    }

    private var addRow: some View {
        HStack {
            Button(action: onCreate) {
                HStack(spacing: DS.space4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                    Text("New skill")
                        .font(DS.caption)
                }
                .foregroundStyle(DS.accent)
                .padding(.horizontal, DS.space10)
                .padding(.vertical, DS.space6)
                .background(DS.accentSoft, in: Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .cosmoClickCursor()
            .keyboardShortcut("n", modifiers: .command)
            .help("Create a skill (⌘N)")
            .accessibilityLabel("Create new skill")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space10)
    }

    // MARK: Built-in skills

    private var builtinSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            SettingsSectionHeader(label: "BUILT-IN SKILLS", detail: "\(builtinSkills.count)")
            SettingsGroupedBox {
                builtinRows
            }
            Text("Built-ins ship with Cosmo. Open one to inspect its prompt and save a custom copy you can edit.")
                .font(DS.footnote)
                .foregroundStyle(DS.textMuted)
        }
    }

    private var builtinRows: some View {
        let lastID = builtinSkills.last?.id
        return VStack(spacing: 0) {
            ForEach(builtinSkills) { skill in
                CosmoStudioSkillRow(
                    skill: skill,
                    detail: rowDetail(for: skill),
                    isBuiltin: true,
                    onTap: { onEdit(CosmoAssistantStudioView.editableCopy(of: skill)) }
                )
                if skill.id != lastID {
                    SettingsRowDivider()
                }
            }
        }
    }

    private func rowDetail(for skill: CosmoInlineSkillDefinition) -> String {
        var parts = [skill.displayedModelLabel]
        parts.append(skill.route == .action ? "Diff" : "Answer")
        if let stat = acceptStats[skill.id], stat.total > 0 {
            parts.append("\(Int(Double(stat.accepted) / Double(stat.total) * 100))% accepted")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Router test

    private var routerSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            SettingsSectionHeader(label: "TEST ROUTING")
            SettingsGroupedBox {
                routerInputRow
                if isRouting || !routerResults.isEmpty {
                    SettingsRowDivider(inset: 0)
                    routerResultRows
                }
            }
            Text("Type a request the way you'd ask it — see which skill the router picks before you rely on it.")
                .font(DS.footnote)
                .foregroundStyle(DS.textMuted)
        }
    }

    private var routerInputRow: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)

            TextField("Try a request…", text: $routerTestPhrase)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .onSubmit { runRouterTest() }
                .accessibilityLabel("Routing test phrase")

            Button(action: runRouterTest) {
                Text("Route")
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(canRoute ? DS.accent : DS.textMuted)
                    .padding(.horizontal, DS.space10)
                    .padding(.vertical, DS.space6)
                    .background(canRoute ? AnyShapeStyle(DS.accentSoft) : AnyShapeStyle(DS.glassSectionFill), in: Capsule(style: .continuous))
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .cosmoClickCursor()
            .disabled(!canRoute)
            .help("Test skill routing")
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space10)
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var routerResultRows: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            if isRouting {
                Text("Routing…")
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
            } else {
                ForEach(routerResults, id: \.self) { line in
                    Text(line)
                        .font(DS.footnote)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canRoute: Bool {
        !routerTestPhrase.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func runRouterTest() {
        let phrase = routerTestPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }
        withAnimation(ProMotionSprings.snappy) { isRouting = true }
        Task {
            let suggestion = await CosmoInlineSkillAutoRouter.shared.suggestion(
                for: phrase,
                registry: CosmoInlineSkillRegistry(store: store)
            )
            let plan = CosmoInlineAssistantSkillRuntime.plan(for: phrase, surfaceKind: nil)
            var lines: [String] = []
            if let suggestion {
                lines.append("Embedding router: \(suggestion.skillName) (score \(String(format: "%.2f", suggestion.score)))")
            } else {
                lines.append("Embedding router: no skill above threshold")
            }
            lines.append("Keyword plan: \(plan.primarySkill.name) → \(plan.route == .action ? "edit" : "answer") route")
            withAnimation(ProMotionSprings.snappy) {
                routerResults = lines
                isRouting = false
            }
        }
    }
}

// MARK: - Skill row

private struct CosmoStudioSkillRow: View {
    let skill: CosmoInlineSkillDefinition
    let detail: String
    let isBuiltin: Bool
    let onTap: () -> Void
    var onToggleEnabled: ((Bool) -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.space10) {
            tapTarget
            trailing
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space10)
        .frame(minHeight: 44)
        .background(isHovered ? DS.surfaceHover : Color.clear)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
    }

    private var tapTarget: some View {
        Button(action: onTap) {
            HStack(spacing: DS.space12) {
                iconChip
                titleBlock
                Spacer(minLength: DS.space8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isBuiltin ? "Inspect this built-in and save a custom copy" : "Edit \(skill.name)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(skill.name). \(skill.summary)")
    }

    private var iconChip: some View {
        Image(systemName: skill.icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(skill.isEnabled ? DS.accent : DS.textMuted)
            .frame(width: 28, height: 28)
            .background(
                (skill.isEnabled ? DS.accent : DS.textMuted).opacity(0.1),
                in: .rect(cornerRadius: 8, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(skill.name)
                .font(DS.callout.weight(.medium))
                .foregroundStyle(skill.isEnabled ? DS.text : DS.textMuted)
                .lineLimit(1)
            Text(skill.summary)
                .font(DS.footnote)
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)
        }
    }

    private var trailing: some View {
        HStack(spacing: DS.space10) {
            if isHovered, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.red.opacity(0.8))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete \(skill.name)")
                .accessibilityLabel("Delete \(skill.name)")
                .transition(.opacity)
            }

            Text(detail)
                .font(DS.footnote.monospacedDigit())
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)

            if let onToggleEnabled {
                Toggle("", isOn: Binding(get: { skill.isEnabled }, set: onToggleEnabled))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityLabel("\(skill.name) enabled")
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Skill editor face

private struct CosmoStudioSkillEditorFace: View {
    @State private var skill: CosmoInlineSkillDefinition
    let onSave: (CosmoInlineSkillDefinition) -> Void
    let onCancel: () -> Void

    @State private var triggerPhrasesText: String
    @State private var instructionsText: String
    @State private var tokenBudgetText: String
    @State private var exampleInputText: String
    @State private var exampleOutputText: String
    @State private var showPromptPreview = false
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let panePolicies: [CosmoInlineSkillPanePolicy] = [
        .neverForAction,
        .openForAnswer,
        .openForResearchBackedAction,
        .alwaysOpenWithResult
    ]

    init(
        skill: CosmoInlineSkillDefinition,
        onSave: @escaping (CosmoInlineSkillDefinition) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _skill = State(initialValue: skill)
        self.onSave = onSave
        self.onCancel = onCancel
        _triggerPhrasesText = State(initialValue: skill.triggerPhrases.joined(separator: ", "))
        _instructionsText = State(initialValue: skill.instructions.joined(separator: "\n"))
        _tokenBudgetText = State(initialValue: String(skill.tokenBudget))
        _exampleInputText = State(initialValue: skill.examples?.first?.input ?? "")
        _exampleOutputText = State(initialValue: skill.examples?.first?.idealOutput ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(DS.sidebarMaterialBorder.opacity(0.45))
                .frame(height: 1)
            form
        }
        .onAppear {
            Task { @MainActor in
                withAnimation(ProMotionSprings.gentle) { hasAppeared = true }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: DS.space8) {
            backButton
            iconMark(size: 24)
            Text(displayName)
                .font(DS.headline)
                .foregroundStyle(DS.text)
                .lineLimit(1)
            Spacer()
            saveButton
        }
        .padding(.horizontal, DS.space24)
        .padding(.vertical, DS.space16)
    }

    private var backButton: some View {
        Button(action: onCancel) {
            HStack(spacing: DS.space4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                Text("Skills")
                    .font(DS.callout)
            }
            .foregroundStyle(DS.textSecondary)
            .padding(.vertical, DS.space4)
            .padding(.trailing, DS.space6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.escape, modifiers: [])
        .help("Back without saving (Esc)")
    }

    private var saveButton: some View {
        Button(action: save) {
            Text("Save Skill")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(canSave ? DS.textOnAccent : DS.textMuted)
                .padding(.horizontal, DS.space16)
                .padding(.vertical, DS.space6)
                .background(
                    Capsule(style: .continuous)
                        .fill(canSave ? AnyShapeStyle(DS.accent) : AnyShapeStyle(DS.glassSectionFill))
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .cosmoClickCursor()
        .disabled(!canSave)
        .keyboardShortcut(.return, modifiers: .command)
        .help("Save skill (⌘↩)")
    }

    private var displayName: String {
        let trimmed = skill.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Skill" : trimmed
    }

    // MARK: Form

    private var form: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.space24) {
                identityStrip
                    .studioCascade(hasAppeared: hasAppeared, index: 0, reduceMotion: reduceMotion)
                behaviorSection
                    .studioCascade(hasAppeared: hasAppeared, index: 1, reduceMotion: reduceMotion)
                triggersSection
                    .studioCascade(hasAppeared: hasAppeared, index: 2, reduceMotion: reduceMotion)
                contextSection
                    .studioCascade(hasAppeared: hasAppeared, index: 3, reduceMotion: reduceMotion)
                toolsSection
                    .studioCascade(hasAppeared: hasAppeared, index: 4, reduceMotion: reduceMotion)
                promptSection
                    .studioCascade(hasAppeared: hasAppeared, index: 5, reduceMotion: reduceMotion)
                exampleSection
                    .studioCascade(hasAppeared: hasAppeared, index: 6, reduceMotion: reduceMotion)
                runtimeSection
                    .studioCascade(hasAppeared: hasAppeared, index: 7, reduceMotion: reduceMotion)
            }
            .padding(DS.space24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    // MARK: Identity strip (the hero — sits directly on the page)

    private var identityStrip: some View {
        HStack(alignment: .center, spacing: DS.space16) {
            iconMark(size: 56)
            VStack(alignment: .leading, spacing: DS.space4) {
                TextField("Name this skill", text: $skill.name)
                    .textFieldStyle(.plain)
                    .font(DS.pageTitle)
                    .foregroundStyle(DS.text)
                    .accessibilityLabel("Skill name")
                TextField("One sentence on what it does", text: $skill.summary)
                    .textFieldStyle(.plain)
                    .font(DS.subheadline)
                    .foregroundStyle(DS.textSecondary)
                    .accessibilityLabel("Skill summary")
                TextField("wand.and.stars", text: $skill.icon)
                    .textFieldStyle(.plain)
                    .font(DS.footnote.monospaced())
                    .foregroundStyle(DS.textMuted)
                    .frame(maxWidth: 220)
                    .help("SF Symbol shown for this skill")
                    .accessibilityLabel("SF Symbol name")
            }
            Spacer(minLength: 0)
        }
    }

    private func iconMark(size: CGFloat) -> some View {
        Image(systemName: skill.icon.isEmpty ? "wand.and.stars" : skill.icon)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(DS.accent)
            .frame(width: size, height: size)
            .background(DS.accentSoft, in: .rect(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }

    // MARK: Behavior

    private var behaviorSection: some View {
        section(label: "BEHAVIOR") {
            SettingsRow(icon: "arrow.triangle.branch", title: "Route") { routePicker }
            SettingsRowDivider()
            SettingsRow(icon: "cpu", title: "Model") { modelPicker }
            SettingsRowDivider()
            SettingsRow(icon: "sidebar.right", title: "Answer pane") { panePicker }
            SettingsRowDivider()
            SettingsRow(
                icon: "checkmark.seal",
                title: "Requires reviewed diff",
                subtitle: "Every visible change lands as a diff you approve"
            ) { reviewedDiffToggle }
            SettingsRowDivider()
            SettingsRow(icon: "signature", title: "Output contract") { contractField }
            SettingsRowDivider()
            SettingsRow(icon: "gauge.with.needle", title: "Token budget") { budgetField }
        }
    }

    private var routePicker: some View {
        Picker("", selection: $skill.route) {
            Text("Reviewed diff").tag(CosmoInlineAssistantRoute.action)
            Text("Pane answer").tag(CosmoInlineAssistantRoute.answer)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel("Route")
    }

    private var modelPicker: some View {
        Picker("", selection: $skill.preferredModelTier) {
            Text("Auto").tag(nil as AgentModelTier?)
            ForEach(AgentModelTier.skillSelectableCases, id: \.rawValue) { tier in
                Text(tier.displayLabel).tag(Optional.some(tier))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel("Model")
    }

    private var panePicker: some View {
        Picker("", selection: $skill.panePolicy) {
            ForEach(Self.panePolicies, id: \.rawValue) { policy in
                Text(panePolicyLabel(policy)).tag(policy)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel("Answer pane policy")
    }

    private var reviewedDiffToggle: some View {
        Toggle("", isOn: $skill.requiresReviewedDiff)
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .accessibilityLabel("Requires reviewed diff")
    }

    private var contractField: some View {
        TextField("reviewed_diff", text: $skill.outputContract)
            .textFieldStyle(.plain)
            .font(DS.footnote.monospaced())
            .foregroundStyle(DS.textSecondary)
            .multilineTextAlignment(.trailing)
            .frame(width: 160)
            .accessibilityLabel("Output contract")
    }

    private var budgetField: some View {
        TextField("1600", text: $tokenBudgetText)
            .textFieldStyle(.plain)
            .font(DS.footnote.monospacedDigit())
            .foregroundStyle(DS.textSecondary)
            .multilineTextAlignment(.trailing)
            .frame(width: 80)
            .accessibilityLabel("Token budget")
    }

    // MARK: Triggers

    private var triggersSection: some View {
        section(
            label: "TRIGGERS",
            footer: "The router matches these against what the user types — write them in the user's words."
        ) {
            fieldRow(
                label: "When to use",
                placeholder: "When should this trigger, in the user's words?",
                text: Binding(
                    get: { skill.triggerDescription ?? "" },
                    set: { skill.triggerDescription = trimmedOptional($0) }
                )
            )
            SettingsRowDivider()
            fieldRow(
                label: "Trigger phrases",
                placeholder: "reel script, hook rewrite, client voice",
                text: $triggerPhrasesText
            )
        }
    }

    // MARK: Context & tools

    private var contextSection: some View {
        section(
            label: "CONTEXT",
            detail: "\(skill.requiredContext.count) of \(CosmoInlineAssistantSkillContext.allCases.count)",
            footer: "Only what the skill actually needs — smaller context means faster, cheaper runs."
        ) {
            pillGrid {
                ForEach(CosmoInlineAssistantSkillContext.allCases, id: \.rawValue) { context in
                    selectionPill(
                        title: context.displayName,
                        icon: contextIcon(context),
                        isSelected: skill.requiredContext.contains(context)
                    ) {
                        toggle(context)
                    }
                }
            }
        }
    }

    private var toolsSection: some View {
        section(
            label: "TOOLS",
            detail: "\(skill.toolBundles.count) of \(AgentToolBundle.allCases.count)"
        ) {
            pillGrid {
                ForEach(AgentToolBundle.allCases) { bundle in
                    selectionPill(
                        title: bundle.displayName,
                        icon: bundle.icon,
                        isSelected: skill.toolBundles.contains(bundle)
                    ) {
                        toggle(bundle)
                    }
                    .help(bundle.accessDescription)
                }
            }
        }
    }

    private func pillGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: DS.space6)],
            alignment: .leading,
            spacing: DS.space6
        ) {
            content()
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space12)
    }

    private func selectionPill(
        title: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DS.space4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 14)
                Text(title)
                    .font(DS.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? DS.accent : DS.textSecondary)
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? AnyShapeStyle(DS.accentSoft) : AnyShapeStyle(Color.clear),
                in: Capsule(style: .continuous)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isSelected ? DS.accent.opacity(0.35) : DS.glassBorder, lineWidth: 1)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(ProMotionSprings.snappy, value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Prompt & example

    private var promptSection: some View {
        section(
            label: "INSTRUCTIONS",
            footer: "One instruction per line — teach how, with zero ambiguity."
        ) {
            editorRow(text: $instructionsText, minHeight: 140, accessibilityLabel: "Skill instructions")
            SettingsRowDivider()
            fieldRow(
                label: "Verification",
                placeholder: "e.g. no invented metrics; every edit is visible in the diff",
                text: Binding(
                    get: { skill.verification ?? "" },
                    set: { skill.verification = trimmedOptional($0) }
                )
            )
        }
    }

    private var exampleSection: some View {
        section(
            label: "EXAMPLE",
            footer: "The strongest teacher — one realistic request and the shape of a great result."
        ) {
            editorRow(
                label: "Request",
                text: $exampleInputText,
                minHeight: 72,
                accessibilityLabel: "Example request"
            )
            SettingsRowDivider()
            editorRow(
                label: "Ideal output",
                text: $exampleOutputText,
                minHeight: 96,
                accessibilityLabel: "Example ideal output"
            )
        }
    }

    // MARK: Runtime preview

    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            SettingsSectionHeader(label: "RUNTIME")
            SettingsGroupedBox {
                runtimeSummaryRow
                if showPromptPreview {
                    SettingsRowDivider(inset: 0)
                    promptPreview
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var runtimeSummaryRow: some View {
        HStack(spacing: DS.space12) {
            Image(systemName: "curlybraces")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 28, height: 28)
                .background(DS.accentSoft, in: .rect(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Prompt block")
                    .font(DS.callout.weight(.medium))
                    .foregroundStyle(DS.text)
                Text(runtimeMetaLine)
                    .font(DS.footnote.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
            }

            Spacer()

            previewToggle
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space12)
        .accessibilityElement(children: .combine)
    }

    private var runtimeMetaLine: String {
        let draft = draftSkill
        return "\(draft.displayedModelLabel) · \(draft.requiredContext.count) context · \(draft.toolBundles.count) tools · \(draft.tokenBudget) tokens"
    }

    private var previewToggle: some View {
        Button {
            withAnimation(ProMotionSprings.gentle) { showPromptPreview.toggle() }
        } label: {
            HStack(spacing: DS.space4) {
                Text(showPromptPreview ? "Hide prompt" : "Show prompt")
                    .font(DS.caption.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .rotationEffect(.degrees(showPromptPreview ? 180 : 0))
            }
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space6)
            .background(DS.glassSectionFill, in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help("The exact skill block injected after routing resolves this skill")
    }

    private var promptPreview: some View {
        ScrollView {
            Text(promptBlockPreview)
                .font(DS.caption.monospaced())
                .foregroundStyle(DS.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 260)
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space12)
    }

    // MARK: Section & field helpers

    private func section<Content: View>(
        label: String,
        detail: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            SettingsSectionHeader(label: label, detail: detail)
            SettingsGroupedBox { content() }
            if let footer {
                Text(footer)
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    private func fieldRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            Text(label)
                .font(DS.footnote.weight(.medium))
                .foregroundStyle(DS.textMuted)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .accessibilityLabel(label)
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editorRow(
        label: String? = nil,
        text: Binding<String>,
        minHeight: CGFloat,
        accessibilityLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            if let label {
                Text(label)
                    .font(DS.footnote.weight(.medium))
                    .foregroundStyle(DS.textMuted)
            }
            TextEditor(text: text)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
                .padding(DS.space8)
                .dsGlassInput()
                .accessibilityLabel(accessibilityLabel)
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space10)
    }

    // MARK: Draft assembly

    private var draftSkill: CosmoInlineSkillDefinition {
        var copy = skill
        copy.triggerPhrases = triggerPhrasesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        copy.instructions = instructionsText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let budget = Int(tokenBudgetText.trimmingCharacters(in: .whitespacesAndNewlines)), budget > 0 {
            copy.tokenBudget = budget
        }

        let input = exampleInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = exampleOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.examples = input.isEmpty || output.isEmpty
            ? nil
            : [CosmoInlineSkillExample(input: input, idealOutput: output)]

        return copy
    }

    private var promptBlockPreview: String {
        CosmoInlineAssistantSkillPlan(
            primarySkill: draftSkill.assistantSkill(),
            definitionID: draftSkill.id
        )
        .promptBlock
    }

    private var canSave: Bool {
        !skill.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !skill.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draftSkill.instructions.isEmpty &&
        !skill.outputContract.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (Int(tokenBudgetText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) > 0
    }

    private func save() {
        guard canSave else { return }
        onSave(draftSkill)
    }

    private func toggle(_ context: CosmoInlineAssistantSkillContext) {
        if skill.requiredContext.contains(context) {
            skill.requiredContext.remove(context)
        } else {
            skill.requiredContext.insert(context)
        }
    }

    private func toggle(_ bundle: AgentToolBundle) {
        if skill.toolBundles.contains(bundle) {
            skill.toolBundles.remove(bundle)
        } else {
            skill.toolBundles.insert(bundle)
        }
    }

    private func panePolicyLabel(_ policy: CosmoInlineSkillPanePolicy) -> String {
        switch policy {
        case .neverForAction: return "Diff only"
        case .openForAnswer: return "Open for answers"
        case .openForResearchBackedAction: return "Open for research"
        case .alwaysOpenWithResult: return "Always show result"
        }
    }

    private func contextIcon(_ context: CosmoInlineAssistantSkillContext) -> String {
        switch context {
        case .activeSurface: return "doc.text"
        case .currentFocus: return "scope"
        case .clientProfile: return "person.crop.rectangle"
        case .clientMemory: return "person.badge.clock"
        case .voiceLessons: return "quote.bubble"
        case .swipes: return "rectangle.stack"
        case .bestPerformingContent: return "chart.line.uptrend.xyaxis"
        case .researchEvidence: return "magnifyingglass"
        case .workspaceMemory: return "brain"
        case .canvasState: return "square.grid.3x3"
        }
    }

    private func trimmedOptional(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Personality tab

private struct CosmoStudioPersonalityTab: View {
    @State private var text: String = CosmoInlineAssistantPersonalityStore.shared.currentText
    @State private var didSave = false
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.space24) {
                characterSection
                    .studioCascade(hasAppeared: hasAppeared, index: 0, reduceMotion: reduceMotion)
            }
            .padding(DS.space24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .onAppear {
            Task { @MainActor in
                withAnimation(ProMotionSprings.gentle) { hasAppeared = true }
            }
        }
    }

    private var characterSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            SettingsSectionHeader(label: "CHARACTER SHEET")
            SettingsGroupedBox {
                explainerRow
                SettingsRowDivider(inset: 0)
                sheetEditor
                SettingsRowDivider(inset: 0)
                footerRow
            }
        }
    }

    private var explainerRow: some View {
        Text("Applies to every inline request. Voice is taught best by the paired examples — edit those before the rules. Saving rewrites the prompt cache once.")
            .font(DS.footnote)
            .foregroundStyle(DS.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sheetEditor: some View {
        TextEditor(text: $text)
            .font(DS.caption.monospaced())
            .foregroundStyle(DS.text)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 380)
            .padding(DS.space8)
            .dsGlassInput()
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space12)
            .accessibilityLabel("Personality character sheet")
    }

    private var footerRow: some View {
        HStack(spacing: DS.space10) {
            Button("Reset to default") {
                CosmoInlineAssistantPersonalityStore.shared.resetToDefault()
                text = CosmoInlineAssistantPersonalityStore.shared.currentText
                didSave = false
            }
            .buttonStyle(.plain)
            .font(DS.caption.weight(.medium))
            .foregroundStyle(DS.textSecondary)
            .cosmoClickCursor()
            .help("Restore the shipped character sheet")

            Spacer()

            if didSave {
                Label("Saved", systemImage: "checkmark")
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
                    .transition(.opacity)
            }

            Button(action: savePersonality) {
                Text("Save")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.textOnAccent)
                    .padding(.horizontal, DS.space16)
                    .padding(.vertical, DS.space6)
                    .background(DS.accent, in: Capsule(style: .continuous))
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .cosmoClickCursor()
            .keyboardShortcut(.return, modifiers: .command)
            .help("Save personality (⌘↩)")
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space12)
    }

    private func savePersonality() {
        CosmoInlineAssistantPersonalityStore.shared.save(text)
        text = CosmoInlineAssistantPersonalityStore.shared.currentText
        withAnimation(ProMotionSprings.snappy) { didSave = true }
    }
}

// MARK: - Metrics tab

private struct CosmoStudioMetricsTab: View {
    private var metrics: CosmoInlineAssistantMetrics { .shared }

    @State private var cacheSnapshot = LLMCacheTelemetry.shared.current()
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.space24) {
                explainer
                    .studioCascade(hasAppeared: hasAppeared, index: 0, reduceMotion: reduceMotion)
                speedSection
                    .studioCascade(hasAppeared: hasAppeared, index: 1, reduceMotion: reduceMotion)
                outcomeSection
                    .studioCascade(hasAppeared: hasAppeared, index: 2, reduceMotion: reduceMotion)
            }
            .padding(DS.space24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .task { cacheSnapshot = LLMCacheTelemetry.shared.current() }
        .onAppear {
            Task { @MainActor in
                withAnimation(ProMotionSprings.gentle) { hasAppeared = true }
            }
        }
    }

    private var explainer: some View {
        Text("Since launch. These numbers are the contract: warm cache reads, sub-second first tokens, edits that locate and get accepted.")
            .font(DS.footnote)
            .foregroundStyle(DS.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            SettingsSectionHeader(label: "SPEED")
            SettingsGroupedBox {
                metricRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Cache read ratio",
                    subtitle: "target ≥ 85% · \(cacheSnapshot.requestCount) LLM calls",
                    value: cacheSnapshot.requestCount > 0
                        ? "\(Int(cacheSnapshot.readRatio * 100))%"
                        : "—",
                    healthy: cacheSnapshot.requestCount == 0 || cacheSnapshot.readRatio >= 0.5
                )
                SettingsRowDivider()
                metricRow(
                    icon: "bolt",
                    title: "First token",
                    subtitle: "avg time to first streamed answer token",
                    value: metrics.averageTTFTMs.map { "\($0) ms" } ?? "—",
                    healthy: (metrics.averageTTFTMs ?? 0) < 1500
                )
                SettingsRowDivider()
                metricRow(
                    icon: "clock",
                    title: "Proposal staged",
                    subtitle: "avg request → reviewable diff",
                    value: metrics.averageProposalLatencyMs.map { "\($0) ms" } ?? "—",
                    healthy: (metrics.averageProposalLatencyMs ?? 0) < 4000
                )
            }
        }
    }

    private var outcomeSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            SettingsSectionHeader(label: "OUTCOMES")
            SettingsGroupedBox {
                metricRow(
                    icon: "checkmark.circle",
                    title: "Accept rate",
                    subtitle: "\(metrics.operationsAccepted) accepted · \(metrics.operationsRejected) rejected",
                    value: metrics.acceptRate.map { "\(Int($0 * 100))%" } ?? "—",
                    healthy: (metrics.acceptRate ?? 1) >= 0.6
                )
                SettingsRowDivider()
                metricRow(
                    icon: "exclamationmark.triangle",
                    title: "Conflict rate",
                    subtitle: "edits that no longer located — locator health",
                    value: metrics.conflictRate.map { "\(Int($0 * 100))%" } ?? "—",
                    healthy: (metrics.conflictRate ?? 0) <= 0.1
                )
                SettingsRowDivider()
                metricRow(
                    icon: "chart.bar",
                    title: "Activity",
                    subtitle: "\(metrics.proposalsStaged) proposals · \(metrics.paneAnswers) answers",
                    value: "\(metrics.requestCount)",
                    healthy: true
                )
            }
        }
    }

    private func metricRow(
        icon: String,
        title: String,
        subtitle: String,
        value: String,
        healthy: Bool
    ) -> some View {
        SettingsRow(icon: icon, title: title, subtitle: subtitle) {
            Text(value)
                .font(DS.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(healthy ? DS.text : DS.red)
                .contentTransition(.numericText())
        }
    }
}
