// CosmoOS/UI/FocusMode/SwipeStudy/PhysicsHeroHeaderView.swift
// Dashboard header with key metric boxes for Content Physics

import SwiftUI

struct PhysicsHeroHeaderView: View {
    let profile: ContentPhysicsProfile
    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            titleRow
            metricsRow
        }
        .padding(DS.space20)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .stroke(DS.border, lineWidth: 1)
        )
        .dsRestingShadow()
        .onAppear { withAnimation(ProMotionSprings.cardEntrance) { hasAppeared = true } }
    }

    @ViewBuilder
    private var titleRow: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "atom")
                .font(DS.title2)
                .foregroundStyle(DS.entitySwipe)
                .accessibilityHidden(true)

            Text("Content Physics")
                .font(DS.smallCaps)
                .foregroundStyle(DS.entitySwipe)

            Spacer()

            extractedBadge
        }
    }

    @ViewBuilder
    private var extractedBadge: some View {
        if profile.extractedAt != nil {
            Text("Extracted")
                .font(DS.caption2)
                .foregroundStyle(DS.green)
                .padding(.horizontal, DS.space8)
                .padding(.vertical, 3)
                .background(DS.greenSoft, in: Capsule())
        }
    }

    @ViewBuilder
    private var metricsRow: some View {
        HStack(spacing: DS.space8) {
            metricBox(value: "\(profile.slideQuarks?.count ?? 0)", label: "slides", index: 0)
            metricBox(value: "\(profile.transitions?.count ?? 0)", label: "transitions", index: 1)
            metricBox(value: "\(physicsEventCount)", label: "events", index: 2)
            energyMetricBox(index: 3)
        }
    }

    @ViewBuilder
    private func metricBox(value: String, label: String, index: Int) -> some View {
        VStack(spacing: DS.space4) {
            Text(value)
                .font(DS.title1)
                .foregroundStyle(DS.text)
            Text(label)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space10)
        .background(DS.surfaceHover, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 8)
        .animation(ProMotionSprings.staggered(index: index), value: hasAppeared)
    }

    @ViewBuilder
    private func energyMetricBox(index: Int) -> some View {
        let isProportional = profile.physicsEvents?.energyResolution?.proportional == true
        let hasEnergy = profile.physicsEvents?.energyResolution != nil

        VStack(spacing: DS.space4) {
            Image(systemName: hasEnergy ? (isProportional ? "checkmark.circle.fill" : "xmark.circle.fill") : "minus.circle")
                .font(DS.title1)
                .foregroundStyle(hasEnergy ? (isProportional ? DS.green : DS.red) : DS.textMuted)
                .accessibilityLabel(hasEnergy ? (isProportional ? "Proportional energy" : "Disproportional energy") : "No energy data")
            Text("energy")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space10)
        .background(DS.surfaceHover, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 8)
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
