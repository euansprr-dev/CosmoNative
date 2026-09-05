import AppKit
import ImageIO
import SwiftUI

/// A group's members and a manuscript's sections retain their identities across
/// every presentation. Canvas positions never change the authored reading order.
struct SpaceWorkspaceCollectionView: View {
    let spaceID: String
    let container: Atom
    let view: SpaceCompositionView
    var onOpen: (Atom) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = SpaceWorkspaceStore.shared
    @State private var hovered: String?
    @FocusState private var focused: String?
    @State private var camera = SpaceCollectionCamera()
    @State private var viewport = CGSize.zero
    @State private var initialPositions: [String: SpaceCollectionPoint] = [:]
    @State private var optimistic: [String: SpaceCompositionPlacement] = [:]
    @State private var movingID: String?
    @State private var movement = CGSize.zero
    @GestureState private var pan = CGSize.zero
    @GestureState private var magnification: CGFloat = 1
    @State private var loadedContainerID: String?
    @State private var needsInitialFit = true

    private let cardSize = CGSize(width: 252, height: 230)
    private var items: [Atom] { store.items(in: container, spaceID: spaceID) }
    private var selected: String? { store.location(spaceID).selectedUUID }
    private var currentContainer: Atom { store.snapshots[spaceID]?.atomsByUUID[container.uuid] ?? container }
    private var cameraKey: String { "cosmo.space.collection.camera.mac.\(container.uuid)" }
    private var positionsKey: String { "cosmo.space.collection.positions.mac.\(container.uuid)" }

