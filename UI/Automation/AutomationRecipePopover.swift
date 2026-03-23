// CosmoOS/UI/Automation/AutomationRecipePopover.swift
// Compact 3-row "When / If / Then" rule builder — sentence-completion style
// Anchored to cluster headers. Pre-fills scope from cluster context.

import SwiftUI

struct AutomationRecipePopover: View {

    let clusterId: String
    let clusterName: String
    let clusterColor: Color
    let onDismiss: () -> Void

    // MARK: - State

    @State private var appeared = false
    @State private var ruleName = ""
    @State private var selectedTrigger: TriggerOption = .blockAdded
    @State private var conditionEnabled = false
    @State private var selectedCondition: ConditionOption = .typeIs
    @State private var conditionValue = ""
    @State private var selectedAction: ActionOption = .moveToThisCluster
    @State private var actionValue = ""
    @State private var isCreating = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            triggerRow
            conditionRow
            actionRow
            divider
            footer
        }
        .frame(width: 300)
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

            // Scope badge
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
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: - Trigger Row (When)

    private var triggerRow: some View {
        RecipeRow(label: "When", accentColor: DS.green) {
            Menu {
                ForEach(TriggerOption.allCases) { option in
                    Button(option.displayName) {
                        selectedTrigger = option
                    }
                }
            } label: {
                selectorPill(text: selectedTrigger.displayName, isActive: true)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: - Condition Row (If)

    private var conditionRow: some View {
        RecipeRow(label: "If", accentColor: DS.info, isOptional: true, isEnabled: $conditionEnabled) {
            if conditionEnabled {
                HStack(spacing: 6) {
                    Menu {
                        ForEach(ConditionOption.allCases) { option in
                            Button(option.displayName) {
                                selectedCondition = option
                            }
                        }
                    } label: {
                        selectorPill(text: selectedCondition.displayName, isActive: true)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    if selectedCondition.needsValue {
                        conditionValueField
                    }
                }
            }
        }
    }

    // MARK: - Action Row (Then)

    private var actionRow: some View {
        RecipeRow(label: "Then", accentColor: DS.accent) {
            HStack(spacing: 6) {
                Menu {
                    ForEach(ActionOption.allCases) { option in
                        Button(option.displayName) {
                            selectedAction = option
                        }
                    }
                } label: {
                    selectorPill(text: selectedAction.displayName, isActive: true)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                if selectedAction.needsValue {
                    actionValueField
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                onDismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DS.surfaceHover)
                    )
            }
            .buttonStyle(.plain)

            Spacer()

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
                        .fill(DS.accent)
                )
                .shadow(color: DS.accent.opacity(0.2), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(isCreating)
            .opacity(isCreating ? 0.6 : 1.0)
            .accessibilityLabel("Create automation rule")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Shared Components

    private func selectorPill(text: String, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isActive ? DS.text : DS.textMuted)
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(DS.textMuted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(DS.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(DS.borderSubtle, lineWidth: 0.5)
        )
    }

    private var conditionValueField: some View {
        TextField("value", text: $conditionValue)
            .textFieldStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DS.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: 90)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(DS.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(DS.borderSubtle, lineWidth: 0.5)
            )
    }

    private var actionValueField: some View {
        TextField("value", text: $actionValue)
            .textFieldStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DS.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: 90)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(DS.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(DS.borderSubtle, lineWidth: 0.5)
            )
    }

    private var divider: some View {
        Rectangle()
            .fill(DS.borderSubtle)
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    // MARK: - Rule Creation

    private func createRule() {
        isCreating = true

        // Build trigger
        let triggerType = selectedTrigger.triggerType
        var triggerConfig: [String: String] = [:]
        if let atomType = selectedTrigger.atomTypeFilter {
            triggerConfig["atomType"] = atomType
        }

        // Build conditions
        var conditions: [AutomationCondition] = []
        if conditionEnabled {
            let condition = selectedCondition.toCondition(value: conditionValue)
            conditions.append(condition)
        }

        // Build actions
        let action = selectedAction.toAction(
            clusterId: clusterId,
            clusterName: clusterName,
            value: actionValue
        )

        // Generate name
        let name = ruleName.isEmpty
            ? "\(selectedTrigger.shortName) → \(selectedAction.shortName)"
            : ruleName

        let rule = AutomationRule.create(
            name: name,
            scope: .cluster,
            scopeId: clusterId,
            triggerType: triggerType,
            triggerConfig: triggerConfig,
            conditions: conditions,
            actions: [action],
            priority: 50,
            cooldownSeconds: 1
        )

        Task {
            do {
                try await AutomationDispatcher.shared.createRule(rule)
                isCreating = false
                onDismiss()
            } catch {
                print("⚡ [RecipePopover] Failed to create rule: \(error.localizedDescription)")
                isCreating = false
            }
        }
    }
}

// MARK: - Recipe Row

private struct RecipeRow<Content: View>: View {

    let label: String
    let accentColor: Color
    var isOptional: Bool = false
    var isEnabled: Binding<Bool>?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // Label pill
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accentColor)
                    .tracking(0.4)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(accentColor.opacity(0.1))
                    )

                if isOptional, let binding = isEnabled {
                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            binding.wrappedValue.toggle()
                        }
                    } label: {
                        Text(binding.wrappedValue ? "remove" : "add condition")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(DS.textMuted)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }

            // Content
            if !isOptional || isEnabled?.wrappedValue == true {
                content
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Trigger Options

private enum TriggerOption: String, CaseIterable, Identifiable {
    case blockAdded = "block_added"
    case ideaCreated = "idea_created"
    case contentCreated = "content_created"
    case statusChanged = "status_changed"
    case linkCreated = "link_created"
    case researchAdded = "research_added"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blockAdded: return "any block is added"
        case .ideaCreated: return "an idea is created"
        case .contentCreated: return "a content piece is created"
        case .statusChanged: return "status changes"
        case .linkCreated: return "a link is created"
        case .researchAdded: return "research is added"
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
        }
    }

    var triggerType: AutomationTriggerType {
        switch self {
        case .blockAdded: return .addedToThinkspace
        case .ideaCreated, .contentCreated, .researchAdded: return .atomTypeCreated
        case .statusChanged: return .statusChanged
        case .linkCreated: return .linkCreated
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

// MARK: - Condition Options

private enum ConditionOption: String, CaseIterable, Identifiable {
    case typeIs = "type_is"
    case linkedToClient = "linked_to_client"
    case tagContains = "tag_contains"
    case statusIs = "status_is"
    case fromTelegram = "from_telegram"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .typeIs: return "type is"
        case .linkedToClient: return "linked to client"
        case .tagContains: return "tag contains"
        case .statusIs: return "status is"
        case .fromTelegram: return "from Telegram"
        }
    }

    var needsValue: Bool {
        switch self {
        case .fromTelegram: return false
        default: return true
        }
    }

    func toCondition(value: String) -> AutomationCondition {
        switch self {
        case .typeIs:
            return AutomationCondition(field: .atomType, op: .equals, value: .string(value))
        case .linkedToClient:
            return AutomationCondition(field: .atomClientUUID, op: .equals, value: .string(value))
        case .tagContains:
            return AutomationCondition(field: .atomTag, op: .contains, value: .string(value))
        case .statusIs:
            return AutomationCondition(field: .atomStatus, op: .equals, value: .string(value))
        case .fromTelegram:
            return AutomationCondition(field: .captureSource, op: .equals, value: .string("telegram"))
        }
    }
}

// MARK: - Action Options

private enum ActionOption: String, CaseIterable, Identifiable {
    case moveToThisCluster = "move_to_this_cluster"
    case setStatus = "set_status"
    case createLink = "create_link"
    case notify = "notify"
    case sendTelegram = "send_telegram"
    case runAnalysis = "run_analysis"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .moveToThisCluster: return "move to this cluster"
        case .setStatus: return "set status to"
        case .createLink: return "create a link"
        case .notify: return "notify me"
        case .sendTelegram: return "send Telegram message"
        case .runAnalysis: return "run analysis"
        }
    }

    var shortName: String {
        switch self {
        case .moveToThisCluster: return "Move here"
        case .setStatus: return "Set status"
        case .createLink: return "Link"
        case .notify: return "Notify"
        case .sendTelegram: return "Telegram"
        case .runAnalysis: return "Analyze"
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
            return AutomationAction(
                type: .moveToCluster,
                config: ["clusterId": .string(clusterId)],
                label: "Move to \(clusterName)"
            )
        case .setStatus:
            return AutomationAction(
                type: .setStatus,
                config: ["status": .string(value)],
                label: "Set status to \(value)"
            )
        case .createLink:
            return AutomationAction(type: .createLink, label: "Create link")
        case .notify:
            return AutomationAction(
                type: .showNotification,
                config: ["message": .string("Rule fired for {{atom.title}}")],
                label: "Show notification"
            )
        case .sendTelegram:
            return AutomationAction(
                type: .sendTelegram,
                config: ["message": .string("{{atom.title}} matched a rule")],
                label: "Send Telegram"
            )
        case .runAnalysis:
            return AutomationAction(
                type: .runAnalysis,
                config: ["analysisType": .string("quickEnrich")],
                label: "Run analysis"
            )
        }
    }
}
