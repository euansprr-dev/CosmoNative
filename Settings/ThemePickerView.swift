// CosmoOS/Settings/ThemePickerView.swift
// Appearance — iOS Settings parity: System/Light/Dark switch, then the two
// theme identities as cards, each showing its day and night face. Fixed,
// width-constrained layout (the old 7-card HStack overflowed the panel and
// cropped the sidebar).

import SwiftUI

struct ThemePickerView: View {
    @State private var themeManager = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            SettingsSectionHeader(label: "APPEARANCE")

            appearanceSwitch

            HStack(spacing: DS.space12) {
                ForEach(ThemeFamily.allCases) { family in
                    ThemeFamilyCard(
                        family: family,
                        isActive: themeManager.family == family,
                        onSelect: { themeManager.setFamily(family) }
                    )
                }
                Spacer(minLength: 0)
            }

            Text("Each theme has a day and a night face — follow the system or pin one.")
                .font(DS.footnote)
                .foregroundStyle(DS.textMuted)
        }
    }

    // MARK: - System / Light / Dark

    private var appearanceSwitch: some View {
        HStack(spacing: 3) {
            ForEach(ThemeAppearance.allCases) { candidate in
                let isSelected = themeManager.appearance == candidate
                Button {
                    themeManager.setAppearance(candidate)
                } label: {
                    Text(candidate.label)
                        .font(DS.callout)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? DS.text : DS.textMuted)
                        .frame(maxWidth: .infinity)
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
                .help(candidate == .system ? "Follow macOS appearance" : "Pin the \(candidate.label.lowercased()) face")
            }
        }
        .padding(3)
        .background(DS.glassSectionFill, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(DS.glassBorder, lineWidth: 1))
        .frame(maxWidth: 340)
        .animation(ProMotionSprings.snappy, value: themeManager.appearance)
    }
}

// MARK: - Family card

/// One theme identity: its day and night faces side by side, name + tagline.
private struct ThemeFamilyCard: View {
    let family: ThemeFamily
    let isActive: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: DS.space8) {
                HStack(spacing: DS.space6) {
                    FacePreview(palette: family.lightPalette)
                    FacePreview(palette: family.darkPalette)
                }
                .padding(DS.space6)
                .background(DS.glassSectionFill, in: .rect(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isActive ? DS.accent : DS.glassBorder, lineWidth: isActive ? 1.5 : 1)
                )

                VStack(spacing: 1) {
                    Text(family.label)
                        .font(DS.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(isActive ? DS.text : DS.textSecondary)
                    Text(family.tagline)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(1)
                }
            }
            .contentShape(.rect)
            .scaleEffect(isHovered ? 1.01 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help("Switch to the \(family.label) theme")
        .accessibilityLabel("\(family.label) theme\(isActive ? ", active" : "")")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

/// One face at swatch scale: background, a text ladder, the accent.
private struct FacePreview: View {
    let palette: ThemePalette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.bg)
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(palette.text).frame(width: 34, height: 5)
                Capsule().fill(palette.textMuted).frame(width: 22, height: 4)
                Capsule().fill(palette.accent).frame(width: 14, height: 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, DS.space10)
        }
        .frame(width: 76, height: 52)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.border, lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }
}
