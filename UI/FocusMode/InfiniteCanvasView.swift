// CosmoOS/UI/FocusMode/InfiniteCanvasView.swift
// Infinite canvas with pan/zoom for Focus Mode views
// Shared foundation for Research and Connection Focus Modes
// December 2025 - Apple Silicon optimized, 120Hz ProMotion

import SwiftUI
import Combine

// MARK: - Canvas State

/// Represents the current viewport state of an infinite canvas
struct CanvasViewportState: Codable, Equatable {
    var offset: CGPoint = .zero
    var zoomScale: CGFloat = 1.0

    /// Minimum zoom level (25%)
    static let minZoom: CGFloat = 0.25
    /// Maximum zoom level (200%)
    static let maxZoom: CGFloat = 2.0
    /// Default zoom level
    static let defaultZoom: CGFloat = 1.0
}

/// Coordinate in canvas space (not screen space)
struct CanvasCoordinate: Equatable {
    let x: CGFloat
    let y: CGFloat

    init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
    }

    init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

// MARK: - Infinite Canvas View

/// A shared infinite canvas component for Focus Mode views.
/// Provides pan, zoom, and coordinate system management.
///
/// Usage:
/// ```swift
/// InfiniteCanvasView(
///     viewportState: $viewportState,
///     showGrid: true,
///     anchoredContent: {
///         // Content that stays fixed at canvas center
///         ResearchCoreView(...)
///     },
///     floatingContent: {
///         // Content that floats on the canvas
///         ForEach(panels) { panel in
///             FloatingPanelView(...)
///         }
///     }
/// )
/// ```
struct InfiniteCanvasView<AnchoredContent: View, FloatingContent: View>: View {
    // MARK: - Properties

    /// Bindable viewport state for persistence
    @Binding var viewportState: CanvasViewportState

    /// Whether to show the dot grid background
    let showGrid: Bool

    /// Content anchored at the center (cannot be moved by user)
    @ViewBuilder let anchoredContent: () -> AnchoredContent

    /// Floating content that moves with the canvas
    @ViewBuilder let floatingContent: () -> FloatingContent

    // MARK: - Gesture State

    /// Active pan gesture offset
    @GestureState private var panOffset: CGSize = .zero

    /// Active zoom gesture scale
    @GestureState private var zoomGestureScale: CGFloat = 1.0

    /// Canvas size from GeometryReader
    @State private var canvasSize: CGSize = .zero

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Computed Properties

    /// Current effective offset (persistent + gesture)
    private var effectiveOffset: CGPoint {
        CGPoint(
            x: viewportState.offset.x + panOffset.width,
            y: viewportState.offset.y + panOffset.height
        )
    }

    /// Current effective zoom scale
    private var effectiveZoom: CGFloat {
        let combined = viewportState.zoomScale * zoomGestureScale
        return min(max(combined, CanvasViewportState.minZoom), CanvasViewportState.maxZoom)
    }

    /// Center point of the canvas in screen coordinates
    private var canvasCenter: CGPoint {
        CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
    }

    /// Animation for viewport changes
    private var viewportAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : ProMotionSprings.gentle
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // LAYER 1: Grid Background
                if showGrid {
                    CanvasGridView(
                        offset: effectiveOffset,
                        zoom: effectiveZoom
                    )
                    .ignoresSafeArea()
                }

