// CosmoOS/UI/InlineAssistant/CosmoAssistantProseTextView.swift
// Read-only TextKit renderer for finalized pane answers: prose with inline
// document pills drawn by the same CosmoMentionPillCell the composer uses, so
// a citation looks exactly like a mention the user typed.
// June 2026

import SwiftUI
import AppKit

struct CosmoAssistantProseTextView: NSViewRepresentable {
    let segments: [CosmoAssistantProseSegment]

    /// Reading measure shared with the streaming `Text` fallback so the
    /// finalize swap doesn't reflow.
    static let readingMeasure: CGFloat = 620
    static let bodyFont = NSFont.systemFont(ofSize: 15)
    static let lineSpacing: CGFloat = 3

    func makeNSView(context: Context) -> NSTextView {
        let textView = CosmoProsePillTextView()
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
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.lineFragmentPadding = 0

        // Pills carry `.link`; keep the pointer affordance but none of the
        // default blue-underline dressing (the capsule IS the affordance).
        textView.linkTextAttributes = [.cursor: NSCursor.pointingHand]

        // Touching layoutManager pins this view to TextKit 1 — attachment
        // cells (CosmoMentionPillCell) require it.
        _ = textView.layoutManager

        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.shouldUpdate(segments: segments) else { return }

        let attributed = Self.attributedString(from: segments)
        textView.textStorage?.beginEditing()
        textView.textStorage?.setAttributedString(attributed)
        textView.textStorage?.endEditing()

        context.coordinator.record(segments: segments)
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

    // MARK: - Attributed string

    static func attributedString(from segments: [CosmoAssistantProseSegment]) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor(DS.text),
            .font: bodyFont,
            .paragraphStyle: paragraphStyle
        ]

        let result = NSMutableAttributedString()
        for segment in segments {
            switch segment {
            case .text(let run):
                result.append(NSAttributedString(string: run, attributes: baseAttributes))
            case .pill(let ref):
                let attachment = CosmoMentionPillAttachment(sourceRef: ref)
                let pill = NSMutableAttributedString(attachment: attachment)
                pill.addAttributes([
                    .link: ref.uuid as NSString,
                    .paragraphStyle: paragraphStyle,
                    // Baseline math in the cell assumes the surrounding font.
                    .font: bodyFont
                ], range: NSRange(location: 0, length: pill.length))
                result.append(pill)
            }
        }
        return result
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CosmoAssistantProseTextView
        private var lastSegments: [CosmoAssistantProseSegment] = []

        private var hoveredUUID: String?
        private var hoverTask: Task<Void, Never>?
        private var previewPopover: NSPopover?
        /// Atom snippets are tiny but the fetch hits GRDB — remember answers
        /// (including misses) for the view's lifetime.
        private var snippetCache: [String: String?] = [:]
        /// Measured heights per proposed width, valid until the segments change.
        private var sizeCache: [CGFloat: CGSize] = [:]

        init(parent: CosmoAssistantProseTextView) {
            self.parent = parent
        }

        func shouldUpdate(segments: [CosmoAssistantProseSegment]) -> Bool {
            segments != lastSegments
        }

        func record(segments: [CosmoAssistantProseSegment]) {
            lastSegments = segments
            sizeCache.removeAll()
        }

        func cachedSize(forWidth width: CGFloat) -> CGSize? {
            sizeCache[width]
        }

        func cacheSize(_ size: CGSize, forWidth width: CGFloat) {
            sizeCache[width] = size
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
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
                guard let ref = self.ref(forUUID: uuid) else { return }
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

        private func ref(forUUID uuid: String) -> CosmoAssistantSourceRef? {
            for segment in parent.segments {
                if case .pill(let ref) = segment, ref.uuid == uuid {
                    return ref
                }
            }
            return nil
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

// MARK: - Hover-aware text view

/// NSTextView that reports which document pill the pointer is over, so the
/// coordinator can stage a preview card. Pills are the only link runs here.
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
