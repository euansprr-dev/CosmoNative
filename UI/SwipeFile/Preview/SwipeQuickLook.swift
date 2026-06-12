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
struct SwipeQuickLook<Content: View>: View {
    @Binding var expanded: Bool
    let sourceFrame: CGRect?
    let onRequestClose: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let target = SwipeQuickLookGeometry.panelFrame(in: proxy.size)
            let collapsed = sourceFrame ?? target.insetBy(
                dx: target.width * 0.04,
                dy: target.height * 0.04
            )
            let frame = expanded ? target : collapsed

            ZStack(alignment: .topLeading) {
                Color.black.opacity(expanded ? 0.30 : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onRequestClose)

                content()
                    .opacity(expanded ? 1 : 0)
                    .frame(width: frame.width, height: frame.height)
                    .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 24)
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

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                if let glyph = model.platformGlyph {
                    Image(systemName: glyph)
                        .font(DS.caption.weight(.semibold))
                        .foregroundStyle(model.platformColor ?? DS.textMuted)
                        .accessibilityHidden(true)
                }
                Text(SocialPlatform.fromLibraryKey(item.platform)?.displayName ?? "Swipe")
                    .font(DS.subheadline.weight(.medium))
                    .foregroundStyle(DS.textSecondary)
            }
            Spacer()
            SwipeQuickLookIconButton(systemImage: "square.grid.2x2", help: "Add to Canvas", action: onAddToCanvas)
            SwipeQuickLookIconButton(systemImage: "xmark", help: "Close (Esc)", action: onClose)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack {
            Button(action: onStudy) {
                HStack(spacing: 7) {
                    Image(systemName: "play.fill")
                        .font(DS.caption.weight(.bold))
                    Text("Open Study")
                        .font(DS.callout.weight(.semibold))
                    Text("⏎")
                        .font(DS.caption)
                        .opacity(0.7)
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

            Text("← → next · esc close")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
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
            CachedAsyncImage(url: model.mediaURL, stableKey: model.mediaStableKey) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .empty, .failure:
                    Rectangle()
                        .fill(DS.glassSectionFill)
                        .overlay {
                            Image(systemName: model.platformGlyph ?? "photo")
                                .font(DS.title2)
                                .foregroundStyle(DS.textMuted)
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .background(Color.black.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityLabel("Swipe media preview")
        }
    }

    @ViewBuilder
    private var hookSection: some View {
        if model.aspect != .paper {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hook")
                    .font(DS.caption.weight(.bold))
                    .foregroundStyle(DS.textMuted)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Text(model.hookText)
                    .font(DS.body)
                    .foregroundStyle(DS.text)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
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
