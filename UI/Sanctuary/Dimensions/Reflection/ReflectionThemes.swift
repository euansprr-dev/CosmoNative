// CosmoOS/UI/Sanctuary/Dimensions/Reflection/ReflectionThemes.swift
// Recurring Themes - Theme tracking, evolution, and word cloud visualization
// Phase 8: Following SANCTUARY_UI_SPEC_V2.md section 3.6

import SwiftUI

// MARK: - Recurring Themes Panel

/// Main panel showing recurring themes in reflections
public struct RecurringThemesPanel: View {

    // MARK: - Properties

    let themes: [ReflectionTheme]
    let topThemes: [ReflectionTheme]
    let emergingThemes: [ReflectionTheme]
    let fadingThemes: [ReflectionTheme]
    let onThemeTap: (ReflectionTheme) -> Void

    @State private var isVisible: Bool = false
    @State private var selectedView: ThemeView = .cloud

    private enum ThemeView: String, CaseIterable {
        case cloud = "Cloud"
        case list = "List"
        case evolution = "Evolution"
    }

    // MARK: - Initialization

    public init(
        themes: [ReflectionTheme],
        topThemes: [ReflectionTheme],
        emergingThemes: [ReflectionTheme],
        fadingThemes: [ReflectionTheme],
        onThemeTap: @escaping (ReflectionTheme) -> Void
    ) {
        self.themes = themes
        self.topThemes = topThemes
        self.emergingThemes = emergingThemes
        self.fadingThemes = fadingThemes
        self.onThemeTap = onThemeTap
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header with view toggle
            headerSection

            // Selected view content
            Group {
                switch selectedView {
                case .cloud:
                    themeWordCloud
                case .list:
                    themesList
                case .evolution:
                    themesEvolution
                }
            }
            .frame(minHeight: 200)

            // Quick insights
            themeInsights
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
            withAnimation(.easeOut(duration: 0.5)) {
                isVisible = true
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("RECURRING THEMES")
                    .font(SanctuaryTypography.label)
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(2)

                Text("\(themes.count) themes detected")
                    .font(.system(size: 11))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }

            Spacer()

            // View toggle
            HStack(spacing: 0) {
                ForEach(ThemeView.allCases, id: \.self) { view in
                    Button(action: { selectedView = view }) {
                        Text(view.rawValue)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(selectedView == view ? .white : SanctuaryColors.Text.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                selectedView == view ?
                                    Capsule().fill(SanctuaryColors.Dimensions.reflection) :
                                    Capsule().fill(Color.clear)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .background(
                Capsule()
                    .fill(SanctuaryColors.Glass.highlight)
            )
        }
    }

    // MARK: - Theme Word Cloud

    private var themeWordCloud: some View {
        GeometryReader { geometry in
            let cloudItems = generateCloudPositions(themes: topThemes.prefix(15), in: geometry.size)

            ZStack {
                ForEach(Array(cloudItems.enumerated()), id: \.offset) { index, item in
                    ThemeCloudWord(
                        theme: item.theme,
                        fontSize: item.fontSize,
                        onTap: { onThemeTap(item.theme) }
                    )
                    .position(item.position)
                    .opacity(isVisible ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(Double(index) * 0.05), value: isVisible)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
        )
    }

    private struct CloudItem {
        let theme: ReflectionTheme
        let position: CGPoint
        let fontSize: CGFloat
    }

    private func generateCloudPositions(themes: ArraySlice<ReflectionTheme>, in size: CGSize) -> [CloudItem] {
        var items: [CloudItem] = []
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        for (index, theme) in themes.enumerated() {
            // Size based on frequency
            let maxFreq = themes.map { $0.frequency }.max() ?? 1
            let normalizedSize = CGFloat(theme.frequency) / CGFloat(maxFreq)
            let fontSize = 12 + normalizedSize * 18

            // Spiral positioning
            let angle = Double(index) * 0.8
            let radius = 30 + Double(index) * 15
            let x = center.x + CGFloat(cos(angle) * radius)
            let y = center.y + CGFloat(sin(angle) * radius * 0.6)

            items.append(CloudItem(
                theme: theme,
                position: CGPoint(x: x, y: y),
                fontSize: fontSize
            ))
        }

        return items
    }

    // MARK: - Themes List

    private var themesList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: SanctuaryLayout.Spacing.sm) {
                ForEach(themes.prefix(10)) { theme in
                    ThemeListRow(theme: theme, onTap: { onThemeTap(theme) })
                }
            }
            .padding(SanctuaryLayout.Spacing.sm)
        }
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
        )
    }

    // MARK: - Themes Evolution

    private var themesEvolution: some View {
        VStack(spacing: SanctuaryLayout.Spacing.md) {
            // Emerging themes
            if !emergingThemes.isEmpty {
                themeSection(title: "EMERGING", themes: emergingThemes, color: SanctuaryColors.Semantic.success, icon: "arrow.up.circle.fill")
            }

            // Top themes
            if !topThemes.isEmpty {
                themeSection(title: "DOMINANT", themes: Array(topThemes.prefix(3)), color: SanctuaryColors.Dimensions.reflection, icon: "star.fill")
            }

            // Fading themes
            if !fadingThemes.isEmpty {
                themeSection(title: "FADING", themes: fadingThemes, color: SanctuaryColors.Text.tertiary, icon: "arrow.down.circle.fill")
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
        )
    }

    private func themeSection(title: String, themes: [ReflectionTheme], color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(color)

                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(color)
                    .tracking(1)
            }

            FlowLayout(spacing: 6) {
                ForEach(themes) { theme in
                    Text(theme.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(color.opacity(0.15))
                        )
                        .onTapGesture { onThemeTap(theme) }
                }
            }
        }
    }

