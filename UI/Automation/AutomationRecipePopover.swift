// CosmoOS/UI/Automation/AutomationRecipePopover.swift
// Natural language rule creation — describe what you want, see structured preview, confirm
// Falls back to structured dropdown mode via "Advanced" toggle

import SwiftUI

struct AutomationRecipePopover: View {

    let clusterId: String
    let clusterName: String
    let clusterColor: Color
    let onDismiss: () -> Void

    // MARK: - State

    @State private var appeared = false
    @State private var ruleText = ""
    @State private var parsedRule: ParsedRule?
    @State private var isParsing = false
    @State private var isCreating = false
    @State private var showAdvanced = false
    @State private var parseTask: Task<Void, Never>?

    // Advanced mode state
    @State private var selectedTrigger: TriggerOption = .blockAdded
    @State private var conditionEnabled = false
    @State private var selectedCondition: ConditionOption = .typeIs
    @State private var conditionValue = ""
    @State private var selectedAction: ActionOption = .moveToThisCluster
    @State private var actionValue = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isTextFieldFocused: Bool

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider

            if showAdvanced {
                advancedMode
            } else {
                naturalLanguageMode
            }

            divider
            footer
        }
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.border, lineWidth: 1)
        )
        .dsFloatingShadow()
        .scaleEffect(appeared ? 1.0 : 0.92)
        .opacity(appeared ? 1.0 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .none : .spring(response: 0.22, dampingFraction: 0.78)) {
                appeared = true
            }
            isTextFieldFocused = true
        }
        .onDisappear {
            parseTask?.cancel()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(clusterColor)

            Text("NEW RULE")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.textMuted)
                .tracking(0.8)

            Spacer()

            if !clusterId.isEmpty {
                Text(clusterName.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(clusterColor)
                    .tracking(0.4)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(clusterColor.opacity(0.1))
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: - Natural Language Mode

    private var naturalLanguageMode: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Text input
            textInputField

            // Parsed preview
            if let parsed = parsedRule {
                parsedPreview(parsed)
            } else if !ruleText.isEmpty && !isParsing {
                hintText
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var textInputField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Describe your rule")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.textMuted)

            TextEditor(text: $ruleText)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(DS.text)
                .scrollContentBackground(.hidden)
                .frame(height: 56)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DS.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isTextFieldFocused ? clusterColor.opacity(0.4) : DS.borderSubtle, lineWidth: 1)
                )
                .focused($isTextFieldFocused)
                .onChange(of: ruleText) { _, newValue in
                    debounceParse(newValue)
                }
        }
    }

    private var hintText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Try something like:")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DS.textMuted)
                .tracking(0.4)

            VStack(alignment: .leading, spacing: 3) {
                hintExample("When ideas for Josh are created, run analysis")
                hintExample("Move content here when status reaches review")
                hintExample("Notify me on Telegram when new swipes arrive")
                hintExample("Auto-advance pipeline when linked to 3 swipes")
            }
        }
    }

    private func hintExample(_ text: String) -> some View {
        Button {
            ruleText = text
            debounceParse(text)
        } label: {
            Text(text)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(DS.textMuted.opacity(0.7))
                .lineLimit(1)
        }
        .buttonStyle(.plain)
    }

    private func parsedPreview(_ parsed: ParsedRule) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Confidence bar
            HStack(spacing: 4) {
                Text("PARSED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DS.textMuted)
                    .tracking(0.6)

                Spacer()

                // Confidence dots
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Double(i) < parsed.confidence * 3 ? DS.accent : DS.borderSubtle)
                            .frame(width: 4, height: 4)
                    }
                }
            }

            // Triggers
            ForEach(Array(parsed.triggers.enumerated()), id: \.offset) { _, trigger in
                parsedLine(icon: "bolt.fill", color: DS.green, text: trigger.description)
            }

            // Conditions
            ForEach(Array(parsed.conditions.enumerated()), id: \.offset) { _, condition in
                parsedLine(
                    icon: "line.3.horizontal.decrease.circle.fill",
                    color: DS.info,
                    text: "\(condition.field.displayName) \(condition.op.displayName) \(condition.value.stringValue ?? "...")"
                )
            }

            // Actions
            ForEach(Array(parsed.actions.enumerated()), id: \.offset) { _, action in
                parsedLine(icon: "arrow.right.circle.fill", color: clusterColor, text: action.label ?? action.type.displayName)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DS.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DS.borderSubtle, lineWidth: 0.5)
        )
    }

    private func parsedLine(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 14)

            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.text)
                .lineLimit(1)
        }
    }

    // MARK: - Advanced Mode (Dropdowns)

    private var advancedMode: some View {
        VStack(spacing: 0) {
            RecipeRow(label: "When", accentColor: DS.green) {
                Menu {
                    ForEach(TriggerOption.allCases) { option in
                        Button(option.displayName) { selectedTrigger = option }
                    }
                } label: {
                    selectorPill(text: selectedTrigger.displayName)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            RecipeRow(label: "If", accentColor: DS.info, isOptional: true, isEnabled: $conditionEnabled) {
                if conditionEnabled {
                    HStack(spacing: 6) {
                        Menu {
                            ForEach(ConditionOption.allCases) { option in
                                Button(option.displayName) { selectedCondition = option }
                            }
                        } label: {
                            selectorPill(text: selectedCondition.displayName)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()

                        if selectedCondition.needsValue {
                            compactTextField($conditionValue, placeholder: "value")
                        }
                    }
                }
            }

            RecipeRow(label: "Then", accentColor: DS.accent) {
                HStack(spacing: 6) {
                    Menu {
                        ForEach(ActionOption.allCases) { option in
                            Button(option.displayName) { selectedAction = option }
                        }
                    } label: {
                        selectorPill(text: selectedAction.displayName)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    if selectedAction.needsValue {
                        compactTextField($actionValue, placeholder: "value")
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            // Mode toggle
            Button {
                showAdvanced.toggle()
            } label: {
                Text(showAdvanced ? "Simple" : "Advanced")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.textMuted)
            }
            .buttonStyle(.plain)

            Spacer()

            Button("Cancel") { onDismiss() }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.textSecondary)
                .buttonStyle(.plain)

            Button {
                createRule()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("Create")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(canCreate ? DS.accent : DS.textMuted)
                )
                .shadow(color: canCreate ? DS.accent.opacity(0.2) : .clear, radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(!canCreate || isCreating)
            .opacity(isCreating ? 0.6 : 1.0)
            .accessibilityLabel("Create automation rule")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var canCreate: Bool {
        if showAdvanced { return true }
        return parsedRule != nil && !ruleText.isEmpty
    }

    // MARK: - Shared Components

    private func selectorPill(text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(DS.text)
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(DS.textMuted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(DS.surface))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(DS.borderSubtle, lineWidth: 0.5))
    }

    private func compactTextField(_ text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DS.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: 90)
            .background(RoundedRectangle(cornerRadius: 6).fill(DS.surface))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(DS.borderSubtle, lineWidth: 0.5))
    }

    private var divider: some View {
        Rectangle()
            .fill(DS.borderSubtle)
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    // MARK: - Parsing

    private func debounceParse(_ text: String) {
        parseTask?.cancel()
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            parsedRule = nil
            return
        }

        isParsing = true
        parseTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }
            let parsed = await IntentParser.parseRule(text)
            guard !Task.isCancelled else { return }
            parsedRule = parsed
            isParsing = false
        }
    }

    // MARK: - Rule Creation

    private func createRule() {
        isCreating = true

        Task {
            do {
                let rule: AutomationRule

                if showAdvanced {
                    rule = buildAdvancedRule()
                } else if let parsed = parsedRule {
                    rule = parsed.toRule(
                        scope: clusterId.isEmpty ? .global : .cluster,
                        scopeId: clusterId.isEmpty ? nil : clusterId,
                        clusterId: clusterId.isEmpty ? nil : clusterId
                    )
                } else {
                    isCreating = false
                    return
                }

                try await AutomationDispatcher.shared.createRule(rule)
                isCreating = false
                onDismiss()
            } catch {
                print("⚡ [RecipePopover] Failed to create rule: \(error.localizedDescription)")
                isCreating = false
            }
        }
    }

    private func buildAdvancedRule() -> AutomationRule {
        var triggerConfig: [String: String] = [:]
        if let atomType = selectedTrigger.atomTypeFilter {
            triggerConfig["atomType"] = atomType
        }

        var conditions: [AutomationCondition] = []
        if conditionEnabled {
            conditions.append(selectedCondition.toCondition(value: conditionValue))
        }

        let action = selectedAction.toAction(clusterId: clusterId, clusterName: clusterName, value: actionValue)

        return AutomationRule.create(
            name: "\(selectedTrigger.shortName) → \(selectedAction.shortName)",
            scope: clusterId.isEmpty ? .global : .cluster,
            scopeId: clusterId.isEmpty ? nil : clusterId,
            triggerType: selectedTrigger.triggerType,
            triggerConfig: triggerConfig,
            conditions: conditions,
            actions: [action]
        )
    }
}

// MARK: - Recipe Row (Reusable for Advanced mode)

private struct RecipeRow<Content: View>: View {

    let label: String
    let accentColor: Color
    var isOptional: Bool = false
    var isEnabled: Binding<Bool>?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accentColor)
                    .tracking(0.4)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(accentColor.opacity(0.1)))

                if isOptional, let binding = isEnabled {
                    Button {
                        binding.wrappedValue.toggle()
                    } label: {
                        Text(binding.wrappedValue ? "remove" : "add condition")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(DS.textMuted)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }

            if !isOptional || isEnabled?.wrappedValue == true {
                content
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Dropdown Options (Advanced mode)

private enum TriggerOption: String, CaseIterable, Identifiable {
    case blockAdded, ideaCreated, contentCreated, statusChanged, linkCreated, researchAdded
    case pipelineAdvanced, clientAssigned
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .blockAdded: return "any block is added"
        case .ideaCreated: return "an idea is created"
        case .contentCreated: return "content is created"
        case .statusChanged: return "status changes"
        case .linkCreated: return "a link is created"
        case .researchAdded: return "research is added"
        case .pipelineAdvanced: return "pipeline phase advances"
        case .clientAssigned: return "client is assigned"
        }
    }
    var shortName: String {
        switch self {
        case .blockAdded: return "Block added"
        case .ideaCreated: return "Idea created"
        case .contentCreated: return "Content created"
        case .statusChanged: return "Status changed"
        case .linkCreated: return "Link created"
        case .researchAdded: return "Research added"
        case .pipelineAdvanced: return "Phase advanced"
        case .clientAssigned: return "Client assigned"
        }
    }
    var triggerType: AutomationTriggerType {
        switch self {
        case .blockAdded: return .addedToThinkspace
        case .ideaCreated, .contentCreated, .researchAdded: return .atomTypeCreated
        case .statusChanged: return .statusChanged
        case .linkCreated: return .linkCreated
        case .pipelineAdvanced: return .phaseAdvanced
        case .clientAssigned: return .clientAssigned
        }
    }
    var atomTypeFilter: String? {
        switch self {
        case .ideaCreated: return "idea"
        case .contentCreated: return "content"
        case .researchAdded: return "research"
        default: return nil
        }
    }
}

private enum ConditionOption: String, CaseIterable, Identifiable {
    case typeIs, linkedToClient, tagContains, statusIs, fromTelegram, bodyLengthOver, hasSwipes
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .typeIs: return "type is"
        case .linkedToClient: return "linked to client"
        case .tagContains: return "tag contains"
        case .statusIs: return "status is"
        case .fromTelegram: return "from Telegram"
        case .bodyLengthOver: return "body length over"
        case .hasSwipes: return "has linked swipes"
        }
    }
    var needsValue: Bool {
        switch self {
        case .fromTelegram, .hasSwipes: return false
        default: return true
        }
    }
    func toCondition(value: String) -> AutomationCondition {
        switch self {
        case .typeIs: return AutomationCondition(field: .atomType, op: .equals, value: .string(value))
        case .linkedToClient: return AutomationCondition(field: .atomClientUUID, op: .equals, value: .string(value))
        case .tagContains: return AutomationCondition(field: .atomTag, op: .contains, value: .string(value))
        case .statusIs: return AutomationCondition(field: .atomStatus, op: .equals, value: .string(value))
        case .fromTelegram: return AutomationCondition(field: .captureSource, op: .equals, value: .string("telegram"))
        case .bodyLengthOver: return AutomationCondition(field: .bodyLength, op: .greaterThan, value: .number(Double(value) ?? 200))
        case .hasSwipes: return AutomationCondition(field: .linkedSwipeCount, op: .greaterThan, value: .number(0))
        }
    }
}

