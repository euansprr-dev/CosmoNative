// CosmoOS/UI/Sanctuary/SanctuaryGlassMaterial.swift
// Sanctuary Glass Material System - Apple-grade translucent surfaces for dark UI
// Phase 1 Foundation: Glass cards, panels, overlays, and glow effects

import SwiftUI

// MARK: - Glass Material Types

/// Different glass material presets for Sanctuary UI
public enum SanctuaryGlassType {
    /// Primary glass for main cards and panels
    case primary

    /// Secondary glass for nested elements
    case secondary

    /// Accent glass for highlighted/active states
    case accent

    /// Frosted glass with more blur
    case frosted

    /// Subtle glass for backgrounds
    case subtle

    /// Void glass - nearly transparent
    case void
}

/// Glass border position
public enum GlassBorderPosition {
    case all
    case top
    case bottom
    case leading
    case trailing
    case horizontal
    case vertical
}

// MARK: - Glass Surface Modifier

/// Primary glass surface modifier for Sanctuary UI
public struct SanctuaryGlassSurface: ViewModifier {
    let type: SanctuaryGlassType
    let cornerRadius: CGFloat
    let borderPosition: GlassBorderPosition
    let accentColor: Color?
    let isHovered: Bool
    let isPressed: Bool

    public init(
        type: SanctuaryGlassType = .primary,
        cornerRadius: CGFloat = SanctuaryLayout.cardCornerRadius,
        borderPosition: GlassBorderPosition = .all,
        accentColor: Color? = nil,
        isHovered: Bool = false,
        isPressed: Bool = false
    ) {
        self.type = type
        self.cornerRadius = cornerRadius
        self.borderPosition = borderPosition
        self.accentColor = accentColor
        self.isHovered = isHovered
        self.isPressed = isPressed
    }

    private var backgroundColor: Color {
        switch type {
        case .primary: return SanctuaryColors.glassPrimary
        case .secondary: return SanctuaryColors.glassSecondary
        case .accent: return SanctuaryColors.glassAccent
        case .frosted: return Color.white.opacity(0.1)
        case .subtle: return Color.white.opacity(0.03)
        case .void: return Color.white.opacity(0.02)
        }
    }

    private var borderColor: Color {
        if let accent = accentColor, isHovered {
            return accent.opacity(0.4)
        }
        return isHovered ? SanctuaryColors.glassBorder : SanctuaryColors.glassBorderSubtle
    }

    private var shadowOpacity: Double {
        if isPressed { return 0.1 }
        if isHovered { return 0.25 }
        return 0.15
    }

    private var scale: CGFloat {
        if isPressed { return 0.98 }
        if isHovered { return 1.01 }
        return 1.0
    }

    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Base glass fill
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(backgroundColor)