    // MARK: - Theme Insights

    private var themeInsights: some View {
        HStack(spacing: SanctuaryLayout.Spacing.lg) {
            // Most frequent
            if let top = topThemes.first {
                insightCard(
                    label: "Most Frequent",
                    value: top.name,
                    subtext: "\(top.frequency) mentions",
                    color: SanctuaryColors.Dimensions.reflection
                )
            }

            // Fastest growing
            if let emerging = emergingThemes.first {
                insightCard(
                    label: "Emerging",
                    value: emerging.name,
                    subtext: "+\(Int(emerging.growthRate * 100))%",
                    color: SanctuaryColors.Semantic.success
                )
            }

            // Longest running
            if let longest = themes.max(by: { $0.firstSeen > $1.firstSeen }) {
                let days = Calendar.current.dateComponents([.day], from: longest.firstSeen, to: Date()).day ?? 0
                insightCard(
                    label: "Longest Running",
                    value: longest.name,
                    subtext: "\(days) days",
                    color: SanctuaryColors.Semantic.info
                )
            }
        }
    }

    private func insightCard(label: String, value: String, subtext: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color)
                .lineLimit(1)

            Text(subtext)
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                .fill(SanctuaryColors.Glass.highlight)
        )
    }
}

// MARK: - Theme Cloud Word

/// Individual word in the theme cloud
private struct ThemeCloudWord: View {

    let theme: ReflectionTheme
    let fontSize: CGFloat
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onTap) {
            Text(theme.name)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundColor(themeColor)
                .opacity(isHovered ? 1.0 : 0.8)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isHovered ? 1.1 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var themeColor: Color {
        if theme.growthRate > 0.1 { return SanctuaryColors.Semantic.success }
        if theme.growthRate < -0.1 { return SanctuaryColors.Text.tertiary }
        return SanctuaryColors.Dimensions.reflection
    }
}

// MARK: - Theme List Row

/// Row in the themes list view
private struct ThemeListRow: View {

