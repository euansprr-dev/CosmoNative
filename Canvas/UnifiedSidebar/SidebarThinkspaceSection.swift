// CosmoOS/Canvas/UnifiedSidebar/SidebarThinkspaceSection.swift
// The spaces list — an outline in the one row grammar, with keyboard nav,
// inline rename, nest-by-drag and per-space identity marks. Creation and
// settings live in the Space composer sheet; this section only asks for it
// via `SpaceComposerRequest`.
// March 2026 — Command Center navigation · Sept 2026 — Spaces

import SwiftUI
import AppKit

// MARK: - Sidebar Thinkspace Section

struct SidebarThinkspaceSection: View {
    var manager: ThinkspaceManager
    @Binding var currentDestination: SidebarDestination
    var onNavigate: () -> Void = {}
    @EnvironmentObject var crossDragManager: CrossThinkspaceDragManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Hover
    @State private var hoveredThinkspaceId: String?
    @State private var isEmptyStateHovered = false
    @State private var hoverPrewarmTask: Task<Void, Never>?

    // Rename
    @State private var renamingThinkspaceId: String?
    @State private var renameText: String = ""
    @FocusState private var isRenameFieldFocused: Bool

    // Outline
    @State private var expandedThinkspaces: Set<String> = []

    // Row-to-row nesting drag (reparent a space by dragging it onto another)
    @State private var reparentDropTargetId: String?
    @State private var nestDragSourceId: String?
    @State private var nestDragTranslation: CGSize = .zero

    // Keyboard
    @State private var selectedIndex: Int = 0
    @FocusState private var isSectionFocused: Bool

    private let colorOptions = ThinkspaceColorOption.defaultOptions

    private var hoverAnimation: Animation? {
        reduceMotion ? nil : ProMotionSprings.hover
    }

    private var actionAnimation: Animation? {
        reduceMotion ? nil : ProMotionSprings.snappy
    }

