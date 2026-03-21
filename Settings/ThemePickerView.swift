// CosmoOS/Settings/ThemePickerView.swift
// Premium theme selector — horizontal scroll of theme preview cards.

import SwiftUI

struct ThemePickerView: View {
    @State private var themeManager = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            ThemePickerHeader()
            ThemePickerGrid(selectedTheme: themeManager.currentTheme) { theme in
                themeManager.setTheme(theme)
            }
        }
    }
}

// MARK: - Header

private struct ThemePickerHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            Text("APPEARANCE")
                .font(DS.sectionLabel)
                .foregroundStyle(DS.textMuted)
                .tracking(0.88)
            Text("Choose a theme that matches your mood")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
        }
    }
}

// MARK: - Grid

private struct ThemePickerGrid: View {
    let selectedTheme: CosmoAppTheme
    let onSelect: (CosmoAppTheme) -> Void

    var body: some View {
        HStack(spacing: DS.space12) {
            ForEach(CosmoAppTheme.allCases) { theme in
                ThemePreviewCard(
                    theme: theme,
                    isSelected: theme == selectedTheme,
                    onSelect: { onSelect(theme) }
                )
            }
        }
    }
}

// MARK: - Preview Card

private struct ThemePreviewCard: View {
    let theme: CosmoAppTheme
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    private var pal: ThemePalette { theme.palette }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                ThemePreviewSwatch(palette: pal)
                ThemePreviewLabel(theme: theme)
            }
            .clipShape(.rect(cornerRadius: DS.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .stroke(isSelected ? DS.accent : DS.border, lineWidth: isSelected ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    SelectedCheckmark()
                }
            }
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(duration: 0.2, bounce: 0.0), value: isHovered)
            .animation(.spring(duration: 0.25, bounce: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Swatch Preview

private struct ThemePreviewSwatch: View {
    let palette: ThemePalette

    var body: some View {
        ZStack {
            palette.bg
            VStack(spacing: DS.space6) {
                RoundedRectangle(cornerRadius: DS.radiusXSmall)
                    .fill(palette.surfaceElevated)
                    .frame(height: 28)
                    .overlay(alignment: .leading) {
                        HStack(spacing: DS.space4) {
                            Circle()
                                .fill(palette.accent)
                                .frame(width: 8, height: 8)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(palette.text.opacity(0.6))
                                .frame(width: 40, height: 4)
                        }
                        .padding(.leading, DS.space8)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusXSmall)
                            .stroke(palette.border, lineWidth: 0.5)
                    )

                HStack(spacing: DS.space4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(palette.textSecondary.opacity(0.5))
                        .frame(width: 24, height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(palette.textMuted.opacity(0.4))
                        .frame(width: 16, height: 3)
                    Spacer()
                }
            }
            .padding(DS.space8)
        }
        .frame(height: 64)
    }
}

// MARK: - Label

private struct ThemePreviewLabel: View {
    let theme: CosmoAppTheme

    var body: some View {
        VStack(spacing: DS.space2) {
            HStack(spacing: DS.space4) {
                Image(systemName: theme.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(DS.accent)
                Text(theme.displayName)
                    .font(DS.caption)
                    .foregroundStyle(DS.text)
            }
            Text(theme.tagline)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)
        }
        .padding(.vertical, DS.space8)
        .padding(.horizontal, DS.space6)
        .frame(maxWidth: .infinity)
        .background(DS.surfaceElevated)
    }
}

// MARK: - Checkmark

private struct SelectedCheckmark: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 16))
            .foregroundStyle(DS.accent)
            .background(Circle().fill(DS.surfaceElevated).padding(2))
            .offset(x: -DS.space6, y: DS.space6)
    }
}
