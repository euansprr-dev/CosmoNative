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
    private var items: [Atom] { store.items(in: container, spaceID: spaceID) }
    private var selected: String? { store.location(spaceID).selectedUUID }
    private var currentContainer: Atom { store.snapshots[spaceID]?.atomsByUUID[container.uuid] ?? container }
    var body: some View {
        Group {
            if view == .canvas {
                SpaceCompositionCanvasHost(spaceID: spaceID, container: currentContainer, items: items, onOpen: onOpen)
                    .id(container.uuid)
            }
            else if items.isEmpty { emptyState }
            else if view == .list { list }
            else { grid }
        }
        .background(DS.bg)
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
        .scaleEffect(hovered == atom.uuid && !reduceMotion ? 1.008 : 1)
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

    private func open(_ atom: Atom) { store.select(atom.uuid, in: spaceID); onOpen(atom) }
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
