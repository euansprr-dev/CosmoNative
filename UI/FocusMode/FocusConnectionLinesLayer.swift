// CosmoOS/UI/FocusMode/FocusConnectionLinesLayer.swift
// Renders connection lines between elements in focus modes
// February 2026 - Universal Linking (F6)

import SwiftUI

/// Renders connection lines between elements in focus modes
struct FocusConnectionLinesLayer: View {
    @ObservedObject var connectManager: FocusConnectManager
    let focusAtomUUID: String

    /// Stored connections loaded from UserDefaults
    @State private var storedConnections: [(source: String, target: String)] = []

    /// Element positions tracked by the parent view
    var elementPositions: [String: CGPoint] = [:]

    var body: some View {
        Canvas { context, size in
            // Draw active drag line
            if connectManager.isActive {
                drawDragLine(context: context, from: connectManager.sourceCenter, to: connectManager.currentDragPoint)
            }

            // Draw stored connections
            for connection in storedConnections {
                if let fromPos = elementPositions[connection.source],
                   let toPos = elementPositions[connection.target] {
                    drawStoredLine(context: context, from: fromPos, to: toPos)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            loadStoredConnections()
        }
    }

    private func drawDragLine(context: GraphicsContext, from: CGPoint, to: CGPoint) {
        let midX = (from.x + to.x) / 2
        let perpOffset: CGFloat = 30
        let control = CGPoint(x: midX, y: min(from.y, to.y) - perpOffset)

        // Glow
        var glowPath = Path()
        glowPath.move(to: from)
        glowPath.addQuadCurve(to: to, control: control)
        context.stroke(
            glowPath,
            with: .color(CosmoColors.thinkspacePurple.opacity(0.15)),
            style: StrokeStyle(lineWidth: 6, lineCap: .round)
        )

        // Main line
        var mainPath = Path()
        mainPath.move(to: from)
        mainPath.addQuadCurve(to: to, control: control)
        let isHovering = connectManager.hoveredTargetId != nil
        context.stroke(
            mainPath,
            with: .color(CosmoColors.thinkspacePurple.opacity(isHovering ? 0.8 : 0.4)),
            style: StrokeStyle(
                lineWidth: isHovering ? 2 : 1.5,
                lineCap: .round,
                dash: isHovering ? [] : [6, 4]
            )
        )
    }

    private func drawStoredLine(context: GraphicsContext, from: CGPoint, to: CGPoint) {
        let midX = (from.x + to.x) / 2
        let perpOffset: CGFloat = 20
        let control = CGPoint(x: midX, y: min(from.y, to.y) - perpOffset)

        var path = Path()
        path.move(to: from)
        path.addQuadCurve(to: to, control: control)
        context.stroke(
            path,
            with: .color(CosmoColors.thinkspacePurple.opacity(0.25)),
            style: StrokeStyle(lineWidth: 1, lineCap: .round)
        )
    }

    private func loadStoredConnections() {
        let key = "focusConnections_\(focusAtomUUID)"
        if let raw = UserDefaults.standard.array(forKey: key) as? [[String: String]] {
            storedConnections = raw.compactMap { dict in
                guard let source = dict["source"], let target = dict["target"] else { return nil }
                return (source: source, target: target)
            }
        }
    }
}
