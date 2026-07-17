// CosmoOS/UI/FocusMode/Connection/ConnectionSectionCardView.swift
// June 2026 — Connection workspace revamp.
// One scannable card per section on the board: header with count, up to three
// item previews, and a quick-add field. Clicking the header opens the section
// detail in the center column.

import SwiftUI

struct ConnectionSectionCardView: View {
    let section: ConnectionSection
    var isSelected: Bool = false
    var highlightQuery: String = ""
    /// Staged concept-collaborator inserts for this section, rendered as ghost
    /// rows with inline ✓/✗ below the real items.
    var pendingInserts: [ConnectionPendingInsert] = []

    var onOpen: () -> Void = {}
    var onSelect: () -> Void = {}
    var onAddItem: (RichDocument, String) -> Void = { _, _ in }
    var onSourceTap: (String) -> Void = { _ in }
    var onAcceptInsert: (ConnectionPendingInsert) -> Void = { _ in }
    var onRejectInsert: (ConnectionPendingInsert) -> Void = { _ in }

    @State private var isHovered = false

    private var accent: Color { section.type.accentColor }
    private var previewItems: [ConnectionItem] { Array(section.items.prefix(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            header
            if section.items.isEmpty && pendingInserts.isEmpty {
                emptyPrompt
            } else if !section.items.isEmpty {
                previewList
            }
            if !pendingInserts.isEmpty {
                pendingList
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
        .accessibilityLabel("\(section.type.displayName), \(section.itemCount) items")
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
        }
    }

    // MARK: - Staged inserts

    private var pendingList: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            ForEach(pendingInserts) { insert in
                ConnectionPendingInsertRow(
                    insert: insert,
                    accent: accent,
                    onAccept: onAcceptInsert,
                    onReject: onRejectInsert
                )
            }
        }
        .transition(.opacity)
    }
}

// MARK: - Staged insert row (ghost)

/// A not-yet-accepted concept-collaborator insert shown in place — dashed,
/// accent-tinted, with the proposed bullet(s) and a ✓/✗ pair. Accepting routes
/// through the same per-operation apply path as the old full-screen diff.
struct ConnectionPendingInsertRow: View {
    let insert: ConnectionPendingInsert
    let accent: Color
    var onAccept: (ConnectionPendingInsert) -> Void = { _ in }
    var onReject: (ConnectionPendingInsert) -> Void = { _ in }

    var body: some View {
        HStack(alignment: .top, spacing: DS.space8) {
            // Sparkles = collaborator proposal; tray = your own captured
            // material waiting to be swept in (inbox feed, seedling develop).
            Image(systemName: insert.isFromCapture ? "tray.and.arrow.down" : "sparkles")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.top, 3)
                .accessibilityHidden(true)

            // Each bullet previews as its own dotted row — the exact rows that
            // will land in the section — so a multi-item capture never reads
            // as one blob before it's accepted.
            VStack(alignment: .leading, spacing: DS.space6) {
                ForEach(Array(insert.bullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .top, spacing: DS.space8) {
                        Circle()
                            .fill(accent.opacity(0.9))
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                            .accessibilityHidden(true)
                        Text(bullet)
                            .font(DS.callout)
                            .foregroundStyle(DS.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            HStack(spacing: DS.space4) {
                decisionButton(system: "checkmark", tint: accent, label: "Accept") { onAccept(insert) }
                decisionButton(system: "xmark", tint: DS.textMuted, label: "Dismiss") { onReject(insert) }
            }
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space6)
        .background(accent.opacity(0.08), in: .rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(accent.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            insert.isFromCapture
                ? "From your inbox, waiting to be swept in: \(insert.bullets.joined(separator: ", "))"
                : "Suggested for this section: \(insert.bullets.joined(separator: ", "))"
        )
    }

    private func decisionButton(
        system: String,
        tint: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.12), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
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
