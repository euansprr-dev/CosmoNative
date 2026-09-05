import AppKit
import SwiftUI

/// One working surface. The selected object supplies its useful representations;
/// a collection never inherits manuscript controls just because it lives in a Space.
struct SpaceWorkspaceView: View {
    let spaceID: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var creating: SpaceCompositionKind?
    @State private var adding = false
    @State private var addingReference = false
    @State private var preview: SpaceCompositionExportSnapshot?
    @State private var preparingExport = false
    @State private var imageItem: Atom?
    @State private var organizing: SpaceWorkspaceOrganizeAction?
    @State private var contentIdeaSource: Atom?
    @State private var preparingContentIdea = false
    private var store: SpaceWorkspaceStore { .shared }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if let atom = store.selectedItem(in: spaceID) {
                    header(atom, width: geometry.size.width)
                    Divider().overlay(DS.borderSubtle)
                    HStack(spacing: 0) {
                        content(atom)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if store.location(spaceID).sourcesVisible && geometry.size.width >= 1060 {
                            Divider().overlay(DS.borderSubtle)
                            sources.frame(width: 300)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .sheet(isPresented: Binding(get: {
                        store.location(spaceID).sourcesVisible && geometry.size.width < 1060
                    }, set: { if !$0 && store.location(spaceID).sourcesVisible { store.toggleSources(in: spaceID) } })) {
                        VStack(spacing: 0) {
                            HStack { Spacer(); Button("Done") { store.toggleSources(in: spaceID) }.keyboardShortcut(.cancelAction) }
                                .padding(DS.space16)
                            sources
                        }.frame(width: 400, height: 600).background(DS.bg)
                    }
                } else {
                    ContentUnavailableView {
                        Label(store.errors[spaceID] == nil ? "Opening…" : "Couldn't open this item", systemImage: "doc.text")
                    } description: {
                        Text(store.errors[spaceID] ?? "Your Space will be ready in a moment.")
                    } actions: {
                        if store.errors[spaceID] != nil { Button("Try again") { Task { await store.load(spaceID) } } }
                    }
                }
            }
            .padding(.top, SpaceChromeMetrics.contentTopInset)
            .background(DS.bg)
            .animation(reduceMotion ? nil : ProMotionSprings.gentle, value: store.location(spaceID).sourcesVisible)
        }
        .task(id: spaceID) { await store.load(spaceID) }
        .sheet(item: $creating) { kind in
            SpaceWorkspaceCreateSheet(spaceID: spaceID, kind: kind, parent: store.selectedItem(in: spaceID))
        }
        .sheet(isPresented: $adding) {
            if let atom = store.selectedItem(in: spaceID) {
                SpaceWorkspaceItemPicker(spaceID: spaceID, target: atom, purpose: .members)
            }
        }
        .sheet(isPresented: $addingReference) {
            if let atom = store.sourceTarget(in: spaceID) {
                SpaceWorkspaceItemPicker(spaceID: spaceID, target: atom, purpose: .references)
            }
        }
        .sheet(item: $preview) { SpaceExportPreviewView(snapshot: $0) }
        .sheet(item: $organizing) { action in
            if let atom = store.selectedItem(in: spaceID) { SpaceWorkspaceOrganizeSheet(spaceID: spaceID, source: atom, action: action) }
        }
        .sheet(item: $imageItem) { atom in SpaceWorkspaceImageViewer(atom: atom) }
        .sheet(item: $contentIdeaSource) { PageContentIdeaSheet(source: $0) }
    }

    private func header(_ atom: Atom, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            if let snapshot = store.snapshots[spaceID] {
                HStack(spacing: DS.space6) {
                    Button("Canvas") { store.showRoot(.canvas, in: spaceID) }
                    ForEach(breadcrumbs(atom, snapshot: snapshot), id: \.uuid) { ancestor in
                        Image(systemName: "chevron.right").font(DS.caption2)
                        Button(ancestor.title ?? "Untitled") { store.open(ancestor, in: spaceID) }.lineLimit(1)
                    }
                }.font(DS.caption).buttonStyle(.plain).foregroundStyle(DS.textMuted)
            }
            HStack(alignment: .center, spacing: DS.space20) {
                VStack(alignment: .leading, spacing: DS.space6) {
                    SpaceWorkspaceTitle(atom: atom, spaceID: spaceID, prominent: true)
                    Text(subtitle(atom)).font(DS.callout).foregroundStyle(DS.textMuted)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if width >= 850 { viewSwitcher(atom) }
                controls(atom)
            }
            if width < 850 { viewSwitcher(atom) }
            if let error = store.errors[spaceID] {
                HStack(spacing: DS.space12) {
                    Image(systemName: "exclamationmark.circle")
                    Text(error).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Retry") { Task { await store.load(spaceID) } }
                }.font(DS.caption).foregroundStyle(DS.textSecondary)
            }
        }.padding(.horizontal, DS.space32).padding(.top, DS.space24).padding(.bottom, DS.space20)
    }

    @ViewBuilder private func viewSwitcher(_ atom: Atom) -> some View {
        let options = store.views(for: atom, in: spaceID)
        if options.count > 1 {
            CosmoSegmentedSwitcher(options: options, label: { $0.title }, selection: Binding(
                get: { effectiveView(atom) }, set: { store.selectView($0, in: spaceID) }))
                .fixedSize().accessibilityLabel("View")
        }
    }
    private func controls(_ atom: Atom) -> some View {
        HStack(spacing: DS.space8) {
            Button {
                withAnimation(reduceMotion ? nil : ProMotionSprings.gentle) { store.toggleSources(in: spaceID) }
            } label: {
                Image(systemName: "sidebar.right").frame(width: 36, height: 36)
                    .foregroundStyle(store.location(spaceID).sourcesVisible ? DS.accent : DS.textSecondary)
            }.buttonStyle(.plain).help("Show references for the selected page (⌘⇧R)")
                .keyboardShortcut("r", modifiers: [.command, .shift]).accessibilityLabel("References")
            if atom.spaceCompositionKind?.isAuthored == true {
                Menu {
                    Button("Move into…", systemImage: "folder") { organizing = .move }
                    Button("Adapt into a new piece…", systemImage: "arrow.triangle.branch") { organizing = .adapt }
                    Button("Create content idea…", systemImage: "lightbulb") { createContentIdea(from: atom) }
                        .disabled(preparingContentIdea)
                    Divider()
                    Toggle("Include in export", isOn: Binding(get: { atom.spaceComposition?.includeInExport ?? true }, set: { included in
                        store.perform(in: spaceID) { try await SpaceCompositionService.setIncludedInExport(included, for: atom.uuid) }
                    }))
                } label: { Image(systemName: "ellipsis").frame(width: 36, height: 36) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Page actions")
                Button(action: export) {
                    Image(systemName: preparingExport ? "hourglass" : "square.and.arrow.up").frame(width: 36, height: 36)
                }.buttonStyle(.plain).disabled(preparingExport).help("Preview and export").accessibilityLabel("Preview and export")
            }
            Menu {
                if atom.spaceCompositionKind == .group {
                    Button("Add existing…", systemImage: "plus.rectangle.on.folder") { adding = true }
                    Divider()
                    SpaceCreationMenuItems { creating = $0 }
                } else {
                    Button("New section", systemImage: "doc.badge.plus") { creating = .page }
                    Button("Attach reference…", systemImage: "link") { addingReference = true }
                }
                Divider()
                Button("Import files…", systemImage: "arrow.down.doc") {
                    NotificationCenter.default.post(name: Notification.Name("com.cosmo.space.importFiles"), object: nil,
                        userInfo: ["spaceID": spaceID])
                }
            } label: { Image(systemName: "plus").frame(width: 36, height: 36) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Add to \(atom.title ?? "this item")")
        }.font(DS.body).foregroundStyle(DS.textSecondary)
    }

    @ViewBuilder private func content(_ atom: Atom) -> some View {
        switch effectiveView(atom) {
        case .canvas:
            SpaceWorkspaceCollectionView(spaceID: spaceID, container: atom, view: .canvas, onOpen: open)
        case .grid, .list:
            if store.items(in: atom, spaceID: spaceID).isEmpty {
                empty(atom)
            } else {
                SpaceWorkspaceCollectionView(spaceID: spaceID, container: atom, view: effectiveView(atom), onOpen: open)
            }
        case .outline:
            SpaceWorkspaceOutline(spaceID: spaceID, root: atom, create: { creating = .page })
        case .write:
            manuscript(atom)
        }
    }
    private func effectiveView(_ atom: Atom) -> SpaceCompositionView {
        let options = store.views(for: atom, in: spaceID)
        let stored = store.location(spaceID).view
        return options.contains(stored) ? stored : options.first ?? .write
    }
    private func manuscript(_ atom: Atom) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.space48) {
                SpacePageEditor(atom: atom, initialBlockID: store.location(spaceID).landingBlockID,
                    minimumBodyHeight: store.views(for: atom, in: spaceID).contains(.outline) ? 44 : 220).id(atom.uuid)
                ForEach(store.snapshots[spaceID]?.orderedSections(of: atom.uuid, includedOnly: false).filter { $0.atom.uuid != atom.uuid } ?? []) { section in
                    VStack(alignment: .leading, spacing: DS.space16) {
                        Divider().overlay(DS.borderSubtle)
                        HStack(alignment: .firstTextBaseline) {
                            SpaceWorkspaceTitle(atom: section.atom, spaceID: spaceID)
                            Spacer(minLength: DS.space12)
                            if section.atom.spaceComposition?.includeInExport == false {
                                Text("Not in export").font(DS.caption).foregroundStyle(DS.textMuted)
                            }
                            Button { store.select(section.atom.uuid, in: spaceID); if !store.location(spaceID).sourcesVisible { store.toggleSources(in: spaceID) } } label: {
                                Image(systemName: "link").frame(width: 32, height: 32)
                            }.buttonStyle(.plain).help("References for this section")
                        }.padding(.leading, BlockInteractionPolicy.gutterWidth)
                        SpacePageEditor(atom: section.atom, minimumBodyHeight: 44)
                    }.id(section.atom.uuid)
                }
            }
            .scrollTargetLayout()
            .frame(maxWidth: 860).padding(.horizontal, DS.space24).padding(.vertical, DS.space32)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition(id: Binding(get: { store.location(spaceID).selectedUUID }, set: { store.select($0, in: spaceID) }), anchor: .top)
        .background(DS.bg)
    }
    private func empty(_ atom: Atom) -> some View {
        ContentUnavailableView {
            Label(atom.spaceCompositionKind == .group ? "Bring things together" : "Room for the next chapter",
                  systemImage: atom.spaceCompositionKind?.symbol ?? "doc.text")
        } description: {
            Text(atom.spaceCompositionKind == .group ? "Add images, pages or references. Arrange them as your collection grows." : "Add a section, or switch to Write and start with a thought.")
        } actions: {
            if atom.spaceCompositionKind == .group { Button("Add existing…") { adding = true } }
            Button(atom.spaceCompositionKind == .group ? "New page" : "New section") { creating = .page }
                .tint(DS.accent)
        }
    }
    private var sources: some View {
        SpaceWorkspaceSources(spaceID: spaceID, add: { addingReference = true }, open: open)
    }
    private func subtitle(_ atom: Atom) -> String {
        let count = store.items(in: atom, spaceID: spaceID).count
        if atom.spaceCompositionKind == .group { return "\(count) \(count == 1 ? "item" : "items")" }
        if count > 0 { return "\(count) \(count == 1 ? "section" : "sections")" }
        return atom.spaceCompositionKind?.title ?? "Page"
    }
    private func breadcrumbs(_ atom: Atom, snapshot: SpaceCompositionSnapshot) -> [Atom] {
        let path = (store.location(spaceID).navigationPath ?? []).compactMap { snapshot.atomsByUUID[$0] }
        return path.isEmpty ? snapshot.breadcrumbs(to: atom.uuid).filter { $0.uuid != atom.uuid } : path
    }
    private func open(_ atom: Atom) {
        if atom.spaceCompositionKind != nil {
            Task { do { try await store.openOriginal(atom, from: spaceID) } catch { store.report(error, in: spaceID) } }
        }
        else if atom.type == .image { imageItem = atom }
        else if let id = atom.id {
            NotificationCenter.default.post(name: .enterFocusMode, object: nil,
                userInfo: ["type": CanvasBlock.fromAtom(atom, position: .zero).entityType, "id": id])
        }
    }
    private func export() {
        guard !preparingExport, let uuid = store.location(spaceID).itemUUID else { return }
        preparingExport = true
        Task { @MainActor in
            defer { preparingExport = false }
            guard await SpacePageEditorStore.shared.flushAll() else {
                store.report(SpaceCompositionError.conflict, in: spaceID); return
            }
            do {
                let snapshot = try await SpaceCompositionService.load(in: spaceID)
                preview = try SpaceCompositionExportSnapshot.capture(from: snapshot, rootUUID: uuid)
            } catch { store.report(error, in: spaceID) }
        }
    }

    private func createContentIdea(from atom: Atom) {
        guard !preparingContentIdea else { return }
        preparingContentIdea = true
        Task { @MainActor in
            defer { preparingContentIdea = false }
            NSApp.keyWindow?.makeFirstResponder(nil)
            await Task.yield()
            guard await SpacePageEditorStore.shared.flushAll() else {
                store.report(SpaceCompositionError.conflict, in: spaceID); return
            }
            do {
                guard let fresh = try await AtomRepository.shared.fetch(uuid: atom.uuid), !fresh.isDeleted else {
                    throw PageContentHandoffError.unavailablePage
                }
                contentIdeaSource = fresh
            } catch { store.report(error, in: spaceID) }
        }
    }
}

