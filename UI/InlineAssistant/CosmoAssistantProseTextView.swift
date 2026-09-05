// CosmoOS/UI/InlineAssistant/CosmoAssistantProseTextView.swift
// Read-only TextKit renderer for pane answers: Markdown-rendered prose with
// inline document pills drawn by the same CosmoMentionPillCell the composer
// uses, so a citation looks exactly like a mention the user typed. One view
// serves streaming and finalized rows — the text changes, the view never swaps.
// June 2026 · Markdown + decorations September 2026

import SwiftUI
import AppKit

struct CosmoAssistantProseTextView: NSViewRepresentable {
    let rendered: CosmoAssistantRenderedAnswer

    /// Select→mint: hosts that install `conceptMintPillHost()` receive this
    /// view's text selections (nil on collapse). Inert everywhere else.
    @Environment(\.conceptMintReporter) private var mintReporter

    /// Reading measure for pane answers.
    static let readingMeasure: CGFloat = 620
    static let bodyFont = NSFont.systemFont(ofSize: CosmoAssistantMarkdownRenderer.bodySize)
    static let lineSpacing: CGFloat = CosmoAssistantMarkdownRenderer.lineSpacing

    func makeNSView(context: Context) -> NSTextView {
        // Explicit TextKit 1 stack: attachment cells (CosmoMentionPillCell) and
        // the decorating layout manager both require it.
        let storage = NSTextStorage()
        let layoutManager = CosmoProseLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: Self.readingMeasure, height: .greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)

        let textView = CosmoProsePillTextView(frame: .zero, textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.textContainerInset = .zero
        textView.delegate = context.coordinator
        textView.onPillHover = { [weak coordinator = context.coordinator, weak textView] uuid, rect in
            guard let coordinator, let textView else { return }
            coordinator.handlePillHover(uuid: uuid, pillRect: rect, in: textView)
        }

        // SwiftUI owns the height via sizeThatFits.
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        container.lineBreakMode = .byWordWrapping
        container.lineFragmentPadding = 0

        // Pills carry `.link` (a uuid string); URLs carry `.link` (a URL).
        // Keep the pointer affordance but none of the default blue underline —
        // the renderer already tints link runs with the accent.
        textView.linkTextAttributes = [.cursor: NSCursor.pointingHand]

        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.shouldUpdate(key: rendered.key) else { return }

        textView.textStorage?.beginEditing()
        textView.textStorage?.setAttributedString(rendered.attributed)
        textView.textStorage?.endEditing()

        context.coordinator.record(key: rendered.key)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        let measuredWidth = proposal.width ?? nsView.bounds.width
        let width = min(max(1, measuredWidth > 0 ? measuredWidth : 260), Self.readingMeasure)

        guard let layoutManager = nsView.layoutManager,
              let textContainer = nsView.textContainer else {
            return CGSize(width: width, height: 50)
        }

        // SwiftUI probes several widths per layout pass, and LazyVStack
        // placement multiplies the probes across every message. Measuring must
        // therefore be idempotent and O(1) on repeat: memoize per width, only
        // touch the container when the width really changed, and never force a
        // full invalidation — resizing the container (or editing the storage in
        // updateNSView) already invalidates the affected fragments. Doing more
        // than that re-dirties the live view mid-layout and can livelock the
        // whole window.
        if let cached = context.coordinator.cachedSize(forWidth: width) {
            return cached
        }

        if abs(textContainer.containerSize.width - width) > 0.25 {
            textContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: textContainer)

        let usedRect = layoutManager.usedRect(for: textContainer)
        let size = CGSize(width: width, height: ceil(usedRect.height) + 4)
        context.coordinator.cacheSize(size, forWidth: width)
        return size
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    static func dismantleNSView(_ nsView: NSTextView, coordinator: Coordinator) {
        coordinator.closePreview()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CosmoAssistantProseTextView
        private var lastKey: String?

        private var hoveredUUID: String?
        private var hoverTask: Task<Void, Never>?
        private var previewPopover: NSPopover?
        /// Atom snippets are tiny but the fetch hits GRDB — remember answers
        /// (including misses) for the view's lifetime.
        private var snippetCache: [String: String?] = [:]
        /// Measured heights per proposed width, valid until the content changes.
        private var sizeCache: [CGFloat: CGSize] = [:]

        init(parent: CosmoAssistantProseTextView) {
            self.parent = parent
        }

        func shouldUpdate(key: String) -> Bool {
            key != lastKey
        }

        /// Reports name-shaped highlights to the mint pill host (conversation
        /// selections carry no context snippet — organize-don't-author).
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let reporter = parent.mintReporter,
                  let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            let nsString = textView.string as NSString
            guard range.length > 0, range.location + range.length <= nsString.length else {
                Task { @MainActor in reporter(nil) }
                return
            }
            let selected = nsString.substring(with: range)
            let anchor = SelectionAnchorSpace.globalRect(
                fromScreen: textView.firstRect(forCharacterRange: range, actualRange: nil),
                for: textView
            )
            Task { @MainActor in
                guard let anchor else {
                    reporter(nil)
                    return
                }
                reporter(ConceptMintSelectionReport(text: selected, anchor: anchor))
            }
        }

        func record(key: String) {
            lastKey = key
            sizeCache.removeAll()
        }

        func cachedSize(forWidth width: CGFloat) -> CGSize? {
            sizeCache[width]
        }

        func cacheSize(_ size: CGSize, forWidth width: CGFloat) {
            sizeCache[width] = size
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL {
                NSWorkspace.shared.open(url)
                return true
            }
            if let raw = link as? String, let url = URL(string: raw), url.scheme?.hasPrefix("http") == true {
                NSWorkspace.shared.open(url)
                return true
            }
            guard let uuid = link as? String else { return false }
            closePreview()
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openBlockInFocusMode,
                object: nil,
                userInfo: ["atomUUID": uuid, "asPane": true]
            )
            return true
        }

