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
                    .background(DS.border)

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
            color: isHovered ? typeConfig.accentColor.opacity(0.15) : Color.black.opacity(0.06),
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
            Text(typeConfig.label)
                .font(DS.smallCaps)
                .foregroundStyle(typeConfig.accentColor.opacity(0.8))

            Spacer()

            // Close button (shown on hover)
            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.textMuted)
                        .padding(4)
                        .background(DS.border, in: Circle())
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
                .foregroundColor(DS.text)
                .lineLimit(2)

            // Preview text
            if let preview = content.preview, !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 11))
                    .foregroundColor(DS.textSecondary)
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
                        .foregroundColor(DS.textMuted)
                    }

                    if content.annotationCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "note.text")
                                .font(.system(size: 9))
                            Text("\(content.annotationCount)")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(DS.textMuted)
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
            DS.surfaceCard
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
        return DS.border
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

// MARK: - Focus Canvas Block View (Full Thinkspace Block)

/// Renders a full thinkspace-style block on a focus mode canvas.
/// Replaces the compact tab appearance with the same rich block views
/// used on the main Thinkspace canvas.
struct FocusCanvasBlockView: View {
    let block: FocusFloatingBlock
    let canvasBlock: CanvasBlock
    let onRemove: () -> Void
    let onPositionChange: (CGPoint) -> Void
    let onSelect: () -> Void

    @State private var dragOffset: CGSize = .zero

    var body: some View {
        blockContent
            .position(
                x: block.positionX + dragOffset.width,
                y: block.positionY + dragOffset.height
            )
            .simultaneousGesture(TapGesture().onEnded { onSelect() })
            .gesture(dragGesture)
    }

    // MARK: - Block Content (Type-Specific Dispatch)

    @ViewBuilder
    private var blockContent: some View {
        switch canvasBlock.entityType {
        case .research:
            if hasMediaContent(canvasBlock) {
                MediaBlockView(block: canvasBlock)
            } else {
                ResearchBlockView(block: canvasBlock)
            }
        case .connection:
            ConnectionBlockView(block: canvasBlock)
        case .idea:
            IdeaBlockView(block: canvasBlock)
        case .content:
            ContentBlockView(block: canvasBlock)
        case .task:
            TaskBlockView(block: canvasBlock)
        case .note:
            NoteBlockView(block: canvasBlock)
        case .stickyNote:
            StickyNoteBlockView(block: canvasBlock)
        case .cosmoAI:
            CosmoAIBlockView(block: canvasBlock)
        default:
            FloatingBlockView(block: canvasBlock)
        }
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let newPosition = CGPoint(
                    x: block.positionX + value.translation.width,
                    y: block.positionY + value.translation.height
                )
                dragOffset = .zero
                onPositionChange(newPosition)
            }
    }

    // MARK: - Helpers

    private func hasMediaContent(_ block: CanvasBlock) -> Bool {
        let url = (block.metadata["url"] ?? "").lowercased()
        return url.contains("youtube") || url.contains("youtu.be") ||
               url.contains("instagram") || url.contains("tiktok") ||
               block.metadata["isSwipeFile"] == "true"
    }
}

// MARK: - Focus Floating Blocks Layer

/// Renders all persistent floating blocks for a focus mode.
/// Uses the same full block views as the Thinkspace canvas when loaded,
/// with a compact placeholder while atom data is being fetched.
struct FocusFloatingBlocksLayer: View {
    @ObservedObject var manager: FocusFloatingBlocksManager
    var onSelect: (String) -> Void = { _ in }

    var body: some View {
        ZStack {
            // Invisible spacer to fill parent — ensures .position() children
            // use the full parent coordinate system, not a zero-sized one.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            ForEach(manager.blocks) { block in
                if let canvasBlock = manager.canvasBlocks[block.id] {
                    // Full block loaded — render as thinkspace block
                    FocusCanvasBlockView(
                        block: block,
                        canvasBlock: canvasBlock,
                        onRemove: {
                            manager.removeBlock(id: block.id)
                        },
                        onPositionChange: { newPosition in
                            manager.updatePosition(block.id, position: newPosition)
                        },
                        onSelect: {
                            onSelect(block.id)
                        }
                    )
                } else {
                    // Loading placeholder — compact view while atom data loads
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
}
