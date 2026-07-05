// CosmoOS/Canvas/DragToConnectOverlay.swift
// Visual overlay during Option+drag connection gesture
// Renders inside the scaleEffect container (canvas coordinates) so it matches
// the final KnowledgePulseLineView connections exactly.

import SwiftUI

struct DragToConnectOverlay: View {
    var connectManager: DragToConnectManager
    let blocks: [CanvasBlock]

    // MARK: - Bezier Control Point (matches KnowledgePulseLineView / CanvasConnectionLinesLayer)

    /// Perpendicular offset from midpoint — same algorithm as the final rendered lines
    private func bezierControl(from: CGPoint, to: CGPoint) -> CGPoint {
        let midX = (from.x + to.x) / 2
        let midY = (from.y + to.y) / 2
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return CGPoint(x: midX, y: midY) }

        let perpX = -dy / length
        let perpY = dx / length
        let offset = length * 0.15
        let direction: CGFloat = from.x + from.y < to.x + to.y ? 1 : -1

        return CGPoint(
            x: midX + perpX * offset * direction,
            y: midY + perpY * offset * direction
        )
    }

    var body: some View {
        if connectManager.isActive {
            ZStack {
                // Connection line from source to current drag point
                Canvas { context, size in
                    let from = connectManager.sourceCenter
                    let to = connectManager.currentDragPoint
                    let control = bezierControl(from: from, to: to)

                    // Glow layer — matches KnowledgePulseLineView glow
                    var glowPath = Path()
                    glowPath.move(to: from)
                    glowPath.addQuadCurve(to: to, control: control)
                    context.stroke(
                        glowPath,
                        with: .color(DS.textMuted.opacity(0.08)),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )

                    // Main line
                    var mainPath = Path()
                    mainPath.move(to: from)
                    mainPath.addQuadCurve(to: to, control: control)

                    let isHovering = connectManager.hoveredTargetBlockId != nil
                    let lineColor = isHovering ? DS.textMuted.opacity(0.35) : DS.textMuted.opacity(0.2)
                    let lineWidth: CGFloat = isHovering ? 2.0 : 1.2

                    context.stroke(
                        mainPath,
                        with: .color(lineColor),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: isHovering ? [] : [8, 6])
                    )

                    // End dot
                    let dotSize: CGFloat = isHovering ? 8 : 5
                    let dotRect = CGRect(x: to.x - dotSize/2, y: to.y - dotSize/2, width: dotSize, height: dotSize)
                    context.fill(
                        Path(ellipseIn: dotRect),
                        with: .color(DS.textMuted.opacity(isHovering ? 0.5 : 0.3))
                    )
                }

                // Highlight ring around hovered target block (canvas coordinates)
                if let targetId = connectManager.hoveredTargetBlockId,
                   let targetBlock = blocks.first(where: { $0.id == targetId }) {
                    let targetActualSize = BlockRenderedSizeCache.shared.renderedSize(for: targetBlock)
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(DS.textMuted.opacity(0.4), lineWidth: 2)
                        .frame(
                            width: targetActualSize.width * targetBlock.scale + 16,
                            height: targetActualSize.height * targetBlock.scale + 16
                        )
                        .shadow(color: DS.textMuted.opacity(0.2), radius: 8)
                        .position(x: targetBlock.position.x, y: targetBlock.position.y)
                }

                // Success flash
                if connectManager.connectionComplete {
                    Canvas { context, size in
                        let from = connectManager.sourceCenter
                        let to = connectManager.currentDragPoint
                        let control = bezierControl(from: from, to: to)

                        var path = Path()
                        path.move(to: from)
                        path.addQuadCurve(to: to, control: control)
                        context.stroke(
                            path,
                            with: .color(DS.textMuted.opacity(0.6)),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
    }
}
