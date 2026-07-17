// CosmoOS/Canvas/Library/ThinkspaceLibraryListView.swift
// The List lens: the in-depth ledger. One grouped container (the Files
// grammar), hairline separators inset to the text column, sortable column
// headers, honest provenance. Lists are icon territory — kind glyphs and
// thumbnails, never micro-pages.

import SwiftUI
import AppKit

struct ThinkspaceLibraryListView: View {
    let folders: [ThinkspaceLibraryFolder]
    let sections: [(title: String, items: [ThinkspaceLibraryItem])]
    let sortField: ThinkspaceLibrarySortField
    let sortAscending: Bool
    /// "Posted" for foldered search results, "On canvas" / "Stored" otherwise.
    let provenance: (ThinkspaceLibraryItem) -> String
    let dateLabel: (ThinkspaceLibraryItem) -> String
    let onSelectSortColumn: (ThinkspaceLibrarySortField) -> Void
    let context: ThinkspaceLibraryLensContext

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            LibraryListHeaderRow(
                sortField: sortField,
                sortAscending: sortAscending,
                onSelect: onSelectSortColumn
            )
            if !folders.isEmpty {
                folderBlock
            }
            ForEach(sections, id: \.title) { section in
                sectionView(section)
            }
        }
    }

    /// Folders live in their own container so grouped/kind sections never
    /// swallow them under a kind header.
    private var folderBlock: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            CosmoSectionHeader(label: "Folders", detail: "\(folders.count)")
            LibraryListContainer {
                ForEach(folders) { folder in
                    LibraryListFolderRow(folder: folder, dateLabel: folderDate(folder), context: context)
                        .id(folder.id.uuidString)
                    if folder.id != folders.last?.id {
                        LibraryListSeparator()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: (title: String, items: [ThinkspaceLibraryItem])) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            if sections.count > 1 || !folders.isEmpty {
                CosmoSectionHeader(label: section.title, detail: "\(section.items.count)")
            }
            LibraryListContainer {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    LibraryListItemRow(
                        model: context.cardModel(item),
                        provenance: provenance(item),
                        dateLabel: dateLabel(item),
                        context: context
                    )
                    .id(item.id)
                    if index < section.items.count - 1 {
                        LibraryListSeparator()
                    }
                }
            }
        }
    }

    private func folderDate(_ folder: ThinkspaceLibraryFolder) -> String {
        // A folder's date is its newest content — the honest ledger answer.
        let newest = folder.items.compactMap { context.cardModel($0).updatedAt }.max()
        return newest.map(ThinkspaceLibraryDateLabel.label(for:)) ?? "—"
    }
}

// MARK: - Column metrics (one source of truth for header + rows)

enum LibraryListColumns {
    static let kind: CGFloat = 104
    static let date: CGFloat = 136
    static let provenance: CGFloat = 124
    static let markSize: CGFloat = 26
    static let rowHeight: CGFloat = 40
    /// Separators inset to the text column (mark + gaps).
    static let separatorInset: CGFloat = DS.space16 + markSize + DS.space12
}

/// Human date labels for the ledger: named days stay close ("Today, 14:02"),
/// older dates go compact ("Jul 3, 2026").
enum ThinkspaceLibraryDateLabel {
    static func label(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today, \(date.formatted(.dateTime.hour().minute()))"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday, \(date.formatted(.dateTime.hour().minute()))"
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

// MARK: - Container & separator

private struct LibraryListContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(DS.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                    .strokeBorder(DS.glassBorder, lineWidth: 0.5)
            )
    }
}

private struct LibraryListSeparator: View {
    var body: some View {
        Rectangle()
            .fill(DS.glassBorder.opacity(0.6))
            .frame(height: 0.5)
            .padding(.leading, LibraryListColumns.separatorInset)
    }
}

// MARK: - Header row (sortable)

private struct LibraryListHeaderRow: View {
    let sortField: ThinkspaceLibrarySortField
    let sortAscending: Bool
    let onSelect: (ThinkspaceLibrarySortField) -> Void

    var body: some View {
        HStack(spacing: DS.space12) {
            headerButton("Name", field: .name)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, LibraryListColumns.separatorInset)
            headerButton("Kind", field: .kind)
                .frame(width: LibraryListColumns.kind, alignment: .leading)
            headerButton("Date Modified", field: .dateModified)
                .frame(width: LibraryListColumns.date, alignment: .leading)
            Text("Where")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textMuted)
                .frame(width: LibraryListColumns.provenance, alignment: .leading)
        }
        .padding(.horizontal, DS.space16)
        .accessibilityElement(children: .contain)
    }

    private func headerButton(_ title: String, field: ThinkspaceLibrarySortField) -> some View {
        LibraryListHeaderButton(
            title: title,
            isActive: sortField == field,
            ascending: sortAscending,
            action: { onSelect(field) }
        )
    }
}

