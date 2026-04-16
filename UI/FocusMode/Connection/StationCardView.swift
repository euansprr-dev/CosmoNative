// CosmoOS/UI/FocusMode/Connection/StationCardView.swift
// April 2026 — Connection Focus Mode V2 "The Crucible"
//
// A single Station Card. Replaces V1's ConnectionSectionView. Stations live on
// the spatial Forge grid — they can be dragged to rearrange and double-clicked
// to enter Station Mode (full-focus zoom on one dimension).
//
// Visual anatomy:
//   • Gilt corner bracket (top-left)
//   • Drag handle (hover-revealed thin gilt bar, top edge)
//   • Accent dot + small-caps section name + collapse chevron
//   • Italic prompt question
//   • Sepia hairline
//   • Items (5pt accent leading dot)
//   • Ghost whispers (embossed, breathing)
//   • "+ add insight" (unobtrusive capture)

import SwiftUI

struct StationCardView: View {

    // MARK: - Inputs

    @Binding var section: ConnectionSection

    let onAddItem: (RichDocument, String) -> Void
    let onEditItem: (ConnectionItem) -> Void
    let onDeleteItem: (UUID) -> Void
    let onSourceTap: (String) -> Void
    let onAcceptGhost: (GhostSuggestion) -> Void
    let onDismissGhost: (UUID) -> Void

    /// Double-click handler — parent enters Station Mode focus overlay.
    var onEnterStationMode: (() -> Void)? = nil

    /// Hover handler for ley lines — parent can highlight related sources.
    var onHoverChange: ((Bool) -> Void)? = nil

    /// Fixed width in the grid; actual height flows with content.
    var cardWidth: CGFloat = 260

    // MARK: - Local state

    @State private var isHovered: Bool = false
    @State private var isAddingItem: Bool = false
    @State private var newItemText: String = ""
    @State private var newItemDocument: RichDocument = .empty
    @FocusState private var newItemFocused: Bool

    private var accent: Color { section.type.accentColor }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            promptLine
            hairline
            if section.isExpanded {
                itemsList
                whisperList
                captureRow
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(width: cardWidth, alignment: .topLeading)
        .background(surface)
        .overlay(alignment: .topLeading) { giltCorner }
        .overlay(alignment: .top) { dragHandle }
        .clipShape(.rect(cornerRadius: 4))
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
            onHoverChange?(hovering)
        }
        .onTapGesture(count: 2) {
            onEnterStationMode?()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Station: \(section.type.displayName), \(section.itemCount) items, \(section.ghostSuggestions.count) whispers")
    }

    // MARK: - Surface

    private var surface: some View {
        ZStack {
            Rectangle().fill(DS.vellum)
            Rectangle().stroke(DS.sepiaBorder, lineWidth: 0.5)
            if isHovered {
                Rectangle()
                    .stroke(accent.opacity(0.35), lineWidth: 0.6)
            }
        }
    }

    private var giltCorner: some View {
        GiltCornerBracket()
            .stroke(DS.gilt.opacity(0.8), lineWidth: 0.8)
            .frame(width: 14, height: 14)
            .padding(6)
            .allowsHitTesting(false)
    }

    // MARK: - Drag handle (hover-revealed)

