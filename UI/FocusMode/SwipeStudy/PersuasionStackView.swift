// CosmoOS/UI/FocusMode/SwipeStudy/PersuasionStackView.swift
// Persuasion technique bar chart for Swipe Study Focus Mode
// February 2026

import SwiftUI

// MARK: - Persuasion Stack View

struct PersuasionStackView: View {
    let techniques: [PersuasionTechnique]

    @State private var barProgress: [String: CGFloat] = [:]
    @State private var hasAppeared = false
    @State private var expandedTechnique: PersuasionType? = nil

    /// Top 6 techniques sorted by intensity
    private var topTechniques: [PersuasionTechnique] {
        Array(
            techniques
                .sorted { $0.intensity > $1.intensity }
                .prefix(6)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text("Persuasion Stack")
                .dsSmallCapsLabel()

            if topTechniques.isEmpty {
                placeholderView
            } else {
                VStack(spacing: 8) {
                    ForEach(topTechniques) { technique in
                        techniqueRow(technique)
                    }
                }
            }
        }
        .padding(16)
        .background(DS.surfaceCard, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .stroke(DS.border, lineWidth: 1)
        )
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            animateBars()
        }
    }

    // MARK: - Technique Row

    private func techniqueRow(_ technique: PersuasionTechnique) -> some View {
        let isExpanded = expandedTechnique == technique.type
        let hasExample = technique.example != nil

        return VStack(alignment: .leading, spacing: 0) {
            // Main bar row — tappable
            HStack(spacing: 10) {
                // Label
                Text(technique.type.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.text)
                    .frame(width: 100, alignment: .leading)

                // Bar
                GeometryReader { geo in
                    let progress = barProgress[technique.type.rawValue] ?? 0
                    let barWidth = geo.size.width * technique.intensity * progress

                    ZStack(alignment: .leading) {
                        // Track
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DS.borderSubtle)
                            .frame(height: 20)

                        // Fill
                        RoundedRectangle(cornerRadius: 4)
                            .fill(technique.type.color.opacity(0.7))
                            .frame(width: barWidth, height: 20)
                    }
                }
                .frame(height: 20)

                // Intensity value
                Text(String(format: "%.0f%%", technique.intensity * 100))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .frame(width: 36, alignment: .trailing)

                // Chevron indicator (only if example available)
                if hasExample {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(DS.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .animation(ProMotionSprings.snappy, value: isExpanded)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard hasExample else { return }
                withAnimation(ProMotionSprings.snappy) {
                    if expandedTechnique == technique.type {
                        expandedTechnique = nil
                    } else {
                        expandedTechnique = technique.type
                    }
                }
            }

            // Expandable example quote
            if isExpanded, let example = technique.example {
                Text(example)
                    .font(.system(size: 12).italic())
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(nil)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .fill(DS.borderSubtle)
                )
                .padding(.top, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Helpers

    private func animateBars() {
        for (index, technique) in topTechniques.enumerated() {
            let delay = Double(index) * 0.08
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    barProgress[technique.type.rawValue] = 1.0
                }
            }
        }
    }

    private var placeholderView: some View {
        Text("No persuasion techniques detected")
            .font(.system(size: 13))
            .foregroundColor(DS.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
    }
}

// MARK: - Preview

#if DEBUG
struct PersuasionStackView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            PersuasionStackView(
                techniques: [
                    PersuasionTechnique(type: .curiosityGap, intensity: 0.92, example: "\"You won't believe what happened next...\" — withholds the key detail to pull the reader forward."),
                    PersuasionTechnique(type: .socialProof, intensity: 0.75, example: "\"Over 10,000 creators already use this method.\""),
                    PersuasionTechnique(type: .scarcity, intensity: 0.68, example: "\"Only available for the next 24 hours.\""),
                    PersuasionTechnique(type: .authority, intensity: 0.55),
                    PersuasionTechnique(type: .storytelling, intensity: 0.43, example: "\"I was broke, sleeping on my friend's couch, when I stumbled on this one idea...\""),
                ]
            )
            .frame(width: 400)
            .padding()
        }
    }
}
#endif
