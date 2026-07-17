// CosmoOS/Navigation/Browser/CosmoBrowserSheets.swift
// Sheets presented by the browser pane.

import SwiftUI

struct CosmoBrowserRenamePinSheet: View {
    let pin: CosmoBrowserPinnedSite
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var draftName: String
    @FocusState private var isNameFocused: Bool

    init(
        pin: CosmoBrowserPinnedSite,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String) -> Void
    ) {
        self.pin = pin
        self.onCancel = onCancel
        self.onSave = onSave
        _draftName = State(initialValue: pin.displayName)
    }

    private var trimmedName: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                CommandKFavicon(host: pin.host, size: 20) {
                    CosmoIdentityChip(systemName: "globe", tint: DS.textMuted, size: 20)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Rename Favorite")
                        .font(DS.callout)
                        .foregroundStyle(DS.text)
                    Text(pin.host)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(1)
                }
            }

            TextField("Favorite name", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .onSubmit(save)

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 360)
        .background(DS.bg)
        .onAppear {
            isNameFocused = true
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        onSave(trimmedName)
    }
}
