// CosmoOS/Canvas/BlockContextMenu.swift
// Floating context menu that appears on right-click on a canvas block

import SwiftUI

struct BlockContextMenu: View {
    let blockId: String
    let block: CanvasBlock
    let position: CGPoint
    let selectedBlockIds: [String]
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var hoveredItem: String? = nil
    @State private var hoveredColor: StickyNoteColor? = nil

    private var isStickyNote: Bool { block.entityType == .stickyNote }

    private struct MenuItem: Identifiable {
        let id: String
        let icon: String
        let label: String
        let shortcut: String?
        let isDestructive: Bool

        init(_ id: String, icon: String, label: String, shortcut: String? = nil, isDestructive: Bool = false) {
            self.id = id
            self.icon = icon
            self.label = label
            self.shortcut = shortcut
            self.isDestructive = isDestructive
        }
    }

    // MARK: - Menu Groups

    private var navigationItems: [MenuItem] {
        guard !isStickyNote else { return [] }
        var items: [MenuItem] = []
        let focusTypes: [EntityType] = [.idea, .content, .research, .connection, .cosmoAI, .note, .template]
        if focusTypes.contains(block.entityType) {
            items.append(MenuItem("peek", icon: "eye", label: "Peek"))
            items.append(MenuItem("focus", icon: "arrow.up.left.and.arrow.down.right", label: "Open Focus Mode", shortcut: "⏎"))
        }
        let paneTypes: [EntityType] = [.idea, .content, .research, .connection, .cosmoAI, .note, .template]
        if paneTypes.contains(block.entityType) {
            items.append(MenuItem("pane", icon: "rectangle.split.2x1", label: "Open as Pane"))
        }
        return items
    }

    private var actionItems: [MenuItem] {
        guard !isStickyNote else {
            return [MenuItem("duplicate", icon: "plus.square.on.square", label: "Duplicate", shortcut: "⌘D")]
        }
        var items: [MenuItem] = []
        if block.entityType == .content {
            items.append(MenuItem("compileSpokes", icon: "sparkles.rectangle.stack", label: "Compile Spokes"))
        }
        items.append(MenuItem("connect", icon: "link", label: "Connect to…"))
        if selectedBlockIds.count >= 2 {
            items.append(MenuItem("createCluster", icon: "square.3.layers.3d", label: "Create Cluster"))
        }
        if block.entityType != .cosmoAI {
            items.append(MenuItem("askCosmo", icon: "sparkle", label: "Ask Cosmo"))
        }
        items.append(MenuItem("duplicate", icon: "plus.square.on.square", label: "Duplicate", shortcut: "⌘D"))
        if block.entityType == .template {
            items.append(MenuItem("editTemplate", icon: "rectangle.3.group.fill", label: "Edit Template"))
        }
        return items
    }

    private var destructiveItems: [MenuItem] {
        [MenuItem("delete", icon: "trash", label: "Delete", shortcut: "⌫", isDestructive: true)]
    }

    private var allGroups: [[MenuItem]] {
        [navigationItems, actionItems, destructiveItems].filter { !$0.isEmpty }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBadge
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)

            // Color palette for sticky notes
            if isStickyNote {
                colorPalette
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
            }

            ForEach(Array(allGroups.enumerated()), id: \.offset) { groupIndex, group in
                if groupIndex > 0 || isStickyNote {
                    Divider()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }

                ForEach(Array(group.enumerated()), id: \.element.id) { itemIndex, item in
                    let flatIndex = flatIndexFor(groupIndex: groupIndex, itemIndex: itemIndex)
                    menuRow(item, index: flatIndex)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(width: 240)
        .cortexInspectorPanel(cornerRadius: 18)
        .scaleEffect(appeared ? 1.0 : 0.85)
        .opacity(appeared ? 1.0 : 0)
        .position(x: position.x + 110, y: position.y)
        .onAppear {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
                appeared = true
            }
        }
    }

    // MARK: - Header

