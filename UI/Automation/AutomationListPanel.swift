// CosmoOS/UI/Automation/AutomationListPanel.swift
// Management list view for all automation rules, grouped by scope
// Accessible from canvas sidebar or Command-K

import SwiftUI

struct AutomationListPanel: View {

    @State private var rules: [AutomationRule] = []
    @State private var isLoading = true
    @State private var showRecipePopover = false
    @State private var editingRule: AutomationRule?
    @State private var searchQuery = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            Divider()

            if isLoading {
                loadingState
            } else if filteredRules.isEmpty {
                emptyState
            } else {
                ruleList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DS.surface)
        .task {
            await loadRules()
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Automation.ruleCreated)) { _ in
            Task { await loadRules() }
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Automation.ruleUpdated)) { _ in
            Task { await loadRules() }
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Automation.ruleDeleted)) { _ in
            Task { await loadRules() }
        }
    }

    // MARK: - Header

    private var panelHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.accent)

                Text("Automations")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.text)

                Spacer()

                // Active count badge
                if !rules.isEmpty {
                    let active = rules.filter(\.isEnabled).count
                    Text("\(active) active")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(DS.surfaceHover)
                        )
                }

                Button {
                    showRecipePopover = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.accent)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(DS.accentSoft)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add new rule")
                .popover(isPresented: $showRecipePopover) {
                    AutomationRecipePopover(
                        clusterId: "",
                        clusterName: "Global",
                        clusterColor: DS.accent,
                        onDismiss: { showRecipePopover = false }
                    )
                }
            }

            // Search
            if rules.count > 5 {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.textMuted)

                    TextField("Filter rules...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.text)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DS.surfaceHover)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(DS.borderSubtle, lineWidth: 0.5)
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Rule List

    private var ruleList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                // Group by scope
                let grouped = groupedRules

                ForEach(Array(grouped.keys.sorted(by: scopeOrder)), id: \.self) { scope in
                    if let scopeRules = grouped[scope], !scopeRules.isEmpty {
                        scopeSection(scope: scope, rules: scopeRules)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func scopeSection(scope: AutomationScope, rules: [AutomationRule]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 6) {
                Circle()
                    .fill(scopeColor(scope))
                    .frame(width: 5, height: 5)

                Text(scopeLabel(scope, rules: rules))
                    .dsSmallCapsLabel()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)

            ForEach(rules, id: \.uuid) { rule in
                AutomationRuleRow(
                    rule: rule,
                    onToggle: {
                        Task {
                            try? await AutomationDispatcher.shared.toggleRule(uuid: rule.uuid)
                            await loadRules()
                        }
                    },
                    onDelete: {
                        Task {
                            try? await AutomationDispatcher.shared.deleteRule(uuid: rule.uuid)
                            await loadRules()
                        }
                    },
                    onEdit: {
                        editingRule = rule
                    }
                )
            }
        }
    }

    // MARK: - Empty / Loading States

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading rules...")
                .font(.system(size: 11))
                .foregroundStyle(DS.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(DS.textMuted.opacity(0.5))

            Text("No automations yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DS.textSecondary)

            Text("Add rules to clusters to automate\nhow content flows through your workspace.")
                .font(.system(size: 12))
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Button {
                showRecipePopover = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("Create First Rule")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DS.accent)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 24)
    }

    // MARK: - Data

    private func loadRules() async {
        do {
            rules = try await AutomationDispatcher.shared.fetchAllRules()
            isLoading = false
        } catch {
            isLoading = false
        }
    }

    private var filteredRules: [AutomationRule] {
        guard !searchQuery.isEmpty else { return rules }
        let query = searchQuery.lowercased()
        return rules.filter {
            $0.name.lowercased().contains(query) ||
            $0.naturalLanguageDescription.lowercased().contains(query)
        }
    }

    private var groupedRules: [AutomationScope: [AutomationRule]] {
        Dictionary(grouping: filteredRules, by: \.scope)
    }

    // MARK: - Helpers

    private func scopeColor(_ scope: AutomationScope) -> Color {
        switch scope {
        case .global: return DS.green
        case .thinkspace: return DS.info
        case .cluster: return DS.orange
        }
    }

    private func scopeLabel(_ scope: AutomationScope, rules: [AutomationRule]) -> String {
        switch scope {
        case .global: return "GLOBAL"
        case .thinkspace: return "THINKSPACE"
        case .cluster: return "CLUSTER"
        }
    }

    private func scopeOrder(_ a: AutomationScope, _ b: AutomationScope) -> Bool {
        let order: [AutomationScope] = [.global, .thinkspace, .cluster]
        let aIdx = order.firstIndex(of: a) ?? 0
        let bIdx = order.firstIndex(of: b) ?? 0
        return aIdx < bIdx
    }
}
