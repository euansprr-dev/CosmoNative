// CosmoOS/Canvas/Library/ThinkspaceLibraryIconsView.swift
// The Icons lens: a strict uniform grid (Finder's icon view), never a
// masonry. Objects are recognizable-not-readable at small scales; rows stay
// aligned because every cell shares one fixed well height. Folders and
// documents share cell metrics so the whole page reads as one grid.

import SwiftUI
import AppKit

// MARK: - Lens context (everything a cell needs)

/// Bundled dependencies for cells, so lens signatures stay flat and cells
/// never reach into global state.
struct ThinkspaceLibraryLensContext {
    let selection: ThinkspaceLibrarySelectionModel
    let actions: ThinkspaceLibraryActions
    let folders: [ThinkspaceLibraryFolder]
    let currentFolder: ThinkspaceLibraryFolder?
    let cardModel: (ThinkspaceLibraryItem) -> ThinkspaceLibraryCardModel
    let openFolder: (ThinkspaceLibraryFolder) -> Void
    /// All items currently selected, for batch actions from any cell.
    let selectedItems: () -> [ThinkspaceLibraryItem]
    /// Files every selected on-canvas item into a folder (batch move).
    let fileSelectionIntoFolder: (UUID) -> Void
    let deleteFolder: (ThinkspaceLibraryFolder) -> Void
}

/// The shared coordinate space cells register their frames in.
enum ThinkspaceLibrarySpace {
    static let name = "thinkspace-library-browser"
}

// MARK: - Icons Lens

struct ThinkspaceLibraryIconsView: View {
    let folders: [ThinkspaceLibraryFolder]
    let sections: [(title: String, items: [ThinkspaceLibraryItem])]
    let scale: ThinkspaceLibraryIconScale
    let cascadeOnAppear: Bool
    let context: ThinkspaceLibraryLensContext

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space32) {
            if !folders.isEmpty {
                folderSection
            }
            ForEach(sections, id: \.title) { section in
                itemSection(section)
            }
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: scale.cellWidth, maximum: scale.cellWidth), spacing: DS.space18, alignment: .top)]
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            CosmoSectionHeader(label: "Folders", detail: "\(folders.count)")
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: DS.space20) {
                ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                    LibraryFolderCell(
                        folder: folder,
                        scale: scale,
                        appearIndex: index,
                        cascadeOnAppear: cascadeOnAppear,
                        context: context
                    )
                    // Keyboard navigation scrolls by selection id (uuidString).
                    .id(folder.id.uuidString)
                    .transition(ThinkspaceLibraryTransitions.entry)
                }
            }
        }
    }

    private func itemSection(_ section: (title: String, items: [ThinkspaceLibraryItem])) -> some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            CosmoSectionHeader(label: section.title, detail: "\(section.items.count)")
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: DS.space20) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    LibraryDocumentCell(
                        model: context.cardModel(item),
                        scale: scale,
                        appearIndex: folders.count + index,
                        cascadeOnAppear: cascadeOnAppear,
                        context: context
                    )
                    .id(item.id)
                    .transition(ThinkspaceLibraryTransitions.entry)
                }
            }
        }
    }
}

/// Finder-style settle: arriving content rises in a touch; departing content
/// simply fades so the two never fight for attention.
enum ThinkspaceLibraryTransitions {
    static let entry: AnyTransition = .asymmetric(
        insertion: .opacity.combined(with: .offset(y: 10)),
        removal: .opacity
    )
}

// MARK: - Click grammar (shared by all cells)

enum LibraryClickGestures {
    /// Single click selects (⌘ toggles, ⇧ ranges — read from the live event);
    /// double click opens. One gesture pair, every lens. Gesture callbacks
    /// fire on the main thread, so hopping onto the main actor is assumption,
    /// not dispatch — selection stays synchronous with the click.
    static func selectAndOpen(
        id: String,
        selection: ThinkspaceLibrarySelectionModel,
        onOpen: @escaping @MainActor () -> Void
    ) -> some Gesture {
        SimultaneousGesture(
            TapGesture(count: 2).onEnded {
                MainActor.assumeIsolated { onOpen() }
            },
            TapGesture().onEnded {
                MainActor.assumeIsolated {
                    let modifiers = NSApp.currentEvent?.modifierFlags ?? []
                    withAnimation(ProMotionSprings.snappy) {
                        selection.click(id, modifiers: modifiers)
                    }
                }
            }
        )
    }
}

