// CosmoOS/Canvas/BlockContextMenu.swift
// Floating context menu that appears on right-click on a canvas block

import SwiftUI

struct BlockContextMenu: View {
    let blockId: String
    let block: CanvasBlock
    let position: CGPoint
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var isHovered: String? = nil

    private var menuItems: [(id: String, icon: String, label: String, color: Color)] {
        var items: [(id: String, icon: String, label: String, color: Color)] = []

        // Focus mode (for types that support it)
        if [.idea, .content, .research, .connection, .cosmoAI].contains(block.entityType) {
            items.append(("focus", "arrow.up.left.and.arrow.down.right", "Open Focus Mode", .white))
        }

        items.append(("connect", "link", "Connect to...", CosmoColors.thinkspacePurple))

        // Ask Cosmo (for non-AI blocks)
        if block.entityType != .cosmoAI {
            items.append(("askCosmo", "sparkle", "Ask Cosmo", CosmoColors.lavender))
        }

        items.append(("duplicate", "plus.square.on.square", "Duplicate", .white))
        items.append(("delete", "trash", "Delete", CosmoColors.softRed))

        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Block type header
            HStack(spacing: 6) {
                Circle()
                    .fill(CosmoMentionColors.color(for: block.entityType))
                    .frame(width: 6, height: 6)
                Text(block.title.isEmpty ? block.entityType.rawValue.capitalized : block.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CosmoColors.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()
                .background(Color.white.opacity(0.06))

            ForEach(menuItems, id: \.id) { item in
                Button {
                    handleAction(item.id)
                    onDismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12))
                            .foregroundColor(item.color.opacity(0.8))
                            .frame(width: 16)

                        Text(item.label)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.white.opacity(0.9))

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHovered == item.id ? Color.white.opacity(0.08) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHovered = hovering ? item.id : nil
                }
            }
        }
        .padding(.vertical, 4)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        .scaleEffect(appeared ? 1.0 : 0.8)
        .opacity(appeared ? 1.0 : 0)
        .position(x: position.x + 100, y: position.y)  // Offset right so menu doesn't cover click point
        .onAppear {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }

    private func handleAction(_ actionId: String) {
        switch actionId {
        case "focus":
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: ["type": block.entityType, "id": block.entityId]
            )
        case "connect":
            // Will be wired to DragToConnectManager in Feature 3
            break
        case "askCosmo":
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.createCosmoAIBlock,
                object: nil,
                userInfo: [
                    "position": CGPoint(x: block.position.x + 360, y: block.position.y),
                    "contextBlockId": blockId
                ]
            )
        case "duplicate":
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.duplicateBlock,
                object: nil,
                userInfo: ["blockId": blockId]
            )
        case "delete":
            NotificationCenter.default.post(
                name: .removeBlock,
                object: nil,
                userInfo: ["blockId": blockId]
            )
        default:
            break
        }
    }
}
