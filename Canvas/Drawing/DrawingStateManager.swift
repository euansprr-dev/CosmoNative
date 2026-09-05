// CosmoOS/Canvas/Drawing/DrawingStateManager.swift
// Central state manager for canvas drawing tools

import SwiftUI
import GRDB

enum ShapeResizeCorner: CaseIterable, Hashable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

@MainActor
@Observable
final class DrawingStateManager {
    let compositionSession: SpaceCompositionCanvasSession?

    init(compositionSession: SpaceCompositionCanvasSession? = nil) {
        self.compositionSession = compositionSession
    }

    private func registerUndo(_ action: UndoableAction) {
        if compositionSession == nil { CosmoUndoManager.shared.register(action) }
    }


    // MARK: - Tool State

    var toolMode: CanvasToolMode = .select
    var currentShapeKind: ShapeKind = .rectangle
    var currentStrokeColor: String = "#1A1A1A"
    var currentFillColor: String? = nil
    var currentStrokeWidth: CGFloat = 2.5
    var currentTextWeight: DrawingTextWeight = .M
    var currentLassoSubMode: LassoSubMode = .lasso
    var recentColors: [String] = []

    /// Shift held during shape creation constrains to 1:1 aspect ratio
    var shiftConstrain: Bool = false

    // MARK: - Zone Tool State

    /// The rectangle being dragged out in canvas coordinates (nil when not dragging)
    var activeZoneRect: CGRect?
    private var zoneStartPoint: CGPoint?

    // MARK: - Drawings

    var drawings: [CanvasDrawing] = []
    var selectedDrawingId: String?
    var selectedDrawingIds: Set<String> = []

    // MARK: - Drag-to-Move State

    var draggingDrawingId: String?
    var drawingDragOffset: CGSize = .zero

    // MARK: - Group Shape Resize State

    private struct GroupShapeResizeSession {
        let corner: ShapeResizeCorner
        let initialBounds: CGRect
        let snapshots: [String: CGRect]
        let selectedShapeIds: [String]
    }

    private let minimumGroupDimension: CGFloat = 12
    private let minimumShapeDimension: CGFloat = 4
    private var groupShapeResizeSession: GroupShapeResizeSession?

    // MARK: - Active Drawing (in-progress preview)

    var activeDrawing: CanvasDrawing?
    var activePathPoints: [CGPoint] = []
    var activePathWidths: [CGFloat] = []
    var editingTextId: String?

    /// Timestamp of last freehand point for velocity calculation
    private var lastPointTimestamp: Date?
    private var lastPointPosition: CGPoint?

    // MARK: - Thinkspace

    var currentThinkspaceId: String?

    // MARK: - Database

    private var database: CosmoDatabase { CosmoDatabase.shared }

    // MARK: - Load

