// CosmoOS/UI/FocusMode/SwipeStudy/EmotionalArcView.swift
// Emotional arc visualization for Swipe Study Focus Mode
// February 2026

import SwiftUI

// MARK: - Emotional Arc View

struct EmotionalArcView: View {
    let dataPoints: [EmotionDataPoint]
    let dominantEmotion: SwipeEmotion?
    var onSeek: ((Double) -> Void)?
    var transcriptText: String = ""

    @State private var lineProgress: CGFloat = 0
    @State private var hasAppeared = false
    @State private var hoveredPointID: String?

    private let chartHeight: CGFloat = 140
    private let gridLineCount = 5

    /// Set of data point IDs that represent emotion transitions (key moments)
    private var transitionPointIDs: Set<String> {
        let sorted = dataPoints.sorted { $0.position < $1.position }
        guard !sorted.isEmpty else { return [] }

        var ids: Set<String> = []
        // First point is always a transition
        ids.insert(sorted[0].id)
        for i in 1..<sorted.count {
            if sorted[i].emotion != sorted[i - 1].emotion {
                ids.insert(sorted[i].id)
            }
        }
        return ids
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text("EMOTIONAL ARC")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.4))
                .textCase(.uppercase)

            if dataPoints.isEmpty {
                placeholderView
            } else {
                chartView
            }
        }
        .padding(16)
        .background(Color(hex: "#1A1A25"), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            withAnimation(.easeInOut(duration: 1.2)) {
                lineProgress = 1.0
            }
        }
    }

    // MARK: - Chart View

    private var chartView: some View {
        VStack(spacing: 8) {
            // Chart area
            GeometryReader { geo in
                let width = geo.size.width
                let height = chartHeight

                ZStack(alignment: .topLeading) {
                    // Grid lines
                    ForEach(0..<gridLineCount, id: \.self) { i in
                        let y = height * CGFloat(i) / CGFloat(gridLineCount - 1)
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: width, y: y))
                        }
                        .stroke(Color.white.opacity(0.04), lineWidth: 1)
                    }

                    // Line path
                    let linePath = buildLinePath(width: width, height: height)
                    linePath
                        .trim(from: 0, to: lineProgress)
                        .stroke(
                            lineColor,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                        )

                    // Data point dots with hover + click
                    ForEach(dataPoints) { point in
                        let x = point.position * width
                        let y = (1.0 - point.intensity) * height
                        let isHovered = hoveredPointID == point.id
                        let isTransition = transitionPointIDs.contains(point.id)
                        let baseSize: CGFloat = isTransition ? 8 : 6
                        let dotSize: CGFloat = isHovered ? max(baseSize, 8) + 2 : baseSize

                        EmotionalArcDot(
                            point: point,
                            dotSize: dotSize,
                            isHovered: isHovered,
                            isTransition: isTransition,
                            transcriptExcerpt: transcriptExcerpt(at: point.position),
                            onHoverChanged: { hovering in
                                withAnimation(ProMotionSprings.hover) {
                                    hoveredPointID = hovering ? point.id : nil
                                }
                            },
                            onTap: {
                                onSeek?(point.position)
                            }
                        )
                        .position(x: x, y: y)
                        .opacity(Double(lineProgress))
                        .zIndex(isHovered ? 10 : (isTransition ? 5 : 1))
                    }
                }
            }
            .frame(height: chartHeight)

            // Emotion labels at key transition points
            emotionLabels
        }
    }

    private var lineColor: Color {
        dominantEmotion?.color ?? .white
    }

    private func buildLinePath(width: CGFloat, height: CGFloat) -> Path {
        let sorted = dataPoints.sorted { $0.position < $1.position }
        guard sorted.count >= 2 else {
            return Path { path in
                if let first = sorted.first {
                    let x = first.position * width
                    let y = (1.0 - first.intensity) * height
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x + 1, y: y))
                }
            }
        }

        return Path { path in
            let firstPoint = CGPoint(
                x: sorted[0].position * width,
                y: (1.0 - sorted[0].intensity) * height
            )
            path.move(to: firstPoint)

            for i in 1..<sorted.count {
                let current = CGPoint(
                    x: sorted[i].position * width,
                    y: (1.0 - sorted[i].intensity) * height
                )
                let prev = CGPoint(
                    x: sorted[i - 1].position * width,
                    y: (1.0 - sorted[i - 1].intensity) * height
                )
                let controlX = (prev.x + current.x) / 2
                path.addCurve(
                    to: current,
                    control1: CGPoint(x: controlX, y: prev.y),
                    control2: CGPoint(x: controlX, y: current.y)
                )
            }
        }
    }

    private var emotionLabels: some View {
        HStack(spacing: 0) {
            // Show labels at key transition points
            let transitions = findTransitions()
            ForEach(transitions, id: \.position) { point in
                Text(point.emotion.displayName)
                    .font(.system(size: 10))
                    .foregroundColor(point.emotion.color)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Find points where the emotion changes
    private func findTransitions() -> [EmotionDataPoint] {
        let sorted = dataPoints.sorted { $0.position < $1.position }
        guard !sorted.isEmpty else { return [] }

        var result: [EmotionDataPoint] = [sorted[0]]
        for i in 1..<sorted.count {
            if sorted[i].emotion != sorted[i - 1].emotion {
                result.append(sorted[i])
            }
        }
        // Always include the last point if different from last added
        if let last = sorted.last, last.emotion != result.last?.emotion {
            result.append(last)
        }
        // Cap at 5 labels to avoid crowding
        if result.count > 5 {
            let stride = result.count / 5
            result = (0..<5).map { result[min($0 * stride, result.count - 1)] }
        }
        return result
    }

    // MARK: - Transcript Excerpt

    private func transcriptExcerpt(at position: Double) -> String? {
        guard !transcriptText.isEmpty else { return nil }
        let charIndex = Int(position * Double(transcriptText.count))
        let start = max(0, charIndex - 40)
        let end = min(transcriptText.count, charIndex + 40)
        guard start < end else { return nil }
        let startIdx = transcriptText.index(transcriptText.startIndex, offsetBy: start)
        let endIdx = transcriptText.index(transcriptText.startIndex, offsetBy: end)
        var excerpt = String(transcriptText[startIdx..<endIdx])
        if start > 0 { excerpt = "..." + excerpt }
        if end < transcriptText.count { excerpt = excerpt + "..." }
        return excerpt
    }

    // MARK: - Placeholder

    private var placeholderView: some View {
        Text("Analysis pending...")
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(0.3))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
    }
}

// MARK: - Emotional Arc Dot

/// Individual dot on the emotional arc chart with hover tooltip and click-to-seek.
/// Extracted as a standalone view so each dot can independently track its own hover state.
private struct EmotionalArcDot: View {
    let point: EmotionDataPoint
    let dotSize: CGFloat
    let isHovered: Bool
    let isTransition: Bool
    let transcriptExcerpt: String?
    let onHoverChanged: (Bool) -> Void
    let onTap: () -> Void

    var body: some View {
        Circle()
            .fill(point.emotion.color)
            .frame(width: dotSize, height: dotSize)
            .shadow(
                color: isHovered ? point.emotion.color.opacity(0.6) : .clear,
                radius: isHovered ? 6 : 0
            )
            .overlay(
                // Outer ring on transition points for emphasis
                Circle()
                    .stroke(point.emotion.color.opacity(isTransition && !isHovered ? 0.3 : 0), lineWidth: 1.5)
                    .frame(width: dotSize + 4, height: dotSize + 4)
            )
            .contentShape(Circle().size(width: 24, height: 24).offset(.init(width: -12 + dotSize / 2, height: -12 + dotSize / 2)))
            .onHover { hovering in
                onHoverChanged(hovering)
            }
            .onTapGesture {
                onTap()
            }
            .popover(isPresented: .constant(isHovered), arrowEdge: .top) {
                EmotionalArcTooltip(point: point, transcriptExcerpt: transcriptExcerpt)
            }
            .animation(ProMotionSprings.hover, value: isHovered)
    }
}

// MARK: - Tooltip View

/// Dark-themed tooltip shown when hovering over an emotional arc data point.
private struct EmotionalArcTooltip: View {
    let point: EmotionDataPoint
    var transcriptExcerpt: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Emotion name with icon
            HStack(spacing: 6) {
                Image(systemName: point.emotion.iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(point.emotion.color)

                Text(point.emotion.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
            }

            // Accent bar
            RoundedRectangle(cornerRadius: 1)
                .fill(point.emotion.color)
                .frame(height: 2)
                .frame(maxWidth: .infinity)

            // Intensity row
            HStack(spacing: 4) {
                Text("Intensity")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Text(String(format: "%.1f", point.intensity))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
            }

            // Position row
            HStack(spacing: 4) {
                Text("Position")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Text("\(Int(point.position * 100))% through content")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }

            // Transcript excerpt
            if let excerpt = transcriptExcerpt {
                Text(excerpt)
                    .font(.system(size: 11))
                    .italic()
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(width: 190)
        .background(Color(hex: "#1A1A25"))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#if DEBUG
struct EmotionalArcView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color(hex: "#0A0A0F").ignoresSafeArea()
            EmotionalArcView(
                dataPoints: [
                    EmotionDataPoint(position: 0.0, intensity: 0.6, emotion: .curiosity),
                    EmotionDataPoint(position: 0.2, intensity: 0.8, emotion: .curiosity),
                    EmotionDataPoint(position: 0.4, intensity: 0.5, emotion: .aspiration),
                    EmotionDataPoint(position: 0.6, intensity: 0.9, emotion: .urgency),
                    EmotionDataPoint(position: 0.8, intensity: 0.7, emotion: .desire),
                    EmotionDataPoint(position: 1.0, intensity: 0.95, emotion: .awe),
                ],
                dominantEmotion: .curiosity,
                onSeek: { position in
                    print("Seek to \(position)")
                }
            )
            .frame(width: 400)
            .padding()
        }
    }
}
#endif
