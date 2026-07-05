// CosmoOS/UI/FocusMode/DeepDive/DeepDiveDossierSections.swift
// The dossier grammar for the Study overview: one section-header voice with
// live counts, one grouped-pane container (the Files grammar — rows share a
// single surface with hairline separators, never per-row cards), teaching
// rows for every absence, and the arrival cascade.

import SwiftUI

// MARK: - Section header (the one header voice)

struct StudySectionHeader: View {
    let label: String
    var count: Int?

    var body: some View {
        HStack(spacing: DS.space6) {
            Text(label)
                .font(CosmoTypography.labelSmall)
                .tracking(2)
                .foregroundStyle(CosmoColors.textSecondary.opacity(0.78))
            Spacer()
            if let count {
                Text("\(count)")
                    .font(CosmoTypography.caption)
                    .monospacedDigit()
                    .foregroundStyle(CosmoColors.textTertiary)
                    .contentTransition(.numericText())
            }
        }
    }
}

// MARK: - Grouped pane (the Files grammar container)

/// One shared surface for a section's rows — hairline separators inset to the
/// text column; rows never carry their own borders or shadows.
struct StudyPane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background(DS.surfaceElevated, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
    }
}

/// Hairline between pane rows, inset to the text column.
struct StudyPaneDivider: View {
    var body: some View {
        Divider()
            .overlay(DS.borderSubtle)
            .padding(.leading, DS.space12)
    }
}

/// A section = header + pane, always in that order.
struct StudySection<Content: View>: View {
    let label: String
    var count: Int?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            StudySectionHeader(label: label, count: count)
            StudyPane { content }
        }
    }
}

// MARK: - Teaching + overflow rows

/// An absence is never silence — it's a quiet row that names the next action.
struct StudyTeachingRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(CosmoTypography.bodySmall)
            .foregroundStyle(CosmoColors.textTertiary)
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "+N more ›" tail row that expands the section in place.
struct StudyOverflowRow: View {
    let hiddenCount: Int
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) { isExpanded.toggle() }
        } label: {
            HStack(spacing: DS.space6) {
                Text(isExpanded ? "Show fewer" : "+\(hiddenCount) more")
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(CosmoColors.textTertiary)
                    .accessibilityHidden(true)
                Spacer()
            }
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Show fewer" : "Show \(hiddenCount) more")
    }
}

// MARK: - Generic pane row

/// The standard row anatomy: leading dot/glyph · text · muted trailing detail
/// · hover chevron. Hover lifts quietly; accent never appears at rest.
struct StudyPaneRow<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    let title: String
    var subtitle: String?
    var titleLineLimit: Int = 1
    @ViewBuilder let trailing: Trailing
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space8) {
                leading
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(CosmoTypography.body)
                        .foregroundStyle(CosmoColors.textPrimary)
                        .lineLimit(titleLineLimit)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(CosmoTypography.caption)
                            .foregroundStyle(CosmoColors.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DS.space8)
                trailing
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CosmoColors.textTertiary)
                    .opacity(isHovered ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space8)
            .background(isHovered ? DS.surface.opacity(0.7) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
    }
}

// MARK: - Arrival cascade

/// Sections rise in once on first load — an arrival, not a loop.
struct StudyCascade: ViewModifier {
    let hasAppeared: Bool
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared || reduceMotion ? 0 : 6)
            .animation(
                ProMotionSprings.gentle.delay(Double(min(index, 8)) * 0.06),
                value: hasAppeared
            )
    }
}

extension View {
    func studyCascade(_ hasAppeared: Bool, index: Int) -> some View {
        modifier(StudyCascade(hasAppeared: hasAppeared, index: index))
    }
}
