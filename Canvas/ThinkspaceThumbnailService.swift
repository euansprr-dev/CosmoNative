// CosmoOS/Canvas/ThinkspaceThumbnailService.swift
// Renders cached bitmap miniatures of thinkspace canvases — blocks as
// entity-tinted rounded rects at true positions, cluster zones as soft washes.
// Powers the Constellation, portals, and workbench previews. Never renders
// a live canvas; consumers draw cached bitmaps only.

import SwiftUI
import AppKit
import GRDB

// MARK: - Snapshot Proxy

/// An invisible NSView embedded in the canvas so the real rendered pixels can
/// be captured (SwiftUI's ImageRenderer can't see NSViewRepresentable content;
/// snapshotting the window's layer tree can).
struct CanvasSnapshotProxy: NSViewRepresentable {
    let onReady: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onReady(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Tracks whether the Constellation overlay is anywhere on screen — including
/// its fade-out transition after a dismiss or a dive. Canvas screenshot capture
/// consults this because captures composite the window's full layer tree:
/// a capture taken while the Constellation is still visible (even mid-fade)
/// would store the Constellation grid itself as a thinkspace's thumbnail.
@MainActor
final class ConstellationPresentationState {
    static let shared = ConstellationPresentationState()
    private(set) var isOnScreen = false
    func setOnScreen(_ onScreen: Bool) { isOnScreen = onScreen }
}

/// Tracks whether the Command-K palette is visibly on screen — including its
/// fade-out transition. The palette outlives its `showCommandK` flag two ways:
/// the dismiss fade is still running, or the view stays mounted at opacity 0
/// behind a focus mode for state preservation (visibility, not mount state, is
/// what matters for capture safety). Without this, a Command-K thinkspace jump
/// composites the fading palette into the outgoing thinkspace's thumbnail.
@MainActor
final class CommandKPalettePresentationState {
    static let shared = CommandKPalettePresentationState()
    private(set) var isOnScreen = false
    func setOnScreen(_ onScreen: Bool) { isOnScreen = onScreen }
}

/// Tracks whether the workspace pane deck is anywhere on screen — including
/// its slide-out transition after the last pane closes. While the deck is up
/// (or mid-transition) the canvas rect is squeezed or overlapped, so a capture
/// would store a deck-contaminated frame as the thinkspace's thumbnail.
/// A stale thumbnail beats a corrupted one.
@MainActor
final class PaneDeckPresentationState {
    static let shared = PaneDeckPresentationState()
    private(set) var isOnScreen = false
    func setOnScreen(_ onScreen: Bool) { isOnScreen = onScreen }
}

/// CGImage is immutable and thread-safe; this carries one across actor hops.
private struct PixelPayload: @unchecked Sendable {
    let image: CGImage
}

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

    // MARK: - Real screenshots (preferred)
    // Captured from the actual rendered canvas when you leave a thinkspace —
    // what the Constellation and portals show is what the space really looks
    // like. The vector map below is only the fallback for never-opened spaces.

    private var screenshotCache: [String: NSImage] = [:]
    private var screenshotCapturedAt: [String: Date] = [:]
    private var screenshotGeneration = 0
    private var screenshotGenerationById: [String: Int] = [:]
    private var diskProbedIds: Set<String> = []

    nonisolated private static var screenshotDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("CosmoOS/ThinkspaceScreenshots", isDirectory: true)
    }

