// CosmoOS/Canvas/Spaces/SpaceChromeRow.swift
// The one chrome row every space wears, on the app's island baseline:
// [sidebar · trail] [identity] … [view switcher (+ the active view's own
// controls)] … [＋] [⋯]. Replaces the hover capsule that used to hide in the
// canvas's bottom-right corner. Islands are real glass; everything inside
// them is bare (glass never samples glass). The row never remounts across
// view switches — only the view-specific islands fade in and out.

import SwiftUI

struct SpaceChromeActions {
    var rename: (String) -> Void = { _ in }
    var openSettings: () -> Void = {}
    var openAsPane: () -> Void = {}
    var pickEmoji: () -> Void = {}
    var recolor: (String) -> Void = { _ in }
    var delete: () -> Void = {}
    var addAtCamera: (SpaceAddKind) -> Void = { _ in }
    var organizeWorkspace: () -> Void = {}
    var savePlace: () -> Void = {}
    var showPlaces: () -> Void = {}
    var exitFolder: () -> Void = {}
    var renameFolder: (UUID, String) -> Void = { _, _ in }
    var dropToRoot: (String) -> Bool = { _ in false }
}

/// What ＋ can make — the menu adapts to the active view.
enum SpaceAddKind: String, CaseIterable, Identifiable {
    case note, idea, task, content, stickyNote, deepDive, file, question, group, existing
    var id: String { rawValue }

    var title: String {
        switch self {
        case .group: return "New material group"
        case .existing: return "Add existing material…"
        case .note: return "Note"
        case .idea: return "Idea"
        case .task: return "Task"
        case .content: return "Content piece"
        case .stickyNote: return "Sticky note"
        case .deepDive: return "Deep dive"
        case .file: return "Import file…"
        case .question: return "Question"
        }
    }

    var icon: String {
        switch self {
        case .group: return "folder.badge.plus"
        case .existing: return "plus.rectangle.on.folder"
        case .note: return "doc.text"
        case .idea: return "lightbulb"
        case .task: return "checkmark.circle"
        case .content: return "doc.richtext"
        case .stickyNote: return "note.text"
        case .deepDive: return "circle.hexagongrid.circle"
        case .file: return "arrow.down.doc"
        case .question: return "questionmark.circle"
        }
    }

    static func kinds(for view: SpaceView) -> [SpaceAddKind] {
        switch view {
        case .home: return [.note, .existing, .file, .question]
        case .canvas: return [.note, .idea, .task, .content, .stickyNote, .deepDive, .file]
        case .library: return [.existing, .file, .note, .group]
        case .deepDive: return [.question, .note]
        case .board: return [.content, .idea]
        case .calendar, .tasks: return [.task]
        }
    }
}

struct SpaceChromeRow: View {
    let thinkspace: Thinkspace?
    let activeView: SpaceView
    let renderableViews: [SpaceView]
    let libraryFolder: ThinkspaceLibraryFolder?
    let libraryChrome: ThinkspaceLibraryChromeModel
    let deepDiveChrome: DeepDiveStudyChromeModel
    let leadingInset: CGFloat
    let actions: SpaceChromeActions
    let onSelectView: (SpaceView) -> Void
    let availableWidth: CGFloat
    private var compact: Bool { availableWidth - leadingInset < (activeView == .library ? 1400 : 900) }

    var body: some View {
        CosmoChromeRow(insetsEnabled: true, centersAbsolutely: false) {
            NavigationTrailIsland(showsSidebarToggle: leadingInset == 0)
            if availableWidth - leadingInset >= 600 {
            SpaceIdentityIsland(
                thinkspace: thinkspace,
                folder: activeView == .library ? libraryFolder : nil,
                actions: actions
            )
            }
        } center: {
            centerIslands
        } trailing: {
            trailingIslands
        }
        .padding(.leading, leadingInset)
        .animation(ProMotionSprings.gentle, value: leadingInset)
        .animation(ProMotionSprings.focusTransition, value: activeView)
    }

