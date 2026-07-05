import SwiftUI

// MARK: - Frame store

/// Last-known media frames of on-screen cards, in page coordinates. A plain class
/// (not @Observable) — cells write on scroll, nothing re-renders; the quick look
/// and hero read a frame once at the moment they open or close. Main-thread only.
final class SwipeFrameStore {
    var frames: [String: CGRect] = [:]
}

/// Geometry shared by the quick look and the study hero so handoffs line up.
enum SwipeQuickLookGeometry {
    static func panelFrame(in size: CGSize) -> CGRect {
        let width = min(680, max(420, size.width - 160))
        let height = min(size.height * 0.88, 780)
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
    let onRequestClose: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let target = SwipeQuickLookGeometry.panelFrame(in: proxy.size)
            let fallback = target.insetBy(
                dx: target.width * 0.04,
                dy: target.height * 0.04
            )
            // A card frame that scrolled out of the viewport is stale — fall
            // back to a centered fade rather than flying to a wrong point.
            let collapsed = sourceFrame.flatMap { $0.intersects(bounds) ? $0 : nil } ?? fallback
            let frame = expanded ? target : collapsed

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
                .frame(width: frame.width, height: frame.height)
                .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: expanded ? 24 : 14)
                .position(x: frame.midX, y: frame.midY)
            }
        }
        .onAppear(perform: expandOnMount)
        .onExitCommand(perform: onRequestClose)
    }

    private func expandOnMount() {
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

// MARK: - Library content

struct SwipeQuickLookLibraryContent: View {
    let item: SwipeGalleryItem
    let model: SwipeCardModel
    var hasPrevious = false
    var hasNext = false
    let onStudy: () -> Void
    let onAddToCanvas: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                SwipeQuickLookBody(item: item, model: model)
                    .id(item.id)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.12), value: item.id)
            footer
        }
    }

    /// Creator identity leads — the quick look is the sanctioned identity
    /// surface, so the platform glyph keeps its brand color here.
    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                if let glyph = model.platformGlyph {
                    Image(systemName: glyph)
                        .font(DS.caption.weight(.semibold))
                        .foregroundStyle(model.platformColor ?? DS.textMuted)
                        .accessibilityHidden(true)
                }
                Text(identityLine)
                    .font(DS.subheadline.weight(.medium))
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                if let age = model.ageLabel {
                    Text("· \(age)")
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                }
            }
            Spacer()
            SwipeQuickLookIconButton(systemImage: "chevron.left", help: "Previous (←)", action: onPrevious)
                .disabled(!hasPrevious)
                .opacity(hasPrevious ? 1 : 0.35)
            SwipeQuickLookIconButton(systemImage: "chevron.right", help: "Next (→)", action: onNext)
                .disabled(!hasNext)
                .opacity(hasNext ? 1 : 0.35)
            SwipeQuickLookIconButton(systemImage: "square.grid.2x2", help: "Add to Canvas", action: onAddToCanvas)
            SwipeQuickLookIconButton(systemImage: "xmark", help: "Close (Esc)", action: onClose)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var identityLine: String {
        model.creatorLine
            ?? SocialPlatform.fromLibraryKey(item.platform)?.displayName
            ?? "Swipe"
    }

    private var footer: some View {
        HStack {
            Button(action: onStudy) {
                HStack(spacing: 7) {
                    Image(systemName: "play.fill")
                        .font(DS.caption.weight(.bold))
                    Text("Open Study")
                        .font(DS.callout.weight(.semibold))
                }
                .foregroundStyle(DS.textOnAccent)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(DS.accent, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Open in Swipe Study (⏎)")

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.glassBorder).frame(height: 0.5)
        }
    }
}

// MARK: - Scrollable body

private struct SwipeQuickLookBody: View {
    let item: SwipeGalleryItem
    let model: SwipeCardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                media
                hookSection
                metadataSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder
    private var media: some View {
        if model.aspect == .paper {
            Text(model.paperText ?? model.hookText)
                .font(DS.body)
                .foregroundStyle(DS.text)
                .lineSpacing(4)
                .textSelection(.enabled)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(DS.glassSectionFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            SwipeQuickLookMedia(
                url: model.mediaURL,
                stableKey: model.mediaStableKey,
                aspect: model.aspect,
                fallbackGlyph: model.platformGlyph
            )
            .accessibilityLabel("Swipe media preview")
        }
    }

    /// The hook IS the headline — no label needed above the one line the
    /// swipe exists for.
    @ViewBuilder
    private var hookSection: some View {
        if model.aspect != .paper {
            Text(model.hookText)
                .font(DS.headline)
                .foregroundStyle(DS.text)
                .lineSpacing(3)
                .textSelection(.enabled)
        }
    }

    private var metadataSection: some View {
        VStack(spacing: 0) {
            metadataRow("Hook type", item.hookType?.displayName)
            metadataRow("Narrative", item.primaryNarrative?.displayName)
            metadataRow("Format", item.swipeContentFormat?.displayName)
            metadataRow("Hook score", item.hookScore.map { String(format: "%.1f", $0) })
            metadataRow("Niche", item.niche)
            metadataRow("Creator", item.creatorName ?? item.author)
        }
        .padding(.vertical, 4)
        .dsGlassSection()
    }

    @ViewBuilder
    private func metadataRow(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack {
                Text(label)
                    .font(DS.subheadline)
                    .foregroundStyle(DS.textMuted)
                Spacer()
                Text(value)
                    .font(DS.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(DS.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Media well (natural aspect)

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
