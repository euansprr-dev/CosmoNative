// CosmoOS/Components/ContinuityCameraButton.swift
// Native Continuity Camera intake: an NSView that conforms to
// NSServicesMenuRequestor so AppKit appends "Take Photo" / "Scan Documents"
// (from a nearby iPhone/iPad) to the menu it pops. Captured images arrive on
// the pasteboard via readSelection(from:) — the WWDC18 Continuity Camera
// contract. SwiftUI hosts it as a hidden anchor; the visible affordance is
// whatever menu/button the caller renders.

import AppKit
import SwiftUI

/// Hosts the requestor view and exposes a `present()` trigger that pops the
/// device menu at the anchor. When the system finds no nearby device, the
/// menu still shows the fallback items the caller provides.
struct ContinuityCameraAnchor: NSViewRepresentable {
    /// Incremented by the caller to pop the menu.
    var presentTick: Int
    /// JPEG/TIFF data for every image the device sends back.
    let onImages: ([Data]) -> Void
    /// Rendered at the top of the popped menu (e.g. "Upload images…").
    var fallbackItems: [(title: String, action: () -> Void)] = []

    func makeNSView(context: Context) -> ContinuityCameraReceiverView {
        let view = ContinuityCameraReceiverView()
        view.onImages = onImages
        return view
    }

    func updateNSView(_ view: ContinuityCameraReceiverView, context: Context) {
        view.onImages = onImages
        view.fallbackItems = fallbackItems
        if presentTick != context.coordinator.lastTick {
            context.coordinator.lastTick = presentTick
            if presentTick > 0 {
                view.presentDeviceMenu()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastTick = 0
    }
}

final class ContinuityCameraReceiverView: NSView, NSServicesMenuRequestor {
    var onImages: (([Data]) -> Void)?
    var fallbackItems: [(title: String, action: () -> Void)] = []

    override var acceptsFirstResponder: Bool { true }

    /// Advertise that this responder accepts images — the hook AppKit uses
    /// to add Continuity Camera items to menus popped from this view.
    override func validRequestor(
        forSendType sendType: NSPasteboard.PasteboardType?,
        returnType: NSPasteboard.PasteboardType?
    ) -> Any? {
        if let returnType, NSImage.imageTypes.contains(returnType.rawValue) {
            return self
        }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    func readSelection(from pboard: NSPasteboard) -> Bool {
        var images: [Data] = []
        for item in pboard.pasteboardItems ?? [] {
            for type in item.types where NSImage.imageTypes.contains(type.rawValue) {
                if let data = item.data(forType: type) {
                    images.append(data)
                    break
                }
            }
        }
        guard !images.isEmpty else { return false }
        onImages?(images)
        return true
    }

    func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        false
    }

    /// Pop the menu: fallback items first, then whatever device items AppKit
    /// appends for the first responder (this view).
    func presentDeviceMenu() {
        window?.makeFirstResponder(self)
        let menu = NSMenu()
        menu.allowsContextMenuPlugIns = true
        for fallback in fallbackItems {
            let item = NSMenuItem(title: fallback.title, action: #selector(runFallback(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = FallbackBox(action: fallback.action)
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: syntheticEvent(), for: self)
    }

    @objc private func runFallback(_ sender: NSMenuItem) {
        (sender.representedObject as? FallbackBox)?.action()
    }

    private final class FallbackBox {
        let action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
    }

    private func syntheticEvent() -> NSEvent {
        let location = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
        return NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) ?? NSEvent()
    }
}
