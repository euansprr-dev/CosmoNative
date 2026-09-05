import SwiftUI

enum SpaceWorkspaceOrganizeAction: String, Identifiable { case move, adapt; var id: String { rawValue } }

struct SpaceWorkspaceOrganizeSheet: View {
    let spaceID: String
    let source: Atom
    let action: SpaceWorkspaceOrganizeAction
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var parentID = ""
    @State private var kind = SpaceCompositionKind.page
    @State private var saving = false
    @State private var error: String?
    private var store: SpaceWorkspaceStore { .shared }
    private var parents: [Atom] {
        guard let snapshot = store.snapshots[spaceID] else { return [] }
        return snapshot.atomsByUUID.values.filter { atom in
            guard atom.spaceCompositionKind?.isAuthored == true else { return false }
            return action == .adapt || !snapshot.breadcrumbs(to: atom.uuid).contains { $0.uuid == source.uuid }
        }.sorted { ($0.title ?? "").localizedStandardCompare($1.title ?? "") == .orderedAscending }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: DS.space20) {
            Text(action == .adapt ? "Adapt your work" : "Move page").font(DS.title1).foregroundStyle(DS.text)
            Text(action == .adapt ? "Start a new piece from “\(source.title ?? "Untitled")”. It keeps its references and a link to the original." : "Choose where “\(source.title ?? "Untitled")” belongs in this Space.")
                .font(DS.callout).foregroundStyle(DS.textSecondary)
            if action == .adapt {
                TextField("Title", text: $title).textFieldStyle(.plain).font(DS.title2).padding(DS.space12).dsGlassInput()
                Picker("Start as", selection: $kind) {
                    ForEach([SpaceCompositionKind.page, .book, .course, .guide]) { kind in Text(kind.title).tag(kind) }
                }
            }
            Picker("Inside", selection: $parentID) {
                Text("Space contents").tag("")
                ForEach(parents, id: \.uuid) { atom in Text(atom.title ?? "Untitled").tag(atom.uuid) }
            }
            if let error { Text(error).font(DS.callout).foregroundStyle(DS.textSecondary) }
            HStack {
                Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(saving ? "Saving…" : action == .adapt ? "Create adaptation" : "Move") { save() }
                    .buttonStyle(.borderedProminent).tint(DS.accent).keyboardShortcut(.defaultAction)
                    .disabled(saving || (action == .adapt && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }.padding(DS.space32).frame(width: 500).background(DS.bg).interactiveDismissDisabled(saving)
        .onAppear {
            title = (source.title ?? "Untitled") + " — adaptation"
            kind = source.spaceCompositionKind ?? .page
            if action == .move { parentID = source.spaceComposition?.parentUUID ?? "" }
        }
    }
    private func save() {
        saving = true
        Task { @MainActor in
            defer { saving = false }
            do {
                let atom: Atom
                if action == .adapt {
                    atom = try await SpaceCompositionService.adapt(source.uuid, title: title, kind: kind,
                        in: spaceID, parentUUID: parentID.isEmpty ? nil : parentID)
                } else {
                    try await SpaceCompositionService.move(source.uuid, to: parentID.isEmpty ? nil : parentID, in: spaceID)
                    atom = source
                }
                await store.load(spaceID)
                store.open(store.snapshots[spaceID]?.atomsByUUID[atom.uuid] ?? atom, in: spaceID)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