    @ViewBuilder
    private var centerIslands: some View {
        CosmoChromeIsland(recede: recedes) {
            if compact {
                Menu {
                    ForEach([SpaceView.home, .library, .canvas, .deepDive]) { view in
                        Button(view.title, systemImage: view.icon) { onSelectView(view) }
                    }
                    if activeView == .library {
                        Divider()
                        Picker("Display", selection: Binding(get: { libraryChrome.prefs.viewMode }, set: { libraryChrome.setViewMode($0) })) {
                            ForEach(ThinkspaceLibraryViewMode.allCases) { Text($0.title).tag($0) }
                        }
                    }
                } label: { Label(activeView.title, systemImage: activeView.icon).font(DS.subheadline).padding(.horizontal, DS.space8) }
                .menuStyle(.borderlessButton).fixedSize().help("Space tools and views")
            } else {
            ForEach([SpaceView.home, .library, .canvas]) { view in
                Button { onSelectView(view) } label: {
                    Label(view.title, systemImage: view.icon)
                        .lineLimit(1)
                        .font(DS.subheadline.weight(activeView == view ? .semibold : .regular))
                        .foregroundStyle(activeView == view ? DS.accent : DS.textSecondary)
                        .padding(.horizontal, DS.space10)
                        .frame(minHeight: 44)
                        .background(activeView == view ? DS.glassSectionFill : .clear, in: .capsule)
                }
                .buttonStyle(.plain)
                .help("Open \(view.title.lowercased())")
                .accessibilityAddTraits(activeView == view ? .isSelected : [])
            }
            Menu {
                Button("Start or continue inquiry", systemImage: "sparkle.magnifyingglass") { onSelectView(.deepDive) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(DS.subheadline)
                    .frame(width: 36, height: 44)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Research tools")
            .accessibilityLabel("Research tools")
            }
        }
        switch activeView {
        case .library:
            if !compact { ThinkspaceLibraryLensIsland(chrome: libraryChrome)
                .transition(.opacity)
            }
        case .deepDive:
            DeepDiveStudyTabsIsland(chrome: deepDiveChrome)
                .transition(.opacity)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var trailingIslands: some View {
        switch activeView {
        case .library:
            ThinkspaceLibraryToolsIsland(chrome: libraryChrome, compact: compact)
                .transition(.opacity)
        case .deepDive:
            DeepDiveStudyToolsIsland(chrome: deepDiveChrome)
                .transition(.opacity)
        default:
            EmptyView()
        }
        CosmoChromeIsland(recede: recedes) {
            SpaceAddMenu(activeView: activeView, actions: actions)
            SpaceMoreMenu(activeView: activeView, actions: actions)
        }
    }

    private var recedes: Bool {
        activeView == .deepDive && deepDiveChrome.recede
    }
}

// MARK: - Identity island (the name IS the title)

struct SpaceIdentityIsland: View {
    let thinkspace: Thinkspace?
    let folder: ThinkspaceLibraryFolder?
    let actions: SpaceChromeActions

    @State private var isRootDropTarget = false

    var body: some View {
        CosmoChromeIsland {
            HStack(spacing: DS.space6) {
                if let thinkspace {
                    SpaceIdentityMark(thinkspace: thinkspace, size: 16)
                        .padding(.leading, DS.space2)
                }
                rootSegment
                if let folder {
                    Image(systemName: "chevron.right")
                        .font(DS.caption.weight(.semibold))
                        .foregroundStyle(DS.textMuted)
                        .accessibilityHidden(true)
                    LibraryRenamableTitle(title: folder.title, prominent: true, help: "Rename folder") { newName in
                        actions.renameFolder(folder.id, newName)
                    }
                }
                spaceMenu
            }
            .padding(.horizontal, DS.space4)
        }
    }

    private var name: String { thinkspace?.identityLabel ?? "Space" }

    /// At root the name is the page title (click to rename); inside a folder
    /// it demotes to a waypoint that accepts drops un-filing items.
    @ViewBuilder
    private var rootSegment: some View {
        if folder == nil {
            LibraryRenamableTitle(title: name, prominent: true, help: "Rename space") { newName in
                actions.rename(newName)
            }
        } else {
            Button(action: actions.exitFolder) {
                Text(name)
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
                for uuid in items where actions.dropToRoot(uuid) { handled = true }
                return handled
            } isTargeted: { targeting in
                withAnimation(ProMotionSprings.snappy) { isRootDropTarget = targeting }
            }
            .help("Back to \(name) — drop a document here to take it out of the folder")
            .accessibilityLabel("Back to \(name)")
        }
    }

    private var spaceMenu: some View {
        Menu {
            Button { actions.pickEmoji() } label: { Label("Change emoji…", systemImage: "face.smiling") }
            Menu {
                ForEach(ThinkspaceManager.accentColorPalette, id: \.self) { hex in
                    Button { actions.recolor(hex) } label: {
                        Label {
                            Text(hex == thinkspace?.accentColorHex ? "Current" : "Colour")
                        } icon: {
                            Image(systemName: hex == thinkspace?.accentColorHex ? "checkmark.circle.fill" : "circle.fill")
                                .foregroundStyle(Color(hex: hex))
                        }
                    }
                }
            } label: { Label("Change colour", systemImage: "paintpalette") }
            Button { actions.openSettings() } label: { Label("Space settings…", systemImage: "slider.horizontal.3") }
            Divider()
            Button { actions.openAsPane() } label: { Label("Open as Pane", systemImage: "rectangle.split.2x1") }
            Divider()
            Button(role: .destructive) { actions.delete() } label: { Label("Delete space", systemImage: "trash") }
        } label: {
            Image(systemName: "chevron.down")
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(DS.textMuted)
                .frame(width: 18, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("Space menu")
        .accessibilityLabel("Space menu")
    }
}

// MARK: - ＋ and ⋯

struct SpaceAddMenu: View {
    let activeView: SpaceView
    let actions: SpaceChromeActions

    @State private var isHovered = false

    var body: some View {
        Menu {
            ForEach(SpaceAddKind.kinds(for: activeView)) { kind in
                Button { actions.addAtCamera(kind) } label: { Label(kind.title, systemImage: kind.icon) }
            }
        } label: {
            Image(systemName: "plus")
                .font(DS.subheadline.weight(.semibold))
                .foregroundStyle(isHovered ? DS.text : DS.textSecondary)
                .frame(width: 30, height: 30)
                .background(isHovered ? AnyShapeStyle(DS.glassCardFill) : AnyShapeStyle(.clear), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { hovering in withAnimation(ProMotionSprings.hover) { isHovered = hovering } }
        .help(activeView == .canvas ? "New block at the camera" : "New")
        .accessibilityLabel("New")
    }
}

struct SpaceMoreMenu: View {
    let activeView: SpaceView
    let actions: SpaceChromeActions

    @State private var isHovered = false

    var body: some View {
        Menu {
            if activeView == .canvas {
                Button { actions.organizeWorkspace() } label: { Label("Organize workspace", systemImage: "wand.and.stars") }
                Button { actions.savePlace() } label: { Label("Save this view as a Place", systemImage: "mappin.and.ellipse") }
                    .keyboardShortcut("d", modifiers: .command)
                Button { actions.showPlaces() } label: { Label("Jump to last Place", systemImage: "map") }
                Divider()
            }
            Button { actions.openSettings() } label: { Label("Space settings…", systemImage: "slider.horizontal.3") }
        } label: {
            Image(systemName: "ellipsis")
                .font(DS.subheadline.weight(.semibold))
                .foregroundStyle(isHovered ? DS.text : DS.textSecondary)
                .frame(width: 30, height: 30)
                .background(isHovered ? AnyShapeStyle(DS.glassCardFill) : AnyShapeStyle(.clear), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { hovering in withAnimation(ProMotionSprings.hover) { isHovered = hovering } }
        .help("More")
        .accessibilityLabel("More")
    }
}