    private var headerBadge: some View {
        let typeColor = CosmoMentionColors.color(for: block.entityType)
        let title: String = isStickyNote
            ? "Sticky Note"
            : (block.title.isEmpty ? block.entityType.rawValue.capitalized : block.title)

        return HStack(spacing: 6) {
            Circle()
                .fill(typeColor)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(DS.text)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(block.entityType.rawValue.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(DS.giltMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(DS.glassInputFill)
        )
        .overlay(
            Capsule().strokeBorder(DS.glassBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Color Palette

    private var currentStickyColor: StickyNoteColor {
        if let key = block.metadata["stickyColor"],
           let color = StickyNoteColor(rawValue: key) {
            return color
        }
        return .yellow
    }

    private var colorPalette: some View {
        HStack(spacing: 8) {
            ForEach(StickyNoteColor.allCases) { color in
                colorSwatch(color)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func colorSwatch(_ color: StickyNoteColor) -> some View {
        let isActive = color == currentStickyColor
        let isHover = hoveredColor == color

        Button {
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.changeStickyColor,
                object: nil,
                userInfo: [
                    "blockId": blockId,
                    "color": color.rawValue
                ]
            )
            onDismiss()
        } label: {
            Circle()
                .fill(color.paper)
                .frame(width: 22, height: 22)
                .overlay(
                    Circle()
                        .stroke(color.selectedBorder, lineWidth: isActive ? 2 : (isHover ? 1.5 : 0))
                )
                .overlay {
                    if isActive {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(color.selectedBorder)
                    }
                }
                .scaleEffect(isHover ? 1.12 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredColor = hovering ? color : nil
            }
        }
    }

    // MARK: - Menu Row

    @ViewBuilder
    private func menuRow(_ item: MenuItem, index: Int) -> some View {
        let isHovered = hoveredItem == item.id
        let itemColor: Color = item.isDestructive ? DS.red : DS.text
        let hoverBg: Color = item.isDestructive
            ? DS.red.opacity(0.10)
            : DS.glassInputFillFocused

        Button {
            handleAction(item.id)
            onDismiss()
        } label: {
            HStack(spacing: 0) {
                Image(systemName: item.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isHovered ? itemColor : DS.text.opacity(0.6))
                    .frame(width: 18)

                Text(item.label)
                    .font(.system(size: 13, weight: isHovered ? .medium : .regular))
                    .foregroundStyle(item.isDestructive ? (isHovered ? DS.red : DS.red.opacity(0.8)) : DS.text)
                    .padding(.leading, 10)

                Spacer()

                if let shortcut = item.shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(DS.text.opacity(0.45))
                        .padding(.trailing, 2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? hoverBg : Color.clear)
                    .padding(.horizontal, 6)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredItem = hovering ? item.id : nil
            }
        }
        .opacity(appeared ? 1.0 : 0)
        .offset(y: appeared ? 0 : 4)
        .animation(
            .spring(response: 0.3, dampingFraction: 0.8).delay(Double(index) * 0.02),
            value: appeared
        )
    }

    // MARK: - Helpers

    private func flatIndexFor(groupIndex: Int, itemIndex: Int) -> Int {
        var count = 0
        for g in 0..<groupIndex {
            count += allGroups[g].count
        }
        return count + itemIndex
    }

    // MARK: - Actions

    private func handleAction(_ actionId: String) {
        switch actionId {
        case "peek":
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.peekEntity,
                object: nil,
                userInfo: ["type": block.entityType, "id": block.entityId]
            )
        case "compileSpokes":
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.compileSpokes,
                object: nil,
                userInfo: ["id": block.entityId]
            )
        case "focus":
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: ["type": block.entityType, "id": block.entityId]
            )
        case "connect":
            break
        case "createCluster":
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.createClusterFromSelection,
                object: nil,
                userInfo: [
                    "blockIds": selectedBlockIds,
                    "position": position
                ]
            )
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
        case "pane":
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openAsPane,
                object: nil,
                userInfo: ["type": block.entityType, "id": block.entityId]
            )
        case "delete":
            NotificationCenter.default.post(
                name: .removeBlock,
                object: nil,
                userInfo: ["blockId": blockId]
            )
        case "editTemplate":
            NotificationCenter.default.post(
                name: CosmoNotification.Template.editTemplate,
                object: nil,
                userInfo: ["blockUUID": block.entityUuid]
            )
        default:
            break
        }
    }
}
