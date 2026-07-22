import SwiftUI

#if DEBUG
/// TEMPORARY diagnostic for the stuck/clipped quick look — appends geometry
/// truth to /tmp/cosmo-quicklook-debug.log on every body pass so the SwiftUI
/// state can be compared against what the screen shows. Remove when closed.
enum SwipeQuickLookDebugLog {
    nonisolated(unsafe) private static var lastLine = ""
    private static let url = URL(fileURLWithPath: "/tmp/cosmo-quicklook-debug.log")

    static func log(_ line: String) {
        guard line != lastLine else { return }
        lastLine = line
        let stamped = "\(Date().timeIntervalSince1970) \(line)\n"
        if let data = stamped.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    /// Dump every glass-flavored AppKit view in the key window: real frames,
    /// layer presentation values, and one level of children.
    @MainActor
    static func dumpGlassViews() {
        guard let root = NSApp.keyWindow?.contentView else {
            log("GLASS-DUMP no key window")
            return
        }
        var found = 0
        func walk(_ view: NSView) {
            let cls = String(describing: type(of: view))
            if cls.localizedCaseInsensitiveContains("glass") {
                found += 1
                let inWindow = view.superview?.convert(view.frame, to: nil) ?? view.frame
                var line = "GLASS-DUMP \(cls) frame=\(view.frame) inWindow=\(inWindow)"
                if let layer = view.layer {
                    line += " layerBounds=\(layer.bounds) tf=\(layer.affineTransform())"
                    if let pres = layer.presentation() {
                        line += " presBounds=\(pres.bounds) presTF=\(pres.affineTransform())"
                    }
                }
                log(line)
                for sub in view.subviews {
                    let subIn = view.convert(sub.frame, to: nil)
                    log("GLASS-DUMP   child \(String(describing: type(of: sub))) frame=\(sub.frame) inWindow=\(subIn)")
                }
            }
            view.subviews.forEach(walk)
        }
        walk(root)
        log("GLASS-DUMP done, glassViews=\(found)")
    }
}
#endif

// MARK: - Frame store

/// Last-known media frames of on-screen cards, in page coordinates. A plain class
/// (not @Observable) — cells write on scroll, nothing re-renders; the quick look
/// and hero read a frame once at the moment they open or close. Main-thread only.
final class SwipeFrameStore {
    var frames: [String: CGRect] = [:]
}

/// Geometry shared by the quick look and the study hero so handoffs line up.
/// July 2026: the panel IS the post — sized to the medium's honest aspect
/// (9:16 reel, square carousel, 16:9 video) plus one footer bar. Library
/// previews moved to SwipePreviewSidebar; this shell now serves the Discover
/// quick look and the study hero's target frame.
enum SwipeQuickLookGeometry {
    static let footerHeight: CGFloat = 56

    static func panelFrame(in size: CGSize, aspect: SwipeCardAspect? = nil) -> CGRect {
        let maxWidth = max(320, size.width - 160)
        let maxHeight = size.height * 0.9

        var width: CGFloat
        var height: CGFloat

        switch aspect {
        case .vertical:
            // 9:16 reel — height-major, width re-clamped for narrow windows.
            let mediaHeight = min(maxHeight - footerHeight, 760)
            let mediaWidth = min(mediaHeight * 9 / 16, maxWidth)
            width = mediaWidth
            height = min(mediaWidth * 16 / 9, maxHeight - footerHeight) + footerHeight
        case .portrait:
            // Square carousel stage.
            let side = min(540, maxWidth, maxHeight - footerHeight)
            width = side
            height = side + footerHeight
        case .wide:
            let mediaWidth = min(760, maxWidth, (maxHeight - footerHeight) * 16 / 9)
            width = mediaWidth
            height = mediaWidth * 9 / 16 + footerHeight
        case .paper:
            width = min(480, maxWidth)
            height = min(520, maxHeight)
        case nil:
            // Legacy shape (Discover quick look).
            width = min(680, max(420, size.width - 160))
            height = min(maxHeight * 0.98, 780)
        }

        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
    }
}

// MARK: - Quick look shell

/// Click-to-preview: the panel grows out of the clicked card's frame into a centered
/// glass panel ("the card becomes the page"). The page owns `expanded` so Esc, the
/// scrim, the close button, and Open Study all collapse through one path.
///
/// Continuity: `heroModel` renders the card's media inside the panel while it is
/// collapsed, crossfading with the real content as the frame springs — so the
/// thumbnail is what grows out of the grid and what lands back in it, never an
/// empty glass shell. The page hides the source card while the panel is up, so
/// the thumbnail visibly returns into the gap it left.
struct SwipeQuickLook<Content: View>: View {
    @Binding var expanded: Bool
    let sourceFrame: CGRect?
    var heroModel: SwipeCardModel?
    /// When set, the panel takes the medium's honest shape (reel/square/wide)
    /// instead of the legacy document shape.
    var panelAspect: SwipeCardAspect?
    let onRequestClose: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let target = SwipeQuickLookGeometry.panelFrame(in: proxy.size, aspect: panelAspect)
            let fallback = target.insetBy(
                dx: target.width * 0.04,
                dy: target.height * 0.04
            )
            // A card frame that scrolled out of the viewport is stale — fall
            // back to a centered fade rather than flying to a wrong point.
            let collapsed = sourceFrame.flatMap { $0.intersects(bounds) ? $0 : nil } ?? fallback
            let frame = expanded ? target : collapsed
            let scaleX = frame.width / max(target.width, 1)
            let scaleY = frame.height / max(target.height, 1)