    var body: some View {
        Group {
            if items.isEmpty { emptyState }
            else if view == .canvas { canvas }
            else if view == .list { list }
            else { grid }
        }
        .background(DS.bg)
        .task(id: container.uuid) { restoreCamera(); ensurePositions(); fitInitialCanvasIfNeeded() }
        .onChange(of: items.map(\.uuid)) { _, _ in ensurePositions(); fitInitialCanvasIfNeeded() }
        .onChange(of: view) { _, _ in fitInitialCanvasIfNeeded() }
        .onDisappear { if view == .canvas { persistCamera() } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("space.collection.\(view.rawValue)")
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 330), spacing: DS.space24)], spacing: DS.space24) {
                ForEach(items, id: \.uuid) { atom in
                    interactive(atom) { card(atom, spatial: false) }
                }
            }.padding(DS.space32)
        }.scrollEdgeEffectStyle(.soft, for: .all)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items, id: \.uuid) { atom in
                    interactive(atom) { row(atom) }
                    if atom.uuid != items.last?.uuid {
                        Rectangle().fill(DS.borderSubtle).frame(height: 1).padding(.leading, 80)
                    }
                }
            }
            .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusLarge))
            .padding(DS.space32)
        }.scrollEdgeEffectStyle(.soft, for: .all)
    }

    private var canvas: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                DS.canvas
                    .contentShape(.rect)
                    .onTapGesture { store.select(nil, in: spaceID); focused = nil }
                    .gesture(panGesture)
                dotGrid
                    .allowsHitTesting(false)
                ForEach(visibleItems(in: geometry.size), id: \.uuid) { atom in
                    canvasCard(atom)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .simultaneousGesture(zoomGesture)
            .background(SpaceCollectionScrollBridge { event in scroll(event) })
            .overlay(alignment: .bottom) { canvasControls.padding(DS.space16) }
            .onGeometryChange(for: CGSize.self, of: \.size) { viewport = $0; fitInitialCanvasIfNeeded() }
        }
        .accessibilityElement(children: .contain)
    }

    private func canvasCard(_ atom: Atom) -> some View {
        let position = position(for: atom.uuid)
        let delta = movingID == atom.uuid ? movement : .zero
        return interactive(atom) { card(atom, spatial: true) }
            .frame(width: cardSize.width, height: cardSize.height)
            .scaleEffect(effectiveScale, anchor: .topLeading)
            .offset(x: (position.x + delta.width) * effectiveScale + effectiveOffset.width,
                    y: (position.y + delta.height) * effectiveScale + effectiveOffset.height)
            .zIndex(movingID == atom.uuid ? 2 : selected == atom.uuid ? 1 : 0)
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .global).onChanged { value in
                if movingID != atom.uuid { movingID = atom.uuid; store.select(atom.uuid, in: spaceID) }
                movement = CGSize(width: value.translation.width / effectiveScale, height: value.translation.height / effectiveScale)
            }.onEnded { value in
                let target = SpaceCompositionPlacement(itemUUID: atom.uuid,
                    x: position.x + value.translation.width / effectiveScale,
                    y: position.y + value.translation.height / effectiveScale,
                    width: cardSize.width, height: cardSize.height)
                movingID = nil; movement = .zero
                savePlacement(target)
            })
            .accessibilityAction(named: "Move left") { nudge(atom, x: -24, y: 0) }
            .accessibilityAction(named: "Move right") { nudge(atom, x: 24, y: 0) }
            .accessibilityAction(named: "Move up") { nudge(atom, x: 0, y: -24) }
            .accessibilityAction(named: "Move down") { nudge(atom, x: 0, y: 24) }
    }

    private func interactive<Content: View>(_ atom: Atom, @ViewBuilder content: () -> Content) -> some View {
        content()
            .contentShape(.rect)
            .onTapGesture(count: 2) { open(atom) }
            .onTapGesture { store.select(atom.uuid, in: spaceID); focused = atom.uuid }
            .focusable().focused($focused, equals: atom.uuid).focusEffectDisabled()
            .onKeyPress(.return) { open(atom); return .handled }
            .onKeyPress(.space) { open(atom); return .handled }
            .onKeyPress(.escape) { focused = nil; store.select(nil, in: spaceID); return .handled }
            .onHover { hovered = $0 ? atom.uuid : (hovered == atom.uuid ? nil : hovered) }
            .contextMenu { contextMenu(atom) }
            .help("\(atom.title ?? "Untitled") — double-click to open")
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(atom.title?.isEmpty == false ? atom.title! : "Untitled"), \(atom.spaceCompositionKind?.title ?? atom.type.displayName)")
            .accessibilityIdentifier("space.collection.item.\(atom.uuid)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(selected == atom.uuid ? .isSelected : [])
            .accessibilityAction { open(atom) }
    }

    private func card(_ atom: Atom, spatial: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SpaceCollectionPreview(atom: atom)
                .frame(height: spatial ? 164 : 182)
                .clipped()
            VStack(alignment: .leading, spacing: DS.space4) {
                Text(atom.title?.isEmpty == false ? atom.title! : "Untitled")
                    .font(DS.headline).foregroundStyle(DS.text).lineLimit(1)
                HStack(spacing: DS.space6) {
                    Text(atom.spaceCompositionKind?.title ?? atom.type.displayName)
                    if atom.spaceComposition?.includeInExport == false && atom.spaceCompositionKind?.isAuthored == true {
                        Text("· Not in export")
                    }
                    Spacer(minLength: 0)
                    if selected == atom.uuid { Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.accent) }
                }.font(DS.caption).foregroundStyle(DS.textMuted)
            }.padding(.horizontal, DS.space16).padding(.vertical, DS.space12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surfaceElevated)
        .clipShape(.rect(cornerRadius: DS.radiusLarge))
        .overlay { RoundedRectangle(cornerRadius: DS.radiusLarge).strokeBorder(focused == atom.uuid ? DS.focusRing : selected == atom.uuid ? DS.accent : DS.borderSubtle, lineWidth: selected == atom.uuid || focused == atom.uuid ? 2 : 1) }
        .shadow(color: DS.text.opacity(hovered == atom.uuid ? 0.07 : 0.025), radius: hovered == atom.uuid ? 14 : 5, y: hovered == atom.uuid ? 4 : 1)
        .scaleEffect(hovered == atom.uuid && movingID == nil && !reduceMotion ? 1.008 : 1)
        .animation(reduceMotion ? nil : ProMotionSprings.hover, value: hovered == atom.uuid)
    }

    private func row(_ atom: Atom) -> some View {
        HStack(spacing: DS.space16) {
            SpaceCollectionPreview(atom: atom, compact: true)
                .frame(width: 44, height: 48)
                .clipShape(.rect(cornerRadius: DS.radiusSmall))
            VStack(alignment: .leading, spacing: DS.space4) {
                Text(atom.title?.isEmpty == false ? atom.title! : "Untitled").font(DS.headline).foregroundStyle(DS.text).lineLimit(1)
                Text(atom.spaceCompositionKind?.title ?? atom.type.displayName).font(DS.caption).foregroundStyle(DS.textMuted)
            }
            Spacer(minLength: DS.space16)
            if atom.spaceComposition?.includeInExport == false && atom.spaceCompositionKind?.isAuthored == true {
                Image(systemName: "eye.slash").foregroundStyle(DS.textMuted).help("Excluded from export")
            }
            if selected == atom.uuid { Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.accent) }
            else { Image(systemName: "chevron.right").font(DS.caption).foregroundStyle(DS.textMuted) }
        }
        .padding(.horizontal, DS.space16).padding(.vertical, DS.space12)
        .background(selected == atom.uuid ? DS.accentSoft : hovered == atom.uuid ? DS.surfaceHover : .clear)
        .overlay(alignment: .leading) { if selected == atom.uuid { Rectangle().fill(DS.accent).frame(width: 3) } }
        .overlay { if focused == atom.uuid { Rectangle().strokeBorder(DS.focusRing, lineWidth: 2) } }
    }

    @ViewBuilder private func contextMenu(_ atom: Atom) -> some View {
        Button("Open", systemImage: "arrow.up.right.square") { open(atom) }
        if view == .canvas {
            Button("Bring into view", systemImage: "viewfinder") { fit(atom) }
        }
        if atom.spaceCompositionKind?.isAuthored == true {
            let included = atom.spaceComposition?.includeInExport != false
            Button(included ? "Exclude from export" : "Include in export", systemImage: included ? "eye.slash" : "eye") {
                store.perform(in: spaceID) { try await SpaceCompositionService.setIncludedInExport(!included, for: atom.uuid) }
            }
        }
        Divider()
        if container.spaceCompositionKind == .group {
            Button("Remove from group", systemImage: "rectangle.badge.minus") {
                store.perform(in: spaceID) { try await SpaceCompositionService.removeMembers([atom.uuid], from: container.uuid) }
            }
        } else {
            Button("Move to Space", systemImage: "arrow.up.doc") {
                store.perform(in: spaceID) { try await SpaceCompositionService.move(atom.uuid, to: nil, in: spaceID) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.space12) {
            Image(systemName: container.spaceCompositionKind == .group ? "photo.on.rectangle.angled" : "doc.text")
                .font(DS.title1).foregroundStyle(DS.textMuted)
            Text(container.spaceCompositionKind == .group ? "A place for what belongs together" : "Give your work a shape")
                .font(DS.title2).foregroundStyle(DS.text)
            Text(container.spaceCompositionKind == .group ? "Use Add to bring in photographs, notes, files or existing material." : "Add a page to start. Each section stays editable as your work grows.")
                .font(DS.callout).foregroundStyle(DS.textSecondary).multilineTextAlignment(.center)
        }.frame(maxWidth: 390).padding(DS.space32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var effectiveScale: CGFloat { min(2.5, max(0.2, camera.scale * magnification)) }
    private var effectiveOffset: CGSize {
        let shift = effectiveScale / camera.scale
        return CGSize(width: viewport.width / 2 + (camera.x - viewport.width / 2) * shift + pan.width,
                      height: viewport.height / 2 + (camera.y - viewport.height / 2) * shift + pan.height)
    }
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2).updating($pan) { value, state, _ in state = value.translation }
            .onEnded { camera.x += $0.translation.width; camera.y += $0.translation.height; persistCamera() }
    }
    private var zoomGesture: some Gesture {
        MagnifyGesture().updating($magnification) { value, state, _ in state = value.magnification }
            .onEnded { zoom(to: camera.scale * $0.magnification, around: CGPoint(x: viewport.width / 2, y: viewport.height / 2), animate: false) }
    }
    private var dotGrid: some View {
        SwiftUI.Canvas { context, size in
            let spacing = max(16, 32 * effectiveScale)
            let origin = effectiveOffset
            let startX = origin.width.truncatingRemainder(dividingBy: spacing)
            let startY = origin.height.truncatingRemainder(dividingBy: spacing)
            var path = Path()
            for x in stride(from: startX - spacing, through: size.width, by: spacing) {
                for y in stride(from: startY - spacing, through: size.height, by: spacing) {
                    path.addEllipse(in: CGRect(x: x, y: y, width: 1.4, height: 1.4))
                }
            }
            context.fill(path, with: .color(DS.textMuted.opacity(0.19)))
        }
    }
    private var canvasControls: some View {
        HStack(spacing: DS.space4) {
            control("Zoom out", symbol: "minus") { zoom(to: camera.scale / 1.2) }
            Text("\(Int((camera.scale * 100).rounded()))%")
                .font(DS.caption.monospacedDigit()).foregroundStyle(DS.textSecondary).frame(width: 48)
            control("Zoom in", symbol: "plus") { zoom(to: camera.scale * 1.2) }
            Rectangle().fill(DS.borderSubtle).frame(width: 1, height: 18).padding(.horizontal, DS.space8)
            control("Fit all items", symbol: "arrow.up.left.and.arrow.down.right") { fitAll() }
            if let atom = items.first(where: { $0.uuid == selected }) {
                control("Fit selection", symbol: "viewfinder") { fit(atom) }
                control("Open selection", symbol: "arrow.up.right.square") { open(atom) }
            }
        }
        .padding(DS.space4)
        .glassEffect(.regular, in: .capsule)
    }
    private func control(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(DS.callout).frame(width: 44, height: 44).contentShape(.circle) }
            .buttonStyle(.plain).foregroundStyle(DS.textSecondary).help(title).accessibilityLabel(title)
    }

    private func open(_ atom: Atom) { store.select(atom.uuid, in: spaceID); onOpen(atom) }
    private func position(for id: String) -> CGPoint {
        if let value = optimistic[id] ?? currentContainer.spaceComposition?.placements.first(where: { $0.itemUUID == id }) {
            return CGPoint(x: value.x, y: value.y)
        }
        let fallback = initialPositions[id] ?? SpaceCollectionPoint(x: 0, y: 0)
        return CGPoint(x: fallback.x, y: fallback.y)
    }
    private func visibleItems(in size: CGSize) -> [Atom] {
        let screen = CGRect(origin: .zero, size: size).insetBy(dx: -120, dy: -120)
        return items.filter { atom in
            if atom.uuid == movingID { return true }
            let point = position(for: atom.uuid)
            return CGRect(x: point.x * effectiveScale + effectiveOffset.width, y: point.y * effectiveScale + effectiveOffset.height,
                          width: cardSize.width * effectiveScale, height: cardSize.height * effectiveScale).intersects(screen)
        }
    }
    private func savePlacement(_ placement: SpaceCompositionPlacement) {
        optimistic[placement.itemUUID] = placement
        Task { @MainActor in
            do {
                try await SpaceCompositionService.setPlacement(placement, for: placement.itemUUID, in: container.uuid)
                await store.load(spaceID)
            } catch { store.report(error, in: spaceID) }
            if optimistic[placement.itemUUID] == placement { optimistic[placement.itemUUID] = nil }
        }
    }
    private func nudge(_ atom: Atom, x: Double, y: Double) {
        let point = position(for: atom.uuid)
        savePlacement(.init(itemUUID: atom.uuid, x: point.x + x, y: point.y + y, width: cardSize.width, height: cardSize.height))
    }
    private func ensurePositions() {
        var changed = false
        for atom in items where initialPositions[atom.uuid] == nil {
            let index = initialPositions.count
            initialPositions[atom.uuid] = .init(x: Double(index % 3) * 292, y: Double(index / 3) * 270)
            changed = true
        }
        if changed, let data = try? JSONEncoder().encode(initialPositions) { UserDefaults.standard.set(data, forKey: positionsKey) }
    }
    private func restoreCamera() {
        guard loadedContainerID != container.uuid else { return }
        loadedContainerID = container.uuid
        camera = SpaceCollectionCamera()
        needsInitialFit = true
        initialPositions = [:]
        optimistic = [:]
        if let data = UserDefaults.standard.data(forKey: cameraKey), let saved = try? JSONDecoder().decode(SpaceCollectionCamera.self, from: data), saved.isValid {
            camera = saved
            needsInitialFit = false
        }
        if let data = UserDefaults.standard.data(forKey: positionsKey), let positions = try? JSONDecoder().decode([String: SpaceCollectionPoint].self, from: data) { initialPositions = positions }
    }
    private func persistCamera() {
        guard camera.isValid, let data = try? JSONEncoder().encode(camera) else { return }
        needsInitialFit = false
        UserDefaults.standard.set(data, forKey: cameraKey)
    }
    private func fitInitialCanvasIfNeeded() {
        guard needsInitialFit, view == .canvas, loadedContainerID == container.uuid,
              !items.isEmpty, viewport.width > 0, viewport.height > 0 else { return }
        ensurePositions()
        let rect = items.reduce(CGRect.null) { $0.union(CGRect(origin: position(for: $1.uuid), size: cardSize)) }
        fit(rect, animate: false)
    }
    private func zoom(to scale: CGFloat, around point: CGPoint? = nil, animate: Bool = true) {
        let anchor = point ?? CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let next = min(2.5, max(0.2, scale)), ratio = next / camera.scale
        withAnimation(animate && !reduceMotion ? ProMotionSprings.gentle : nil) {
            camera.x = anchor.x + (camera.x - anchor.x) * ratio
            camera.y = anchor.y + (camera.y - anchor.y) * ratio
            camera.scale = next
        }
        persistCamera()
    }
    private func fitAll() {
        let rect = items.reduce(CGRect.null) { $0.union(CGRect(origin: position(for: $1.uuid), size: cardSize)) }
        fit(rect)
    }
    private func fit(_ atom: Atom) { fit(CGRect(origin: position(for: atom.uuid), size: cardSize)) }
    private func fit(_ rect: CGRect, animate: Bool = true) {
        guard !rect.isNull, viewport.width > 0, viewport.height > 0 else { return }
        let scale = min(1.2, max(0.2, min((viewport.width - 96) / rect.width, (viewport.height - 128) / rect.height)))
        withAnimation(reduceMotion || !animate ? nil : ProMotionSprings.gentle) {
            camera = .init(x: viewport.width / 2 - rect.midX * scale, y: (viewport.height - 64) / 2 - rect.midY * scale, scale: scale)
        }
        persistCamera()
    }
    private func scroll(_ event: SpaceCollectionScrollEvent) {
        if event.zoom {
            zoom(to: camera.scale * exp(event.dy * 0.008), around: event.location, animate: false)
        } else {
            camera.x += event.dx; camera.y += event.dy
            if event.ended { persistCamera() }
        }
    }
}

