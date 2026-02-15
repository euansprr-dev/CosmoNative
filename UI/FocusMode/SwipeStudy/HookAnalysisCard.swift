// CosmoOS/UI/FocusMode/SwipeStudy/HookAnalysisCard.swift
// Hook analysis card for Swipe Study Focus Mode
// February 2026

import SwiftUI

// MARK: - Hook Analysis Card

struct HookAnalysisCard: View {
    let analysis: SwipeAnalysis

    @State private var animatedScore: Double = 0
    @State private var ringProgress: CGFloat = 0
    @State private var hasAppeared = false

    private var hookScore: Double { analysis.effectiveHookScore }

    private var ringColor: Color {
        if hookScore >= 8 { return Color(hex: "#22C55E") }
        if hookScore >= 5 { return Color(hex: "#3B82F6") }
        return Color(hex: "#64748B")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Hook text
            Text(analysis.hookText ?? "No hook detected")
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.3)
                .foregroundColor(.white)
                .lineLimit(4)

            // Pills row
            HStack(spacing: 8) {
                // Hook type pill
                if let hookType = analysis.hookType {
                    HStack(spacing: 4) {
                        Image(systemName: hookType.iconName)
                            .font(.system(size: 10))
                        Text(hookType.displayName)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(hookType.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(hookType.color.opacity(0.2), in: Capsule())
                }

                // Emotion pill
                if let emotion = analysis.dominantEmotion {
                    HStack(spacing: 4) {
                        Image(systemName: emotion.iconName)
                            .font(.system(size: 10))
                        Text(emotion.displayName)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(emotion.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(emotion.color.opacity(0.2), in: Capsule())
                }
            }

            // Score and word count row
            HStack(spacing: 16) {
                // Circular score ring
                ZStack {
                    Circle()
                        .stroke(ringColor.opacity(0.15), lineWidth: 3)
                        .frame(width: 40, height: 40)

                    Circle()
                        .trim(from: 0, to: ringProgress)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 40, height: 40)
                        .rotationEffect(.degrees(-90))

                    Text(String(format: "%.0f", animatedScore))
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(ringColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Hook Score")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))

                    if let wordCount = analysis.hookWordCount {
                        Text("\(wordCount) words")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }

                Spacer()
            }

            // Hook score reason callout
            if let reason = analysis.hookScoreReason, !reason.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    // Left accent border
                    RoundedRectangle(cornerRadius: 1)
                        .fill(ringColor)
                        .frame(width: 2)

                    Text(reason)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(ringColor.opacity(0.06))
                )
                .padding(.top, 8)
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
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                ringProgress = CGFloat(hookScore / 10.0)
            }
            // Animate score counter
            animateCounter(to: hookScore, duration: 0.8)
        }
    }

    private func animateCounter(to target: Double, duration: Double) {
        let steps = 20
        let stepDuration = duration / Double(steps)
        for i in 0...steps {
            let fraction = Double(i) / Double(steps)
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(i)) {
                animatedScore = target * fraction
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct HookAnalysisCard_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color(hex: "#0A0A0F").ignoresSafeArea()
            HookAnalysisCard(
                analysis: SwipeAnalysis(
                    hookText: "Stop scrolling. This one technique changed how I write every single hook.",
                    hookType: .curiosityGap,
                    hookScore: 8.5,
                    hookWordCount: 12,
                    dominantEmotion: .curiosity,
                    hookScoreReason: "Strong curiosity gap with specific number creates dual tension — the reader needs to know both the technique and why it works for every hook.",
                    analysisVersion: 1,
                    isFullyAnalyzed: true
                )
            )
            .frame(width: 400)
            .padding()
        }
    }
}
#endif
