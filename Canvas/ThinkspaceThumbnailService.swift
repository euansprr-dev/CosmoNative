// CosmoOS/Canvas/ThinkspaceThumbnailService.swift
// Renders cached bitmap miniatures of thinkspace canvases — blocks as
// entity-tinted rounded rects at true positions, cluster zones as soft washes.
// Powers the Constellation, portals, and workbench previews. Never renders
// a live canvas; consumers draw cached bitmaps only.

import SwiftUI
import AppKit
import GRDB

@MainActor
final class ThinkspaceThumbnailService {

    static let shared = ThinkspaceThumbnailService()

    private struct CachedThumbnail {
        let image: NSImage
        let generatedAt: Date
    }

    private var cache: [String: CachedThumbnail] = [:]
    private var inFlight: Set<String> = []

    private let freshness: TimeInterval = 60

    // MARK: - Public

    /// Cached thumbnail if one exists (any age) — for instant first paint.
    func cachedThumbnail(for thinkspaceId: String) -> NSImage? {
        cache[thinkspaceId]?.image
    }

    /// Render (or return fresh-cached) thumbnail for a thinkspace.
    func thumbnail(for thinkspaceId: String, size: CGSize) async -> NSImage? {
        if let cached = cache[thinkspaceId],
           Date().timeIntervalSince(cached.generatedAt) < freshness {
            return cached.image
        }
        guard !inFlight.contains(thinkspaceId) else {
            return cache[thinkspaceId]?.image
        }
        inFlight.insert(thinkspaceId)
        defer { inFlight.remove(thinkspaceId) }

        guard let scene = await loadScene(for: thinkspaceId) else { return nil }

        let pixelSize = CGSize(width: size.width * 2, height: size.height * 2)
        let image = await Task.detached(priority: .userInitiated) {
            Self.render(scene: scene, size: pixelSize)
        }.value

        guard let image else { return nil }
        cache[thinkspaceId] = CachedThumbnail(image: image, generatedAt: Date())
        return image
    }

    /// Drop the cache for a thinkspace (call after its canvas saves).
    func invalidate(_ thinkspaceId: String) {
        cache.removeValue(forKey: thinkspaceId)
    }

    // MARK: - Scene loading

    /// Everything the renderer needs, in plain Sendable values.
    struct Scene: Sendable {
        struct Block: Sendable {
            let rect: CGRect
            let rgba: RGBA
        }
        struct Zone: Sendable {
            let rect: CGRect
            let rgba: RGBA
        }
        struct RGBA: Sendable {
            let r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
        }
        var blocks: [Block]
        var zones: [Zone]
        var background: RGBA
    }

    private func loadScene(for thinkspaceId: String) async -> Scene? {
        let records: [CanvasBlockRecord]
        do {
            records = try await CosmoDatabase.shared.asyncRead { db in
                try CanvasBlockRecord
                    .filter(Column("thinkspace_id") == thinkspaceId)
                    .filter(Column("is_deleted") == false)
                    .fetchAll(db)
            }
        } catch {
            print("❌ Thumbnail scene load failed: \(error)")
            return nil
        }

        let blocks: [Scene.Block] = records.map { record in
            let rect = CGRect(
                x: CGFloat(record.positionX),
                y: CGFloat(record.positionY),
                width: CGFloat(record.width ?? 320),
                height: CGFloat(record.height ?? 200)
            )
            let color = EntityType(rawValue: record.entityType)?.color ?? DS.textMuted
            return Scene.Block(rect: rect, rgba: Self.rgba(from: color))
        }

        var zones: [Scene.Zone] = []
        if let atom = try? await AtomRepository.shared.fetch(uuid: thinkspaceId),
           let metadata = atom.metadataValue(as: ThinkspaceMetadata.self) {
            zones = metadata.clusters.compactMap { cluster in
                guard let x = cluster.originX, let y = cluster.originY,
                      let w = cluster.rectWidth, let h = cluster.rectHeight else { return nil }
                let color = CanvasCluster.palette[cluster.colorIndex % CanvasCluster.palette.count]
                return Scene.Zone(
                    rect: CGRect(x: x, y: y, width: w, height: h),
                    rgba: Self.rgba(from: color)
                )
            }
        }

        guard !blocks.isEmpty || !zones.isEmpty else { return nil }
        return Scene(blocks: blocks, zones: zones, background: Self.rgba(from: DS.canvas))
    }

    private static func rgba(from color: Color) -> Scene.RGBA {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .gray
        return Scene.RGBA(
            r: ns.redComponent,
            g: ns.greenComponent,
            b: ns.blueComponent,
            a: ns.alphaComponent
        )
    }

    // MARK: - Rendering (off-main, CGContext)

    nonisolated private static func render(scene: Scene, size: CGSize) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }

        // Content bounds with breathing room
        var bounds = CGRect.null
        for block in scene.blocks { bounds = bounds.union(block.rect) }
        for zone in scene.zones { bounds = bounds.union(zone.rect) }
        guard !bounds.isNull else { return nil }
        bounds = bounds.insetBy(dx: -100, dy: -100)
        if bounds.width < 800 { bounds = bounds.insetBy(dx: -(800 - bounds.width) / 2, dy: 0) }
        if bounds.height < 500 { bounds = bounds.insetBy(dx: 0, dy: -(500 - bounds.height) / 2) }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        func set(_ rgba: Scene.RGBA, alpha: CGFloat) {
            context.setFillColor(CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: alpha))
        }

        // Background
        set(scene.background, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))

        // Aspect-fit transform from canvas space to image space.
        // Canvas Y grows downward; CGContext Y grows upward — flip.
        let scale = min(size.width / bounds.width, size.height / bounds.height)
        let offsetX = (size.width - bounds.width * scale) / 2
        let offsetY = (size.height - bounds.height * scale) / 2

        func mapped(_ rect: CGRect) -> CGRect {
            let x = (rect.minX - bounds.minX) * scale + offsetX
            let yTop = (rect.minY - bounds.minY) * scale + offsetY
            let height = rect.height * scale
            let y = size.height - yTop - height
            return CGRect(x: x, y: y, width: rect.width * scale, height: height)
        }

        // Cluster zones first — soft washes with a hairline
        for zone in scene.zones {
            let rect = mapped(zone.rect)
            let path = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
            set(zone.rgba, alpha: 0.10)
            context.addPath(path)
            context.fillPath()
            context.setStrokeColor(CGColor(srgbRed: zone.rgba.r, green: zone.rgba.g, blue: zone.rgba.b, alpha: 0.30))
            context.setLineWidth(1)
            context.addPath(path)
            context.strokePath()
        }

        // Blocks — tinted rounded rects
        for block in scene.blocks {
            var rect = mapped(block.rect)
            // Keep tiny blocks visible
            rect.size.width = max(rect.width, 3)
            rect.size.height = max(rect.height, 3)
            let radius = min(3, rect.width / 3)
            let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            set(block.rgba, alpha: 0.85)
            context.addPath(path)
            context.fillPath()
        }

        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: CGSize(width: size.width / 2, height: size.height / 2))
    }
}
