// CosmoOS/UI/Sanctuary/Dimensions/Knowledge/KnowledgeClusterInsights.swift
// Cluster Insights - Growing, dormant, and emerging clusters with predictions
// Phase 7: Following SANCTUARY_UI_SPEC_V2.md section 3.5

import SwiftUI

// MARK: - Cluster Insights Panel

/// Panel showing cluster insights and predictions
public struct KnowledgeClusterInsights: View {

    // MARK: - Properties

    let growingClusters: [KnowledgeCluster]
    let dormantClusters: [KnowledgeCluster]
    let emergingLinks: [EmergingConnection]
    let predictions: [KnowledgePrediction]

    @State private var isVisible: Bool = false

    // MARK: - Initialization

    public init(
        growingClusters: [KnowledgeCluster],
        dormantClusters: [KnowledgeCluster],
        emergingLinks: [EmergingConnection],
        predictions: [KnowledgePrediction]
    ) {
        self.growingClusters = growingClusters
        self.dormantClusters = dormantClusters
        self.emergingLinks = emergingLinks
        self.predictions = predictions
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            Text("CLUSTER INSIGHTS")
                .font(SanctuaryTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            // Insight cards row
            HStack(alignment: .top, spacing: SanctuaryLayout.Spacing.md) {
                // Growing clusters
                if let growing = growingClusters.first {
                    ClusterInsightCard(
                        type: .growing,
                        cluster: growing
                    )
                    .opacity(isVisible ? 1 : 0)
                    .offset(y: isVisible ? 0 : 15)
                    .animation(.easeOut(duration: 0.3).delay(0.1), value: isVisible)
                }

                // Dormant clusters
                if let dormant = dormantClusters.first {
                    ClusterInsightCard(
                        type: .dormant,
                        cluster: dormant
                    )
                    .opacity(isVisible ? 1 : 0)
                    .offset(y: isVisible ? 0 : 15)
                    .animation(.easeOut(duration: 0.3).delay(0.15), value: isVisible)
                }

                // Emerging links
                if let emerging = emergingLinks.first {
                    EmergingLinkCard(connection: emerging)
                        .opacity(isVisible ? 1 : 0)
                        .offset(y: isVisible ? 0 : 15)
                        .animation(.easeOut(duration: 0.3).delay(0.2), value: isVisible)
                }
            }

            // Prediction section
            if let prediction = predictions.first {
                KnowledgePredictionCard(prediction: prediction)
                    .opacity(isVisible ? 1 : 0)
                    .offset(y: isVisible ? 0 : 15)
                    .animation(.easeOut(duration: 0.3).delay(0.25), value: isVisible)
            }
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Cluster Insight Card

/// Card showing a cluster insight
public struct ClusterInsightCard: View {

    enum InsightType {
        case growing
        case dormant

        var title: String {
            switch self {
            case .growing: return "GROWING CLUSTER"
            case .dormant: return "DORMANT CLUSTER"
            }
        }

        var color: Color {
            switch self {
            case .growing: return SanctuaryColors.Semantic.success
            case .dormant: return SanctuaryColors.Text.tertiary
            }
        }
    }

    let type: InsightType
    let cluster: KnowledgeCluster

    @State private var isHovered: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Type header
            Text(type.title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(type.color)
                .tracking(1)

            // Cluster name
            Text(cluster.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.primary)

            // Stats
            VStack(alignment: .leading, spacing: 4) {
                switch type {
                case .growing:
                    Text("+\(Int(cluster.growthRate)) nodes this week")
                        .font(.system(size: 11))
                        .foregroundColor(SanctuaryColors.Text.secondary)

                    HStack(spacing: 4) {
                        Text("Density:")
                            .font(.system(size: 10))
                            .foregroundColor(SanctuaryColors.Text.tertiary)

                        Text(String(format: "%.2f", cluster.density))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(type.color)
                    }

                case .dormant:
                    Text("No access: \(cluster.daysSinceActivity) days")
                        .font(.system(size: 11))
                        .foregroundColor(SanctuaryColors.Text.secondary)

                    Text("Consider archiving?")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Semantic.warning)
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(isHovered ? type.color.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Emerging Link Card

/// Card showing an emerging connection
public struct EmergingLinkCard: View {

    let connection: EmergingConnection

    @State private var isHovered: Bool = false
    @State private var lineAnimated: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            Text("EMERGING LINK")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(SanctuaryColors.XP.primary)
                .tracking(1)

            // Connection visualization
            HStack(spacing: SanctuaryLayout.Spacing.sm) {
                Text(connection.sourceCluster)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.primary)

                // Animated connection line
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(SanctuaryColors.Glass.border)
                            .frame(height: 2)

                        Rectangle()
                            .fill(SanctuaryColors.XP.primary)
                            .frame(width: lineAnimated ? geometry.size.width : 0, height: 2)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 8))
                            .foregroundColor(SanctuaryColors.XP.primary)
                            .position(x: geometry.size.width / 2, y: 0)
                    }
                }
                .frame(width: 40, height: 10)

                Text(connection.targetCluster)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }

            // Strength
            HStack(spacing: 4) {
                Text("Strength:")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text(String(format: "%.2f", connection.strength))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.XP.primary)
            }

            // Description
            Text("\"\(connection.description)\"")
                .font(.system(size: 10, design: .serif))
                .foregroundColor(SanctuaryColors.Text.secondary)
                .italic()
                .lineLimit(2)
        }
        .padding(SanctuaryLayout.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(isHovered ? SanctuaryColors.XP.primary.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                lineAnimated = true
            }
        }
    }
}

