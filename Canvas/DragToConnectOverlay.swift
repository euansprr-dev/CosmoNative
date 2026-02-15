// CosmoOS/Canvas/DragToConnectOverlay.swift
// Visual overlay during Option+drag connection gesture

import SwiftUI

struct DragToConnectOverlay: View {
    @ObservedObject var connectManager: DragToConnectManager
    let blocks: [CanvasBlock]
    let canvasOffset: CGSize
    let scaledPanOffset: CGSize
    let effectiveScale: CGFloat

    var body: some View {
        GeometryReader { geo in
            let screenCenter = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            if connectManager.isActive {
                // Connection line from source to current drag point
                Canvas { context, size in
                    let from = connectManager.sourceCenter
                    let to = connectManager.currentDragPoint

                    // Control point for bezier curve
                    let midX = (from.x + to.x) / 2
                    let midY = (from.y + to.y) / 2
                    let controlOffset: CGFloat = min(abs(to.x - from.x), abs(to.y - from.y)) * 0.3
                    let control = CGPoint(x: midX, y: midY - controlOffset)

                    // Glow layer
                    var glowPath = Path()
                    glowPath.move(to: from)
                    glowPath.addQuadCurve(to: to, control: control)
                    context.stroke(
                        glowPath,
                        with: .color(CosmoColors.thinkspacePurple.opacity(0.15)),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )

                    // Main line
                    var mainPath = Path()
                    mainPath.move(to: from)
                    mainPath.addQuadCurve(to: to, control: control)

                    let isHovering = connectManager.hoveredTargetBlockId != nil
                    let lineColor = isHovering ? CosmoColors.thinkspacePurple : CosmoColors.thinkspacePurple.opacity(0.6)
                    let lineWidth: CGFloat = isHovering ? 2.5 : 1.5

                    context.stroke(
                        mainPath,
                        with: .color(lineColor),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: isHovering ? [] : [8, 6])
                    )

                    // End dot
                    let dotSize: CGFloat = isHovering ? 10 : 6
                    let dotRect = CGRect(x: to.x - dotSize/2, y: to.y - dotSize/2, width: dotSize, height: dotSize)
                    context.fill(
                        Path(ellipseIn: dotRect),
                        with: .color(CosmoColors.thinkspacePurple)
                    )
                }

                // Highlight ring around hovered target block
                if let targetId = connectManager.hoveredTargetBlockId,
                   let targetBlock = blocks.first(where: { $0.id == targetId }) {
                    let blockX = targetBlock.position.x + canvasOffset.width + scaledPanOffset.width
                    let blockY = targetBlock.position.y + canvasOffset.height + scaledPanOffset.height
                    let scaledX = screenCenter.x + (blockX - screenCenter.x) * effectiveScale
                    let scaledY = screenCenter.y + (blockY - screenCenter.y) * effectiveScale

                    RoundedRectangle(cornerRadius: 14)
                        .stroke(CosmoColors.thinkspacePurple, lineWidth: 2)
                        .frame(
                            width: targetBlock.size.width * effectiveScale * targetBlock.scale + 16,
                            height: targetBlock.size.height * effectiveScale * targetBlock.scale + 16
                        )
                        .shadow(color: CosmoColors.thinkspacePurple.opacity(0.4), radius: 8)
                        .position(x: scaledX, y: scaledY)
                }

                // Success flash
                if connectManager.connectionComplete {
                    Canvas { context, size in
                        let from = connectManager.sourceCenter
                        let to = connectManager.currentDragPoint
                        let midX = (from.x + to.x) / 2
                        let midY = (from.y + to.y) / 2
                        let controlOffset: CGFloat = min(abs(to.x - from.x), abs(to.y - from.y)) * 0.3
                        let control = CGPoint(x: midX, y: midY - controlOffset)

                        var path = Path()
                        path.move(to: from)
                        path.addQuadCurve(to: to, control: control)
                        context.stroke(
                            path,
                            with: .color(.white),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                    }
                    .transition(.opacity)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
