// CosmoOS/Canvas/RadialMenuView.swift
// Radial creation menu - right-click anywhere to create blocks
// Dark glass aesthetic matching Thinkspace (Part 10 of Project System Architecture)

import SwiftUI

// MARK: - Radial Menu View

struct RadialMenuView: View {
    let position: CGPoint
    let onSelect: (RadialAction) -> Void
    let onDismiss: () -> Void
    let customActions: [RadialAction]?

    @State private var isAnimating = false
    @State private var hoveredIndex: Int?
    @State private var isCenterHovered = false  // Hover state for X button

    init(
        position: CGPoint,
        onSelect: @escaping (RadialAction) -> Void,
        onDismiss: @escaping () -> Void,
        customActions: [RadialAction]? = nil
    ) {
        self.position = position
        self.onSelect = onSelect
        self.onDismiss = onDismiss
        self.customActions = customActions
    }

    // Default 6 block types for canvas creation
    private static let defaultActions: [RadialAction] = [
        RadialAction(icon: "doc.text.fill", label: "Content", color: DS.entityContent, type: .createContent),
        RadialAction(icon: "note.text", label: "Note", color: DS.entityNote, type: .createNote),
        RadialAction(icon: "square.and.pencil", label: "Sticky", color: DS.entityStickyNote, type: .createStickyNote),
        RadialAction(icon: "point.3.connected.trianglepath.dotted", label: "Connection", color: DS.entityConnection, type: .createConnection),
        RadialAction(icon: "circle.hexagongrid.circle.fill", label: "Deep Dive", color: CosmoMentionColors.color(for: .deepDive), type: .createDeepDive),
        RadialAction(icon: "rectangle.3.group.fill", label: "Template", color: DS.accent, type: .createTemplate),
        RadialAction(icon: "arrow.up.forward.app", label: "Portal", color: DS.accent, type: .createPortal),
    ]

    private var actions: [RadialAction] {
        customActions ?? Self.defaultActions
    }

    /// Radius for the circular layout (increased for 6 items)
    private let radius: CGFloat = 95

    var body: some View {
        ZStack {
            // Expanding circle backdrop
            Circle()
                .fill(DS.border.opacity(isAnimating ? 0.06 : 0))
                .frame(width: isAnimating ? 230 : 60, height: isAnimating ? 230 : 60)
                .animation(.easeOut(duration: 0.35), value: isAnimating)
                .allowsHitTesting(false)

            // Center dismiss button - dark glass with hover state
            Button(action: { onDismiss() }) {
                ZStack {
                    Circle()
                        .fill(DS.vellum)
                        .frame(width: isCenterHovered ? 52 : 48, height: isCenterHovered ? 52 : 48)
                        .overlay(
                            Circle()
                                .stroke(
                                    isCenterHovered ? DS.sepiaBorder : DS.sepiaSubtle,
                                    lineWidth: isCenterHovered ? 1 : 0.5
                                )
                        )
                        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
                        .shadow(color: Color.black.opacity(0.05), radius: 32, x: 0, y: 16)

                    // X icon
                    Image(systemName: "xmark")
                        .font(.system(size: isCenterHovered ? 16 : 14, weight: .medium))
                        .foregroundColor(isCenterHovered ? DS.text : DS.textSecondary)
                }
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isCenterHovered)
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .onHover { hovering in
                // Direct state update - animation is handled by view modifier
                isCenterHovered = hovering
                if hovering {
                    hoveredIndex = nil
                }
            }
            .scaleEffect(isAnimating ? 1 : 0.8)
            .opacity(isAnimating ? 1 : 0)
            .zIndex(10)  // Keep X button on top for hit testing

            // Action items in circular pattern - positioned absolutely
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                RadialMenuButton(
                    action: action,
                    index: index,
                    isHovered: hoveredIndex == index,
                    isAnimating: isAnimating,
                    onTap: {
                        print("🎯 RadialMenu: Tapped \(action.label)")
                        withAnimation(.easeOut(duration: 0.15)) {
                            isAnimating = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            onSelect(action)
                        }
                    },
                    onHover: { isHovered in
                        guard !isCenterHovered else { return }
                        // Direct state update - animation is handled by view modifier
                        hoveredIndex = isHovered ? index : nil
                    }
                )
                // Position each button at its final location (not offset from center)
                .position(
                    x: 170 + itemOffset(for: index).width,
                    y: 170 + itemOffset(for: index).height
                )
            }
        }
        .frame(width: 340, height: 340)
        .position(position)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: hoveredIndex)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isAnimating)
        .onAppear {
            // Direct state update - animation handled by view modifier
            isAnimating = true
        }
    }

    // MARK: - Circular Layout

    /// 4 items positioned at top, right, bottom, left
    private func itemOffset(for index: Int) -> CGSize {
        let totalItems = CGFloat(actions.count)
        let fullCircle: CGFloat = 2 * .pi
        let startAngle: CGFloat = -.pi / 2  // Start from top

        let angleStep = fullCircle / totalItems
        let itemAngle = startAngle + CGFloat(index) * angleStep

        let x = cos(itemAngle) * radius
        let y = sin(itemAngle) * radius

        return CGSize(width: x, height: y)
    }
}

