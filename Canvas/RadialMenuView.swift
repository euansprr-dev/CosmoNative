// CosmoOS/Canvas/RadialMenuView.swift
// Radial creation menu - right-click anywhere to create blocks
// Dark glass aesthetic matching Thinkspace (Part 10 of Project System Architecture)

import SwiftUI

// MARK: - Radial Menu View

struct RadialMenuView: View {
    let position: CGPoint
    let onSelect: (RadialAction) -> Void
    let onDismiss: () -> Void

    @State private var isAnimating = false
    @State private var hoveredIndex: Int?
    @State private var isCenterHovered = false  // Hover state for X button

    // 6 block types for Focus Mode canvas creation
    private let actions: [RadialAction] = [
        RadialAction(
            icon: "note.text",
            label: "Note",
            color: Color(hex: "#F97316"),  // Orange
            type: .createNote
        ),
        RadialAction(
            icon: "doc.text.fill",
            label: "Content",
            color: Color(hex: "#3B82F6"),  // Blue
            type: .createContent
        ),
        RadialAction(
            icon: "magnifyingglass",
            label: "Research",
            color: Color(hex: "#10B981"),  // Green
            type: .createResearch
        ),
        RadialAction(
            icon: "link.circle.fill",
            label: "Connection",
            color: Color(hex: "#8B5CF6"),  // Purple
            type: .createConnection
        ),
        RadialAction(
            icon: "brain.head.profile",
            label: "Agent",
            color: Color(hex: "#06B6D4"),  // Cyan
            type: .researchAgent
        ),
        RadialAction(
            icon: "tray.full.fill",
            label: "Database",
            color: Color(hex: "#64748B"),  // Slate
            type: .fromDatabase
        ),
    ]

    /// Radius for the circular layout (increased for 6 items)
    private let radius: CGFloat = 95

    var body: some View {
        ZStack {
            // Center dismiss button - dark glass with hover state
            Button(action: { onDismiss() }) {
                ZStack {
                    Circle()
                        .fill(isCenterHovered ? Color(hex: "#2A2A35") : Color(hex: "#1A1A25"))
                        .frame(width: isCenterHovered ? 52 : 48, height: isCenterHovered ? 52 : 48)
                        .overlay(
                            Circle()
                                .stroke(
                                    isCenterHovered ? Color.white.opacity(0.2) : Color.white.opacity(0.1),
                                    lineWidth: isCenterHovered ? 1.5 : 1
                                )
                        )
                        .shadow(color: Color.black.opacity(0.4), radius: isCenterHovered ? 16 : 12)

                    // X icon
                    Image(systemName: "xmark")
                        .font(.system(size: isCenterHovered ? 16 : 14, weight: .medium))
                        .foregroundColor(isCenterHovered ? Color.white.opacity(0.9) : Color.white.opacity(0.6))
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

    /// Staggered delay for stagger animation (50ms per item)
    private var animationDelay: Double {
        Double(index) * 0.05
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                // Icon pill with dark glass styling
                ZStack {
                    // Background - dark glass
                    RoundedRectangle(cornerRadius: isHovered ? 14 : 12)
                        .fill(Color(hex: "#1A1A25"))
                        .frame(
                            width: isHovered ? 56 : 48,
                            height: isHovered ? 56 : 48
                        )

                    // Border with accent color on hover
                    RoundedRectangle(cornerRadius: isHovered ? 14 : 12)
                        .stroke(
                            isHovered ? action.color : Color.white.opacity(0.1),
                            lineWidth: isHovered ? 2 : 1
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
                        .foregroundColor(isHovered ? action.color : Color.white.opacity(0.7))
                }
                .shadow(
                    color: isHovered ? action.color.opacity(0.3) : Color.black.opacity(0.3),
                    radius: isHovered ? 12 : 8
                )

                // Label - always visible but more prominent on hover
                Text(action.label)
                    .font(.system(size: 11, weight: isHovered ? .semibold : .medium))
                    .foregroundColor(isHovered ? .white : Color.white.opacity(0.6))
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover(perform: onHover)
        .scaleEffect(itemAnimated ? (isHovered ? 1.1 : 1.0) : 0.5)
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
    case createContent
    case createResearch
    case createConnection
    case researchAgent      // Opens Research Agent panel (Perplexity AI)
    case fromDatabase       // Opens Cmd-K to select atom from database
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