                    // Highlight gradient (top-left light source)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered ? 0.12 : 0.08),
                                    Color.white.opacity(0.02),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // Accent tint overlay
                    if let accent = accentColor {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(accent.opacity(isHovered ? 0.08 : 0.04))
                    }
                }
            )
            .overlay(
                // Border
                glassBorder
            )
            .shadow(
                color: (accentColor ?? Color.black).opacity(shadowOpacity),
                radius: isHovered ? 16 : 8,
                x: 0,
                y: isHovered ? 6 : 4
            )
            .scaleEffect(scale)
    }

    @ViewBuilder
    private var glassBorder: some View {
        switch borderPosition {
        case .all:
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(borderColor, lineWidth: 1)

        case .top:
            VStack(spacing: 0) {
                Rectangle()
                    .fill(borderColor)
                    .frame(height: 1)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

        case .bottom:
            VStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(borderColor)
                    .frame(height: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

        case .leading:
            HStack(spacing: 0) {
                Rectangle()
                    .fill(borderColor)
                    .frame(width: 1)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

        case .trailing:
            HStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(borderColor)
                    .frame(width: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

        case .horizontal:
            VStack(spacing: 0) {
                Rectangle()
                    .fill(borderColor)
                    .frame(height: 1)
                Spacer()
                Rectangle()
                    .fill(borderColor)
                    .frame(height: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

        case .vertical:
            HStack(spacing: 0) {
                Rectangle()
                    .fill(borderColor)
                    .frame(width: 1)
                Spacer()
                Rectangle()
                    .fill(borderColor)
                    .frame(width: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

// MARK: - Glass Card Modifier

/// Glass card with integrated hover and press states
@MainActor
public struct SanctuaryGlassCard: ViewModifier {
    let accentColor: Color
    let cornerRadius: CGFloat
    @Binding var isHovered: Bool
    @Binding var isPressed: Bool

    public init(
        accentColor: Color = SanctuaryColors.cognitive,
        cornerRadius: CGFloat = SanctuaryLayout.cardCornerRadius,
        isHovered: Binding<Bool> = .constant(false),
        isPressed: Binding<Bool> = .constant(false)
    ) {
        self.accentColor = accentColor
        self.cornerRadius = cornerRadius
        self._isHovered = isHovered
        self._isPressed = isPressed
    }

    public func body(content: Content) -> some View {
        content
            .modifier(SanctuaryGlassSurface(
                type: .primary,
                cornerRadius: cornerRadius,
                accentColor: accentColor,
                isHovered: isHovered,
                isPressed: isPressed
            ))
            .onHover { hovering in
                withAnimation(SanctuarySprings.hover) {
                    isHovered = hovering
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        withAnimation(SanctuarySprings.press) {
                            isPressed = true
                        }
                    }
                    .onEnded { _ in
                        withAnimation(SanctuarySprings.hover) {
                            isPressed = false
                        }
                    }
            )
    }
}

// MARK: - Accent Seam

/// Colored accent bar for dimension indication
public struct SanctuaryAccentSeam: View {
    public let color: Color
    public let position: Edge
    public let width: CGFloat
    public let cornerRadius: CGFloat

    public init(
        color: Color,
        position: Edge = .leading,
        width: CGFloat = 3,
        cornerRadius: CGFloat = 2
    ) {
        self.color = color
        self.position = position
        self.width = width
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        GeometryReader { geometry in
            switch position {
            case .leading:
                HStack(spacing: 0) {
                    seamBar(height: geometry.size.height)
                    Spacer()
                }
            case .trailing:
                HStack(spacing: 0) {
                    Spacer()
                    seamBar(height: geometry.size.height)
                }
            case .top:
                VStack(spacing: 0) {
                    seamBar(width: geometry.size.width)
                    Spacer()
                }
            case .bottom:
                VStack(spacing: 0) {
                    Spacer()
                    seamBar(width: geometry.size.width)
                }
            }
        }
    }

    @ViewBuilder
    private func seamBar(width: CGFloat? = nil, height: CGFloat? = nil) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    colors: [color, color.opacity(0.6)],
                    startPoint: position == .leading || position == .trailing ? .top : .leading,
                    endPoint: position == .leading || position == .trailing ? .bottom : .trailing
                )
            )
            .frame(width: width ?? self.width, height: height ?? self.width)
            .shadow(color: color.opacity(0.5), radius: 4, x: 0, y: 0)
    }
}

// MARK: - Glow Effects

/// Dimension-colored glow modifier
@MainActor
public struct SanctuaryGlow: ViewModifier {
    let color: Color
    let intensity: CGFloat
    let radius: CGFloat
    let isAnimated: Bool

    @State private var glowPhase: CGFloat = 0

    public init(
        color: Color,
        intensity: CGFloat = 0.3,
        radius: CGFloat = 15,
        isAnimated: Bool = false
    ) {
        self.color = color
        self.intensity = intensity
        self.radius = radius
        self.isAnimated = isAnimated
    }

    private var animatedIntensity: CGFloat {
        if isAnimated {
            return intensity * (0.8 + sin(glowPhase) * 0.2)
        }
        return intensity
    }

    public func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(animatedIntensity), radius: radius, x: 0, y: 0)
            .shadow(color: color.opacity(animatedIntensity * 0.5), radius: radius * 2, x: 0, y: 0)
            .onAppear {
                if isAnimated {
                    withAnimation(
                        .easeInOut(duration: SanctuaryDurations.glowPulse)
                        .repeatForever(autoreverses: true)
                    ) {
                        glowPhase = .pi * 2
                    }
                }
            }
    }
}

// MARK: - Connection Line View

/// Animated connection line between elements
public struct SanctuaryConnectionLine: View {
    let from: CGPoint
    let to: CGPoint
    let color1: Color
    let color2: Color
    let lineWidth: CGFloat
    let glowIntensity: CGFloat
    let isAnimated: Bool

    @State private var flowPhase: CGFloat = 0

    public init(
        from: CGPoint,
        to: CGPoint,
        color1: Color,
        color2: Color,
        lineWidth: CGFloat = 1.5,
        glowIntensity: CGFloat = 0.3,
        isAnimated: Bool = true
    ) {
        self.from = from
        self.to = to
        self.color1 = color1
        self.color2 = color2
        self.lineWidth = lineWidth
        self.glowIntensity = glowIntensity
        self.isAnimated = isAnimated
    }

    public var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)

            // Draw glow layer
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [
                        color1.opacity(glowIntensity),
                        color2.opacity(glowIntensity)
                    ]),
                    startPoint: from,
                    endPoint: to
                ),
                lineWidth: lineWidth * 3
            )

            // Draw main line
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [color1, color2]),
                    startPoint: from,
                    endPoint: to
                ),
                lineWidth: lineWidth
            )
        }
        .blur(radius: 0.5)
        .opacity(0.8 + Darwin.sin(flowPhase) * 0.2)
        .onAppear {
            if isAnimated {
                withAnimation(
                    .linear(duration: 3.0)
                    .repeatForever(autoreverses: false)
                ) {
                    flowPhase = .pi * 2
                }
            }
        }
    }
}

