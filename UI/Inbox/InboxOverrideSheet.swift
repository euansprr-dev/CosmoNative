import SwiftUI

/// One destination, one visible effect, one commit. Selecting a row previews it.
struct InboxOverrideSheet: View {
    let item: InboxItem
    @Bindable var viewModel: InboxViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var destinations: [InboxFilingDestination] = []
    @State private var selected: InboxFilingDestination?
    @State private var action: InboxFilingAction = .page
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var error: String?
    @FocusState private var searchFocused: Bool

    private var results: [InboxFilingDestination] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return needle.isEmpty ? destinations : destinations.filter { $0.path.localizedCaseInsensitiveContains(needle) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            searchField
            destinationList
            consequence
            footer
        }
        .frame(width: 540, height: 650)
        .background(DS.bg)
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DS.space16) {
            VStack(alignment: .leading, spacing: DS.space4) {
                Text("Choose destination").font(DS.title2).foregroundStyle(DS.text)
                Text(item.title ?? String(item.rawText.prefix(80)))
                    .font(DS.subheadline).foregroundStyle(DS.textSecondary).lineLimit(2)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).foregroundStyle(DS.textSecondary)
            .help("Close destination picker (Esc)").accessibilityLabel("Close destination picker")
            .keyboardShortcut(.cancelAction)
        }
        .padding(DS.space24)
    }

    private var searchField: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "magnifyingglass").foregroundStyle(DS.textMuted)
            TextField("Search Spaces, Groups, Pages, clients…", text: $query)
                .textFieldStyle(.plain).font(DS.body).focused($searchFocused)
                .accessibilityLabel("Search destinations")
        }
        .padding(DS.space12).dsGlassInput(cornerRadius: 14)
        .padding(.horizontal, DS.space24)
    }

    private var destinationList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if isLoading {
                    ForEach(0..<5, id: \.self) { _ in
                        HStack { RoundedRectangle(cornerRadius: 4).fill(DS.surface).frame(width: 220, height: 16); Spacer() }
                            .padding(DS.space16).accessibilityHidden(true)
                    }
                } else if results.isEmpty {
                    Text("No destinations match. Try a Page, Group, Space, or client name.")
                        .font(DS.body).foregroundStyle(DS.textSecondary).padding(DS.space24)
                } else {
                    ForEach(results) { destination in
                        InboxDestinationRow(destination: destination, isSelected: selected?.id == destination.id) {
                            selected = destination
                            action = destination.defaultAction
                            error = nil
                        }
                    }
                }
            }
        }
        .padding(.horizontal, DS.space16).padding(.vertical, DS.space12)
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    @ViewBuilder private var consequence: some View {
        if let selected {
            VStack(alignment: .leading, spacing: DS.space8) {
                Text(selected.path).font(DS.headline).foregroundStyle(DS.text).lineLimit(2)
                if selected.kind == .page {
                    Picker("Save as", selection: $action) {
                        Text("Reference").tag(InboxFilingAction.reference)
                        Text("New child Page").tag(InboxFilingAction.childPage)
                    }
                    .pickerStyle(.segmented)
                }
                Text(action.consequence(in: selected)).font(DS.subheadline).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.space16).frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.surface).clipShape(.rect(cornerRadius: 14))
            .padding(.horizontal, DS.space24)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            if let error { Text(error).font(DS.subheadline).foregroundStyle(DS.textSecondary) }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.plain).foregroundStyle(DS.textSecondary)
                Spacer()
                Button(isSaving ? "Saving…" : action.title) { Task { await save() } }
                    .buttonStyle(.borderedProminent).tint(DS.accent)
                    .disabled(selected == nil || isSaving).keyboardShortcut(.defaultAction)
                    .help("Save to the selected destination (Return)")
            }
        }
        .padding(DS.space24)
    }

    private func load() async {
        do {
            destinations = try await InboxPlacementService.shared.destinations()
            selected = destinations.first
            action = selected?.defaultAction ?? .page
            isLoading = false
            searchFocused = true
        } catch {
            isLoading = false
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        guard let selected, !isSaving else { return }
        isSaving = true
        error = await viewModel.fileCapture(item, destination: selected, action: action)
        isSaving = false
        if error == nil { dismiss() }
    }
}

private struct InboxDestinationRow: View {
    let destination: InboxFilingDestination
    let isSelected: Bool
    let select: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: DS.space12) {
                Image(systemName: destination.symbol).frame(width: 24).foregroundStyle(isSelected ? DS.accent : DS.textSecondary)
                VStack(alignment: .leading, spacing: DS.space4) {
                    Text(destination.name).font(DS.body.weight(.medium)).foregroundStyle(DS.text)
                    Text(destination.path).font(DS.caption).foregroundStyle(DS.textSecondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "checkmark").foregroundStyle(DS.accent).opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, DS.space12).padding(.vertical, DS.space12)
            .frame(minHeight: 52).frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? DS.accentSoft : isHovered ? DS.surface : Color.clear)
            .clipShape(.rect(cornerRadius: 12)).contentShape(.rect)
        }
        .buttonStyle(.plain).onHover { isHovered = $0 }
        .help("Choose \(destination.path)")
        .accessibilityElement(children: .combine).accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
