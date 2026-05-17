import SwiftUI

struct CommandKActionPanelRow: View {
    let action: CommandKContextualAction
    let isSelected: Bool
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            HStack(spacing: DS.space12) {
                icon

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(DS.body)
                        .foregroundStyle(titleColor)
                        .lineLimit(1)

                    if let subtitle {
                        Text(subtitle)
                            .font(DS.caption)
                            .foregroundStyle(DS.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: DS.space12)

                if let shortcut = action.shortcut {
                    Text(shortcut.label)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(DS.inkFaded)
                }
            }
            .padding(.horizontal, DS.space12)
            .frame(height: 48)
            .background(rowBackground)
            .clipShape(.rect(cornerRadius: DS.radiusSmall))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!action.availability.isEnabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var icon: some View {
        Image(systemName: action.systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(iconColor)
            .frame(width: 28, height: 28)
            .background(iconColor.opacity(action.availability.isEnabled ? 0.10 : 0.04), in: .rect(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(iconColor.opacity(action.availability.isEnabled ? 0.22 : 0.10), lineWidth: 0.5)
            }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
            .fill(isSelected ? DS.accentSoft : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
                    .strokeBorder(isSelected ? DS.borderActive.opacity(0.55) : Color.clear, lineWidth: 0.5)
            }
    }

    private var iconColor: Color {
        if action.role == .destructive { return DS.red }
        return action.availability.isEnabled ? DS.accent : DS.textMuted
    }

    private var titleColor: Color {
        action.availability.isEnabled ? DS.text : DS.textMuted
    }

    private var subtitle: String? {
        if let subtitle = action.subtitle { return subtitle }
        if case .disabled(let reason) = action.availability { return reason }
        return nil
    }

    private var accessibilityLabel: String {
        if let subtitle {
            return "\(action.title), \(subtitle)"
        }
        return action.title
    }
}

private extension CommandKActionShortcut {
    var label: String {
        switch self {
        case .returnKey: return "return"
        case .commandK: return "cmd K"
        case .commandS: return "cmd S"
        case .commandI: return "cmd I"
        case .commandT: return "cmd T"
        case .shiftCommandP: return "shift cmd P"
        }
    }
}
