import AppKit
import SwiftUI

@main
struct ExportIcon {
    @MainActor
    static func main() throws {
        let source = CommandLine.arguments[1]
        let destination = CommandLine.arguments[2]
        guard let image = NSImage(contentsOfFile: source) else {
            fatalError("Cannot read approved Evergreen artwork")
        }
        let icon = Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: 832, height: 832)
            .clipShape(RoundedRectangle(cornerRadius: 188, style: .continuous))
            .padding(96)
            .frame(width: 1024, height: 1024)
        let renderer = ImageRenderer(content: icon)
        renderer.proposedSize = ProposedViewSize(width: 1024, height: 1024)
        renderer.scale = 1
        renderer.isOpaque = false
        guard let cgImage = renderer.cgImage else { fatalError("Icon render failed") }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("PNG encoding failed")
        }
        try png.write(to: URL(fileURLWithPath: destination))
    }
}
