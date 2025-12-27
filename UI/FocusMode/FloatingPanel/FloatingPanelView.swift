// CosmoOS/UI/FocusMode/FloatingPanel/FloatingPanelView.swift
// Visual component for floating panels on Focus Mode canvas
// Three states: Collapsed, Standard, Expanded
// December 2025 - Premium design matching Sanctuary aesthetic

import SwiftUI

// MARK: - Floating Panel View

/// A floating panel that displays an atom on the Focus Mode canvas.
/// Supports three display states with smooth transitions.
struct FloatingPanelView: View {
    // MARK: - Properties

    /// Panel data (position, state, etc.)
    @Binding var panel: FloatingPanelData

    /// Content loaded from database
    let content: FloatingPanelContent

    /// Callback when panel is double-clicked (open Focus Mode)
    let onDoubleTap: () -> Void

    /// Callback when panel requests removal
    let onRemove: () -> Void

    /// Callback when panel requests atom deletion
    let onDelete: () -> Void

    /// Callback when position changes (for persistence)
    let onPositionChange: (CGPoint) -> Void

    // MARK: - State

    @State private var isHovered = false
    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero
    @State private var showDeleteConfirmation = false

    // MARK: - Computed

    private var config: FloatingPanelTypeConfig {
        FloatingPanelTypeConfig.config(for: panel.atomType)
    }

    private var effectiveWidth: CGFloat {
        panel.displayState.width
    }

    // MARK: - Body