    func loadDrawings(thinkspaceId: String?) {
        if let compositionSession {
            drawings = compositionSession.drawings
            return
        }
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
                guard self.currentThinkspaceId == thinkspaceId else { return }
                self.drawings = records.map { CanvasDrawing(from: $0) }
                self.clearSelection()
                self.editingTextId = nil
                self.draggingDrawingId = nil
                self.drawingDragOffset = .zero
            } catch {
                print("DrawingStateManager: loadDrawings failed: \(error)")
            }
        }
    }

    // MARK: - Selection

    func isSelected(_ id: String) -> Bool {
        selectedDrawingIds.contains(id)
    }

    func clearSelection() {
        selectedDrawingIds.removeAll()
        selectedDrawingId = nil
        groupShapeResizeSession = nil
    }

    func selectSingleDrawing(_ id: String?) {
        guard let id else {
            clearSelection()
            return
        }
        selectedDrawingIds = [id]
        selectedDrawingId = id
        groupShapeResizeSession = nil
    }

    func toggleSelection(_ id: String, additive: Bool) {
        if additive {
            if selectedDrawingIds.contains(id) {
                selectedDrawingIds.remove(id)
                if selectedDrawingId == id {
                    selectedDrawingId = primarySelectedDrawingId()
                }
            } else {
                selectedDrawingIds.insert(id)
                selectedDrawingId = id
            }
            if selectedDrawingIds.isEmpty {
                selectedDrawingId = nil
            }
        } else {
            if selectedDrawingIds.count == 1, selectedDrawingIds.contains(id) {
                clearSelection()
                return
            }
            selectedDrawingIds = [id]
            selectedDrawingId = id
        }
        groupShapeResizeSession = nil
    }

    func selectedShapeDrawings() -> [CanvasDrawing] {
        drawings.filter { selectedDrawingIds.contains($0.id) && $0.drawingType == .shape }
    }

    func selectedShapeBounds() -> CGRect? {
        let selectedShapes = selectedShapeDrawings()
        guard !selectedShapes.isEmpty else { return nil }
        return selectedShapes.dropFirst().reduce(selectedShapes[0].boundingRect) { partial, drawing in
            partial.union(drawing.boundingRect)
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

        if let compositionSession { compositionSession.saveDrawing(drawing); return }

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
        // Snapshot before removal for undo (CosmoUndoManager ignores during undo/redo)
        if let drawing = drawings.first(where: { $0.id == id }) {
            registerUndo(DeleteDrawingAction(drawing: drawing, drawingState: self))
        }

        drawings.removeAll { $0.id == id }
        selectedDrawingIds.remove(id)
        if selectedDrawingId == id {
            selectedDrawingId = primarySelectedDrawingId()
        }
        if selectedDrawingIds.isEmpty {
            selectedDrawingId = nil
        }
        if editingTextId == id {
            editingTextId = nil
        }
        if groupShapeResizeSession?.selectedShapeIds.contains(id) == true {
            groupShapeResizeSession = nil
        }

        if let compositionSession { compositionSession.deleteDrawing(id); return }

        // Soft-delete in DB
        Task {
            do {
                try await database.asyncWrite { db in
                    try db.execute(
                        sql: "UPDATE canvas_drawings SET is_deleted = 1, updated_at = ? WHERE id = ?",
                        arguments: [ISO8601.string(from: Date()), id]
                    )
                }
            } catch {
                print("DrawingStateManager: deleteDrawing failed: \(error)")
            }
        }
    }

    // MARK: - Restore (undo delete)

    func restoreDrawing(_ drawing: CanvasDrawing) {
        // Re-add to memory
        drawings.append(drawing)

        if let compositionSession { compositionSession.saveDrawing(drawing); return }

        // Un-soft-delete in DB
        let record = drawing.toRecord(thinkspaceId: currentThinkspaceId)
        Task {
            do {
                try await database.asyncWrite { db in
                    try db.execute(
                        sql: "UPDATE canvas_drawings SET is_deleted = 0, updated_at = ? WHERE id = ?",
                        arguments: [ISO8601.string(from: Date()), drawing.id]
                    )
                }
            } catch {
                // If the row was hard-deleted, re-insert it
                do {
                    try await database.asyncWrite { db in
                        try record.save(db)
                    }
                } catch {
                    print("DrawingStateManager: restoreDrawing failed: \(error)")
                }
            }
        }
    }

    // MARK: - Drag-to-Move

    func beginDragDrawing(id: String) {
        if !selectedDrawingIds.contains(id) {
            selectSingleDrawing(id)
        }
        draggingDrawingId = id
        drawingDragOffset = .zero
        groupShapeResizeSession = nil
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

        // Capture old state for undo
        let oldOrigin = drawings[idx].origin
        let oldPathPoints = drawings[idx].pathPoints

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

        // Register undo action
        let newOrigin = drawings[idx].origin
        let newPathPoints = drawings[idx].pathPoints
        if oldOrigin != newOrigin {
            registerUndo(
                MoveDrawingAction(
                    drawingId: dragId,
                    oldOrigin: oldOrigin,
                    newOrigin: newOrigin,
                    oldPathPoints: oldPathPoints,
                    newPathPoints: newPathPoints,
                    drawingState: self
                )
            )
        }

        // Persist
        saveDrawing(drawings[idx])

        draggingDrawingId = nil
        drawingDragOffset = .zero
    }

    // MARK: - Group Shape Resize

    func beginSelectedShapeResize(corner: ShapeResizeCorner) {
        let shapes = selectedShapeDrawings()
        guard !shapes.isEmpty else {
            groupShapeResizeSession = nil
            return
        }

        let initialBounds = shapes.dropFirst().reduce(shapes[0].boundingRect) { partial, drawing in
            partial.union(drawing.boundingRect)
        }
        let snapshots = Dictionary(uniqueKeysWithValues: shapes.map { ($0.id, $0.boundingRect) })

        groupShapeResizeSession = GroupShapeResizeSession(
            corner: corner,
            initialBounds: initialBounds,
            snapshots: snapshots,
            selectedShapeIds: shapes.map(\.id)
        )
    }

    func updateSelectedShapeResize(corner: ShapeResizeCorner, translation: CGSize) {
        if groupShapeResizeSession == nil || groupShapeResizeSession?.corner != corner {
            beginSelectedShapeResize(corner: corner)
        }
        guard let session = groupShapeResizeSession else { return }

        let initial = session.initialBounds
        let minWidth = max(minimumGroupDimension, 1)
        let minHeight = max(minimumGroupDimension, 1)
        var target = initial

        switch corner {
        case .topLeft:
            let newMinX = min(initial.minX + translation.width, initial.maxX - minWidth)
            let newMinY = min(initial.minY + translation.height, initial.maxY - minHeight)
            target = CGRect(x: newMinX, y: newMinY, width: initial.maxX - newMinX, height: initial.maxY - newMinY)
        case .topRight:
            let newMaxX = max(initial.maxX + translation.width, initial.minX + minWidth)
            let newMinY = min(initial.minY + translation.height, initial.maxY - minHeight)
            target = CGRect(x: initial.minX, y: newMinY, width: newMaxX - initial.minX, height: initial.maxY - newMinY)
        case .bottomLeft:
            let newMinX = min(initial.minX + translation.width, initial.maxX - minWidth)
            let newMaxY = max(initial.maxY + translation.height, initial.minY + minHeight)
            target = CGRect(x: newMinX, y: initial.minY, width: initial.maxX - newMinX, height: newMaxY - initial.minY)
        case .bottomRight:
            let newMaxX = max(initial.maxX + translation.width, initial.minX + minWidth)
            let newMaxY = max(initial.maxY + translation.height, initial.minY + minHeight)
            target = CGRect(x: initial.minX, y: initial.minY, width: newMaxX - initial.minX, height: newMaxY - initial.minY)
        }

        let baseWidth = max(initial.width, 1)
        let baseHeight = max(initial.height, 1)
        let sx = target.width / baseWidth
        let sy = target.height / baseHeight

        for id in session.selectedShapeIds {
            guard let snapshot = session.snapshots[id],
                  let idx = drawings.firstIndex(where: { $0.id == id }) else { continue }

            let relativeX = snapshot.minX - initial.minX
            let relativeY = snapshot.minY - initial.minY
            let newWidth = max(minimumShapeDimension, snapshot.width * sx)
            let newHeight = max(minimumShapeDimension, snapshot.height * sy)
            let newOrigin = CGPoint(
                x: target.minX + relativeX * sx,
                y: target.minY + relativeY * sy
            )

            drawings[idx].origin = newOrigin
            drawings[idx].size = CGSize(width: newWidth, height: newHeight)
        }
    }

    func finishSelectedShapeResize() {
        guard let session = groupShapeResizeSession else { return }
        groupShapeResizeSession = nil

        for id in session.selectedShapeIds {
            guard let drawing = drawings.first(where: { $0.id == id }) else { continue }
            saveDrawing(drawing)
        }
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
        var w = point.x - drawing.origin.x
        var h = point.y - drawing.origin.y

        // Shift-constrain to 1:1 aspect ratio
        if shiftConstrain {
            let side = max(abs(w), abs(h))
            w = w < 0 ? -side : side
            h = h < 0 ? -side : side
        }

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
            registerUndo(CreateDrawingAction(drawing: drawing, drawingState: self))
        }
        activeDrawing = nil
    }

    // MARK: - Freehand Gesture Handling

    func beginFreehand(at point: CGPoint) {
        activePathPoints = [point]
        activePathWidths = [currentStrokeWidth]
        lastPointTimestamp = Date()
        lastPointPosition = point
        activeDrawing = CanvasDrawing(
            drawingType: .freehand,
            origin: point,
            pathPoints: [point],
            pathWidths: [currentStrokeWidth],
            strokeColor: currentStrokeColor,
            strokeWidth: currentStrokeWidth
        )
    }

    func addFreehandPoint(_ point: CGPoint) {
        // Compute velocity-based width (Craft-style: very subtle variation)
        let now = Date()
        var width = currentStrokeWidth

        if let lastTime = lastPointTimestamp, let lastPos = lastPointPosition {
            let dt = now.timeIntervalSince(lastTime)
            if dt > 0 {
                let distance = hypot(point.x - lastPos.x, point.y - lastPos.y)
                let velocity = distance / (dt * 1000) // px per ms

                // Subtle velocity mapping: slow = 1.12× base, fast = 0.88× base
                // Much gentler than before — Craft-like consistency with hints of variation
                let factor = max(0.88, min(1.12, 1.12 - velocity * 0.12))
                width = currentStrokeWidth * factor
            }
        }

        // Heavy smoothing to prevent any visible jumps (80% previous, 20% new)
        if let lastWidth = activePathWidths.last {
            width = lastWidth * 0.8 + width * 0.2
        }

        activePathPoints.append(point)
        activePathWidths.append(width)
        activeDrawing?.pathPoints = activePathPoints
        activeDrawing?.pathWidths = activePathWidths

        lastPointTimestamp = now
        lastPointPosition = point
    }

    func finishFreehand() {
        guard var drawing = activeDrawing, activePathPoints.count > 1 else {
            activeDrawing = nil
            activePathPoints = []
            activePathWidths = []
            lastPointTimestamp = nil
            lastPointPosition = nil
            return
        }

        // Save exactly what was shown during live preview — no post-processing.
        // The renderer already applies Catmull-Rom bezier smoothing at render time,
        // so the stored points don't need to be modified.
        drawing.pathPoints = activePathPoints
        drawing.pathWidths = activePathWidths
        drawing.zIndex = (drawings.map(\.zIndex).max() ?? 0) + 1
        saveDrawing(drawing)
        registerUndo(CreateDrawingAction(drawing: drawing, drawingState: self))
        activeDrawing = nil
        activePathPoints = []
        activePathWidths = []
        lastPointTimestamp = nil
        lastPointPosition = nil
    }

    /// 3-point moving average smoothing
    private func smoothPoints(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var result = [points[0]]
        for i in 1..<(points.count - 1) {
            let avg = CGPoint(
                x: (points[i-1].x + points[i].x + points[i+1].x) / 3.0,
                y: (points[i-1].y + points[i].y + points[i+1].y) / 3.0
            )
            result.append(avg)
        }
        result.append(points.last!)
        return result
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

    // MARK: - Zone Gesture Handling

    func beginZone(at point: CGPoint) {
        zoneStartPoint = point
        activeZoneRect = CGRect(origin: point, size: .zero)
    }

    func updateZone(to point: CGPoint) {
        guard let start = zoneStartPoint else { return }
        let x = min(start.x, point.x)
        let y = min(start.y, point.y)
        let w = abs(point.x - start.x)
        let h = abs(point.y - start.y)
        activeZoneRect = CGRect(x: x, y: y, width: w, height: h)
    }

    /// Finishes the zone drag. Returns the canvas-space rect if large enough, otherwise nil.
    func finishZone() -> CGRect? {
        guard let rect = activeZoneRect,
              rect.width > 20, rect.height > 20 else {
            activeZoneRect = nil
            zoneStartPoint = nil
            return nil
        }
        let result = rect
        activeZoneRect = nil
        zoneStartPoint = nil
        return result
    }

    // MARK: - Ramer-Douglas-Peucker Path Simplification

    func simplifyPath(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2, let first = points.first, let last = points.last else { return points }

        // Find the point with maximum distance from the line between first and last
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

    private func primarySelectedDrawingId() -> String? {
        drawings.last(where: { selectedDrawingIds.contains($0.id) })?.id ?? selectedDrawingIds.first
    }

    // MARK: - Recent Colors

    func trackRecentColor(_ hex: String) {
        recentColors.removeAll { $0 == hex }
        recentColors.insert(hex, at: 0)
        if recentColors.count > 4 {
            recentColors = Array(recentColors.prefix(4))
        }
    }
}
