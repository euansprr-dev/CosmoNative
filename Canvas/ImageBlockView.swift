// CosmoOS/Canvas/ImageBlockView.swift
// Native image block for Thinkspace canvas — clean image with rounded corners, no chrome

import SwiftUI

struct ImageBlockView: View {
    let block: CanvasBlock

    @State private var loadedImage: NSImage?
    @State private var blockSize: CGSize
    @State private var isHovered = false
    @State private var reflectionColor = DS.entityImage
    @State private var reflectionSignalToken = "fallback"
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
        .cosmoGlassSceneSignal(
            id: "canvas-image-\(block.id)-\(reflectionSignalToken)",
            source: .canvasBlock,
            color: reflectionColor,
            intensity: 0.72,
            allowsDeepDiffusion: true
        )
        .overlay {
            SimpleResizeOverlay(
                size: $blockSize,
                blockId: block.id,
                minSize: CGSize(width: 100, height: 80),
                maxSize: CGSize(width: 1200, height: 1000)
            )
        }
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

    private func loadImage() {
        guard loadedImage == nil else { return }
        if let path = block.metadata["imagePath"] {
            loadedImage = ImageStore.load(path: path)
            if let loadedImage,
               let sample = loadedImage.cosmoSidebarReflectionSample {
                reflectionColor = sample.color
                reflectionSignalToken = sample.token
            }
        }
    }
}

private extension NSImage {
    var cosmoSidebarReflectionSample: (color: Color, token: String)? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let width = 14
        let height = 14
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        let drewImage = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }

            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard drewImage else { return nil }

        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var totalWeight = 0.0

        stride(from: 0, to: pixels.count, by: bytesPerPixel).forEach { index in
            let alpha = Double(pixels[index + 3]) / 255.0
            guard alpha > 0.08 else { return }

            let r = Double(pixels[index]) / 255.0
            let g = Double(pixels[index + 1]) / 255.0
            let b = Double(pixels[index + 2]) / 255.0
            let maxChannel = max(r, g, b)
            let minChannel = min(r, g, b)
            let saturation = maxChannel == 0 ? 0 : (maxChannel - minChannel) / maxChannel
            let weight = alpha * (0.55 + saturation * 0.75 + maxChannel * 0.22)

            red += r * weight
            green += g * weight
            blue += b * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else { return nil }

        let sampledRed = min(max(red / totalWeight, 0), 1)
        let sampledGreen = min(max(green / totalWeight, 0), 1)
        let sampledBlue = min(max(blue / totalWeight, 0), 1)
        let token = String(
            format: "%02X%02X%02X",
            Int((sampledRed * 255).rounded()),
            Int((sampledGreen * 255).rounded()),
            Int((sampledBlue * 255).rounded())
        )

        return (
            Color(red: sampledRed, green: sampledGreen, blue: sampledBlue),
            token
        )
    }
}