private struct LibraryListHeaderButton: View {
    let title: String
    let isActive: Bool
    let ascending: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space4) {
                Text(title)
                    .font(DS.caption.weight(.semibold))
                if isActive {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(DS.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(isActive ? DS.text : (isHovered ? DS.textSecondary : DS.textMuted))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help("Sort by \(title)\(isActive ? (ascending ? " (ascending)" : " (descending)") : "")")
        .accessibilityLabel("Sort by \(title)")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Folder row

private struct LibraryListFolderRow: View {
    let folder: ThinkspaceLibraryFolder
    let dateLabel: String
    let context: ThinkspaceLibraryLensContext

    @State private var isHovered = false
    @State private var isDropTarget = false

    private var isSelected: Bool { context.selection.isSelected(folder.id.uuidString) }

    var body: some View {
        HStack(spacing: DS.space12) {
            LibraryFolderIconV2(folder: folder, showsBadge: false)
                .frame(width: LibraryListColumns.markSize, height: LibraryListColumns.markSize * 0.72)
            Text(folder.title)
                .font(DS.callout.weight(.medium))
                .foregroundStyle(DS.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Folder · \(folder.items.count)")
                .font(DS.footnote)
                .foregroundStyle(DS.textMuted)
                .monospacedDigit()
                .frame(width: LibraryListColumns.kind, alignment: .leading)
            Text(dateLabel)
                .font(DS.footnote)
                .foregroundStyle(DS.textMuted)
                .monospacedDigit()
                .frame(width: LibraryListColumns.date, alignment: .leading)
            Text("—")
                .font(DS.footnote)
                .foregroundStyle(DS.textMuted)
                .frame(width: LibraryListColumns.provenance, alignment: .leading)
        }
        .padding(.horizontal, DS.space16)
        .frame(height: LibraryListColumns.rowHeight)
        .background(rowFill)
        .contentShape(Rectangle())
        .gesture(LibraryClickGestures.selectAndOpen(
            id: folder.id.uuidString,
            selection: context.selection,
            onOpen: { context.openFolder(folder) }
        ))
        .dropDestination(for: String.self) { items, _ in
            var moved = false
            for uuid in items where !folder.items.contains(where: { $0.entityUuid == uuid }) {
                context.actions.fileIntoFolder(uuid, folder.id)
                moved = true
            }
            return moved
        } isTargeted: { targeting in
            withAnimation(ProMotionSprings.snappy) { isDropTarget = targeting }
        }
        .contextMenu {
            Button("Open", systemImage: "folder") { context.openFolder(folder) }
            LibraryFolderColorMenu(folder: folder, onRecolor: { context.actions.recolorFolder(folder.id, $0) })
            Divider()
            Button("Delete Folder", systemImage: "trash", role: .destructive) { context.deleteFolder(folder) }
        }
        .onHover { isHovered = $0 }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(ThinkspaceLibrarySpace.name))
        } action: { frame in
            context.selection.register(id: folder.id.uuidString, frame: frame)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(folder.title) folder, \(folder.items.count) items")
    }

    private var rowFill: Color {
        if isDropTarget { return folder.color.opacity(0.10) }
        if isSelected { return DS.accentSoft }
        if isHovered { return DS.text.opacity(0.035) }
        return .clear
    }
}

// MARK: - Item row

private struct LibraryListItemRow: View {
    let model: ThinkspaceLibraryCardModel
    let provenance: String
    let dateLabel: String
    let context: ThinkspaceLibraryLensContext

    @State private var isHovered = false
    @FocusState private var renameFocused: Bool
    @State private var draftName = ""

    private var item: ThinkspaceLibraryItem { model.item }
    private var isSelected: Bool { context.selection.isSelected(item.id) }
    private var isRenaming: Bool { context.selection.renamingID == item.id }

    var body: some View {
        draggableRow
            .onHover { isHovered = $0 }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(ThinkspaceLibrarySpace.name))
            } action: { frame in
                context.selection.register(id: item.id, frame: frame)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel("\(item.title), \(model.kindLabel), modified \(dateLabel)")
    }

    @ViewBuilder
    private var draggableRow: some View {
        if item.block != nil {
            row.draggable(item.entityUuid) {
                if isSelected && context.selection.count > 1 {
                    ThinkspaceLibraryFlockDragPreview(lead: model, count: context.selection.count)
                } else {
                    ThinkspaceLibraryDragPreview(model: model)
                }
            }
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: DS.space12) {
            LibraryListObjectMark(model: model, size: LibraryListColumns.markSize)
            nameCell
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(model.kindLabel)
                .font(DS.footnote)
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)
                .frame(width: LibraryListColumns.kind, alignment: .leading)
            Text(dateLabel)
                .font(DS.footnote)
                .foregroundStyle(DS.textMuted)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: LibraryListColumns.date, alignment: .leading)
            Text(provenance)
                .font(DS.footnote)
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)
                .frame(width: LibraryListColumns.provenance, alignment: .leading)
        }
        .padding(.horizontal, DS.space16)
        .frame(height: LibraryListColumns.rowHeight)
        .background(rowFill)
        .contentShape(Rectangle())
        .gesture(LibraryClickGestures.selectAndOpen(
            id: item.id,
            selection: context.selection,
            onOpen: { context.actions.openItem(item) }
        ))
        .contextMenu { LibraryItemMenuItems(model: model, context: context) }
    }

    @ViewBuilder
    private var nameCell: some View {
        if isRenaming {
            LibraryInlineRenameField(
                draft: $draftName,
                focused: $renameFocused,
                font: DS.callout.weight(.medium),
                onCommit: commitRename,
                onCancel: { context.selection.renamingID = nil }
            )
            .onAppear {
                draftName = item.title
                DispatchQueue.main.async { renameFocused = true }
            }
        } else {
            Text(item.title)
                .font(DS.callout.weight(.medium))
                .foregroundStyle(DS.text)
                .lineLimit(1)
        }
    }

    private var rowFill: Color {
        if isSelected { return DS.accentSoft }
        if isHovered { return DS.text.opacity(0.035) }
        return .clear
    }

    private func commitRename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != item.title {
            context.actions.renameItem(item, trimmed)
        }
        context.selection.renamingID = nil
    }
}
