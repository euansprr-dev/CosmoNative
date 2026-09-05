import SwiftUI

struct SwipeLabLaunchButton: View {
    let scope: SwipeLabScope
    var clientID: String? = nil
    var title = "Open in Swipe Lab"
    @State private var isOpening = false
    @State private var error: String?
    var body: some View {
        Button {
            guard !isOpening else { return }
            isOpening = true
            Task {
                do { try await SwipeLabNavigation.open(scope: scope, clientID: clientID) }
                catch { self.error = error.localizedDescription }
                isOpening = false
            }
        } label: { Label(title, systemImage: "books.vertical") }
        .disabled(isOpening)
        .alert("Couldn’t open Swipe Lab", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

@MainActor enum SwipeLabNavigation {
    static func open(scope: SwipeLabScope, clientID: String? = nil, fresh: Bool = false) async throws {
        let atom = try await SwipeLabStore.shared.open(scope: scope, targetClientID: clientID, fresh: fresh)
        guard let id = atom.id else { throw SwipeLabError.sessionMissing }
        NotificationCenter.default.post(name: .enterFocusMode, object: nil, userInfo: ["type": EntityType.inquirySession, "id": id])
    }
}

struct SwipeLabLibraryMenu: View {
    @Bindable var viewModel: SwipeLibraryViewModel
    @State private var showPicker = false
    @State private var error: String?

    private var scope: SwipeLabScope {
        if case .board(let id) = viewModel.scope, let board = SwipeBoardStore.shared.board(withID: id) { return .board(board) }
        return .init(kind: .library, title: "All swipes")
    }

    var body: some View {
        Menu {
            SwipeLabLaunchButton(scope: scope, title: scope.kind == .board ? "Study this board" : "Study all swipes")
            if !viewModel.visibleItems.isEmpty {
                SwipeLabLaunchButton(scope: .selection(viewModel.visibleItems.map(\.atomUUID), title: "Filtered swipes"), title: "Study shown posts (\(viewModel.visibleItems.count))")
            }
            Button("Choose posts to study…") { showPicker = true }
        } label: {
            Label("Lab", systemImage: "books.vertical").font(DS.subheadline.weight(.medium))
                .padding(.horizontal, DS.space12).frame(height: 32)
                .background(DS.glassInputFill, in: Capsule())
                .overlay(Capsule().strokeBorder(DS.glassBorder, lineWidth: 0.5))
        }.menuStyle(.button).buttonStyle(.plain).fixedSize().help("Deep study in Swipe Lab")
        .sheet(isPresented: $showPicker) {
            SwipeLabScopePicker(title: "Build your study", actionTitle: "Open Swipe Lab") { scope in
                Task {
                    do { try await SwipeLabNavigation.open(scope: scope); showPicker = false }
                    catch { self.error = error.localizedDescription }
                }
            }
        }
        .alert("Couldn’t open Swipe Lab", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

/// Used for both the study population and its explicit comparison population.
struct SwipeLabScopePicker: View {
    let title: String
    let actionTitle: String
    let onSelect: (SwipeLabScope) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind = "board"
    @State private var boards: [SwipeBoard] = []
    @State private var swipes: [Atom] = []
    @State private var clients: [Atom] = []
    @State private var selection = Set<String>()
    @State private var boardID = ""
    @State private var clientID = ""
    @State private var query = ""
    @State private var studyTitle = "Selected swipes"
    @State private var isLoading = true
    @State private var error: String?

    private var filtered: [Atom] { query.isEmpty ? swipes : swipes.filter { ($0.title ?? "").localizedCaseInsensitiveContains(query) } }
    private var resolved: SwipeLabScope? {
        switch kind {
        case "library": return .init(kind: .library, title: "All swipes")
        case "selection": return selection.isEmpty ? nil : .selection(Array(selection), title: studyTitle.isEmpty ? "Selected swipes" : studyTitle)
        case "client": return clients.first { $0.uuid == clientID }.map { .client($0.uuid, name: $0.title ?? "Client") }
        default: return boards.first { $0.uuid == boardID }.map { .board($0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            SwipeLabSheetHeader(title: title, detail: "Choose exactly which posts count as evidence.")
                .padding(-DS.space24)
            Picker("Source population", selection: $kind) {
                Text("Board").tag("board")
                Text("Selection").tag("selection")
                Text("Client posts").tag("client")
                Text("All swipes").tag("library")
            }.pickerStyle(.segmented)
            if isLoading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { populationContent }
            if let error { Text(error).font(DS.subheadline).foregroundStyle(DS.orange) }
            Spacer(minLength: 0)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(actionTitle) { if let resolved { onSelect(resolved) } }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(resolved == nil || isLoading)
            }
        }
        .padding(DS.space24).frame(width: 560, height: 570).background(DS.bg).tint(DS.accent)
        .task {
            do {
                await SwipeBoardStore.shared.loadIfNeeded()
                boards = SwipeBoardStore.shared.boards.filter { !$0.isArchived }
                swipes = try await AtomRepository.shared.fetchSwipeFileAtoms()
                clients = try await AtomRepository.shared.fetchAll(type: .clientProfile)
                boardID = boards.first?.uuid ?? ""
                clientID = clients.first?.uuid ?? ""
                if boards.isEmpty { kind = "selection" }
            } catch { self.error = error.localizedDescription }
            isLoading = false
        }
    }

    @ViewBuilder private var populationContent: some View {
        switch kind {
        case "selection":
            TextField("Study title", text: $studyTitle).textFieldStyle(.roundedBorder)
            TextField("Find a post", text: $query).textFieldStyle(.roundedBorder)
            HStack {
                Text("\(selection.count) selected").font(DS.subheadline).foregroundStyle(DS.textSecondary)
                Spacer()
                Button("Select shown") { selection.formUnion(filtered.map(\.uuid)) }
                Button("Clear") { selection.removeAll() }
            }.font(DS.subheadline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.space12) {
                    ForEach(filtered) { atom in
                        Toggle(atom.title ?? "Untitled swipe", isOn: Binding(get: { selection.contains(atom.uuid) }, set: { selected in
                            if selected { selection.insert(atom.uuid) } else { selection.remove(atom.uuid) }
                        })).toggleStyle(.checkbox).font(DS.body)
                    }
                }.padding(.vertical, DS.space8)
            }
        case "client":
            Picker("Client", selection: $clientID) { ForEach(clients) { Text($0.title ?? "Untitled client").tag($0.uuid) } }
            Text("Studies this client’s published content. To study saved inspiration for a client, choose its board here and set “Learn for” inside the Lab.")
                .font(DS.body).foregroundStyle(DS.textSecondary)
        case "library":
            Text("\(swipes.count) saved posts").font(DS.headline)
            Text("Large collections are read in batches. Progress shows which originals were inspected, and completed readings are reused when you retry the same question.")
                .font(DS.body).foregroundStyle(DS.textSecondary)
        default:
            Picker("Board", selection: $boardID) { ForEach(boards, id: \.uuid) { Text($0.name).tag($0.uuid) } }
            Text("The study remembers this board and its current sources. New board members become available when you update the study.")
                .font(DS.body).foregroundStyle(DS.textSecondary)
        }
    }
}
