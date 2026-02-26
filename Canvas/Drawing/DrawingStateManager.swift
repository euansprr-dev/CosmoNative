// CosmoOS/Canvas/Drawing/DrawingStateManager.swift
// Central state manager for canvas drawing tools

import SwiftUI
import GRDB

@MainActor
final class DrawingStateManager: ObservableObject {

    // MARK: - Tool State

    @Published var toolMode: CanvasToolMode = .select
    @Published var currentShapeKind: ShapeKind = .rectangle
    @Published var currentStrokeColor: String = "#FFFFFF"
    @Published var currentFillColor: String? = nil
    @Published var currentStrokeWidth: CGFloat = 2.0
    @Published var currentTextWeight: DrawingTextWeight = .M

    // MARK: - Drawings

    @Published var drawings: [CanvasDrawing] = []
    @Published var selectedDrawingId: String?

    // MARK: - Drag-to-Move State

    @Published var draggingDrawingId: String?
    @Published var drawingDragOffset: CGSize = .zero

    // MARK: - Active Drawing (in-progress preview)

    @Published var activeDrawing: CanvasDrawing?
    @Published var activePathPoints: [CGPoint] = []
    @Published var editingTextId: String?

    // MARK: - Thinkspace

    var currentThinkspaceId: String?

    // MARK: - Database

    private var database: CosmoDatabase { CosmoDatabase.shared }

    // MARK: - Load

    func loadDrawings(thinkspaceId: String?) {
        currentThinkspaceId = thinkspaceId
        Task {
            do {
                let records: [CanvasDrawingRecord] = try await database.asyncRead { db in
                    if let tsId = thinkspaceId {
                        return try CanvasDrawingRecord
                            .filter(Column("thinkspace_id") == tsId)
                            .filter(Column("is_deleted") == false)
                            .order(Column("z_index").asc)
                            .fetchAll(db)
                    } else {
                        return try CanvasDrawingRecord
                            .filter(Column("thinkspace_id") == nil)
                            .filter(Column("is_deleted") == false)
                            .order(Column("z_index").asc)
                            .fetchAll(db)
                    }
                }
                self.drawings = records.map { CanvasDrawing(from: $0) }
            } catch {
                print("DrawingStateManager: loadDrawings failed: \(error)")
            }
        }
    }

    // MARK: - Save

    func saveDrawing(_ drawing: CanvasDrawing) {
        // Update in-memory
        if let idx = drawings.firstIndex(where: { $0.id == drawing.id }) {
            drawings[idx] = drawing
        } else {
            drawings.append(drawing)
        }

        // Persist
        let record = drawing.toRecord(thinkspaceId: currentThinkspaceId)
        Task {
            do {
                try await database.asyncWrite { db in
                    try record.save(db)
                }
            } catch {
                print("DrawingStateManager: saveDrawing failed: \(error)")
            }
        }
    }

    // MARK: - Delete

    func deleteDrawing(_ id: String) {
        drawings.removeAll { $0.id == id }
        if selectedDrawingId == id {
            selectedDrawingId = nil
        }
        if editingTextId == id {
            editingTextId = nil
        }

        // Soft-delete in DB
        Task {
            do {
                try await database.asyncWrite { db in
                    try db.execute(
                        sql: "UPDATE canvas_drawings SET is_deleted = 1, updated_at = ? WHERE id = ?",
                        arguments: [ISO8601DateFormatter().string(from: Date()), id]
                    )
                }
            } catch {
                print("DrawingStateManager: deleteDrawing failed: \(error)")
            }
        }
    }

    // MARK: - Drag-to-Move

    func beginDragDrawing(id: String) {
        draggingDrawingId = id
        drawingDragOffset = .zero
    }

    func updateDragDrawing(translation: CGSize) {
        drawingDragOffset = translation
    }

    func finishDragDrawing() {
        guard let dragId = draggingDrawingId else { return }
        guard let idx = drawings.firstIndex(where: { $0.id == dragId }) else {
            draggingDrawingId = nil
            drawingDragOffset = .zero
            return
        }

        let dx = drawingDragOffset.width
        let dy = drawingDragOffset.height

        // Update origin
        drawings[idx].origin.x += dx
        drawings[idx].origin.y += dy

        // For shapes, origin is the top-left — already handled above
        // For freehand, also translate all path points
        if drawings[idx].drawingType == .freehand, let points = drawings[idx].pathPoints {
            drawings[idx].pathPoints = points.map {
                CGPoint(x: $0.x + dx, y: $0.y + dy)
            }
        }

        // Persist
        saveDrawing(drawings[idx])

        draggingDrawingId = nil
        drawingDragOffset = .zero
    }

