// CosmoOS/UI/Codex/CodexAkashicComponents.swift
// Shared Akashic visual language components for the Codex.
// April 2026 — Akashic Records Premium Redesign

import SwiftUI

// MARK: - Akashic Callout

/// Replaces left-accent-bar callouts with gilt-ruled vellum surfaces.
struct AkashicCallout: View {
    let text: String
    var tintColor: Color = DS.gilt
    var font: Font = DS.body

    var body: some View {
        VStack(spacing: 0) {
            OrnamentalRule(width: 48, color: tintColor.opacity(0.5))
                .padding(.bottom, DS.space8)
            Text(text)
                .font(font)
                .foregroundStyle(DS.inkWash)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
            OrnamentalRule(width: 48, color: tintColor.opacity(0.5))
                .padding(.top, DS.space8)
        }
        .padding(DS.space16)
        .background(DS.vellumDeep, in: .rect(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(DS.sepiaBorder, lineWidth: 0.5)
        )
        .filmGrain(opacity: 0.01)
    }
}

/// Akashic callout that accepts a View instead of a plain string.
struct AkashicCalloutContainer<Content: View>: View {
    var tintColor: Color = DS.gilt
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            OrnamentalRule(width: 48, color: tintColor.opacity(0.5))
                .padding(.bottom, DS.space8)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
            OrnamentalRule(width: 48, color: tintColor.opacity(0.5))
                .padding(.top, DS.space8)
        }
        .padding(DS.space16)
        .background(DS.vellumDeep, in: .rect(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(DS.sepiaBorder, lineWidth: 0.5)
        )
        .filmGrain(opacity: 0.01)
    }
}

// MARK: - Akashic Section Header

/// Small caps section label with leading gilt diamond ornament.
struct AkashicSectionHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            giltDiamond
            Text(title)
                .dsSmallCapsLabel()
        }
    }

    private var giltDiamond: some View {
        Rectangle()
            .fill(DS.gilt)
            .frame(width: 4, height: 4)
            .rotationEffect(.degrees(45))
    }
}

// MARK: - Akashic Category Diamond

/// Category icon inside a rotated-square (diamond) frame.
struct AkashicCategoryDiamond: View {
    let icon: String
    let color: Color
    var size: DiamondSize = .medium

    enum DiamondSize {
        case small, medium, large

        var dimension: CGFloat {
            switch self {
            case .small: 20
            case .medium: 32
            case .large: 40
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .small: 9
            case .medium: 14
            case .large: 20
            }
        }
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size.iconSize, weight: .medium))
            .foregroundStyle(color)
            .frame(width: size.dimension, height: size.dimension)
            .background(
                Rectangle()
                    .fill(color.opacity(0.1))
                    .rotationEffect(.degrees(45))
                    .frame(
                        width: size.dimension * 0.72,
                        height: size.dimension * 0.72
                    )
            )
            .overlay(
                Rectangle()
                    .stroke(DS.giltMuted, lineWidth: 0.5)
                    .rotationEffect(.degrees(45))
                    .frame(
                        width: size.dimension * 0.72,
                        height: size.dimension * 0.72
                    )
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Constellation Dots

/// Frequency indicator as editorial dot constellation.
struct ConstellationDots: View {
    let frequency: String?
    @State private var animatedCount: Int = 0

    private var parsed: (numerator: Int, denominator: Int)? {
        guard let freq = frequency else { return nil }
        let parts = freq.split(separator: "/")
        guard parts.count == 2,
              let num = Int(parts[0]),
              let den = Int(parts[1]),
              den > 0 else { return nil }
        return (num, den)
    }

    private var filledCount: Int {
        guard let data = parsed, data.denominator > 0 else { return 0 }
        return max(1, Int(round(Double(data.numerator) / Double(data.denominator) * 10)))
    }

    var body: some View {
        if let data = parsed {
            VStack(alignment: .leading, spacing: 3) {
                dotsRow
                ratioLabel(data)
            }
            .onAppear {
                animateSequentially()
            }
        }
    }

    private var dotsRow: some View {
        HStack(spacing: 3) {
            ForEach(0..<10, id: \.self) { index in
                Circle()
                    .fill(index < animatedCount ? DS.gilt : DS.sepiaSubtle)
                    .frame(width: 4, height: 4)
            }
        }
    }

    private func ratioLabel(_ data: (numerator: Int, denominator: Int)) -> some View {
        Text("\(data.numerator)/\(data.denominator)")
            .font(DS.smallCaps)
            .foregroundStyle(DS.inkFaded)
    }

    private func animateSequentially() {
        let target = filledCount
        for i in 0..<target {
            withAnimation(ProMotionSprings.gentle.delay(Double(i) * 0.03)) {
                animatedCount = i + 1
            }
        }
    }
}

// MARK: - Gilt Hairline

/// Thin horizontal gilt rule for visual separation within cards.
struct GiltHairline: View {
    var body: some View {
        Rectangle()
            .fill(DS.giltMuted)
            .frame(height: 0.5)
    }
}

// MARK: - Gilt Dot Connector

/// Vertical dot connector for walkthrough slides (replaces line + chevron).
struct GiltDotConnector: View {
    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(DS.giltMuted.opacity(index == 1 ? 0.6 : 0.3))
                    .frame(width: index == 1 ? 4 : 3, height: index == 1 ? 4 : 3)
            }
        }
        .frame(height: 24)
    }
}
