import SwiftUI

/// Page → Content is an explicit choice of intent and client, with one live
/// source link. Rich writing remains in the page where the user developed it.
struct PageContentIdeaSheet: View {
    let source: Atom
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var angle = ""
    @State private var clientUUID = ""
    @State private var clients: [Atom] = []
    @State private var loadingClients = true
    @State private var saving = false
    @State private var error: String?
    @State private var operationID = UUID().uuidString
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space24) {
            VStack(alignment: .leading, spacing: DS.space8) {
                Text("Create content idea").font(DS.title1).foregroundStyle(DS.text)
                Text("Start an idea in Content, with this page linked as a source.")
                    .font(DS.callout).foregroundStyle(DS.textSecondary)
            }
            Label(source.title ?? "Untitled page", systemImage: "doc.text")
                .font(DS.callout).foregroundStyle(DS.textSecondary).lineLimit(2)
            VStack(alignment: .leading, spacing: DS.space16) {
                TextField("Idea title", text: $title).font(DS.title2).textFieldStyle(.plain)
                    .padding(DS.space12).dsGlassInput(isFocused: titleFocused).focused($titleFocused)
                TextField("The angle you want to explore (optional)", text: $angle, axis: .vertical)
                    .lineLimit(3...6).textFieldStyle(.plain).padding(DS.space12).dsGlassInput()
                Picker("For", selection: $clientUUID) {
                    Text("Personal content").tag("")
                    ForEach(clients, id: \.uuid) { client in Text(client.title ?? "Untitled client").tag(client.uuid) }
                }.disabled(loadingClients || saving)
            }
            if let error { Text(error).font(DS.callout).foregroundStyle(DS.textSecondary).fixedSize(horizontal: false, vertical: true) }
            HStack {
                if loadingClients { ProgressView().controlSize(.small).accessibilityLabel("Loading clients") }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
                Button(saving ? "Creating…" : "Create idea") { create() }
                    .buttonStyle(.borderedProminent).tint(DS.accent).keyboardShortcut(.defaultAction)
                    .disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(DS.space32).frame(width: 520).background(DS.bg)
            .interactiveDismissDisabled(saving)
            .task {
                title = source.title ?? ""
                titleFocused = true
                defer { loadingClients = false }
                do { clients = try await AtomRepository.shared.fetchAll(type: .clientProfile).sorted { ($0.title ?? "").localizedStandardCompare($1.title ?? "") == .orderedAscending } }
                catch { self.error = "Clients couldn't be loaded. You can still create a personal idea." }
            }
    }

    private func create() {
        guard !saving else { return }
        saving = true; error = nil
        Task { @MainActor in
            defer { saving = false }
            do {
                let idea = try await PageContentHandoffService.create(sourceUUID: source.uuid, title: title,
                    angle: angle, clientUUID: clientUUID.isEmpty ? nil : clientUUID, operationID: operationID)
                dismiss()
                NotificationCenter.default.post(name: CosmoNotification.Navigation.openBlockInFocusMode,
                    object: nil, userInfo: ["atomUUID": idea.uuid])
            } catch { self.error = error.localizedDescription }
        }
    }
}
