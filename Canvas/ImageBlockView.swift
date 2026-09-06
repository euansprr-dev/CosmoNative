// CosmoOS/Canvas/ImageBlockView.swift
// Native image block for Thinkspace canvas — clean image with rounded corners, no chrome

import SwiftUI

struct ImageBlockView: View {
    let block: CanvasBlock

    @State private var loadedImage: NSImage?
    @State private var blockSize: CGSize
    @State private var isHovered = false
    @Environment(\.canvasBlockSelectionSuppressed) private var selectionNotificationsSuppressed

    private var isSelected: Bool { block.isSelected }

    init(block: CanvasBlock) {
        self.block = block
        self._blockSize = State(initialValue: block.size)
    }

    var body: some View {
        Group {
            if let nsImage = loadedImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: blockSize.width, height: blockSize.height)
                    .clipped()
            } else {
                // Placeholder while loading
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .fill(DS.surfaceElevated)
                    .frame(width: blockSize.width, height: blockSize.height)
                    .overlay {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 32))
                            .foregroundColor(DS.textMuted)
                    }
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        BlockRenderedSizeCache.shared.update(blockId: block.id, size: geo.size)
                    }
                    .onChange(of: geo.size) { _, newSize in
                        BlockRenderedSizeCache.shared.update(blockId: block.id, size: newSize)
                    }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .strokeBorder(
                    isSelected ? DS.entityImage.opacity(0.5) : Color.black.opacity(0.06),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .shadow(
            color: .black.opacity(isSelected ? 0.06 : 0.04),
            radius: isHovered ? 14 : 8,
            x: 0,
            y: isHovered ? 4 : 2
        )
        .overlay {
            SimpleResizeOverlay(
                size: $blockSize,
                blockId: block.id,
                minSize: CGSize(width: 100, height: 80),
                maxSize: CGSize(width: 1200, height: 1000)
            )
        }
        .imageSaveAffordance(saveRequest, isHovered: isHovered)
        .imageSaveContextMenu(saveRequest)
        .contentShape(RoundedRectangle(cornerRadius: DS.radiusMedium))
        .onTapGesture {
            guard !selectionNotificationsSuppressed else { return }
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.blockSelected,
                object: nil,
                userInfo: ["blockId": block.id]
            )
        }
        .onChange(of: block.size) { _, newSize in
            guard blockSize != newSize else { return }
            blockSize = newSize
        }
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
        .task {
            loadImage()
        }
    }

    private var saveRequest: ImageSaveRequest? {
        guard let path = block.metadata["imagePath"], !path.isEmpty else { return nil }
        return ImageSaveRequest(.file(URL(fileURLWithPath: path)), title: block.metadata["title"])
    }

    private func loadImage() {
        guard loadedImage == nil else { return }
        if let path = block.metadata["imagePath"] {
            loadedImage = ImageStore.load(path: path)
        }
    }
}
