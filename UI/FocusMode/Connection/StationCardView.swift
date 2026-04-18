// CosmoOS/UI/FocusMode/Connection/StationCardView.swift
// April 2026 — governed Forge station card
//
// Compact by default, fully editable when expanded. The Forge owns expansion
// and reflow; the card owns capture, committed insight editing, and whisper
// actions without relying on internal scroll regions.

import SwiftUI

struct StationCardView: View {

    enum DisplayMode {
        case collapsed
        case expanded
        case focus

        var showsFullContent: Bool {
            self != .collapsed
        }
    }

    @Binding var section: ConnectionSection

    let onAddItem: (RichDocument, String) -> Void
    let onEditItem: (ConnectionItem) -> Void
    let onDeleteItem: (UUID) -> Void
    let onSourceTap: (String) -> Void
    let onAcceptGhost: (GhostSuggestion) -> Void
    let onDismissGhost: (UUID) -> Void

    var displayMode: DisplayMode = .collapsed
    var isSelected: Bool = false
    var onSelect: (() -> Void)? = nil
    var onEnterStationMode: (() -> Void)? = nil
    var onHoverChange: ((Bool) -> Void)? = nil
    var cardWidth: CGFloat = 260

    @State private var isHovered = false
    @State private var isAddingItem = false
    @State private var newItemText = ""
    @FocusState private var newItemFocused: Bool

    private var accent: Color { section.type.accentColor }
    private var previewItems: ArraySlice<ConnectionItem> { section.items.prefix(2) }
    private var showsExpandButton: Bool { onSelect != nil }
    private var showsFocusButton: Bool { displayMode == .expanded && onEnterStationMode != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            promptLine
            hairline
            if displayMode.showsFullContent {
                expandedContent
            } else {
                collapsedContent
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(width: cardWidth, alignment: .topLeading)
        .background(surface)
        .overlay(alignment: .topLeading) { giltCorner }
        .overlay(alignment: .top) { selectionHandle }
        .clipShape(.rect(cornerRadius: 6))
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }
            onHoverChange?(hovering)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Station: \(section.type.displayName), \(section.itemCount) insights, \(section.ghostSuggestions.count) whispers")
    }

    private var surface: some View {
        ZStack {
            Rectangle().fill(DS.vellum)
            Rectangle().stroke(DS.sepiaBorder, lineWidth: 0.5)
            if isSelected || isHovered {
                Rectangle()
                    .stroke(accent.opacity(isSelected ? 0.55 : 0.28), lineWidth: isSelected ? 1.0 : 0.6)
            }
        }
    }

    private var giltCorner: some View {
        GiltCornerBracket()
            .stroke(DS.gilt.opacity(0.78), lineWidth: 0.8)
            .frame(width: 14, height: 14)
            .padding(6)
            .allowsHitTesting(false)
    }

