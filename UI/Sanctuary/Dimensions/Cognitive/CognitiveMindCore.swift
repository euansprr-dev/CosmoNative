// CosmoOS/UI/Sanctuary/Dimensions/Cognitive/CognitiveMindCore.swift
// Mental Energy Nucleus - Central visualization with focus/load rings
// Phase 3: Following SANCTUARY_UI_SPEC_V2.md section 3.1

import SwiftUI

// MARK: - Cognitive Mind Core

/// The central "Mind Core" visualization for the Cognitive Dimension
/// Features: Core nucleus, Focus Stability Ring (24h), Cognitive Load Ring with particles
public struct CognitiveMindCore: View {

    // MARK: - Properties

    let data: CognitiveDimensionData
    let breathingScale: CGFloat

    @State private var ring1Rotation: Double = 0
    @State private var ring2Rotation: Double = 0
    @State private var nucleusPulse: CGFloat = 1.0
    @State private var particlePhase: Double = 0
    @State private var isHovered: Bool = false
    @State private var currentHourPulse: Double = 1.0

    // MARK: - Layout Constants

    private enum Layout {
        static let totalSize: CGFloat = 280          // Total area
        static let coreSize: CGFloat = 120           // Core nucleus
        static let focusRingRadius: CGFloat = 120    // Outer ring
        static let loadRingRadius: CGFloat = 80      // Inner ring
        static let segmentCount: Int = 24            // Hours in a day
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            // Layer 1: Ambient Glow
            ambientGlow

            // Layer 2: Focus Stability Ring (outer, 24 segments)
            focusStabilityRing

            // Layer 3: Cognitive Load Ring (inner, with particles)
            cognitiveLoadRing

            // Layer 4: Core Nucleus
            coreNucleus

