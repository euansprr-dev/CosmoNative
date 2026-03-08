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

    func tileMultiplier(for spacing: CGFloat) -> Int {
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

    private func buildImage(spacing: CGFloat, dotSize: CGFloat, tileMultiplier: Int) -> NSImage {
        let tileSize = max(spacing * CGFloat(tileMultiplier), 1)
        let image = NSImage(size: CGSize(width: tileSize, height: tileSize))
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()

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
                    x: CGFloat(xIndex) * spacing,
                    y: CGFloat(yIndex) * spacing
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

        return image
    }
}