    private var selectionHandle: some View {
        Rectangle()
            .fill(accent.opacity(isSelected ? 0.72 : 0))
            .frame(width: 40, height: 2)
            .padding(.top, 4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)

            Text(section.type.displayName.uppercased())
                .font(DS.smallCaps)
                .tracking(1.6)
                .foregroundStyle(DS.inkWash)

            Spacer()

            if section.itemCount > 0 {
                Text("\(section.itemCount)")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(DS.inkFaded)
            }

            if showsFocusButton {
                Button {
                    onEnterStationMode?()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DS.giltMuted)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open station mode")
            }

            if showsExpandButton {
                Button {
                    onSelect?()
                } label: {
                    Image(systemName: displayMode == .collapsed ? "plus.circle" : "minus.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(displayMode == .collapsed ? accent : DS.giltMuted)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(displayMode == .collapsed ? "Expand station" : "Collapse station")
            }
        }
    }

    private var promptLine: some View {
        Text(section.type.promptQuestion)
            .font(.system(size: 11, weight: .regular, design: .serif))
            .italic()
            .foregroundStyle(DS.inkFaded)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hairline: some View {
        Rectangle()
            .fill(DS.sepiaSubtle)
            .frame(height: 0.5)
    }

    @ViewBuilder
    private var collapsedContent: some View {
        if previewItems.isEmpty && section.ghostSuggestions.isEmpty {
            Text("Ready for the first sharp insight.")
                .font(.system(size: 12, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(DS.inkFaded)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(previewItems), id: \.id) { item in
                    StationPreviewRow(item: item, accent: accent)
                }
                summaryLine
            }
        }
        addBar
    }

    private var summaryLine: some View {
        HStack(spacing: 6) {
            if !section.ghostSuggestions.isEmpty {
                Text("\(section.ghostSuggestions.count) whispers")
                    .font(.system(size: 10, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(DS.giltMuted)
            }
            if section.itemCount > previewItems.count {
                Text("+\(section.itemCount - previewItems.count) more")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(DS.inkFaded)
            }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !section.items.isEmpty {
                itemsList
            }
            whisperList
            captureRow
        }
    }

    private var itemsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(section.items) { item in
                StationItemRow(
                    item: item,
                    accent: accent,
                    onEdit: onEditItem,
                    onDelete: { onDeleteItem(item.id) },
                    onSourceTap: onSourceTap
                )
            }
        }
    }

    @ViewBuilder
    private var whisperList: some View {
        if section.showGhostSuggestions, !section.ghostSuggestions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(section.ghostSuggestions) { ghost in
                    StationWhisperRow(
                        suggestion: ghost,
                        accent: accent,
                        onAccept: { onAcceptGhost(ghost) },
                        onDismiss: { onDismissGhost(ghost.id) },
                        onSourceTap: { onSourceTap(ghost.sourceAtomUUID) }
                    )
                }
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var captureRow: some View {
        if isAddingItem {
            captureField
        } else {
            addBar
        }
    }

    private var addBar: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                isAddingItem = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                newItemFocused = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                Text("add insight")
                    .font(.system(size: 11, weight: .regular, design: .serif))
                    .italic()
            }
            .foregroundStyle(DS.giltMuted.opacity((isHovered || isSelected || displayMode.showsFullContent) ? 1 : 0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add insight to \(section.type.displayName)")
    }

    private var captureField: some View {
        HStack(alignment: .top, spacing: 6) {
            TextField("capture a thought…", text: $newItemText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(DS.inkWash)
                .lineLimit(1...5)
                .focused($newItemFocused)
                .onSubmit { submitCapture() }
                .onKeyPress(.escape) {
                    cancelCapture()
                    return .handled
                }

            Button(action: cancelCapture) {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(DS.inkFaded)
            }
            .buttonStyle(.plain)

            Button(action: submitCapture) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
            .disabled(newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(DS.vellumDeep, in: .rect(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3).stroke(DS.sepiaBorder, lineWidth: 0.5)
        )
    }

    private func submitCapture() {
        let trimmed = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        onAddItem(RichDocument.migrateLegacy(trimmed), trimmed)
        newItemText = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            newItemFocused = true
        }
    }

    private func cancelCapture() {
        withAnimation(ProMotionSprings.snappy) {
            isAddingItem = false
            newItemText = ""
            newItemFocused = false
        }
    }
}

private struct StationPreviewRow: View {
    let item: ConnectionItem
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(accent)
                .frame(width: 5, height: 5)
                .padding(.top, 6)

            Text(item.resolvedPlainText)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(DS.inkWash)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct StationItemRow: View {
    let item: ConnectionItem
    let accent: Color
    let onEdit: (ConnectionItem) -> Void
    let onDelete: () -> Void
    let onSourceTap: (String) -> Void

    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editDocument: RichDocument = .empty

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(accent)
                .frame(width: 5, height: 5)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    CosmoDocumentEditor(
                        document: $editDocument,
                        fontSize: 13,
                        compact: true,
                        placeholder: "",
                        allowSlashCommands: false,
                        allowMentions: true,
                        allowSelectionMenu: false,
                        allowImages: false,
                        onDocumentChange: { document, _ in
                            var updated = item
                            updated.applyDocument(document)
                            onEdit(updated)
                        }
                    )
                    .frame(minHeight: 22)
                } else {
                    Text(item.resolvedPlainText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(DS.inkWash)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let sourceUUID = item.sourceAtomUUID {
                    Button {
                        onSourceTap(sourceUUID)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "link")
                                .font(.system(size: 8))
                            Text("source")
                                .font(.system(size: 9, weight: .regular, design: .serif))
                                .italic()
                        }
                        .foregroundStyle(DS.giltMuted)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)

            trailingControls
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button(isEditing ? "Done Editing" : "Edit Insight") {
                toggleEditing()
            }
            Button("Delete Insight", role: .destructive, action: onDelete)
        }
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
    }

    @ViewBuilder
    private var trailingControls: some View {
        if isEditing {
            Button("Done") {
                isEditing = false
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(accent)
        } else {
            Menu {
                Button("Edit Insight") {
                    toggleEditing()
                }
                Button("Delete Insight", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle((isHovered ? accent : DS.inkFaded).opacity(0.9))
                    .frame(width: 18, height: 18)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func toggleEditing() {
        if !isEditing {
            editDocument = item.resolvedDocument
        }
        isEditing.toggle()
    }
}

private struct StationWhisperRow: View {
    let suggestion: GhostSuggestion
    let accent: Color
    let onAccept: () -> Void
    let onDismiss: () -> Void
    let onSourceTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isHovered)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let breath = 0.5 + 0.08 * sin(2 * .pi * 0.08 * t)
            content(opacity: isHovered ? 0.9 : breath)
        }
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
    }

    @ViewBuilder
    private func content(opacity: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "diamond")
                    .font(.system(size: 8))
                    .foregroundStyle(DS.gilt.opacity(0.7))
                    .padding(.top, 3)

                Text(suggestion.content)
                    .font(.system(size: 11, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(DS.inkWash)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button(action: onSourceTap) {
                    Text("from \(suggestion.sourceAtomTitle)")
                        .font(.system(size: 9, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(DS.giltMuted)
                }
                .buttonStyle(.plain)

                Text("·")
                    .font(.system(size: 9))
                    .foregroundStyle(DS.inkFaded)

                Text("\(suggestion.confidencePercent)%")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(DS.inkFaded)

                Spacer()

                if isHovered {
                    Button(action: onAccept) {
                        Text("crystallize")
                            .font(.system(size: 10, weight: .regular, design: .serif))
                            .italic()
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundStyle(DS.inkFaded)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(DS.vellumDeep.opacity(0.7), in: .rect(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(style: StrokeStyle(lineWidth: 0.5, dash: [2.5, 2.5]))
                .foregroundStyle(DS.gilt.opacity(0.35))
        )
        .opacity(opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Whisper from \(suggestion.sourceAtomTitle), \(suggestion.confidencePercent) percent match")
    }
}

#if DEBUG
#Preview("Station — Collapsed") {
    StationPreviewHarness(type: .goal)
        .padding(40)
        .background(DS.vellum.opacity(0.6))
}

#Preview("Station — Expanded") {
    StationPreviewHarness(type: .problems, mode: .expanded)
        .padding(40)
        .background(DS.vellum.opacity(0.6))
}

private struct StationPreviewHarness: View {
    let type: ConnectionSectionType
    let mode: StationCardView.DisplayMode
    @State private var section: ConnectionSection

    init(type: ConnectionSectionType, mode: StationCardView.DisplayMode = .collapsed) {
        self.type = type
        self.mode = mode
        let items: [ConnectionItem] = [
            ConnectionItem(content: "Identity-shift precedes behavior change."),
            ConnectionItem(
                content: "People change when they adopt a new story about themselves.",
                sourceAtomUUID: "source-uuid"
            )
        ]
        let ghosts: [GhostSuggestion] = [
            GhostSuggestion(
                content: "Framing the goal as identity unlocks all downstream mechanics.",
                sourceAtomUUID: "research-uuid",
                sourceAtomTitle: "Houpert — Transcendence",
                sourceSnippet: "...",
                targetSectionType: type,
                confidence: 0.78
            )
        ]
        self._section = State(initialValue: ConnectionSection(
            type: type,
            items: items,
            ghostSuggestions: ghosts
        ))
    }

    var body: some View {
        StationCardView(
            section: $section,
            onAddItem: { _, _ in },
            onEditItem: { _ in },
            onDeleteItem: { _ in },
            onSourceTap: { _ in },
            onAcceptGhost: { _ in },
            onDismissGhost: { _ in },
            displayMode: mode,
            isSelected: mode == .expanded
        )
    }
}
#endif