    var body: some View {
        panelContent
            .frame(width: effectiveWidth)
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(selectionOverlay)
            .shadow(
                color: shadowColor,
                radius: isDragging ? 20 : (isHovered ? 16 : 10),
                y: isDragging ? 10 : (isHovered ? 6 : 4)
            )
            .scaleEffect(scaleEffect)
            .offset(dragOffset)
            .position(panel.position)
            .gesture(dragGesture)
            .onHover { hovering in
                withAnimation(ProMotionSprings.hover) {
                    isHovered = hovering
                }
            }
            .onTapGesture(count: 2) {
                onDoubleTap()
            }
            .onTapGesture(count: 1) {
                // Select panel
                panel.isSelected = true
            }
            .contextMenu { contextMenuContent }
            .animation(ProMotionSprings.snappy, value: panel.displayState)
            .animation(ProMotionSprings.snappy, value: panel.isSelected)
            .confirmationDialog(
                "Delete Atom?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    onDelete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete \"\(content.title)\". This cannot be undone.")
            }
    }

    // MARK: - Panel Content

    @ViewBuilder
    private var panelContent: some View {
        switch panel.displayState {
        case .collapsed:
            collapsedContent
        case .standard:
            standardContent
        case .expanded:
            expandedContent
        }
    }

    // MARK: - Collapsed State (200pt)

    private var collapsedContent: some View {
        HStack(spacing: 12) {
            // Thumbnail/Icon
            panelThumbnail(size: 40)

            // Title + type
            VStack(alignment: .leading, spacing: 2) {
                Text(config.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(config.accentColor)
                    .textCase(.uppercase)
                    .tracking(0.8)

                Text(content.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer()

            // More button
            moreButton
        }
        .padding(12)
    }

    // MARK: - Standard State (280pt)

    private var standardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                panelThumbnail(size: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text(config.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(config.accentColor)
                        .textCase(.uppercase)
                        .tracking(0.8)

                    Text(content.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(2)
                }

                Spacer()

                moreButton
            }

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)

            // Preview text
            if let preview = content.preview, !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.6))
                    .lineLimit(3)
            }

            // Footer
            HStack {
                // Annotation count
                if content.annotationCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text")
                            .font(.system(size: 10))
                        Text("\(content.annotationCount)")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(Color.white.opacity(0.5))
                }

                // Linked count
                if content.linkedCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 10))
                        Text("\(content.linkedCount) linked")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(Color.white.opacity(0.5))
                }

                Spacer()

                // Expand button
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        panel.displayState = .expanded
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Expand")
                            .font(.system(size: 10, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .medium))
                    }
                    .foregroundColor(config.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
    }

    // MARK: - Expanded State (380pt)

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 12) {
                panelThumbnail(size: 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text(config.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(config.accentColor)
                        .textCase(.uppercase)
                        .tracking(0.8)

                    Text(content.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    // Metadata
                    metadataRow
                }

                Spacer()

                moreButton
            }

            // Thumbnail preview for video/research
            if let thumbnailURL = content.thumbnailURL {
                thumbnailPreview(url: thumbnailURL)
            }

            // Preview text
            if let preview = content.preview, !preview.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SUMMARY")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.4))
                        .tracking(1)

                    Text(preview)
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.7))
                        .lineLimit(6)
                }
            }

            Divider()
                .background(Color.white.opacity(0.1))

            // Stats footer
            HStack {
                if content.annotationCount > 0 {
                    statBadge(icon: "note.text", value: "\(content.annotationCount) notes")
                }

                if content.linkedCount > 0 {
                    statBadge(icon: "link", value: "\(content.linkedCount) linked")
                }

                Spacer()
            }

            // Open hint
            HStack {
                Spacer()
                Text("Double-click to open Focus Mode")
                    .font(.system(size: 10))
                    .foregroundColor(Color.white.opacity(0.3))
                Spacer()
            }
        }
        .padding(16)
    }

    // MARK: - Sub-components

    @ViewBuilder
    private func panelThumbnail(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(config.accentColor.opacity(0.15))

            Image(systemName: config.icon)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundColor(config.accentColor)
        }
        .frame(width: size, height: size)
    }

    private var metadataRow: some View {
        HStack(spacing: 8) {
            if let author = content.metadata.author {
                Text(author)
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.5))
            }

            if let platform = content.metadata.platform {
                Text("·")
                    .foregroundColor(Color.white.opacity(0.3))
                Text(platform)
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.5))
            }

            if let duration = content.metadata.duration {
                Text("·")
                    .foregroundColor(Color.white.opacity(0.3))
                Text(duration)
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.5))
            }
        }
    }

    @ViewBuilder
    private func thumbnailPreview(url: String) -> some View {
        AsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fill)
                    .frame(height: 120)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        // Play button overlay
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.8))
                            .shadow(radius: 10)
                    )
            case .failure, .empty:
                Rectangle()
                    .fill(config.accentColor.opacity(0.1))
                    .frame(height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        Image(systemName: config.icon)
                            .font(.system(size: 30))
                            .foregroundColor(config.accentColor.opacity(0.5))
                    )
            @unknown default:
                EmptyView()
            }
        }
    }

    private func statBadge(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(value)
                .font(.system(size: 10))
        }
        .foregroundColor(Color.white.opacity(0.5))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.05), in: Capsule())
    }

    private var moreButton: some View {
        Menu {
            contextMenuContent
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.white.opacity(0.5))
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Background

    private var panelBackground: some View {
        ZStack {
            // Base color
            Color(hex: "#1A1A25")

            // Subtle gradient
            LinearGradient(
                colors: [
                    config.accentColor.opacity(0.03),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var selectionOverlay: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                panel.isSelected ? config.accentColor : Color.white.opacity(isHovered ? 0.2 : 0.1),
                lineWidth: panel.isSelected ? 2 : 1
            )
    }

    // MARK: - Styling

    private var shadowColor: Color {
        if isDragging {
            return config.accentColor.opacity(0.3)
        } else if isHovered {
            return config.accentColor.opacity(0.2)
        } else {
            return Color.black.opacity(0.3)
        }
    }

    private var scaleEffect: CGFloat {
        if isDragging {
            return 1.02
        } else if isHovered {
            return 1.01
        } else {
            return 1.0
        }
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDragging {
                    withAnimation(ProMotionSprings.press) {
                        isDragging = true
                    }
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                withAnimation(ProMotionSprings.release) {
                    isDragging = false
                    dragOffset = .zero

                    // Update position
                    let newPosition = CGPoint(
                        x: panel.position.x + value.translation.width,
                        y: panel.position.y + value.translation.height
                    )
                    panel.position = newPosition
                    onPositionChange(newPosition)
                }
            }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            onDoubleTap()
        } label: {
            Label("Open Focus Mode", systemImage: FloatingPanelContextAction.openFocusMode.icon)
        }

        Divider()

        Text("Display State")

        Button {
            withAnimation(ProMotionSprings.snappy) {
                panel.displayState = .collapsed
            }
        } label: {
            Label("Collapsed", systemImage: FloatingPanelContextAction.collapsed.icon)
        }

        Button {
            withAnimation(ProMotionSprings.snappy) {
                panel.displayState = .standard
            }
        } label: {
            Label("Standard", systemImage: FloatingPanelContextAction.standard.icon)
        }

        Button {
            withAnimation(ProMotionSprings.snappy) {
                panel.displayState = .expanded
            }
        } label: {
            Label("Expanded", systemImage: FloatingPanelContextAction.expanded.icon)
        }

        Divider()

        Button {
            onRemove()
        } label: {
            Label("Remove from Canvas", systemImage: FloatingPanelContextAction.removeFromCanvas.icon)
        }

        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Label("Delete Atom", systemImage: FloatingPanelContextAction.deleteAtom.icon)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct FloatingPanelView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            CosmoColors.thinkspaceVoid
                .ignoresSafeArea()

            FloatingPanelPreviewWrapper()
        }
        .frame(width: 800, height: 600)
    }

    struct FloatingPanelPreviewWrapper: View {
        @State private var panel = FloatingPanelData(
            atomUUID: "preview-uuid",
            atomType: .research,
            position: CGPoint(x: 400, y: 300),
            displayState: .standard
        )

        private let content = FloatingPanelContent(
            title: "Dan Koe - How to Reinvent Your Life in 6-12 Months",
            preview: "Identity is not fixed — it's a story you tell yourself. Real transformation comes from subtraction, not addition. Remove what doesn't serve your vision.",
            thumbnailURL: nil,
            metadata: FloatingPanelContent.PanelMetadata(
                author: "Dan Koe",
                duration: "42:18",
                platform: "YouTube",
                sourceType: "youtube"
            ),
            annotationCount: 5,
            linkedCount: 3,
            updatedAt: Date()
        )

        var body: some View {
            FloatingPanelView(
                panel: $panel,
                content: content,
                onDoubleTap: { print("Open focus mode") },
                onRemove: { print("Remove from canvas") },
                onDelete: { print("Delete atom") },
                onPositionChange: { print("Position: \($0)") }
            )
        }
    }
}
#endif
