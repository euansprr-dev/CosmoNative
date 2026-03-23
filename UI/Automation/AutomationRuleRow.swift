// CosmoOS/UI/Automation/AutomationRuleRow.swift
// Single rule row component for the automation management panel
// Shows name, natural language description, fire count, scope dot, enable toggle

import SwiftUI

struct AutomationRuleRow: View {

    let rule: AutomationRule
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void

    @State private var isHovered = false
    @State private var isEditingName = false
    @State private var editedName = ""

    var body: some View {
        HStack(spacing: 10) {
            scopeDot
            ruleInfo
            Spacer(minLength: 0)
            statsSection
            enableToggle
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? DS.surfaceHover : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
        .contextMenu {
            Button {
                onToggle()
            } label: {
                Label(
                    rule.isEnabled ? "Disable" : "Enable",
                    systemImage: rule.isEnabled ? "pause.circle" : "play.circle"
                )
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Rule", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rule.name), \(rule.isEnabled ? "enabled" : "disabled"), fired \(rule.fireCount) times")
    }

    // MARK: - Scope Dot

    private var scopeDot: some View {
        Circle()
            .fill(scopeColor)
            .frame(width: 6, height: 6)
    }

    private var scopeColor: Color {
        switch rule.scope {
        case .global: return DS.green
        case .thinkspace: return DS.info
        case .cluster: return DS.orange
        }
    }

    // MARK: - Rule Info

    private var ruleInfo: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(rule.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(rule.isEnabled ? DS.text : DS.textMuted)
                    .lineLimit(1)

                if rule.isBuiltIn {
                    Text("BUILT-IN")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DS.textMuted)
                        .tracking(0.6)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(DS.surfaceHover)
                        )
                }
            }

            Text(rule.naturalLanguageDescription)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DS.textMuted)
                .lineLimit(2)
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if rule.fireCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .semibold))
                    Text("\(rule.fireCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(DS.textMuted)
            }

            if let lastFired = rule.lastFiredAt {
                Text(relativeTime(lastFired))
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(DS.textMuted.opacity(0.7))
            }
        }
    }

    // MARK: - Toggle

    private var enableToggle: some View {
        Button {
            onToggle()
        } label: {
            RoundedRectangle(cornerRadius: 7)
                .fill(rule.isEnabled ? DS.accent : DS.surfaceHover)
                .frame(width: 28, height: 16)
                .overlay(
                    Circle()
                        .fill(.white)
                        .frame(width: 12, height: 12)
                        .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                        .offset(x: rule.isEnabled ? 5 : -5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(rule.isEnabled ? DS.accent : DS.border, lineWidth: 0.5)
                )
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: rule.isEnabled)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rule.isEnabled ? "Disable" : "Enable")
    }

    // MARK: - Helpers

    private func relativeTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: isoString) else { return "" }
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
