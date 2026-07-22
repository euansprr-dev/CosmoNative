// SwipeQuickLookPanelInvariantTests.swift
// The quick look panel's LAYOUT size must never animate: the card→panel
// flight is transforms only (scale + position). Springing the frame itself
// re-laid-out the AppKit-backed glass layer ~60×/s through transient and
// overshooting sizes, and that layer latches a transient size until its next
// invalidation — which left previews clipped at rest (media cropped at the
// top, the footer's Open Study button spilling out of the panel). July 2026.

import XCTest
import SwiftUI
import AppKit
@testable import CosmoOS

/// Hosts the production SwipeQuickLook exactly as the pages do: the shell
/// owns its expand-on-mount spring via the bound `expanded` state. The
/// invariant under test is the SHELL's (layout size static through the
/// spring), so the probe content is a plain stage — the library content
/// moved into SwipePreviewSidebar (July 2026), outside this shell.
///
/// The ProgressView is load-bearing: NSHostingView only materializes an
/// AppKit subview hierarchy when the SwiftUI tree bridges a platform view
/// (NSProgressIndicator here — the old library content bridged one the same
/// way). All-native SwiftUI content leaves `hosting.subviews` empty and the
/// probe would sample nothing.
private struct QuickLookProbeHost: View {
    let item: SwipeGalleryItem
    let model: SwipeCardModel
    @State private var expanded = false

    var body: some View {
        SwipeQuickLook(
            expanded: $expanded,
            sourceFrame: CGRect(x: 600, y: 500, width: 208, height: 260),
            heroModel: model,
            panelAspect: model.aspect,
            onRequestClose: {}
        ) {
            ZStack {
                Rectangle().fill(.black)
                ProgressView().controlSize(.small)
            }
        }
    }
}

@MainActor
final class SwipeQuickLookPanelInvariantTests: XCTestCase {

    func testPanelLayoutSizeIsStaticDuringExpandSpring() throws {
        let windowSize = CGSize(width: 1512, height: 860)
        let item = SwipeGalleryItem(
            atomUUID: "probe-atom",
            title: "Probe swipe",
            hookText: "Probe hook text",
            platform: "instagram_carousel",
            thumbnailUrl: nil,
            author: "probecreator",
            createdAt: ISO8601.string(from: Date()),
            instagramId: nil
        )
        let model = SwipeCardModel(item: item)
        let target = SwipeQuickLookGeometry.panelFrame(in: windowSize, aspect: model.aspect)

        let hosting = NSHostingView(
            rootView: AnyView(
                QuickLookProbeHost(item: item, model: model)
                    .frame(width: windowSize.width, height: windowSize.height)
            )
        )
        hosting.frame = NSRect(origin: .zero, size: windowSize)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()

        // Sample the panel's AppKit layout frame all the way through the
        // expand spring (response 0.35 + physical tail).
        var sampled = 0
        let start = Date()
        while Date().timeIntervalSince(start) < 1.5 {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.016))
            hosting.layoutSubtreeIfNeeded()
            guard let panel = hosting.subviews.first else { continue }
            sampled += 1
            XCTAssertEqual(
                panel.frame.size.width, target.width, accuracy: 0.5,
                "panel layout WIDTH animated mid-flight — the glass layer can latch a transient size again"
            )
            XCTAssertEqual(
                panel.frame.size.height, target.height, accuracy: 0.5,
                "panel layout HEIGHT animated mid-flight — the glass layer can latch a transient size again"
            )
        }
        XCTAssertGreaterThan(sampled, 20, "spring never sampled — probe did not run")

        // And at rest the panel sits exactly on the geometry target.
        if let panel = hosting.subviews.first {
            XCTAssertEqual(panel.frame.origin.x, target.origin.x, accuracy: 0.5)
            XCTAssertEqual(panel.frame.origin.y, target.origin.y, accuracy: 0.5)
        }
    }
}
