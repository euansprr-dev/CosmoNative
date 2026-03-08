// CosmoOS/Canvas/UnifiedSidebar/SidebarDimensionSection.swift
// Compact dimension scores with mini progress bars
// March 2026 — Command Center navigation

import SwiftUI

struct SidebarDimensionSection: View {
    let isCollapsed: Bool

    @ObservedObject private var engine = DimensionIndexEngine.shared
    @State private var hoveredDimension: LevelDimension?
    @State private var presentedDimension: LevelDimension?

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
                cosmoIndexCard

                VStack(spacing: 6) {
                    ForEach(LevelDimension.allCases, id: \.self) { dimension in
                        dimensionRow(dimension)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $presentedDimension) { dimension in
            DimensionDetailView(
                dimension: dimension,
                state: nil,
                insights: [],
                onDismiss: { presentedDimension = nil }
            )
        }
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            if isCollapsed {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .frame(width: UnifiedSidebarMetrics.railHitTarget, height: UnifiedSidebarMetrics.railHitTarget)
                    .background(DS.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(maxWidth: .infinity)
            } else {
                Text("Dimensions")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.text)

                Spacer()

                Text("CI \(cosmoIndex)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(DS.accent)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(DS.accentSoft, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(DS.accent.opacity(0.12), lineWidth: 1)
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
                .foregroundColor(DS.accent)
        }
    }

    private var cosmoIndexCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(DS.accent.opacity(0.18), lineWidth: 3)
                    .frame(width: 42, height: 42)

                Circle()
                    .trim(from: 0, to: CGFloat(cosmoIndex) / 100.0)
                    .stroke(DS.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 42, height: 42)
                    .rotationEffect(.degrees(-90))

                Text("\(cosmoIndex)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(DS.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Cosmo Index")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.text)

                Text("Weighted view across your six dimensions")
                    .font(.system(size: 11))
                    .foregroundColor(DS.textMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
    }

    // MARK: - Dimension Row

    private func dimensionRow(_ dimension: LevelDimension) -> some View {
        let index = engine.dimensionIndices[dimension] ?? .empty
        let score = Int(index.score.rounded())
        let isHovered = hoveredDimension == dimension
        let color = Color(hex: dimension.colorHex)

        return Button {
            presentedDimension = dimension
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(color.opacity(0.14))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: dimension.iconName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(color)
                    )

                Text(dimension.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(DS.borderSubtle)
                            .frame(height: 4)

                        Capsule()
                            .fill(color)
                            .frame(width: max(0, geo.size.width * CGFloat(score) / 100.0), height: 4)
                    }
                }
                .frame(width: 48, height: 4)

                Text("\(score)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(DS.textMuted)
                    .frame(width: 24, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: UnifiedSidebarMetrics.dimensionRowHeight, alignment: .leading)
            .unifiedSidebarRowChrome(isActive: false, isHovered: isHovered, cornerRadius: 9, hoverFill: DS.surfaceHover)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredDimension = $0 ? dimension : nil }
        .help("\(dimension.displayName): \(score)/100")
    }
}

// MARK: - LevelDimension Identifiable conformance for sheet

extension LevelDimension: Identifiable {
    public var id: String { rawValue }
}
