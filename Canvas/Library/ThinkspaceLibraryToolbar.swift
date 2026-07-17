// CosmoOS/Canvas/Library/ThinkspaceLibraryToolbar.swift
// The library's one chrome row, on the app's shared island baseline
// (CosmoChromeRow): trail island + breadcrumb leading, the view-mode
// switcher dead center, sort and search trailing. The breadcrumb IS the
// page title (the pane-spine law) — no second title below to collide with.

import SwiftUI
import AppKit

struct ThinkspaceLibraryToolbar: View {
    let thinkspaceName: String
    let folder: ThinkspaceLibraryFolder?
    @Binding var viewMode: ThinkspaceLibraryViewMode
    @Binding var searchText: String
    var searchFocused: FocusState<Bool>.Binding
    let sortField: ThinkspaceLibrarySortField
    let sortAscending: Bool
    let grouping: ThinkspaceLibraryGrouping
    let iconScale: ThinkspaceLibraryIconScale
    let onSelectSort: (ThinkspaceLibrarySortField) -> Void
    let onSelectGrouping: (ThinkspaceLibraryGrouping) -> Void
    let onSelectIconScale: (ThinkspaceLibraryIconScale) -> Void
    let onExitFolder: () -> Void
    let onRenameFolder: (UUID, String) -> Void
    /// A document dropped on the root breadcrumb segment un-files it.
    let onDropToRoot: (String) -> Bool

    var body: some View {
        CosmoChromeRow(insetsEnabled: true, centersAbsolutely: true) {
            // The app shell's floating sidebar toggle already serves library
            // mode, so the island variant stands down here.
            NavigationTrailIsland(showsSidebarToggle: false)
            LibraryBreadcrumbIsland(
                thinkspaceName: thinkspaceName,
                folder: folder,
                onExitFolder: onExitFolder,
                onRenameFolder: onRenameFolder,
                onDropToRoot: onDropToRoot
            )
        } center: {
            CosmoChromeIsland {
                CosmoSegmentedSwitcher(
                    options: ThinkspaceLibraryViewMode.allCases,
                    label: { $0.title },
                    icon: { $0.icon },
                    help: { mode in
                        "\(mode.title) view (⌘\((ThinkspaceLibraryViewMode.allCases.firstIndex(of: mode) ?? 0) + 1))"
                    },
                    chrome: .bare,
                    selection: $viewMode
                )
            }
        } trailing: {
            CosmoChromeIsland {
                LibrarySortMenu(
                    sortField: sortField,
                    sortAscending: sortAscending,
                    grouping: grouping,
                    iconScale: iconScale,
                    showsIconScale: viewMode == .icons,
                    onSelectSort: onSelectSort,
                    onSelectGrouping: onSelectGrouping,
                    onSelectIconScale: onSelectIconScale
                )
                LibrarySearchField(searchText: $searchText, focused: searchFocused)
            }
        }
    }
}

// MARK: - Breadcrumb (the title that navigates)

private struct LibraryBreadcrumbIsland: View {
    let thinkspaceName: String
    let folder: ThinkspaceLibraryFolder?
    let onExitFolder: () -> Void
    let onRenameFolder: (UUID, String) -> Void
    let onDropToRoot: (String) -> Bool

    @State private var isRootDropTarget = false

    var body: some View {
        CosmoChromeIsland {
            HStack(spacing: DS.space6) {
                rootSegment
                if let folder {
                    Image(systemName: "chevron.right")
                        .font(DS.caption.weight(.semibold))
                        .foregroundStyle(DS.textMuted)
                        .accessibilityHidden(true)
                    LibraryRenamableTitle(
                        title: folder.title,
                        prominent: true,
                        help: "Rename folder"
                    ) { newName in
                        onRenameFolder(folder.id, newName)
                    }
                }
            }
            .padding(.horizontal, DS.space4)
        }
    }

    /// At root the thinkspace name is the page title; inside a folder it
    /// demotes to a clickable waypoint and accepts drops that un-file items.
    @ViewBuilder
    private var rootSegment: some View {
        if folder == nil {
            Text(thinkspaceName)
                .font(DS.headline.weight(.semibold))
                .foregroundStyle(DS.text)
                .lineLimit(1)
        } else {
            Button(action: onExitFolder) {
                Text(thinkspaceName)
                    .font(DS.headline.weight(.medium))
                    .foregroundStyle(isRootDropTarget ? DS.accent : DS.textMuted)
                    .lineLimit(1)
                    .padding(.horizontal, DS.space4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isRootDropTarget ? DS.accentSoft : .clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dropDestination(for: String.self) { items, _ in
                var handled = false
                for uuid in items where onDropToRoot(uuid) { handled = true }
                return handled
            } isTargeted: { targeting in
                withAnimation(ProMotionSprings.snappy) { isRootDropTarget = targeting }
            }
            .help("Back to \(thinkspaceName) — drop a document here to take it out of the folder")
            .accessibilityLabel("Back to \(thinkspaceName)")
        }
    }
}

/// Click-to-rename title — the same rename dialect as the folder tiles and
/// the canvas cluster label, sized for the chrome island.
struct LibraryRenamableTitle: View {
    let title: String
    var prominent = false
    var help = "Rename"
    let onRename: (String) -> Void

    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var isHovered = false
    @FocusState private var renameFocused: Bool

    var body: some View {
        if isRenaming {
            renameField
        } else {
            Text(title)
                .font(DS.headline.weight(prominent ? .semibold : .medium))
                .foregroundStyle(DS.text)
                .lineLimit(1)
                .padding(.horizontal, DS.space4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered ? DS.text.opacity(0.055) : .clear)
                )
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(ProMotionSprings.hover) { isHovered = hovering }
                }
                .onTapGesture {
                    draftName = title
                    isRenaming = true
                    DispatchQueue.main.async { renameFocused = true }
                }
                .help(help)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(help)
        }
    }