// MARK: - Folder cell

struct LibraryFolderCell: View {
    let folder: ThinkspaceLibraryFolder
    let scale: ThinkspaceLibraryIconScale
    var appearIndex: Int = 0
    var cascadeOnAppear: Bool = true
    let context: ThinkspaceLibraryLensContext

    @State private var isHovered = false
    @State private var isDropTarget = false
    @State private var hasAppeared = false
    /// Finder's spring-open: hold a drag over the folder and it opens.
    @State private var springOpenTask: Task<Void, Never>?
    @FocusState private var renameFocused: Bool
    @State private var draftName = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isSelected: Bool { context.selection.isSelected(folder.id.uuidString) }
    private var isRenaming: Bool { context.selection.renamingID == folder.id.uuidString }

    private var iconSize: CGSize {
        let height = scale.wellHeight * 0.68
        return CGSize(width: height * 1.37, height: height)
    }

    var body: some View {
        cell
            .scaleEffect(isDropTarget ? 1.05 : 1)
            .animation(ProMotionSprings.hover, value: isHovered)
            .animation(ProMotionSprings.snappy, value: isSelected)
            .animation(ProMotionSprings.bouncy, value: isDropTarget)
            .opacity(hasAppeared || reduceMotion ? 1 : 0)
            .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.96)
            .onHover { isHovered = $0 }
            .onAppear(perform: animateEntrance)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(ThinkspaceLibrarySpace.name))
            } action: { frame in
                context.selection.register(id: folder.id.uuidString, frame: frame)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel("\(folder.displayLabel) folder, \(folder.items.count) items. Drop a document here to file it.")
    }

    private var cell: some View {
        VStack(spacing: DS.space8) {
            iconWell
            label
        }
        .padding(.vertical, DS.space8)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(LibraryClickGestures.selectAndOpen(
            id: folder.id.uuidString,
            selection: context.selection,
            onOpen: { context.openFolder(folder) }
        ))
        .dropDestination(for: String.self) { items, _ in
            springOpenTask?.cancel()
            return handleDrop(items)
        } isTargeted: { targeting in
            isDropTarget = targeting
            scheduleSpringOpen(targeting)
        }
        // contextMenu must wrap the drop destination — the other way round,
        // the drop machinery swallows right-clicks and the menu never appears.
        .contextMenu { menuItems }
        .help("Open \(folder.displayLabel) — \(folder.items.count) item\(folder.items.count == 1 ? "" : "s")")
    }

    private var iconWell: some View {
        LibraryFolderIconV2(folder: folder)
            .frame(width: iconSize.width, height: iconSize.height)
            .scaleEffect(isHovered && !isDropTarget ? 1.02 : 1)
            .padding(DS.space8)
            // Finder's grammar: a soft grey backing hugging the icon — never
            // a ring. The drop-target state keeps the folder-color ring
            // because that's a drag affordance, not selection.
            .background(
                RoundedRectangle(cornerRadius: scale.objectCornerRadius + 4, style: .continuous)
                    .fill(DS.text.opacity(isSelected ? 0.09 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: scale.objectCornerRadius + 4, style: .continuous)
                    .strokeBorder(folder.color.opacity(isDropTarget ? 0.6 : 0), lineWidth: 2)
            )
            .frame(height: scale.wellHeight, alignment: .bottom)
    }

    @ViewBuilder
    private var label: some View {
        VStack(spacing: 2) {
            if isRenaming {
                LibraryInlineRenameField(
                    draft: $draftName,
                    focused: $renameFocused,
                    font: scale.labelFont.weight(.medium),
                    onCommit: commitRename,
                    onCancel: { context.selection.renamingID = nil }
                )
            } else {
                Text(folder.displayLabel)
                    .font(scale.labelFont.weight(.medium))
                    .foregroundStyle(isSelected ? .white : DS.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.space6)
                    .padding(.vertical, 1)
                    .background(
                        isSelected ? DS.accent : .clear,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
            }
            Text("\(folder.items.count)")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(height: 40, alignment: .top)
        .onChange(of: isRenaming) { _, renaming in
            if renaming {
                draftName = folder.title
                DispatchQueue.main.async { renameFocused = true }
            }
        }
    }

    private func commitRename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != folder.title {
            context.actions.renameFolder(folder.id, trimmed)
        }
        context.selection.renamingID = nil
    }

    private func handleDrop(_ uuids: [String]) -> Bool {
        // A drop of any selected item carries the whole selection (the flock).
        var moved = false
        let payload = expandedPayload(uuids)
        for uuid in payload where !folder.items.contains(where: { $0.entityUuid == uuid }) {
            context.actions.fileIntoFolder(uuid, folder.id)
            moved = true
        }
        return moved
    }

    private func expandedPayload(_ uuids: [String]) -> [String] {
        let selectedItems = context.selectedItems()
        if let first = uuids.first,
           selectedItems.count > 1,
           selectedItems.contains(where: { $0.entityUuid == first }) {
            return selectedItems.filter(\.isOnCanvas).map(\.entityUuid)
        }
        return uuids
    }

    /// Hold a drag over the folder for a beat and it opens under the drag —
    /// Finder's spring-loaded folders.
    private func scheduleSpringOpen(_ targeting: Bool) {
        springOpenTask?.cancel()
        guard targeting else { return }
        springOpenTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))
            guard !Task.isCancelled, isDropTarget else { return }
            context.openFolder(folder)
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Open", systemImage: "folder") { context.openFolder(folder) }
        Button("Rename…", systemImage: "pencil") {
            context.selection.renamingID = folder.id.uuidString
        }
        LibraryFolderColorMenu(folder: folder, onRecolor: { context.actions.recolorFolder(folder.id, $0) })
        Divider()
        Button("Delete Folder", systemImage: "trash", role: .destructive) {
            context.deleteFolder(folder)
        }
    }

    private func animateEntrance() {
        guard cascadeOnAppear, !reduceMotion, !hasAppeared else { hasAppeared = true; return }
        withAnimation(ProMotionSprings.cascade(index: min(appearIndex, 8))) { hasAppeared = true }
    }
}