    /// Hover intent → prewarm: a brief dwell on a sidebar row predicts a
    /// visit, so the thinkspace's blocks load into the snapshot cache before
    /// the click (same pattern as Constellation cards). Debounced so sweeping
    /// the pointer down the sidebar stays free.
    private func scheduleHoverPrewarm(_ thinkspaceId: String, hovering: Bool) {
        hoverPrewarmTask?.cancel()
        guard hovering else { return }
        hoverPrewarmTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.prewarmThinkspace,
                object: nil,
                userInfo: ["thinkspaceId": thinkspaceId]
            )
        }
    }

    // MARK: - Data

    private var rootThinkspaces: [Thinkspace] {
        manager.sidebarThinkspaces
            .filter { $0.parentThinkspaceId == nil }
            .sorted { $0.lastOpened > $1.lastOpened }
    }

    /// Every row currently on screen, in reading order (keyboard path).
    private var visibleThinkspaces: [Thinkspace] {
        var items: [Thinkspace] = []
        for thinkspace in rootThinkspaces {
            appendVisible(from: thinkspace, into: &items)
        }
        return items
    }

    private func appendVisible(from thinkspace: Thinkspace, into items: inout [Thinkspace]) {
        items.append(thinkspace)
        guard expandedThinkspaces.contains(thinkspace.id) else { return }
        for child in manager.childThinkspaces(of: thinkspace.id) {
            appendVisible(from: child, into: &items)
        }
    }

    private var activeThinkspaceId: String? {
        if case .thinkspace(let id) = currentDestination {
            return id
        }
        return nil
    }

    // MARK: - Body

    var body: some View {
        SidebarSection(title: "Library", count: rootThinkspaces.count) {
            if rootThinkspaces.isEmpty {
                emptyState
            } else {
                ForEach(rootThinkspaces) { thinkspace in
                    thinkspaceRow(thinkspace, level: 0)
                }
                SidebarRow(title: "New space…", mark: .symbol("plus"), prominence: .ghost, help: "New space") {
                    SpaceComposerRequest.post(.create(parentId: nil))
                }
            }
        }
        .focused($isSectionFocused)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }
        .onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
        .onKeyPress(.return) { handleKeyReturn(); return .handled }
        .onKeyPress(.escape) {
            guard renamingThinkspaceId != nil else { return .ignored }
            cancelRename()
            return .handled
        }
        .onKeyPress(.rightArrow) { setSelectedExpanded(true); return .handled }
        .onKeyPress(.leftArrow) { setSelectedExpanded(false); return .handled }
        // A space made inside another: open the parent so the new row shows.
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.spaceComposerDidCreate)) { notification in
            guard let created = SpaceComposerCreated(from: notification),
                  let parentId = created.parentId else { return }
            withAnimation(actionAnimation) { _ = expandedThinkspaces.insert(parentId) }
        }
        .onPreferenceChange(ThinkspaceRowFrameKey.self) { frames in
            crossDragManager.thinkspaceRowFrames = frames
        }
    }

    // MARK: - Rows

    /// A row and, when open, its children beneath it. The chrome and the
    /// drop frame belong to the row surface alone — children are siblings,
    /// so a drop lands on exactly one row.
    private func thinkspaceRow(_ thinkspace: Thinkspace, level: Int) -> some View {
        let isExpanded = expandedThinkspaces.contains(thinkspace.id)

        return VStack(spacing: UnifiedSidebarMetrics.rowSpacing) {
            rowSurface(thinkspace, level: level)

            if isExpanded {
                childRows(manager.childThinkspaces(of: thinkspace.id), level: level + 1)
            }
        }
    }

    @ViewBuilder
    private func childRows(_ children: [Thinkspace], level: Int) -> some View {
        ForEach(children) { child in
            AnyView(thinkspaceRow(child, level: level))
        }
    }

    private func rowSurface(_ thinkspace: Thinkspace, level: Int) -> some View {
        let color = thinkspace.accentColor
        let isActive = activeThinkspaceId == thinkspace.id
        let isHovered = hoveredThinkspaceId == thinkspace.id
        let isRenaming = renamingThinkspaceId == thinkspace.id
        let isBlockDropTarget =
            crossDragManager.isDragging &&
            crossDragManager.isOverSidebar &&
            crossDragManager.hoveredThinkspaceId == thinkspace.id
        // A sibling space is being dragged onto this row to nest it.
        let isDropTarget = isBlockDropTarget || reparentDropTargetId == thinkspace.id
        // Discrete flag only — the 60Hz pulse value is read inside the row
        // chrome (via the pulse host), never here, so ticks don't re-evaluate
        // the whole section body.
        let isSpringLoadCandidate = crossDragManager.isSpringLoadCandidate(thinkspace.id)
        let isDragSource = nestDragSourceId == thinkspace.id

        return Group {
            if isRenaming {
                renameRow(thinkspace, level: level)
            } else {
                rowLabel(thinkspace, isActive: isActive, isHovered: isHovered, level: level)
            }
        }
        .modifier(ThinkspaceRowChrome(
            thinkspaceId: thinkspace.id,
            isDropTarget: isDropTarget,
            isSpringLoadCandidate: isSpringLoadCandidate,
            pulseHost: crossDragManager.springLoadPulseHost,
            accentColor: color,
            fillColor: rowFill(color: color, isActive: isActive, isHovered: isHovered, isDropTarget: isDropTarget)
        ))
        .onHover { hovering in
            hoveredThinkspaceId = hovering ? thinkspace.id : nil
            scheduleHoverPrewarm(thinkspace.id, hovering: hovering)
        }
        .contextMenu {
            thinkspaceContextMenu(thinkspace)
        }
        .animation(hoverAnimation, value: isHovered)
        .animation(hoverAnimation, value: isDropTarget)
        // Nest-by-drag: a plain SwiftUI DragGesture rather than AppKit
        // drag-and-drop. `.onDrop`/`.dropDestination` never received these
        // sidebar rows (the row chrome/controls swallow the drop), so we
        // detect the target ourselves by hit-testing the live row frames the
        // section already publishes into `crossDragManager.thinkspaceRowFrames`.
        .opacity(isDragSource ? 0.5 : 1)
        .offset(isDragSource ? nestDragTranslation : .zero)
        .zIndex(isDragSource ? 10 : 0)
        .gesture(rowNestDragGesture(for: thinkspace))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func rowLabel(_ thinkspace: Thinkspace, isActive: Bool, isHovered: Bool, level: Int) -> some View {
        HStack(spacing: DS.space8) {
            if level > 0 {
                Color.clear.frame(width: CGFloat(level) * UnifiedSidebarMetrics.nestIndent, height: 1)
            }

            identityWell(thinkspace, isActive: isActive, isHovered: isHovered)

            // Plain tap target (not a Button): a Button sits frontmost and
            // swallows the block drop that targets this row. `.onTapGesture`
            // keeps selection working while letting drops through — same
            // pattern as the dashboard task rows.
            HStack(spacing: DS.space8) {
                Text(thinkspace.identityLabel)
                    .font(DS.callout.weight(.medium))
                    .foregroundStyle(isActive ? DS.text : DS.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: DS.space8)

                if thinkspace.blockCount > 0 {
                    Text("\(thinkspace.blockCount)")
                        .font(DS.caption.monospacedDigit())
                        .foregroundStyle(isActive ? DS.textSecondary : DS.textMuted)
                        .contentTransition(.numericText())
                }
            }
            .frame(maxWidth: .infinity, minHeight: UnifiedSidebarMetrics.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { selectThinkspace(thinkspace) }
            .help("\(thinkspace.identityLabel) · \((thinkspace.kind ?? .custom).title)")
            // A tap gesture exposes no AX action — VoiceOver (and any
            // automation) needs the row to press like the Button it isn't.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(thinkspace.identityLabel)
            .accessibilityAction { selectThinkspace(thinkspace) }
        }
        .padding(.horizontal, UnifiedSidebarMetrics.rowInset)
        .frame(maxWidth: .infinity, minHeight: UnifiedSidebarMetrics.rowHeight, alignment: .leading)
    }

    /// The identity mark rests in the glyph column; hovering a row that holds
    /// children swaps in the disclosure chevron (Finder's on-hover triangle,
    /// without a gutter — labels stay on one column).
    private func identityWell(_ thinkspace: Thinkspace, isActive: Bool, isHovered: Bool) -> some View {
        let isExpandable = !manager.childThinkspaces(of: thinkspace.id).isEmpty
        let isExpanded = expandedThinkspaces.contains(thinkspace.id)
        let showsDisclosure = isExpandable && isHovered

        return ZStack {
            SpaceIdentityMark(thinkspace: thinkspace, size: UnifiedSidebarMetrics.glyphWidth)
                .opacity(showsDisclosure ? 0 : (isActive ? 1 : 0.86))
                .scaleEffect(showsDisclosure ? 0.84 : 1)

            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(DS.caption2.weight(.bold))
                .foregroundStyle(thinkspace.accentColor)
                .opacity(showsDisclosure ? 1 : 0)
                .scaleEffect(showsDisclosure ? 1 : 0.8)
        }
        .frame(width: UnifiedSidebarMetrics.glyphWidth, height: UnifiedSidebarMetrics.glyphWidth)
        .animation(hoverAnimation, value: showsDisclosure)
        .animation(hoverAnimation, value: isExpanded)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isExpandable else { return }
            toggleExpand(thinkspace)
        }
        .accessibilityLabel(
            isExpandable
                ? "\(isExpanded ? "Collapse" : "Expand") \(thinkspace.identityLabel)"
                : thinkspace.identityLabel
        )
        .accessibilityAddTraits(isExpandable ? .isButton : [])
        .accessibilityAction {
            guard isExpandable else { return }
            toggleExpand(thinkspace)
        }
        .help(isExpandable ? (isExpanded ? "Collapse" : "Expand") : thinkspace.identityLabel)
    }

    // MARK: - Rename Row

    private func renameRow(_ thinkspace: Thinkspace, level: Int) -> some View {
        HStack(spacing: DS.space8) {
            if level > 0 {
                Color.clear.frame(width: CGFloat(level) * UnifiedSidebarMetrics.nestIndent, height: 1)
            }

            SpaceIdentityMark(thinkspace: thinkspace, size: UnifiedSidebarMetrics.glyphWidth)

            TextField("Name", text: $renameText)
                .textFieldStyle(.plain)
                .font(DS.callout.weight(.medium))
                .foregroundStyle(DS.text)
                .focused($isRenameFieldFocused)
                .onSubmit { commitRename(thinkspace) }
                .onExitCommand { cancelRename() }
        }
        .sidebarInlineFieldChrome()
    }

    // MARK: - Row Nesting Drag

    /// The row under `point` (global coords) that isn't `sourceId`.
    private func nestTarget(at point: CGPoint, excluding sourceId: String) -> String? {
        crossDragManager.thinkspaceRowFrames.first { id, frame in
            id != sourceId && frame.contains(point)
        }?.key
    }

    /// Drag a space row onto another to nest it. Reparenting only moves the
    /// dragged space, so anything already nested inside it rides along.
    private func rowNestDragGesture(for thinkspace: Thinkspace) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                nestDragSourceId = thinkspace.id
                nestDragTranslation = value.translation
                let target = nestTarget(at: value.location, excluding: thinkspace.id)
                let valid = target.map { manager.canNest(thinkspace.id, under: $0) } ?? false
                let resolved = valid ? target : nil
                if resolved != reparentDropTargetId {
                    withAnimation(hoverAnimation) { reparentDropTargetId = resolved }
                }
            }
            .onEnded { value in
                let sourceId = thinkspace.id
                let target = nestTarget(at: value.location, excluding: sourceId)
                if let target, manager.canNest(sourceId, under: target) {
                    Task { @MainActor in
                        await manager.reparentThinkspace(sourceId, to: target)
                        withAnimation(actionAnimation) { _ = expandedThinkspaces.insert(target) }
                    }
                }
                withAnimation(hoverAnimation) {
                    reparentDropTargetId = nil
                    nestDragSourceId = nil
                    nestDragTranslation = .zero
                }
            }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func thinkspaceContextMenu(_ thinkspace: Thinkspace) -> some View {
        Button {
            selectThinkspace(thinkspace)
        } label: {
            Label("Open", systemImage: "arrow.right.circle")
        }

        Button {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openAsPane,
                object: nil,
                userInfo: ["thinkspaceId": thinkspace.id]
            )
        } label: {
            Label("Open as Pane", systemImage: "rectangle.split.2x1")
        }

        Divider()

        Button {
            beginRename(thinkspace)
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            SpaceComposerRequest.post(.edit(thinkspaceId: thinkspace.id))
        } label: {
            Label("Space settings…", systemImage: "slider.horizontal.3")
        }

        Button {
            SpaceComposerRequest.post(.create(parentId: thinkspace.id))
        } label: {
            Label("New Child Space", systemImage: "rectangle.stack.badge.plus")
        }

        if thinkspace.parentThinkspaceId != nil {
            Button {
                Task { await manager.reparentThinkspace(thinkspace.id, to: nil) }
            } label: {
                Label("Move to Top Level", systemImage: "arrow.up.to.line")
            }
        }

        Menu {
            ForEach(colorOptions) { option in
                Button {
                    Task { await manager.updateColor(thinkspace, to: option.hex) }
                } label: {
                    Label {
                        Text(option.name)
                    } icon: {
                        // Native NSMenu items force `systemImage:` symbols to a
                        // monochrome template, so a plain `circle.fill` renders
                        // black. A non-template NSImage swatch keeps its color.
                        Image(nsImage: option.swatchImage(selected: thinkspace.accentColorHex == option.hex))
                            .renderingMode(.original)
                    }
                }
            }
        } label: {
            Label("Change Color", systemImage: "paintpalette")
        }

        Divider()

        Button(role: .destructive) {
            Task { await manager.delete(thinkspace) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Empty State

    /// A teaching row in the row grammar: the first space is one click away.
    private var emptyState: some View {
        Button {
            SpaceComposerRequest.post(.create(parentId: nil))
        } label: {
            HStack(alignment: .top, spacing: DS.space8) {
                Image(systemName: "plus.circle")
                    .font(DS.title3)
                    .foregroundStyle(DS.accent)
                    .frame(width: UnifiedSidebarMetrics.glyphWidth, height: UnifiedSidebarMetrics.glyphWidth)

                VStack(alignment: .leading, spacing: DS.space2) {
                    Text("Create your first space")
                        .font(DS.callout.weight(.semibold))
                        .foregroundStyle(DS.text)
                    Text("A canvas, a library, or a topic's deep dive — the kind decides.")
                        .font(DS.footnote)
                        .foregroundStyle(DS.textMuted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, UnifiedSidebarMetrics.rowInset)
            .padding(.vertical, DS.space6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous))
            .sidebarRowChrome(isActive: false, isHovered: isEmptyStateHovered)
        }
        .buttonStyle(.plain)
        .onHover { isEmptyStateHovered = $0 }
        .animation(hoverAnimation, value: isEmptyStateHovered)
        .help("New space")
        .accessibilityLabel("Create your first space")
    }

    private func rowFill(color: Color, isActive: Bool, isHovered: Bool, isDropTarget: Bool) -> Color {
        if isDropTarget {
            return color.opacity(DS.palette.isDark ? 0.22 : 0.16)
        }
        return SidebarRowFill.resolve(isActive: isActive, isHovered: isHovered, tint: color)
    }

    // MARK: - Actions

    private func selectThinkspace(_ thinkspace: Thinkspace) {
        // Only set destination — MainView's onChange handles the actual switchTo()
        withAnimation(actionAnimation) {
            currentDestination = .thinkspace(id: thinkspace.id)
        }
        onNavigate()
    }

    private func beginRename(_ thinkspace: Thinkspace) {
        renameText = thinkspace.name
        renamingThinkspaceId = thinkspace.id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            isRenameFieldFocused = true
        }
    }

    private func commitRename(_ thinkspace: Thinkspace) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != thinkspace.name else {
            cancelRename()
            return
        }
        Task {
            await manager.rename(thinkspace, to: trimmed)
        }
        withAnimation(actionAnimation) {
            renamingThinkspaceId = nil
        }
    }

    private func cancelRename() {
        withAnimation(actionAnimation) {
            renamingThinkspaceId = nil
            renameText = ""
        }
    }

    private func toggleExpand(_ thinkspace: Thinkspace) {
        withAnimation(actionAnimation) {
            if expandedThinkspaces.contains(thinkspace.id) {
                expandedThinkspaces.remove(thinkspace.id)
            } else {
                expandedThinkspaces.insert(thinkspace.id)
            }
        }
    }

    // MARK: - Keyboard

    private func moveSelection(by delta: Int) {
        let items = visibleThinkspaces
        guard !items.isEmpty else { return }
        withAnimation(actionAnimation) {
            selectedIndex = min(max(selectedIndex + delta, 0), items.count - 1)
            hoveredThinkspaceId = items[selectedIndex].id
        }
    }

    private func handleKeyReturn() {
        if let renamingThinkspaceId,
           let thinkspace = manager.thinkspaces.first(where: { $0.id == renamingThinkspaceId }) {
            commitRename(thinkspace)
            return
        }
        let items = visibleThinkspaces
        guard selectedIndex < items.count else { return }
        selectThinkspace(items[selectedIndex])
    }

    private func setSelectedExpanded(_ expanded: Bool) {
        let items = visibleThinkspaces
        guard selectedIndex < items.count else { return }
        let thinkspace = items[selectedIndex]
        withAnimation(actionAnimation) {
            if expanded {
                guard !manager.childThinkspaces(of: thinkspace.id).isEmpty else { return }
                expandedThinkspaces.insert(thinkspace.id)
            } else {
                expandedThinkspaces.remove(thinkspace.id)
            }
        }
    }
}

