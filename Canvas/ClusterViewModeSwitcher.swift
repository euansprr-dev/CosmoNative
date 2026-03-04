// CosmoOS/Canvas/ClusterViewModeSwitcher.swift
// Floating inspector panel for cluster settings — color, view mode
// Appears to the right of a selected user cluster

import SwiftUI

/// Floating inspector panel positioned to the right of a selected cluster.
/// Modeled after Muse/Figma "Section" inspector: name header, color swatches, view mode pills.
struct ClusterInspectorPanel: View {

    let cluster: CanvasCluster
    let onChangeColor: (Int) -> Void
    let onChangeViewMode: (ClusterViewMode) -> Void
    let onDismiss: () -> Void

    private let panelWidth: CGFloat = 240

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            sectionDivider
            colorSection
            sectionDivider
            viewModeSection
        }
        .frame(width: panelWidth)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        .shadow(color: .black.opacity(0.03), radius: 4, y: 2)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(DS.border)
            .frame(height: 1)
            .padding(.horizontal, 12)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 8) {
            Text(cluster.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.text)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(DS.textMuted)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle().fill(DS.surface)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Color Section

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SECTION COLOR")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DS.textMuted)
                .tracking(0.8)

            HStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { index in
                    colorSwatch(index: index)
                    if index < 7 { Spacer(minLength: 0) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func colorSwatch(index: Int) -> some View {
        let isActive = cluster.colorIndex == index

        Button {
            onChangeColor(index)
        } label: {
            Circle()
                .fill(CanvasCluster.palette[index])
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .stroke(DS.text.opacity(0.6), lineWidth: 2)
                        .frame(width: 30, height: 30)
                        .opacity(isActive ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.15), value: isActive)
    }

    // MARK: - View Mode Section

    private var viewModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("VIEW MODE")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DS.textMuted)
                .tracking(0.8)

            HStack(spacing: 4) {
                ForEach(ClusterViewMode.allCases, id: \.self) { mode in
                    modePill(mode)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func modePill(_ mode: ClusterViewMode) -> some View {
        let isActive = cluster.viewMode == mode

        Button {
            withAnimation(ProMotionSprings.snappy) {
                onChangeViewMode(mode)
            }
        } label: {
            Text(mode.displayName)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? DS.text : DS.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? DS.surface : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View Mode Display Names & Icons

extension ClusterViewMode {
    var iconName: String {
        switch self {
        case .canvas: return "square.grid.2x2"
        case .list:   return "list.bullet"
        case .board:  return "rectangle.split.3x1"
        }
    }

    var displayName: String {
        switch self {
        case .canvas: return "Canvas"
        case .list:   return "List"
        case .board:  return "Board"
        }
    }
}
