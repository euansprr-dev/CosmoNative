// CosmoOS/UI/FocusMode/Connection/ConnectionOutlineView.swift
// June 2026 — Connection workspace revamp.
// View mode 2: the whole connection as one flattened, editable column —
// section headers with their items inline, quick-add per section. Fastest
// way to read and edit the full concept top to bottom.

import SwiftUI

struct ConnectionOutlineView: View {
    var viewModel: ConnectionFocusModeViewModel
    var workspace: ConnectionWorkspaceModel
    let actions: ConnectionWorkspaceActions
    var pendingInsertsBySection: [ConnectionSectionType: [ConnectionPendingInsert]] = [:]

    private var visibleSections: [ConnectionSection] {
        workspace.matchingSections(in: viewModel.state.sections)
            .sorted { $0.type.sortOrder < $1.type.sortOrder }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space24) {
                    ForEach(visibleSections) { section in
                        outlineSection(section)
                            .id(section.type.rawValue)
                    }
                }
                .padding(.horizontal, DS.space24)
                .padding(.vertical, DS.space20)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .onChange(of: workspace.scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(ProMotionSprings.gentle) {
                    proxy.scrollTo(target.rawValue, anchor: .top)
                }
                workspace.scrollTarget = nil
            }
        }
    }

    private func outlineSection(_ section: ConnectionSection) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            sectionHeader(section)
            if section.items.isEmpty && pendingInserts(for: section).isEmpty {
                Text(section.type.promptQuestion)
                    .font(DS.callout)
                    .italic()
                    .foregroundStyle(DS.textMuted)
                    .padding(.leading, DS.space24)
            } else if !section.items.isEmpty {
                itemRows(section)
            }
            if !pendingInserts(for: section).isEmpty {
                pendingRows(section)
            }
            ConnectionQuickAddField(
                accent: section.type.accentColor,
                sectionName: section.type.displayName,
                onSubmit: { document, text in
                    viewModel.addItem(document: document, plainText: text, toSection: section.type)
                }
            )
            .padding(.leading, DS.space24)
        }
    }

    private func sectionHeader(_ section: ConnectionSection) -> some View {
        Button(action: { workspace.openSection(section.type) }) {
            HStack(spacing: DS.space8) {
                Image(systemName: section.type.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(section.type.accentColor)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(section.type.displayName)
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                if section.itemCount > 0 {
                    Text("\(section.itemCount)")
                        .font(DS.caption)
                        .foregroundStyle(DS.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(section.type.displayName)")
    }

    private func pendingInserts(for section: ConnectionSection) -> [ConnectionPendingInsert] {
        pendingInsertsBySection[section.type] ?? []
    }

    private func pendingRows(_ section: ConnectionSection) -> some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            ForEach(pendingInserts(for: section)) { insert in
                ConnectionPendingInsertRow(
                    insert: insert,
                    accent: section.type.accentColor,
                    onAccept: actions.onAcceptInsert,
                    onReject: actions.onRejectInsert
                )
            }
        }
        .padding(.leading, DS.space16)
    }

    private func itemRows(_ section: ConnectionSection) -> some View {
        VStack(alignment: .leading, spacing: DS.space2) {
            ForEach(workspace.matchingItems(in: section)) { item in
                ConnectionItemEditRow(
                    item: item,
                    accent: section.type.accentColor,
                    sectionType: section.type,
                    isSelected: workspace.selection == .item(section.type, item.id),
                    onSelect: { workspace.selection = .item(section.type, item.id) },
                    onEdit: { updated in viewModel.editItem(updated, inSection: section.type) },
                    onDelete: { viewModel.deleteItem(item.id, fromSection: section.type) },
                    onSourceTap: actions.onSourceTap
                )
            }
        }
        .padding(.leading, DS.space16)
    }
}
