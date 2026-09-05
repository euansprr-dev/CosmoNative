import SwiftUI

struct SpaceWorkspaceOutline: View {
    let spaceID: String
    let root: Atom
    let create: () -> Void
    @State private var collapsed: Set<String> = []
    @State private var dropTarget: String?
    private var store: SpaceWorkspaceStore { .shared }
    private var sections: [SpaceCompositionSection] {
        guard let snapshot = store.snapshots[spaceID] else { return [] }
        return snapshot.orderedSections(of: root.uuid, includedOnly: false).filter { section in
            section.atom.uuid != root.uuid && !snapshot.breadcrumbs(to: section.atom.uuid)
                .dropLast().contains(where: { collapsed.contains($0.uuid) })
        }
    }
    private var selected: Atom? {
        guard let uuid = store.location(spaceID).selectedUUID else { return nil }
        return store.snapshots[spaceID]?.atomsByUUID[uuid]
    }
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DS.space4) {
                        HStack { Text("CONTENTS"); Spacer(); Text("\(sections.count)").monospacedDigit() }
                            .font(DS.caption.weight(.medium)).tracking(1).foregroundStyle(DS.textMuted)
                            .padding(.horizontal, DS.space12).padding(.bottom, DS.space12)
                        ForEach(sections) { row($0) }
                        Button(action: create) {
                            Label("Add section", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
                        }.buttonStyle(.plain).font(DS.callout).foregroundStyle(DS.accent).padding(.horizontal, DS.space12)
                    }.padding(DS.space24)
                }.frame(maxWidth: geometry.size.width >= 980 ? 420 : .infinity)
                if geometry.size.width >= 980 {
                    Divider().overlay(DS.borderSubtle)
                    if let selected {
                        ScrollView {
                            VStack(alignment: .leading, spacing: DS.space24) {
                                SpaceWorkspaceTitle(atom: selected, spaceID: spaceID, prominent: true)
                                    .padding(.leading, BlockInteractionPolicy.gutterWidth)
                                SpacePageEditor(atom: selected).id(selected.uuid)
                            }.padding(DS.space24).frame(maxWidth: 860).frame(maxWidth: .infinity)
                        }
                    } else {
                        ContentUnavailableView("Choose a section", systemImage: "doc.text", description: Text("Shape the order on the left. Write and refine here."))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .onAppear {
            if selected == nil, let first = sections.first { store.select(first.atom.uuid, in: spaceID) }
        }
    }
    private func row(_ section: SpaceCompositionSection) -> some View {
        let atom = section.atom
        let isSelected = selected?.uuid == atom.uuid
        let included = atom.spaceComposition?.includeInExport ?? true
        let hasChildren = !(store.snapshots[spaceID]?.children(of: atom.uuid).isEmpty ?? true)
        return HStack(spacing: DS.space8) {
            Button {
                if !collapsed.insert(atom.uuid).inserted { collapsed.remove(atom.uuid) }
            } label: {
                Image(systemName: "chevron.right").rotationEffect(.degrees(collapsed.contains(atom.uuid) ? 0 : 90))
                    .font(DS.caption2).frame(width: 18, height: 36).opacity(hasChildren ? 1 : 0)
            }.buttonStyle(.plain).disabled(!hasChildren).help(collapsed.contains(atom.uuid) ? "Expand section" : "Collapse section")
            Image(systemName: atom.spaceCompositionKind?.symbol ?? "doc.text").foregroundStyle(DS.textMuted)
            VStack(alignment: .leading, spacing: DS.space4) {
                Text(atom.title ?? "Untitled").font(DS.callout.weight(.medium)).foregroundStyle(DS.text).lineLimit(2)
                if !included { Text("Not in export").font(DS.caption).foregroundStyle(DS.textMuted) }
            }
            Spacer(minLength: DS.space8)
            Menu { actions(atom) } label: { Image(systemName: "ellipsis").frame(width: 28, height: 36) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Section actions")
            Button { store.open(atom, in: spaceID) } label: {
                Image(systemName: "arrow.up.right").font(DS.caption).frame(width: 28, height: 36)
            }.buttonStyle(.plain).help("Open section")
        }
        .padding(.leading, DS.space8 + CGFloat(max(0, section.depth - 1)) * DS.space16)
        .padding(.trailing, DS.space8).padding(.vertical, DS.space8)
        .background(isSelected ? DS.accentSoft : .clear, in: .rect(cornerRadius: DS.radiusSmall))
        .overlay(alignment: .top) { if dropTarget == atom.uuid { Rectangle().fill(DS.accent).frame(height: 2) } }
        .contentShape(.rect).onTapGesture { store.select(atom.uuid, in: spaceID) }
        .onTapGesture(count: 2) { store.open(atom, in: spaceID) }
        .draggable(atom.uuid)
        .dropDestination(for: String.self) { ids, _ in
            guard ids.count == 1, let id = ids.first, id != atom.uuid,
                  store.snapshots[spaceID]?.atomsByUUID[id]?.spaceCompositionKind?.isAuthored == true else { return false }
            let parent = atom.spaceComposition?.parentUUID ?? root.uuid
            let siblings = store.snapshots[spaceID]?.children(of: parent).filter { $0.uuid != id } ?? []
            let index = siblings.firstIndex { $0.uuid == atom.uuid } ?? 0
            store.perform(in: spaceID) { try await SpaceCompositionService.move(id, to: parent, in: spaceID, at: index) }
            return true
        } isTargeted: { dropTarget = $0 ? atom.uuid : nil }
        .contextMenu { actions(atom) }
        .accessibilityElement(children: .contain).accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    @ViewBuilder private func actions(_ atom: Atom) -> some View {
        Button("Open section", systemImage: "arrow.up.right") { store.open(atom, in: spaceID) }
        Divider()
        Button("Move up", systemImage: "arrow.up") { reorder(atom, delta: -1) }.disabled(!canReorder(atom, delta: -1))
        Button("Move down", systemImage: "arrow.down") { reorder(atom, delta: 1) }.disabled(!canReorder(atom, delta: 1))
        Menu("Move into…") {
            Button("Space contents") { move(atom, to: nil) }
            ForEach(destinations(for: atom), id: \.uuid) { parent in
                Button(parent.title ?? "Untitled") { move(atom, to: parent.uuid) }
            }
        }
        Divider()
        Toggle("Include in export", isOn: Binding(get: { atom.spaceComposition?.includeInExport ?? true }, set: { included in
            store.perform(in: spaceID) { try await SpaceCompositionService.setIncludedInExport(included, for: atom.uuid) }
        }))
        Button("Adapt as new page", systemImage: "doc.on.doc") {
            store.perform(in: spaceID) {
                let copy = try await SpaceCompositionService.adapt(atom.uuid, title: (atom.title ?? "Untitled") + " — adaptation", in: spaceID)
                await store.load(spaceID); store.open(copy, in: spaceID)
            }
        }
    }
    private func destinations(for atom: Atom) -> [Atom] {
        guard let snapshot = store.snapshots[spaceID] else { return [] }
        return snapshot.atomsByUUID.values.filter { candidate in
            candidate.spaceCompositionKind?.isAuthored == true && candidate.uuid != atom.uuid &&
                !snapshot.breadcrumbs(to: candidate.uuid).contains { $0.uuid == atom.uuid }
        }.sorted { ($0.title ?? "").localizedStandardCompare($1.title ?? "") == .orderedAscending }
    }
    private func move(_ atom: Atom, to parent: String?) {
        store.perform(in: spaceID) { try await SpaceCompositionService.move(atom.uuid, to: parent, in: spaceID) }
    }
    private func siblings(_ atom: Atom) -> [Atom] {
        store.snapshots[spaceID]?.children(of: atom.spaceComposition?.parentUUID ?? root.uuid) ?? []
    }
    private func canReorder(_ atom: Atom, delta: Int) -> Bool {
        let items = siblings(atom)
        guard let index = items.firstIndex(where: { $0.uuid == atom.uuid }) else { return false }
        return items.indices.contains(index + delta)
    }
    private func reorder(_ atom: Atom, delta: Int) {
        let items = siblings(atom)
        guard let index = items.firstIndex(where: { $0.uuid == atom.uuid }), items.indices.contains(index + delta) else { return }
        var ids = items.map(\.uuid); ids.swapAt(index, index + delta)
        store.perform(in: spaceID) {
            try await SpaceCompositionService.reorderChildren(of: atom.spaceComposition?.parentUUID ?? root.uuid, in: spaceID, orderedUUIDs: ids)
        }
    }
}
