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
        var icon: CosmoIcon? = nil
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

    private init() {}

    /// Starts a session and returns the item provider for `onDrag`.
    func begin(uuids: [String], card: CardFace) -> NSItemProvider {
        let payload = Payload(uuids: uuids, card: card)
        self.payload = payload
        isPointerOutsidePalette = false
        startMouseReleasePoll()
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

        // Current pointer in window-content space (top-left origin): screen →
        // window → flipped, the CrossThinkspaceDragManager recipe.
        var flipped: CGPoint?
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            let contentHeight = window.contentView?.bounds.height ?? window.frame.height
            let point = CGPoint(x: windowPoint.x, y: contentHeight - windowPoint.y)
            flipped = point
            let outside = !paletteFrameInWindow.contains(point)
            if outside != isPointerOutsidePalette {
                isPointerOutsidePalette = outside
            }
        }

        guard NSEvent.pressedMouseButtons & 0x1 == 0 else { return }

        // Button released — the drag is over. Stop polling.
        mouseReleasePoll?.invalidate()
        mouseReleasePoll = nil

        // Released beyond the palette edge → a canvas drop. AppKit never
        // delivered these through a SwiftUI drop target reliably: a catcher
        // that isn't hit-testable at drag-start is never enrolled as a live
        // drop destination, so its performDrop never fired. Instead we route
        // the release point straight to the active canvas from this poll,
        // which we KNOW runs for the whole drag (it also drives the ghosting).
        if isPointerOutsidePalette, let drop = flipped, let payload {
            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.commandKAtomDropOnCanvas,
                object: nil,
                userInfo: ["uuids": payload.uuids, "x": drop.x, "y": drop.y]
            )
            end()
            return
        }

        // Released over the palette (or window lookup failed) → let an
        // in-palette drop target (thinkspace filing) consume it first, then
        // clear the session.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            CommandKDragSession.shared.end()
        }
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
    var icon: CosmoIcon? = nil
    var thumbnailURL: String? = nil
    var faviconHost: String? = nil
    /// Read at drag start so a selection made after view construction counts.
    var selectedUUIDs: () -> Set<String> = { [] }

    private var cardFace: CommandKDragSession.CardFace {
        CommandKDragSession.CardFace(
            title: title,
            subtitle: subtitle,
            accent: accent,
            icon: icon,
            thumbnailURL: thumbnailURL,
            faviconHost: faviconHost
        )
    }

    func body(content: Content) -> some View {
        content.onDrag {
            let selected = selectedUUIDs()
            let uuids = (selected.contains(uuid) && selected.count > 1)
                ? selected.sorted()
                : [uuid]
            return CommandKDragSession.shared.begin(uuids: uuids, card: cardFace)
        } preview: {
            CommandKDragPreviewLive(fallbackCard: cardFace)
        }
    }
}

/// A result is a destination only when it is a Space or a composition. The
/// existing drag session supplies originals; the Space writer decides whether
/// they become membership, Group items, or authored references.
struct CommandKSpaceDropModifier: ViewModifier {
    let targetUUID: String?
    let exactSpaceID: String?
    var viewModel: CommandKViewModel
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .strokeBorder(DS.accent.opacity(isTargeted ? 0.6 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let targetUUID, CommandKDragSession.shared.isActive,
                      let payload = CommandKDragSession.shared.payload, !payload.uuids.isEmpty else { return false }
                let ids = payload.uuids
                CommandKDragSession.shared.end()
                viewModel.addDroppedOriginals(ids, to: targetUUID, exactSpaceID: exactSpaceID)
                return true
            } isTargeted: { targeted in
                withAnimation(ProMotionSprings.snappy) { isTargeted = targeted && targetUUID != nil }
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
        } else if card.icon != nil {
            identityChip
                .frame(width: 30, height: 40)
        } else {
            SpotlightFauxPage(accentColor: card.accent)
                .frame(width: 30, height: 40)
                .clipShape(.rect(cornerRadius: DS.radiusSmall))
        }
    }

    private var identityChip: some View {
        CosmoIdentityChip(icon: card.icon ?? .system("doc"), tint: card.accent, size: 22)
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
