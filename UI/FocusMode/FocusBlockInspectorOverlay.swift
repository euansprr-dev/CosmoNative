// CosmoOS/UI/FocusMode/FocusBlockInspectorOverlay.swift
// Reusable modifier that adds CanvasSelectionInspector + block size persistence
// to any focus mode that uses FocusFloatingBlocksLayer.
// March 2026

import SwiftUI

// MARK: - Focus Block Inspector Overlay

struct FocusBlockInspectorOverlay: ViewModifier {
    @ObservedObject var floatingBlocksManager: FocusFloatingBlocksManager

    @State private var selectedCanvasBlockId: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                inspectorPanel
            }
            .onReceive(
                NotificationCenter.default.publisher(for: CosmoNotification.Canvas.blockSelected)
            ) { notification in
                guard let blockId = notification.userInfo?["blockId"] as? String else { return }
                // Check if this block belongs to our floating blocks
                if floatingBlocksManager.canvasBlocks.values.contains(where: { $0.id == blockId }) {
                    withAnimation(ProMotionSprings.snappy) {
                        selectedCanvasBlockId = blockId
                    }
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: CosmoNotification.Canvas.saveBlockSize)
            ) { notification in
                guard let userInfo = notification.userInfo,
                      let blockId = userInfo["blockId"] as? String,
                      let newSize = userInfo["size"] as? CGSize else { return }

                // Find the floating block that contains this canvasBlock
                if let entry = floatingBlocksManager.canvasBlocks.first(where: { $0.value.id == blockId }) {
                    floatingBlocksManager.updateSize(entry.key, size: newSize)
                }
            }
    }

    // MARK: - Inspector Panel

    @ViewBuilder
    private var inspectorPanel: some View {
        if let canvasBlockId = selectedCanvasBlockId,
           let canvasBlock = floatingBlocksManager.canvasBlocks.values.first(where: { $0.id == canvasBlockId }),
           let floatingBlockEntry = floatingBlocksManager.canvasBlocks.first(where: { $0.value.id == canvasBlockId }) {
            CanvasSelectionInspector(
                block: canvasBlock,
                currentThinkspaceId: nil,
                onClose: {
                    withAnimation(ProMotionSprings.snappy) {
                        selectedCanvasBlockId = nil
                    }
                },
                onFocusMode: {
                    NotificationCenter.default.post(
                        name: CosmoNotification.Navigation.openBlockInFocusMode,
                        object: nil,
                        userInfo: ["atomUUID": canvasBlock.entityUuid]
                    )
                    selectedCanvasBlockId = nil
                },
                onDuplicate: {
                    Task {
                        if let atom = try? await AtomRepository.shared.fetch(uuid: canvasBlock.entityUuid) {
                            var duplicate = atom
                            duplicate.uuid = UUID().uuidString
                            duplicate.id = nil
                            duplicate.createdAt = ISO8601DateFormatter().string(from: Date())
                            duplicate.updatedAt = duplicate.createdAt
                            if let created = try? await AtomRepository.shared.create(duplicate) {
                                let position = CGPoint(
                                    x: canvasBlock.position.x + canvasBlock.size.width + 40,
                                    y: canvasBlock.position.y
                                )
                                floatingBlocksManager.addBlock(
                                    linkedAtomUUID: created.uuid,
                                    linkedAtomType: created.type,
                                    title: created.title ?? "Untitled",
                                    position: position
                                )
                            }
                        }
                    }
                    selectedCanvasBlockId = nil
                },
                onDelete: {
                    floatingBlocksManager.removeBlock(id: floatingBlockEntry.key)
                    selectedCanvasBlockId = nil
                }
            )
            .padding(.top, 60)
            .padding(.trailing, 16)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

// MARK: - View Extension

extension View {
    func focusBlockInspector(manager: FocusFloatingBlocksManager) -> some View {
        modifier(FocusBlockInspectorOverlay(floatingBlocksManager: manager))
    }
}