private struct ThinkspaceColorOption: Identifiable {
    let name: String
    let hex: String

    var id: String { hex }

    static let defaultOptions: [ThinkspaceColorOption] = [
        ThinkspaceColorOption(name: "Moss", hex: "#2D6A4F"),
        ThinkspaceColorOption(name: "Sky", hex: "#4A7B9D"),
        ThinkspaceColorOption(name: "Clay", hex: "#C7623F"),
        ThinkspaceColorOption(name: "Violet", hex: "#8B6BAB"),
        ThinkspaceColorOption(name: "Ochre", hex: "#B08C5A"),
        ThinkspaceColorOption(name: "Teal", hex: "#4A8B72"),
        ThinkspaceColorOption(name: "Rose", hex: "#B06B6B"),
        ThinkspaceColorOption(name: "Cobalt", hex: "#5B84B0"),
    ]

    var color: Color { Color(hex: hex) }

    /// A full-color, non-template swatch for use as a native-menu icon.
    /// `Label(_, systemImage:)` symbols are force-templated to monochrome inside
    /// an `NSMenu`, so the color dots read as black; a non-template `NSImage`
    /// preserves its fill. The selected option gets a white checkmark inside.
    func swatchImage(selected: Bool) -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor(color).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()

            if selected {
                let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .heavy)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
                if let check = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
                    .withSymbolConfiguration(config) {
                    let checkSize = check.size
                    check.draw(in: NSRect(
                        x: (rect.width - checkSize.width) / 2,
                        y: (rect.height - checkSize.height) / 2,
                        width: checkSize.width,
                        height: checkSize.height
                    ))
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}

// MARK: - Thinkspace Row Chrome

/// The row surface: the one selection wash, plus the drop-target and
/// spring-load states a block drag needs. Extracted as a ViewModifier to keep
/// the row's opaque type shallow (deep overlay/background chains have
/// stack-overflowed the type checker).
private struct ThinkspaceRowChrome: ViewModifier {
    let thinkspaceId: String
    let isDropTarget: Bool
    let isSpringLoadCandidate: Bool
    /// Read here — and only here — so the 60Hz pulse invalidates just this
    /// chrome, never the owning section body (CortexScrollMetricsStore pattern).
    let pulseHost: SpringLoadPulseHost
    let accentColor: Color
    let fillColor: Color

