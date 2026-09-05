import SwiftUI

extension SpaceCompositionKind: Identifiable { var id: String { rawValue } }

struct SpaceContentsNavigator: View {
    let spaceID: String
    let name: String
    var onBack: () -> Void
    @State private var expanded: Set<String> = []
    @State private var creating: SpaceCompositionKind?
    private var store: SpaceWorkspaceStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            SidebarRow(title: "All spaces", mark: .symbol("chevron.left"), prominence: .ghost,
                       help: "Browse all spaces", action: onBack)
            SidebarSection(title: name) {
                destination(.canvas)
                ForEach(rows) { row in
                    SpaceContentsRow(atom: row.atom, depth: row.depth, expanded: expanded.contains(row.atom.uuid),
                                     hasChildren: !children(row.atom).isEmpty,
                                     selected: store.location(spaceID).itemUUID == row.atom.uuid,
                                     toggle: { if !expanded.insert(row.atom.uuid).inserted { expanded.remove(row.atom.uuid) } },
                                     open: { store.open(row.atom, in: spaceID) })
                }
                Menu {
                    SpaceCreationMenuItems { creating = $0 }
                } label: { Label("Add to Space", systemImage: "plus").font(DS.callout).foregroundStyle(DS.textSecondary) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(minHeight: 36)
                    .padding(.horizontal, DS.space8).help("Create a page, group, book or course")
            }
            SidebarSection(title: "Explore") { destination(.library); destination(.deepDive) }
            if let error = store.errors[spaceID] {
                VStack(alignment: .leading, spacing: DS.space8) {
                    Text(error).font(DS.caption).foregroundStyle(DS.textSecondary)
                    Button("Retry") { Task { await store.load(spaceID) } }.buttonStyle(.plain).foregroundStyle(DS.accent)
                }.padding(DS.space8)
            }
        }
        .task(id: spaceID) { await store.load(spaceID); revealSelection() }
        .onChange(of: store.location(spaceID).itemUUID) { _, _ in revealSelection() }
        .sheet(item: $creating) { kind in SpaceWorkspaceCreateSheet(spaceID: spaceID, kind: kind) }
    }
    private func destination(_ view: SpaceView) -> some View {
        SidebarRow(title: view.title, mark: .symbol(view.icon),
                   isActive: !store.isPresenting(in: spaceID) && SpaceViewStore.shared.activeView(for: spaceID) == view,
                   help: "Open \(view.title.lowercased())") { store.showRoot(view, in: spaceID) }
    }
    private func children(_ atom: Atom) -> [Atom] {
        store.items(in: atom, spaceID: spaceID).filter { $0.spaceCompositionKind != nil }
    }
    private var rows: [SpaceContentsEntry] {
        guard let snapshot = store.snapshots[spaceID] else { return [] }
        var output: [SpaceContentsEntry] = []
        func append(_ atom: Atom, depth: Int, path: Set<String>, prefix: String) {
            guard !path.contains(atom.uuid) else { return }
            let id = prefix + atom.uuid
            output.append(.init(id: id, atom: atom, depth: depth))
            if expanded.contains(atom.uuid) {
                for child in children(atom) { append(child, depth: depth + 1, path: path.union([atom.uuid]), prefix: id + "/") }
            }
        }
        for root in snapshot.roots { append(root, depth: 0, path: [], prefix: "") }
        return output
    }
    private func revealSelection() {
        guard let id = store.location(spaceID).itemUUID, let snapshot = store.snapshots[spaceID] else { return }
        expanded.formUnion(snapshot.breadcrumbs(to: id).map(\.uuid))
    }
}

private struct SpaceContentsEntry: Identifiable { let id: String; let atom: Atom; let depth: Int }

