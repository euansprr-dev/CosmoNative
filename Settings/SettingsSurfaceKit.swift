// CosmoOS/Settings/SettingsSurfaceKit.swift
// The Settings surface grammar — the iOS grouped-list language translated to
// the Mac's glass panel: ONE header voice (small-caps + quiet count), ONE
// container per section (flat warm fill on glass, hairline, 14pt), rows with
// inset separators that never carry their own card chrome.

import SwiftUI

// MARK: - Section header

/// The one header voice: small-caps label with an optional quiet detail.
struct SettingsSectionHeader: View {
    let label: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.space8) {
            Text(label)
                .dsSmallCapsLabel()
            Spacer(minLength: DS.space8)
            if let detail {
                Text(detail)
                    .font(DS.caption.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Grouped container

/// One section, one surface. Content stacks inside; separate rows with
/// `SettingsRowDivider`. Inner chrome on glass = flat warm fill, never
/// more glass.
struct SettingsGroupedBox<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.glassCardFill)
        .clipShape(.rect(cornerRadius: DS.radiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .stroke(DS.glassBorder, lineWidth: 1)
        )
    }
}

/// Hairline between rows, inset to the text column.
struct SettingsRowDivider: View {
    var inset: CGFloat = DS.space16

    var body: some View {
        Rectangle()
            .fill(DS.glassBorder)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

// MARK: - Row

/// A standard settings row: tinted icon chip, title + optional subtitle, and
/// a trailing slot (toggle, badge, chevron, button).
struct SettingsRow<Trailing: View>: View {
    let icon: String
    var tint: Color = DS.accent
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: DS.space12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DS.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(DS.text)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.footnote)
                        .foregroundStyle(DS.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: DS.space8)

            trailing
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space10)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Status badge (shared by connection rows)

struct SettingsStatusBadge: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(DS.footnote)
                .foregroundStyle(color)
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space4)
        .background(Capsule().fill(color.opacity(0.1)))
    }
}
