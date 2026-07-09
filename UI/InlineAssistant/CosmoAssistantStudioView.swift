// CosmoOS/UI/InlineAssistant/CosmoAssistantStudioView.swift
// The Assistant Studio — one panel to manage skills, tune the personality
// character sheet, and read the assistant's own scorecard.

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

// MARK: - Studio

struct CosmoAssistantStudioView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case skills = "Skills"
        case personality = "Personality"
        case metrics = "Metrics"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .skills: return "wand.and.stars"
            case .personality: return "person.crop.circle"
            case .metrics: return "chart.bar"
            }
        }
    }

    /// A prefilled skill draft ("promote this run to a skill") — the Skills
    /// tab opens straight into the editor with it.
    var initialSkillDraft: CosmoInlineSkillDefinition? = nil
    let onDismiss: () -> Void

    @State private var selectedTab: Tab = .skills
    @State private var closeHovered = false
    @Namespace private var tabNamespace

    var body: some View {
        VStack(spacing: DS.space12) {
            header
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, DS.space12)
        .padding(.horizontal, DS.space12)
        .padding(.bottom, DS.space16)
        .frame(width: 920, height: 680)
        .background(DS.bg)
    }

    private var header: some View {
        ZStack {
            HStack(spacing: DS.space12) {
                titleBlock
                Spacer()
                closeButton
            }

            tabSwitcher
        }
        .padding(.leading, DS.space16)
        .padding(.trailing, DS.space8)
        .padding(.vertical, DS.space8)
        .modifier(CosmoAssistantStudioHeaderChrome())
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Assistant Studio")
                .font(DS.pageTitle)
                .foregroundStyle(DS.text)
                .lineLimit(1)

            Text("Skills, prompts, models, and routing contracts")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: 330, alignment: .leading)
    }

    private var tabSwitcher: some View {
        CosmoAssistantStudioTabSwitcher(
            selectedTab: $selectedTab,
            namespace: tabNamespace
        )
    }

    private var closeButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(DS.caption.weight(.semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(closeHovered ? DS.text : DS.textSecondary)
                .background(
                    closeHovered ? DS.glassInputFillFocused : DS.glassInputFill.opacity(0.72),
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(closeHovered ? 1.04 : 1)
        .animation(ProMotionSprings.hover, value: closeHovered)
        .onHover { closeHovered = $0 }
        .cosmoClickCursor()
        .keyboardShortcut(.escape, modifiers: [])
        .help("Close Assistant Studio (Esc)")
        .accessibilityLabel("Close Assistant Studio")
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .skills: CosmoStudioSkillsTab(initialDraft: initialSkillDraft)
        case .personality: CosmoStudioPersonalityTab()
        case .metrics: CosmoStudioMetricsTab()
        }
    }
}

private struct CosmoAssistantStudioHeaderChrome: ViewModifier {
    private let cornerRadius: CGFloat = 28

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .clipShape(shape)
            .glassEffect(.regular.tint(DS.glassPanelTint), in: shape)
            .background {
                shape
                    .fill(DS.surface.opacity(0.56))
                    .shadow(color: DS.glassPanelShadow.opacity(0.72), radius: 22, x: 0, y: 8)
                    .shadow(color: DS.glassPanelShadow.opacity(0.24), radius: 5, x: 0, y: 1)
            }
    }
}

private struct CosmoAssistantStudioTabSwitcher: View {
    @Binding var selectedTab: CosmoAssistantStudioView.Tab
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: DS.space2) {
            ForEach(Array(CosmoAssistantStudioView.Tab.allCases.enumerated()), id: \.element.id) { index, tab in
                CosmoAssistantStudioTabButton(
                    tab: tab,
                    index: index,
                    selectedTab: $selectedTab,
                    namespace: namespace
                )
            }
        }
        .padding(3)
        .background(DS.glassInputFill.opacity(0.68), in: Capsule())
        .overlay {
            Capsule()
                .stroke(DS.glassBorder.opacity(0.72), lineWidth: 1)
        }
    }
}

private struct CosmoAssistantStudioTabButton: View {
    let tab: CosmoAssistantStudioView.Tab
    let index: Int
    @Binding var selectedTab: CosmoAssistantStudioView.Tab
    let namespace: Namespace.ID

