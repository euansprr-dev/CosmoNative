// CosmoOS/UI/FocusMode/Connection/ConnectionSectionCardView.swift
// June 2026 — Connection workspace revamp.
// One scannable card per section on the board: header with count, up to three
// item previews, inline ghost suggestions, and a quick-add field. Clicking the
// header opens the section detail in the center column.

import SwiftUI

struct ConnectionSectionCardView: View {
    let section: ConnectionSection
    var isSelected: Bool = false
    var highlightQuery: String = ""

    var onOpen: () -> Void = {}
    var onSelect: () -> Void = {}
    var onAddItem: (RichDocument, String) -> Void = { _, _ in }
    var onAcceptGhost: (GhostSuggestion) -> Void = { _ in }
    var onDismissGhost: (UUID) -> Void = { _ in }
    var onSourceTap: (String) -> Void = { _ in }

    @State private var isHovered = false

    private var accent: Color { section.type.accentColor }
    private var previewItems: [ConnectionItem] { Array(section.items.prefix(3)) }
    private var previewGhosts: [GhostSuggestion] { Array(section.ghostSuggestions.prefix(2)) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            header
            if section.items.isEmpty && previewGhosts.isEmpty {
                emptyPrompt
            } else {
                previewList
            }
            ConnectionQuickAddField(accent: accent, sectionName: section.type.displayName, onSubmit: onAddItem)
        }
        .padding(DS.space16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(cardSurface)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(cardBorder)
        .shadow(
            color: .black.opacity(isHovered ? 0.10 : 0.05),
            radius: isHovered ? 10 : 4,
            y: isHovered ? 4 : 1
        )
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .contentShape(.rect(cornerRadius: 12))
        .onTapGesture(count: 2) { onOpen() }
        .simultaneousGesture(TapGesture().onEnded { onSelect() })
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(section.type.displayName), \(section.itemCount) items, \(section.ghostSuggestions.count) suggestions")
    }

    private var cardSurface: some ShapeStyle {
        DS.surfaceElevated
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(
                isSelected ? accent.opacity(0.55) : (isHovered ? DS.border : DS.borderSubtle),
                lineWidth: isSelected ? 1.2 : 1
            )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: section.type.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 16)
                .accessibilityHidden(true)

            Text(section.type.displayName)
                .font(DS.headline)
                .foregroundStyle(DS.text)

            if section.itemCount > 0 {
                Text("\(section.itemCount)")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, DS.space6)
                    .padding(.vertical, 1)
                    .background(DS.border.opacity(0.6), in: Capsule())
            }

            Spacer(minLength: 0)

            Button(action: onOpen) {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .help("Open \(section.type.displayName)")
            .accessibilityLabel("Open \(section.type.displayName)")
        }
    }

    // MARK: - Body content

    private var emptyPrompt: some View {
        Text(section.type.promptQuestion)
            .font(DS.callout)
            .italic()
            .foregroundStyle(DS.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DS.space2)
    }

    private var previewList: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            ForEach(previewItems) { item in
                ConnectionItemPreviewRow(item: item, accent: accent, highlightQuery: highlightQuery)
            }
            if section.itemCount > previewItems.count {
                Button(action: onOpen) {
                    Text("\(section.itemCount - previewItems.count) more…")
                        .font(DS.caption)
                        .foregroundStyle(DS.textSecondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 13)
            }
            ForEach(previewGhosts) { ghost in
                ConnectionGhostRow(
                    ghost: ghost,
                    accent: accent,
                    onAccept: { onAcceptGhost(ghost) },
                    onDismiss: { onDismissGhost(ghost.id) },
                    onSourceTap: { onSourceTap(ghost.sourceAtomUUID) }
                )
            }
        }
    }
}

// MARK: - Item preview row

struct ConnectionItemPreviewRow: View {
    let item: ConnectionItem
    let accent: Color
    var highlightQuery: String = ""
    var lineLimit: Int = 2

    private var isMatch: Bool {
        !highlightQuery.isEmpty &&
        item.resolvedPlainText.localizedCaseInsensitiveContains(highlightQuery)
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.space8) {
            if item.isConnectionLink {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(CosmoMentionColors.connection)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
            } else {
                Circle()
                    .fill(accent.opacity(0.9))
                    .frame(width: 5, height: 5)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
            }
            Text(item.resolvedPlainText)
                .font(DS.callout)
                .foregroundStyle(item.isConnectionLink ? CosmoMentionColors.connection : DS.text)
                .lineLimit(lineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, isMatch ? DS.space4 : 0)
        .background(isMatch ? accent.opacity(0.10) : .clear, in: .rect(cornerRadius: 4))
    }
}

// MARK: - Ghost suggestion row

struct ConnectionGhostRow: View {
    let ghost: GhostSuggestion
    let accent: Color
    let onAccept: () -> Void
    let onDismiss: () -> Void
    var onSourceTap: () -> Void = {}

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Image(systemName: "sparkle")
                .font(.system(size: 8))
                .foregroundStyle(accent.opacity(0.7))
                .padding(.top, 4)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DS.space2) {
                Text(ghost.content)
                    .font(DS.callout)
                    .italic()
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(2)
                Button(action: onSourceTap) {
                    Text(ghost.sourceAtomTitle)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .help("Open source")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: DS.space4) {
                Button(action: onAccept) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 20, height: 20)
                        .background(accent.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Accept suggestion")

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DS.textMuted)
                        .frame(width: 20, height: 20)
                        .background(DS.border.opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss suggestion")
            }
            .opacity(isHovered ? 1 : 0.55)
        }
        .padding(DS.space8)
        .background(accent.opacity(0.05), in: .rect(cornerRadius: 8))
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
    }
}

// MARK: - Quick add

struct ConnectionQuickAddField: View {
    let accent: Color
    let sectionName: String
    let onSubmit: (RichDocument, String) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isFocused ? accent : DS.textMuted)
                .accessibilityHidden(true)
            TextField("Add to \(sectionName)", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .lineLimit(1...4)
                .focused($isFocused)
                .onSubmit(submit)
                .onKeyPress(.escape) {
                    text = ""
                    isFocused = false
                    return .handled
                }
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space6)
        .background(isFocused ? DS.bg : .clear, in: .rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isFocused ? accent.opacity(0.4) : DS.borderSubtle.opacity(0.6), lineWidth: 1)
        )
        .animation(ProMotionSprings.hover, value: isFocused)
        .accessibilityLabel("Add item to \(sectionName)")
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(RichDocument.migrateLegacy(trimmed), trimmed)
        text = ""
    }
}
