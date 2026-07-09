// CosmoOS/UI/CommandK/Forms/CommandKComposerRows.swift
// The shared chassis every ⌘K composer form is built from — "one sheet of
// paper": boxless hero fields written directly on the pane, ONE grouped
// rows container (the Files grammar: icon + label | control rows with
// hairline separators), the single section-label voice with live counts,
// and tint-wash chips (selection = soft wash + hairline, never solid fill).

import SwiftUI

// MARK: - Hero fields (boxless, written on the pane itself)

/// The form's hero — the title, written directly on the paper. No input box;
/// the entity-tinted caret and placeholder carry the affordance.
struct CommandKComposerHeroTitleField: View {
    let placeholder: String
    @Binding var text: String
    let accent: Color
    var focus: FocusState<CommandKComposerField?>.Binding
    var field: CommandKComposerField = .lead
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(DS.title2.weight(.semibold))
            .foregroundStyle(DS.text)
            .tint(accent)
            .lineLimit(1...3)
            .focused(focus, equals: field)
            .onSubmit(onSubmit)
    }
}

/// A quieter multi-line companion under the hero (notes, the idea itself,
/// a note's opening paragraph). Boxless like the hero — same sheet of paper.
struct CommandKComposerHeroEditor: View {
    let placeholder: String
    @Binding var text: String
    let accent: Color
    var focus: FocusState<CommandKComposerField?>.Binding
    let field: CommandKComposerField
    var minHeight: CGFloat = 44
    var lineLimit: ClosedRange<Int> = 2...10

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(DS.callout)
            .foregroundStyle(DS.textSecondary)
            .tint(accent)
            .lineLimit(lineLimit)
            .frame(minHeight: minHeight, alignment: .topLeading)
            .focused(focus, equals: field)
    }
}

// MARK: - The grouped rows container (one container grammar per form)

/// One grouped container for everything below the hero. Rows are never
/// individual cards; separators are hairlines inset to the text column.
struct CommandKComposerRowGroup<Content: View>: View {
    var separatorInset: CGFloat = 40
    @ViewBuilder var content: Content

    var body: some View {
        Group(subviews: content) { subviews in
            VStack(spacing: 0) {
                ForEach(Array(subviews.enumerated()), id: \.element.id) { index, subview in
                    subview
                    if index < subviews.count - 1 {
                        Rectangle()
                            .fill(DS.glassBorder)
                            .frame(height: 0.5)
                            .padding(.leading, separatorInset)
                    }
                }
            }
        }
        .background(DS.glassSectionFill, in: .rect(cornerRadius: DS.radiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .strokeBorder(DS.glassBorder, lineWidth: 0.5)
        )
    }
}

/// `icon + label | control` — the only row shape inside a row group.
struct CommandKComposerRow<Control: View>: View {
    let icon: String
    let label: String
    var labelColor: Color = DS.text
    var help: String? = nil
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: DS.space10) {
            Image(systemName: icon)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(label)
                .font(DS.callout)
                .foregroundStyle(labelColor)
            Spacer(minLength: DS.space8)
            control()
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space10)
        .help(help ?? label)
    }
}

/// A full-bleed row for custom content (chips rows, checklist entries,
/// segmented controls) that still lives inside the one container.
struct CommandKComposerCustomRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space10)
    }
}

// MARK: - Section label (the one header voice)

struct CommandKComposerSectionLabel: View {
    let label: String
    var count: Int? = nil

    var body: some View {
        HStack(spacing: DS.space6) {
            Text(label.uppercased())
                .font(DS.caption2.weight(.semibold))
                .kerning(0.8)
                .foregroundStyle(DS.textMuted)
            if let count, count > 0 {
                Text("· \(count)")
                    .font(DS.caption2.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Chips (selection = tint wash + hairline; never a solid fill)

struct CommandKComposerChoiceChip: View {
    let label: String
    var icon: String? = nil
    let isOn: Bool
    let tint: Color
    var help: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space6) {
                if let icon {
                    Image(systemName: icon)
                        .font(DS.caption2)
                        .accessibilityHidden(true)
                }
                Text(label)
                    .font(DS.caption.weight(isOn ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? tint : DS.textSecondary)
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space6)
            .background(
                isOn ? tint.opacity(0.13) : DS.glassSectionFill.opacity(isHovered ? 1 : 0.65),
                in: .capsule
            )
            .overlay(
                Capsule().strokeBorder(
                    isOn ? tint.opacity(0.35) : DS.glassBorder,
                    lineWidth: isOn ? 1 : 0.5
                )
            )
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.snappy, value: isOn)
        .help(help ?? label)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// The one small × affordance for list rows (hooks, checklist, slides,
/// linked swipes) — quiet until hovered.
struct CommandKComposerRemoveButton: View {
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(DS.caption)
                .foregroundStyle(isHovered ? DS.textSecondary : DS.textMuted.opacity(0.6))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Trailing value affordance inside a row — muted "None" until set, then the
/// value in ink with a quiet chevron. Wrap in a Menu for picker rows.
struct CommandKComposerRowValueLabel: View {
    let text: String
    let isSet: Bool
    var tint: Color = DS.accent

    var body: some View {
        HStack(spacing: DS.space4) {
            Text(text)
                .font(DS.caption.weight(isSet ? .medium : .regular))
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(DS.caption2.weight(.semibold))
                .imageScale(.small)
                .accessibilityHidden(true)
        }
        .foregroundStyle(isSet ? tint : DS.textMuted)
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space4)
        .background(
            (isSet ? tint : DS.textMuted).opacity(0.08),
            in: .capsule
        )
        .contentShape(.capsule)
    }
}
