// CosmoOS/Canvas/AutomationFlowLine.swift
// Animated bezier flow line between clusters that have automation rules connecting them
// Reuses KnowledgePulseLineView visual pattern — glow + gradient energy flow
// Lines are derived from rules at render time, not stored separately

import SwiftUI

/// Renders a single directional flow line between two cluster rects
struct AutomationFlowLine: View {

    let fromRect: CGRect         // Source cluster screen rect
    let toRect: CGRect           // Target cluster screen rect
    let color: Color             // Source cluster's accent color
    let isEnabled: Bool          // Rule is active
    let isPulsing: Bool          // Rule just fired — show pulse

    @State private var pulseProgress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let lineWidth: CGFloat = 1.2
    private let glowBlur: CGFloat = 3
    private let arrowSize: CGFloat = 6

    var body: some View {
        let (start, end) = endpoints
        let control = bezierControl(from: start, to: end)

        ZStack {
            // Glow layer
            flowPath(from: start, to: end, control: control)
                .stroke(
                    color.opacity(isEnabled ? 0.12 : 0.05),
                    style: StrokeStyle(lineWidth: lineWidth * 2.5, lineCap: .round)
                )
                .blur(radius: glowBlur)

            // Main line
            flowPath(from: start, to: end, control: control)
                .stroke(
                    isEnabled ? energyGradient(from: start, to: end) : AnyShapeStyle(color.opacity(0.15)),
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round,
                        dash: isEnabled ? [] : [6, 4]
                    )
                )

            // Directional arrow at endpoint
            arrowHead(at: end, from: control)
                .fill(color.opacity(isEnabled ? 0.4 : 0.15))

            // Pulse dot (travels along path when rule fires)
            if isPulsing && !reduceMotion {
                pulseDot(from: start, to: end, control: control)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                pulseProgress = 1.0
            }
        }
    }

    // MARK: - Geometry

    private var endpoints: (start: CGPoint, end: CGPoint) {
        // Connect from right edge of source to left edge of target
        let fromCenter = CGPoint(x: fromRect.midX, y: fromRect.midY)
        let toCenter = CGPoint(x: toRect.midX, y: toRect.midY)

        let angle = atan2(toCenter.y - fromCenter.y, toCenter.x - fromCenter.x)

        let startX = fromRect.midX + cos(angle) * (fromRect.width / 2 + 8)
        let startY = fromRect.midY + sin(angle) * (fromRect.height / 2 + 8)

        let endX = toRect.midX - cos(angle) * (toRect.width / 2 + 8)
        let endY = toRect.midY - sin(angle) * (toRect.height / 2 + 8)

        return (CGPoint(x: startX, y: startY), CGPoint(x: endX, y: endY))
    }

    private func bezierControl(from: CGPoint, to: CGPoint) -> CGPoint {
        let midX = (from.x + to.x) / 2
        let midY = (from.y + to.y) / 2
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return CGPoint(x: midX, y: midY) }

        let perpX = -dy / length
        let perpY = dx / length
        let offset = length * 0.12
        let direction: CGFloat = from.x + from.y < to.x + to.y ? 1 : -1

        return CGPoint(
            x: midX + perpX * offset * direction,
            y: midY + perpY * offset * direction
        )
    }

    // MARK: - Shapes

    private func flowPath(from: CGPoint, to: CGPoint, control: CGPoint) -> Path {
        Path { path in
            path.move(to: from)
            path.addQuadCurve(to: to, control: control)
        }
    }

    private func arrowHead(at point: CGPoint, from control: CGPoint) -> Path {
        let angle = atan2(point.y - control.y, point.x - control.x)

        return Path { path in
            let tip = point
            let left = CGPoint(
                x: tip.x - cos(angle - .pi / 6) * arrowSize,
                y: tip.y - sin(angle - .pi / 6) * arrowSize
            )
            let right = CGPoint(
                x: tip.x - cos(angle + .pi / 6) * arrowSize,
                y: tip.y - sin(angle + .pi / 6) * arrowSize
            )
            path.move(to: tip)
            path.addLine(to: left)
            path.addLine(to: right)
            path.closeSubpath()
        }
    }

    // MARK: - Gradient

    private func energyGradient(from: CGPoint, to: CGPoint) -> AnyShapeStyle {
        let p = pulseProgress
        let s1 = max(0, min(p, 0.79))
        let s2 = max(s1 + 0.001, min(p + 0.08, 0.89))
        let s3 = max(s2 + 0.001, min(p + 0.16, 0.99))

        return AnyShapeStyle(
            LinearGradient(
                stops: [
                    .init(color: color.opacity(0.15), location: 0),
                    .init(color: color.opacity(0.35), location: s1),
                    .init(color: color.opacity(0.25), location: s2),
                    .init(color: color.opacity(0.35), location: s3),
                    .init(color: color.opacity(0.15), location: 1),
                ],
                startPoint: UnitPoint(x: from.x < to.x ? 0 : 1, y: 0.5),
                endPoint: UnitPoint(x: from.x < to.x ? 1 : 0, y: 0.5)
            )
        )
    }

    // MARK: - Pulse Dot

    private func pulseDot(from: CGPoint, to: CGPoint, control: CGPoint) -> some View {
        let t = pulseProgress
        // Quadratic bezier point at parameter t
        let x = (1 - t) * (1 - t) * from.x + 2 * (1 - t) * t * control.x + t * t * to.x
        let y = (1 - t) * (1 - t) * from.y + 2 * (1 - t) * t * control.y + t * t * to.y

        return Circle()
            .fill(color)
            .frame(width: 4, height: 4)
            .shadow(color: color.opacity(0.5), radius: 3)
            .position(x: x, y: y)
    }
}

// MARK: - Flow Line Data Derivation

@MainActor
enum AutomationFlowLineScanner {

    /// Scan all rules to find cluster-to-cluster flow connections
    /// Returns pairs of (sourceClusterId, targetClusterId, isEnabled) for rendering
    static func scanFlowConnections() -> [FlowConnection] {
        let allRules = AutomationDispatcher.shared.ruleCache.values.flatMap { $0 }
        var connections: [FlowConnection] = []

        for rule in allRules {
            guard rule.scope == .cluster, let sourceClusterId = rule.scopeId else { continue }

            let actions = rule.parsedActions
            for action in actions {
                if action.type == .moveToCluster, let targetId = action.configString("clusterId") {
                    if targetId != sourceClusterId {
                        connections.append(FlowConnection(
                            sourceClusterId: sourceClusterId,
                            targetClusterId: targetId,
                            ruleName: rule.name,
                            ruleUUID: rule.uuid,
                            isEnabled: rule.isEnabled
                        ))
                    }
                }
            }
        }

        return connections
    }
}

struct FlowConnection: Identifiable {
    let sourceClusterId: String
    let targetClusterId: String
    let ruleName: String
    let ruleUUID: String
    let isEnabled: Bool

    var id: String { "\(sourceClusterId)→\(targetClusterId)" }
}
