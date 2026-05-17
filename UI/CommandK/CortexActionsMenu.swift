// CosmoOS/UI/CommandK/CortexActionsMenu.swift
// The Raycast-style "Actions" menu for the action bar. Universal uuid-based
// actions (mirrors the row context menus' notification contract) so it works
// identically for Recents and search results.

import SwiftUI

struct CortexActionsMenu: View {
    let atomUUID: String?

    var body: some View {
        Menu {
            if let uuid = atomUUID {
                Button {
                    NotificationCenter.default.post(
                        name: CosmoNotification.NodeGraph.openAtomFromCommandK,
                        object: nil, userInfo: ["atomUUID": uuid]
                    )
                    NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
                } label: {
                    Label("Open in Focus Mode", systemImage: "arrow.up.left.and.arrow.down.right")
                }

                Button {
                    NotificationCenter.default.post(
                        name: CosmoNotification.NodeGraph.addToCanvas,
                        object: nil, userInfo: ["atomUUID": uuid]
                    )
                } label: {
                    Label("Add to Canvas", systemImage: "plus.rectangle.on.rectangle")
                }

                Button {
                    NotificationCenter.default.post(
                        name: CosmoNotification.NodeGraph.goToObjectFromCommandK,
                        object: nil, userInfo: ["atomUUID": uuid]
                    )
                    NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
                } label: {
                    Label("Go to Object", systemImage: "scope")
                }

                Divider()

                Button(role: .destructive) {
                    Task { try? await AtomRepository.shared.delete(uuid: uuid) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } label: {
            HStack(spacing: DS.space6) {
                Text("Actions")
                    .font(DS.caption)
                    .foregroundStyle(atomUUID == nil ? DS.textMuted : DS.textSecondary)
                CortexKeycap(symbol: "command")
                CortexKeycap(symbol: "K", isLetter: true)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(atomUUID == nil)
        .accessibilityLabel("Item actions")
    }
}

/// Small keycap glyph shared by the action bar and actions menu.
struct CortexKeycap: View {
    let symbol: String
    var isLetter: Bool = false

    var body: some View {
        Group {
            if isLetter {
                Text(symbol.uppercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .medium))
            }
        }
        .foregroundStyle(DS.inkFaded)
        .frame(width: 18, height: 18)
        .background(DS.vellumDeep, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(DS.sepiaBorder, lineWidth: 0.5)
        )
    }
}
