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
    var selectedSourceIDs: () -> [String] = { [] }
}

/// What ＋ can make — the menu adapts to the active view.
enum SpaceAddKind: String, CaseIterable, Identifiable {
    case note, idea, task, content, stickyNote, deepDive, file, question, group, existing
    var id: String { rawValue }

    var title: String {
        switch self {
        case .group: return "New material group"
        case .existing: return "Add existing material…"
        case .note: return "Page"
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
        case .canvas: return [.note, .idea, .task, .content, .stickyNote, .existing, .file]
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
    private var compact: Bool { availableWidth - leadingInset < 980 }
    @State private var creating: SpaceCompositionKind?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CosmoChromeRow(insetsEnabled: true, centersAbsolutely: availableWidth - leadingInset >= 900) {
            NavigationTrailIsland(showsSidebarToggle: leadingInset == 0)
            if availableWidth - leadingInset >= 900 {
            SpaceIdentityIsland(
                thinkspace: thinkspace,
                folder: activeView == .library ? libraryFolder : nil,
                actions: actions
            )
            .frame(maxWidth: availableWidth - leadingInset >= 1200 ? 320 : 230)
            }
        } center: {
            centerIslands
        } trailing: {
            trailingIslands
        }
        .padding(.leading, leadingInset)
        .animation(reduceMotion ? nil : ProMotionSprings.gentle, value: leadingInset)
        .animation(reduceMotion ? nil : ProMotionSprings.focusTransition, value: activeView)
        .sheet(item: $creating) { kind in
            if let thinkspace {
                SpaceWorkspaceCreateSheet(spaceID: thinkspace.id, kind: kind,
                    parent: SpaceWorkspaceStore.shared.selectedItem(in: thinkspace.id))
            }
        }
    }

    @ViewBuilder
    private var centerIslands: some View {
        // Contents lives in the contextual sidebar. The same destinations stay
        // one click away when the sidebar is tucked away.
        if leadingInset == 0 {
            CosmoChromeIsland {
                Menu {
                    ForEach([SpaceView.canvas, .library, .deepDive]) { view in
                        Button(view.title, systemImage: view.icon) { onSelectView(view) }
                    }
                    if let thinkspace, let snapshot = SpaceWorkspaceStore.shared.snapshots[thinkspace.id], !snapshot.roots.isEmpty {
                        Divider()
                        ForEach(snapshot.roots, id: \.uuid) { atom in
                            Button(atom.title ?? "Untitled", systemImage: atom.spaceCompositionKind?.symbol ?? "doc.text") {
                                SpaceWorkspaceStore.shared.open(atom, in: thinkspace.id)
                            }
                        }
                    }
                } label: {
                    Label("Contents", systemImage: "sidebar.left")
                        .font(DS.subheadline.weight(.medium)).foregroundStyle(DS.textSecondary)
                        .frame(minHeight: 44).padding(.horizontal, DS.space8)
                }
                .menuStyle(.borderlessButton).menuIndicator(.visible).help("Navigate this Space")
            }
        }
    }

    @ViewBuilder
    private var trailingIslands: some View {
        CosmoChromeIsland {
            Button {
                guard let thinkspace else { return }
                SpaceInquiryRequest.start(spaceID: thinkspace.id, sources: actions.selectedSourceIDs())
                onSelectView(.deepDive)
            } label: {
                Label("Start inquiry", systemImage: "questionmark.bubble")
                    .font(DS.subheadline.weight(.medium))
                    .foregroundStyle(DS.accent)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .help("Start an inquiry with the selected materials (⌘⌥I)")
            .keyboardShortcut("i", modifiers: [.command, .option])
            if !(thinkspace.map { SpaceWorkspaceStore.shared.isPresenting(in: $0.id) } ?? false) {
            Menu {
                SpaceCreationMenuItems { creating = $0 }
                Divider()
                Button("Add existing material…", systemImage: "plus.rectangle.on.folder") { actions.addAtCamera(.existing) }
                Button("Import files…", systemImage: "arrow.down.doc") { actions.addAtCamera(.file) }
                if activeView == .canvas, let thinkspace, !SpaceWorkspaceStore.shared.isPresenting(in: thinkspace.id) {
                    Button("Sticky note", systemImage: "note.text") { actions.addAtCamera(.stickyNote) }
                }
            } label: {
                Image(systemName: "plus").font(DS.subheadline.weight(.semibold))
                    .foregroundStyle(DS.textSecondary).frame(width: 44, height: 44).contentShape(.rect)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).help("Add to Space").accessibilityLabel("Add to Space")
            }
            SpaceMoreMenu(activeView: activeView, actions: actions,
                showsCanvasActions: !(thinkspace.map { SpaceWorkspaceStore.shared.isPresenting(in: $0.id) } ?? false))
        }
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
    var showsCanvasActions = true

    @State private var isHovered = false

    var body: some View {
        Menu {
            if activeView == .canvas && showsCanvasActions {
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
