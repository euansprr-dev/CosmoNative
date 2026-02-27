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

    /// Find all block IDs whose centers are enclosed by the lasso path.
    /// blockFrames maps blockId -> CGRect in the same coordinate space as lassoPath.
    static func enclosedBlocks(lassoPath: [CGPoint], blockFrames: [String: CGRect]) -> [String] {
        guard lassoPath.count >= 3 else { return [] }

        var enclosed: [String] = []
        for (blockId, frame) in blockFrames {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            if pointInPolygon(center, polygon: lassoPath) {
                enclosed.append(blockId)
            }
        }
        return enclosed
    }
}
