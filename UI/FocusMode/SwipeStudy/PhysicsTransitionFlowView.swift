// CosmoOS/UI/FocusMode/SwipeStudy/PhysicsTransitionFlowView.swift
// Transition causality flow — shows how each slide connects to the next

import SwiftUI

struct PhysicsTransitionFlowView: View {
    let transitions: [QuarkTransition]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            HStack {
                Text("TRANSITION FLOW")
                    .font(DS.caption)
                    .tracking(1.2)
                    .foregroundStyle(DS.textMuted)
                Spacer()
                Text("\(transitions.count) transitions")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }

            ForEach(transitions) { transition in
                transitionRow(transition)
            }
        }
        .padding(DS.space16)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusMedium).stroke(DS.border, lineWidth: 1))
    }

    @ViewBuilder
    private func transitionRow(_ t: QuarkTransition) -> some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            HStack(spacing: DS.space8) {
                Text("\(t.from)→\(t.to)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(DS.text)
                    .frame(width: 40, alignment: .leading)

                Text(t.type)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(transitionColor(t.type))
                    .padding(.horizontal, DS.space6)
                    .padding(.vertical, 2)
                    .background(transitionColor(t.type).opacity(DS.opacitySubtle), in: Capsule())

                Spacer()

                if t.swapTestPasses == false {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.green)
                        .help("Can't swap — strong causal link")
                }

                if t.doubleHelix == true {
                    Text("🧬")
                        .font(.system(size: 11))
                        .help("Double helix — both narrative + psychological causality")
                }
            }

            if let mechanism = t.mechanism, !mechanism.isEmpty {
                Text(mechanism)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(2)
                    .padding(.leading, 48)
            }
        }
        .padding(.vertical, DS.space4)
    }

    private func transitionColor(_ type: String) -> Color {
        let t = type.lowercased()
        if t.contains("escalation") || t.contains("payoff") || t.contains("reaffirmation") { return DS.green }
        if t.contains("deflation") || t.contains("loss") || t.contains("discomfort") { return DS.red }
        if t.contains("skip") || t.contains("context") { return DS.info }
        if t.contains("decision") || t.contains("action") { return DS.orange }
        if t.contains("gratitude") || t.contains("closure") { return DS.entitySwipe }
        return DS.textSecondary
    }
}
