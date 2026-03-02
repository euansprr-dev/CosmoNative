// CosmoOS/UI/Sanctuary/Dimensions/Physiological/PhysiologicalBodyScanner.swift
// Body Scanner - Holographic body visualization with muscle recovery heatmap
// Phase 5: Following SANCTUARY_UI_SPEC_V2.md section 3.3

import SwiftUI

// MARK: - Body Scanner

/// Holographic body visualization with interactive muscle groups
public struct PhysiologicalBodyScanner: View {

    // MARK: - Properties

    let muscleMap: [MuscleStatus]
    let stressLevel: Double
    let cortisolEstimate: CortisolLevel
    let breathingRate: Double
    let currentHRV: Double
    let onMuscleTap: ((MuscleStatus) -> Void)?

    @State private var isVisible: Bool = false
    @State private var rotationAngle: Double = 0
    @State private var selectedMuscle: MuscleGroup?
    @State private var breathingPhase: CGFloat = 0
    @State private var hrvWavePhase: CGFloat = 0
    @State private var isHovered: Bool = false

    // MARK: - Initialization

    public init(
        muscleMap: [MuscleStatus],
        stressLevel: Double,
        cortisolEstimate: CortisolLevel,
        breathingRate: Double,
        currentHRV: Double,
        onMuscleTap: ((MuscleStatus) -> Void)? = nil
    ) {
        self.muscleMap = muscleMap
        self.stressLevel = stressLevel
        self.cortisolEstimate = cortisolEstimate
        self.breathingRate = breathingRate
        self.currentHRV = currentHRV
        self.onMuscleTap = onMuscleTap
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            Text("Holographic Body Scanner")
                .font(OnyxTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            HStack(alignment: .top, spacing: SanctuaryLayout.Spacing.xl) {
                // Body visualization
                bodyVisualization
                    .frame(width: 280, height: 400)

                // Info panels
                VStack(spacing: SanctuaryLayout.Spacing.lg) {
                    stressZonePanel
                    breathingPanel
                    hrvWavePanel
                }
                .frame(maxWidth: 200)
            }

            // Controls
            controlsRow

            // Legend
            legendRow
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
        .offset(y: isVisible ? 0 : 20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.1)) {
                isVisible = true
            }
            startAnimations()
        }
    }

    // MARK: - Body Visualization

    private var bodyVisualization: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                // Background glow
                RadialGradient(
                    colors: [
                        SanctuaryColors.Dimensions.physiological.opacity(0.15),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 50,
                    endRadius: 200
                )

                // Body silhouette
                bodyPath(width: width, height: height)
                    .fill(
                        LinearGradient(
                            colors: [
                                SanctuaryColors.Glass.highlight,
                                SanctuaryColors.Dimensions.physiological.opacity(0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        bodyPath(width: width, height: height)
                            .stroke(
                                SanctuaryColors.Dimensions.physiological.opacity(0.5),
                                lineWidth: 1
                            )
                    )

                // Muscle overlays
                ForEach(muscleMap) { muscle in
                    muscleOverlay(for: muscle, width: width, height: height)
                }

                // Breathing animation around chest
                breathingWave(width: width, height: height)

                // HRV wave overlay
                hrvWaveOverlay(width: width, height: height)

                // Scan line effect
                scanLineEffect(height: height)
            }
            .rotation3DEffect(
                .degrees(rotationAngle),
                axis: (x: 0, y: 1, z: 0)
            )
        }
    }

    private func bodyPath(width: CGFloat, height: CGFloat) -> Path {
        let centerX = width / 2

        return Path { path in
            // Head
            path.addEllipse(in: CGRect(
                x: centerX - 25,
                y: height * 0.05,
                width: 50,
                height: 60
            ))

            // Neck
            path.move(to: CGPoint(x: centerX - 12, y: height * 0.13))
            path.addLine(to: CGPoint(x: centerX - 12, y: height * 0.17))
            path.addLine(to: CGPoint(x: centerX + 12, y: height * 0.17))
            path.addLine(to: CGPoint(x: centerX + 12, y: height * 0.13))

            // Torso
            path.move(to: CGPoint(x: centerX - 45, y: height * 0.17))
            path.addQuadCurve(
                to: CGPoint(x: centerX - 35, y: height * 0.48),
                control: CGPoint(x: centerX - 50, y: height * 0.32)
            )
            path.addLine(to: CGPoint(x: centerX + 35, y: height * 0.48))
            path.addQuadCurve(
                to: CGPoint(x: centerX + 45, y: height * 0.17),
                control: CGPoint(x: centerX + 50, y: height * 0.32)
            )
            path.closeSubpath()

            // Left arm
            path.move(to: CGPoint(x: centerX - 45, y: height * 0.17))
            path.addQuadCurve(
                to: CGPoint(x: centerX - 70, y: height * 0.45),
                control: CGPoint(x: centerX - 65, y: height * 0.28)
            )
            path.addLine(to: CGPoint(x: centerX - 55, y: height * 0.45))
            path.addQuadCurve(
                to: CGPoint(x: centerX - 45, y: height * 0.22),
                control: CGPoint(x: centerX - 50, y: height * 0.30)
            )

            // Right arm
            path.move(to: CGPoint(x: centerX + 45, y: height * 0.17))
            path.addQuadCurve(
                to: CGPoint(x: centerX + 70, y: height * 0.45),
                control: CGPoint(x: centerX + 65, y: height * 0.28)
            )
            path.addLine(to: CGPoint(x: centerX + 55, y: height * 0.45))
            path.addQuadCurve(
                to: CGPoint(x: centerX + 45, y: height * 0.22),
                control: CGPoint(x: centerX + 50, y: height * 0.30)
            )

            // Left leg
            path.move(to: CGPoint(x: centerX - 35, y: height * 0.48))
            path.addLine(to: CGPoint(x: centerX - 40, y: height * 0.92))
            path.addLine(to: CGPoint(x: centerX - 15, y: height * 0.92))
            path.addLine(to: CGPoint(x: centerX - 8, y: height * 0.48))

            // Right leg
            path.move(to: CGPoint(x: centerX + 35, y: height * 0.48))
            path.addLine(to: CGPoint(x: centerX + 40, y: height * 0.92))
            path.addLine(to: CGPoint(x: centerX + 15, y: height * 0.92))
            path.addLine(to: CGPoint(x: centerX + 8, y: height * 0.48))
        }
    }

    private func muscleOverlay(for muscle: MuscleStatus, width: CGFloat, height: CGFloat) -> some View {
        let position = muscle.muscleGroup.bodyPosition
        let x = width * position.x
        let y = height * position.y
        let isSelected = selectedMuscle == muscle.muscleGroup

        return ZStack {
            // Muscle indicator
            Circle()
                .fill(muscle.statusColor.opacity(isSelected ? 0.9 : 0.6))
                .frame(width: isSelected ? 28 : 22, height: isSelected ? 28 : 22)
                .shadow(color: muscle.statusColor.opacity(0.5), radius: isSelected ? 10 : 5)

            // Percentage label
            Text("\(Int(muscle.recoveryPercent))%")
                .font(.system(size: isSelected ? 9 : 7, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .position(x: x, y: y)
        .animation(SanctuarySprings.hover, value: isSelected)
        .onTapGesture {
            withAnimation(SanctuarySprings.snappy) {
                if selectedMuscle == muscle.muscleGroup {
                    selectedMuscle = nil
                } else {
                    selectedMuscle = muscle.muscleGroup
                }
            }
            onMuscleTap?(muscle)
        }
    }

    private func breathingWave(width: CGFloat, height: CGFloat) -> some View {
        let centerX = width / 2
        let chestY = height * 0.28

        return Ellipse()
            .stroke(
                SanctuaryColors.Semantic.info.opacity(0.4),
                style: StrokeStyle(lineWidth: 2, dash: [8, 4])
            )
            .frame(
                width: 80 + 10 * sin(breathingPhase),
                height: 40 + 5 * sin(breathingPhase)
            )
            .position(x: centerX, y: chestY)
    }

    private func hrvWaveOverlay(width: CGFloat, height: CGFloat) -> some View {
        let centerX = width / 2
        let chestY = height * 0.32

        return Path { path in
            let waveWidth: CGFloat = 80
            let startX = centerX - waveWidth / 2

            for i in 0..<Int(waveWidth) {
                let x = startX + CGFloat(i)
                let progress = CGFloat(i) / waveWidth
                let y = chestY + 8 * sin(progress * .pi * 4 + hrvWavePhase)

                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(
            SanctuaryColors.Dimensions.physiological,
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
        )
    }

    private func scanLineEffect(height: CGFloat) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.clear,
                        SanctuaryColors.Dimensions.physiological.opacity(0.3),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: 4)
            .offset(y: -height / 2 + (height * CGFloat(Int(Date().timeIntervalSince1970) % 100) / 100))
            .animation(.linear(duration: 3).repeatForever(autoreverses: false), value: Date())
    }

    // MARK: - Info Panels

    private var stressZonePanel: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            Text("Stress Zone")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            HStack {
                // Stress bar
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(SanctuaryColors.Glass.highlight)
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(stressColor)
                        .frame(width: CGFloat(stressLevel) / 100 * 120, height: 8)
                }
                .frame(width: 120)

                Text("\(Int(stressLevel))%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }

            // Cortisol indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: cortisolEstimate.color))
                    .frame(width: 6, height: 6)

                Text("CORTISOL: \(cortisolEstimate.displayName.uppercased())")
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                .fill(SanctuaryColors.Glass.highlight)
        )
    }

    private var stressColor: Color {
        if stressLevel < 30 { return SanctuaryColors.Semantic.success }
        if stressLevel < 50 { return SanctuaryColors.Semantic.info }
        if stressLevel < 70 { return SanctuaryColors.Semantic.warning }
        return SanctuaryColors.Semantic.error
    }

    private var breathingPanel: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            Text("Breathing")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            // Breathing wave visualization
            HStack(spacing: 4) {
                ForEach(0..<8, id: \.self) { i in
                    let height = 12 + 8 * sin(breathingPhase + CGFloat(i) * 0.5)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(SanctuaryColors.Semantic.info)
                        .frame(width: 4, height: height)
                }
            }

            Text("\(String(format: "%.1f", breathingRate)) breaths/min")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(SanctuaryColors.Text.primary)
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                .fill(SanctuaryColors.Glass.highlight)
        )
    }

    private var hrvWavePanel: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            Text("HRV Wave")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(1)

            // HRV value
            HStack(spacing: SanctuaryLayout.Spacing.sm) {
                Text("\(Int(currentHRV))ms")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Dimensions.physiological)

                Text("Live")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(SanctuaryColors.Semantic.success)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(SanctuaryColors.Semantic.success.opacity(0.2))
                    )
            }

            // Mini HRV wave
            GeometryReader { geometry in
                Path { path in
                    let width = geometry.size.width
                    let height = geometry.size.height

                    for i in 0..<Int(width) {
                        let x = CGFloat(i)
                        let y = height / 2 + 8 * sin(CGFloat(i) / 10 + hrvWavePhase)

                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(
                    SanctuaryColors.Dimensions.physiological,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
            }
            .frame(height: 20)
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                .fill(SanctuaryColors.Glass.highlight)
        )
    }

    // MARK: - Controls

    private var controlsRow: some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            controlButton(icon: "arrow.left", label: "Rotate") {
                withAnimation(.easeInOut(duration: 0.5)) {
                    rotationAngle -= 45
                }
            }

            controlButton(icon: "arrow.2.circlepath", label: "360°") {
                withAnimation(.easeInOut(duration: 2)) {
                    rotationAngle += 360
                }
            }

            controlButton(icon: "plus.magnifyingglass", label: "Zoom") {
                // Zoom functionality
            }

            controlButton(icon: "arrow.counterclockwise", label: "Reset") {
                withAnimation(.easeInOut(duration: 0.3)) {
                    rotationAngle = 0
                    selectedMuscle = nil
                }
            }

            Spacer()
        }
    }

    private func controlButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))

                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(SanctuaryColors.Text.secondary)
            .padding(.horizontal, SanctuaryLayout.Spacing.sm)
            .padding(.vertical, SanctuaryLayout.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                    .fill(SanctuaryColors.Glass.highlight)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Legend

    private var legendRow: some View {
        HStack(spacing: SanctuaryLayout.Spacing.lg) {
            legendItem(color: Color(hex: "#22C55E"), label: "80%+ Ready")
            legendItem(color: Color(hex: "#84CC16"), label: "60-80% Good")
            legendItem(color: Color(hex: "#F59E0B"), label: "40-60% Moderate")
            legendItem(color: Color(hex: "#EF4444"), label: "<40% Fatigued")

            Spacer()
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 8)

            Text(label)
                .font(.system(size: 9))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
    }

    // MARK: - Animations

    private func startAnimations() {
        // Breathing animation
        withAnimation(
            .easeInOut(duration: 4)
            .repeatForever(autoreverses: true)
        ) {
            breathingPhase = .pi * 2
        }

        // HRV wave animation
        withAnimation(
            .linear(duration: 2)
            .repeatForever(autoreverses: false)
        ) {
            hrvWavePhase = .pi * 2
        }
    }
}