        // MARK: Hover previews

        /// Debounced hover: linger ~0.35s on a pill before the preview card
        /// appears; leaving the pill closes it instantly.
        func handlePillHover(uuid: String?, pillRect: NSRect, in textView: NSTextView) {
            guard uuid != hoveredUUID else { return }
            hoveredUUID = uuid
            hoverTask?.cancel()
            closePreview()

            guard let uuid else { return }
            hoverTask = Task { [weak self, weak textView] in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard let self, let textView, !Task.isCancelled, self.hoveredUUID == uuid else { return }
                let snippet = await self.snippet(forUUID: uuid)
                guard !Task.isCancelled, self.hoveredUUID == uuid else { return }
                guard let ref = self.ref(forUUID: uuid, in: textView) else { return }
                self.showPreview(
                    ref: ref,
                    snippet: snippet,
                    relativeTo: pillRect,
                    of: textView
                )
            }
        }

        func closePreview() {
            previewPopover?.close()
            previewPopover = nil
        }

        /// The pill attachment carrying this uuid, read back from the live
        /// storage so the hover never depends on a stale segment list.
        private func ref(forUUID uuid: String, in textView: NSTextView) -> CosmoAssistantSourceRef? {
            guard let storage = textView.textStorage else { return nil }
            var found: CosmoAssistantSourceRef?
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
                guard let attachment = value as? CosmoMentionPillAttachment,
                      let link = storage.attribute(.link, at: range.location, effectiveRange: nil) as? String,
                      link == uuid else { return }
                found = attachment.sourceRef
                stop.pointee = true
            }
            return found
        }

        private func snippet(forUUID uuid: String) async -> String? {
            if let cached = snippetCache[uuid] { return cached }
            let atom = try? await AtomRepository.shared.fetch(uuid: uuid)
            let snippet = Self.snippet(fromBody: atom?.body)
            snippetCache[uuid] = snippet
            return snippet
        }

        static func snippet(fromBody body: String?, maxLength: Int = 220) -> String? {
            guard let body else { return nil }
            let collapsed = body
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !collapsed.isEmpty else { return nil }
            guard collapsed.count > maxLength else { return collapsed }
            return String(collapsed.prefix(maxLength - 1)) + "…"
        }

        private func showPreview(
            ref: CosmoAssistantSourceRef,
            snippet: String?,
            relativeTo rect: NSRect,
            of view: NSView
        ) {
            closePreview()
            let popover = NSPopover()
            popover.behavior = .applicationDefined
            popover.animates = true
            popover.contentViewController = NSHostingController(
                rootView: CosmoAssistantPillPreviewCard(ref: ref, snippet: snippet)
            )
            popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
            previewPopover = popover
        }
    }
}

// MARK: - Decorating layout manager