            #if DEBUG
            let _ = SwipeQuickLookDebugLog.log(
                "SHELL expanded=\(expanded) proxy=\(proxy.size) aspect=\(String(describing: panelAspect)) "
                + "target=\(target) collapsed=\(collapsed) frame=\(frame) source=\(String(describing: sourceFrame)) "
                + "hero=\(heroModel != nil)"
            )
            #endif

            ZStack(alignment: .topLeading) {
                Color.black.opacity(expanded ? 0.30 : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onRequestClose)

                ZStack {
                    content()
                        .opacity(expanded ? 1 : 0)
                    if let heroModel {
                        SwipeQuickLookHeroThumbnail(model: heroModel)
                            .opacity(expanded ? 0 : 1)
                            .allowsHitTesting(false)
                    }
                }
                // INVARIANT: the panel's LAYOUT size never animates — it is
                // always laid out at the settled target, and the card→panel
                // flight is transforms only (scale + position). Springing the
                // frame itself re-laid-out the AppKit-backed glass layer ~60×/s
                // through transient (and overshooting) sizes, and that layer
                // latches a transient size until its next invalidation — which
                // is what left previews clipped at rest: media cropped at the
                // top, the footer's Open Study button spilling past the panel.
                // (Pure-SwiftUI layout of this content is proven correct; the
                // desync lived entirely in the glass layer. July 2026.)
                .frame(width: target.width, height: target.height)
                .cosmoGlassPanel(
                    role: .floatingAssistant,
                    // Collapsed radius is compensated for the down-scale so the
                    // shrunk panel still lands on the card with its 14pt corners.
                    cornerRadius: expanded ? 24 : 14 / max(scaleX, 0.05)
                )
                .scaleEffect(x: scaleX, y: scaleY)
                .position(x: frame.midX, y: frame.midY)
            }
        }
        .onAppear(perform: expandOnMount)
        #if DEBUG
        .onChange(of: expanded) { _, isExpanded in
            guard isExpanded else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                SwipeQuickLookDebugLog.dumpGlassViews()
            }
        }
        #endif
        .onExitCommand(perform: onRequestClose)
    }

    private func expandOnMount() {
        #if DEBUG
        SwipeQuickLookDebugLog.log("EXPAND-ON-MOUNT expanded=\(expanded) reduceMotion=\(reduceMotion)")
        #endif
        guard !expanded else { return }
        if reduceMotion {
            expanded = true
            return
        }
        withAnimation(ProMotionSprings.modal) { expanded = true }
    }
}

/// The continuity layer: the card's media (already cached by the grid, so it
/// mounts without a flash) filling the collapsed panel.
private struct SwipeQuickLookHeroThumbnail: View {
    let model: SwipeCardModel

    var body: some View {
        Group {
            if model.aspect == .paper {
                Text(model.paperText ?? model.hookText)
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)
                    .lineSpacing(3)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(DS.glassSectionFill)
            } else {
                CachedAsyncImage(url: model.mediaURL, stableKey: model.mediaStableKey) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty, .failure:
                        Rectangle().fill(DS.glassSectionFill)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityHidden(true)
    }
}

// MARK: - Media well (natural aspect — Discover quick look)

/// Quick-look media at the post's own aspect ratio — width-fit, height-capped,
/// edge-to-edge fill on a warm well. No black letterbox.
struct SwipeQuickLookMedia: View {
    let url: URL?
    let stableKey: String?
    let aspect: SwipeCardAspect
    var fallbackGlyph: String?

    /// The well breathes with the medium: reels get a tall stage, posts a
    /// squarer one, videos a wide one.
    private var wellHeight: CGFloat {
        switch aspect {
        case .wide: 320
        case .portrait: 380
        case .vertical: 440
        case .paper: 320
        }
    }

    var body: some View {
        CachedAsyncImage(url: url, stableKey: stableKey) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            case .empty, .failure:
                Rectangle()
                    .fill(.clear)
                    .overlay {
                        Image(systemName: fallbackGlyph ?? "photo")
                            .font(DS.title2)
                            .foregroundStyle(DS.textMuted)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: wellHeight)
        .background(DS.glassSectionFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Icon button

struct SwipeQuickLookIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(hovering ? DS.text : DS.textSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(hovering ? DS.glassInputFill : Color.clear))
                .overlay(Circle().strokeBorder(DS.glassBorder, lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { value in withAnimation(ProMotionSprings.hover) { hovering = value } }
        .help(help)
        .accessibilityLabel(help)
    }
}