// MARK: - Radial Menu Button

/// A button for the radial menu with proper hit testing
/// Uses .position() for placement so hit testing area matches visual position
struct RadialMenuButton: View {
    let action: RadialAction
    let index: Int
    let isHovered: Bool
    let isAnimating: Bool
    let onTap: () -> Void
    let onHover: (Bool) -> Void

    @State private var itemAnimated = false
    @State private var didTap = false

    /// Staggered delay for stagger animation (30ms per item)
    private var animationDelay: Double {
        Double(index) * 0.03
    }

    var body: some View {
        Button(action: {
            didTap = true
            withAnimation(ProMotionSprings.press) { }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                onTap()
            }
        }) {
            VStack(spacing: 6) {
                // Icon pill with dark glass styling
                ZStack {
                    // Background - vellum surface
                    RoundedRectangle(cornerRadius: isHovered ? 14 : 12)
                        .fill(DS.vellum)
                        .frame(
                            width: isHovered ? 56 : 48,
                            height: isHovered ? 56 : 48
                        )

                    // Border with accent color on hover
                    RoundedRectangle(cornerRadius: isHovered ? 14 : 12)
                        .stroke(
                            isHovered ? action.color : DS.sepiaBorder,
                            lineWidth: isHovered ? 1.5 : 0.5
                        )
                        .frame(
                            width: isHovered ? 56 : 48,
                            height: isHovered ? 56 : 48
                        )

                    // Inner glow on hover
                    if isHovered {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(action.color.opacity(0.15))
                            .frame(width: 52, height: 52)
                    }

                    // Icon
                    Image(systemName: action.icon)
                        .font(.system(size: isHovered ? 18 : 16, weight: .medium))
                        .foregroundColor(isHovered ? action.color : DS.textSecondary)
                }
                .shadow(
                    color: isHovered ? action.color.opacity(0.3) : Color.black.opacity(0.05),
                    radius: isHovered ? 12 : 12
                )

                // Label - always visible but more prominent on hover
                Text(action.label)
                    .font(.system(size: 11, weight: isHovered ? .semibold : .medium))
                    .foregroundColor(isHovered ? DS.text : DS.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover(perform: onHover)
        .scaleEffect(didTap ? 0.85 : (itemAnimated ? (isHovered ? 1.1 : 1.0) : 0.5))
        .opacity(itemAnimated ? 1 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .onAppear {
            guard isAnimating else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + animationDelay) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    itemAnimated = true
                }
            }
        }
        .onChange(of: isAnimating) { _, newValue in
            if newValue && !itemAnimated {
                DispatchQueue.main.asyncAfter(deadline: .now() + animationDelay) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        itemAnimated = true
                    }
                }
            } else if !newValue {
                withAnimation(.easeOut(duration: 0.1)) {
                    itemAnimated = false
                }
            }
        }
    }
}

// MARK: - Radial Action Model

struct RadialAction: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let color: Color
    let type: RadialActionType
}

enum RadialActionType {
    case createNote
    case createIdea
    case createTask
    case createContent
    case createResearch
    case createConnection
    case createStickyNote   // Creates a sticky note block
    case createDeepDive     // Creates a Deep Dive portal block
    case researchAgent      // Opens Research Agent panel (Perplexity AI)
    case fromDatabase       // Opens database picker overlay
    case createTemplate     // Opens template gallery to spawn a template block
    case createPortal       // Opens the portal target picker (window into another thinkspace)
}

// MARK: - Preview

#if DEBUG
struct RadialMenuView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            // Dark background to simulate canvas
            Color(hex: "#0A0A0F")
                .ignoresSafeArea()

            RadialMenuView(
                position: CGPoint(x: 200, y: 200),
                onSelect: { action in
                    print("Selected: \(action.label)")
                },
                onDismiss: {
                    print("Dismissed")
                }
            )
        }
        .frame(width: 400, height: 400)
    }
}
#endif
