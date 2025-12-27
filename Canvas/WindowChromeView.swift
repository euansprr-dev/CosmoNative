// CosmoOS/Canvas/WindowChromeView.swift
// macOS-style window chrome with traffic light buttons
// Makes blocks feel like real windowed apps
// December 2025 - ProMotion springs, symbol effects, 3-layer shadows, haptics

import SwiftUI

struct WindowChromeView<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    let onClose: () -> Void
    var onMinimize: (() -> Void)? = nil
    var onMaximize: (() -> Void)? = nil
    /// Optional size binding for resizable windows
    var size: Binding<CGSize>? = nil
    /// Called when size changes during resize
    var onSizeChange: ((CGSize) -> Void)? = nil
    @ViewBuilder let content: () -> Content

    @State private var isHoveringTrafficLights = false
    @State private var isResizing = false
    @State private var isHovered = false
    @State private var titleIconBounce = false

    /// Minimum window dimensions
    private let minWidth: CGFloat = 200
    private let minHeight: CGFloat = 150

    var body: some View {
        VStack(spacing: 0) {
            // Title bar with traffic lights
            HStack(spacing: 0) {
                // Traffic lights container
                HStack(spacing: 8) {
                    TrafficLightButton(
                        color: Color(hex: "FF5F57"),
                        hoverIcon: "xmark",
                        isHovering: isHoveringTrafficLights,
                        action: onClose
                    )

                    TrafficLightButton(
                        color: Color(hex: "FFBD2E"),
                        hoverIcon: "minus",
                        isHovering: isHoveringTrafficLights,
                        action: onMinimize
                    )

                    TrafficLightButton(
                        color: Color(hex: "28C840"),
                        hoverIcon: "arrow.up.left.and.arrow.down.right",
                        isHovering: isHoveringTrafficLights,
                        action: onMaximize
                    )
                }
                .padding(.leading, 12)
                .onHover { hovering in
                    withAnimation(ProMotionSprings.hover) {
                        isHoveringTrafficLights = hovering
                    }
                }

                Spacer()

                // Centered title with symbol effect
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(iconColor)
                        .symbolEffect(.bounce, value: titleIconBounce)

                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(CosmoColors.textPrimary)
                }
                .onAppear {
                    // Subtle bounce on appear
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        titleIconBounce.toggle()
                    }
                }

                Spacer()

                // Spacer to balance traffic lights
                Color.clear
                    .frame(width: 68)
            }
            .frame(height: 36)
            .background(
                ZStack {
                    Color.clear.background(.ultraThinMaterial)
                    Color.white.opacity(0.4)
                    // Subtle accent gradient on hover
                    LinearGradient(
                        colors: [iconColor.opacity(isHovered ? 0.05 : 0), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            )

            // Divider with accent tint
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [iconColor.opacity(0.3), CosmoColors.glassGrey.opacity(0.5)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            // Content area
            content()
        }
        .frame(
            width: size?.wrappedValue.width,
            height: size?.wrappedValue.height
        )
        .background(
            ZStack {
                // Glass material base for transparent look
                Color.clear.background(.ultraThinMaterial)
                // Subtle white brightener
                Color.white.opacity(0.35)
            }
        )
        .environment(\.colorScheme, .light) // Force light mode for proper glass rendering
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    LinearGradient(
                        colors: [
                            iconColor.opacity(isHovered ? 0.3 : 0.1),
                            CosmoColors.glassGrey.opacity(0.5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isHovered ? 1.5 : 1
                )
        )
        .overlay(alignment: .bottomTrailing) {
            // Resize handle (only if size binding provided)
            if size != nil {
                WindowResizeHandle(
                    size: size!,
                    isResizing: $isResizing,
                    minWidth: minWidth,
                    minHeight: minHeight,
                    onSizeChange: onSizeChange
                )
            }
        }
        // Simplified shadow for performance (single shadow instead of 3-layer)
        .shadow(
            color: .black.opacity(isHovered ? 0.12 : 0.08),
            radius: isHovered ? 12 : 8,
            y: isHovered ? 5 : 3
        )
        .compositingGroup() // Groups blur effects for better GPU handling
        // NOTE: Removed .drawingGroup() - it was breaking async image loading in
        // wrapped content (entity thumbnails, etc.)
        .scaleEffect(isHovered ? 1.005 : 1.0)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Resize Handle
/// Interactive corner handle for resizing windows/blocks
/// Premium version with haptic feedback and smooth animations
struct WindowResizeHandle: View {
    @Binding var size: CGSize
    @Binding var isResizing: Bool

    let minWidth: CGFloat
    let minHeight: CGFloat
    var onSizeChange: ((CGSize) -> Void)?

    @State private var dragStart: CGSize = .zero
    @State private var isHovered = false
    @State private var lastThresholdWidth: CGFloat = 0
    @State private var lastThresholdHeight: CGFloat = 0

    // Threshold interval for haptic feedback (every 50pt)
    private let thresholdInterval: CGFloat = 50

    var body: some View {
        ZStack {
            // Invisible hit target (larger for easier grabbing)
            Color.clear
                .frame(width: 24, height: 24)

            // Visible handle with premium styling
            Image(systemName: "arrow.up.backward.and.arrow.down.forward")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(isHovered || isResizing ? CosmoColors.textSecondary : CosmoColors.textTertiary)
                .rotationEffect(.degrees(90))  // Correct orientation for bottom-right
                .frame(width: 14, height: 14)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(CosmoColors.glassGrey.opacity(isHovered || isResizing ? 0.6 : 0.35))
                        .shadow(
                            color: .black.opacity(isResizing ? 0.15 : 0),
                            radius: isResizing ? 4 : 0,
                            y: isResizing ? 2 : 0
                        )
                )
                .scaleEffect(isResizing ? 1.15 : (isHovered ? 1.08 : 1.0))
                .rotationEffect(.degrees(isResizing ? 5 : 0))
        }
        .offset(x: -6, y: -6)
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if !isResizing {
                        dragStart = size
                        lastThresholdWidth = size.width
                        lastThresholdHeight = size.height
                        isResizing = true
                        CosmicHaptics.shared.play(.cardPickUp)
                    }

                    let newWidth = max(minWidth, dragStart.width + value.translation.width)
                    let newHeight = max(minHeight, dragStart.height + value.translation.height)
                    let newSize = CGSize(width: newWidth, height: newHeight)

                    // Haptic feedback at size thresholds
                    let widthThreshold = floor(newWidth / thresholdInterval)
                    let heightThreshold = floor(newHeight / thresholdInterval)
                    let lastWidthThreshold = floor(lastThresholdWidth / thresholdInterval)
                    let lastHeightThreshold = floor(lastThresholdHeight / thresholdInterval)

                    if widthThreshold != lastWidthThreshold || heightThreshold != lastHeightThreshold {
                        CosmicHaptics.shared.play(.threshold)
                        lastThresholdWidth = newWidth
                        lastThresholdHeight = newHeight
                    }

                    size = newSize
                    onSizeChange?(newSize)
                }
                .onEnded { _ in
                    isResizing = false
                    CosmicHaptics.shared.play(.cardDrop)
                }
        )
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }

            if hovering {
                CosmicHaptics.shared.play(.threshold)
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        .animation(ProMotionSprings.snappy, value: isResizing)
        .animation(ProMotionSprings.hover, value: isHovered)
    }
}

// MARK: - Traffic Light Button
/// Premium traffic light button with symbol effects and haptic feedback
struct TrafficLightButton: View {
    let color: Color
    let hoverIcon: String
    let isHovering: Bool
    let action: (() -> Void)?

    @State private var isPressed = false
    @State private var isButtonHovered = false
    @State private var symbolBounce = false

    // Determine haptic pattern based on icon type
    private var hapticPattern: CosmicHaptics.Pattern {
        switch hoverIcon {
        case "xmark": return .delete
        case "minus": return .selection
        default: return .cardPickUp
        }
    }

    var body: some View {
        Button(action: {
            CosmicHaptics.shared.play(hapticPattern)
            symbolBounce.toggle()
            action?()
        }) {
            ZStack {
                // PERFORMANCE FIX: Removed blur (very expensive) - use simple opacity instead
                // Outer glow ring on hover (no blur)
                if isButtonHovered {
                    Circle()
                        .fill(color.opacity(0.25))
                        .frame(width: 16, height: 16)
                }

                // PERFORMANCE FIX: Replaced RadialGradient with simple fill
                // Main circle - simple solid color with opacity variation
                Circle()
                    .fill(action != nil ? color : color.opacity(0.5))
                    .frame(width: 12, height: 12)
                    .overlay(
                        // Simple highlight (no gradient)
                        Circle()
                            .fill(Color.white.opacity(isButtonHovered ? 0.3 : 0.2))
                            .frame(width: 6, height: 6)
                            .offset(x: -2, y: -2)
                    )
                    .shadow(color: color.opacity(isButtonHovered ? 0.4 : 0.2), radius: isButtonHovered ? 3 : 1, y: 0)

                // Icon with symbol effect
                if isHovering && action != nil {
                    Image(systemName: hoverIcon)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(Color.black.opacity(0.6))
                        .symbolEffect(.bounce.down, value: symbolBounce)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .scaleEffect(isPressed ? 0.85 : (isButtonHovered ? 1.08 : 1.0))
        .animation(ProMotionSprings.snappy, value: isPressed)
        .animation(ProMotionSprings.hover, value: isButtonHovered)
        .animation(ProMotionSprings.hover, value: isHovering)
        .onHover { hovering in
            guard action != nil else { return }
            isButtonHovered = hovering
            if hovering {
                CosmicHaptics.shared.play(.threshold)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}

// MARK: - Preview
#if DEBUG
struct WindowChromeView_Previews: PreviewProvider {
    @State static var previewSize = CGSize(width: 300, height: 200)

    static var previews: some View {
        VStack(spacing: 40) {
            // Non-resizable version
            WindowChromeView(
                title: "Static Window",
                icon: "lightbulb.fill",
                iconColor: CosmoColors.lavender,
                onClose: {},
                onMinimize: {},
                onMaximize: {}
            ) {
                VStack {
                    Text("Non-resizable content")
                        .padding()
                }
                .frame(width: 280, height: 150)
            }

            // Resizable version (with size binding)
            WindowChromeView(
                title: "Resizable Window",
                icon: "doc.text.fill",
                iconColor: CosmoColors.skyBlue,
                onClose: {},
                onMinimize: {},
                onMaximize: {},
                size: $previewSize
            ) {
                VStack {
                    Text("Drag corner to resize")
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(40)
        .background(CosmoColors.mistGrey)
    }
}
#endif