            // Layer 5: Level Display
            levelDisplay
        }
        .frame(width: Layout.totalSize, height: Layout.totalSize)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            startAnimations()
        }
    }

    // MARK: - Layer 1: Ambient Glow

    private var ambientGlow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        SanctuaryColors.Dimensions.cognitive.opacity(0.4),
                        SanctuaryColors.Dimensions.cognitive.opacity(0.1),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: Layout.totalSize / 2
                )
            )
            .frame(width: Layout.totalSize + 40, height: Layout.totalSize + 40)
            .blur(radius: 40)
            .opacity(0.3 + (data.focusIndex / 200))  // Brightness correlates to focus
            .scaleEffect(nucleusPulse * breathingScale)
    }

    // MARK: - Layer 2: Focus Stability Ring

    private var focusStabilityRing: some View {
        ZStack {
            // Track
            Circle()
                .stroke(
                    SanctuaryColors.Glass.border,
                    style: StrokeStyle(lineWidth: 6)
                )
                .frame(width: Layout.focusRingRadius * 2, height: Layout.focusRingRadius * 2)

            // 24 segments
            ForEach(0..<Layout.segmentCount, id: \.self) { hour in
                focusSegment(hour: hour)
            }

            // Current hour indicator
            currentHourIndicator
        }
        .rotationEffect(.degrees(-90))  // Start at top (12 o'clock)
        .rotationEffect(.degrees(ring1Rotation))
    }

    private func focusSegment(hour: Int) -> some View {
        let stability = data.focusStabilityByHour[hour] ?? 0
        let isSleep = hour < 6 || hour > 22
        let segmentAngle = 360.0 / Double(Layout.segmentCount)
        let gapAngle = 2.0  // Gap between segments

        let startAngle = Double(hour) * segmentAngle + gapAngle / 2
        let endAngle = Double(hour + 1) * segmentAngle - gapAngle / 2

        let color = segmentColor(stability: stability, isSleep: isSleep)

        return Circle()
            .trim(
                from: startAngle / 360,
                to: endAngle / 360
            )
            .stroke(
                color,
                style: StrokeStyle(lineWidth: 6, lineCap: .round)
            )
            .frame(width: Layout.focusRingRadius * 2, height: Layout.focusRingRadius * 2)
    }

    private func segmentColor(stability: Double, isSleep: Bool) -> Color {
        if isSleep { return SanctuaryColors.Glass.border }

        switch stability {
        case 80...: return SanctuaryColors.Semantic.success
        case 50..<80: return SanctuaryColors.Semantic.warning
        case 1...: return SanctuaryColors.Semantic.error
        default: return SanctuaryColors.Glass.border
        }
    }

    private var currentHourIndicator: some View {
        let currentHour = Calendar.current.component(.hour, from: Date())
        let segmentAngle = 360.0 / Double(Layout.segmentCount)
        let angle = Double(currentHour) * segmentAngle + segmentAngle / 2

        return Circle()
            .fill(Color.white)
            .frame(width: 10, height: 10)
            .offset(x: Layout.focusRingRadius)
            .rotationEffect(.degrees(angle))
            .scaleEffect(currentHourPulse)
            .shadow(color: Color.white.opacity(0.5), radius: 4)
    }

    // MARK: - Layer 3: Cognitive Load Ring

    private var cognitiveLoadRing: some View {
        ZStack {
            // Track
            Circle()
                .stroke(
                    loadGradient,
                    style: StrokeStyle(lineWidth: 4)
                )
                .frame(width: Layout.loadRingRadius * 2, height: Layout.loadRingRadius * 2)

            // Particle flow
            particleFlow
        }
        .rotationEffect(.degrees(-ring2Rotation))
    }

    private var loadGradient: AngularGradient {
        // Color based on current load: cyan (low) → red (high)
        let loadNormalized = data.cognitiveLoadCurrent / 100

        let startColor = Color(hex: "#22D3EE")  // Cyan
        let endColor = Color(hex: "#EF4444")    // Red
        let midColor = interpolateColor(from: startColor, to: endColor, progress: loadNormalized)

        return AngularGradient(
            colors: [
                midColor.opacity(0.3),
                midColor,
                midColor.opacity(0.8),
                midColor.opacity(0.3)
            ],
            center: .center,
            startAngle: .degrees(0),
            endAngle: .degrees(360)
        )
    }

    private var particleFlow: some View {
        ForEach(0..<12, id: \.self) { index in
            let baseAngle = Double(index) * 30
            let animatedAngle = baseAngle + particlePhase

            Circle()
                .fill(particleColor)
                .frame(width: particleSize(for: index), height: particleSize(for: index))
                .offset(x: Layout.loadRingRadius)
                .rotationEffect(.degrees(animatedAngle))
                .opacity(particleOpacity(for: index))
                .blur(radius: 1)
        }
    }

    private var particleColor: Color {
        let loadNormalized = data.cognitiveLoadCurrent / 100
        let cyan = Color(hex: "#22D3EE")
        let red = Color(hex: "#EF4444")
        return interpolateColor(from: cyan, to: red, progress: loadNormalized)
    }

    private func particleSize(for index: Int) -> CGFloat {
        CGFloat(4 + (index % 3) * 2)
    }

    private func particleOpacity(for index: Int) -> Double {
        0.5 + Double(index % 4) * 0.15
    }

    // MARK: - Layer 4: Core Nucleus

    private var coreNucleus: some View {
        ZStack {
            // Base radial gradient
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.9),
                            SanctuaryColors.Dimensions.cognitive.opacity(0.8),
                            SanctuaryColors.Dimensions.cognitive
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: Layout.coreSize
                    )
                )

            // Inner glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.6),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: Layout.coreSize * 0.3
                    )
                )

            // Animated plasma texture
            plasmaTexture

            // Highlight arc
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(
                    Color.white.opacity(0.3),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-45))
                .blur(radius: 2)
        }
        .frame(width: Layout.coreSize - 20, height: Layout.coreSize - 20)  // 100pt
        .scaleEffect(nucleusPulse * breathingScale)
        .shadow(color: Color.black.opacity(0.4), radius: 20, x: 0, y: 10)
        .shadow(color: SanctuaryColors.Dimensions.cognitive.opacity(0.5), radius: 25, x: 0, y: 0)
    }

    private var plasmaTexture: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate

            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.clear,
                            Color.white.opacity(0.1),
                            Color.clear,
                            Color.white.opacity(0.12),
                            Color.clear
                        ],
                        center: .center,
                        startAngle: .degrees(phase.truncatingRemainder(dividingBy: 360) * 8),
                        endAngle: .degrees(phase.truncatingRemainder(dividingBy: 360) * 8 + 360)
                    )
                )
                .rotationEffect(.degrees(phase.truncatingRemainder(dividingBy: 360) * 3))
        }
    }

    // MARK: - Layer 5: Level Display

    private var levelDisplay: some View {
        VStack(spacing: SanctuaryLayout.Spacing.xs) {
            // NELO indicator
            Text("NELO")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.secondary)

            // Score value
            Text(String(format: "%.1f", data.neloScore))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(SanctuaryColors.Text.primary)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)

            // Status indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(neloStatusColor)
                    .frame(width: 6, height: 6)

                Text(data.neloStatus.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(neloStatusColor)
            }
        }
    }

    private var neloStatusColor: Color {
        switch data.neloStatus {
        case .balanced: return SanctuaryColors.Semantic.success
        case .elevated: return SanctuaryColors.Semantic.warning
        case .depleted: return SanctuaryColors.Semantic.error
        }
    }

    // MARK: - Animation

    private func startAnimations() {
        // Nucleus pulse synced to NELO rhythm (3s cycle per spec)
        withAnimation(
            .easeInOut(duration: 3)
            .repeatForever(autoreverses: true)
        ) {
            nucleusPulse = 1.02
        }

        // Focus ring rotation (CW @ 30s per spec)
        withAnimation(.linear(duration: 30).repeatForever(autoreverses: false)) {
            ring1Rotation = 360
        }

        // Load ring counter-rotation (CCW @ 45s per spec)
        withAnimation(.linear(duration: 45).repeatForever(autoreverses: false)) {
            ring2Rotation = 360
        }

        // Particle flow speed proportional to cognitive load
        let particleSpeed = max(10, 30 - (data.cognitiveLoadCurrent / 5))
        withAnimation(.linear(duration: particleSpeed).repeatForever(autoreverses: false)) {
            particlePhase = 360
        }

        // Current hour indicator pulse
        withAnimation(
            .easeInOut(duration: 1)
            .repeatForever(autoreverses: true)
        ) {
            currentHourPulse = 1.15
        }
    }

    // MARK: - Helpers

    private func interpolateColor(from: Color, to: Color, progress: Double) -> Color {
        // Simple linear interpolation
        let p = min(1, max(0, progress))
        return Color(
            red: lerp(from.components.red, to.components.red, p),
            green: lerp(from.components.green, to.components.green, p),
            blue: lerp(from.components.blue, to.components.blue, p)
        )
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}