    let theme: ReflectionTheme
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: SanctuaryLayout.Spacing.md) {
                // Frequency indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(themeColor)
                    .frame(width: 4, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(SanctuaryColors.Text.primary)

                    Text("\(theme.frequency) mentions")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }

                Spacer()

                // Trend indicator
                HStack(spacing: 2) {
                    Image(systemName: trendIcon)
                        .font(.system(size: 10))
                        .foregroundColor(trendColor)

                    Text(trendLabel)
                        .font(.system(size: 10))
                        .foregroundColor(trendColor)
                }

                // Last seen
                Text(formatDate(theme.lastSeen))
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }
            .padding(.horizontal, SanctuaryLayout.Spacing.md)
            .padding(.vertical, SanctuaryLayout.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                    .fill(isHovered ? SanctuaryColors.Glass.highlight : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var themeColor: Color {
        if theme.growthRate > 0.1 { return SanctuaryColors.Semantic.success }
        if theme.growthRate < -0.1 { return SanctuaryColors.Text.tertiary }
        return SanctuaryColors.Dimensions.reflection
    }

    private var trendIcon: String {
        if theme.growthRate > 0.05 { return "arrow.up" }
        if theme.growthRate < -0.05 { return "arrow.down" }
        return "minus"
    }

    private var trendColor: Color {
        if theme.growthRate > 0.05 { return SanctuaryColors.Semantic.success }
        if theme.growthRate < -0.05 { return SanctuaryColors.Semantic.error }
        return SanctuaryColors.Text.tertiary
    }

    private var trendLabel: String {
        let percent = abs(Int(theme.growthRate * 100))
        if theme.growthRate > 0.05 { return "+\(percent)%" }
        if theme.growthRate < -0.05 { return "-\(percent)%" }
        return "stable"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Theme Detail Panel

/// Detailed view of a single theme
public struct ThemeDetailPanel: View {

    let theme: ReflectionTheme
    let relatedThemes: [ReflectionTheme]
    let journalExcerpts: [String]
    let onDismiss: () -> Void

    public init(
        theme: ReflectionTheme,
        relatedThemes: [ReflectionTheme],
        journalExcerpts: [String],
        onDismiss: @escaping () -> Void
    ) {
        self.theme = theme
        self.relatedThemes = relatedThemes
        self.journalExcerpts = journalExcerpts
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            HStack {
                Text(theme.name.uppercased())
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(SanctuaryColors.Dimensions.reflection)
                    .tracking(1)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
                .buttonStyle(PlainButtonStyle())
            }

            Rectangle()
                .fill(SanctuaryColors.Glass.border)
                .frame(height: 1)

            // Stats
            HStack(spacing: SanctuaryLayout.Spacing.xl) {
                statItem(value: "\(theme.frequency)", label: "mentions")
                statItem(value: formatGrowth(theme.growthRate), label: "growth")
                statItem(value: formatDuration(from: theme.firstSeen), label: "tracking")
            }

            // Related themes
            if !relatedThemes.isEmpty {
                VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
                    Text("RELATED THEMES")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                        .tracking(1)

                    FlowLayout(spacing: 6) {
                        ForEach(relatedThemes) { related in
                            Text(related.name)
                                .font(.system(size: 10))
                                .foregroundColor(SanctuaryColors.Dimensions.reflection)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(SanctuaryColors.Dimensions.reflection.opacity(0.1))
                                )
                        }
                    }
                }
            }

            // Journal excerpts
            if !journalExcerpts.isEmpty {
                VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
                    Text("EXCERPTS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                        .tracking(1)

                    ForEach(journalExcerpts.prefix(3), id: \.self) { excerpt in
                        Text("\"...\(excerpt)...\"")
                            .font(.system(size: 11))
                            .foregroundColor(SanctuaryColors.Text.secondary)
                            .italic()
                            .lineLimit(2)
                            .padding(SanctuaryLayout.Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                                    .fill(SanctuaryColors.Glass.highlight)
                            )
                    }
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(SanctuaryColors.Dimensions.reflection.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(SanctuaryColors.Text.primary)

            Text(label)
                .font(.system(size: 9))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatGrowth(_ rate: Double) -> String {
        let percent = Int(rate * 100)
        if percent > 0 { return "+\(percent)%" }
        if percent < 0 { return "\(percent)%" }
        return "0%"
    }

    private func formatDuration(from date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days >= 30 {
            return "\(days / 30) mo"
        }
        return "\(days) days"
    }
}

// MARK: - Themes Compact

/// Compact themes summary
public struct ThemesCompact: View {

    let topThemes: [ReflectionTheme]
    let onExpand: () -> Void

    public init(topThemes: [ReflectionTheme], onExpand: @escaping () -> Void) {
        self.topThemes = topThemes
        self.onExpand = onExpand
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            HStack {
                Text("THEMES")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                Spacer()

                Button(action: onExpand) {
                    HStack(spacing: 4) {
                        Text("View All")
                            .font(.system(size: 10))

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8))
                    }
                    .foregroundColor(SanctuaryColors.Dimensions.reflection)
                }
                .buttonStyle(PlainButtonStyle())
            }

            FlowLayout(spacing: 6) {
                ForEach(topThemes.prefix(5)) { theme in
                    Text(theme.name)
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(SanctuaryColors.Glass.highlight)
                        )
                }
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

// MARK: - Flow Layout (Duplicate for local use if not imported)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }

    private struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
                self.size.width = max(self.size.width, x)
            }
            self.size.height = y + lineHeight
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ReflectionThemes_Previews: PreviewProvider {
    static var previews: some View {
        let themes = ReflectionDimensionData.preview.themes
        let topThemes = themes.sorted { $0.frequency > $1.frequency }
        let emergingThemes = themes.filter { $0.growthRate > 0.1 }
        let fadingThemes = themes.filter { $0.growthRate < -0.1 }

        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    RecurringThemesPanel(
                        themes: themes,
                        topThemes: topThemes,
                        emergingThemes: emergingThemes,
                        fadingThemes: fadingThemes,
                        onThemeTap: { _ in }
                    )

                    ThemeDetailPanel(
                        theme: themes[0],
                        relatedThemes: Array(themes.prefix(3)),
                        journalExcerpts: [
                            "feeling grateful for the small moments",
                            "gratitude helps me stay grounded",
                            "writing about what I'm grateful for"
                        ],
                        onDismiss: {}
                    )
                    .frame(maxWidth: 400)

                    ThemesCompact(
                        topThemes: topThemes,
                        onExpand: {}
                    )
                }
                .padding()
            }
        }
        .frame(minWidth: 800, minHeight: 900)
    }
}
#endif
