// CosmoOS/UI/FocusMode/SwipeStudy/HookAnalysisCard.swift
// Hook analysis card for Swipe Study Focus Mode
// February 2026

import SwiftUI

// MARK: - Hook Analysis Card

struct HookAnalysisCard: View {
    let analysis: SwipeAnalysis

    @State private var animatedScore: Double = 0
    @State private var hasAppeared = false

    private var hookScore: Double { analysis.effectiveHookScore }

    private var ringColor: Color {
        if hookScore >= 8 { return DS.green }
        if hookScore >= 5 { return DS.info }
        return DS.inkFaded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            MarginaliaLabel("HOOK", countText: String(format: "%.1f", animatedScore))

            Text(analysis.hookText ?? "No hook detected")
                .font(.system(size: 18, weight: .regular, design: .serif))
                .foregroundStyle(DS.text)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DS.space8) {
                if let hookType = analysis.hookType {
                    inlineTrait(icon: hookType.iconName, title: hookType.displayName, color: hookType.color)
                }

                if let emotion = analysis.dominantEmotion {
                    inlineTrait(icon: emotion.iconName, title: emotion.displayName, color: emotion.color)
                }
            }

            VStack(alignment: .leading, spacing: DS.space6) {
                HStack {
                    Text("hook score")
                    Spacer()
                    if let wordCount = analysis.hookWordCount {
                        Text("\(wordCount) words")
                    }
                }
                .font(DS.caption2)
                .foregroundStyle(DS.inkFaded)

                TrackAndBead(progress: hookScore / 10.0, color: ringColor, animate: hasAppeared)
            }

            if let reason = analysis.hookScoreReason, !reason.isEmpty {
                Text(reason)
                    .font(DS.callout)
                    .foregroundStyle(DS.inkFaded)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.space4)
            }
        }
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            animateCounter(to: hookScore, duration: 0.8)
        }
    }

    private func inlineTrait(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: DS.space4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .regular))
            Text(title.lowercased())
                .font(DS.dateSerif)
                .italic()
        }
        .foregroundStyle(color.opacity(0.82))
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
#Preview {
    ZStack {
        DS.bg.ignoresSafeArea()
        HookAnalysisCard(
            analysis: SwipeAnalysis(
                hookText: "Stop scrolling. This one technique changed how I write every single hook.",
                hookType: .curiosityGap,
                hookScore: 8.5,
                hookWordCount: 12,
                dominantEmotion: .curiosity,
                hookScoreReason: "Strong curiosity gap with specific number creates dual tension because the reader needs to know both the technique and why it works for every hook.",
                analysisVersion: 1,
                isFullyAnalyzed: true
            )
        )
        .frame(width: 400)
        .padding()
    }
}
#endif