private struct SpaceCollectionPoint: Codable { var x: Double; var y: Double }
private struct SpaceCollectionCamera: Codable {
    var x: CGFloat = 48
    var y: CGFloat = 40
    var scale: CGFloat = 1
    var isValid: Bool { x.isFinite && y.isFinite && scale.isFinite && (0.2...2.5).contains(scale) }
}

/// Images decode directly at thumbnail size; only generic files need Quick Look.
struct SpaceCollectionPreview: View {
    let atom: Atom
    var compact = false
    @State private var localImage: NSImage?
    @State private var localAttempted = false
    private var sourceURL: URL? {
        if atom.type == .image, let path = atom.imageMetadata?.imagePath {
            return path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL(string: path)
        }
        if let thumbnail = atom.thumbnailUrl ?? atom.richContent?.thumbnailUrl, !thumbnail.isEmpty { return URL(string: thumbnail) }
        return nil
    }
    var body: some View {
        Group {
            if let localImage { Image(nsImage: localImage).resizable().scaledToFit() }
            else if let url = sourceURL, !url.isFileURL {
                CachedAsyncImage(url: url, stableKey: "space-preview-\(atom.uuid)") { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFit() }
                    else { placeholder(unavailable: phase.isFailure) }
                }
            } else if atom.type == .image || atom.type == .file { placeholder(unavailable: localAttempted) }
            else { documentPreview }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.surface)
        .task(id: atom.uuid + String(atom.localVersion)) { await loadLocal() }
    }
    private var documentPreview: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Image(systemName: atom.spaceCompositionKind?.symbol ?? "doc.text")
                .font(compact ? DS.headline : DS.title2).foregroundStyle(DS.textMuted)
            if !compact {
                Text(String((atom.body ?? "").prefix(360)))
                    .font(DS.callout).foregroundStyle(DS.textSecondary)
                    .lineLimit(5).frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
        }.padding(compact ? DS.space8 : DS.space20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .center : .topLeading)
    }
    private func placeholder(unavailable: Bool) -> some View {
        VStack(spacing: DS.space8) {
            Image(systemName: atom.type == .file ? "doc" : "photo").font(compact ? DS.headline : DS.title2)
            if unavailable && !compact { Text("Preview unavailable").font(DS.caption) }
        }.foregroundStyle(DS.textMuted).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func loadLocal() async {
        if let url = sourceURL, url.isFileURL {
            let image = await SpaceCollectionImageCache.shared.image(for: url, stamp: String(atom.localVersion))
            guard !Task.isCancelled else { return }
            localImage = image
            localAttempted = true
        } else if atom.type == .file {
            if case .resolved(let file) = await FilePortalResolver.resolve(entityUuid: atom.uuid), let url = file.thumbnailFileURL ?? file.fileURL {
                localImage = await FilePortalThumbnailStore.shared.thumbnail(for: url, cacheKey: file.metadata.attachmentUUID, stamp: file.metadata.thumbStamp, pixelWidth: 512)
            }
            localAttempted = true
        } else if atom.type == .image, sourceURL == nil {
            localAttempted = true
        }
    }
}

