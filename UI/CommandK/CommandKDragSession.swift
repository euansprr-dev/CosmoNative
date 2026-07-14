// CosmoOS/UI/CommandK/CommandKDragSession.swift
// Session state for dragging results out of the Command-K palette onto the
// canvas. Pattern sibling of ClusterViewDragSession / CrossThinkspaceDragManager:
// observable state set at drag start, consumed by the canvas drop delegate.

import SwiftUI
import AppKit

/// Tracks a drag that started on a Command-K result card.
///
/// While a session is active the palette ghosts out of the way (CommandKView
/// observes `payload`) and the thinkspace canvas accepts the drop
/// (`CanvasDropDelegate` checks `isActive`).
///
/// AppKit gives SwiftUI `onDrag` sources no end-of-drag callback, and local
/// event monitors are starved inside an `NSDraggingSession`, so the session
/// polls `NSEvent.pressedMouseButtons`: once the primary button releases and
/// no drop handler consumed the payload within a beat, the drag ended in a
/// miss and the palette springs back.
@MainActor
@Observable
final class CommandKDragSession {

    /// What the dragged result card looks like — enough to rebuild a
    /// miniature of it under the cursor (same identity grammar as
    /// CortexRailRow's thumbnail slot: thumbnail > favicon > identity chip).
    struct CardFace {
        let title: String
        var subtitle: String = ""
        var accent: Color = DS.accent
        var symbolName: String? = nil
        var thumbnailURL: String? = nil
        var faviconHost: String? = nil
    }

    struct Payload {
        /// Atom UUIDs riding the drag. A single-uuid drag travels the
        /// pasteboard as a bare uuid string — compatible with every
        /// `String`-typed drop target in the app. Multi-select drags join
        /// with newlines; only the canvas drop path understands that form.
        let uuids: [String]
        let card: CardFace

        var title: String { card.title }
        var count: Int { uuids.count }
        var pasteboardString: String { uuids.joined(separator: "\n") }

        /// Splits a dropped pasteboard string back into uuids.
        static func uuids(fromDropped string: String) -> [String] {
            string.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        }
    }

    static let shared = CommandKDragSession()

    private(set) var payload: Payload?
    var isActive: Bool { payload != nil }

    /// True while the drag cursor is outside the palette panel. The palette
    /// ghosts only then — hovering back over it restores full opacity AND
    /// hit-testing, so in-palette drop targets (thinkspace filing) still work.
    private(set) var isPointerOutsidePalette = false

    /// Palette panel frame in SwiftUI global (window content, top-left origin)
    /// space — kept fresh by CommandKView via onGeometryChange.
    @ObservationIgnored var paletteFrameInWindow: CGRect = .zero

    @ObservationIgnored private var mouseReleasePoll: Timer?
    @ObservationIgnored private var pollTickCount = 0

    private init() {}

    /// Starts a session and returns the item provider for `onDrag`.
    func begin(uuids: [String], card: CardFace) -> NSItemProvider {
        let payload = Payload(uuids: uuids, card: card)
        self.payload = payload
        isPointerOutsidePalette = false
        startMouseReleasePoll()
        NSLog("CMDKDRAG begin uuids=\(uuids) paletteFrame=\(paletteFrameInWindow)")
        return NSItemProvider(object: payload.pasteboardString as NSString)
    }

    /// Called by drop handlers that consumed the payload, and by the poll
    /// when the mouse releases without a drop. Idempotent.
    func end() {
        mouseReleasePoll?.invalidate()
        mouseReleasePoll = nil
        payload = nil
        isPointerOutsidePalette = false
    }

    private func startMouseReleasePoll() {
        mouseReleasePoll?.invalidate()
        let poll = Timer(timeInterval: 1.0 / 30.0, repeats: true) { _ in
            Task { @MainActor in
                CommandKDragSession.shared.pollTick()
            }
        }
        RunLoop.main.add(poll, forMode: .common)
        mouseReleasePoll = poll
    }

