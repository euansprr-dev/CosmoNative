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

    let onDismiss: () -> Void

    @State private var selectedTab: Tab = .skills

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabContent
        }
        .frame(width: 560, height: 580)
        .background(DS.surfaceCard)
    }

    private var header: some View {
        HStack(spacing: DS.space12) {
            Text("Assistant Studio")
                .font(DS.title3.weight(.semibold))
                .foregroundStyle(DS.text)

            Picker("Section", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(DS.caption.weight(.semibold))
                    .frame(width: 26, height: 26)
                    .background(DS.surface, in: Circle())
                    .foregroundStyle(DS.textSecondary)
            }
            .buttonStyle(.plain)
            .cosmoClickCursor()
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel("Close Assistant Studio")
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space12)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .skills: CosmoStudioSkillsTab()
        case .personality: CosmoStudioPersonalityTab()
        case .metrics: CosmoStudioMetricsTab()
        }
    }
}

// MARK: - Skills Tab

private struct CosmoStudioSkillsTab: View {
    @State private var skills: [CosmoInlineSkillDefinition] = []
    @State private var editingSkill: CosmoInlineSkillDefinition?
    @State private var acceptStats: [String: (accepted: Int, total: Int)] = [:]

    private let store = CosmoInlineSkillStore.defaultForRuntime()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: DS.space8) {
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
            .padding(DS.space16)
        }
        .task { reload() }
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

    private var customSkills: [CosmoInlineSkillDefinition] {
        skills.filter { !$0.isBuiltin }
    }

    private var builtinSkills: [CosmoInlineSkillDefinition] {
        skills.filter(\.isBuiltin)
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
        Text("No custom skills yet. Type /New Skill in the assistant bar to build one — it interviews you, dry-runs the skill on your live surface, then saves it here.")
            .font(DS.caption)
            .foregroundStyle(DS.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.space12)
            .background(DS.surface, in: .rect(cornerRadius: 10))
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
                Button("Duplicate") { duplicateAsCustom(skill) }
                    .buttonStyle(.plain)
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(DS.accent)
                    .cosmoClickCursor()
                    .help("Copy this built-in as an editable custom skill")
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
        Text(skill.preferredModelTier?.displayLabel ?? "Auto")
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

    private func duplicateAsCustom(_ builtin: CosmoInlineSkillDefinition) {
        var copy = builtin
        copy.id = UUID().uuidString
        copy.name = "\(builtin.name) Copy"
        copy.isBuiltin = false
        copy.createdAt = Date()
        copy.updatedAt = Date()
        store.save(copy)
        reload()
    }
}

// MARK: - Skill Editor

private struct CosmoStudioSkillEditor: View {
    @State var skill: CosmoInlineSkillDefinition
    let onSave: (CosmoInlineSkillDefinition) -> Void
    let onCancel: () -> Void

    @State private var triggerPhrasesText: String
    @State private var instructionsText: String

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
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Divider()
            editorForm
            Divider()
            editorFooter
        }
        .frame(width: 480, height: 560)
        .background(DS.surfaceCard)
    }

    private var editorHeader: some View {
        HStack {
            Text("Edit \(skill.name)")
                .font(DS.headline)
                .foregroundStyle(DS.text)
            Spacer()
        }
        .padding(DS.space16)
    }

    private var editorForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space12) {
                labeledField("Name") {
                    TextField("Skill name", text: $skill.name)
                        .textFieldStyle(.roundedBorder)
                }
                labeledField("Summary") {
                    TextField("One sentence on what it does", text: $skill.summary)
                        .textFieldStyle(.roundedBorder)
                }
                labeledField("Trigger description (drives auto-routing)") {
                    TextField(
                        "When should this trigger, in your words?",
                        text: Binding(
                            get: { skill.triggerDescription ?? "" },
                            set: { skill.triggerDescription = $0.isEmpty ? nil : $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }
                labeledField("Trigger phrases (comma-separated)") {
                    TextField("e.g. reel script, hook rewrite", text: $triggerPhrasesText)
                        .textFieldStyle(.roundedBorder)
                }
                pickersRow
                labeledField("Instructions (one per line)") {
                    TextEditor(text: $instructionsText)
                        .font(DS.caption)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(DS.surface, in: .rect(cornerRadius: 8))
                }
                labeledField("Verification (optional post-condition)") {
                    TextField(
                        "e.g. no invented metrics",
                        text: Binding(
                            get: { skill.verification ?? "" },
                            set: { skill.verification = $0.isEmpty ? nil : $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }
            }
            .padding(DS.space16)
        }
    }

    private var pickersRow: some View {
        HStack(spacing: DS.space12) {
            Picker("Route", selection: $skill.route) {
                Text("Reviewed diff").tag(CosmoInlineAssistantRoute.action)
                Text("Pane answer").tag(CosmoInlineAssistantRoute.answer)
            }
            .pickerStyle(.menu)

            Picker("Model", selection: $skill.preferredModelTier) {
                Text("Auto").tag(AgentModelTier?.none)
                Text("Haiku (fast)").tag(AgentModelTier?.some(.sensor))
                Text("Sonnet (judgment)").tag(AgentModelTier?.some(.strategist))
            }
            .pickerStyle(.menu)
        }
        .font(DS.caption)
    }

    private var editorFooter: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .foregroundStyle(DS.textSecondary)
                .cosmoClickCursor()
                .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            Button("Save") {
                skill.triggerPhrases = triggerPhrasesText
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                skill.instructions = instructionsText
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                skill.updatedAt = Date()
                onSave(skill)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(skill.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(DS.space16)
    }

    private func labeledField<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(DS.caption.weight(.medium))
                .foregroundStyle(DS.textSecondary)
            content()
        }
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
                .font(.system(size: 12, design: .monospaced))
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
