// CosmoOS/Canvas/ClusterRuleIndicator.swift
// Lightning bolt pill that appears in cluster headers when automation rules are active
// Clicking opens a compact popover listing active rules with enable/disable toggles

import SwiftUI

struct ClusterRuleIndicator: View {

    let clusterId: UUID
    let clusterColor: Color
    let ruleCount: Int
    let onAddRule: () -> Void

    @State private var isHovered = false
    @State private var showPopover = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var rules: [AutomationRule] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        indicatorPill
    }

    // MARK: - Pill

    private var indicatorPill: some View {
        Button {
            loadRules()
            showPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .bold))

                if ruleCount > 0 {
                    Text("\(ruleCount)")
                        .font(.system(size: 9, weight: .bold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(ruleCount > 0 ? clusterColor : DS.textMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(ruleCount > 0 ? clusterColor.opacity(0.1) : DS.surfaceHover)
            )
            .overlay(
                Capsule()
                    .stroke(ruleCount > 0 ? clusterColor.opacity(0.2) : DS.borderSubtle, lineWidth: 0.5)
            )
            .scaleEffect(pulseScale)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .popover(isPresented: $showPopover) {
            rulePopoverContent
        }
        .accessibilityLabel("\(ruleCount) automation rules")
        .accessibilityHint("Click to view and manage rules")
    }

    // MARK: - Popover Content

    private var rulePopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(clusterColor)

                Text("Rules")
                    .dsSmallCapsLabel()

                Spacer()

                Button {
                    showPopover = false
                    onAddRule()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.accent)
                        .frame(width: 20, height: 20)
                        .background(
                            Circle().fill(DS.accentSoft)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add new rule")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 12)

            if rules.isEmpty {
                emptyState
            } else {
                rulesList
            }
        }
        .frame(width: 260)
        .background(DS.surfaceElevated)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No rules yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.textMuted)

            Button {
                showPopover = false
                onAddRule()
            } label: {
                Text("Add Rule")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var rulesList: some View {
        VStack(spacing: 0) {
            ForEach(rules, id: \.uuid) { rule in
                RuleListRow(
                    rule: rule,
                    clusterColor: clusterColor,
                    onToggle: {
                        Task {
                            try? await AutomationDispatcher.shared.toggleRule(uuid: rule.uuid)
                            loadRules()
                        }
                    },
                    onDelete: {
                        Task {
                            try? await AutomationDispatcher.shared.deleteRule(uuid: rule.uuid)
                            loadRules()
                        }
                    }
                )
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Data

    private func loadRules() {
        rules = AutomationDispatcher.shared.rules(for: clusterId.uuidString)
    }

    // MARK: - Pulse Animation (called externally via notification)

    func triggerPulse() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
            pulseScale = 1.15
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                pulseScale = 1.0
            }
        }
    }
}

// MARK: - Rule List Row

private struct RuleListRow: View {

    let rule: AutomationRule
    let clusterColor: Color
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Left accent bar
            RoundedRectangle(cornerRadius: 1)
                .fill(rule.isEnabled ? clusterColor : DS.textMuted.opacity(0.3))
                .frame(width: 2, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(rule.isEnabled ? DS.text : DS.textMuted)
                    .lineLimit(1)

                Text(rule.naturalLanguageDescription)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Fire count badge
            if rule.fireCount > 0 {
                Text("\(rule.fireCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(DS.textMuted)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(DS.surfaceHover)
                    )
            }

            // Enable/disable toggle
            Button {
                onToggle()
            } label: {
                Circle()
                    .fill(rule.isEnabled ? DS.accent : DS.surfaceHover)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .stroke(rule.isEnabled ? DS.accent : DS.border, lineWidth: 1)
                    )
                    .overlay {
                        if rule.isEnabled {
                            Image(systemName: "checkmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rule.isEnabled ? "Disable rule" : "Enable rule")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? DS.surfaceHover : Color.clear)
                .padding(.horizontal, 4)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Rule", systemImage: "trash")
            }
        }
    }
}