                // LAYER 2: Canvas Content Container
                canvasContentLayer
                    .frame(width: geometry.size.width, height: geometry.size.height)

            }
            .onAppear {
                canvasSize = geometry.size
            }
            .onChange(of: geometry.size) { _, newSize in
                canvasSize = newSize
            }
        }
        .background(DS.bg)
        // Note: No .clipped() to allow transcript content to overflow visually
        .gesture(panGesture)
        .gesture(zoomGesture)
        // Keyboard shortcuts for zoom
        .onKeyPress { keyPress in
            switch keyPress.characters {
            case "+", "=":
                zoomIn()
                return .handled
            case "-":
                zoomOut()
                return .handled
            case "0":
                if keyPress.modifiers.contains(.command) {
                    resetZoom()
                    return .handled
                }
                return .ignored
            default:
                return .ignored
            }
        }
    }

    // MARK: - Canvas Content Layer

    private var canvasContentLayer: some View {
        ZStack {
            // Anchored content (stays visually centered, but scales)
            anchoredContent()
                .scaleEffect(effectiveZoom)
                .offset(x: effectiveOffset.x, y: effectiveOffset.y)

            // Floating content (on top of anchored, moves with pan/zoom)
            floatingContent()
                .scaleEffect(effectiveZoom)
                .offset(x: effectiveOffset.x, y: effectiveOffset.y)
        }
    }

    // MARK: - Gestures

    /// Pan gesture (two-finger drag or spacebar+drag)
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .updating($panOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                // No animation to prevent jitter when releasing pan
                viewportState.offset = CGPoint(
                    x: viewportState.offset.x + value.translation.width,
                    y: viewportState.offset.y + value.translation.height
                )
            }
    }

    /// Zoom gesture (pinch or Cmd+scroll)
    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($zoomGestureScale) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                // No animation to prevent jitter when releasing zoom
                let newScale = viewportState.zoomScale * value.magnification
                viewportState.zoomScale = min(max(newScale, CanvasViewportState.minZoom), CanvasViewportState.maxZoom)
            }
    }

    // MARK: - Zoom Controls

    private func zoomIn() {
        let newScale = min(viewportState.zoomScale * 1.25, CanvasViewportState.maxZoom)
        withAnimation(viewportAnimation) {
            viewportState.zoomScale = newScale
        }
    }

    private func zoomOut() {
        let newScale = max(viewportState.zoomScale * 0.8, CanvasViewportState.minZoom)
        withAnimation(viewportAnimation) {
            viewportState.zoomScale = newScale
        }
    }

    private func resetZoom() {
        withAnimation(viewportAnimation) {
            viewportState.zoomScale = CanvasViewportState.defaultZoom
        }
    }

    /// Recenter the canvas to origin
    func recenter() {
        withAnimation(viewportAnimation) {
            viewportState.offset = .zero
        }
    }

    // MARK: - Coordinate Conversion

    /// Convert screen point to canvas coordinate
    func screenToCanvas(_ screenPoint: CGPoint) -> CanvasCoordinate {
        let x = (screenPoint.x - canvasCenter.x - effectiveOffset.x) / effectiveZoom
        let y = (screenPoint.y - canvasCenter.y - effectiveOffset.y) / effectiveZoom
        return CanvasCoordinate(x: x, y: y)
    }

    /// Convert canvas coordinate to screen point
    func canvasToScreen(_ canvasCoord: CanvasCoordinate) -> CGPoint {
        let x = canvasCoord.x * effectiveZoom + effectiveOffset.x + canvasCenter.x
        let y = canvasCoord.y * effectiveZoom + effectiveOffset.y + canvasCenter.y
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Canvas Grid View

/// Subtle dot grid background that scales with zoom
struct CanvasGridView: View {
    let offset: CGPoint
    let zoom: CGFloat

    /// Grid spacing in points
    private let gridSpacing: CGFloat = 40

    var body: some View {
        let spacing = max(gridSpacing * zoom, 1)
        let dotSize = max(1.5, 2 * zoom)
        let tileMultiplier = CanvasGridPatternCache.shared.tileMultiplier(for: spacing)
        let tileSize = spacing * CGFloat(tileMultiplier)
        let tileImage = CanvasGridPatternCache.shared.image(
            spacing: spacing,
            dotSize: dotSize,
            tileMultiplier: tileMultiplier
        )

        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
            let resolved = context.resolve(Image(nsImage: tileImage))
            let startX = -offset.x.truncatingRemainder(dividingBy: tileSize)
            let startY = -offset.y.truncatingRemainder(dividingBy: tileSize)

            for x in stride(from: startX - tileSize, through: size.width + tileSize, by: tileSize) {
                for y in stride(from: startY - tileSize, through: size.height + tileSize, by: tileSize) {
                    context.draw(
                        resolved,
                        in: CGRect(x: x, y: y, width: tileSize, height: tileSize)
                    )
                }
            }
        }
    }
}

