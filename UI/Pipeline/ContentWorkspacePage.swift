import SwiftUI

/// One editorial workspace. Scope belongs here, so changing the way work is
/// viewed can never silently change whose work is on screen.
enum ContentWorkspaceTab: String, CaseIterable, Identifiable {
    case ideas, pipeline, calendar
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String { cosmoIcon.systemName }

    var cosmoIcon: CosmoIcon {
        switch self {
        case .ideas: return .idea
        case .pipeline: return .pipeline
        case .calendar: return .calendar
        }
    }
}

struct ContentWorkspacePage: View {
    @Binding var destination: SidebarDestination
    @Binding var boardRequest: String?
    let pipelineModel: PipelinePageModel
    let ideasModel: IdeasPageModel
    let clientsModel: ClientsPageModel
    @State private var tab: ContentWorkspaceTab = .ideas
    @State private var visitedTabs: Set<ContentWorkspaceTab> = [.ideas]
    @State private var showingClients = false
    @State private var briefClient: PipelineClient?
    @State private var listLayout = false
    @State private var availableWidth: CGFloat = 1000
    private var compact: Bool { availableWidth < 660 }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
        VStack(spacing: 0) {
            header
            Divider().overlay(DS.borderSubtle)
            retainedPages(width: geometry.size.width)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(DS.bg)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { availableWidth = $0 }
        .task {
            route()
            consumeBoardRequest()
            async let pipelineStart: Void = pipelineModel.start()
            async let ideasStart: Void = ideasModel.start()
            _ = await (pipelineStart, ideasStart)
        }
        .onChange(of: destination) { _, _ in route() }
        .onChange(of: boardRequest) { _, _ in consumeBoardRequest() }
        .onChange(of: pipelineModel.scope) { _, scope in ideasModel.scope = scope }
        .onChange(of: tab) { _, value in
            visitedTabs.insert(value)
            updateLayout()
            syncDestination(to: value)
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.openPipeline)) { notification in
            if notification.userInfo?["tab"] as? String == "ideas" { tab = .ideas }
            else { tab = notification.userInfo?["view"] as? String == "calendar" ? .calendar : .pipeline }
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.openIdeas)) { _ in tab = .ideas }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.openClients)) { notification in
            if notification.userInfo?["clientUUID"] == nil { showingClients = true }
        }
        .onDisappear { pipelineModel.stop(); ideasModel.stop() }
        .sheet(isPresented: $showingClients) { clientsSheet }
        .sheet(item: $briefClient) { client in ContentClientBrief(client: client) }
        .background(keyboardLayer)
    }

    /// Lazily mount each page once. A tab switch changes visibility, not identity:
    /// scroll positions, selection, calendar month and decoded data all survive.
    private func retainedPages(width: CGFloat) -> some View {
        ZStack {
            if tab == .ideas || visitedTabs.contains(.ideas) {
                ContentIdeasView(model: ideasModel, pipelineModel: pipelineModel,
                                 isActive: tab == .ideas, managesLifecycle: false)
                    .modifier(ContentTabVisibility(active: tab == .ideas))
            }
            if tab == .pipeline || visitedTabs.contains(.pipeline) {
                PipelinePage(model: pipelineModel, workspace: true, availableWidth: width,
                             displayView: listLayout ? .list : .board, isActive: tab == .pipeline)
                    .modifier(ContentTabVisibility(active: tab == .pipeline))
            }
            if tab == .calendar || visitedTabs.contains(.calendar) {
                PipelinePage(model: pipelineModel, workspace: true, availableWidth: width,
                             displayView: .calendar, isActive: tab == .calendar)
                    .modifier(ContentTabVisibility(active: tab == .calendar))
            }
        }
        // The switcher's thumb keeps its spring. Hundreds of content views do not
        // cross-fade/re-layout inside that same animated transaction.
        .transaction { $0.animation = nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            HStack(alignment: .firstTextBaseline, spacing: DS.space16) {
                Text("Content").font(DS.pageTitle).foregroundStyle(DS.text)
                Spacer(minLength: DS.space16)
                if tab != .ideas { scopeMenu }
                if let client = selectedClient {
                    Button { briefClient = client } label: {
                        HStack(spacing: DS.space6) {
                            Image(systemName: "doc.text")
                            if !compact { Text("Client brief") }
                        }
                    }
                        .accessibilityLabel("Client brief")
                        .buttonStyle(.borderless).help("Audience, voice and strategy for \(client.name)")
                }
            }
            HStack(spacing: DS.space16) {
                CosmoSegmentedSwitcher(
                    options: ContentWorkspaceTab.allCases,
                    label: { $0.title }, icon: { $0.cosmoIcon },
                    help: { "\($0.title) (⌘\((ContentWorkspaceTab.allCases.firstIndex(of: $0) ?? 0) + 1))" },
                    selection: $tab
                )
                .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: DS.space8)
                if tab == .pipeline {
                    Menu {
                        Button("Board", systemImage: "rectangle.split.3x1") { listLayout = false; updateLayout() }
                        Button("List", systemImage: "list.bullet") { listLayout = true; updateLayout() }
                    } label: {
                        HStack(spacing: DS.space6) {
                            Image(systemName: listLayout ? "list.bullet" : "rectangle.split.3x1")
                            if !compact { Text(listLayout ? "List" : "Board") }
                        }
                    }
                    .menuStyle(.borderlessButton).fixedSize().help("Change pipeline layout")
                    .accessibilityLabel(listLayout ? "List layout" : "Board layout")
                }
                Menu {
                    Button("New idea", systemImage: "lightbulb") { ideasModel.createIdea(clientUUID: pipelineModel.scope.clientUUID) }
                    Button("New draft", systemImage: "square.and.pencil") { pipelineModel.createDraft() }
                } label: {
                    HStack(spacing: DS.space6) {
                        Image(systemName: "plus")
                        if !compact { Text(tab == .ideas ? "New idea" : "New draft") }
                    }
                } primaryAction: { createInCurrentTab() }
                    .buttonStyle(.borderedProminent).tint(DS.accent)
                    .disabled(pipelineModel.creatingDraft)
                    .accessibilityLabel(tab == .ideas ? "New idea" : "New draft")
                    .help("Create in this scope (⌘N)")
            }
            if case .space(let id) = pipelineModel.scope {
                HStack(spacing: DS.space8) {
                    Image(systemName: "rectangle.3.group")
                    Text("From \(ThinkspaceManager.shared.thinkspaces.first { $0.id == id }?.identityLabel ?? "this Space")")
                    Button("Return to Space", systemImage: "arrow.up.right") { destination = .thinkspace(id: id) }
                        .buttonStyle(.borderless)
                }
                .font(DS.caption).foregroundStyle(DS.textSecondary)
            }
        }
        .padding(.horizontal, DS.space32).padding(.top, DS.space48).padding(.bottom, DS.space20)
    }

    private var selectedClient: PipelineClient? {
        guard let id = pipelineModel.scope.clientUUID else { return nil }
        return pipelineModel.clients.first { $0.uuid == id }
    }

    private var scopeTitle: String {
        switch pipelineModel.scope {
        case .all: return "All content"
        case .unassigned: return "Personal"
        case .client: return selectedClient?.name ?? "Client"
        case .space(let id): return ThinkspaceManager.shared.thinkspaces.first { $0.id == id }?.identityLabel ?? "Space"
        }
    }

    private var scopeMenu: some View {
        Menu {
            Button("All content", systemImage: pipelineModel.scope == .all ? "checkmark" : "rectangle.stack") { setScope(.all) }
            Button("Personal", systemImage: pipelineModel.scope == .unassigned ? "checkmark" : "person") { setScope(.unassigned) }
            if !pipelineModel.clients.isEmpty {
                Divider()
                ForEach(pipelineModel.clients) { client in
                    Button(client.name, systemImage: pipelineModel.scope.clientUUID == client.uuid ? "checkmark" : "person.crop.circle") {
                        setScope(.client(uuid: client.uuid))
                    }
                }
            }
            Divider()
            Button("Manage clients…", systemImage: "person.2") { showingClients = true }
        } label: { Label(scopeTitle, systemImage: selectedClient == nil ? "line.3.horizontal.decrease" : "person.crop.circle") }
        .menuStyle(.borderlessButton).fixedSize().font(DS.callout)
        .help("Choose the scope for ideas, pipeline and calendar")
    }

    private var clientsSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Add client", systemImage: "plus") {
                    showingClients = false
                    NotificationCenter.default.post(name: .showSettings, object: nil, userInfo: ["newClient": true])
                }
                Spacer()
                Button("Done") { showingClients = false }.keyboardShortcut(.defaultAction)
            }.padding(DS.space20)
            ClientsPage(model: clientsModel) { id in setScope(.client(uuid: id)); showingClients = false }
        }
        .frame(minWidth: 720, minHeight: 560).background(DS.bg)
    }

    private var keyboardLayer: some View {
        Group {
            Button("") { tab = .ideas }.keyboardShortcut("1", modifiers: .command)
            Button("") { tab = .pipeline }.keyboardShortcut("2", modifiers: .command)
            Button("") { tab = .calendar }.keyboardShortcut("3", modifiers: .command)
            Button("") { createInCurrentTab() }.keyboardShortcut("n", modifiers: .command)
        }.hidden().accessibilityHidden(true)
    }

    private func setScope(_ scope: PipelineScope) { pipelineModel.scope = scope; ideasModel.scope = scope }
    private func createInCurrentTab() {
        if tab == .ideas { ideasModel.createIdea(clientUUID: pipelineModel.scope.clientUUID) }
        else { pipelineModel.createDraft() }
    }
    private func route() {
        switch destination {
        case .ideas: tab = .ideas
        case .pipeline: tab = pipelineModel.view == .calendar ? .calendar : .pipeline
        case .client(let id): setScope(.client(uuid: id)); tab = .pipeline
        case .clients: showingClients = true
        default: break
        }
        ideasModel.scope = pipelineModel.scope
        updateLayout()
    }
    private func consumeBoardRequest() {
        guard let id = boardRequest else { return }
        boardRequest = nil
        setScope(id == "__unassigned__" ? .unassigned : .client(uuid: id))
        tab = .ideas
    }
    private func updateLayout() {
        if tab != .ideas { pipelineModel.view = tab == .calendar ? .calendar : (listLayout ? .list : .board) }
    }
    /// The in-page switcher writes the destination back, so the sidebar and
    /// the trail always name the lens on screen. A client hub stays a client
    /// hub — both pipeline lenses are honest under `.client`.
    private func syncDestination(to tab: ContentWorkspaceTab) {
        switch tab {
        case .ideas:
            if destination != .ideas { destination = .ideas }
        case .pipeline, .calendar:
            switch destination {
            case .pipeline, .client: break
            default: destination = .pipeline
            }
        }
    }
}

private struct ContentClientBrief: View {
    let client: PipelineClient
    @State private var store = ProfileStudioStore()
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(client.name) · Client brief").font(DS.headline)
                Spacer()
                Button(saving ? "Saving…" : "Done") {
                    saving = true
                    Task { if await store.finalizeOnExit() { dismiss() }; saving = false }
                }.keyboardShortcut(.defaultAction).disabled(saving)
            }.padding(DS.space20)
            ProfileStudioView(store: store)
        }
        .frame(minWidth: 820, minHeight: 640).background(DS.bg)
        .task { await store.load(atomUUID: client.uuid) }
        .interactiveDismissDisabled()
    }
}

private struct ContentTabVisibility: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .opacity(active ? 1 : 0)
            .allowsHitTesting(active)
            .accessibilityHidden(!active)
            .zIndex(active ? 1 : 0)
    }
}