    private func pollTick() {
        guard isActive else {
            end()
            return
        }

        // Track whether the drag has left the palette (screen → window →
        // flipped, the CrossThinkspaceDragManager recipe).
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            let contentHeight = window.contentView?.bounds.height ?? window.frame.height
            let flipped = CGPoint(x: windowPoint.x, y: contentHeight - windowPoint.y)
            let outside = !paletteFrameInWindow.contains(flipped)
            pollTickCount += 1
            if pollTickCount % 5 == 0 || outside != isPointerOutsidePalette {
                NSLog("CMDKDRAG tick#\(pollTickCount) flipped=\(flipped) frame=\(paletteFrameInWindow) outside=\(outside) wasOutside=\(isPointerOutsidePalette) pressed=\(NSEvent.pressedMouseButtons & 0x1)")
            }
            if outside != isPointerOutsidePalette {
                isPointerOutsidePalette = outside
            }
        }

        if NSEvent.pressedMouseButtons & 0x1 == 0 {
            mouseReleasePoll?.invalidate()
            mouseReleasePoll = nil
            // Give a performDrop that fired on this release a beat to consume
            // the session before treating it as a miss.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                CommandKDragSession.shared.end()
            }
        }
    }
}

// MARK: - Window-Level Canvas Drop Catcher

/// A full-window drop target that sits **above every other layer** and claims a
/// ⌘K retrieve drag the instant it leaves the palette.
///
/// The retrieve verb used to rely on the palette ghosting itself out of the way
/// so the drop could "fall through" to the canvas underneath. That only worked
/// where the canvas was the topmost view under the cursor — over any chrome that
/// outranks the canvas (the trail island, a cluster surface, the top strip
/// above the panel) the drop hit that view instead and was silently dropped.
///
/// This catcher removes the guesswork: while a ⌘K drag is active **and** the
/// pointer is outside the palette panel, it is the topmost hit-testable view
/// everywhere, so it — and nothing else — receives the drop, then routes the
/// release point to the active canvas (`commandKAtomDropOnCanvas`). When the
/// pointer is back over the panel it goes hit-transparent so in-palette drop
/// targets (thinkspace filing, the Ideas board) keep working, and it is inert
/// whenever no ⌘K drag is in flight. Observation is scoped to this view so only
/// it re-evaluates on the 30 Hz pointer poll, never MainView's body.
struct CommandKCanvasDropCatcher: View {
    private var session: CommandKDragSession { .shared }

    /// Live only for the retrieve verb, and only beyond the panel's edge.
    private var isArmed: Bool {
        session.isActive && session.isPointerOutsidePalette
    }

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .allowsHitTesting(isArmed)
            .onDrop(of: [.text], delegate: CommandKCanvasDropCatcherDelegate())
            .ignoresSafeArea()
    }
}

private struct CommandKCanvasDropCatcherDelegate: DropDelegate {
    private var isArmed: Bool {
        CommandKDragSession.shared.isActive
            && CommandKDragSession.shared.isPointerOutsidePalette
    }

    func validateDrop(info: DropInfo) -> Bool {
        isArmed && info.hasItemsConforming(to: [.text])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        // Back over the palette mid-drag reads as "changed my mind": decline so
        // the release is a miss, not a silent drop-behind onto the canvas.
        guard isArmed else { return DropProposal(operation: .cancel) }
        return DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        NSLog("CMDKDRAG catcher.performDrop armed=\(isArmed) loc=\(info.location)")
        guard isArmed else { return false }
        let location = info.location
        for provider in info.itemProviders(for: [.text]) {
            _ = provider.loadObject(ofClass: NSString.self) { item, _ in
                guard let dropped = item as? String else { return }
                let uuids = CommandKDragSession.Payload.uuids(fromDropped: dropped)
                guard !uuids.isEmpty else { return }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: CosmoNotification.NodeGraph.commandKAtomDropOnCanvas,
                        object: nil,
                        userInfo: ["uuids": uuids, "x": location.x, "y": location.y]
                    )
                }
            }
        }
        return true
    }
}

// MARK: - Drag-Out Modifier

