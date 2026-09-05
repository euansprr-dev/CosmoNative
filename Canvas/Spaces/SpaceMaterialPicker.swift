import SwiftUI
import GRDB

/// Existing material is referenced in place; adding it never duplicates the atom.
struct SpaceMaterialPicker: View {
    let spaceID: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Atom] = []
    @State private var members: Set<String> = []
    @State private var selection: Set<String> = []
    @State private var saving = false
    @State private var loaded = false
    @State private var error: String?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space20) {
            Text("Add material").font(DS.pageTitle).foregroundStyle(DS.text)
            Text("Bring existing sources and notes into this Space. The original stays available everywhere it is used.")
                .font(DS.callout).foregroundStyle(DS.textSecondary)
            TextField("Search your sources and notes", text: $query)
                .textFieldStyle(.roundedBorder).focused($searchFocused)
            if let error { Text(error).font(DS.callout).foregroundStyle(DS.textSecondary) }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results, id: \.uuid) { atom in materialRow(atom) }
                    if loaded && results.isEmpty {
                        Text("No matching materials. Try another search, or import a file from the Space’s Add menu.")
                            .font(DS.callout).foregroundStyle(DS.textMuted).padding(.vertical, DS.space24)
                    }
                }
            }.frame(minHeight: 280)
            HStack {
                Text("\(selection.count) selected").font(DS.caption).foregroundStyle(DS.textMuted).monospacedDigit()
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(saving ? "Adding…" : "Add to Space") { addSelection() }
                    .buttonStyle(.borderedProminent).tint(DS.accent).keyboardShortcut(.defaultAction)
                    .disabled(selection.isEmpty || saving)
            }
        }
        .padding(DS.space32).frame(width: 600, height: 580).background(DS.bg)
        .task { searchFocused = true; members = (try? await SpaceMembershipService.memberUUIDs(in: spaceID)) ?? [] }
        .task(id: query) { await search() }
        .interactiveDismissDisabled(saving)
    }

    private func materialRow(_ atom: Atom) -> some View {
        let included = members.contains(atom.uuid)
        return Button {
            if selection.contains(atom.uuid) { selection.remove(atom.uuid) } else { selection.insert(atom.uuid) }
        } label: {
            HStack(spacing: DS.space12) {
                Image(systemName: included || selection.contains(atom.uuid) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(included ? DS.textMuted : DS.accent)
                Image(systemName: atom.type.iconName).foregroundStyle(DS.textMuted).frame(width: 20)
                VStack(alignment: .leading, spacing: DS.space4) {
                    Text(atom.title ?? "Untitled").font(DS.callout).foregroundStyle(DS.text).lineLimit(2)
                    Text(included ? "Already in this Space" : atom.type.displayName).font(DS.caption).foregroundStyle(DS.textMuted)
                }
                Spacer()
            }.padding(DS.space12).frame(minHeight: 56).contentShape(.rect)
        }
        .buttonStyle(.borderless).disabled(included || saving)
        .help(included ? "Already in this Space" : "Select \(atom.title ?? "material")")
        .accessibilityAddTraits(selection.contains(atom.uuid) ? .isSelected : [])
    }

    private func search() async {
        let requested = query
        if !requested.isEmpty {
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
        }
        do {
            let tokens = requested.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
            let found = try await CosmoDatabase.shared.asyncRead { db in
                var request = Atom.filter([AtomType.note, .research, .connection, .image, .file, .extract, .lexiconEntry].map(\.rawValue).contains(Column("type")))
                    .filter(Column("is_deleted") == false)
                for token in tokens {
                    // INSTR treats wildcard characters literally and binds user input.
                    request = request.filter(sql: "INSTR(LOWER(COALESCE(title, '') || ' ' || COALESCE(body, '')), ?) > 0", arguments: [token])
                }
                return try request.order(Column("updated_at").desc, Column("uuid")).limit(100).fetchAll(db)
            }
            guard !Task.isCancelled, requested == query else { return }
            results = found; loaded = true; error = nil
        } catch { self.error = "Couldn't search materials. Try again." }
    }

    private func addSelection() {
        let ids = selection
        saving = true
        Task {
            defer { saving = false }
            do {
                let atoms = try await AtomRepository.shared.fetchBatch(uuids: Array(ids))
                for atom in atoms {
                    try await SpaceMembershipService.add(atom, to: spaceID)
                    CosmoUndoManager.shared.register(InlineUndoAction(
                        actionDescription: "Add material to Space",
                        undo: { try? await SpaceMembershipService.remove(atom.uuid, from: spaceID) },
                        redo: { _ = try? await SpaceMembershipService.add(atom, to: spaceID) }
                    ))
                    selection.remove(atom.uuid); members.insert(atom.uuid)
                }
                dismiss()
            } catch { self.error = "Some materials couldn't be added. Retry the remaining selection." }
        }
    }
}