    private var springLoadPulse: CGFloat {
        isSpringLoadCandidate ? pulseHost.pulse : 0
    }

    private var isSpringLoading: Bool {
        springLoadPulse > 0
    }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(springLoadFill)
            .overlay(strokeOverlay)
            .shadow(
                color: (isDropTarget || isSpringLoading)
                    ? accentColor.opacity(0.20 + springLoadPulse * 0.32)
                    : .clear,
                radius: 10 + springLoadPulse * 8,
                x: 0,
                y: 0
            )
            .background(frameTracker)
    }

    private var springLoadFill: some View {
        RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous)
            .fill(accentColor.opacity(0.07 + springLoadPulse * 0.16))
            .opacity(isSpringLoading ? 1 : 0)
    }

    /// A stroke only while a drag is armed on this row — selection is a
    /// wash, never an outline.
    private var strokeOverlay: some View {
        RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous)
            .strokeBorder(
                isSpringLoading
                    ? accentColor.opacity(0.24 + springLoadPulse * 0.36)
                    : (isDropTarget ? accentColor.opacity(0.34) : Color.clear),
                lineWidth: 1.5
            )
    }

    private var frameTracker: some View {
        GeometryReader { geo in
            Color.clear
                .preference(
                    key: ThinkspaceRowFrameKey.self,
                    value: [thinkspaceId: geo.frame(in: .global)]
                )
        }
    }
}