/// Paints the renderer's block decorations — rounded code/quote backgrounds,
/// the quote's accent bar, inline-code chips — behind the glyphs. Decoration is
/// a draw-time concern: it adds no layout, so the pane's per-frame cost is the
/// same as plain text.
final class CosmoProseLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let characterRange = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        guard characterRange.length > 0 else { return }

        let palette = CosmoAssistantMarkdownRenderer.Palette.current
        let containerWidth = container.containerSize.width

        // Block decorations: one rounded rect per contiguous run, spanning the
        // full measure so the background reads as a block, not a highlight.
        storage.enumerateAttribute(.cosmoProseBlock, in: characterRange, options: [.longestEffectiveRangeNotRequired]) { value, range, _ in
            guard let raw = value as? String, let kind = CosmoProseBlockDecoration(rawValue: raw) else { return }
            var fullRange = NSRange(location: range.location, length: range.length)
            // Extend to the whole decorated run even when only part is being drawn.
            var effective = NSRange()
            _ = storage.attribute(.cosmoProseBlock, at: range.location, longestEffectiveRange: &effective, in: NSRange(location: 0, length: storage.length))
            if effective.length > 0 { fullRange = effective }

            let glyphRange = self.glyphRange(forCharacterRange: fullRange, actualCharacterRange: nil)
            var union = NSRect.null
            self.enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, _, _ in
                union = union.union(rect)
            }
            guard !union.isNull else { return }

            let pad = CosmoAssistantMarkdownRenderer.blockVerticalPad - 2
            var block = NSRect(
                x: origin.x,
                y: union.minY + origin.y - pad,
                width: containerWidth,
                height: union.height + pad * 2
            )
            block = block.integral
            let path = NSBezierPath(roundedRect: block, xRadius: CosmoAssistantMarkdownRenderer.cornerRadius, yRadius: CosmoAssistantMarkdownRenderer.cornerRadius)
            palette.blockFill.setFill()
            path.fill()
            palette.blockBorder.setStroke()
            path.lineWidth = 1
            path.stroke()

            if kind == .quote {
                let bar = NSRect(
                    x: block.minX + CosmoAssistantMarkdownRenderer.blockInset - CosmoAssistantMarkdownRenderer.quoteBarWidth - 4,
                    y: block.minY + 6,
                    width: CosmoAssistantMarkdownRenderer.quoteBarWidth,
                    height: block.height - 12
                )
                palette.accent.withAlphaComponent(0.55).setFill()
                NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
            }
        }

        // Inline code chips: a small rounded rect behind each enclosing rect.
        storage.enumerateAttribute(.cosmoProseInlineCode, in: characterRange, options: []) { value, range, _ in
            guard (value as? Bool) == true else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            self.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
                let chip = NSRect(
                    x: rect.minX + origin.x - 2,
                    y: rect.minY + origin.y + 1,
                    width: rect.width + 4,
                    height: rect.height - 2
                )
                palette.inlineCodeFill.setFill()
                NSBezierPath(roundedRect: chip, xRadius: 4, yRadius: 4).fill()
            }
        }
    }
}

// MARK: - Hover-aware text view

/// NSTextView that reports which document pill the pointer is over, so the
/// coordinator can stage a preview card. Pills are the only attachment runs.
final class CosmoProsePillTextView: NSTextView {
    var onPillHover: (@MainActor (String?, NSRect) -> Void)?

    private var pillTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pillTrackingArea {
            removeTrackingArea(pillTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        pillTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        reportHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onPillHover?(nil, .zero)
    }

    private func reportHover(at point: NSPoint) {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else {
            onPillHover?(nil, .zero)
            return
        }

        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        let index = layoutManager.characterIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        guard index < storage.length,
              storage.attribute(.attachment, at: index, effectiveRange: nil) != nil,
              let uuid = storage.attribute(.link, at: index, effectiveRange: nil) as? String else {
            onPillHover?(nil, .zero)
            return
        }

        // characterIndex(for:) snaps to the nearest glyph — require the pointer
        // to actually sit inside the pill's bounds before claiming a hover.
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: index, length: 1),
            actualCharacterRange: nil
        )
        var pillRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        pillRect.origin.x += textContainerOrigin.x
        pillRect.origin.y += textContainerOrigin.y
        guard pillRect.insetBy(dx: -2, dy: -2).contains(point) else {
            onPillHover?(nil, .zero)
            return
        }

        onPillHover?(uuid, pillRect)
    }
}

// MARK: - Preview card

/// The hover card for a document pill: kind, title, and a body snippet — enough
/// to decide whether the citation is worth opening.
struct CosmoAssistantPillPreviewCard: View {
    let ref: CosmoAssistantSourceRef
    let snippet: String?

    private var tint: Color {
        CosmoMentionColors.color(for: CosmoMentionPillTint.entityType(forSourceKind: ref.kind))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            kindRow
            Text(ref.title.isEmpty ? "Untitled" : ref.title)
                .font(DS.headline)
                .foregroundStyle(DS.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let snippet, !snippet.isEmpty {
                Text(snippet)
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Click to open")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
        .padding(DS.space12)
        .frame(width: 280, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kindLabel): \(ref.title). \(snippet ?? "")")
    }

    private var kindRow: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: ref.icon)
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: 6))
                .accessibilityHidden(true)

            Text(kindLabel)
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(DS.textMuted)
                .textCase(.uppercase)
                .kerning(0.4)

            Spacer(minLength: 0)
        }
    }

    private var kindLabel: String {
        switch ref.kind {
        case "swipe_file": return "Swipe"
        case "clientProfile", "client_profile": return "Client"
        case "sticky_note": return "Sticky note"
        default: return ref.kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