private struct SpaceContentsRow: View {
    let atom: Atom
    let depth: Int
    let expanded: Bool
    let hasChildren: Bool
    let selected: Bool
    let toggle: () -> Void
    let open: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: DS.space4) {
            Button(action: toggle) {
                Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0))
                    .font(DS.caption2).foregroundStyle(DS.textMuted).frame(width: 18, height: 30)
                    .opacity(hasChildren ? 1 : 0)
            }.buttonStyle(.plain).disabled(!hasChildren).help(expanded ? "Collapse" : "Expand")
            Button(action: open) {
                HStack(spacing: DS.space8) {
                    Image(systemName: atom.spaceCompositionKind?.symbol ?? "doc.text").frame(width: 18)
                    Text(atom.title ?? "Untitled").lineLimit(1)
                    Spacer(minLength: 0)
                }.font(DS.callout).foregroundStyle(selected ? DS.accent : DS.textSecondary)
                    .frame(minHeight: 32).contentShape(.rect)
            }.buttonStyle(.plain).help("Open \(atom.title ?? "page")")
        }
        .padding(.leading, CGFloat(min(depth, 6)) * DS.space12)
        .padding(.trailing, DS.space8)
        .background(selected ? DS.accentSoft : hovered ? DS.glassSectionFill : .clear, in: .rect(cornerRadius: 8))
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: selected)
        .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: expanded)
        .accessibilityElement(children: .contain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SpaceCreationMenuItems: View {
    let create: (SpaceCompositionKind) -> Void
    var body: some View {
        Button("New page", systemImage: "square.and.pencil") { create(.page) }
        Button("New group", systemImage: "folder.badge.plus") { create(.group) }
        Divider()
        Menu("Start from…") {
            Button("Book", systemImage: "book.closed") { create(.book) }
            Button("Course", systemImage: "play.rectangle.on.rectangle") { create(.course) }
            Button("Guide", systemImage: "doc.richtext") { create(.guide) }
        }
    }
}

struct SpaceWorkspaceCreateSheet: View {
    let spaceID: String
    let kind: SpaceCompositionKind
    var parent: Atom? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var error: String?
    @State private var saving = false
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: DS.space20) {
            Text("New \(kind.title.lowercased())").font(DS.title1).foregroundStyle(DS.text)
            TextField(kind == .group ? "What belongs together?" : "Give it a title", text: $title)
                .textFieldStyle(.plain).font(DS.title2).padding(DS.space12).dsGlassInput(isFocused: focused)
                .focused($focused).onSubmit { create() }
            Text(kind == .group ? "Gather images, notes and references. Arrange them in the way that works for you." :
                    kind == .page ? "Start with a thought. Add structure as it grows." : "An editable starting point. Every section can be renamed, moved or removed.")
                .font(DS.callout).foregroundStyle(DS.textSecondary)
            if let error { Text(error).font(DS.callout).foregroundStyle(DS.textSecondary) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(saving ? "Creating…" : "Create") { create() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(DS.accent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
            }
        }.padding(DS.space32).frame(width: 440).background(DS.bg)
            .onAppear { focused = true }.interactiveDismissDisabled(saving)
    }
    private func create() {
        guard !saving, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        saving = true
        Task { @MainActor in
            defer { saving = false }
            do {
                let atom: Atom
                if kind == .book || kind == .course || kind == .guide {
                    atom = try await SpaceCompositionService.createStarter(kind, title: title, in: spaceID,
                        groupUUID: parent?.spaceCompositionKind == .group ? parent?.uuid : nil)
                } else {
                    atom = try await SpaceCompositionService.create(kind: kind, title: title, in: spaceID,
                        parentUUID: parent?.spaceCompositionKind?.isAuthored == true && kind.isAuthored ? parent?.uuid : nil,
                        groupUUID: parent?.spaceCompositionKind == .group ? parent?.uuid : nil)
                }
                await SpaceWorkspaceStore.shared.load(spaceID)
                if parent == nil && SpaceViewStore.shared.activeView(for: spaceID) == .canvas && !SpaceWorkspaceStore.shared.isPresenting(in: spaceID) {
                    NotificationCenter.default.post(name: Notification.Name("com.cosmo.space.placeCreatedItem"), object: nil,
                        userInfo: ["spaceID": spaceID, "atomUUID": atom.uuid])
                }
                SpaceWorkspaceStore.shared.open(atom, in: spaceID)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
