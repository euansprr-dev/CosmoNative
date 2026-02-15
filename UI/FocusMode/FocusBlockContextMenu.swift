// CosmoOS/UI/FocusMode/FocusBlockContextMenu.swift
// Right-click context menu modifier for adding floating blocks to focus modes
// February 2026 - Persistent floating blocks stored in atom metadata

import SwiftUI

// MARK: - Focus Block Context Menu

/// A ViewModifier that adds a right-click context menu for creating or adding
/// persistent floating blocks to a focus mode canvas.
struct FocusBlockContextMenuModifier: ViewModifier {
    let manager: FocusFloatingBlocksManager
    let ownerAtomUUID: String

    /// Position to place new blocks at (center-right of canvas)
    var defaultPosition: CGPoint = CGPoint(x: 500, y: 300)

    func body(content: Content) -> some View {
        content
            .contextMenu {
                // Create new atom blocks
                Section("Create New") {
                    Button {
                        createAndAddBlock(type: .note, title: "New Note")
                    } label: {
                        Label("Add Note", systemImage: "note.text")
                    }

                    Button {
                        createAndAddBlock(type: .idea, title: "New Idea")
                    } label: {
                        Label("Add Idea", systemImage: "lightbulb.fill")
                    }

                    Button {
                        createAndAddBlock(type: .task, title: "New Task")
                    } label: {
                        Label("Add Task", systemImage: "checkmark.circle.fill")
                    }

                    Button {
                        createAndAddBlock(type: .content, title: "New Content")
                    } label: {
                        Label("Add Content", systemImage: "doc.text.fill")
                    }

                    Button {
                        createAndAddBlock(type: .research, title: "New Research")
                    } label: {
                        Label("Add Research", systemImage: "magnifyingglass")
                    }

                    Button {
                        createAndAddBlock(type: .connection, title: "New Connection")
                    } label: {
                        Label("Add Connection", systemImage: "link.circle.fill")
                    }
                }

                Divider()

                // Add from database
                Section {
                    Button {
                        NotificationCenter.default.post(
                            name: CosmoNotification.FocusMode.showAtomPicker,
                            object: nil,
                            userInfo: ["ownerAtomUUID": ownerAtomUUID]
                        )
                    } label: {
                        Label("Add from Database...", systemImage: "tray.full.fill")
                    }
                }

                // Remove all
                if !manager.blocks.isEmpty {
                    Divider()
                    Button(role: .destructive) {
                        manager.removeAllBlocks()
                    } label: {
                        Label("Remove All Floating Blocks", systemImage: "trash")
                    }
                }
            }
    }

    private func createAndAddBlock(type: AtomType, title: String) {
        Task {
            let atom = Atom.new(type: type, title: title, body: "")
            guard let created = try? await AtomRepository.shared.create(atom) else { return }

            // Random offset so blocks don't stack perfectly
            let offset = CGPoint(
                x: CGFloat.random(in: -60...60),
                y: CGFloat.random(in: -60...60)
            )
            let position = CGPoint(
                x: defaultPosition.x + offset.x,
                y: defaultPosition.y + offset.y
            )

            await MainActor.run {
                manager.addBlock(
                    linkedAtomUUID: created.uuid,
                    linkedAtomType: type,
                    title: title,
                    position: position
                )
            }
        }
    }
}

extension View {
    /// Adds a right-click context menu for adding persistent floating blocks
    func focusBlockContextMenu(
        manager: FocusFloatingBlocksManager,
        ownerAtomUUID: String,
        defaultPosition: CGPoint = CGPoint(x: 500, y: 300)
    ) -> some View {
        self.modifier(
            FocusBlockContextMenuModifier(
                manager: manager,
                ownerAtomUUID: ownerAtomUUID,
                defaultPosition: defaultPosition
            )
        )
    }
}

// MARK: - Notification Extension

extension CosmoNotification {
    enum FocusMode {
        /// Posted when user wants to pick an atom from database to add as floating block
        static let showAtomPicker = Notification.Name("com.cosmo.focusMode.showAtomPicker")

        /// Posted when an atom is selected from the picker to be added as floating block
        static let addAtomAsFloatingBlock = Notification.Name("com.cosmo.focusMode.addAtomAsFloatingBlock")
    }
}
