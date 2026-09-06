import AppKit
import SwiftUI

/// Note focus mode image block with Google-Docs-style proportional resizing: hover the image
/// to reveal four corner handles, then drag a corner to resize with a live size badge. Height
/// always follows the intrinsic aspect ratio, so the image can never be distorted. The chosen
/// width is committed once per gesture via `onCommitWidth` (`nil` ⇒ reset to the default size).
struct ResizableImageBlockView: View {
    let image: RichImageReference
    var darkMode: Bool
    /// Persist a new display width. `nil` resets to the default size. Called once per gesture.
    var onCommitWidth: (CGFloat?) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var nsImage: NSImage?
    @State private var availableWidth: CGFloat = 680
    @State private var isHovering = false
    @State private var dragStartWidth: CGFloat?
    @State private var liveWidth: CGFloat?

    private var intrinsic: CGSize { CGSize(width: image.width, height: image.height) }
    private var isDragging: Bool { dragStartWidth != nil }
    private var showChrome: Bool { isHovering || isDragging }

    private var displaySize: CGSize {
        ImageResizeMath.resolvedSize(
            displayWidth: liveWidth ?? image.displayWidth,
            intrinsic: intrinsic,
            maxWidth: availableWidth
        )
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(widthReader)
            .task(id: image.path + (image.remoteURL ?? "")) { nsImage = await ImageStore.resolve(image) }
    }

    @ViewBuilder
    private var content: some View {
        if let nsImage {
            imageView(nsImage)
        } else {
            missingPlaceholder
        }
    }

    private func imageView(_ nsImage: NSImage) -> some View {
        Image(nsImage: nsImage)
            .resizable()
            .interpolation(.high)
            .frame(width: displaySize.width, height: displaySize.height)
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
            .overlay { selectionFrame }
            .overlay { handles }
            .overlay(alignment: .top) { sizeBadge }
            // Save pill rides the same hover as the handles; inset 14 keeps it
            // clear of the bottom-trailing handle's hot zone.
            .imageSaveAffordance(saveRequest, isHovered: showChrome, inset: 14)
            .contentShape(.rect(cornerRadius: 10, style: .continuous))
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : ProMotionSprings.hover) { isHovering = hovering }
            }
            .contextMenu { presetMenu }
            .help("Drag a corner to resize")
            .accessibilityElement()
            .accessibilityLabel("Image")
            .accessibilityValue(ImageResizeMath.format(size: displaySize))
            .accessibilityAdjustableAction(adjustSize)
            .animation(reduceMotion || isDragging ? nil : ProMotionSprings.snappy, value: displaySize)
    }

    // MARK: - Chrome

    @ViewBuilder
    private var selectionFrame: some View {
        if showChrome {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(DS.accent, lineWidth: 1.5)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var handles: some View {
        if showChrome {
            ZStack {
                ForEach(Corner.allCases, id: \.self, content: cornerHandle)
            }
            .transition(.opacity)
        }
    }

    private func cornerHandle(_ corner: Corner) -> some View {
        handleDot
            .frame(width: 28, height: 28)
            .contentShape(.rect)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
            .offset(corner.offset(half: 14))
            .pointerStyle(.frameResize(position: corner.pointer))
            .gesture(resizeGesture(growsRight: corner.growsRight))
            .accessibilityHidden(true)
    }

    private var handleDot: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(DS.accent)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(.white, lineWidth: 1.5)
            }
            .frame(width: 11, height: 11)
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
    }

    @ViewBuilder
    private var sizeBadge: some View {
        if isDragging {
            Text(ImageResizeMath.format(size: displaySize))
                .font(DS.caption.monospacedDigit())
                .foregroundStyle(DS.text)
                .padding(.horizontal, DS.space10)
                .padding(.vertical, DS.space4)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, DS.space8)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .allowsHitTesting(false)
        }
    }

    private var saveRequest: ImageSaveRequest { ImageSaveRequest(.reference(image)) }

    @ViewBuilder
    private var presetMenu: some View {
        ImageSaveMenuItems(request: saveRequest)
        Divider()
        Button("Small") { commit(width: intrinsic.width * 0.25) }
        Button("Medium") { commit(width: intrinsic.width * 0.5) }
        Button("Original size") { commit(width: intrinsic.width) }
        Button("Fit width") { commit(width: availableWidth) }
        Divider()
        Button("Reset size") { commit(width: nil) }
    }

    private var missingPlaceholder: some View {
        Text("Image unavailable")
            .font(DS.body)
            .foregroundStyle(darkMode ? Color.white.opacity(0.62) : DS.documentTextSecondary)
            .padding(.vertical, DS.space8)
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { availableWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { _, newValue in availableWidth = newValue }
        }
    }

    // MARK: - Interaction

    private func resizeGesture(growsRight: Bool) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStartWidth == nil { dragStartWidth = displaySize.width }
                liveWidth = ImageResizeMath.cornerResizedWidth(
                    startWidth: dragStartWidth ?? displaySize.width,
                    deltaX: value.translation.width,
                    growsRight: growsRight,
                    maxWidth: availableWidth
                )
            }
            .onEnded { _ in
                commit(width: liveWidth)
                dragStartWidth = nil
                liveWidth = nil
            }
    }

    private func adjustSize(_ direction: AccessibilityAdjustmentDirection) {
        let step: CGFloat = 24
        commit(width: displaySize.width + (direction == .increment ? step : -step))
    }

    /// Clamp through `resolvedSize` so the stored width always matches what renders.
    private func commit(width: CGFloat?) {
        guard let width else { onCommitWidth(nil); return }
        let clamped = ImageResizeMath.resolvedSize(displayWidth: width, intrinsic: intrinsic, maxWidth: availableWidth).width
        onCommitWidth(clamped)
    }
}

private enum Corner: CaseIterable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    var alignment: Alignment {
        switch self {
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        }
    }

    var growsRight: Bool { self == .topTrailing || self == .bottomTrailing }

    var pointer: FrameResizePosition {
        switch self {
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        }
    }

    func offset(half: CGFloat) -> CGSize {
        let isLeading = self == .topLeading || self == .bottomLeading
        let isTop = self == .topLeading || self == .topTrailing
        return CGSize(width: isLeading ? -half : half, height: isTop ? -half : half)
    }
}
