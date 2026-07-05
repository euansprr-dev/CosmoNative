import SwiftUI
import AppKit

@MainActor
final class CanvasGridPatternCache {
    static let shared = CanvasGridPatternCache()

    struct Key: Hashable {
        let spacing: Int
        let dotSize: Int
        let tileMultiplier: Int
    }

    private var images: [Key: NSImage] = [:]

    /// Pack several dots into one tile when spacing gets small so the tiled
    /// image never degenerates into a sub-pixel stamp.
    nonisolated static func tileMultiplier(for spacing: CGFloat) -> Int {
        switch spacing {
        case ..<14:
            return 5
        case ..<20:
            return 4
        case ..<30:
            return 3
        case ..<44:
            return 2
        default:
            return 1
        }
    }

    nonisolated func tileMultiplier(for spacing: CGFloat) -> Int {
        Self.tileMultiplier(for: spacing)
    }

    func image(spacing: CGFloat, dotSize: CGFloat, tileMultiplier: Int) -> NSImage {
        let key = Key(
            spacing: max(Int((spacing * 100).rounded()), 1),
            dotSize: max(Int((dotSize * 100).rounded()), 1),
            tileMultiplier: max(tileMultiplier, 1)
        )

        if let existing = images[key] {
            return existing
        }

        let image = buildImage(
            spacing: CGFloat(key.spacing) / 100,
            dotSize: CGFloat(key.dotSize) / 100,
            tileMultiplier: key.tileMultiplier
        )
        images[key] = image
        return image
    }

    /// Draws one tile with dot centers at `(i + 0.5)·spacing` (inset from the
    /// edges so tiles join without seams), backed at 2x so the pattern stays
    /// crisp on Retina displays.
    private func buildImage(spacing: CGFloat, dotSize: CGFloat, tileMultiplier: Int) -> NSImage {
        let tileSize = max(spacing * CGFloat(tileMultiplier), 1)
        let pixelScale: CGFloat = 2
        let pixelSide = max(Int((tileSize * pixelScale).rounded()), 1)

        let image = NSImage(size: NSSize(width: tileSize, height: tileSize))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSide,
            pixelsHigh: pixelSide,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return image
        }
        rep.size = NSSize(width: tileSize, height: tileSize)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: NSSize(width: tileSize, height: tileSize)).fill()

        let dotColor = NSColor(
            srgbRed: 216.0 / 255.0,
            green: 215.0 / 255.0,
            blue: 211.0 / 255.0,
            alpha: 0.5
        )
        dotColor.setFill()

        for xIndex in 0..<tileMultiplier {
            for yIndex in 0..<tileMultiplier {
                let center = CGPoint(
                    x: (CGFloat(xIndex) + 0.5) * spacing,
                    y: (CGFloat(yIndex) + 0.5) * spacing
                )
                let rect = CGRect(
                    x: center.x - dotSize / 2,
                    y: center.y - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )
                NSBezierPath(ovalIn: rect).fill()
            }
        }

        NSGraphicsContext.restoreGraphicsState()
        image.addRepresentation(rep)
        return image
    }
}