// MARK: - Folder color menu (shared with list rows)

struct LibraryFolderColorMenu: View {
    let folder: ThinkspaceLibraryFolder
    let onRecolor: (Int) -> Void

    var body: some View {
        Menu("Color") {
            ForEach(Array(CanvasCluster.palette.enumerated()), id: \.offset) { index, color in
                Button {
                    onRecolor(index)
                } label: {
                    Label {
                        Text(LibraryFolderSwatch.name(at: index))
                    } icon: {
                        Image(nsImage: LibraryFolderSwatch.image(for: color, selected: index == normalizedColorIndex))
                    }
                }
            }
        }
    }

    private var normalizedColorIndex: Int {
        let count = CanvasCluster.palette.count
        return ((folder.colorIndex % count) + count) % count
    }
}

/// Color swatches for the folder context menu — pre-rendered NSImages so the
/// menu shows real color (SwiftUI menus render SF Symbols as template/mono).
enum LibraryFolderSwatch {
    // Mirrors CanvasCluster.paletteHexes order.
    private static let paletteNames = ["Indigo", "Purple", "Pink", "Orange", "Green", "Cyan", "Blue", "Coral"]

    static func name(at index: Int) -> String {
        guard index >= 0, index < paletteNames.count else { return "Color \(index + 1)" }
        return paletteNames[index]
    }

    static func image(for color: Color, selected: Bool) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor(color).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5)).fill()
            if selected {
                NSColor.white.setStroke()
                let check = NSBezierPath()
                check.lineWidth = 1.6
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                check.move(to: NSPoint(x: rect.midX - 3.4, y: rect.midY + 0.2))
                check.line(to: NSPoint(x: rect.midX - 1.2, y: rect.midY - 2.4))
                check.line(to: NSPoint(x: rect.midX + 3.6, y: rect.midY + 2.8))
                check.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}

