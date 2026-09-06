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
        .onChange(of: listLayout) { _, _ in updateLayout() }
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
                             displayView: listLayout ? .list : .board, isActive: tab == .pipeline,
                             layout: $listLayout)
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

    /// The masthead: a bare title (the masthead law), the scope beside the one
    /// hero affordance, and the destination switcher on its own line. It clears
    /// the app's floating chrome band (sidebar toggle + trail) with real air —
    /// the title used to sit 2pt under the islands.
    private var header: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            HStack(alignment: .center, spacing: DS.space10) {
                Text("Content").font(DS.pageTitle).foregroundStyle(DS.text)
                Spacer(minLength: DS.space16)
                if tab != .ideas { scopeMenu }
                if let client = selectedClient { briefButton(client) }
                primaryButton
            }
            HStack(alignment: .center, spacing: DS.space16) {
                CosmoSegmentedSwitcher(
                    options: ContentWorkspaceTab.allCases,
                    label: { $0.title }, icon: { $0.cosmoIcon },
                    help: { "\($0.title) (⌘\((ContentWorkspaceTab.allCases.firstIndex(of: $0) ?? 0) + 1))" },
                    selection: $tab
                )
                .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: DS.space8)
                if case .space(let id) = pipelineModel.scope { spaceOrigin(id) }
            }
        }
        .padding(.horizontal, DS.space32)
        .padding(.top, SpaceChromeMetrics.contentTopInset + DS.space16)
        .padding(.bottom, DS.space20)
    }

    /// One accent capsule — never a split button. ⌘N and the active tab decide
    /// what "new" means; the label says which.
    private var primaryButton: some View {
        Button(action: createInCurrentTab) {
            HStack(spacing: DS.space6) {
                Image(systemName: "plus").font(DS.callout.weight(.semibold))
                if !compact { Text(tab == .ideas ? "New idea" : "New draft") }
            }
        }
        .buttonStyle(ContentPrimaryButtonStyle())
        .disabled(pipelineModel.creatingDraft)
        .help(tab == .ideas ? "New idea (⌘N)" : "New draft (⌘N)")
        .accessibilityLabel(tab == .ideas ? "New idea" : "New draft")
    }

    private func briefButton(_ client: PipelineClient) -> some View {
        Button { briefClient = client } label: {
            HStack(spacing: DS.space6) {
                Image(systemName: "doc.text").font(DS.caption.weight(.medium))
                if !compact { Text("Client brief").font(DS.callout.weight(.medium)) }
            }
            .modifier(ContentWorkspaceChip())
        }
        .buttonStyle(.plain)
        .help("Audience, voice and strategy for \(client.name)")
        .accessibilityLabel("Client brief")
    }

    private func spaceOrigin(_ id: String) -> some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "rectangle.3.group")
            Text("From \(ThinkspaceManager.shared.thinkspaces.first { $0.id == id }?.identityLabel ?? "this Space")")
            Button("Return to Space", systemImage: "arrow.up.right") { destination = .thinkspace(id: id) }
                .buttonStyle(.borderless)
        }
        .font(DS.caption).foregroundStyle(DS.textSecondary)
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

    /// Whose work is on the table — a quiet chip beside the hero, in the
    /// filter-chip grammar. A client wears its own color as the mark.
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
        } label: {
            HStack(spacing: DS.space6) {
                if let client = selectedClient {
                    Circle().fill(DS.clientColor(for: client.uuid)).frame(width: 7, height: 7)
                } else {
                    Image(systemName: pipelineModel.scope == .unassigned ? "person" : "line.3.horizontal.decrease")
                        .font(DS.caption.weight(.medium))
                }
                Text(scopeTitle).font(DS.callout.weight(.medium)).lineLimit(1)
                Image(systemName: "chevron.down").font(DS.caption2.weight(.semibold))
            }
            .modifier(ContentWorkspaceChip())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Choose the scope for ideas, pipeline and calendar")
        .accessibilityLabel("Scope: \(scopeTitle)")
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

/// The workspace's one hero affordance: an accent capsule that lights on hover
/// and compresses on press. (`ButtonStyleConfiguration` spelled out — the repo's
/// top-level `Configuration` type shadows the ButtonStyle alias.)
private struct ContentPrimaryButtonStyle: ButtonStyle {
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(DS.callout.weight(.semibold))
            .foregroundStyle(DS.textOnAccent)
            .padding(.horizontal, DS.space16)
            .frame(height: 34)
            .background(hovered ? DS.accentHover : DS.accent, in: .capsule)
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : ProMotionSprings.hover, value: hovered)
            .animation(reduceMotion ? nil : ProMotionSprings.press, value: configuration.isPressed)
            .contentShape(.capsule)
            .onHover { hovered = $0 }
    }
}

/// Secondary masthead chips (scope, client brief): the filter-chip grammar —
/// quiet input fill, hairline, ink on hover.
private struct ContentWorkspaceChip: ViewModifier {
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .foregroundStyle(hovered ? DS.text : DS.textSecondary)
            .padding(.horizontal, DS.space12)
            .frame(height: 32)
            .background(hovered ? DS.glassInputFillFocused : DS.glassInputFill, in: .capsule)
            .overlay(Capsule().strokeBorder(DS.glassBorder, lineWidth: 0.5))
            .contentShape(.capsule)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : ProMotionSprings.hover, value: hovered)
    }
}