struct SpaceWorkspaceTitle: View {
    let atom: Atom
    let spaceID: String
    var prominent = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool
    var body: some View {
        Group {
            if editing {
                TextField("Title", text: $draft).textFieldStyle(.plain).focused($focused)
                    .onSubmit(commit).onExitCommand { editing = false }
                    .onChange(of: focused) { _, value in if !value { commit() } }
            } else {
                Button { draft = atom.title ?? ""; editing = true; focused = true } label: {
                    Text(atom.title ?? "Untitled").multilineTextAlignment(.leading).lineLimit(prominent ? 2 : nil)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                }.buttonStyle(.plain).help("Rename \(atom.title ?? "page")")
            }
        }.font(prominent ? DS.title1 : DS.title2).foregroundStyle(DS.text)
    }
    private func commit() {
        guard editing else { return }
        editing = false
        guard draft.trimmingCharacters(in: .whitespacesAndNewlines) != atom.title else { return }
        SpaceWorkspaceStore.shared.perform(in: spaceID) { try await SpaceCompositionService.rename(atom.uuid, to: draft) }
    }
}

private struct SpaceWorkspaceImageViewer: View {
    let atom: Atom
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: NSImage?
    @State private var error: String?
    @State private var zoom: CGFloat = 1
    @State private var retry = 0
    @GestureState private var pinch: CGFloat = 1
    private var sourceURL: URL? {
        guard let path = atom.imageMetadata?.imagePath, !path.isEmpty else { return nil }
        return path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL(string: path)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.space12) {
                Text(atom.title ?? "Image").font(DS.headline).lineLimit(1)
                Spacer()
                Button { changeZoom(zoom / 1.4) } label: { Image(systemName: "minus.magnifyingglass").frame(width: 44, height: 44) }
                    .help("Zoom out").accessibilityLabel("Zoom out").disabled(image == nil || zoom <= 1)
                Button("Fit") { changeZoom(1) }.frame(minHeight: 44).help("Fit the image in the window")
                Button { changeZoom(zoom * 1.4) } label: { Image(systemName: "plus.magnifyingglass").frame(width: 44, height: 44) }
                    .help("Zoom in").accessibilityLabel("Zoom in").disabled(image == nil || zoom >= 4)
                Button("Done") { dismiss() }.frame(minHeight: 44).keyboardShortcut(.cancelAction)
            }.buttonStyle(.plain).foregroundStyle(DS.text).padding(.horizontal, DS.space20).padding(.vertical, DS.space8)
            Divider()
            GeometryReader { geometry in
                if let image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image).resizable().scaledToFit()
                            .frame(width: max(1, geometry.size.width - 48) * min(4, max(1, zoom * pinch)),
                                   height: max(1, geometry.size.height - 48) * min(4, max(1, zoom * pinch)))
                            .padding(DS.space24)
                            .accessibilityLabel(atom.title ?? "Image")
                    }
                    .simultaneousGesture(MagnifyGesture().updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { changeZoom(zoom * $0.magnification, animated: false) })
                } else if let error {
                    ContentUnavailableView {
                        Label("Image unavailable", systemImage: "photo")
                    } description: { Text(error) } actions: {
                        Button("Try again") { retry += 1 }
                    }.frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    RoundedRectangle(cornerRadius: DS.radiusMedium).fill(DS.surface)
                        .overlay { Image(systemName: "photo").font(DS.title1).foregroundStyle(DS.textMuted) }
                        .padding(DS.space24).accessibilityLabel("Loading image")
                }
            }
        }.frame(minWidth: 600, idealWidth: 900, minHeight: 480, idealHeight: 700).background(DS.bg)
            .task(id: retry) { await load() }
    }
    private func changeZoom(_ next: CGFloat, animated: Bool = true) {
        withAnimation(animated && !reduceMotion ? ProMotionSprings.gentle : nil) { zoom = min(4, max(1, next)) }
    }
    private func load() async {
        error = nil
        guard let url = sourceURL else { error = "The original image has no available file location."; return }
        let pixels: CGFloat = 4096
        let result: NSImage?
        if url.isFileURL {
            result = await Task.detached(priority: .userInitiated) {
                ThumbnailCacheService.downsampledImage(contentsOf: url, maxPixelSize: pixels)
            }.value
        } else {
            // The viewer resolves the original; card thumbnails remain in their
            // small shared cache. Decoding never runs on the scrolling thread.
            let request = SupabaseClient.shared.flatMap { $0.isSupabaseHostedURL(url) ? $0.authorizedRequest(for: url) : nil } ?? URLRequest(url: url)
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true {
                result = await Task.detached(priority: .userInitiated) { ThumbnailCacheService.downsampledImage(data: data, maxPixelSize: pixels) }.value
            } else { result = nil }
        }
        guard !Task.isCancelled else { return }
        if let result { image = result }
        else { error = "The original image isn't available on this device. Its record and place in the collection have been kept." }
    }
}
