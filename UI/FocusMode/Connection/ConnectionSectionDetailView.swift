// CosmoOS/UI/FocusMode/Connection/ConnectionSectionDetailView.swift
// June 2026 — Connection workspace revamp.
// Full single-section editor pushed inside the center column (replaces the
// old full-screen Station Mode overlay): every item editable in place, ghost
// suggestions, and a capture field. Esc or the back chevron pops back.

import SwiftUI

struct ConnectionSectionDetailView: View {
    let sectionType: ConnectionSectionType
    var viewModel: ConnectionFocusModeViewModel
    var workspace: ConnectionWorkspaceModel
    let actions: ConnectionWorkspaceActions

    private var section: ConnectionSection? {
        viewModel.state.section(for: sectionType)
    }

    private var accent: Color { sectionType.accentColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(DS.borderSubtle)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space16) {
                    if let section {
                        itemList(section)
                    }
                    ConnectionQuickAddField(
                        accent: accent,
                        sectionName: sectionType.displayName,
                        onSubmit: { document, text in
                            viewModel.addItem(document: document, plainText: text, toSection: sectionType)
                        }
                    )
                }
                .padding(.horizontal, DS.space24)
                .padding(.vertical, DS.space20)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        // Select→mint on the user's own bullets: highlight a phrase in an
        // item and mint or link it (the pill reads selections the rows
        // report via ConnectionLinkedProseView).
        .conceptMintPillHost()
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DS.space10) {
            Button(action: { workspace.popSection() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(DS.surfaceElevated, in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("[", modifiers: .command)
            .help("Back to board (Esc)")
            .accessibilityLabel("Back to board")

            Image(systemName: sectionType.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(sectionType.displayName)
                    .font(DS.title2)
                    .foregroundStyle(DS.text)
                Text(sectionType.promptQuestion)
                    .font(DS.callout)
                    .italic()
                    .foregroundStyle(DS.textMuted)
            }

            Spacer()

            if let count = section?.itemCount, count > 0 {
                Text("\(count) item\(count == 1 ? "" : "s")")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
            }
        }
        .padding(.horizontal, DS.space24)
        .padding(.vertical, DS.space12)
    }

    // MARK: - Items

    private func itemList(_ section: ConnectionSection) -> some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            ForEach(section.items) { item in
                ConnectionItemEditRow(
                    item: item,
                    accent: accent,
                    sectionType: sectionType,
                    isSelected: workspace.selection == .item(sectionType, item.id),
                    onSelect: { workspace.selection = .item(sectionType, item.id) },
                    onEdit: { updated in viewModel.editItem(updated, inSection: sectionType) },
                    onDelete: { viewModel.deleteItem(item.id, fromSection: sectionType) },
                    onSourceTap: actions.onSourceTap
                )
            }
        }
    }

}

// MARK: - Editable item row

struct ConnectionItemEditRow: View {
    let item: ConnectionItem
    let accent: Color
    var sectionType: ConnectionSectionType? = nil
    var isSelected: Bool = false
    var onSelect: () -> Void = {}
    let onEdit: (ConnectionItem) -> Void
    let onDelete: () -> Void
    let onSourceTap: (String) -> Void

    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editDocument: RichDocument = .empty

    var body: some View {
        HStack(alignment: .top, spacing: DS.space10) {
            Circle()
                .fill(accent.opacity(0.9))
                .frame(width: 5, height: 5)
                .padding(.top, 8)
                .accessibilityHidden(true)
            itemContent
            Spacer(minLength: 0)
            trailingControls
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space8)
        .background(rowBackground, in: .rect(cornerRadius: 8))
        .contentShape(.rect(cornerRadius: 8))
        .onTapGesture(count: 2) { beginEditing() }
        .simultaneousGesture(TapGesture().onEnded { onSelect() })
        .contextMenu {
            Button(isEditing ? "Done Editing" : "Edit") { toggleEditing() }
            Button("Delete", role: .destructive, action: onDelete)
        }
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
    }

    private var rowBackground: Color {
        if isEditing { return DS.bg }
        if isSelected { return accent.opacity(0.08) }
        if isHovered { return DS.border.opacity(0.35) }
        return .clear
    }

    @ViewBuilder
    private var itemContent: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
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
            } else if let linkedUUID = item.linkedConnectionUUID {
                ConnectionLinkPill(title: item.resolvedPlainText) {
                    onSourceTap(linkedUUID)
                }
            } else {
                // NSTextView-backed twin of ConnectionLinkedText: same mention
                // links, plus a readable selection so the mint pill works here.
                ConnectionLinkedProseView(text: item.resolvedPlainText, originSection: sectionType)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let sourceUUID = item.sourceAtomUUID, !item.isConnectionLink {
                Button(action: { onSourceTap(sourceUUID) }) {
                    Label("source", systemImage: "link")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }
                .buttonStyle(.plain)
                .help("Open source")
            }
        }
    }

    @ViewBuilder
    private var trailingControls: some View {
        if isEditing {
            Button("Done") { isEditing = false }
                .buttonStyle(.plain)
                .font(DS.caption)
                .foregroundStyle(accent)
        } else {
            Menu {
                Button("Edit") { toggleEditing() }
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .opacity(isHovered || isSelected ? 1 : 0)
            .accessibilityLabel("Item actions")
        }
    }

    private func beginEditing() {
        guard !isEditing else { return }
        editDocument = item.resolvedDocument
        isEditing = true
    }

    private func toggleEditing() {
        if !isEditing {
            editDocument = item.resolvedDocument
        }
        isEditing.toggle()
    }
}
