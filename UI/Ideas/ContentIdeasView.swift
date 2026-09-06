import SwiftUI

/// Client collections for orientation; working-document previews for discovery.
/// Scope remains owned by Content and follows the user into Pipeline and Calendar.
struct ContentIdeasView: View {
    let model: IdeasPageModel
    @Bindable var pipelineModel: PipelinePageModel
    var isActive = true
    var managesLifecycle = true
    @AppStorage("content.ideas.gallerySort") private var sort: IdeasGallerySort = .recent
    @State private var pinnedOnly = false
    @State private var selection: Set<String> = []
    @State private var anchor: String?
    @State private var cursor: String?
    @State private var quickLook: IdeaGalleryItem?
    @State private var beginning: Set<String> = []
    @State private var excerpts: [String: String] = [:]
    @State private var snapshot = IdeasGallerySnapshot.empty
    @State private var availableWidth: CGFloat = 1000
    @State private var availableHeight: CGFloat = 720
    @State private var searchExpanded = false
    @FocusState private var searchFocused: Bool
    @FocusState private var pageFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isSpace: Bool { if case .space = pipelineModel.scope { return true }; return false }
    private var showsRail: Bool { availableWidth >= 960 && !isSpace }
    private var inset: CGFloat { availableWidth < 600 ? DS.space20 : DS.space24 }
    private var galleryWidth: CGFloat { max(0, availableWidth - (showsRail ? 200 : 0) - inset * 2) }
    private var compact: Bool { galleryWidth < 660 }
    private var ready: Bool { model.isLoaded && model.loadedScope == pipelineModel.scope }
    private var visible: [IdeaGalleryItem] { snapshot.items }
    private var selectedIdeas: [IdeaGalleryItem] { visible.filter { selection.contains($0.atomUUID) } }

    var body: some View {
        ZStack {
            browser.accessibilityHidden(quickLook != nil)
            if let idea = quickLook {
                IdeaQuickLookPanel(idea: idea, model: model,
                    onOpen: { quickLook = nil; open(idea) },
                    onOpenAsPane: { quickLook = nil; open(idea, pane: true) },
                    onClose: { quickLook = nil; pageFocused = true }, availableWidth: availableWidth, availableHeight: availableHeight)
            }
        }
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { size in
            availableWidth = size.width
            availableHeight = size.height
            if snapshot.columns != IdeasGallerySnapshot.columnCount(width: galleryWidth) { refresh() }
        }
        .task {
            if managesLifecycle { await model.start() }
            refresh()
            pageFocused = isActive
        }
        .onDisappear { if managesLifecycle { model.stop() } }
        .onChange(of: isActive) { _, active in
            pageFocused = active
            if !active { searchFocused = false; searchExpanded = false; quickLook = nil }
        }
        .onChange(of: model.revision) { _, _ in refresh() }
        .onChange(of: pipelineModel.filters) { _, _ in refresh() }
        .onChange(of: pipelineModel.scope) { _, _ in resetSelection(); snapshot = .empty }
        .onChange(of: pipelineModel.showsArchivedIdeas) { _, _ in resetSelection(); refresh() }
        .onChange(of: sort) { _, _ in refresh() }
        .onChange(of: pinnedOnly) { _, _ in refresh() }
        .onChange(of: cursor) { _, id in
            if quickLook != nil { quickLook = visible.first { $0.atomUUID == id } }
        }
        .onExitCommand(perform: escape)
        .overlay(alignment: .bottom) { if quickLook == nil { selectionBar } }
        .overlay(alignment: .bottom) { deleteUndoToast }
        .overlay(alignment: .bottom) { SwipeSaveToast(message: Binding(get: { model.toastMessage }, set: { model.toastMessage = $0 })) }
        .background { if isActive { keyboardLayer } }
        .transaction { if reduceMotion { $0.animation = nil } }
    }