    private var isSelected: Bool { selectedTab == tab }

    var body: some View {
        Button {
            withAnimation(ProMotionSprings.focusTransition) {
                selectedTab = tab
            }
        } label: {
            label
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut, modifiers: .command)
        .help("\(tab.rawValue) (⌘\(index + 1))")
        .accessibilityLabel(tab.rawValue)
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private var label: some View {
        HStack(spacing: DS.space4) {
            Image(systemName: tab.icon)
                .font(DS.caption.weight(.semibold))
                .frame(width: 13)

            Text(tab.rawValue)
                .font(DS.caption.weight(.semibold))
        }
        .foregroundStyle(isSelected ? DS.text : DS.textMuted)
        .padding(.horizontal, DS.space10)
        .padding(.vertical, 7)
        .frame(minWidth: 102)
        .background(selectionBackground)
        .contentShape(Capsule())
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            Capsule()
                .fill(DS.surfaceElevated)
                .matchedGeometryEffect(id: "assistant-studio-tab", in: namespace)
                .overlay {
                    Capsule()
                        .stroke(DS.glassBorder, lineWidth: 1)
                }
        }
    }

    private var shortcut: KeyEquivalent {
        KeyEquivalent(Character(String(index + 1)))
    }
}

// MARK: - Skills Tab

private struct CosmoStudioSkillsTab: View {
    var initialDraft: CosmoInlineSkillDefinition? = nil

    @State private var skills: [CosmoInlineSkillDefinition] = []
    @State private var editingSkill: CosmoInlineSkillDefinition?
    @State private var acceptStats: [String: (accepted: Int, total: Int)] = [:]
    @State private var didPresentInitialDraft = false

    private let store = CosmoInlineSkillStore.defaultForRuntime()

