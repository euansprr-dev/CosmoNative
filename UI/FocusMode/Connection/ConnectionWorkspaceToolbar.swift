// CosmoOS/UI/FocusMode/Connection/ConnectionWorkspaceToolbar.swift
// June 2026 — Connection workspace revamp.
// Floating glass toolbar at the top of the workspace: view-mode switcher,
// search, navigator/inspector toggles, add source, close. Uses the app's
// native Liquid Glass chrome via cosmoGlassPanel (CosmoGlassPanel.swift).

import SwiftUI

struct ConnectionWorkspaceToolbar: View {
    var workspace: ConnectionWorkspaceModel
    let breakpoint: ConnectionWorkspaceBreakpoint
    let isPaneContext: Bool
    let actions: ConnectionWorkspaceActions

    @Environment(\.atomWindowChromeContext) private var atomChrome
    @Environment(\.paneDeckChrome) private var paneDeckChrome
    @FocusState private var searchFocused: Bool

    var body: some View {
        // Chrome islands, not a full-width bar: navigate | modes | tools,
        // grouped by function on the shared chrome baseline. In pane context
        // the mode switcher flows between the clusters — no ZStack overlap
        // at pane widths.
        CosmoChromeRow(centersAbsolutely: !isPaneContext) {
            if atomChrome == nil, !isPaneContext {
                NavigationTrailIsland()
            }
            if let paneDeckChrome {
                CosmoChromeIsland { PaneDeckTabStrip(context: paneDeckChrome) }
            }
            CosmoChromeIsland { leadingControls }
        } center: {
            CosmoChromeIsland { viewModeSwitcher }
        } trailing: {
            CosmoChromeIsland {
                searchField
                trailingControls
            }
        }
        .onChange(of: workspace.searchFocusTick) {
            searchFocused = true
        }
    }

    // MARK: - Leading

    @ViewBuilder
    private var leadingControls: some View {
        if let atomChrome {
            AtomWindowChromeLeadingControls(context: atomChrome)
            AtomWindowChromeDivider()
        }
        toolbarButton(
            icon: "sidebar.squares.left",
            help: workspace.isNavigatorShowing ? "Hide navigator (⌘0)" : "Show navigator (⌘0)",
            isActive: workspace.isNavigatorShowing
        ) {
            withAnimation(ProMotionSprings.focusTransition) {
                workspace.toggleNavigator()
            }
        }
        if breakpoint == .narrow {
            sectionJumpMenu
        }
    }

    private var sectionJumpMenu: some View {
        Menu {
            ForEach(ConnectionSectionType.allCases.sorted { $0.sortOrder < $1.sortOrder }, id: \.self) { type in
                Button {
                    workspace.openSection(type)
                } label: {
                    Label(type.displayName, systemImage: type.icon)
                }
            }
        } label: {
            Image(systemName: "list.triangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Jump to section")
        .accessibilityLabel("Jump to section")
    }

    // MARK: - View mode

    private var viewModeSwitcher: some View {
        HStack(spacing: DS.space2) {
            ForEach(Array(ConnectionViewMode.allCases.enumerated()), id: \.element) { index, mode in
                Button {
                    withAnimation(ProMotionSprings.focusTransition) {
                        workspace.viewMode = mode
                        workspace.pushedSection = nil
                    }
                } label: {
                    HStack(spacing: DS.space4) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 11, weight: .medium))
                        if breakpoint == .regular {
                            Text(mode.displayName)
                                .font(DS.buttonText)
                        }
                    }
                    .foregroundStyle(workspace.viewMode == mode ? DS.text : DS.textMuted)
                    .padding(.horizontal, DS.space10)
                    .padding(.vertical, DS.space6)
                    .background(
                        workspace.viewMode == mode ? AnyShapeStyle(DS.surfaceElevated) : AnyShapeStyle(.clear),
                        in: Capsule()
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("\(mode.displayName) (⌘\(index + 1))")
                .accessibilityLabel("\(mode.displayName) view")
                .accessibilityAddTraits(workspace.viewMode == mode ? .isSelected : [])
            }
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(searchFocused ? DS.accent : DS.textMuted)
                .accessibilityHidden(true)
            TextField("Find in concept", text: searchBinding)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .focused($searchFocused)
                .frame(width: breakpoint == .regular ? 150 : 110)
                .onKeyPress(.escape) {
                    guard searchFocused else { return .ignored }
                    workspace.searchQuery = ""
                    searchFocused = false
                    return .handled
                }
            if workspace.isSearching {
                Button {
                    workspace.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space6)
        .background(DS.surfaceElevated.opacity(searchFocused ? 1 : 0.6), in: Capsule())
        .overlay(
            Capsule().stroke(searchFocused ? DS.accent.opacity(0.4) : DS.borderSubtle, lineWidth: 1)
        )
        .animation(ProMotionSprings.hover, value: searchFocused)
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { workspace.searchQuery },
            set: { workspace.searchQuery = $0 }
        )
    }

    // MARK: - Trailing

    @ViewBuilder
    private var trailingControls: some View {
        toolbarButton(
            icon: "plus",
            help: "Link a source (⌘K)",
            action: actions.onAddSource
        )
        toolbarButton(
            icon: "sidebar.right",
            help: workspace.isInspectorShowing ? "Hide inspector (⌘⌥I)" : "Show inspector (⌘⌥I)",
            isActive: workspace.isInspectorShowing
        ) {
            withAnimation(ProMotionSprings.focusTransition) {
                workspace.toggleInspector()
            }
        }
        if let atomChrome {
            AtomWindowChromeDivider()
            AtomWindowChromeTrailingControls(context: atomChrome)
        }
    }

    // MARK: - Button factory

    private func toolbarButton(
        icon: String,
        help: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive ? DS.text : DS.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
