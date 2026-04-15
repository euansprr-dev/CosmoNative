// CosmoOS/UI/FocusMode/Content/AIWritingProgressView.swift
// Atmospheric writing-in-progress view for AI draft generation
// Replaces basic spinner with a premium, warm, alive experience
// April 2026

import SwiftUI

// MARK: - Writing Phase

private enum WritingPhase: CaseIterable {
    case analyzing, planning, writing, refining, finishing

    var label: String {
        switch self {
        case .analyzing: "Analyzing your idea..."
        case .planning: "Planning structure..."
        case .writing: "Writing your draft..."
        case .refining: "Refining and polishing..."
        case .finishing: "Almost there..."
        }
    }

    static func from(elapsedSeconds: Int) -> WritingPhase {
        switch elapsedSeconds {
        case 0..<5: .analyzing
        case 5..<15: .planning
        case 15..<35: .writing
        case 35..<60: .refining
        default: .finishing
        }
    }
}

// MARK: - Seeded Line Widths

/// Deterministic line width pattern so we never trigger re-renders from randomness.
private let lineWidthPattern: [CGFloat] = [
    0.92, 0.78, 0.85, 0.63, 0.95, 0.71, 0.88, 0.67, 0.82, 0.74, 0.91, 0.60
]

// MARK: - AIWritingProgressView

struct AIWritingProgressView: View {
    @State private var currentPhase: WritingPhase = .analyzing
    @State private var elapsedSeconds: Int = 0
    @State private var visibleLineCount: Int = 0
    @State private var glowPulsing: Bool = false
    @State private var cursorVisible: Bool = true

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: DS.space24) {
            Spacer()
            phaseHeader
            simulatedTextBlock
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .filmGrain(opacity: 0.018)
        .onAppear { startAnimations() }
        .onReceive(timer) { _ in tick() }
    }
}

// MARK: - Subviews

private extension AIWritingProgressView {

    var phaseHeader: some View {
        ZStack {
            ambientGlow
            VStack(spacing: DS.space8) {
                phaseLabel
                elapsedTimeLabel
            }
        }
    }

    var ambientGlow: some View {
        Circle()
            .fill(DS.accent.opacity(0.15))
            .frame(width: 180, height: 180)
            .blur(radius: 40)
            .scaleEffect(glowPulsing ? 1.15 : 0.9)
            .opacity(glowPulsing ? 1.0 : 0.6)
            .animation(
                .easeInOut(duration: 2.5).repeatForever(autoreverses: true),
                value: glowPulsing
            )
    }

    var phaseLabel: some View {
        Text(currentPhase.label)
            .font(DS.headline)
            .foregroundStyle(DS.text)
            .contentTransition(.opacity)
            .animation(ProMotionSprings.gentle, value: currentPhase)
    }

    var elapsedTimeLabel: some View {
        Text("\(elapsedSeconds) seconds...")
            .font(DS.caption)
            .monospacedDigit()
            .foregroundStyle(DS.textMuted)
    }

    var simulatedTextBlock: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            ForEach(0..<visibleLineCount, id: \.self) { index in
                simulatedLine(at: index)
            }
        }
        .frame(maxWidth: 480, alignment: .leading)
        .padding(.horizontal, DS.space32)
    }

    func simulatedLine(at index: Int) -> some View {
        let isLatest = index == visibleLineCount - 1
        let widthFraction = lineWidthPattern[index % lineWidthPattern.count]

        return HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: DS.radiusXSmall)
                .fill(DS.textMuted.opacity(0.08))
                .frame(height: 10)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .scaleEffect(x: widthFraction, y: 1, anchor: .leading)

            if isLatest {
                blinkingCursor
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }

    var blinkingCursor: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(CosmoMentionColors.content)
            .frame(width: 2, height: 14)
            .opacity(cursorVisible ? 1.0 : 0.0)
            .animation(
                .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                value: cursorVisible
            )
    }
}

// MARK: - Logic

private extension AIWritingProgressView {

    func startAnimations() {
        glowPulsing = true
        cursorVisible = false
    }

    func tick() {
        elapsedSeconds += 1

        let newPhase = WritingPhase.from(elapsedSeconds: elapsedSeconds)
        if newPhase != currentPhase {
            withAnimation(ProMotionSprings.gentle) {
                currentPhase = newPhase
            }
        }

        // Add a new simulated line every ~2.5 seconds, capped at 12
        if elapsedSeconds % 2 == 0, elapsedSeconds > 1, visibleLineCount < lineWidthPattern.count {
            withAnimation(ProMotionSprings.cardEntrance) {
                visibleLineCount += 1
            }
        }
    }
}

// MARK: - Equatable Conformance for Phase Animation

extension WritingPhase: Equatable {}

#Preview {
    AIWritingProgressView()
        .frame(width: 600, height: 500)
        .background(DS.bg)
}
