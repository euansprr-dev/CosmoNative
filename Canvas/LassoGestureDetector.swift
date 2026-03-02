// CosmoOS/Canvas/LassoGestureDetector.swift
// Point-in-polygon detection for lasso selection tool

import Foundation

struct LassoGestureDetector {

    /// Check if a point is inside a polygon using ray casting algorithm
    static func pointInPolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }

        var inside = false
        var j = polygon.count - 1

        for i in 0..<polygon.count {
            let pi = polygon[i]
            let pj = polygon[j]

            if (pi.y > point.y) != (pj.y > point.y) {
                let intersectX = (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x
                if point.x < intersectX {
                    inside.toggle()
                }
            }
            j = i
        }

        return inside
    }

    /// Find all block IDs where ANY of the 5 test points (center + 4 corners)
    /// fall inside the lasso path. This catches blocks mostly inside the lasso
    /// even when their center is just outside.
    /// blockFrames maps blockId -> CGRect in the same coordinate space as lassoPath.
    static func enclosedBlocks(lassoPath: [CGPoint], blockFrames: [String: CGRect]) -> [String] {
        guard lassoPath.count >= 3 else { return [] }

        var enclosed: [String] = []
        for (blockId, frame) in blockFrames {
            let testPoints = [
                CGPoint(x: frame.midX, y: frame.midY),      // center
                CGPoint(x: frame.minX, y: frame.minY),      // top-left
                CGPoint(x: frame.maxX, y: frame.minY),      // top-right
                CGPoint(x: frame.minX, y: frame.maxY),      // bottom-left
                CGPoint(x: frame.maxX, y: frame.maxY),      // bottom-right
            ]
            if testPoints.contains(where: { pointInPolygon($0, polygon: lassoPath) }) {
                enclosed.append(blockId)
            }
        }
        return enclosed
    }
}