// MARK: - Muscle Detail Panel

/// Detail panel for selected muscle group
public struct MuscleDetailPanel: View {

    let muscle: MuscleStatus
    let onDismiss: () -> Void

    @State private var isVisible: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(muscle.muscleGroup.displayName.uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(SanctuaryColors.Text.primary)
                        .tracking(1)

                    Text(muscle.statusText)
                        .font(.system(size: 12))
                        .foregroundColor(muscle.statusColor)
                }

                Spacer()

                Button(action: {
                    withAnimation(SanctuarySprings.snappy) {
                        onDismiss()
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Recovery progress
            VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
                HStack {
                    Text("Recovery")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Spacer()

                    Text("\(Int(muscle.recoveryPercent))%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.primary)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(SanctuaryColors.Glass.highlight)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [muscle.statusColor.opacity(0.8), muscle.statusColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * muscle.recoveryPercent / 100)
                    }
                }
                .frame(height: 6)
            }

            // Stats
            HStack(spacing: SanctuaryLayout.Spacing.lg) {
                statBlock(label: "Strain", value: muscle.strain.displayName)

                if let lastWorked = muscle.lastWorked {
                    statBlock(label: "Last Worked", value: formatDate(lastWorked))
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(muscle.statusColor.opacity(0.5), lineWidth: 1)
                )
        )
        .shadow(color: muscle.statusColor.opacity(0.2), radius: 10)
        .scaleEffect(isVisible ? 1 : 0.9)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(SanctuarySprings.gentle) {
                isVisible = true
            }
        }
    }

