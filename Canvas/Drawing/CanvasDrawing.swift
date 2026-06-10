// CosmoOS/Canvas/Drawing/CanvasDrawing.swift
// Data model for canvas drawing elements (shapes, freehand, text)

import SwiftUI

// MARK: - Enums

enum DrawingType: String, Codable {
    case shape
    case freehand
    case text
}

enum ShapeKind: String, Codable, CaseIterable {
    case rectangle
    case roundedRectangle
    case circle
    case line
    case arrow
    case triangle
}

enum DrawingTextWeight: String, Codable, CaseIterable {
    case S, M, L, X, XL

    var fontSize: CGFloat {
        switch self {
        case .S: return 11
        case .M: return 15
        case .L: return 22
        case .X: return 28
        case .XL: return 36
        }
    }

    var fontWeight: Font.Weight {
        switch self {
        case .S: return .regular
        case .M: return .medium
        case .L: return .semibold
        case .X: return .bold
        case .XL: return .heavy
        }
    }
}

// MARK: - CanvasDrawing

struct CanvasDrawing: Identifiable, Codable {
    var id: String
    var drawingType: DrawingType
    var shapeKind: ShapeKind?
    var origin: CGPoint
    var size: CGSize?
    var rotation: Double
    var pathPoints: [CGPoint]?
    var pathWidths: [CGFloat]?  // Per-point width for velocity-sensitive strokes
    var textContent: String?
    var textWeight: DrawingTextWeight?
    var strokeColor: String  // hex
    var fillColor: String?   // hex
    var strokeWidth: CGFloat
    var opacity: Double
    var zIndex: Int

    init(
        id: String = UUID().uuidString,
        drawingType: DrawingType,
        shapeKind: ShapeKind? = nil,
        origin: CGPoint = .zero,
        size: CGSize? = nil,
        rotation: Double = 0,
        pathPoints: [CGPoint]? = nil,
        pathWidths: [CGFloat]? = nil,
        textContent: String? = nil,
        textWeight: DrawingTextWeight? = nil,
        strokeColor: String = "#1A1A1A",
        fillColor: String? = nil,
        strokeWidth: CGFloat = 2.5,
        opacity: Double = 1.0,
        zIndex: Int = 0
    ) {
        self.id = id
        self.drawingType = drawingType
        self.shapeKind = shapeKind
        self.origin = origin
        self.size = size
        self.rotation = rotation
        self.pathPoints = pathPoints
        self.pathWidths = pathWidths
        self.textContent = textContent
        self.textWeight = textWeight
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.strokeWidth = strokeWidth
        self.opacity = opacity
        self.zIndex = zIndex
    }

    // MARK: - Bounding Rect

    var boundingRect: CGRect {
        switch drawingType {
        case .shape:
            let s = size ?? CGSize(width: 100, height: 100)
            return CGRect(origin: origin, size: s)

        case .freehand:
            guard let points = pathPoints, !points.isEmpty else {
                return CGRect(origin: origin, size: CGSize(width: 1, height: 1))
            }
            var minX = CGFloat.infinity, minY = CGFloat.infinity
            var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
            for pt in points {
                minX = min(minX, pt.x)
                minY = min(minY, pt.y)
                maxX = max(maxX, pt.x)
                maxY = max(maxY, pt.y)
            }
            let padding = strokeWidth / 2
            return CGRect(
                x: minX - padding, y: minY - padding,
                width: maxX - minX + strokeWidth,
                height: maxY - minY + strokeWidth
            )

        case .text:
            let weight = textWeight ?? .M
            let text = textContent ?? ""
            let charWidth = weight.fontSize * 0.6
            let estimatedWidth = max(CGFloat(text.count) * charWidth, 40)
            let estimatedHeight = weight.fontSize * 1.4
            return CGRect(origin: origin, size: CGSize(width: estimatedWidth, height: estimatedHeight))
        }
    }

    // MARK: - Record Conversion