    /// Store a freshly captured canvas bitmap. The full-resolution image is
    /// usable from memory immediately (the Constellation's entrance dissolve
    /// reads it on the next frame); downscaling, PNG encoding, and the disk
    /// write all run off the main thread, and the memory cache is swapped to
    /// the downscaled copy once it's ready so retained screenshots stay small.
    func storeScreenshot(_ rep: NSBitmapImageRep, for thinkspaceId: String) {
        let immediate = NSImage(size: rep.size)
        immediate.addRepresentation(rep)
        screenshotCache[thinkspaceId] = immediate
        screenshotCapturedAt[thinkspaceId] = Date()
        diskProbedIds.insert(thinkspaceId)

        guard let cgImage = rep.cgImage else { return }
        screenshotGeneration += 1
        let generation = screenshotGeneration
        screenshotGenerationById[thinkspaceId] = generation
        let payload = PixelPayload(image: cgImage)
        let url = Self.screenshotDirectory.appendingPathComponent("\(thinkspaceId).png")
        Task.detached(priority: .utility) {
            let scaled = Self.downscale(payload.image, maxWidth: 1200)
            let outRep = NSBitmapImageRep(cgImage: scaled)
            if let png = outRep.representation(using: .png, properties: [:]) {
                try? FileManager.default.createDirectory(
                    at: Self.screenshotDirectory,
                    withIntermediateDirectories: true
                )
                try? png.write(to: url)
            }
            let scaledPayload = PixelPayload(image: scaled)
            await MainActor.run {
                ThinkspaceThumbnailService.shared.finishScreenshotStore(
                    scaledPayload, for: thinkspaceId, generation: generation
                )
            }
        }
    }

    /// Swap the transient full-resolution capture for its downscaled copy —
    /// unless a newer capture for this thinkspace superseded it in the meantime.
    private func finishScreenshotStore(
        _ payload: PixelPayload,
        for thinkspaceId: String,
        generation: Int
    ) {
        guard screenshotGenerationById[thinkspaceId] == generation else { return }
        let pointSize = NSSize(
            width: CGFloat(payload.image.width) / 2,
            height: CGFloat(payload.image.height) / 2
        )
        screenshotCache[thinkspaceId] = NSImage(cgImage: payload.image, size: pointSize)
    }

    /// Whether a screenshot for this thinkspace was captured within `interval`.
    /// Presentation paths use this to skip a redundant capture when the zoom
    /// gesture already pre-captured on its way past the floor.
    func hasFreshScreenshot(for thinkspaceId: String, within interval: TimeInterval) -> Bool {
        guard let capturedAt = screenshotCapturedAt[thinkspaceId] else { return false }
        return Date().timeIntervalSince(capturedAt) < interval
    }

    /// The real screenshot for a thinkspace, if one was ever captured.
    func screenshot(for thinkspaceId: String) -> NSImage? {
        if let cached = screenshotCache[thinkspaceId] { return cached }
        guard !diskProbedIds.contains(thinkspaceId) else { return nil }
        diskProbedIds.insert(thinkspaceId)
        let url = Self.screenshotDirectory.appendingPathComponent("\(thinkspaceId).png")
        guard let image = NSImage(contentsOf: url) else { return nil }
        screenshotCache[thinkspaceId] = image
        return image
    }

    nonisolated private static func downscale(_ image: CGImage, maxWidth: CGFloat) -> CGImage {
        let width = CGFloat(image.width)
        guard width > maxWidth,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return image }
        let scale = maxWidth / width
        let targetWidth = Int(maxWidth)
        let targetHeight = Int(CGFloat(image.height) * scale)
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage() ?? image
    }

    // MARK: - Public

    /// Cached thumbnail if one exists (any age) — for instant first paint.
    /// Real screenshots win over vector maps.
    func cachedThumbnail(for thinkspaceId: String) -> NSImage? {
        screenshot(for: thinkspaceId) ?? cache[thinkspaceId]?.image
    }

    /// Best available thumbnail: the real screenshot when one exists,
    /// otherwise the rendered vector map. Disk reads happen off-main here —
    /// the sync `screenshot(for:)` probe is reserved for callers that need
    /// an answer this frame.
    func thumbnail(for thinkspaceId: String, size: CGSize) async -> NSImage? {
        if let shot = screenshotCache[thinkspaceId] {
            return shot
        }
        if !diskProbedIds.contains(thinkspaceId) {
            diskProbedIds.insert(thinkspaceId)
            let url = Self.screenshotDirectory.appendingPathComponent("\(thinkspaceId).png")
            let data = await Task.detached(priority: .userInitiated) {
                try? Data(contentsOf: url)
            }.value
            if let data, let image = NSImage(data: data) {
                screenshotCache[thinkspaceId] = image
                return image
            }
        }
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
