// CosmoOS/Canvas/CanvasViewLayersToolbar.swift
// Vertical toolbar for canvas view layer toggles — sits below the settings cog
// Mirrors CanvasDrawingToolbar pattern with vertical orientation

import SwiftUI

// MARK: - View Layer Item

private enum ViewLayerItem: String, CaseIterable {
    case heatmap
    case provocation
    case cluster

    var icon: String {
        switch self {
        case .heatmap: return "flame"
        case .provocation: return "diamond"
        case .cluster: return "circle.hexagongrid"
        }
    }

    var label: String {
        switch self {
        case .heatmap: return "Crystallization Heatmap"
        case .provocation: return "AI Provocation Scan"
        case .cluster: return "AI Clusters"
        }
    }

    var activeColor: Color {
        switch self {
        case .heatmap: return Color(red: 1.0, green: 0.75, blue: 0.0) // amber
        case .provocation: return Color(red: 0.9, green: 0.25, blue: 0.25) // red
        case .cluster: return DS.accent
        }
    }
}

// MARK: - Canvas View Layers Toolbar

struct CanvasViewLayersToolbar: View {
    @Binding var showCrystallizationHeatmap: Bool
    @ObservedObject var provocationEngine: ProvocationEngine
    @ObservedObject var clusterEngine: CanvasClusterEngine
    let blockUUIDs: [String]

    @State private var layersVisible = true
    @State private var hoveredItem: ViewLayerItem?

    private let items: [ViewLayerItem] = ViewLayerItem.allCases

    var body: some View {
        VStack(spacing: 0) {
            // Horizontal divider line (clickable toggle)
            dividerToggle

            // Layer icons
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element) { index, item in
                    layerButton(item, index: index)
                        .verticalToolReveal(
                            visible: layersVisible,
                            index: index,
                            total: items.count
                        )
                }
            }
            .clipped()
        }
    }

    // MARK: - Divider Toggle

    private var dividerToggle: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                layersVisible.toggle()
            }
        } label: {
            Rectangle()
                .fill(DS.textMuted.opacity(0.4))
                .frame(width: 16, height: 1)
                .padding(.vertical, 8)
                .frame(width: 28)
                .contentShape(Rectangle().size(width: 28, height: 20))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Layer Button

    private func layerButton(_ item: ViewLayerItem, index: Int) -> some View {
        let isActive = itemIsActive(item)
        let badgeCount = item == .provocation ? provocationEngine.activeProvocations.count : 0

        return Button {
            activateItem(item)
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: item.icon)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(isActive ? item.activeColor : DS.textMuted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())

                // Badge count for provocation
                if item == .provocation && badgeCount > 0 && !provocationEngine.isScanning {
                    Text("\(badgeCount)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 14, height: 14)
                        .background(item.activeColor)
                        .clipShape(Circle())
                        .offset(x: 4, y: -2)
                }
            }
            .overlay(alignment: .leading) {
                // Hover tooltip
                if hoveredItem == item {
                    tooltipLabel(item.label)
                        .transition(.opacity)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            withAnimation(.easeInOut(duration: 0.2)) {
                hoveredItem = isHovered ? item : nil
            }
        }
    }

    // MARK: - Tooltip

    private func tooltipLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(DS.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(CosmoColors.thinkspaceTertiary)
            )
            .fixedSize()
            .offset(x: -8)
            .anchorPreference(key: TooltipAnchorKey.self, value: .leading) { $0 }
            .frame(width: 0, height: 0, alignment: .trailing)
            .offset(x: -14)
    }

    // MARK: - State Helpers

    private func itemIsActive(_ item: ViewLayerItem) -> Bool {
        switch item {
        case .heatmap:
            return showCrystallizationHeatmap
        case .provocation:
            return provocationEngine.isScanning || !provocationEngine.activeProvocations.isEmpty
        case .cluster:
            return clusterEngine.isEnabled
        }
    }

    private func activateItem(_ item: ViewLayerItem) {
        switch item {
        case .heatmap:
            withAnimation(ProMotionSprings.snappy) {
                showCrystallizationHeatmap.toggle()
            }
        case .provocation:
            let uuids = blockUUIDs
            Task {
                await provocationEngine.scanBlocks(atomUUIDs: uuids)
            }
        case .cluster:
            withAnimation(ProMotionSprings.snappy) {
                clusterEngine.isEnabled.toggle()
            }
        }
    }
}

// MARK: - Tooltip Anchor Key

private struct TooltipAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGPoint>?
    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = nextValue() ?? value
    }
}

// MARK: - Vertical Staggered Reveal Modifier

/// Animates a tool item sliding in/out vertically with staggered timing.
/// Items collapse upward (toward the divider) one by one.
private struct VerticalToolRevealModifier: ViewModifier {
    let visible: Bool
    let index: Int
    let total: Int

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : -CGFloat((index + 1)) * 14)
            .scaleEffect(visible ? 1 : 0.3, anchor: .top)
            .animation(
                .spring(response: 0.35, dampingFraction: 0.75)
                    .delay(visible ? Double(index) * 0.03 : Double(total - 1 - index) * 0.03),
                value: visible
            )
    }
}

extension View {
    fileprivate func verticalToolReveal(visible: Bool, index: Int, total: Int) -> some View {
        modifier(VerticalToolRevealModifier(visible: visible, index: index, total: total))
    }
}