/// Makes a ⌘K result card a drag source for the retrieve verb. The payload
/// is resolved at drag time: when the card is part of an active multi-select,
/// the whole selection rides the drag.
struct CommandKDragOutModifier: ViewModifier {
    let uuid: String
    let title: String
    var subtitle: String = ""
    var accent: Color = DS.accent
    var symbolName: String? = nil
    var thumbnailURL: String? = nil
    var faviconHost: String? = nil
    /// Read at drag start so a selection made after view construction counts.
    var selectedUUIDs: () -> Set<String> = { [] }

    private var cardFace: CommandKDragSession.CardFace {
        CommandKDragSession.CardFace(
            title: title,
            subtitle: subtitle,
            accent: accent,
            symbolName: symbolName,
            thumbnailURL: thumbnailURL,
            faviconHost: faviconHost
        )
    }

    func body(content: Content) -> some View {
        content.onDrag {
            let selected = selectedUUIDs()
            let uuids = (selected.contains(uuid) && selected.count > 1)
                ? Array(selected)
                : [uuid]
            return CommandKDragSession.shared.begin(uuids: uuids, card: cardFace)
        } preview: {
            CommandKDragPreviewLive(fallbackCard: cardFace)
        }
    }
}

/// Reads the live session payload at render time — the preview is built when
/// the drag begins, after `begin(...)` has stamped the payload.
private struct CommandKDragPreviewLive: View {
    let fallbackCard: CommandKDragSession.CardFace

    var body: some View {
        let payload = CommandKDragSession.shared.payload
        CommandKDragCardPreview(
            card: payload?.card ?? fallbackCard,
            count: payload?.count ?? 1
        )
    }
}

// MARK: - Drag Preview

/// Miniature of the dragged result card, shown under the cursor — the same
/// identity grammar as the rail row (thumbnail / favicon / identity chip +
/// title + subtitle), just smaller, the way Finder previews the real item.
struct CommandKDragCardPreview: View {
    let card: CommandKDragSession.CardFace
    let count: Int

    var body: some View {
        HStack(spacing: DS.space10) {
            thumbnailSlot
            VStack(alignment: .leading, spacing: DS.space2) {
                Text(card.title)
                    .font(DS.footnote.weight(.semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                if !card.subtitle.isEmpty {
                    Text(card.subtitle)
                        .font(DS.caption2)
                        .foregroundStyle(DS.inkFaded)
                        .lineLimit(1)
                }
            }
            if count > 1 { countBadge }
        }
        .padding(DS.space8)
        .frame(maxWidth: 240, alignment: .leading)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .strokeBorder(DS.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Place \(card.title) on canvas")
    }

    /// Mirrors CortexRailRow's slot ladder at drag-preview scale: real media
    /// thumbnails and favicons are identity and win; kinds get the chip.
    @ViewBuilder
    private var thumbnailSlot: some View {
        if let url = card.thumbnailURL, !url.isEmpty {
            SpotlightImageContent(urlString: url)
                .frame(width: 30, height: 40)
                .clipShape(.rect(cornerRadius: DS.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
                        .strokeBorder(DS.commandChromeSeparator, lineWidth: 0.5)
                )
        } else if let host = card.faviconHost {
            CommandKFavicon(host: host) { identityChip }
                .frame(width: 30, height: 40)
        } else if card.symbolName != nil {
            identityChip
                .frame(width: 30, height: 40)
        } else {
            SpotlightFauxPage(accentColor: card.accent)
                .frame(width: 30, height: 40)
                .clipShape(.rect(cornerRadius: DS.radiusSmall))
        }
    }

    private var identityChip: some View {
        CosmoIdentityChip(systemName: card.symbolName ?? "doc", tint: card.accent, size: 22)
    }

    private var countBadge: some View {
        Text("\(count)")
            .font(DS.caption2.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(DS.textOnAccent)
            .padding(.horizontal, DS.space6)
            .padding(.vertical, DS.space2)
            .background(DS.accent, in: Capsule())
    }
}