// MARK: - Document cell

struct LibraryDocumentCell: View {
    let model: ThinkspaceLibraryCardModel
    let scale: ThinkspaceLibraryIconScale
    var appearIndex: Int = 0
    var cascadeOnAppear: Bool = true
    let context: ThinkspaceLibraryLensContext

    @State private var isHovered = false
    @State private var hasAppeared = false
    @FocusState private var renameFocused: Bool
    @State private var draftName = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var item: ThinkspaceLibraryItem { model.item }
    private var isSelected: Bool { context.selection.isSelected(item.id) }
    private var isRenaming: Bool { context.selection.renamingID == item.id }

    var body: some View {
        draggableCell
            .scaleEffect(isHovered ? 1.012 : 1)
            .animation(ProMotionSprings.hover, value: isHovered)
            .animation(ProMotionSprings.snappy, value: isSelected)
            .opacity(hasAppeared || reduceMotion ? 1 : 0)
            .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.96)
            .onHover { isHovered = $0 }
            .onAppear(perform: animateEntrance)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(ThinkspaceLibrarySpace.name))
            } action: { frame in
                context.selection.register(id: item.id, frame: frame)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel("\(item.title), \(model.kindLabel), \(item.isOnCanvas ? "on canvas" : "stored")")
    }

    // On-canvas items can be dragged into folders; stored items aren't draggable.
    @ViewBuilder
    private var draggableCell: some View {
        if item.block != nil {
            cell.draggable(item.entityUuid) { dragPreview }
        } else {
            cell
        }
    }

    /// Dragging a selected cell carries the whole selection as a flock.
    @ViewBuilder
    private var dragPreview: some View {
        let count = context.selection.count
        if isSelected && count > 1 {
            ThinkspaceLibraryFlockDragPreview(lead: model, count: count)
        } else {
            ThinkspaceLibraryDragPreview(model: model)
        }
    }

    private var cell: some View {
        VStack(spacing: DS.space8) {
            objectWell
            label
        }
        .padding(.vertical, DS.space8)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(LibraryClickGestures.selectAndOpen(
            id: item.id,
            selection: context.selection,
            onOpen: { context.actions.openItem(item) }
        ))
        .contextMenu { LibraryItemMenuItems(model: model, context: context) }
    }

    private var objectWell: some View {
        LibraryDocumentObject(
            model: model,
            wellWidth: scale.cellWidth - DS.space12,
            wellHeight: scale.wellHeight,
            cornerRadius: scale.objectCornerRadius,
            miniature: scale != .large,
            isSelected: isSelected
        )
        .overlay(alignment: .topTrailing) { quickOpenButton }
        .cardShadow(isHovered: isHovered)
    }

    private var quickOpenButton: some View {
        Button {
            context.actions.openItem(item)
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.text)
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .opacity(isHovered && scale != .small ? 1 : 0)
        .allowsHitTesting(isHovered && scale != .small)
        .padding(DS.space6)
        .help("Open (⌘O)")
        .accessibilityLabel("Open \(item.title)")
    }

    @ViewBuilder
    private var label: some View {
        VStack(spacing: 0) {
            if isRenaming {
                LibraryInlineRenameField(
                    draft: $draftName,
                    focused: $renameFocused,
                    font: scale.labelFont.weight(.medium),
                    onCommit: commitRename,
                    onCancel: { context.selection.renamingID = nil }
                )
            } else {
                // macOS selection, one-to-one: accent-filled label pill with
                // white text — the label is the loudest selected element.
                Text(item.title)
                    .font(scale.labelFont.weight(.medium))
                    .foregroundStyle(isSelected ? .white : DS.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.space6)
                    .padding(.vertical, 1)
                    .background(
                        isSelected ? DS.accent : .clear,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
            }
        }
        .frame(height: 38, alignment: .top)
        .padding(.horizontal, 2)
        .onChange(of: isRenaming) { _, renaming in
            if renaming {
                draftName = item.title
                DispatchQueue.main.async { renameFocused = true }
            }
        }
    }

    private func commitRename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != item.title {
            context.actions.renameItem(item, trimmed)
        }
        context.selection.renamingID = nil
    }

    private func animateEntrance() {
        guard cascadeOnAppear, !reduceMotion, !hasAppeared else { hasAppeared = true; return }
        withAnimation(ProMotionSprings.cascade(index: min(appearIndex, 8))) { hasAppeared = true }
    }
}

