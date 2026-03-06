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
        VStack(spacing: 0) {
            sectionHeader

            if !isCollapsed {
                VStack(spacing: 2) {
                    ForEach(LevelDimension.allCases, id: \.self) { dimension in
                        dimensionRow(dimension)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
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
                // Collapsed: just show CI score in a circle
                ZStack {
                    Circle()
                        .stroke(DS.accent.opacity(0.3), lineWidth: 2)
                        .frame(width: 28, height: 28)

                    Circle()
                        .trim(from: 0, to: CGFloat(cosmoIndex) / 100.0)
                        .stroke(DS.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 28, height: 28)
                        .rotationEffect(.degrees(-90))

                    Text("\(cosmoIndex)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(DS.accent)
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("DIMENSIONS")
                    .font(DS.sectionLabel)
                    .foregroundColor(DS.textMuted)
                    .tracking(0.88)

                Spacer()

                // CI score badge
                HStack(spacing: 3) {
                    Text("CI")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(DS.accent)

                    Text("\(cosmoIndex)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(DS.accent)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DS.accent.opacity(0.10), in: Capsule())
            }
        }
        .padding(.horizontal, isCollapsed ? 8 : 16)
        .padding(.vertical, 6)
    }

    // MARK: - Dimension Row

    private func dimensionRow(_ dimension: LevelDimension) -> some View {
        let index = engine.dimensionIndices[dimension] ?? .empty
        let score = Int(index.score.rounded())
        let isHovered = hoveredDimension == dimension

        return Button {
            presentedDimension = dimension
        } label: {
            HStack(spacing: 8) {
                // Icon
                Image(systemName: dimension.iconName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(hex: dimension.colorHex))
                    .frame(width: 16)

                // Name
                Text(dimension.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(1)

                Spacer()

                // Mini progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(DS.borderSubtle)
                            .frame(height: 3)

                        // Fill
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(hex: dimension.colorHex))
                            .frame(width: max(0, geo.size.width * CGFloat(score) / 100.0), height: 3)
                    }
                }
                .frame(width: 40, height: 3)

                // Score number
                Text("\(score)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(DS.textMuted)
                    .frame(width: 22, alignment: .trailing)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? DS.surfaceHover : Color.clear)
            )
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
