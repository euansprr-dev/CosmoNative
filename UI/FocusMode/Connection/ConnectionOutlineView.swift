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

    /// The objection whose handling composer is open, if any.
    @State private var handlingComposerItemID: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space24) {
                    ForEach(visibleSections) { section in
                        outlineSection(section)
                            .opacity(
                                workspace.focusedSection.map { $0 != section.type } ?? false
                                    ? 0.3 : 1
                            )
                            .id(section.type.rawValue)
                    }
                }
                .animation(ProMotionSprings.gentle, value: workspace.focusedSection)
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
            if !anchoredMedia(for: section).isEmpty {
                mediaRows(section)
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

    private func anchoredMedia(for section: ConnectionSection) -> [ConnectionMediaItem] {
        viewModel.state.media(anchoredTo: section.type)
    }

    /// Compact media rows under their anchored section: thumbnail, title,
    /// platform + moment line. Click opens the Stage lightbox.
    private func mediaRows(_ section: ConnectionSection) -> some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            ForEach(anchoredMedia(for: section)) { item in
                outlineMediaRow(item)
            }
        }
        .padding(.leading, DS.space16)
    }

    private func outlineMediaRow(_ item: ConnectionMediaItem) -> some View {
        let atom = item.atomUUID.flatMap { viewModel.mediaAtoms[$0] }
        return Button {
            actions.onOpenMedia(item.id)
        } label: {
            HStack(spacing: DS.space8) {
                ConceptMediaTile(
                    item: item,
                    atom: atom,
                    actions: actions,
                    tileAspect: 1.4
                )
                .frame(width: 64)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.caption ?? atom?.title ?? item.assetTitle ?? "Media")
                        .font(DS.callout)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                    HStack(spacing: DS.space4) {
                        Text(item.kind.rawValue.capitalized)
                        if let moment = item.timestampSeconds, moment > 0 {
                            Text("·")
                            Text(ConceptMediaLightbox.timestampLabel(moment))
                                .monospacedDigit()
                        }
                    }
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open in the Stage")
        .accessibilityLabel("Open media \(item.caption ?? atom?.title ?? "media")")
    }

    private func itemRows(_ section: ConnectionSection) -> some View {
        VStack(alignment: .leading, spacing: DS.space2) {
            ForEach(workspace.matchingItems(in: section)) { item in
                VStack(alignment: .leading, spacing: DS.space4) {
                    ConnectionItemEditRow(
                        item: item,
                        accent: section.type.accentColor,
                        sectionType: section.type,
                        isSelected: workspace.selection == .item(section.type, item.id),
                        onSelect: { workspace.selection = .item(section.type, item.id) },
                        onEdit: { updated in viewModel.editItem(updated, inSection: section.type) },
                        onDelete: { viewModel.deleteItem(item.id, fromSection: section.type) },
                        onSourceTap: actions.onSourceTap,
                        onHandleObjection: section.type == .beliefsObjections
                            ? { withAnimation(ProMotionSprings.gentle) { handlingComposerItemID = item.id } }
                            : nil
                    )
                    objectionThread(for: item, in: section.type)
                }
            }
        }
        .padding(.leading, DS.space16)
        .animation(ProMotionSprings.gentle, value: handlingComposerItemID)
    }

    /// The handling thread / composer beneath an objection row (shared
    /// grammar with the section detail).
    @ViewBuilder
    private func objectionThread(for item: ConnectionItem, in type: ConnectionSectionType) -> some View {
        if type == .beliefsObjections {
            if let staged = workspace.stagedObjectionHandlings.first(where: { $0.objectionItemID == item.id }),
               handlingComposerItemID != item.id {
                StagedObjectionHandlingRow(
                    staged: staged,
                    resolveRef: { viewModel.resolveBoardRef($0) },
                    onAccept: { actions.onAcceptStagedHandling(staged.id) },
                    onReject: { actions.onRejectStagedHandling(staged.id) }
                )
            } else if handlingComposerItemID == item.id {
                ObjectionHandlingComposer(
                    sections: viewModel.state.sections,
                    objectionItemID: item.id,
                    initial: item.handling,
                    onSave: { text, refs in
                        viewModel.setObjectionHandling(itemID: item.id, inSection: type, text: text, linkedRefs: refs)
                        handlingComposerItemID = nil
                    },
                    onCancel: { handlingComposerItemID = nil }
                )
            } else if item.isHandled, let handling = item.handling {
                ObjectionHandlingThread(
                    handling: handling,
                    resolveRef: { viewModel.resolveBoardRef($0) },
                    onJump: { ref in
                        guard let section = ref.section else { return }
                        workspace.selection = .item(section, ref.itemID)
                        workspace.jump(to: section)
                    },
                    onEdit: {
                        withAnimation(ProMotionSprings.gentle) { handlingComposerItemID = item.id }
                    },
                    onReopen: {
                        withAnimation(ProMotionSprings.gentle) {
                            viewModel.clearObjectionHandling(itemID: item.id, inSection: type)
                        }
                    }
                )
            }
        }
    }
}