    // MARK: - Shape Gesture Handling

    func beginShape(at point: CGPoint) {
        activeDrawing = CanvasDrawing(
            drawingType: .shape,
            shapeKind: currentShapeKind,
            origin: point,
            size: .zero,
            strokeColor: currentStrokeColor,
            fillColor: currentFillColor,
            strokeWidth: currentStrokeWidth
        )
    }

    func updateShape(to point: CGPoint) {
        guard var drawing = activeDrawing else { return }
        let w = point.x - drawing.origin.x
        let h = point.y - drawing.origin.y
        // Support dragging in any direction
        drawing.origin = CGPoint(
            x: min(drawing.origin.x, drawing.origin.x + w),
            y: min(drawing.origin.y, drawing.origin.y + h)
        )
        if w < 0 { drawing.origin.x = point.x }
        if h < 0 { drawing.origin.y = point.y }
        drawing.size = CGSize(width: abs(w), height: abs(h))
        activeDrawing = drawing
    }

    func finishShape() {
        guard var drawing = activeDrawing else { return }
        // Only save if shape has meaningful size
        let s = drawing.size ?? .zero
        if s.width > 3 || s.height > 3 {
            drawing.zIndex = (drawings.map(\.zIndex).max() ?? 0) + 1
            saveDrawing(drawing)
        }
        activeDrawing = nil
    }

    // MARK: - Freehand Gesture Handling

    func beginFreehand(at point: CGPoint) {
        activePathPoints = [point]
        activeDrawing = CanvasDrawing(
            drawingType: .freehand,
            origin: point,
            pathPoints: [point],
            strokeColor: currentStrokeColor,
            strokeWidth: currentStrokeWidth
        )
    }

    func addFreehandPoint(_ point: CGPoint) {
        activePathPoints.append(point)
        activeDrawing?.pathPoints = activePathPoints
    }

    func finishFreehand() {
        guard var drawing = activeDrawing, activePathPoints.count > 1 else {
            activeDrawing = nil
            activePathPoints = []
            return
        }
        let simplified = simplifyPath(activePathPoints, epsilon: 1.5)
        drawing.pathPoints = simplified
        drawing.zIndex = (drawings.map(\.zIndex).max() ?? 0) + 1
        saveDrawing(drawing)
        activeDrawing = nil
        activePathPoints = []
    }

    // MARK: - Text Creation

    func createText(at point: CGPoint) {
        let drawing = CanvasDrawing(
            drawingType: .text,
            origin: point,
            textContent: "",
            textWeight: currentTextWeight,
            strokeColor: currentStrokeColor,
            zIndex: (drawings.map(\.zIndex).max() ?? 0) + 1
        )
        drawings.append(drawing)
        editingTextId = drawing.id
    }

    func updateTextContent(_ id: String, content: String) {
        guard let idx = drawings.firstIndex(where: { $0.id == id }) else { return }
        drawings[idx].textContent = content
    }

    func finishTextEditing(_ id: String) {
        guard let idx = drawings.firstIndex(where: { $0.id == id }) else { return }
        editingTextId = nil
        let drawing = drawings[idx]
        // Remove empty text drawings
        if (drawing.textContent ?? "").isEmpty {
            deleteDrawing(id)
        } else {
            saveDrawing(drawing)
        }
    }

    // MARK: - Ramer-Douglas-Peucker Path Simplification

    func simplifyPath(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }

        // Find the point with maximum distance from the line between first and last
        let first = points.first!
        let last = points.last!
        var maxDist: CGFloat = 0
        var maxIdx = 0

        for i in 1..<(points.count - 1) {
            let d = perpendicularDistance(point: points[i], lineStart: first, lineEnd: last)
            if d > maxDist {
                maxDist = d
                maxIdx = i
            }
        }

        if maxDist > epsilon {
            let left = simplifyPath(Array(points[0...maxIdx]), epsilon: epsilon)
            let right = simplifyPath(Array(points[maxIdx...]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        } else {
            return [first, last]
        }
    }

    private func perpendicularDistance(point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let lengthSq = dx * dx + dy * dy
        guard lengthSq > 0 else {
            return hypot(point.x - lineStart.x, point.y - lineStart.y)
        }
        let t = max(0, min(1, ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / lengthSq))
        let projX = lineStart.x + t * dx
        let projY = lineStart.y + t * dy
        return hypot(point.x - projX, point.y - projY)
    }
}
