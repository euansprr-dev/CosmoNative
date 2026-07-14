// CosmoOS/UI/CommandK/IdeasTab.swift
// Slimmed July 2026 (the Ideas surface demotion): Command-K stopped being the
// place you BROWSE ideas — the rail shows top hits plus an "Open Ideas board"
// jump row, and the full board lives on the Ideas destination. What remains
// here is the shared vocabulary other surfaces still speak: the search
// matcher (rail + search pipeline + tests) and the client-column card the
// canvas ideaBoard block renders (`IdeaBoardBlockView`).

import SwiftUI
import UniformTypeIdentifiers

// MARK: - IdeaClientSection

struct IdeaClientSection: Identifiable {
    let id: String
    let clientName: String
    let clientUUID: String?   // nil for "Unassigned"
    let color: Color
    let items: [IdeaGalleryItem]
}

// MARK: - IdeasTab (search matcher namespace)

enum IdeasTab {
    nonisolated static func matchesSearch(_ item: IdeaGalleryItem, query: String) -> Bool {
        CommandKSearchMatcher.matches(query, inAny: [item.title, item.body, item.clientName] + item.tags.map(Optional.some))
    }
}

// MARK: - Board Card (Compact)

struct IdeaBoardCard: View {

    let item: IdeaGalleryItem
    let columnColor: Color
    var viewModel: CommandKViewModel?
    let hasAppeared: Bool
    let appearDelay: Double

    @State private var isHovered = false
    @State private var showDeleteAlert = false

    private var isSelected: Bool {
        viewModel?.selectedUUIDs.contains(item.atomUUID) ?? false
    }

    var body: some View {
        HStack(spacing: 10) {
            // Format icon
            formatIcon

            // Content
            VStack(alignment: .leading, spacing: 2) {
                if let format = item.contentFormat {
                    Text(format.displayName)
                        .font(DS.smallCaps)
                        .foregroundStyle(columnColor.opacity(0.7))
                }

                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.text)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            // Status dot
            Circle()
                .fill(item.status.color)
                .frame(width: 7, height: 7)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    isSelected ? columnColor.opacity(0.12) :
                    isHovered ? columnColor.opacity(0.06) :
                    DS.surfaceElevated
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isSelected ? columnColor.opacity(0.5) :
                    isHovered ? columnColor.opacity(0.25) :
                    DS.borderSubtle,
                    lineWidth: 1
                )
        )
        .shadow(
            color: isHovered ? columnColor.opacity(0.1) : .clear,
            radius: isHovered ? 6 : 0,
            y: isHovered ? 2 : 0
        )
        .opacity(hasAppeared ? 1.0 : 0.0)
        .offset(y: hasAppeared ? 0 : 12)
        .animation(
            ProMotionSprings.snappy.delay(appearDelay),
            value: hasAppeared
        )
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .onTapGesture { handleTap() }
        .contextMenu { boardCardContextMenu }
        .alert("Delete Idea?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteIdea() }
        } message: {
            Text("This will permanently remove this idea.")
        }
    }

    // MARK: - Format Icon

    @ViewBuilder
    private var formatIcon: some View {
        let iconName = item.contentFormat?.icon ?? "lightbulb"
        Image(systemName: iconName)
            .font(.system(size: 14))
            .foregroundColor(columnColor.opacity(0.7))
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(columnColor.opacity(0.08))
            )
    }

    // MARK: - Tap Handler

    private func handleTap() {
        if NSEvent.modifierFlags.contains(.shift) {
            withAnimation(ProMotionSprings.snappy) {
                viewModel?.toggleSelection(item.atomUUID)
            }
        } else if viewModel?.isMultiSelectActive == true {
            withAnimation(ProMotionSprings.snappy) {
                viewModel?.clearSelection()
            }
        } else {
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: ["type": EntityType.idea, "id": item.entityId, "commandKTab": "ideas"]
            )
            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.hideCommandK,
                object: nil
            )
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var boardCardContextMenu: some View {
        Button {
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: ["type": EntityType.idea, "id": item.entityId, "commandKTab": "ideas"]
            )
            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.hideCommandK,
                object: nil
            )
        } label: {
            Label("Open", systemImage: "arrow.up.left.and.arrow.down.right")
        }

        Button {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openAsPane, object: nil,
                userInfo: ["type": EntityType.idea, "id": item.entityId]
            )
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
        } label: {
            Label("Open as Pane", systemImage: "rectangle.split.2x1")
        }

        Button {
            NotificationCenter.default.post(
                name: Notification.Name("addIdeaToCanvas"),
                object: nil,
                userInfo: ["atomUUID": item.atomUUID]
            )
        } label: {
            Label("Add to Canvas", systemImage: "plus.rectangle.on.rectangle")
        }

        Divider()

        Menu("Change Status") {
            ForEach(IdeaStatus.allCases, id: \.rawValue) { status in
                Button {
                    changeStatus(to: status)
                } label: {
                    Label(status.displayName, systemImage: status.iconName)
                }
                .disabled(item.status == status)
            }
        }

        Divider()

        Button(role: .destructive) {
            showDeleteAlert = true
        } label: {
            Label("Delete Idea", systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func changeStatus(to newStatus: IdeaStatus) {
        Task {
            _ = try? await AtomRepository.shared.update(uuid: item.atomUUID) { atom in
                atom = atom.withUpdatedIdeaMetadata { meta in
                    meta.ideaStatus = newStatus
                    meta.statusChangedAt = ISO8601.string(from: Date())
                }
            }
        }
    }

    private func deleteIdea() {
        Task {
            try? await AtomRepository.shared.delete(uuid: item.atomUUID)
            NotificationCenter.default.post(
                name: Notification.Name("ideaDeleted"),
                object: nil,
                userInfo: ["uuid": item.atomUUID]
            )
        }
    }
}