// MARK: - Progress Ring View

/// XP progress ring with smooth animation
public struct SanctuaryProgressRing: View {
    let progress: Double
    let lineWidth: CGFloat
    let progressColor: Color
    let trackColor: Color
    let showGlow: Bool

    @State private var animatedProgress: Double = 0

    public init(
        progress: Double,
        lineWidth: CGFloat = 3,
        progressColor: Color = SanctuaryColors.live,
        trackColor: Color = Color.white.opacity(0.1),
        showGlow: Bool = true
    ) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.progressColor = progressColor
        self.trackColor = trackColor
        self.showGlow = showGlow
    }

    public var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)

            // Progress
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    LinearGradient(
                        colors: [progressColor, progressColor.opacity(0.7)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(
                    color: showGlow ? progressColor.opacity(0.5) : .clear,
                    radius: showGlow ? 4 : 0
                )
        }
        .onAppear {
            withAnimation(SanctuarySprings.smooth) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(SanctuarySprings.smooth) {
                animatedProgress = newValue
            }
        }
    }
}

// MARK: - Metric Card View

/// Reusable metric display card for Sanctuary
public struct SanctuaryMetricCard<Content: View>: View {
    let title: String
    let value: String
    let trend: String?
    let trendIsPositive: Bool?
    let dimension: LevelDimension?
    let content: (() -> Content)?

    @State private var isHovered = false

    public init(
        title: String,
        value: String,
        trend: String? = nil,
        trendIsPositive: Bool? = nil,
        dimension: LevelDimension? = nil,
        @ViewBuilder content: @escaping () -> Content = { EmptyView() }
    ) {
        self.title = title
        self.value = value
        self.trend = trend
        self.trendIsPositive = trendIsPositive
        self.dimension = dimension
        self.content = content
    }

    private var accentColor: Color {
        if let dimension = dimension {
            return SanctuaryColors.color(for: dimension)
        }
        return SanctuaryColors.cognitive
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.spacing8) {
            // Title
            Text(title.uppercased())
                .font(SanctuaryTypography.labelSmall)
                .foregroundColor(SanctuaryColors.textTertiary)
                .tracking(0.5)

            HStack(alignment: .firstTextBaseline, spacing: SanctuaryLayout.spacing8) {
                // Value
                Text(value)
                    .font(SanctuaryTypography.metricMedium)
                    .foregroundColor(SanctuaryColors.textPrimary)

                // Trend
                if let trend = trend, let isPositive = trendIsPositive {
                    HStack(spacing: 2) {
                        Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text(trend)
                            .font(SanctuaryTypography.labelSmall)
                    }
                    .foregroundColor(isPositive ? SanctuaryColors.live : SanctuaryColors.warning)
                }
            }

            // Optional additional content
            if let content = content {
                content()
            }
        }
        .padding(SanctuaryLayout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SanctuaryGlassSurface(
            type: .primary,
            accentColor: accentColor,
            isHovered: isHovered
        ))
        .overlay(alignment: .leading) {
            if dimension != nil {
                SanctuaryAccentSeam(color: accentColor)
                    .padding(.vertical, SanctuaryLayout.spacing8)
            }
        }
        .onHover { hovering in
            withAnimation(SanctuarySprings.hover) {
                isHovered = hovering
            }
        }
    }
}