    private var renameField: some View {
        TextField("Name", text: $draftName)
            .textFieldStyle(.plain)
            .font(DS.headline.weight(.medium))
            .foregroundStyle(DS.text)
            .focused($renameFocused)
            .onSubmit(commit)
            .onExitCommand { isRenaming = false }
            .onChange(of: renameFocused) { _, focused in
                if !focused && isRenaming { commit() }
            }
            .padding(.horizontal, DS.space6)
            .padding(.vertical, 2)
            .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(DS.focusRing, lineWidth: 1)
            )
            .frame(width: 200)
    }

    private func commit() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != title {
            onRename(trimmed)
        }
        isRenaming = false
    }
}

// MARK: - Sort / Group / Scale menu

private struct LibrarySortMenu: View {
    let sortField: ThinkspaceLibrarySortField
    let sortAscending: Bool
    let grouping: ThinkspaceLibraryGrouping
    let iconScale: ThinkspaceLibraryIconScale
    let showsIconScale: Bool
    let onSelectSort: (ThinkspaceLibrarySortField) -> Void
    let onSelectGrouping: (ThinkspaceLibraryGrouping) -> Void
    let onSelectIconScale: (ThinkspaceLibraryIconScale) -> Void

    @State private var isHovered = false

    var body: some View {
        Menu {
            menuContent
        } label: {
            HStack(spacing: DS.space4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(DS.caption.weight(.semibold))
                    .accessibilityHidden(true)
                Text(sortField.title)
                    .font(DS.footnote.weight(.medium))
            }
            .foregroundStyle(isHovered ? DS.text : DS.textSecondary)
            .padding(.horizontal, DS.space10)
            .frame(height: 30)
            .background(isHovered ? AnyShapeStyle(DS.glassCardFill) : AnyShapeStyle(.clear), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help("Sort, group, and icon size")
        .accessibilityLabel("Sort by \(sortField.title), \(sortAscending ? "ascending" : "descending")")
    }

    @ViewBuilder
    private var menuContent: some View {
        Picker("Sort By", selection: Binding(get: { sortField }, set: onSelectSort)) {
            ForEach(ThinkspaceLibrarySortField.allCases) { field in
                // Re-picking the active field flips direction (Finder's move) —
                // the checkmark row doubles as the direction toggle.
                Text(field == sortField ? "\(field.title)  \(sortAscending ? "↑" : "↓")" : field.title)
                    .tag(field)
            }
        }
        .pickerStyle(.inline)
        Divider()
        Picker("Group By", selection: Binding(get: { grouping }, set: onSelectGrouping)) {
            ForEach(ThinkspaceLibraryGrouping.allCases) { grouping in
                Text(grouping == .none ? "No Grouping" : "Group by \(grouping.title)").tag(grouping)
            }
        }
        .pickerStyle(.inline)
        if showsIconScale {
            Divider()
            Picker("Icon Size", selection: Binding(get: { iconScale }, set: onSelectIconScale)) {
                ForEach(ThinkspaceLibraryIconScale.allCases) { scale in
                    Text(scale.title).tag(scale)
                }
            }
            .pickerStyle(.inline)
        }
    }
}

// MARK: - Search field

struct LibrarySearchField: View {
    @Binding var searchText: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: "magnifyingglass")
                .font(DS.caption.weight(.medium))
                .foregroundStyle(focused.wrappedValue ? DS.accent : DS.textMuted)
                .accessibilityHidden(true)
            TextField("Find in library", text: $searchText)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .focused(focused)
                .frame(width: 168)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, DS.space10)
        .frame(height: 30)
        .background(
            Capsule().fill(focused.wrappedValue ? DS.glassInputFillFocused : DS.glassInputFill)
        )
        .overlay(
            Capsule().strokeBorder(
                focused.wrappedValue ? DS.focusRing : DS.glassBorder,
                lineWidth: 1
            )
        )
        .animation(ProMotionSprings.hover, value: focused.wrappedValue)
        .help("Find in library (⌘F)")
    }
}
