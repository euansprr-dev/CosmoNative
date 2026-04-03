// CosmoOS/UI/FocusMode/SwipeStudy/PhysicsTransitionFlowView.swift
// Transition causality flow — vertical stepped diagram with styled edges

import SwiftUI

struct PhysicsTransitionFlowView: View {
    let transitions: [QuarkTransition]

    @State private var hoveredIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            headerRow
            flowContent
        }
        .padding(DS.space16)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusMedium).stroke(DS.border, lineWidth: 1))
        .dsRestingShadow()
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text("TRANSITION FLOW")
                .font(DS.caption)
                .tracking(1.2)
                .foregroundStyle(DS.info)
            Spacer()
            Text("\(transitions.count) transitions")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
    }

    // MARK: - Flow Content

    @ViewBuilder
    private var flowContent: some View {
        if transitions.count > 12 {
            ScrollView(.vertical) {
                flowRows
            }
            .frame(maxHeight: 400)
        } else {
            flowRows
        }
    }

    private var flowRows: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            ForEach(Array(transitions.enumerated()), id: \.element.id) { index, transition in
                transitionRow(transition, index: index)
                if index < transitions.count - 1 {
                    Divider()
                        .foregroundStyle(DS.borderSubtle)
                }
            }
        }
    }

    // MARK: - Transition Row

    @ViewBuilder
    private func transitionRow(_ t: QuarkTransition, index: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            slidePairRow(t, index: index)
            mechanismText(t)
        }
        .onHover { hovering in
            hoveredIndex = hovering ? index : nil
        }
    }

    @ViewBuilder
    private func slidePairRow(_ t: QuarkTransition, index: Int) -> some View {
        HStack(spacing: DS.space4) {
            slideNode(number: t.from, color: transitionColor(t.type))
            connectionEdge(t)
            slideNode(number: t.to, color: transitionColor(t.type))
            specialMarkers(t)
            Spacer()
        }
    }

    // MARK: - Slide Nodes

    private func slideNode(number: Int, color: Color) -> some View {
        Text("\(number)")
            .font(DS.caption)
            .monospaced()
            .foregroundStyle(DS.text)
            .frame(width: 26, height: 26)
            .background(DS.surfaceHover, in: Circle())
            .overlay(Circle().stroke(color, lineWidth: 2))
    }

    // MARK: - Connection Edge

    private func connectionEdge(_ t: QuarkTransition) -> some View {
        HStack(spacing: 0) {
            connectionLine(t)
                .frame(width: 20, height: 2)
            typeBadge(t)
            connectionLine(t)
                .frame(width: 20, height: 2)
        }
    }

    private func connectionLine(_ t: QuarkTransition) -> some View {
        let color = transitionColor(t.type)
        let lower = t.type.lowercased()

        return Group {
            if lower.contains("deflation") || lower.contains("loss") || lower.contains("discomfort") {
                LineShape()
                    .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            } else if lower.contains("skip") || lower.contains("context") {
                LineShape()
                    .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [2, 3]))
            } else {
                LineShape()
                    .stroke(color, lineWidth: 2)
            }
        }
    }

    // MARK: - Type Badge

    private func typeBadge(_ t: QuarkTransition) -> some View {
        let color = transitionColor(t.type)
        return CodexConceptTag(name: t.type, color: color)
    }

    // MARK: - Special Markers

    @ViewBuilder
    private func specialMarkers(_ t: QuarkTransition) -> some View {
        if t.swapTestPasses == false {
            Image(systemName: "lock.fill")
                .font(DS.caption2)
                .foregroundStyle(DS.green)
                .help("Strong causal link")
                .accessibilityLabel("Locked transition — strong causal link")
        }
        if t.doubleHelix == true {
            Image(systemName: "dna")
                .font(DS.caption2)
                .foregroundStyle(DS.info)
                .help("Double helix causality")
                .accessibilityLabel("Double helix causality")
        }
    }

    // MARK: - Mechanism Text

    @ViewBuilder
    private func mechanismText(_ t: QuarkTransition) -> some View {
        if let mechanism = t.mechanism, !mechanism.isEmpty {
            Text(mechanism)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, DS.space16)
        }
    }

    // MARK: - Color Mapping

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

// MARK: - Line Shape

private struct LineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