// MARK: - Recenter Button

/// Button to recenter the canvas when panned far from origin
private struct FocusModeRecenterButton: View {
    let distanceFromCenter: CGFloat
    let onRecenter: () -> Void

    @State private var isHovered = false

    /// Show button when panned more than 200pt from center
    private var shouldShow: Bool {
        distanceFromCenter > 200
    }

    var body: some View {
        if shouldShow {
            Button(action: onRecenter) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .medium))

                    Text("Recenter")
                        .font(CosmoTypography.labelSmall)
                }
                .foregroundColor(isHovered ? DS.accent : DS.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(DS.surfaceElevated)
                        .overlay(
                            Capsule()
                                .stroke(
                                    isHovered ? DS.accent : DS.border,
                                    lineWidth: 1
                                )
                        )
                )
                .shadow(
                    color: .black.opacity(isHovered ? 0.08 : 0.04),
                    radius: isHovered ? 8 : 4,
                    y: isHovered ? 3 : 1
                )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(ProMotionSprings.hover) {
                    isHovered = hovering
                }
            }
            .animation(ProMotionSprings.hover, value: isHovered)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }
}

// MARK: - Viewport Persistence

/// Manages saving and loading viewport state for atoms
@MainActor
class CanvasViewportPersistence: ObservableObject {
    private let userDefaults = UserDefaults.standard
    private let keyPrefix = "canvasViewport_"

    /// Save viewport state for a specific atom
    func save(_ state: CanvasViewportState, forAtomUUID uuid: String) {
        let key = keyPrefix + uuid
        if let encoded = try? JSONEncoder().encode(state) {
            userDefaults.set(encoded, forKey: key)
        }
    }

    /// Load viewport state for a specific atom
    func load(forAtomUUID uuid: String) -> CanvasViewportState {
        let key = keyPrefix + uuid
        guard let data = userDefaults.data(forKey: key),
              let state = try? JSONDecoder().decode(CanvasViewportState.self, from: data) else {
            return CanvasViewportState()
        }
        return state
    }

    /// Clear viewport state for a specific atom
    func clear(forAtomUUID uuid: String) {
        let key = keyPrefix + uuid
        userDefaults.removeObject(forKey: key)
    }
}

// MARK: - Preview

#if DEBUG
struct InfiniteCanvasView_Previews: PreviewProvider {
    static var previews: some View {
        InfiniteCanvasPreviewWrapper()
            .frame(width: 800, height: 600)
    }

    struct InfiniteCanvasPreviewWrapper: View {
        @State private var viewportState = CanvasViewportState()

        var body: some View {
            InfiniteCanvasView(
                viewportState: $viewportState,
                showGrid: true,
                anchoredContent: {
                    // Sample anchored content
                    RoundedRectangle(cornerRadius: 16)
                        .fill(DS.surfaceElevated)
                        .frame(width: 400, height: 300)
                        .overlay(
                            Text("Anchored Content")
                                .foregroundColor(DS.text)
                        )
                },
                floatingContent: {
                    // Sample floating panels
                    RoundedRectangle(cornerRadius: 12)
                        .fill(CosmoColors.blockConnection)
                        .frame(width: 200, height: 150)
                        .position(x: 150, y: 150)
                        .overlay(
                            Text("Floating Panel")
                                .foregroundColor(DS.text)
                        )
                }
            )
        }
    }
}
#endif
