// CosmoOS/UI/FocusMode/FocusFloatingBlockView.swift
// Renders a single persistent floating block on a focus mode canvas
// February 2026 - Stored in atom metadata, travels with the atom

import SwiftUI

// MARK: - Focus Floating Block View

/// Renders a persistent floating block on a focus mode canvas.
/// These blocks are stored in the atom's metadata so they travel with the atom.
struct FocusFloatingBlockView: View {
    let block: FocusFloatingBlock
    let content: FloatingPanelContent
    let onRemove: () -> Void
    let onOpenFocusMode: () -> Void
    let onPositionChange: (CGPoint) -> Void

    @State private var isHovered = false
    @State private var dragOffset: CGSize = .zero
    @State private var dragStartPosition: CGPoint?

    private var typeConfig: FloatingPanelTypeConfig {
        FloatingPanelTypeConfig.config(for: block.atomType ?? .idea)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            header

            if block.displayState != "collapsed" {
                Divider()
                    .background(Color.white.opacity(0.06))

                // Content preview
                contentPreview
            }
        }
        .frame(width: block.size.width)
        .background(blockBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: isHovered ? 1.5 : 1)
        )
        .shadow(
            color: isHovered ? typeConfig.accentColor.opacity(0.2) : Color.black.opacity(0.3),
            radius: isHovered ? 16 : 10,
            y: 4
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .position(
            x: block.positionX + dragOffset.width,
            y: block.positionY + dragOffset.height
        )
        .gesture(dragGesture)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
        .onTapGesture(count: 2) {
            onOpenFocusMode()
        }
        .contextMenu {
            Button {
                onOpenFocusMode()
            } label: {
                Label("Open Focus Mode", systemImage: "arrow.up.left.and.arrow.down.right")
            }

            Divider()

            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove from Canvas", systemImage: "xmark.circle")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            // Type icon
            Image(systemName: typeConfig.icon)
                .font(.system(size: 11))
                .foregroundColor(typeConfig.accentColor)

            // Type badge
            Text(typeConfig.label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .tracking(0.6)
                .foregroundColor(typeConfig.accentColor.opacity(0.8))

            Spacer()

            // Close button (shown on hover)
            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(4)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content Preview

    private var contentPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title
            Text(content.title == "Loading..." ? block.title : content.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)

            // Preview text
            if let preview = content.preview, !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(block.displayState == "expanded" ? 6 : 3)
            }

            // Metadata row
            if content.linkedCount > 0 || content.annotationCount > 0 {
                HStack(spacing: 8) {
                    if content.linkedCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "link")
                                .font(.system(size: 9))
                            Text("\(content.linkedCount)")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(.white.opacity(0.3))
                    }

                    if content.annotationCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "note.text")
                                .font(.system(size: 9))
                            Text("\(content.annotationCount)")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(.white.opacity(0.3))
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Styling

    private var blockBackground: some View {
        ZStack {
            Color(hex: "#1A1A25")
            LinearGradient(
                colors: [typeConfig.accentColor.opacity(0.03), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var borderColor: Color {
        if isHovered {
            return typeConfig.accentColor.opacity(0.4)
        }
        return Color.white.opacity(0.08)
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if dragStartPosition == nil {
                    dragStartPosition = block.position
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                let newPosition = CGPoint(
                    x: block.positionX + value.translation.width,
                    y: block.positionY + value.translation.height
                )
                dragOffset = .zero
                dragStartPosition = nil
                onPositionChange(newPosition)
            }
    }
}

// MARK: - Focus Floating Blocks Layer

/// Renders all persistent floating blocks for a focus mode.
/// Used in the floatingContent closure of InfiniteCanvasView.
/// Must fill the parent so that `.position()` on child blocks
/// uses the full coordinate space.
struct FocusFloatingBlocksLayer: View {
    @ObservedObject var manager: FocusFloatingBlocksManager

    var body: some View {
        ZStack {
            // Invisible spacer to fill parent — ensures .position() children
            // use the full parent coordinate system, not a zero-sized one.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            ForEach(manager.blocks) { block in
                FocusFloatingBlockView(
                    block: block,
                    content: manager.content(for: block.id),
                    onRemove: {
                        manager.removeBlock(id: block.id)
                    },
                    onOpenFocusMode: {
                        NotificationCenter.default.post(
                            name: CosmoNotification.Navigation.openBlockInFocusMode,
                            object: nil,
                            userInfo: ["atomUUID": block.linkedAtomUUID]
                        )
                    },
                    onPositionChange: { newPosition in
                        manager.updatePosition(block.id, position: newPosition)
                    }
                )
            }
        }
    }
}
