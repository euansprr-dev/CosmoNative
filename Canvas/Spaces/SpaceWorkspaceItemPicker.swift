import SwiftUI
import GRDB

struct SpaceWorkspaceItemPicker: View {
    enum Purpose { case members, references }
    let spaceID: String
    let target: Atom
    let purpose: Purpose
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var entireLibrary = false
    @State private var limit = 80
    @State private var results: [Atom] = []
    @State private var selection: Set<String> = []
    @State private var included: Set<String> = []
    @State private var hasMore = false
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space20) {
            VStack(alignment: .leading, spacing: DS.space6) {
                Text(purpose == .members ? "Add to \(target.title ?? "group")" : "Attach references")
                    .font(DS.title1).foregroundStyle(DS.text)
                Text(purpose == .members ? "Use the original wherever you need it." : "Keep the source beside your work. Add excerpts and notes after attaching.")
                    .font(DS.callout).foregroundStyle(DS.textSecondary)
            }
            HStack(spacing: DS.space12) {
                HStack(spacing: DS.space8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(DS.textMuted)
                    TextField("Find an image, page or source", text: $query).textFieldStyle(.plain).focused($focused)
                }.padding(DS.space12).dsGlassInput(isFocused: focused)
                Picker("Search in", selection: $entireLibrary) {
                    Text("This Space").tag(false); Text("Entire library").tag(true)
                }.labelsHidden().fixedSize().help("Choose where to look")
            }
            if let error { Text(error).font(DS.callout).foregroundStyle(DS.textSecondary) }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results, id: \.uuid) { row($0) }
                    if hasMore { Button("Load more") { limit += 80 }.padding(DS.space16) }
                    if loading { ProgressView().controlSize(.small).padding(DS.space24) }
                    else if results.isEmpty {
                        ContentUnavailableView.search(text: query)
                        if !entireLibrary { Button("Search entire library") { entireLibrary = true } }
                    }
                }
            }.frame(maxHeight: .infinity)
            HStack {
                Text("\(selection.count) selected").font(DS.caption).monospacedDigit().foregroundStyle(DS.textMuted)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(saving ? "Adding…" : purpose == .members ? "Add to group" : "Attach") { save() }
                    .buttonStyle(.borderedProminent).tint(DS.accent).keyboardShortcut(.defaultAction)
                    .disabled(selection.isEmpty || saving)
            }
        }.padding(DS.space32).frame(width: 660, height: 620).background(DS.bg)
        .task {
            focused = true
            included = Set(purpose == .members ? target.spaceComposition?.memberUUIDs ?? [] : target.spaceComposition?.references.map(\.sourceUUID) ?? [])
        }
        .task(id: "\(query)|\(entireLibrary)|\(limit)") { await search() }
        .onChange(of: query) { _, _ in limit = 80 }
        .onChange(of: entireLibrary) { _, _ in limit = 80 }
        .interactiveDismissDisabled(saving)
    }
    private func row(_ atom: Atom) -> some View {
        let alreadyIncluded = included.contains(atom.uuid)
        let selected = selection.contains(atom.uuid)
        return Button {
            if !selection.insert(atom.uuid).inserted { selection.remove(atom.uuid) }
        } label: {
            HStack(spacing: DS.space12) {
                Image(systemName: alreadyIncluded || selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(alreadyIncluded ? DS.textMuted : DS.accent)
                Image(cosmo: atom.cosmoIcon).frame(width: 24).foregroundStyle(DS.textMuted)
                VStack(alignment: .leading, spacing: DS.space4) {
                    Text(atom.title ?? "Untitled").font(DS.callout.weight(.medium)).foregroundStyle(DS.text).lineLimit(2)
                    Text(alreadyIncluded ? "Already added" : atom.spaceCompositionKind?.title ?? atom.type.displayName)
                        .font(DS.caption).foregroundStyle(DS.textMuted)
                }
                Spacer(minLength: 0)
            }.padding(DS.space12).frame(minHeight: 60).contentShape(.rect)
                .background(selected ? DS.accentSoft : .clear, in: .rect(cornerRadius: DS.radiusSmall))
        }.buttonStyle(.plain).disabled(alreadyIncluded || saving).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func search() async {
        loading = true
        do {
            if !query.isEmpty { try await Task.sleep(for: .milliseconds(180)) }
            let scopedIDs = entireLibrary ? nil : Set(try await SpaceCompositionService.load(in: spaceID).atomsByUUID.keys)
            let tokens = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
            let requestedLimit = limit
            let targetID = target.uuid
            let found = try await CosmoDatabase.shared.asyncRead { db in
                var request = Atom.filter([AtomType.note, .research, .connection, .image, .file, .extract, .lexiconEntry].map(\.rawValue).contains(Column("type")))
                    .filter(Column("is_deleted") == false).filter(Column("uuid") != targetID)
                if let scopedIDs { request = request.filter(scopedIDs.contains(Column("uuid"))) }
                for token in tokens {
                    request = request.filter(sql: "INSTR(LOWER(COALESCE(title, '') || ' ' || COALESCE(body, '')), ?) > 0", arguments: [token])
                }
                return try request.order(Column("updated_at").desc, Column("uuid")).limit(requestedLimit + 1).fetchAll(db)
            }
            try Task.checkCancellation()
            hasMore = found.count > requestedLimit; results = Array(found.prefix(requestedLimit)); error = nil; loading = false
        } catch is CancellationError { return }
        catch { self.error = error.localizedDescription; loading = false }
    }
    private func save() {
        guard !saving else { return }
        saving = true
        Task { @MainActor in
            defer { saving = false }
            do {
                if purpose == .members {
                    try await SpaceCompositionService.addMembers(selection.sorted(), to: target.uuid, in: spaceID)
                    selection.removeAll()
                } else {
                    let atoms = try await AtomRepository.shared.fetchBatch(uuids: Array(selection))
                    guard atoms.count == selection.count else { throw SpaceCompositionError.notFound }
                    let references = atoms.sorted { $0.uuid < $1.uuid }.map {
                        SpaceCompositionReference(sourceUUID: $0.uuid, sourceTitle: $0.title)
                    }
                    try await SpaceCompositionService.attachReferences(references, to: target.uuid)
                    included.formUnion(selection)
                    selection.removeAll()
                }
                await SpaceWorkspaceStore.shared.load(spaceID); dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
