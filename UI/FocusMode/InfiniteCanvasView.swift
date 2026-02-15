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

    /// Tracks if spacebar is held for drag mode
    @State private var isSpacebarDragMode = false

    /// Canvas size from GeometryReader
    @State private var canvasSize: CGSize = .zero

    /// Show mini-map overlay
    @State private var showMiniMap = false

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

                // LAYER 3: Mini-map (optional, top-right)
                if showMiniMap {
                    miniMapOverlay
                        .frame(width: 150, height: 100)
                        .position(x: geometry.size.width - 90, y: 70)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .onAppear {
                canvasSize = geometry.size
            }
            .onChange(of: geometry.size) { _, newSize in
                canvasSize = newSize
            }
        }
        .background(CosmoColors.thinkspaceVoid)
        // Note: No .clipped() to allow transcript content to overflow visually
        .gesture(panGesture)
        .gesture(zoomGesture)
        .onKeyPress(.space) {
            isSpacebarDragMode = true
            return .handled
        }
        .onKeyPress(keys: [.init(" ")], phases: .up) { _ in
            isSpacebarDragMode = false
            return .handled
        }
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
            case "m":
                withAnimation(ProMotionSprings.snappy) {
                    showMiniMap.toggle()
                }
                return .handled
            default:
                return .ignored
            }
        }
    }

    // MARK: - Canvas Content Layer

    private var canvasContentLayer: some View {
        ZStack {
            // Floating content (moves with pan/zoom)
            floatingContent()
                .scaleEffect(effectiveZoom)
                .offset(x: effectiveOffset.x, y: effectiveOffset.y)

            // Anchored content (stays visually centered, but scales)
            anchoredContent()
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

    // MARK: - Mini-map Overlay

    private var miniMapOverlay: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 8)
                .fill(CosmoColors.thinkspaceTertiary.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(CosmoColors.thinkspaceGrid, lineWidth: 1)
                )

            // Viewport indicator
            Rectangle()
                .stroke(CosmoColors.thinkspacePurple.opacity(0.8), lineWidth: 2)
                .frame(
                    width: max(20, 150 / effectiveZoom),
                    height: max(15, 100 / effectiveZoom)
                )
                .offset(
                    x: -effectiveOffset.x / 20,
                    y: -effectiveOffset.y / 20
                )

            // Center dot
            Circle()
                .fill(CosmoColors.thinkspacePurple)
                .frame(width: 4, height: 4)
        }
        .shadow(color: Color.black.opacity(0.3), radius: 8)
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
        Canvas { context, size in
            let scaledSpacing = gridSpacing * zoom

            // Don't draw grid if too zoomed out (performance)
            guard scaledSpacing >= 15 else { return }

            // Calculate visible grid range
            let startX = -offset.x.truncatingRemainder(dividingBy: scaledSpacing)
            let startY = -offset.y.truncatingRemainder(dividingBy: scaledSpacing)

            // Draw dots
            var x = startX
            while x < size.width + scaledSpacing {
                var y = startY
                while y < size.height + scaledSpacing {
                    let point = CGPoint(x: x, y: y)
                    let dotSize = max(1.5, 2 * zoom)

                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: point.x - dotSize/2,
                            y: point.y - dotSize/2,
                            width: dotSize,
                            height: dotSize
                        )),
                        with: .color(CosmoColors.thinkspaceGrid.opacity(0.15))
                    )

                    y += scaledSpacing
                }
                x += scaledSpacing
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
                .foregroundColor(isHovered ? .white : CosmoColors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(CosmoColors.thinkspaceTertiary)
                        .overlay(
                            Capsule()
                                .stroke(
                                    isHovered ? CosmoColors.thinkspacePurple : CosmoColors.thinkspaceGrid,
                                    lineWidth: 1
                                )
                        )
                )
                .shadow(
                    color: isHovered ? CosmoColors.thinkspacePurple.opacity(0.3) : Color.black.opacity(0.2),
                    radius: isHovered ? 8 : 4
                )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(ProMotionSprings.hover) {
                    isHovered = hovering
                }
            }
            .scaleEffect(isHovered ? 1.05 : 1.0)
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
                        .fill(CosmoColors.thinkspaceTertiary)
                        .frame(width: 400, height: 300)
                        .overlay(
                            Text("Anchored Content")
                                .foregroundColor(.white)
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
                                .foregroundColor(.white)
                        )
                }
            )
        }
    }
}
#endif