    private var dragHandle: some View {
        Rectangle()
            .fill(DS.gilt.opacity(isHovered ? 0.55 : 0))
            .frame(width: 32, height: 2)
            .padding(.top, 4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: - Header

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
            Button {
                withAnimation(ProMotionSprings.snappy) { section.isExpanded.toggle() }
            } label: {
                Image(systemName: section.isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DS.giltMuted)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(section.isExpanded ? "Collapse" : "Expand")
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

    // MARK: - Items

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

    // MARK: - Whispers

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

    // MARK: - Capture

    @ViewBuilder
    private var captureRow: some View {
        if isAddingItem {
            captureField
        } else if isHovered || section.itemCount == 0 {
            addButton
        }
    }

    private var addButton: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) { isAddingItem = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { newItemFocused = true }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                Text("add insight")
                    .font(.system(size: 11, weight: .regular, design: .serif))
                    .italic()
            }
            .foregroundStyle(DS.giltMuted)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add insight to \(section.type.displayName)")
    }

    private var captureField: some View {
        HStack(alignment: .top, spacing: 6) {
            CosmoDocumentEditor(
                document: $newItemDocument,
                fontSize: 12,
                compact: true,
                placeholder: "capture a thought...",
                allowSlashCommands: false,
                allowMentions: true,
                allowSelectionMenu: false,
                allowImages: false,
                onDocumentChange: { _, plainText in newItemText = plainText }
            )
            .frame(minHeight: 24, maxHeight: 96)
            .focused($newItemFocused)

            Button { cancelCapture() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(DS.inkFaded)
            }
            .buttonStyle(.plain)

            Button { submitCapture() } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
            .disabled(newItemText.isEmpty)
            .opacity(newItemText.isEmpty ? 0.4 : 1)
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
        if !trimmed.isEmpty {
            onAddItem(newItemDocument, trimmed)
        }
        cancelCapture()
    }

    private func cancelCapture() {
        withAnimation(ProMotionSprings.snappy) {
            isAddingItem = false
            newItemText = ""
            newItemDocument = .empty
            newItemFocused = false
        }
    }
}

// MARK: - Station item row

private struct StationItemRow: View {
    let item: ConnectionItem
    let accent: Color
    let onEdit: (ConnectionItem) -> Void
    let onDelete: () -> Void
    let onSourceTap: (String) -> Void

    @State private var isHovered: Bool = false
    @State private var isEditing: Bool = false
    @State private var editDocument: RichDocument = .empty

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(accent)
                .frame(width: 5, height: 5)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    CosmoDocumentEditor(
                        document: $editDocument,
                        fontSize: 12,
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
                    CosmoDocumentRenderer(document: item.resolvedDocument)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(DS.inkWash)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if item.hasSource, let sourceUUID = item.sourceAtomUUID {
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

            if isHovered {
                HStack(spacing: 6) {
                    Button {
                        isEditing.toggle()
                        if isEditing { editDocument = item.resolvedDocument }
                    } label: {
                        Image(systemName: isEditing ? "checkmark" : "pencil")
                            .font(.system(size: 9))
                            .foregroundStyle(DS.inkFaded)
                    }
                    .buttonStyle(.plain)

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                            .foregroundStyle(DS.inkFaded)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
    }
}

// MARK: - Whisper row (embossed, breathing)

private struct StationWhisperRow: View {
    let suggestion: GhostSuggestion
    let accent: Color
    let onAccept: () -> Void
    let onDismiss: () -> Void
    let onSourceTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isHovered)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            // 0.08 Hz breathing, ±0.08 around 0.5 opacity
            let breath = 0.5 + 0.08 * sin(2 * .pi * 0.08 * t)
            content(opacity: isHovered ? 0.9 : breath)
        }
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
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
                    .lineLimit(nil)
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
#Preview("Station — Filled") {
    StationPreviewHarness(type: .goal)
        .padding(40)
        .background(DS.vellum.opacity(0.6))
}

#Preview("Station — Empty") {
    StationPreviewHarness(type: .problems, empty: true)
        .padding(40)
        .background(DS.vellum.opacity(0.6))
}

private struct StationPreviewHarness: View {
    let type: ConnectionSectionType
    var empty: Bool = false
    @State private var section: ConnectionSection

    init(type: ConnectionSectionType, empty: Bool = false) {
        self.type = type
        self.empty = empty
        let items: [ConnectionItem] = empty ? [] : [
            ConnectionItem(content: "Identity-shift precedes behavior change."),
            ConnectionItem(
                content: "People change when they adopt a new story about themselves.",
                sourceAtomUUID: "source-uuid"
            )
        ]
        let ghosts: [GhostSuggestion] = empty ? [] : [
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
            onDismissGhost: { _ in }
        )
    }
}
#endif