    var body: some View {
        VStack(spacing: DS.space16) {
            skillsHero

            ScrollView {
                LazyVStack(spacing: DS.space8) {
                    routerTestPanel

                    sectionLabel("Custom skills")
                    if customSkills.isEmpty {
                        emptyCustomState
                    }
                    ForEach(customSkills) { skill in
                        skillRow(skill, isBuiltin: false)
                    }

                    sectionLabel("Built-in skills")
                    ForEach(builtinSkills) { skill in
                        skillRow(skill, isBuiltin: true)
                    }
                }
                .padding(.horizontal, DS.space2)
                .padding(.bottom, DS.space16)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
        }
        .padding(.horizontal, DS.space16)
        .padding(.top, DS.space8)
        .padding(.bottom, DS.space4)
        .task {
            reload()
            if let initialDraft, !didPresentInitialDraft {
                didPresentInitialDraft = true
                editingSkill = initialDraft
            }
        }
        .sheet(item: $editingSkill) { skill in
            CosmoStudioSkillEditor(
                skill: skill,
                onSave: { updated in
                    store.save(updated)
                    editingSkill = nil
                    reload()
                },
                onCancel: { editingSkill = nil }
            )
        }
    }

    private var skillsHero: some View {
        HStack(alignment: .center, spacing: DS.space16) {
            VStack(alignment: .leading, spacing: DS.space4) {
                Text("Skill Agents")
                    .font(DS.title2.weight(.semibold))
                    .foregroundStyle(DS.text)

                Text("Create routable mini-agents with their own model, context, tools, examples, and verification rule.")
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                editingSkill = newSkillTemplate()
            } label: {
                Label("New Skill", systemImage: "plus")
                    .font(DS.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.space12)
                    .padding(.vertical, 8)
                    .background(DS.accent, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.22), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .cosmoClickCursor()
            .keyboardShortcut("n", modifiers: .command)
            .help("Create skill (⌘N)")
            .accessibilityLabel("Create new skill")
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space6)
    }

    private var customSkills: [CosmoInlineSkillDefinition] {
        skills.filter { !$0.isBuiltin }
    }

    private var builtinSkills: [CosmoInlineSkillDefinition] {
        skills.filter(\.isBuiltin)
    }

    // MARK: Router test panel

    @State private var routerTestPhrase = ""
    @State private var routerTestResult: String?

    /// Type a phrase, see which skill the embedding router would pick and its
    /// score — routing quality stops being a guess.
    private var routerTestPanel: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            sectionLabel("Test routing")
            HStack(spacing: DS.space8) {
                TextField("Type a request the way you would ask it…", text: $routerTestPhrase)
                    .textFieldStyle(.plain)
                    .font(DS.callout)
                    .padding(.horizontal, DS.space10)
                    .padding(.vertical, 7)
                    .background(DS.surface, in: .rect(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(DS.borderSubtle, lineWidth: 1)
                    }
                    .onSubmit { runRouterTest() }

                Button("Route") { runRouterTest() }
                    .buttonStyle(.plain)
                    .font(DS.callout.weight(.semibold))
                    .foregroundStyle(DS.accent)
                    .cosmoClickCursor()
                    .disabled(routerTestPhrase.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Test skill routing")
            }
            if let routerTestResult {
                Text(routerTestResult)
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, DS.space8)
    }

    private func runRouterTest() {
        let phrase = routerTestPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }
        routerTestResult = "Routing…"
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
            routerTestResult = lines.joined(separator: "\n")
        }
    }

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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.caption.weight(.semibold))
            .foregroundStyle(DS.textMuted)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, DS.space8)
    }

    private var emptyCustomState: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Label("No custom skills yet", systemImage: "wand.and.stars")
                .font(DS.headline)
                .foregroundStyle(DS.text)

            Text("Create one here, or ask the assistant to build one from a live dry run. Skills work best when they include trigger language, context, examples, and a verification rule.")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                editingSkill = newSkillTemplate()
            } label: {
                Label("Create first skill", systemImage: "plus")
                    .font(DS.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.accent)
            .cosmoClickCursor()
            .help("Create first skill")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space8)
    }

    private func skillRow(_ skill: CosmoInlineSkillDefinition, isBuiltin: Bool) -> some View {
        HStack(spacing: DS.space12) {
            Image(systemName: skill.icon)
                .font(DS.callout)
                .foregroundStyle(skill.isEnabled ? DS.accent : DS.textMuted)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.space6) {
                    Text(skill.name)
                        .font(DS.callout.weight(.medium))
                        .foregroundStyle(skill.isEnabled ? DS.text : DS.textMuted)
                    tierBadge(skill)
                    routeBadge(skill)
                }
                Text(skill.summary)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(2)
                if let stat = acceptStats[skill.id], stat.total > 0 {
                    Text("\(Int(Double(stat.accepted) / Double(stat.total) * 100))% accepted · \(stat.total) outcomes")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }
            }

            Spacer()

            if isBuiltin {
                Button("Inspect") { editingSkill = editableCopy(of: skill) }
                    .buttonStyle(.plain)
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(DS.accent)
                    .cosmoClickCursor()
                    .help("Inspect this built-in prompt and save a custom version")
            } else {
                Toggle("", isOn: enabledBinding(for: skill))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityLabel("\(skill.name) enabled")

                Button("Edit") { editingSkill = skill }
                    .buttonStyle(.plain)
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(DS.accent)
                    .cosmoClickCursor()

                Button {
                    store.delete(id: skill.id)
                    reload()
                } label: {
                    Image(systemName: "trash")
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                }
                .buttonStyle(.plain)
                .cosmoClickCursor()
                .help("Delete \(skill.name)")
                .accessibilityLabel("Delete \(skill.name)")
            }
        }
        .padding(DS.space12)
        .background(DS.surface, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.borderSubtle, lineWidth: 1)
        }
    }

    private func tierBadge(_ skill: CosmoInlineSkillDefinition) -> some View {
        Text(skill.displayedModelLabel)
            .font(DS.caption2.weight(.semibold))
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(DS.surfaceElevated, in: Capsule())
    }

    private func routeBadge(_ skill: CosmoInlineSkillDefinition) -> some View {
        Text(skill.route == .action ? "Diff" : "Answer")
            .font(DS.caption2.weight(.semibold))
            .foregroundStyle(skill.route == .action ? DS.green : DS.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(DS.surfaceElevated, in: Capsule())
    }

    private func enabledBinding(for skill: CosmoInlineSkillDefinition) -> Binding<Bool> {
        Binding(
            get: { skill.isEnabled },
            set: { newValue in
                var updated = skill
                updated.isEnabled = newValue
                updated.updatedAt = Date()
                store.save(updated)
                reload()
            }
        )
    }

    private func editableCopy(of builtin: CosmoInlineSkillDefinition) -> CosmoInlineSkillDefinition {
        var copy = builtin
        copy.id = UUID().uuidString
        copy.name = "\(builtin.name) Copy"
        copy.isBuiltin = false
        copy.createdAt = Date()
        copy.updatedAt = Date()
        return copy
    }

    private func newSkillTemplate() -> CosmoInlineSkillDefinition {
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

// MARK: - Skill Editor

private struct CosmoStudioSkillEditor: View {
    @State var skill: CosmoInlineSkillDefinition
    let onSave: (CosmoInlineSkillDefinition) -> Void
    let onCancel: () -> Void

    @State private var triggerPhrasesText: String
    @State private var instructionsText: String
    @State private var tokenBudgetText: String
    @State private var exampleInputText: String
    @State private var exampleOutputText: String

    private static let routes: [CosmoInlineAssistantRoute] = [.action, .answer]
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
            editorHeader
            HStack(spacing: 0) {
                editorForm
                Divider()
                promptPreview
                    .frame(width: 310)
            }
            editorFooter
        }
        .frame(width: 860, height: 690)
        .background(DS.bg)
    }

    private var editorHeader: some View {
        HStack(spacing: DS.space12) {
            Image(systemName: skill.icon.isEmpty ? "wand.and.stars" : skill.icon)
                .font(DS.title3.weight(.semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 42, height: 42)
                .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Skill" : skill.name)
                    .font(DS.title2.weight(.semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                Text("Skill-agent contract")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }

            Spacer()

            routeBadge
        }
        .padding(DS.space16)
        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 22)
        .padding(DS.space12)
    }

    private var editorForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space16) {
                section("Identity", icon: "sparkles") {
                    studioTextField("Name", placeholder: "Skill name", text: $skill.name)
                    studioTextField("SF Symbol", placeholder: "wand.and.stars", text: $skill.icon)
                    studioTextField("Summary", placeholder: "One sentence on what it does", text: $skill.summary)
                }

                section("Routing", icon: "point.3.connected.trianglepath.dotted") {
                    studioTextField(
                        "Trigger description",
                        placeholder: "When should this trigger, in the user's words?",
                        text: Binding(
                            get: { skill.triggerDescription ?? "" },
                            set: { skill.triggerDescription = trimmedOptional($0) }
                        )
                    )
                    studioTextField(
                        "Trigger phrases",
                        placeholder: "e.g. reel script, hook rewrite, client voice",
                        text: $triggerPhrasesText
                    )
                }

                section("Execution", icon: "slider.horizontal.3") {
                    pickersRow

                    Toggle("Requires reviewed diff", isOn: $skill.requiresReviewedDiff)
                        .font(DS.callout)
                        .toggleStyle(.checkbox)
                        .foregroundStyle(DS.text)

                    HStack(spacing: DS.space10) {
                        studioTextField("Output contract", placeholder: "reviewed_diff", text: $skill.outputContract)
                        studioTextField("Token budget", placeholder: "1600", text: $tokenBudgetText)
                            .frame(width: 130)
                    }
                }

                section("Context", icon: "rectangle.stack.badge.person.crop") {
                    contextGrid
                }

                section("Tools", icon: "wrench.and.screwdriver") {
                    toolGrid
                }

                section("Prompt", icon: "text.alignleft") {
                    studioTextEditor("Instructions", text: $instructionsText, minHeight: 148)
                    studioTextField(
                        "Verification",
                        placeholder: "e.g. no invented metrics; every edit is visible in the diff",
                        text: Binding(
                            get: { skill.verification ?? "" },
                            set: { skill.verification = trimmedOptional($0) }
                        )
                    )
                }

                section("Example", icon: "quote.bubble") {
                    studioTextEditor("Input", text: $exampleInputText, minHeight: 86)
                    studioTextEditor("Ideal output", text: $exampleOutputText, minHeight: 108)
                }
            }
            .padding(DS.space16)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private var pickersRow: some View {
        HStack(spacing: DS.space8) {
            Picker("Route", selection: $skill.route) {
                ForEach(Self.routes, id: \.rawValue) { route in
                    Text(routeLabel(route)).tag(route)
                }
            }
            .pickerStyle(.menu)

            Picker("Model", selection: $skill.preferredModelTier) {
                Text("Auto").tag(nil as AgentModelTier?)
                ForEach(AgentModelTier.skillSelectableCases, id: \.rawValue) { tier in
                    Text(tier.displayLabel).tag(Optional.some(tier))
                }
            }
            .pickerStyle(.menu)

            Picker("Pane", selection: $skill.panePolicy) {
                ForEach(Self.panePolicies, id: \.rawValue) { policy in
                    Text(panePolicyLabel(policy)).tag(policy)
                }
            }
            .pickerStyle(.menu)
        }
        .font(DS.caption)
    }

    private var contextGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 142), spacing: DS.space6)],
            alignment: .leading,
            spacing: DS.space6
        ) {
            ForEach(CosmoInlineAssistantSkillContext.allCases, id: \.rawValue) { context in
                contractChip(
                    title: context.displayName,
                    icon: contextIcon(context),
                    isSelected: skill.requiredContext.contains(context)
                ) {
                    toggle(context)
                }
            }
        }
    }

    private var toolGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: DS.space6)],
            alignment: .leading,
            spacing: DS.space6
        ) {
            ForEach(AgentToolBundle.allCases) { bundle in
                contractChip(
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

    private var promptPreview: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Label("Runtime Prompt", systemImage: "curlybraces")
                .font(DS.headline)
                .foregroundStyle(DS.text)

            Text("Exact skill block injected after local routing resolves this skill.")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                Text(promptBlockPreview)
                    .font(DS.caption.monospaced())
                    .foregroundStyle(DS.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.space10)
            }
            .frame(maxHeight: .infinity)
            .background(DS.glassInputFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DS.glassBorder, lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: DS.space6) {
                metricLine("Model", value: skill.displayedModelLabel)
                metricLine("Context", value: "\(skill.requiredContext.count)")
                metricLine("Tools", value: "\(skill.toolBundles.count)")
                metricLine("Budget", value: "\(draftSkill.tokenBudget)")
            }
            .padding(DS.space10)
            .dsGlassSection(cornerRadius: 12)
        }
        .padding(.trailing, DS.space16)
        .padding(.vertical, DS.space16)
    }

    private var editorFooter: some View {
        HStack {
            Button(action: onCancel) {
                Label("Cancel", systemImage: "xmark")
            }
                .buttonStyle(.plain)
                .foregroundStyle(DS.textSecondary)
                .cosmoClickCursor()
                .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            Button {
                var updated = draftSkill
                updated.updatedAt = Date()
                onSave(updated)
            } label: {
                Label("Save Skill", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canSave)
        }
        .font(DS.callout.weight(.medium))
        .padding(DS.space16)
    }

    private var routeBadge: some View {
        Label(routeLabel(skill.route), systemImage: skill.route == .action ? "text.badge.checkmark" : "bubble.left.and.text.bubble.right")
            .font(DS.caption.weight(.semibold))
            .foregroundStyle(skill.route == .action ? DS.green : DS.accent)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, 5)
            .background(DS.glassInputFill, in: Capsule())
    }

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

    private func section<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            Label(title, systemImage: icon)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.text)
            content()
        }
        .padding(DS.space12)
        .dsGlassSection(cornerRadius: 14)
    }

    private func studioTextField(
        _ label: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(DS.textMuted)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .padding(.horizontal, DS.space10)
                .padding(.vertical, 8)
                .background(DS.glassInputFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DS.glassBorder, lineWidth: 1)
                }
        }
    }

    private func studioTextEditor(
        _ label: String,
        text: Binding<String>,
        minHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(DS.textMuted)

            TextEditor(text: text)
                .font(DS.caption.monospaced())
                .foregroundStyle(DS.text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
                .padding(8)
                .background(DS.glassInputFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DS.glassBorder, lineWidth: 1)
                }
        }
    }

    private func contractChip(
        title: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(DS.caption)
                    .frame(width: 14)
                Text(title)
                    .font(DS.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? DS.text : DS.textSecondary)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? DS.accentSoft : DS.glassInputFill, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? DS.accent.opacity(0.42) : DS.glassBorder, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .cosmoClickCursor()
        .animation(ProMotionSprings.snappy, value: isSelected)
    }

    private func metricLine(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
            Spacer()
            Text(value)
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(DS.text)
                .lineLimit(1)
        }
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

    private func routeLabel(_ route: CosmoInlineAssistantRoute) -> String {
        switch route {
        case .action: return "Reviewed diff"
        case .answer: return "Pane answer"
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

// MARK: - Personality Tab

private struct CosmoStudioPersonalityTab: View {
    @State private var text: String = CosmoInlineAssistantPersonalityStore.shared.currentText
    @State private var didSave = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Text("Cosmo's character sheet. Edits apply to every inline request — voice is taught best by the paired examples, so edit those before the rules. Changing this rewrites the prompt cache once.")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $text)
                .font(DS.caption.monospaced())
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(DS.surface, in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(DS.borderSubtle, lineWidth: 1)
                }
                .accessibilityLabel("Personality character sheet")

            HStack {
                Button("Reset to default") {
                    CosmoInlineAssistantPersonalityStore.shared.resetToDefault()
                    text = CosmoInlineAssistantPersonalityStore.shared.currentText
                    didSave = false
                }
                .buttonStyle(.plain)
                .font(DS.caption.weight(.medium))
                .foregroundStyle(DS.textSecondary)
                .cosmoClickCursor()

                Spacer()

                if didSave {
                    Label("Saved", systemImage: "checkmark")
                        .font(DS.caption)
                        .foregroundStyle(DS.green)
                        .transition(.opacity)
                }

                Button("Save personality") {
                    CosmoInlineAssistantPersonalityStore.shared.save(text)
                    text = CosmoInlineAssistantPersonalityStore.shared.currentText
                    withAnimation(ProMotionSprings.snappy) { didSave = true }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(DS.space16)
    }
}

// MARK: - Metrics Tab

private struct CosmoStudioMetricsTab: View {
    private var metrics: CosmoInlineAssistantMetrics { .shared }
    @State private var cacheSnapshot = LLMCacheTelemetry.shared.current()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space12) {
                Text("Since launch. These numbers are the contract: warm cache reads, sub-second first tokens, edits that locate and get accepted.")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                metricsGrid
            }
            .padding(DS.space16)
        }
        .task { cacheSnapshot = LLMCacheTelemetry.shared.current() }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.space8) {
            metricCard(
                title: "Cache read ratio",
                value: cacheSnapshot.requestCount > 0
                    ? "\(Int(cacheSnapshot.readRatio * 100))%"
                    : "—",
                detail: "target ≥ 85% · \(cacheSnapshot.requestCount) LLM calls",
                healthy: cacheSnapshot.requestCount == 0 || cacheSnapshot.readRatio >= 0.5
            )
            metricCard(
                title: "First token",
                value: metrics.averageTTFTMs.map { "\($0) ms" } ?? "—",
                detail: "avg time to first streamed answer token",
                healthy: (metrics.averageTTFTMs ?? 0) < 1500
            )
            metricCard(
                title: "Proposal staged",
                value: metrics.averageProposalLatencyMs.map { "\($0) ms" } ?? "—",
                detail: "avg request → reviewable diff",
                healthy: (metrics.averageProposalLatencyMs ?? 0) < 4000
            )
            metricCard(
                title: "Accept rate",
                value: metrics.acceptRate.map { "\(Int($0 * 100))%" } ?? "—",
                detail: "\(metrics.operationsAccepted) accepted · \(metrics.operationsRejected) rejected",
                healthy: (metrics.acceptRate ?? 1) >= 0.6
            )
            metricCard(
                title: "Conflict rate",
                value: metrics.conflictRate.map { "\(Int($0 * 100))%" } ?? "—",
                detail: "edits that no longer located — locator health",
                healthy: (metrics.conflictRate ?? 0) <= 0.1
            )
            metricCard(
                title: "Activity",
                value: "\(metrics.requestCount)",
                detail: "\(metrics.proposalsStaged) proposals · \(metrics.paneAnswers) answers",
                healthy: true
            )
        }
    }

    private func metricCard(title: String, value: String, detail: String, healthy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textMuted)
                .textCase(.uppercase)
            Text(value)
                .font(DS.title2.weight(.semibold))
                .foregroundStyle(healthy ? DS.text : DS.red)
            Text(detail)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.space12)
        .background(DS.surface, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.borderSubtle, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value). \(detail)")
    }
}