    private var browser: some View {
        HStack(spacing: 0) {
            if showsRail {
                IdeaCollectionsRail(collections: model.collections, scope: pipelineModel.scope,
                                    archived: pipelineModel.showsArchivedIdeas, onSelect: setScope)
            }
            VStack(spacing: 0) {
                controls
                gallery
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var controls: some View {
        HStack(spacing: DS.space16) {
            VStack(alignment: .leading, spacing: DS.space4) {
                if showsRail || isSpace { Text(collectionTitle).font(DS.title2).foregroundStyle(DS.text).lineLimit(1) }
                else { collectionMenu }
                Text(subtitle).font(DS.caption).foregroundStyle(DS.textMuted).lineLimit(1)
                    .contentTransition(.numericText())
            }.frame(maxWidth: .infinity, alignment: .leading)
            if compact {
                Button { focusSearch() } label: { Image(systemName: "magnifyingglass").frame(width: 32, height: 36) }
                    .buttonStyle(.borderless).help("Search ideas (⌘F)").accessibilityLabel("Search ideas")
                    .popover(isPresented: $searchExpanded) { searchField.frame(width: 280).padding(DS.space12) }
            } else { searchField.frame(width: 250) }
            filterMenu
        }
        .padding(.horizontal, inset).padding(.vertical, DS.space20)
    }

    private var collectionTitle: String {
        if pipelineModel.showsArchivedIdeas { return "Archived · \(scopeTitle)" }
        if pinnedOnly { return "Pinned · \(scopeTitle)" }
        return scopeTitle
    }

    private var scopeTitle: String {
        switch pipelineModel.scope {
        case .all: return "All clients"
        case .unassigned: return "Personal"
        case .client(let id): return model.collections.first { $0.clientUUID == id }?.name ?? "Client"
        case .space: return "Linked ideas"
        }
    }

    private var subtitle: String {
        guard ready else { return model.errorMessage == nil ? "Loading your collection…" : "Collection unavailable" }
        let count = snapshot.total
        if !pipelineModel.filters.isEmpty { return "\(count) matching idea\(count == 1 ? "" : "s")" }
        if snapshot.isOverview { return "\(count) ideas · \(snapshot.sections.count) collections" }
        return "\(count) idea\(count == 1 ? "" : "s") · \(sort.label.lowercased())"
    }

    private var collectionMenu: some View {
        Menu {
            Button("All clients") { setScope(.all) }
            Button("Personal") { setScope(.unassigned) }
            Divider()
            ForEach(model.collections.filter { $0.clientUUID != nil }) { client in
                Button("\(client.name) (\(client.count(archived: pipelineModel.showsArchivedIdeas)))") { setScope(client.scope) }
            }
        } label: {
            HStack(spacing: DS.space6) {
                Text(collectionTitle).font(DS.title2).lineLimit(1)
                Image(systemName: "chevron.down").font(DS.caption)
            }.foregroundStyle(DS.text)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize(horizontal: false, vertical: true)
        .help("Choose a client collection").accessibilityLabel("Collection: \(collectionTitle)")
    }

    private var searchField: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "magnifyingglass").foregroundStyle(DS.textMuted)
            TextField("Search ideas", text: $pipelineModel.filters.query)
                .textFieldStyle(.plain).focused($searchFocused).font(DS.callout)
                .accessibilityLabel("Search ideas in this collection")
            if !pipelineModel.filters.query.isEmpty {
                Button { pipelineModel.filters.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(DS.textMuted).help("Clear search").accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, DS.space12).frame(height: 32)
        .dsGlassInput(isFocused: searchFocused, cornerRadius: 16)
    }

    private var filterMenu: some View {
        Menu {
            Toggle("Pinned only", isOn: $pinnedOnly)
            Toggle("Show archived ideas", isOn: $pipelineModel.showsArchivedIdeas)
            Divider()
            Picker("Sort by", selection: $sort) {
                ForEach(IdeasGallerySort.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Picker("Platform", selection: $pipelineModel.filters.platform) {
                Text("Any platform").tag(nil as SocialPlatform?)
                ForEach(SocialPlatform.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
            }
            Picker("Format", selection: $pipelineModel.filters.format) {
                Text("Any format").tag(nil as ContentFormat?)
                ForEach(ContentFormat.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
            }
            if !pipelineModel.filters.isEmpty || pinnedOnly {
                Divider()
                Button("Clear filters") { clearFilters() }
            }
        } label: {
            Image(systemName: pipelineModel.filters.isEmpty && !pinnedOnly ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(pipelineModel.filters.isEmpty && !pinnedOnly ? DS.textSecondary : DS.accent)
                .frame(width: 32, height: 36)
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("Filter and sort ideas").accessibilityLabel("Filter and sort ideas")
    }

    private var gallery: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.space32) {
                    if let error = model.errorMessage { errorRow(error) }
                    if !ready {
                        if model.errorMessage == nil { skeleton }
                    } else if snapshot.total == 0 { emptyState }
                    else {
                        if snapshot.isOverview {
                            ForEach(snapshot.shelves) { shelf in overviewShelf(shelf) }
                        } else {
                            ForEach(snapshot.sections) { section in gallerySection(section) }
                        }
                    }
                }
                .id("ideas-top")
                .padding(.horizontal, inset).padding(.top, DS.space4).padding(.bottom, DS.space32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, selection.isEmpty ? 0 : 64)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .focusable().focusEffectDisabled().focused($pageFocused)
            .onMoveCommand(perform: moveCursor)
            .onKeyPress(.return) { openCursor() }
            .onKeyPress(.space) { previewCursor() }
            .onKeyPress(.delete) { archiveSelection() }
            .onChange(of: cursor) { _, id in
                if let id {
                    withAnimation(reduceMotion ? nil : ProMotionSprings.snappy) { proxy.scrollTo(id) }
                }
            }
            .onChange(of: pipelineModel.scope) { _, _ in proxy.scrollTo("ideas-top", anchor: .top) }
            .onChange(of: pipelineModel.filters) { _, _ in proxy.scrollTo("ideas-top", anchor: .top) }
        }
    }

    private func overviewShelf(_ shelf: IdeasGallerySnapshot.Shelf) -> some View {
        let cardWidth = (galleryWidth - CGFloat(snapshot.columns - 1) * DS.space16) / CGFloat(snapshot.columns)
        return HStack(alignment: .top, spacing: DS.space16) {
            ForEach(shelf.sections) { section in
                gallerySection(section)
                    .frame(width: cardWidth * CGFloat(section.items.count) + DS.space16 * CGFloat(max(0, section.items.count - 1)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func gallerySection(_ section: IdeasGallerySnapshot.Section) -> some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            if snapshot.isOverview { sectionHeader(section) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.space16, alignment: .top), count: snapshot.isOverview ? section.items.count : snapshot.columns),
                      alignment: .leading, spacing: DS.space16) {
                ForEach(section.items, id: \.atomUUID) { idea in
                    IdeaGalleryCard(idea: idea, excerpt: excerpts[idea.atomUUID],
                        thumbnails: model.inspirationThumbs[idea.atomUUID] ?? [],
                        showsClient: !snapshot.isOverview && (pipelineModel.scope == .all || isSpace),
                        selected: selection.contains(idea.atomUUID), cursor: cursor == idea.atomUUID,
                        selectionCount: selection.count, actions: actions(for: idea),
                        onSelect: { select(idea) }, onOpen: { open(idea) }, onPreview: { cursor = idea.atomUUID; quickLook = idea },
                        onBegin: { begin(idea) }, onBulkAssign: { model.bulkAssign(selectedIdeas, to: $0) },
                        onBulkArchive: { archiveOrRestore() })
                        .id(idea.atomUUID)
                }
            }
        }
    }

    private func sectionHeader(_ section: IdeasGallerySnapshot.Section) -> some View {
        HStack(spacing: DS.space8) {
            Circle().fill(section.scope.clientUUID.map { DS.clientColor(for: $0) } ?? DS.textMuted).frame(width: 7, height: 7)
            Text(section.title).font(DS.headline).foregroundStyle(DS.text)
            Text("\(section.total)").font(DS.caption).foregroundStyle(DS.textMuted).monospacedDigit()
            Spacer(minLength: DS.space8)
            Button { setScope(section.scope) } label: {
                HStack(spacing: DS.space4) {
                    Text(section.total > section.items.count ? "See all \(section.total)" : "Open")
                    Image(systemName: "chevron.right")
                }.font(DS.callout)
            }
            .buttonStyle(.borderless).foregroundStyle(DS.textSecondary)
            .help("Open all ideas for \(section.title)")
        }
        .frame(height: 32)
    }

    private var footer: some View {
        HStack(spacing: DS.space8) {
            Text(snapshot.isOverview ? "A preview of each collection" : "\(snapshot.total) ideas")
            Spacer(minLength: 0)
            if !compact { Text("Click to select · Space to preview · ↵ to open") }
        }
        .font(DS.caption2).foregroundStyle(DS.textMuted)
        .padding(.horizontal, inset).frame(height: 28)
        .overlay(alignment: .top) { Rectangle().fill(DS.borderSubtle).frame(height: 0.5) }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            Image(systemName: pipelineModel.showsArchivedIdeas ? "archivebox" : "lightbulb").font(DS.pageTitle).foregroundStyle(DS.textMuted)
            Text(emptyTitle).font(DS.title2).foregroundStyle(DS.text)
            Text(emptyMessage).font(DS.body).foregroundStyle(DS.textSecondary).frame(maxWidth: 440, alignment: .leading)
            if !pipelineModel.filters.isEmpty || pinnedOnly {
                Button("Clear filters", action: clearFilters).buttonStyle(.bordered)
            } else if !pipelineModel.showsArchivedIdeas {
                Button("New idea", systemImage: "plus") { model.createIdea(clientUUID: pipelineModel.scope.clientUUID) }
                    .buttonStyle(.bordered).tint(DS.accent)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, DS.space32)
    }
    private var emptyTitle: String {
        if !pipelineModel.filters.isEmpty { return "No matching ideas" }
        if pinnedOnly { return "Keep promising ideas close" }
        return pipelineModel.showsArchivedIdeas ? "Nothing archived here" : "Your next idea starts here"
    }
    private var emptyMessage: String {
        if !pipelineModel.filters.isEmpty { return "Try fewer words or clear your filters to see this collection." }
        if pinnedOnly { return "Pin an idea from its menu to find it quickly when you're ready to write." }
        if pipelineModel.showsArchivedIdeas { return "Archived ideas stay available here. Restore one whenever it becomes useful again." }
        return "Capture a thought, an angle or a question. It will gather here with the rest of this collection."
    }
    private var skeleton: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.space16), count: max(1, snapshot.columns)), spacing: DS.space16) {
            ForEach(0..<6) { _ in
                RoundedRectangle(cornerRadius: DS.radiusLarge).fill(DS.glassSectionFill).frame(height: 232)
            }
        }.accessibilityLabel("Loading ideas")
    }
    private func errorRow(_ error: String) -> some View {
        HStack { Text(error); Spacer(); Button("Retry") { Task { await model.load() } } }
            .font(DS.callout).foregroundStyle(DS.textSecondary).padding(DS.space16)
            .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusSmall))
    }

    @ViewBuilder private var selectionBar: some View {
        if !selection.isEmpty {
            HStack(spacing: DS.space16) {
                Text("\(selection.count) selected").monospacedDigit()
                if selection.count == 1, let idea = selectedIdeas.first, idea.status != .archived {
                    Button(beginning.contains(idea.atomUUID) ? "Starting…" : "Begin writing", systemImage: "square.and.pencil") { begin(idea) }
                        .disabled(beginning.contains(idea.atomUUID)).help("Create a draft from this idea")
                }
                Menu {
                    Menu("Assign client") {
                        Button("Personal") { model.bulkAssign(selectedIdeas, to: nil) }
                        Divider()
                        ForEach(model.assignableClients, id: \.uuid) { client in
                            Button(client.name) { model.bulkAssign(selectedIdeas, to: client.uuid) }
                        }
                    }
                    Button(pipelineModel.showsArchivedIdeas ? "Restore" : "Archive", action: archiveOrRestore)
                } label: { Image(systemName: "ellipsis").frame(width: 28, height: 32) }
                .menuStyle(.borderlessButton).fixedSize().help("Actions for selected ideas").accessibilityLabel("Selection actions")
                Button { resetSelection() } label: { Image(systemName: "xmark").frame(width: 28, height: 32) }
                    .help("Clear selection (Esc)").accessibilityLabel("Clear selection")
            }
            .buttonStyle(.borderless).font(DS.callout)
            .padding(.horizontal, DS.space16).frame(height: 48)
            .glassEffect(.regular, in: .capsule).padding(.bottom, DS.space24)
        }
    }

    @ViewBuilder private var deleteUndoToast: some View {
        if model.pendingDelete != nil {
            HStack(spacing: DS.space16) {
                Text("Idea deleted").font(DS.callout)
                Button("Undo") { model.undoDelete() }.buttonStyle(.borderless).tint(DS.accent)
            }
            .padding(.horizontal, DS.space20).frame(height: 44)
            .glassEffect(.regular, in: .capsule).padding(.bottom, DS.space24)
        }
    }

    private var keyboardLayer: some View {
        Group {
            Button("", action: focusSearch).keyboardShortcut("f", modifiers: .command)
            Button("") { selection = Set(visible.map(\.atomUUID)); pageFocused = true }
                .keyboardShortcut("a", modifiers: .command).disabled(searchFocused)
            Button("") { Task { await model.load() } }.keyboardShortcut("r", modifiers: .command)
        }.hidden().accessibilityHidden(true)
    }
    private func refresh() {
        guard ready else { return }
        snapshot = IdeasGallerySnapshot.make(items: pipelineModel.showsArchivedIdeas ? model.archivedIdeas : model.ideas,
            scope: pipelineModel.scope, collections: model.collections, filters: pipelineModel.filters,
            pinnedOnly: pinnedOnly, sort: sort, width: galleryWidth)
        excerpts = Dictionary(uniqueKeysWithValues: visible.compactMap { idea in
            IdeasGallerySnapshot.excerpt(for: idea).map { (idea.atomUUID, $0) }
        })
        let ids = Set(visible.map(\.atomUUID))
        selection.formIntersection(ids)
        if let cursor, !ids.contains(cursor) { self.cursor = nil }
        if let preview = quickLook { quickLook = visible.first { $0.atomUUID == preview.atomUUID } }
    }
    private func setScope(_ scope: PipelineScope) {
        resetSelection()
        pipelineModel.scope = scope
        model.scope = scope
        pageFocused = true
    }
    private func clearFilters() { pipelineModel.filters = PipelineFilters(); pinnedOnly = false }
    private func resetSelection() { selection.removeAll(); anchor = nil; cursor = nil; quickLook = nil }
    private func focusSearch() { if compact { searchExpanded = true }; searchFocused = true }
    private func escape() {
        guard isActive else { return }
        if quickLook != nil { quickLook = nil; pageFocused = true }
        else if searchExpanded || searchFocused { searchExpanded = false; searchFocused = false; pageFocused = true }
        else { resetSelection() }
    }
    private func select(_ idea: IdeaGalleryItem) {
        let mods = NSApp.currentEvent?.modifierFlags ?? []
        let ids = visible.map(\.atomUUID)
        if mods.contains(.command) {
            if selection.contains(idea.atomUUID) { selection.remove(idea.atomUUID) } else { selection.insert(idea.atomUUID) }
            anchor = idea.atomUUID
        } else if mods.contains(.shift), let anchor, let a = ids.firstIndex(of: anchor), let b = ids.firstIndex(of: idea.atomUUID) {
            selection = Set(ids[min(a, b)...max(a, b)])
        } else { selection = [idea.atomUUID]; anchor = idea.atomUUID }
        cursor = idea.atomUUID; pageFocused = true
    }
    private func actions(for idea: IdeaGalleryItem) -> IdeaDeskActions {
        IdeaDeskActions(open: { open(idea) }, openAsPane: { open(idea, pane: true) },
            togglePin: { model.togglePin(idea) }, pass: { model.pass(idea) }, setStatus: { model.setStatus(idea, to: $0) },
            assignClient: { model.assignClient(idea, to: $0) }, schedule: { model.scheduleDevelopment(idea, on: $0) },
            delete: { model.deferDelete(idea) }, dropSwipe: { model.linkSwipe(uuid: $0, toIdea: idea.atomUUID) },
            assignableClients: model.assignableClients)
    }
    private func open(_ idea: IdeaGalleryItem, pane: Bool = false) {
        NotificationCenter.default.post(name: pane ? CosmoNotification.Navigation.openAsPane : .enterFocusMode,
            object: nil, userInfo: ["type": EntityType.idea, "id": idea.entityId])
    }
    private func begin(_ idea: IdeaGalleryItem) {
        guard beginning.insert(idea.atomUUID).inserted else { return }
        Task {
            defer { beginning.remove(idea.atomUUID) }
            do {
                _ = try await IdeaPromotionService.promote(ideaUUID: idea.atomUUID,
                    options: .init(refreshInsightIfStale: false, initialPhase: .draft, openFocusMode: true))
                await model.load()
            } catch { model.toastMessage = "Couldn't begin writing. Try again." }
        }
    }
    private func moveCursor(_ direction: MoveCommandDirection) {
        guard !searchFocused else { return }
        let move: IdeasGallerySnapshot.Direction
        switch direction {
        case .left: move = .left
        case .right: move = .right
        case .up: move = .up
        case .down: move = .down
        @unknown default: return
        }
        guard let next = snapshot.nextID(from: cursor, direction: move) else { return }
        cursor = next
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            let ids = visible.map(\.atomUUID)
            if let anchor, let a = ids.firstIndex(of: anchor), let b = ids.firstIndex(of: next) { selection = Set(ids[min(a, b)...max(a, b)]) }
            else { anchor = next; selection = [next] }
        } else { selection = [next]; anchor = next }
    }
    private func openCursor() -> KeyPress.Result {
        guard !searchFocused, let idea = visible.first(where: { $0.atomUUID == cursor }) else { return .ignored }
        quickLook = nil; open(idea); return .handled
    }
    private func previewCursor() -> KeyPress.Result {
        guard !searchFocused, let idea = visible.first(where: { $0.atomUUID == cursor }) else { return .ignored }
        quickLook = quickLook == nil ? idea : nil; return .handled
    }
    private func archiveSelection() -> KeyPress.Result {
        guard !searchFocused, !selection.isEmpty, quickLook == nil else { return .ignored }
        archiveOrRestore(); return .handled
    }
    private func archiveOrRestore() {
        if pipelineModel.showsArchivedIdeas { selectedIdeas.forEach { model.setStatus($0, to: .spark) } }
        else { model.bulkArchive(selectedIdeas) }
        resetSelection()
    }
}