private enum ActionOption: String, CaseIterable, Identifiable {
    case moveToThisCluster, setStatus, advancePipeline, createLink
    case notify, sendTelegram, runAnalysis, generateOutline, awardXP, createTask
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .moveToThisCluster: return "move to this cluster"
        case .setStatus: return "set status to"
        case .advancePipeline: return "advance pipeline"
        case .createLink: return "create a link"
        case .notify: return "notify me"
        case .sendTelegram: return "send Telegram message"
        case .runAnalysis: return "run full analysis"
        case .generateOutline: return "generate outline"
        case .awardXP: return "award XP"
        case .createTask: return "create task"
        }
    }
    var shortName: String {
        switch self {
        case .moveToThisCluster: return "Move here"
        case .setStatus: return "Set status"
        case .advancePipeline: return "Advance"
        case .createLink: return "Link"
        case .notify: return "Notify"
        case .sendTelegram: return "Telegram"
        case .runAnalysis: return "Analyze"
        case .generateOutline: return "Outline"
        case .awardXP: return "XP"
        case .createTask: return "Task"
        }
    }
    var needsValue: Bool {
        switch self {
        case .setStatus: return true
        default: return false
        }
    }
    func toAction(clusterId: String, clusterName: String, value: String) -> AutomationAction {
        switch self {
        case .moveToThisCluster:
            return AutomationAction(type: .moveToCluster, config: ["clusterId": .string(clusterId)], label: "Move to \(clusterName)")
        case .setStatus:
            return AutomationAction(type: .setStatus, config: ["status": .string(value)], label: "Set status to \(value)")
        case .advancePipeline:
            return AutomationAction(type: .advancePipeline, label: "Advance pipeline phase")
        case .createLink:
            return AutomationAction(type: .createLink, label: "Create link")
        case .notify:
            return AutomationAction(type: .showNotification, config: ["message": .string("Rule fired for {{atom.title}}")], label: "Show notification")
        case .sendTelegram:
            return AutomationAction(type: .sendTelegram, config: ["message": .string("⚡ {{atom.title}} — automation fired")], label: "Send Telegram")
        case .runAnalysis:
            return AutomationAction(type: .runAnalysis, config: ["analysisType": .string("fullAnalysis")], label: "Run full analysis")
        case .generateOutline:
            return AutomationAction(type: .generateOutline, label: "Generate outline")
        case .awardXP:
            return AutomationAction(type: .awardXP, config: ["amount": .number(10), "dimension": .string("creative")], label: "Award 10 XP")
        case .createTask:
            return AutomationAction(type: .createTask, config: ["title": .string("Review {{atom.title}}")], label: "Create review task")
        }
    }
}