// Empty view default for content
extension SanctuaryMetricCard where Content == EmptyView {
    public init(
        title: String,
        value: String,
        trend: String? = nil,
        trendIsPositive: Bool? = nil,
        dimension: LevelDimension? = nil
    ) {
        self.title = title
        self.value = value
        self.trend = trend
        self.trendIsPositive = trendIsPositive
        self.dimension = dimension
        self.content = nil
    }
}

// MARK: - View Extensions

extension View {
    /// Apply Sanctuary glass surface
    public func sanctuaryGlass(
        _ type: SanctuaryGlassType = .primary,
        cornerRadius: CGFloat = SanctuaryLayout.cardCornerRadius,
        accentColor: Color? = nil,
        isHovered: Bool = false
    ) -> some View {
        modifier(SanctuaryGlassSurface(
            type: type,
            cornerRadius: cornerRadius,
            accentColor: accentColor,
            isHovered: isHovered
        ))
    }

    /// Apply Sanctuary glow effect
    public func sanctuaryGlow(
        _ color: Color,
        intensity: CGFloat = 0.3,
        radius: CGFloat = 15,
        isAnimated: Bool = false
    ) -> some View {
        modifier(SanctuaryGlow(
            color: color,
            intensity: intensity,
            radius: radius,
            isAnimated: isAnimated
        ))
    }

    /// Apply dimension-specific styling
    public func dimensionStyling(
        _ dimension: LevelDimension,
        isHovered: Bool = false,
        showGlow: Bool = true
    ) -> some View {
        let color = SanctuaryColors.color(for: dimension)
        return self
            .sanctuaryGlass(accentColor: color, isHovered: isHovered)
            .overlay(alignment: .leading) {
                SanctuaryAccentSeam(color: color)
                    .padding(.vertical, SanctuaryLayout.spacing8)
            }
            .sanctuaryGlow(color, intensity: showGlow ? 0.2 : 0, isAnimated: showGlow)
    }
}

// MARK: - Preview

#if DEBUG
struct SanctuaryGlassMaterial_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            SanctuaryColors.voidPrimary.ignoresSafeArea()

            VStack(spacing: 24) {
                // Glass types
                HStack(spacing: 16) {
                    ForEach([SanctuaryGlassType.primary, .secondary, .accent], id: \.self) { type in
                        Text("Glass")
                            .font(SanctuaryTypography.label)
                            .foregroundColor(.white)
                            .padding()
                            .sanctuaryGlass(type)
                    }
                }

                // Metric cards
                HStack(spacing: 16) {
                    SanctuaryMetricCard(
                        title: "Deep Work",
                        value: "4h 32m",
                        trend: "+18%",
                        trendIsPositive: true,
                        dimension: .cognitive
                    )
                    .frame(width: 160)

                    SanctuaryMetricCard(
                        title: "Words",
                        value: "2,847",
                        trend: "-5%",
                        trendIsPositive: false,
                        dimension: .creative
                    )
                    .frame(width: 160)
                }

                // Progress ring
                SanctuaryProgressRing(progress: 0.72)
                    .frame(width: 80, height: 80)

                // Connection line
                SanctuaryConnectionLine(
                    from: CGPoint(x: 50, y: 50),
                    to: CGPoint(x: 200, y: 50),
                    color1: SanctuaryColors.cognitive,
                    color2: SanctuaryColors.creative
                )
                .frame(width: 250, height: 100)
            }
            .padding(32)
        }
        .preferredColorScheme(.dark)
    }
}
#endif