// MARK: - Color Components Extension

private extension Color {
    var components: (red: Double, green: Double, blue: Double, opacity: Double) {
        #if canImport(UIKit)
        typealias NativeColor = UIColor
        #elseif canImport(AppKit)
        typealias NativeColor = NSColor
        #endif

        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        #if canImport(UIKit)
        guard NativeColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return (0, 0, 0, 0)
        }
        #elseif canImport(AppKit)
        let color = NativeColor(self).usingColorSpace(.sRGB) ?? NativeColor(self)
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif

        return (Double(r), Double(g), Double(b), Double(a))
    }
}

// MARK: - NELO Waveform View

/// Real-time NELO waveform visualization
public struct NELOWaveformView: View {

    let waveformData: [Double]
    let status: NELOStatus

    @State private var animationPhase: CGFloat = 0

    public var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            Path { path in
                guard waveformData.count > 1 else { return }

                let stepX = width / CGFloat(waveformData.count - 1)
                let midY = height / 2
                let amplitude = height * 0.35

                path.move(to: CGPoint(x: 0, y: midY))

                for (index, value) in waveformData.enumerated() {
                    let x = CGFloat(index) * stepX
                    let normalizedValue = (value - 30) / 40  // Normalize around 30-70 range
                    let y = midY - CGFloat(normalizedValue) * amplitude

                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(
                LinearGradient(
                    colors: [statusColor.opacity(0.5), statusColor, statusColor.opacity(0.5)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
            .shadow(color: statusColor.opacity(0.4), radius: 4)
        }
    }

    private var statusColor: Color {
        switch status {
        case .balanced: return SanctuaryColors.Semantic.success
        case .elevated: return SanctuaryColors.Semantic.warning
        case .depleted: return SanctuaryColors.Semantic.error
        }
    }
}

// MARK: - NELO Score Card

/// Card showing NELO score with waveform
public struct NELOScoreCard: View {

    let data: CognitiveDimensionData
    @State private var isHovered: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            HStack {
                Text("NELO SCORE")
                    .font(SanctuaryTypography.label)
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Spacer()

                // Status badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)

                    Text(data.neloStatus.displayName)
                        .font(SanctuaryTypography.label)
                        .foregroundColor(statusColor)
                }
            }

            // Waveform
            NELOWaveformView(
                waveformData: data.neloWaveform,
                status: data.neloStatus
            )
            .frame(height: 40)

            // Score
            HStack {
                Text(String(format: "%.1f", data.neloScore))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Spacer()

                // Optimal range indicator
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Optimal")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                    Text("35-55")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.secondary)
                }
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
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var statusColor: Color {
        switch data.neloStatus {
        case .balanced: return SanctuaryColors.Semantic.success
        case .elevated: return SanctuaryColors.Semantic.warning
        case .depleted: return SanctuaryColors.Semantic.error
        }
    }
}

// MARK: - Focus Index Card

/// Card showing current focus index with progress
public struct FocusIndexCard: View {

    let data: CognitiveDimensionData
    @State private var isHovered: Bool = false
    @State private var progressAnimated: Double = 0

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            HStack {
                Text("FOCUS INDEX")
                    .font(SanctuaryTypography.label)
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Spacer()

                // Peak indicator
                if data.focusIndex >= 80 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(SanctuaryColors.Semantic.success)
                            .frame(width: 6, height: 6)

                        Text("Peak")
                            .font(SanctuaryTypography.label)
                            .foregroundColor(SanctuaryColors.Semantic.success)
                    }
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SanctuaryColors.Glass.border)
                        .frame(height: 8)

                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(focusGradient)
                        .frame(width: geometry.size.width * progressAnimated, height: 8)
                }
            }
            .frame(height: 8)

            // Score
            HStack(alignment: .bottom) {
                Text("\(Int(data.focusIndex))")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text("%")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.secondary)
                    .offset(y: -4)

                Spacer()

                // Cognitive load indicator
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Load")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                    Text("\(Int(data.cognitiveLoadCurrent))%")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(loadColor)
                }
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
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                progressAnimated = data.focusIndex / 100
            }
        }
    }

    private var focusGradient: LinearGradient {
        LinearGradient(
            colors: [
                SanctuaryColors.Dimensions.cognitive,
                SanctuaryColors.Dimensions.cognitive.opacity(0.8)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var loadColor: Color {
        switch data.cognitiveLoadCurrent {
        case 0..<50: return SanctuaryColors.Semantic.success
        case 50..<75: return SanctuaryColors.Semantic.warning
        default: return SanctuaryColors.Semantic.error
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CognitiveMindCore_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                CognitiveMindCore(
                    data: .preview,
                    breathingScale: 1.0
                )

                HStack(spacing: 16) {
                    NELOScoreCard(data: .preview)
                        .frame(width: 180)

                    FocusIndexCard(data: .preview)
                        .frame(width: 180)
                }
            }
        }
    }
}
#endif
