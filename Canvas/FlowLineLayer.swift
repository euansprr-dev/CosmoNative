// CosmoOS/Canvas/FlowLineLayer.swift
// The visible skin of Living Workflows: ink bezier lines from cluster edges,
// one capsule verb chip per flow, a single bead of light when a flow fires.
// Idle flows are completely static — a canvas full of flows reads as an
// annotated diagram, never a machine.

import SwiftUI

// MARK: - Layer

/// Renders all flows in canvas space (mounted beside the cluster layer).
struct FlowLineLayer: View {
    let flows: [CanvasFlow]
    let clusters: [CanvasCluster]
    let firingFlowIds: Set<String>
    let runningFlowIds: Set<String>
    let onSelectFlow: (CanvasFlow) -> Void
    let onMoveFlowEnd: (String, CGPoint) -> Void
    let onAcceptProposal: (CanvasFlow) -> Void
    let onDiscardProposal: (CanvasFlow) -> Void

    var body: some View {
        ZStack {
            ForEach(flows) { flow in
                if let cluster = clusters.first(where: { $0.id.uuidString == flow.sourceClusterId }) {
                    FlowLineView(
                        flow: flow,
                        cluster: cluster,
                        isFiring: firingFlowIds.contains(flow.uuid),
                        isRunning: runningFlowIds.contains(flow.uuid),
                        onSelect: { onSelectFlow(flow) },
                        onMoveEnd: { onMoveFlowEnd(flow.uuid, $0) },
                        onAcceptProposal: { onAcceptProposal(flow) },
                        onDiscardProposal: { onDiscardProposal(flow) }
                    )
                }
            }
        }
        .allowsHitTesting(true)
    }
}

// MARK: - Geometry

struct FlowGeometry {
    let start: CGPoint
    let end: CGPoint

    init(clusterRect: CGRect, end: CGPoint) {
        let fromRight = end.x >= clusterRect.midX
        self.start = CGPoint(
            x: fromRight ? clusterRect.maxX : clusterRect.minX,
            y: min(max(end.y, clusterRect.minY + 24), clusterRect.maxY - 24)
        )
        self.end = end
    }

    private var controlOffset: CGFloat {
        max(abs(end.x - start.x) * 0.45, 40)
    }

    var control1: CGPoint {
        CGPoint(x: start.x + (end.x >= start.x ? controlOffset : -controlOffset), y: start.y)
    }

    var control2: CGPoint {
        CGPoint(x: end.x - (end.x >= start.x ? controlOffset : -controlOffset), y: end.y)
    }

    var path: Path {
        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: control1, control2: control2)
        return path
    }

    /// Point along the cubic curve at parameter t (0…1).
    func point(at t: CGFloat) -> CGPoint {
        let mt = 1 - t
        let a = mt * mt * mt
        let b = 3 * mt * mt * t
        let c = 3 * mt * t * t
        let d = t * t * t
        return CGPoint(
            x: a * start.x + b * control1.x + c * control2.x + d * end.x,
            y: a * start.y + b * control1.y + c * control2.y + d * end.y
        )
    }

    var midpoint: CGPoint { point(at: 0.5) }

    /// Arrowhead direction at the end of the curve.
    var endAngle: Angle {
        let before = point(at: 0.96)
        return Angle(radians: atan2(end.y - before.y, end.x - before.x))
    }
}

// MARK: - Single flow

private struct FlowLineView: View {
    let flow: CanvasFlow
    let cluster: CanvasCluster
    let isFiring: Bool
    let isRunning: Bool
    let onSelect: () -> Void
    let onMoveEnd: (CGPoint) -> Void
    let onAcceptProposal: () -> Void
    let onDiscardProposal: () -> Void

    private var hasProposal: Bool { flow.pendingOutputAtomUUID != nil }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawnIn = false
    @State private var beadProgress: CGFloat = 0
    @State private var chipHovered = false
    @State private var dragEnd: CGPoint?

    private var geometry: FlowGeometry {
        FlowGeometry(
            clusterRect: cluster.boundingRect,
            end: dragEnd ?? flow.endPoint
        )
    }

    var body: some View {
        let geo = geometry
        ZStack {
            inkLine(geo)
            arrowhead(geo)
            if isFiring && !reduceMotion {
                bead(geo)
            }
            chip(geo)
            if hasProposal {
                proposalCard(geo)
            }
        }
        .onAppear {
            guard !reduceMotion else { drawnIn = true; return }
            withAnimation(.easeOut(duration: 0.3)) { drawnIn = true }
        }
        .onChange(of: isFiring) { _, firing in
            guard firing, !reduceMotion else { return }
            beadProgress = 0
            withAnimation(.easeOut(duration: 0.6)) { beadProgress = 1 }
        }
    }