    func toRecord(thinkspaceId: String?) -> CanvasDrawingRecord {
        var pathData: String? = nil
        if let points = pathPoints {
            let widths = pathWidths
            let pointDicts: [[String: Double]] = points.enumerated().map { i, pt in
                var dict: [String: Double] = ["x": pt.x, "y": pt.y]
                if let widths, i < widths.count {
                    dict["w"] = Double(widths[i])
                }
                return dict
            }
            if let data = try? JSONSerialization.data(withJSONObject: pointDicts),
               let str = String(data: data, encoding: .utf8) {
                pathData = str
            }
        }

        return CanvasDrawingRecord(
            id: id,
            thinkspaceId: thinkspaceId,
            drawingType: drawingType.rawValue,
            shapeKind: shapeKind?.rawValue,
            originX: Double(origin.x),
            originY: Double(origin.y),
            width: size.map { Double($0.width) },
            height: size.map { Double($0.height) },
            rotation: rotation,
            pathData: pathData,
            textContent: textContent,
            textWeight: textWeight?.rawValue,
            strokeColor: strokeColor,
            fillColor: fillColor,
            strokeWidth: Double(strokeWidth),
            opacity: opacity,
            zIndex: zIndex,
            isDeleted: false,
            createdAt: ISO8601.string(from: Date()),
            updatedAt: ISO8601.string(from: Date())
        )
    }

    init(from record: CanvasDrawingRecord) {
        self.id = record.id
        self.drawingType = DrawingType(rawValue: record.drawingType) ?? .freehand
        self.shapeKind = record.shapeKind.flatMap { ShapeKind(rawValue: $0) }
        self.origin = CGPoint(x: record.originX, y: record.originY)
        if let w = record.width, let h = record.height {
            self.size = CGSize(width: w, height: h)
        } else {
            self.size = nil
        }
        self.rotation = record.rotation ?? 0
        self.textContent = record.textContent
        self.textWeight = record.textWeight.flatMap { DrawingTextWeight(rawValue: $0) }
        self.strokeColor = record.strokeColor
        self.fillColor = record.fillColor
        self.strokeWidth = record.strokeWidth
        self.opacity = record.opacity
        self.zIndex = record.zIndex ?? 0

        // Parse path data (supports optional per-point width via "w" key)
        if let pathData = record.pathData,
           let data = pathData.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Double]] {
            self.pathPoints = arr.compactMap { dict in
                guard let x = dict["x"], let y = dict["y"] else { return nil }
                return CGPoint(x: x, y: y)
            }
            let widths = arr.compactMap { $0["w"] }.map { CGFloat($0) }
            self.pathWidths = widths.isEmpty ? nil : widths
        } else {
            self.pathPoints = nil
            self.pathWidths = nil
        }
    }

    // MARK: - Color Helpers

    static func colorFromHex(_ hex: String) -> Color {
        let components = rgbComponents(from: hex)
        guard let components else {
            return Color(red: 0.1, green: 0.1, blue: 0.1)
        }
        return Color(red: components.red, green: components.green, blue: components.blue)
    }

    static func themeResolvedColorFromHex(_ hex: String) -> Color {
        if !DS.palette.isDark, isAdaptiveCanvasWhite(hex) {
            return DS.text
        }
        return colorFromHex(hex)
    }

    private static func rgbComponents(from hex: String) -> (red: Double, green: Double, blue: Double)? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6,
              let val = UInt64(cleaned, radix: 16) else {
            return nil
        }
        let r = Double((val >> 16) & 0xFF) / 255.0
        let g = Double((val >> 8) & 0xFF) / 255.0
        let b = Double(val & 0xFF) / 255.0
        return (r, g, b)
    }

    private static func isAdaptiveCanvasWhite(_ hex: String) -> Bool {
        guard let components = rgbComponents(from: hex) else { return false }
        return components.red >= 0.94 &&
            components.green >= 0.94 &&
            components.blue >= 0.94
    }

    var strokeSwiftUIColor: Color {
        Self.themeResolvedColorFromHex(strokeColor)
    }

    var fillSwiftUIColor: Color? {
        fillColor.map { Self.themeResolvedColorFromHex($0) }
    }
}