// MARK: - Inline rename field (one dialect, all cells)

struct LibraryInlineRenameField: View {
    @Binding var draft: String
    var focused: FocusState<Bool>.Binding
    let font: Font
    let onCommit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        TextField("Name", text: $draft)
            .textFieldStyle(.plain)
            .font(font)
            .multilineTextAlignment(.center)
            .focused(focused)
            .onSubmit(onCommit)
            .onExitCommand(perform: onCancel)
            .onChange(of: focused.wrappedValue) { _, isFocused in
                if !isFocused { onCommit() }
            }
            .padding(.horizontal, DS.space8)
            .padding(.vertical, 2)
            .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(DS.focusRing, lineWidth: 1)
            )
            .frame(maxWidth: 150)
    }
}

// MARK: - Item context menu (shared by icons, list, gallery)

struct LibraryItemMenuItems: View {
    let model: ThinkspaceLibraryCardModel
    let context: ThinkspaceLibraryLensContext

    private var item: ThinkspaceLibraryItem { model.item }
    /// Multi-selection menus act on the group; single menus on the item.
    private var batch: [ThinkspaceLibraryItem] {
        let selected = context.selectedItems()
        return selected.count > 1 && selected.contains(where: { $0.id == item.id }) ? selected : [item]
    }

    var body: some View {
        openItems
        moveItems
        renameItem
        copyLinkItem
        deleteItems
    }

    @ViewBuilder
    private var openItems: some View {
        if batch.count > 1 {
            Button("Open \(batch.count) Items", systemImage: "arrow.up.left.and.arrow.down.right") {
                for target in batch.prefix(4) { context.actions.openItem(target) }
            }
        } else {
            Button("Open", systemImage: "arrow.up.left.and.arrow.down.right") { context.actions.openItem(item) }
            Button("Peek", systemImage: "eye") {
                guard item.entityId > 0 else { return }
                PeekController.shared.peek(.entity(EntitySelection(id: item.entityId, type: item.entityType)))
            }
            if item.isOnCanvas {
                Button("Reveal on Canvas", systemImage: "scope") { context.actions.revealOnCanvas(item) }
            }
        }
    }

    @ViewBuilder
    private var moveItems: some View {
        let movable = batch.filter(\.isOnCanvas)
        if !movable.isEmpty {
            let targets = context.folders.filter { $0.id != context.currentFolder?.id }
            if !targets.isEmpty || context.currentFolder != nil { Divider() }
            if !targets.isEmpty {
                Menu(movable.count > 1 ? "Move \(movable.count) to Folder" : "Move to Folder") {
                    ForEach(targets) { folder in
                        Button(folder.title) {
                            for target in movable { context.actions.fileIntoFolder(target.entityUuid, folder.id) }
                        }
                    }
                }
            }
            if let current = context.currentFolder {
                Button("Remove from “\(current.title)”", systemImage: "folder.badge.minus") {
                    for target in movable { context.actions.removeFromFolder(target.entityUuid, current.id) }
                }
            }
        }
    }

    @ViewBuilder
    private var renameItem: some View {
        if batch.count == 1 {
            Button("Rename…", systemImage: "pencil") {
                context.selection.renamingID = item.id
            }
        }
    }

    @ViewBuilder
    private var copyLinkItem: some View {
        if batch.count == 1, let url = model.metadata["url"], !url.isEmpty {
            Divider()
            Button("Copy Link", systemImage: "link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
            }
        }
    }

    private var deleteItems: some View {
        Group {
            Divider()
            Button(
                batch.count > 1 ? "Delete \(batch.count) Items" : "Delete",
                systemImage: "trash",
                role: .destructive
            ) {
                for target in batch { context.actions.deleteItem(target) }
            }
        }
    }
}