    // MARK: Ink

    private func inkLine(_ geo: FlowGeometry) -> some View {
        geo.path
            .trim(from: 0, to: drawnIn ? 1 : 0)
            .stroke(
                DS.textMuted.opacity(0.35),
                style: StrokeStyle(
                    lineWidth: 1.5,
                    lineCap: .round,
                    // Dashed = a proposal waiting for approval (propose-mode language)
                    dash: hasProposal ? [5, 5] : []
                )
            )
    }

    /// The propose-mode card at the line's end: autonomous output staged,
    /// nothing lands until you say so.
    private func proposalCard(_ geo: FlowGeometry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: flow.verb.icon)
                    .font(DS.caption)
                    .foregroundStyle(flow.verb.outputTint)
                Text("\(flow.verb.displayName) ready")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.text)
            }
            HStack(spacing: 8) {
                Button(action: onAcceptProposal) {
                    Text("Add")
                        .font(DS.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(DS.accent))
                }
                .buttonStyle(.plain)
                .help("Place the output here")

                Button(action: onDiscardProposal) {
                    Text("Discard")
                        .font(DS.caption.weight(.semibold))
                        .foregroundStyle(DS.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(DS.glassCardFill))
                        .overlay(Capsule().strokeBorder(DS.glassBorder, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help("Delete the staged output")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(flow.verb.outputTint.opacity(0.4), lineWidth: 1)
        )
        .position(x: geo.end.x, y: geo.end.y - 52)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(flow.verb.displayName) proposal awaiting approval")
    }

    private func arrowhead(_ geo: FlowGeometry) -> some View {
        Image(systemName: "chevron.right")
            .font(DS.caption2.weight(.semibold))
            .foregroundStyle(DS.textMuted.opacity(0.5))
            .rotationEffect(geo.endAngle)
            .position(geo.end)
            .opacity(drawnIn ? 1 : 0)
    }

    // MARK: Bead — the entire firing show

    private func bead(_ geo: FlowGeometry) -> some View {
        Circle()
            .fill(DS.accent)
            .frame(width: 5, height: 5)
            .shadow(color: DS.accent.opacity(0.5), radius: 3)
            .position(geo.point(at: beadProgress))
    }

    // MARK: Chip

    private func chip(_ geo: FlowGeometry) -> some View {
        HStack(spacing: 5) {
            if isRunning {
                Image(systemName: "circle.dotted")
                    .font(DS.caption2)
            } else {
                Image(systemName: flow.verb.icon)
                    .font(DS.caption2)
            }
            Text(flow.verb.displayName)
                .font(DS.caption.weight(.semibold))
        }
        .foregroundStyle(flow.verb.outputTint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular.interactive(), in: .capsule)
        .scaleEffect(isFiring ? 1.04 : (chipHovered ? 1.03 : 1))
        .position(geo.midpoint)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : ProMotionSprings.hover) { chipHovered = hovering }
        }
        .onTapGesture(perform: onSelect)
        .simultaneousGesture(chipDrag)
        .help("\(flow.verb.displayName) flow — click to inspect")
        .accessibilityLabel("\(flow.verb.displayName) flow from \(cluster.name)")
        .accessibilityAddTraits(.isButton)
        .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: isFiring)
    }

    /// Dragging the chip repositions the flow's end point (the midpoint
    /// follows the cursor, so the gesture feels like holding the line itself).
    private var chipDrag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let start = geometry.start
                dragEnd = CGPoint(
                    x: 2 * value.location.x - start.x,
                    y: 2 * value.location.y - start.y
                )
            }
            .onEnded { _ in
                if let dragEnd {
                    onMoveEnd(dragEnd)
                }
                dragEnd = nil
            }
    }
}

// MARK: - Verb Picker

/// The two-verb bloom shown when creating a flow from a cluster.
struct FlowVerbPicker: View {
    let clusterName: String
    let onPick: (FlowVerb) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Flow from \(clusterName)")
                .font(DS.caption)
                .tracking(0.3)
                .foregroundStyle(DS.textMuted)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 4)

            ForEach(FlowVerb.allCases) { verb in
                FlowVerbRow(verb: verb) { onPick(verb) }
            }
        }
        .padding(6)
        .frame(width: 280)
        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 16)
        .scaleEffect(appeared ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.01) : ProMotionSprings.bouncy) {
                appeared = true
            }
        }
        .onExitCommand(perform: onDismiss)
    }
}

