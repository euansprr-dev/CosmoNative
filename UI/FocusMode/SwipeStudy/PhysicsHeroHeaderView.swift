// CosmoOS/UI/FocusMode/SwipeStudy/PhysicsHeroHeaderView.swift
// Quiet marginalia header for Content Physics

import SwiftUI

struct PhysicsHeroHeaderView: View {
    let profile: ContentPhysicsProfile
    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            titleRow
            metricsLedger
        }
        .onAppear { withAnimation(ProMotionSprings.cardEntrance) { hasAppeared = true } }
    }

    @ViewBuilder
    private var titleRow: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "atom")
                .font(DS.callout)
                .foregroundStyle(DS.entitySwipe)
                .accessibilityHidden(true)

            Text("CONTENT PHYSICS")
                .font(DS.smallCaps)
                .tracking(1.6)
                .foregroundStyle(DS.entitySwipe)

            Rectangle()
                .fill(DS.sepiaSubtle)
                .frame(height: 0.5)

            extractedBadge
        }
    }

    @ViewBuilder
    private var extractedBadge: some View {
        if profile.extractedAt != nil {
            Text("Extracted")
                .font(DS.caption2)
                .foregroundStyle(DS.green)
        }
    }

    @ViewBuilder
    private var metricsLedger: some View {
        VStack(spacing: DS.space8) {
            metricLine(value: "\(profile.slideQuarks?.count ?? 0)", label: "slides decoded", index: 0)
            metricLine(value: "\(profile.transitions?.count ?? 0)", label: "causal transitions", index: 1)
            metricLine(value: "\(physicsEventCount)", label: "physics events", index: 2)
            energyMetricLine(index: 3)
        }
    }

    @ViewBuilder
    private func metricLine(value: String, label: String, index: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.space8) {
            Text(value)
                .font(.system(size: 22, weight: .light, design: .serif))
                .foregroundStyle(DS.text)
                .monospacedDigit()
                .frame(width: 34, alignment: .leading)
            Text(label)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
            Spacer(minLength: DS.space8)
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 4)
        .animation(ProMotionSprings.staggered(index: index), value: hasAppeared)
    }

    @ViewBuilder
    private func energyMetricLine(index: Int) -> some View {
        let isProportional = profile.physicsEvents?.energyResolution?.proportional == true
        let hasEnergy = profile.physicsEvents?.energyResolution != nil

        HStack(alignment: .center, spacing: DS.space8) {
            Image(systemName: hasEnergy ? (isProportional ? "checkmark.circle.fill" : "xmark.circle.fill") : "minus.circle")
                .font(DS.callout)
                .foregroundStyle(hasEnergy ? (isProportional ? DS.green : DS.red) : DS.textMuted)
                .accessibilityLabel(hasEnergy ? (isProportional ? "Proportional energy" : "Disproportional energy") : "No energy data")
            Text("energy")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
            Spacer(minLength: DS.space8)
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 4)
        .animation(ProMotionSprings.staggered(index: index), value: hasAppeared)
    }

    private var physicsEventCount: Int {
        guard let events = profile.physicsEvents else { return 0 }
        var count = 0
        if events.symmetryBreak?.slideNumber != nil { count += 1 }
        if events.phaseTransition?.slideNumber != nil { count += 1 }
        if events.peakGravity?.slideNumber != nil { count += 1 }
        if events.energyResolution != nil { count += 1 }
        return count
    }
}
