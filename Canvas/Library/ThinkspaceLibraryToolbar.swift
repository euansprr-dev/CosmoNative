// CosmoOS/Canvas/Library/ThinkspaceLibraryToolbar.swift
// Materials display, sorting, and search form one subordinate toolbar.
// Keeping them inside Materials leaves the space's primary tabs stationary.
// Search focus is mirrored into the hoisted chrome model for keyboard routing.

import SwiftUI
import AppKit

// MARK: - Sort + search island (trailing)

struct ThinkspaceLibraryToolsIsland: View {
    let chrome: ThinkspaceLibraryChromeModel
    var compact = false

    @FocusState private var searchFocused: Bool
    @State private var showingSearch = false

    var body: some View {
        CosmoChromeIsland {
            Menu {
                Picker("Display", selection: Binding(get: { chrome.prefs.viewMode }, set: { chrome.setViewMode($0) })) {
                    Text("Grid").tag(ThinkspaceLibraryViewMode.icons)
                    Text("List").tag(ThinkspaceLibraryViewMode.list)
                }
            } label: { Image(systemName: chrome.prefs.viewMode.icon).frame(width: 36, height: 44) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .help("Display materials as a grid or list").accessibilityLabel("Display materials")
            LibrarySortMenu(
                sortField: chrome.prefs.sortField,
                sortAscending: chrome.prefs.sortAscending,
                grouping: chrome.prefs.grouping,
                iconScale: chrome.prefs.iconScale,
                showsIconScale: chrome.prefs.viewMode == .icons,
                onSelectSort: { chrome.selectSort($0) },
                onSelectGrouping: { chrome.setGrouping($0) },
                onSelectIconScale: { chrome.setIconScale($0) },
                showsTitle: !compact
            )
            if compact {
                Button { showingSearch = true } label: {
                    Image(systemName: "magnifyingglass").frame(width: 30, height: 30)
                }
                .buttonStyle(.plain).help("Search materials (⌘F)").accessibilityLabel("Search materials")
                .popover(isPresented: $showingSearch) {
                    searchField.padding(DS.space16).frame(width: 280)
                        .onAppear { searchFocused = true }
                }
            } else { searchField }
        }
        .onChange(of: searchFocused) { _, focused in
            if chrome.isSearchFocused != focused { chrome.isSearchFocused = focused }
        }
        .onChange(of: chrome.isSearchFocused) { _, focused in
            if !focused && searchFocused { searchFocused = false; showingSearch = false }
        }
        .onChange(of: chrome.searchFocusRequest) { _, _ in
            if compact { showingSearch = true } else { searchFocused = true }
        }
    }

    private var searchField: some View {
        LibrarySearchField(
                searchText: Binding(get: { chrome.searchText }, set: { chrome.searchText = $0 }),
                focused: $searchFocused
            )
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

struct LibrarySortMenu: View {
    let sortField: ThinkspaceLibrarySortField
    let sortAscending: Bool
    let grouping: ThinkspaceLibraryGrouping
    let iconScale: ThinkspaceLibraryIconScale
    let showsIconScale: Bool
    let onSelectSort: (ThinkspaceLibrarySortField) -> Void
    let onSelectGrouping: (ThinkspaceLibraryGrouping) -> Void
    let onSelectIconScale: (ThinkspaceLibraryIconScale) -> Void
    var showsTitle = true

    @State private var isHovered = false

    var body: some View {
        Menu {
            menuContent
        } label: {
            HStack(spacing: DS.space4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(DS.caption.weight(.semibold))
                    .accessibilityHidden(true)
                if showsTitle {
                    Text(sortField.title)
                        .font(DS.footnote.weight(.medium)).lineLimit(1)
                }
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
            TextField("Find in materials", text: $searchText)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .focused(focused)
                // Elastic, never fixed: compresses under width pressure so
                // the row truncates gracefully instead of clipping.
                .frame(minWidth: 64, idealWidth: 168, maxWidth: 168)
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
        .help("Find in materials (⌘F)")
    }
}
