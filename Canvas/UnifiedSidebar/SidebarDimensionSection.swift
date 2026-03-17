// CosmoOS/Canvas/UnifiedSidebar/SidebarDimensionSection.swift
// Compact dimension scores with mini progress bars
// March 2026 — Command Center navigation

import SwiftUI

struct SidebarDimensionSection: View {
    @Binding var currentDestination: SidebarDestination
    let isCollapsed: Bool

    @ObservedObject private var engine = DimensionIndexEngine.shared
    @ObservedObject private var coordinator = DimensionWorkspaceCoordinator.shared
    @State private var hoveredDimension: LevelDimension?

    // Cosmo Index = weighted average (sanctuaryLevel from engine)
    private var cosmoIndex: Int {
        Int(engine.sanctuaryLevel.rounded())
    }

    var body: some View {
        VStack(spacing: isCollapsed ? 0 : 12) {
            sectionHeader

            if isCollapsed {
                collapsedIndexBadge
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    cosmoIndexSummary

                    Rectangle()
                        .fill(DS.borderSubtle)
                        .frame(height: 1)
                        .padding(.leading, 46)
                }

                VStack(spacing: 6) {
                    ForEach(LevelDimension.allCases, id: \.self) { dimension in
                        dimensionRow(dimension)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await coordinator.start()
        }
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        let hasActiveDimension = currentDestination.isDimension

        return HStack(spacing: 6) {
            if isCollapsed {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(hasActiveDimension ? DS.accent : DS.textSecondary)
                    .frame(width: UnifiedSidebarMetrics.railHitTarget, height: UnifiedSidebarMetrics.railHitTarget)
                    .background(
                        hasActiveDimension ? DS.accentSoft : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .frame(maxWidth: .infinity)
            } else {
                Text("Dimensions")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.text)

                Spacer()

                Text("CI \(cosmoIndex)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(DS.bg, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(DS.borderSubtle, lineWidth: 1)
                    )
            }
        }
    }

    private var collapsedIndexBadge: some View {
        ZStack {
            Circle()
                .stroke(DS.accent.opacity(0.22), lineWidth: 2)
                .frame(width: 32, height: 32)

            Circle()
                .trim(from: 0, to: CGFloat(cosmoIndex) / 100.0)
                .stroke(DS.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 32, height: 32)
                .rotationEffect(.degrees(-90))

            Text("\(cosmoIndex)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(DS.accent)
        }
    }

    private var cosmoIndexSummary: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(DS.accent.opacity(0.18), lineWidth: 2.5)
                    .frame(width: 38, height: 38)

                Circle()
                    .trim(from: 0, to: CGFloat(cosmoIndex) / 100.0)
                    .stroke(DS.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 38, height: 38)
                    .rotationEffect(.degrees(-90))

                Text("\(cosmoIndex)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Cosmo Index")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.text)

                Text("Weighted view across your six dimensions")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    // MARK: - Dimension Row

    private func dimensionRow(_ dimension: LevelDimension) -> some View {
        let index = engine.dimensionIndices[dimension] ?? .empty
        let score = Int(index.score.rounded())
        let isHovered = hoveredDimension == dimension
        let isActive = currentDestination.dimension == dimension
        let color = Color(hex: dimension.colorHex)

        return Button {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.navigateToDimension,
                object: nil,
                userInfo: CosmoNotification.Navigation.DimensionPayload(dimension: dimension).userInfo
            )
        } label: {
            HStack(spacing: 8) {
                Image(systemName: dimension.iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 18, alignment: .center)

                Text(dimension.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isActive ? DS.text : DS.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DS.borderSubtle)
                        .frame(height: 4)

                    Capsule()
                        .fill(color)
                        .frame(width: max(0, 48 * CGFloat(score) / 100.0), height: 4)
                }
                .frame(width: 48, height: 4)

                Text("\(score)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 24, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: UnifiedSidebarMetrics.dimensionRowHeight, alignment: .leading)
            .unifiedSidebarRowChrome(
                isActive: isActive,
                isHovered: isHovered,
                cornerRadius: 9,
                activeFill: color.opacity(0.08),
                hoverFill: DS.bg
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredDimension = $0 ? dimension : nil }
        .contextMenu {
            Button {
                NotificationCenter.default.post(
                    name: CosmoNotification.Navigation.navigateToDimension,
                    object: nil,
                    userInfo: CosmoNotification.Navigation.DimensionPayload(dimension: dimension).userInfo
                )
            } label: {
                Label("Open", systemImage: "arrow.right.circle")
            }

            Button {
                NotificationCenter.default.post(
                    name: CosmoNotification.Navigation.openDimensionAsPane,
                    object: nil,
                    userInfo: CosmoNotification.Navigation.DimensionPayload(dimension: dimension).userInfo
                )
            } label: {
                Label("Open as Pane", systemImage: "rectangle.split.2x1")
            }
        }
        .help("\(dimension.displayName): \(score)/100")
    }
}