// MARK: - Knowledge Prediction Card

/// Card showing an AI-generated knowledge prediction
public struct KnowledgePredictionCard: View {

    let prediction: KnowledgePrediction

    @State private var isExpanded: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            HStack {
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundColor(SanctuaryColors.XP.primary)

                    Text("PREDICTION")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(SanctuaryColors.XP.primary)
                        .tracking(1)
                }

                Spacer()

                Text("CONFIDENCE: \(Int(prediction.confidence * 100))%")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            Rectangle()
                .fill(SanctuaryColors.Glass.border)
                .frame(height: 1)

            // Condition (IF)
            VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
                Text("IF:")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text(prediction.condition)
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }

            // Prediction (THEN)
            VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
                Text("THEN:")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text(prediction.prediction)
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }

            // Suggested exploration
            if let suggestion = prediction.suggestedExploration, isExpanded {
                VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
                    Text("SUGGESTED EXPLORATION:")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text(suggestion)
                        .font(.system(size: 11))
                        .foregroundColor(SanctuaryColors.Semantic.info)
                }
            }

            // Action buttons
            HStack(spacing: SanctuaryLayout.Spacing.md) {
                ForEach(prediction.actions, id: \.self) { action in
                    actionButton(action)
                }

                Spacer()

                Button(action: {
                    withAnimation(SanctuarySprings.snappy) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(SanctuaryColors.XP.primary.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func actionButton(_ action: String) -> some View {
        Button(action: {}) {
            HStack(spacing: 4) {
                Image(systemName: iconForAction(action))
                    .font(.system(size: 10))

                Text(action)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(SanctuaryColors.Dimensions.knowledge)
            .padding(.horizontal, SanctuaryLayout.Spacing.sm)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                    .fill(SanctuaryColors.Dimensions.knowledge.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                            .stroke(SanctuaryColors.Dimensions.knowledge.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func iconForAction(_ action: String) -> String {
        if action.lowercased().contains("read") { return "book" }
        if action.lowercased().contains("find") { return "magnifyingglass" }
        if action.lowercased().contains("cluster") { return "chart.bar" }
        return "arrow.right"
    }
}

// MARK: - Cluster List Compact

/// Compact list of clusters
public struct ClusterListCompact: View {

    let clusters: [KnowledgeCluster]
    let onClusterTap: (KnowledgeCluster) -> Void

    public init(clusters: [KnowledgeCluster], onClusterTap: @escaping (KnowledgeCluster) -> Void) {
        self.clusters = clusters
        self.onClusterTap = onClusterTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            Text("CLUSTERS")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            ForEach(clusters.prefix(5)) { cluster in
                Button(action: { onClusterTap(cluster) }) {
                    HStack(spacing: SanctuaryLayout.Spacing.sm) {
                        Circle()
                            .fill(Color(hex: cluster.colorHex))
                            .frame(width: 8, height: 8)

                        Text(cluster.name)
                            .font(.system(size: 11))
                            .foregroundColor(SanctuaryColors.Text.primary)

                        Spacer()

                        Text("\(cluster.nodeCount)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(SanctuaryColors.Text.secondary)

                        Image(systemName: cluster.status == .growing ? "arrow.up.right" :
                                          cluster.status == .dormant ? "zzz" : "minus")
                            .font(.system(size: 8))
                            .foregroundColor(cluster.status.color)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview

#if DEBUG
struct KnowledgeClusterInsights_Previews: PreviewProvider {
    static var previews: some View {
        let data = KnowledgeDimensionData.preview

        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    KnowledgeClusterInsights(
                        growingClusters: data.growingClusters,
                        dormantClusters: data.dormantClusters,
                        emergingLinks: data.emergingLinks,
                        predictions: data.predictions
                    )

                    ClusterListCompact(
                        clusters: data.clusters,
                        onClusterTap: { _ in }
                    )
                }
                .padding()
            }
        }
        .frame(minWidth: 900, minHeight: 700)
    }
}
#endif