private struct FlowVerbRow: View {
    let verb: FlowVerb
    let onPick: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 10) {
                Image(systemName: verb.icon)
                    .font(DS.subheadline)
                    .foregroundStyle(verb.outputTint)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(verb.displayName)
                        .font(DS.callout.weight(.semibold))
                        .foregroundStyle(DS.text)
                    Text(verb.pickerDescription)
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? DS.accentSoft : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : ProMotionSprings.hover) { isHovered = hovering }
        }
        .accessibilityLabel("\(verb.displayName): \(verb.pickerDescription)")
    }
}

// MARK: - Flow Inspector

/// The card shown when a chip is clicked: the rule as one plain sentence,
/// a Run button, and the ledger of recent firings.
struct FlowInspectorCard: View {
    let flow: CanvasFlow
    let clusterName: String
    let isRunning: Bool
    let onRun: () -> Void
    let onChangeRunMode: (FlowRunMode) -> Void
    let onDelete: () -> Void
    let onRevealOutput: (String) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var firings: [FlowFiringRecord] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            sentence
            runModeRow
            divider
            ledger
            divider
            footer
        }
        .frame(width: 340)
        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 20)
        .scaleEffect(appeared ? 1 : 0.95)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.01) : ProMotionSprings.bouncy) {
                appeared = true
            }
        }
        .task(id: flow.uuid) {
            firings = await FlowEngine.recentFirings(flowUUID: flow.uuid)
        }
        .onExitCommand(perform: onDismiss)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: flow.verb.icon)
                .font(DS.subheadline)
                .foregroundStyle(flow.verb.outputTint)
            Text("\(flow.verb.displayName) flow")
                .font(DS.headline)
                .foregroundStyle(DS.text)

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(DS.glassCardFill))
            }
            .buttonStyle(.plain)
            .help("Close (esc)")
            .accessibilityLabel("Close flow inspector")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var sentence: some View {
        Text(flow.sentence(clusterName: clusterName))
            .font(DS.callout)
            .foregroundStyle(DS.textSecondary)
            .lineSpacing(3)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Run-mode pills — the selection highlight travels between them.
    private var runModeRow: some View {
        HStack(spacing: 4) {
            ForEach(FlowRunMode.allCases) { mode in
                runModePill(mode)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func runModePill(_ mode: FlowRunMode) -> some View {
        let isSelected = flow.runMode == mode
        return Button {
            guard !isSelected else { return }
            onChangeRunMode(mode)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(DS.caption2)
                Text(mode.displayName)
                    .font(DS.caption.weight(.semibold))
            }
            .foregroundStyle(isSelected ? DS.accent : DS.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(isSelected ? DS.accentSoft : DS.glassCardFill))
            .overlay(Capsule().strokeBorder(isSelected ? DS.accent.opacity(0.4) : DS.glassBorder, lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(runModeHelp(mode))
        .accessibilityLabel("\(mode.displayName) run mode")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func runModeHelp(_ mode: FlowRunMode) -> String {
        switch mode {
        case .manual: return "Fires only when you press Run"
        case .onArrival: return "Fires when something new lands in the cluster — output staged for approval"
        case .daily: return "Fires once a day — output staged for approval"
        }
    }

    private var ledger: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ledger")
                .font(DS.caption)
                .tracking(0.3)
                .foregroundStyle(DS.textMuted)

            if firings.isEmpty {
                Text("Hasn't run yet — press Run to try it.")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            } else {
                ForEach(firings, id: \.uuid) { firing in
                    ledgerRow(firing)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ledgerRow(_ firing: FlowFiringRecord) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(DS.accent.opacity(0.6))
                .frame(width: 4, height: 4)
            Text(firing.summary)
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let outputUUID = firing.outputAtomUUID {
                Button("Reveal") {
                    onRevealOutput(outputUUID)
                }
                .buttonStyle(.plain)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.accent)
                .help("Show the output on the canvas")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(role: .destructive, action: onDelete) {
                Text("Remove")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.red)
            }
            .buttonStyle(.plain)
            .help("Remove this flow (the ledger is kept)")

            Spacer(minLength: 8)

            if flow.runCount > 0 {
                Text("\(flow.runCount) runs")
                    .font(DS.caption.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
            }

            Button(action: onRun) {
                HStack(spacing: 5) {
                    Image(systemName: isRunning ? "circle.dotted" : "play.fill")
                        .font(DS.caption2)
                    Text(isRunning ? "Running…" : "Run")
                        .font(DS.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(DS.accent))
                .opacity(isRunning ? 0.6 : 1)
            }
            .buttonStyle(.plain)
            .disabled(isRunning)
            .keyboardShortcut(.return, modifiers: [])
            .help("Run this flow now (⏎)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
