import SwiftUI

extension SpaceCanvasDrawing {
    init(_ drawing: CanvasDrawing) {
        id = drawing.id; drawingType = drawing.drawingType.rawValue; shapeKind = drawing.shapeKind?.rawValue
        originX = drawing.origin.x; originY = drawing.origin.y
        width = drawing.size.map { Double($0.width) }; height = drawing.size.map { Double($0.height) }; rotation = drawing.rotation
        points = drawing.pathPoints?.enumerated().map { index, point in
            SpaceCanvasPoint(x: point.x, y: point.y, w: drawing.pathWidths.flatMap { index < $0.count ? Double($0[index]) : nil })
        }
        textContent = drawing.textContent; textWeight = drawing.textWeight?.rawValue
        strokeColor = drawing.strokeColor; fillColor = drawing.fillColor; strokeWidth = drawing.strokeWidth
        opacity = drawing.opacity; zIndex = drawing.zIndex
    }
    var drawing: CanvasDrawing {
        CanvasDrawing(id: id, drawingType: DrawingType(rawValue: drawingType) ?? .freehand,
            shapeKind: shapeKind.flatMap(ShapeKind.init(rawValue:)), origin: CGPoint(x: originX, y: originY),
            size: width.flatMap { width in height.map { CGSize(width: width, height: $0) } }, rotation: rotation,
            pathPoints: points?.map { CGPoint(x: $0.x, y: $0.y) }, pathWidths: points?.map { CGFloat($0.w ?? strokeWidth) },
            textContent: textContent, textWeight: textWeight.flatMap(DrawingTextWeight.init(rawValue:)),
            strokeColor: strokeColor, fillColor: fillColor, strokeWidth: strokeWidth, opacity: opacity, zIndex: zIndex)
    }
}