    private func statBlock(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(SanctuaryColors.Text.primary)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let days = calendar.dateComponents([.day], from: date, to: Date()).day ?? 0
            return "\(days)d ago"
        }
    }
}

// MARK: - Compact Body Scanner

/// Smaller version for embedding in other views
public struct BodyScannerCompact: View {

    let muscleMap: [MuscleStatus]

    public init(muscleMap: [MuscleStatus]) {
        self.muscleMap = muscleMap
    }

    public var body: some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            // Mini body icon
            Image(systemName: "figure.stand")
                .font(.system(size: 24))
                .foregroundColor(SanctuaryColors.Dimensions.physiological)

            // Recovery summary
            VStack(alignment: .leading, spacing: 2) {
                Text("Muscle Recovery")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                let avgRecovery = muscleMap.reduce(0.0) { $0 + $1.recoveryPercent } / Double(max(1, muscleMap.count))
                Text("\(Int(avgRecovery))% avg")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }

            Spacer()

            // Fatigue count
            let fatigued = muscleMap.filter { $0.recoveryPercent < 50 }.count
            if fatigued > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Semantic.warning)

                    Text("\(fatigued) fatigued")
                        .font(.system(size: 10))
                        .foregroundColor(SanctuaryColors.Semantic.warning)
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

// MARK: - Preview

#if DEBUG
struct PhysiologicalBodyScanner_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                PhysiologicalBodyScanner(
                    muscleMap: PhysiologicalDimensionData.preview.muscleRecoveryMap,
                    stressLevel: 34,
                    cortisolEstimate: .low,
                    breathingRate: 14.2,
                    currentHRV: 48
                )

                BodyScannerCompact(
                    muscleMap: PhysiologicalDimensionData.preview.muscleRecoveryMap
                )
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 700)
    }
}
#endif