/// A small, deduplicated decoded-image cache avoids a Quick Look service round
/// trip for ordinary images and keeps full-resolution bytes off the main actor.
private actor SpaceCollectionImageCache {
    static let shared = SpaceCollectionImageCache()
    private let cache = NSCache<NSString, NSImage>()
    private var pending: [String: Task<NSImage?, Never>] = [:]

    private init() {
        cache.countLimit = 128
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func image(for url: URL, stamp: String) async -> NSImage? {
        let key = "\(url.absoluteString)|\(stamp)"
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if let task = pending[key] { return await task.value }
        let task = Task<NSImage?, Never>.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 512
                  ] as CFDictionary) else { return nil }
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
        pending[key] = task
        let image = await task.value
        pending[key] = nil
        if let image { cache.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height) * 4) }
        return image
    }
}

private extension CachedImagePhase {
    var isFailure: Bool { if case .failure = self { true } else { false } }
}

private struct SpaceCollectionScrollEvent {
    var dx: CGFloat
    var dy: CGFloat
    var location: CGPoint
    var zoom: Bool
    var ended: Bool
}

/// The monitor is limited to this visible canvas and its own window. Ordinary
/// trackpad scrolling pans; Command-scroll zooms around the pointer.
private struct SpaceCollectionScrollBridge: NSViewRepresentable {
    var onScroll: (SpaceCollectionScrollEvent) -> Void
    func makeNSView(context: Context) -> Surface { let surface = Surface(); surface.onScroll = onScroll; return surface }
    func updateNSView(_ view: Surface, context: Context) { view.onScroll = onScroll }
    static func dismantleNSView(_ view: Surface, coordinator: ()) { view.stop() }

    final class Surface: NSView {
        var onScroll: ((SpaceCollectionScrollEvent) -> Void)?
        private var monitor: Any?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      !self.isHiddenOrHasHiddenAncestor else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.visibleRect.contains(point) else { return event }
                let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
                self.onScroll?(.init(dx: event.scrollingDeltaX * multiplier, dy: event.scrollingDeltaY * multiplier,
                    location: point, zoom: event.modifierFlags.contains(.command),
                    ended: event.phase == .ended || event.momentumPhase == .ended || event.phase.isEmpty))
                return nil
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil } }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
