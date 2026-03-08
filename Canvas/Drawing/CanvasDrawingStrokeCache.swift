import SwiftUI

@MainActor
final class CanvasDrawingStrokeCache: ObservableObject {
    enum Rendering {
        case fill(Path)
        case stroke(Path, lineWidth: CGFloat)

        var path: Path {
            switch self {
            case .fill(let path), .stroke(let path, _):
                return path
            }
        }
    }

    private struct Entry {
        let signature: String
        let rendering: Rendering
    }

    private var entries: [String: Entry] = [:]

    func rendering(for drawing: CanvasDrawing) -> Rendering? {
        guard drawing.drawingType == .freehand,
              let points = drawing.pathPoints,
              points.count > 1 else {
            return nil
        }

        let signature = signature(for: drawing, points: points)
        if let existing = entries[drawing.id], existing.signature == signature {
            return existing.rendering
        }

        let rendering: Rendering
        let widths = drawing.pathWidths ?? []
        if widths.count == points.count {
            rendering = .fill(variableWidthStrokePath(points: points, widths: widths))
        } else {
            rendering = .stroke(smoothBezierPath(through: points), lineWidth: drawing.strokeWidth)
        }

        entries[drawing.id] = Entry(signature: signature, rendering: rendering)
        return rendering
    }

    func invalidateAll() {
        entries.removeAll()
    }

    func retain(ids: Set<String>) {
        entries = entries.filter { ids.contains($0.key) }
    }

    private func signature(for drawing: CanvasDrawing, points: [CGPoint]) -> String {
        var hasher = Hasher()
        hasher.combine(points.count)
        hasher.combine(Int((drawing.strokeWidth * 1000).rounded()))

        for point in points {
            hasher.combine(Int((point.x * 1000).rounded()))
            hasher.combine(Int((point.y * 1000).rounded()))
        }

        if let widths = drawing.pathWidths {
            hasher.combine(widths.count)
            for width in widths {
                hasher.combine(Int((width * 1000).rounded()))
            }
        } else {
            hasher.combine(0)
        }

        return String(hasher.finalize())
    }

    private func variableWidthStrokePath(points: [CGPoint], widths: [CGFloat]) -> Path {
        guard points.count >= 2 else { return Path() }

        let halfWidths = widths.map { $0 / 2.0 }

        var normals: [CGPoint] = []
        for index in 0..<points.count {
            let previous = index > 0 ? points[index - 1] : points[index]
            let next = index < points.count - 1 ? points[index + 1] : points[index]
            let dx = next.x - previous.x
            let dy = next.y - previous.y
            let length = max(hypot(dx, dy), 0.001)
            normals.append(CGPoint(x: -dy / length, y: dx / length))
        }

        var leftEdge: [CGPoint] = []
        var rightEdge: [CGPoint] = []
        for index in 0..<points.count {
            let width = halfWidths[index]
            leftEdge.append(CGPoint(x: points[index].x + normals[index].x * width, y: points[index].y + normals[index].y * width))
            rightEdge.append(CGPoint(x: points[index].x - normals[index].x * width, y: points[index].y - normals[index].y * width))
        }

        return Path { path in
            path.addArc(
                center: points[0],
                radius: max(halfWidths[0], 0.5),
                startAngle: .radians(atan2(leftEdge[0].y - points[0].y, leftEdge[0].x - points[0].x) + Double.pi),
                endAngle: .radians(atan2(leftEdge[0].y - points[0].y, leftEdge[0].x - points[0].x)),
                clockwise: false
            )

            addSmoothCurve(to: &path, through: leftEdge)

            let lastIndex = points.count - 1
            path.addArc(
                center: points[lastIndex],
                radius: max(halfWidths[lastIndex], 0.5),
                startAngle: .radians(atan2(leftEdge[lastIndex].y - points[lastIndex].y, leftEdge[lastIndex].x - points[lastIndex].x)),
                endAngle: .radians(atan2(rightEdge[lastIndex].y - points[lastIndex].y, rightEdge[lastIndex].x - points[lastIndex].x)),
                clockwise: false
            )

            addSmoothCurve(to: &path, through: rightEdge.reversed())
            path.closeSubpath()
        }
    }

    private func addSmoothCurve(to path: inout Path, through points: [CGPoint]) {
        guard points.count >= 2 else { return }

        if points.count == 2 {
            path.addLine(to: points[1])
            return
        }

        path.addLine(to: points[0])
        for index in 0..<(points.count - 1) {
            let p0 = index > 0 ? points[index - 1] : points[index]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = index + 2 < points.count ? points[index + 2] : points[index + 1]

            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6.0,
                y: p1.y + (p2.y - p0.y) / 6.0
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6.0,
                y: p2.y - (p3.y - p1.y) / 6.0
            )
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
    }

    private func smoothBezierPath(through points: [CGPoint]) -> Path {
        Path { path in
            guard points.count >= 2 else { return }
            path.move(to: points[0])

            if points.count == 2 {
                path.addLine(to: points[1])
                return
            }

            for index in 0..<(points.count - 1) {
                let p0 = index > 0 ? points[index - 1] : points[index]
                let p1 = points[index]
                let p2 = points[index + 1]
                let p3 = index + 2 < points.count ? points[index + 2] : points[index + 1]

                let cp1 = CGPoint(
                    x: p1.x + (p2.x - p0.x) / 6.0,
                    y: p1.y + (p2.y - p0.y) / 6.0
                )
                let cp2 = CGPoint(
                    x: p2.x - (p3.x - p1.x) / 6.0,
                    y: p2.y - (p3.y - p1.y) / 6.0
                )
                path.addCurve(to: p2, control1: cp1, control2: cp2)
            }
        }
    }
}
