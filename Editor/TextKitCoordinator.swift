// CosmoOS/Editor/TextKitCoordinator.swift
// Shared TextKit editor infrastructure for rich writing surfaces.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum EditorImmediateResizePolicy {
    static func shouldApplyImmediateResize(
        newHeight: CGFloat,
        textViewHeight: CGFloat,
        scrollViewHeight: CGFloat,
        intrinsicHeight: CGFloat?,
        widthChanged: Bool,
        plainText: String
    ) -> Bool {
        if widthChanged { return true }

        let currentIntrinsicHeight = intrinsicHeight ?? newHeight
        let wouldShrinkHeight = newHeight + 0.5 < scrollViewHeight
            || newHeight + 0.5 < textViewHeight
            || newHeight + 0.5 < currentIntrinsicHeight

        guard wouldShrinkHeight else { return true }

        // Empty split blocks can briefly inherit the previous editor's large
        // frame/intrinsic height. Let those rows shrink immediately so Return
        // creates line-sized blocks instead of page-sized gaps.
        return plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@MainActor
fileprivate protocol CosmoTextViewShortcutDelegate: AnyObject {
    func textViewDidRequestFormattingShortcut(_ shortcut: FormattingType)
    /// Block-manipulation key equivalents (⌘D, ⌥⌘↑/↓, ⌥⌘1–3, ⇧⌘L). Returns
    /// true when the host consumed the shortcut (block rows only).
    func textViewDidRequestBlockShortcut(_ shortcut: BlockKeyboardShortcut) -> Bool
    func textView(_ textView: NSTextView, shouldHandleImagePaste pasteboard: NSPasteboard) -> Bool
}

fileprivate extension NSView {
    func nearestAncestorScrollView(excluding excluded: NSScrollView? = nil) -> NSScrollView? {
        var currentSuperview: NSView? = superview
        while let view = currentSuperview {
            if let scrollView = view as? NSScrollView, scrollView !== excluded {
                return scrollView
            }
            currentSuperview = view.superview
        }
        return nil
    }
}

// MARK: - Implicit-animation suppression

/// CALayer action map used by every Cosmo editor view (text view, scroll view,
/// clip view) to disable Core Animation's default ~0.25s animations on geometry
/// changes. SwiftUI re-layout writes new frames directly to the hosting NSView's
/// layer; without this map, every Return / typing-driven height change would
/// animate, producing the visible "ghost line above" jitter the user sees.
let suppressedLayerActions: [String: any CAAction] = [
    "bounds": NSNull(),
    "position": NSNull(),
    "frame": NSNull(),
    "frameOrigin": NSNull(),
    "frameSize": NSNull(),
    "transform": NSNull(),
    "sublayers": NSNull(),
    "onOrderIn": NSNull(),
    "onOrderOut": NSNull(),
    "contents": NSNull()
]

// MARK: - Scroll-Transparent NSScrollView

/// When `forwardsScrollEvents` is true, scroll wheel events pass through to the
/// next responder (the parent SwiftUI ScrollView) instead of being consumed.
final class CosmoScrollView: NSScrollView {
    var forwardsScrollEvents: Bool = false
    var intrinsicHeight: CGFloat?
    /// Fired after the view lands in (or leaves) a superview — the
    /// coordinator observes the SwiftUI host's frame through this.
    var onDidMoveToSuperview: (() -> Void)?

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        onDidMoveToSuperview?()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: NSView.noIntrinsicMetric,
            height: intrinsicHeight ?? NSView.noIntrinsicMetric
        )
    }

    override func makeBackingLayer() -> CALayer {
        let layer = super.makeBackingLayer()
        layer.actions = suppressedLayerActions
        return layer
    }

    override func scrollWheel(with event: NSEvent) {
        if forwardsScrollEvents {
            if let ancestorScrollView = nearestAncestorScrollView(excluding: self) {
                ancestorScrollView.scrollWheel(with: event)
            } else {
                nextResponder?.scrollWheel(with: event)
            }
        } else {
            super.scrollWheel(with: event)
        }
    }
}

final class CosmoClipView: NSClipView {
    weak var owningScrollView: CosmoScrollView?

    override func makeBackingLayer() -> CALayer {
        let layer = super.makeBackingLayer()
        layer.actions = suppressedLayerActions
        return layer
    }

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        if owningScrollView?.forwardsScrollEvents == true {
            bounds.origin = .zero
        }
        return bounds
    }

    override func scroll(to newOrigin: NSPoint) {
        guard owningScrollView?.forwardsScrollEvents == true else {
            super.scroll(to: newOrigin)
            return
        }
        super.scroll(to: .zero)
    }

    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        guard owningScrollView?.forwardsScrollEvents == true else {
            super.setBoundsOrigin(newOrigin)
            return
        }
        super.setBoundsOrigin(.zero)
    }
}

// MARK: - Custom NSTextView

/// Carries a right-click resize choice from an NSMenuItem back to the coordinator.
private final class ImageResizePresetPayload: NSObject {
    let charIndex: Int
    let width: CGFloat?
    init(charIndex: Int, width: CGFloat?) {
        self.charIndex = charIndex
        self.width = width
    }
}

/// AppKit overlay that draws Google-Docs-style proportional resize handles over a selected
/// inline image attachment in the content editor, and live-resizes it by mutating the
/// attachment's `bounds` (height always follows the intrinsic aspect ratio, so the image can
/// never be distorted). It passes every click through to the text view except the four corner
/// hot-zones, so caret placement and text selection keep working. The final width is reported
/// once per gesture via `onCommit`.
final class ImageResizeOverlayView: NSView {
    weak var textView: CosmoTextView?
    var charIndex: Int = 0
    var intrinsic: CGSize = CGSize(width: 1, height: 1)
    var maxWidth: CGFloat = 680
    var onCommit: ((CGFloat) -> Void)?

    private enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }

    private let dotSize: CGFloat = 11
    private let hitInset: CGFloat = 14
    private var margin: CGFloat { hitInset + 2 }

    private var activeCorner: Corner?
    private var startWidth: CGFloat = 0
    private var startMouseX: CGFloat = 0
    private var isDragging = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Geometry

    /// The image occupies the overlay's bounds inset by `margin` (the handles straddle the edge).
    private var imageRect: CGRect { bounds.insetBy(dx: margin, dy: margin) }

    private func cornerPoint(_ corner: Corner) -> CGPoint {
        let r = imageRect
        switch corner {
        case .topLeft: return CGPoint(x: r.minX, y: r.minY)
        case .topRight: return CGPoint(x: r.maxX, y: r.minY)
        case .bottomLeft: return CGPoint(x: r.minX, y: r.maxY)
        case .bottomRight: return CGPoint(x: r.maxX, y: r.maxY)
        }
    }

    private func handleRect(_ corner: Corner) -> CGRect {
        let c = cornerPoint(corner)
        return CGRect(x: c.x - hitInset, y: c.y - hitInset, width: hitInset * 2, height: hitInset * 2)
    }

    private func growsRight(_ corner: Corner) -> Bool { corner == .topRight || corner == .bottomRight }

    // MARK: - Attachment access

    private var attachment: NSTextAttachment? {
        guard let storage = textView?.textStorage, charIndex < storage.length else { return nil }
        return storage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? NSTextAttachment
    }

    private func currentWidth() -> CGFloat {
        guard let attachment else { return imageRect.width }
        if attachment.bounds.width > 0 { return attachment.bounds.width }
        return attachment.image?.size.width ?? imageRect.width
    }

    /// Re-fit the overlay frame to the attachment's current glyph rect. Returns false when the
    /// attachment can no longer be located, so the caller can drop the overlay.
    @discardableResult
    func repositionToAttachment() -> Bool {
        guard let textView, let lm = textView.layoutManager, let tc = textView.textContainer,
              let storage = textView.textStorage, charIndex < storage.length,
              storage.attribute(.attachment, at: charIndex, effectiveRange: nil) is NSTextAttachment else {
            return false
        }
        let glyphRange = lm.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1), actualCharacterRange: nil)
        var rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
        let origin = textView.textContainerOrigin
        rect.origin.x += origin.x
        rect.origin.y += origin.y
        frame = rect.insetBy(dx: -margin, dy: -margin)
        needsDisplay = true
        return true
    }

    // MARK: - Hit-testing & cursors

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let local = convert(point, from: superview)
        for corner in Corner.allCases where handleRect(corner).contains(local) { return self }
        return nil
    }

    override func resetCursorRects() {
        for corner in Corner.allCases {
            addCursorRect(handleRect(corner), cursor: cursor(for: corner))
        }
    }

    private func cursor(for corner: Corner) -> NSCursor {
        switch corner {
        case .topLeft: return .frameResize(position: .topLeft, directions: .all)
        case .topRight: return .frameResize(position: .topRight, directions: .all)
        case .bottomLeft: return .frameResize(position: .bottomLeft, directions: .all)
        case .bottomRight: return .frameResize(position: .bottomRight, directions: .all)
        }
    }

    // MARK: - Drag

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard let corner = Corner.allCases.first(where: { handleRect($0).contains(local) }) else {
            super.mouseDown(with: event)
            return
        }
        activeCorner = corner
        startWidth = currentWidth()
        startMouseX = event.locationInWindow.x   // window space: stable as the overlay reflows
        isDragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let corner = activeCorner, let attachment else { return }
        let deltaX = event.locationInWindow.x - startMouseX
        let width = ImageResizeMath.cornerResizedWidth(startWidth: startWidth, deltaX: deltaX, growsRight: growsRight(corner), maxWidth: maxWidth)
        let aspect = ImageResizeMath.aspectRatio(intrinsic: intrinsic)
        attachment.bounds = CGRect(x: 0, y: 0, width: width, height: (width / aspect).rounded())
        invalidateAttachmentLayout()
        repositionToAttachment()
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { super.mouseUp(with: event); return }
        isDragging = false
        activeCorner = nil
        needsDisplay = true
        onCommit?(currentWidth())
    }

    private func invalidateAttachmentLayout() {
        guard let textView, let lm = textView.layoutManager, let tc = textView.textContainer else { return }
        let range = NSRange(location: charIndex, length: 1)
        lm.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        lm.invalidateDisplay(forCharacterRange: range)
        lm.ensureLayout(for: tc)
        textView.needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor(DS.accent)
        let r = imageRect

        let framePath = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10)
        framePath.lineWidth = 1.5
        accent.setStroke()
        framePath.stroke()

        for corner in Corner.allCases {
            let c = cornerPoint(corner)
            let dot = NSBezierPath(
                roundedRect: CGRect(x: c.x - dotSize / 2, y: c.y - dotSize / 2, width: dotSize, height: dotSize),
                xRadius: 3, yRadius: 3
            )
            accent.setFill()
            dot.fill()
            NSColor.white.setStroke()
            dot.lineWidth = 1.5
            dot.stroke()
        }

        if isDragging { drawBadge(over: r) }
    }

    private func drawBadge(over rect: CGRect) {
        let aspect = ImageResizeMath.aspectRatio(intrinsic: intrinsic)
        let size = CGSize(width: currentWidth(), height: currentWidth() / aspect)
        let text = ImageResizeMath.format(size: size) as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attrs)
        let padX: CGFloat = 8, padY: CGFloat = 4
        let badge = CGRect(
            x: rect.midX - (textSize.width + padX * 2) / 2,
            y: rect.minY + 6,
            width: textSize.width + padX * 2,
            height: textSize.height + padY * 2
        )
        NSColor.black.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: badge, xRadius: badge.height / 2, yRadius: badge.height / 2).fill()
        text.draw(at: CGPoint(x: badge.minX + padX, y: badge.minY + padY), withAttributes: attrs)
    }
}

final class CosmoTextView: NSTextView {
    fileprivate weak var shortcutDelegate: CosmoTextViewShortcutDelegate?
    /// A later native click supersedes queued structural focus work.
    private(set) static var pointerInteractionGeneration: UInt64 = 0
    var onNativeMouseDown: (() -> Void)?

    override func makeBackingLayer() -> CALayer {
        let layer = super.makeBackingLayer()
        layer.actions = suppressedLayerActions
        return layer
    }

    /// When true, scroll events are handled by the enclosing NSScrollView
    /// instead of being forwarded up the responder chain (canvas zoom).
    var scrollsInternally: Bool = false

    /// Second ⌘A escalates from "all text in this block" to "all blocks" when
    /// the editor participates in a block list (Notion-style selection).
    var onSelectAllEscalation: (() -> Bool)?

    override func selectAll(_ sender: Any?) {
        let length = (string as NSString).length
        let coversAllText = length == 0 || selectedRange() == NSRange(location: 0, length: length)
        if coversAllText, onSelectAllEscalation?() == true {
            return
        }
        super.selectAll(sender)
    }

    /// Called when the user clicks while the editor is read-only (isEditable == false).
    /// Used by canvas blocks to enter edit mode from a single click.
    var onTapWhileReadOnly: (() -> Void)?
    var onBecomeFirstResponder: (() -> Void)?
    var onResignFirstResponder: (() -> Void)?
    var onToggleElementCollapse: ((UUID) -> Void)?
    var onToggleHeadingCollapse: ((NSRange) -> Void)?
    /// Click on a ☐/☑ glyph toggles the to-do — passes the line's start offset.
    var onToggleChecklistItem: ((Int) -> Void)?
    /// Right-click resize preset on an image: passes the attachment's char index and the new
    /// display width (`nil` ⇒ reset to default size).
    var onImageResizePreset: ((Int, CGFloat?) -> Void)?
    var rendersElementChrome: Bool = true
    var elementBlockDarkMode: Bool = false
    var elementBlockBaseFontSize: CGFloat = 16
    var headingDisclosureColor: NSColor?
    /// Block-row mode: this view holds exactly ONE block — hard newlines must
    /// never enter its storage. Multi-line pastes route through onBlockPaste.
    var blockRowMode: Bool = false
    /// Table cell mode (see TextKitEditorRepresentable.tableCellMode).
    var tableCellMode: Bool = false
    /// Table cell mode: the coordinator routes tabular pastes to the table.
    var onTableCellPaste: ((ClipboardImport) -> Bool)?
    /// Table cell mode: the table's own actions ride the text view's
    /// context menu (right-click on the live cell).
    var tableContextMenu: (() -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard tableCellMode, let tableMenu = tableContextMenu?() else {
            return standardMenu(for: event)
        }
        if let base = standardMenu(for: event) {
            tableMenu.addItem(.separator())
            for item in base.items {
                base.removeItem(item)
                tableMenu.addItem(item)
            }
        }
        return tableMenu
    }
    /// Multi-line paste in block-row mode — returns true when the host
    /// spliced the text into blocks structurally.
    var onBlockPaste: ((String) -> Bool)?
    /// Structured block paste (com.cosmo.blocks flavor) in block-row mode.
    var onStructuredBlockPaste: ((Data) -> Bool)?
    /// Cross-block drag selection bridge (block-row mode). When set, single
    /// clicks run a custom tracking loop so drags can escalate to whole-block
    /// selection at block boundaries — NSTextView's own loop clamps at the
    /// view's bounds.
    weak var blockDragSelectionController: BlockDragSelectionController?
    /// The block this row's text view renders — lets drag selection resolve
    /// blocks by AppKit hit-testing (exact) instead of coordinate-space
    /// conversion between AppKit and SwiftUI (offset-prone).
    var rowBlockID: UUID?
    /// The row's block kind (block-row mode) — gates per-event hit-tests:
    /// a paragraph row must not pay checklist-glyph layout queries on every
    /// click and mouse-move.
    var rowBlockKind: RichBlockKind?
    /// Whether this row's heading can collapse — gates the heading hit-test
    /// (a full line walk + forced layout) out of clicks/mouse-moves on the
    /// overwhelming majority of rows.
    var rowHeadingIsCollapsible: Bool = false
    private var disclosureTrackingArea: NSTrackingArea?

    override func draw(_ dirtyRect: NSRect) {
        if rendersElementChrome {
            drawElementBlockDecorations(in: dirtyRect)
        }
        super.draw(dirtyRect)
        drawHeadingDecorations(in: dirtyRect)
        drawChecklistCheckboxes(in: dirtyRect)
    }

    /// Paints iOS-style circle checkboxes (circle / checkmark.circle.fill)
    /// over the stored ☐/☑ characters. The characters stay in storage —
    /// serialization, block mapping, and click hit-testing all key off them —
    /// but render clear; this draws the visible checkbox in their rect.
    private func drawChecklistCheckboxes(in dirtyRect: NSRect) {
        // Block rows know their kind — the active row redraws on every
        // keystroke, and non-checklist rows have no boxes to paint.
        if blockRowMode, rowBlockKind != .checklist { return }
        guard let layoutManager, let textContainer else { return }
        let nsText = string as NSString
        guard nsText.length > 0 else { return }

        let containerRect = dirtyRect.offsetBy(
            dx: -textContainerInset.width,
            dy: -textContainerInset.height
        )
        let visibleGlyphs = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)

        var location = charRange.location
        let end = NSMaxRange(charRange)
        while location < end {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let next = max(NSMaxRange(lineRange), location + 1)
            defer { location = next }
            guard lineRange.length >= 1 else { continue }

            let glyph = nsText.substring(with: NSRange(location: lineRange.location, length: 1))
            let checked: Bool
            switch glyph {
            case "☐": checked = false
            case "☑": checked = true
            default: continue
            }

            let glyphGlyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: lineRange.location, length: 1),
                actualCharacterRange: nil
            )
            var rect = layoutManager.boundingRect(forGlyphRange: glyphGlyphRange, in: textContainer)
            rect.origin.x += textContainerInset.width
            rect.origin.y += textContainerInset.height

            let font = textStorage?.attribute(.font, at: lineRange.location, effectiveRange: nil) as? NSFont
                ?? NSFont.systemFont(ofSize: 16)
            let color = checklistSymbolColor(checked: checked, lineRange: lineRange)
            // Memoized: symbol lookup + tint compositing allocated two
            // NSImages per glyph per draw — and the active row redraws
            // every keystroke.
            guard let symbol = CosmoTextView.checklistSymbol(
                checked: checked,
                pointSize: font.pointSize,
                tint: color
            ) else { continue }

            let size = symbol.size
            let drawRect = NSRect(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
            symbol.draw(
                in: drawRect.integral,
                from: .zero,
                operation: .sourceOver,
                fraction: color.alphaComponent,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high.rawValue]
            )
        }
    }

    private struct ChecklistSymbolKey: Hashable {
        let checked: Bool
        let pointSize: CGFloat
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
    }

    @MainActor private static var checklistSymbolCache: [ChecklistSymbolKey: NSImage] = [:]

    /// The tinted checkbox image for a glyph — memoized by (state, size,
    /// tint). Monochrome tint, not paletteColors: palette rendering paints
    /// the checkmark as its own colored layer, while iOS's foregroundStyle
    /// keeps it a cutout so the paper shows through. Alpha is applied at
    /// draw time (`fraction:`), so the cache keys on the opaque tint only.
    @MainActor
    fileprivate static func checklistSymbol(checked: Bool, pointSize: CGFloat, tint: NSColor) -> NSImage? {
        let srgb = tint.usingColorSpace(.sRGB) ?? tint
        let key = ChecklistSymbolKey(
            checked: checked,
            pointSize: pointSize,
            red: (srgb.redComponent * 255).rounded(),
            green: (srgb.greenComponent * 255).rounded(),
            blue: (srgb.blueComponent * 255).rounded()
        )
        if let cached = checklistSymbolCache[key] { return cached }

        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize + 1, weight: .regular)
        guard let base = NSImage(
            systemSymbolName: checked ? "checkmark.circle.fill" : "circle",
            accessibilityDescription: checked ? "Checked" : "Unchecked"
        )?.withSymbolConfiguration(configuration) else { return nil }

        let opaqueTint = srgb.withAlphaComponent(1)
        let symbol = NSImage(size: base.size, flipped: false) { drawInto in
            base.draw(in: drawInto)
            opaqueTint.set()
            drawInto.fill(using: .sourceAtop)
            return true
        }
        checklistSymbolCache[key] = symbol
        return symbol
    }

    /// Checked boxes take the app accent at full strength (matching iOS
    /// DS.accent exactly); unchecked boxes ride the line's own ink at low
    /// alpha so they sit right on any paper tone in light or dark mode.
    private func checklistSymbolColor(checked: Bool, lineRange: NSRange) -> NSColor {
        if checked {
            return NSColor(CosmoColors.cosmoAI)
        }
        let contentIndex = lineRange.location + 2
        var base = textColor ?? .labelColor
        if let storage = textStorage,
           contentIndex < NSMaxRange(lineRange),
           contentIndex < storage.length,
           let color = storage.attribute(.foregroundColor, at: contentIndex, effectiveRange: nil) as? NSColor {
            base = color
        }
        // 0.55, not 0.4 — the most-repeated interactive mark on the page was
        // near-invisible on dark paper (jury round 1, three seats).
        return base.withAlphaComponent(0.55)
    }

    override func paste(_ sender: Any?) {
        let selectedRange = self.selectedRange()

        // Structured block flavor first — kinds survive within the app.
        if blockRowMode,
           let blockData = NSPasteboard.general.data(forType: .cosmoBlocks),
           onStructuredBlockPaste?(blockData) == true {
            return
        }

        // Table cells: a tabular payload (cosmo blocks, an HTML table, TSV,
        // a pipe table, several lines) fills cells right/down from this
        // cell; anything else is inline text and falls through.
        if tableCellMode {
            var imported: ClipboardImport = .none
            if let blockData = NSPasteboard.general.data(forType: .cosmoBlocks),
               let blocks = try? JSONDecoder().decode([RichBlock].self, from: blockData),
               !blocks.isEmpty {
                imported = .blocks(blocks)
            } else {
                imported = ClipboardBlockImporter.read(NSPasteboard.general)
            }
            if onTableCellPaste?(imported) == true {
                return
            }
        }

        if selectedRange.length > 0,
           let pasteboardString = NSPasteboard.general.string(forType: .string),
           let url = URL(string: pasteboardString),
           let scheme = url.scheme,
           ["http", "https", "mailto"].contains(scheme) {
            guard let textStorage = textStorage,
                  selectedRange.location + selectedRange.length <= textStorage.length else {
                super.paste(sender)
                return
            }

            let selectedText = textStorage.attributedSubstring(from: selectedRange)
            let hyperlinkString = NSAttributedString(
                string: selectedText.string,
                attributes: [
                    .link: url,
                    .foregroundColor: PolishHighlightColors.link,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .font: font ?? NSFont.systemFont(ofSize: 16)
                ]
            )

            if shouldChangeText(in: selectedRange, replacementString: hyperlinkString.string) {
                textStorage.replaceCharacters(in: selectedRange, with: hyperlinkString)
                didChangeText()
                setSelectedRange(NSRange(location: selectedRange.location + hyperlinkString.length, length: 0))
            }
            return
        }

        if shortcutDelegate?.textView(self, shouldHandleImagePaste: NSPasteboard.general) == true {
            return
        }

        if let pasteboardString = NSPasteboard.general.string(forType: .string) {
            // Block rows hold exactly one block — a multi-line paste is a
            // STRUCTURAL edit (split into real blocks), never raw text with
            // embedded newlines. If the structural path declines, degrade to
            // soft line separators so the one-block invariant still holds.
            if blockRowMode, pasteboardString.containsHardNewline {
                if onBlockPaste?(pasteboardString) == true {
                    return
                }
                insertText(
                    pasteboardString.replacingHardNewlinesWithLineSeparators(),
                    replacementRange: selectedRange
                )
                return
            }
            insertText(pasteboardString, replacementRange: selectedRange)
            return
        }

        super.paste(sender)
    }

    /// Image drops must route through the same pipeline as image pastes.
    /// NSTextView's native drop (enabled by `importsGraphics`) inserts the raw
    /// file wrapper at intrinsic pixel size with no `imagePath` attribute, so
    /// the image renders clipped by the text column and the resize overlay /
    /// size menu never engage. Local drags (moving an existing image within
    /// the document) keep the native move behavior.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        if importsGraphics,
           (sender.draggingSource as? NSView) !== self,
           NSImage.canInit(with: pasteboard) {
            let point = convert(sender.draggingLocation, from: nil)
            let index = characterIndexForInsertion(at: point)
            setSelectedRange(NSRange(location: index, length: 0))
            if shortcutDelegate?.textView(self, shouldHandleImagePaste: pasteboard) == true {
                window?.makeFirstResponder(self)
                return true
            }
        }
        return super.performDragOperation(sender)
    }

    override func keyDown(with event: NSEvent) {
        FocusModeTextClipboardTarget.activate(self)
        super.keyDown(with: event)
    }

    /// Trampoline for calling super.mouseDown from a closure (Swift doesn't allow super in closures).
    private func superMouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        Self.pointerInteractionGeneration &+= 1
        onNativeMouseDown?()
        guard isEditable else {
            // Notify the canvas block to enter edit mode.
            // After SwiftUI re-renders with isEditable=true, we become
            // first responder and replay the click so the cursor lands
            // at the correct position — single-click-to-edit.
            let savedEvent = event
            onTapWhileReadOnly?()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isEditable else { return }
                self.window?.makeFirstResponder(self)
                self.superMouseDown(with: savedEvent)
            }
            return
        }
        FocusModeTextClipboardTarget.activate(self)
        let localPoint = convert(event.locationInWindow, from: nil)
        if rendersElementChrome,
           let hit = elementHitTest(at: localPoint),
           hit.area == .collapseToggle {
            onToggleElementCollapse?(hit.instanceID)
            return
        }
        if let hit = headingHitTest(at: localPoint), hit.area == .collapseToggle {
            onToggleHeadingCollapse?(hit.range)
            return
        }
        if let lineStart = checklistGlyphHit(at: localPoint) {
            onToggleChecklistItem?(lineStart)
            return
        }
        if let imageRange = imageAttachmentHit(at: localPoint) {
            // Select the attachment so the coordinator reveals the resize handles
            // (Google Docs: click an image → handles appear).
            window?.makeFirstResponder(self)
            setSelectedRange(imageRange)
            return
        }
        if blockRowMode, let dragController = blockDragSelectionController {
            // Shift+Click while another block holds focus — extend into a
            // block-range selection instead of a local text selection.
            if event.modifierFlags.contains(.shift),
               dragController.handleShiftClick?(event.locationInWindow, self) == true {
                return
            }
            if event.clickCount == 1, !event.modifierFlags.contains(.shift),
               trackBlockRowSelectionDrag(with: event, dragController: dragController) {
                return
            }
        }
        super.mouseDown(with: event)
    }

    /// Owns the selection-drag tracking loop for block rows (NSTextView's own
    /// loop lives inside mouseDown and clamps at the view's bounds, so it can
    /// never see a drag cross into the next block). Inside the origin block
    /// this reproduces native character selection; past a block boundary the
    /// controller escalates to whole-block selection; dragging back into the
    /// origin de-escalates. Returns false when the event should fall through
    /// to native handling (e.g. drag-and-drop of selected text).
    private func trackBlockRowSelectionDrag(
        with event: NSEvent,
        dragController: BlockDragSelectionController
    ) -> Bool {
        guard let window, isEditable else { return false }
        let localPoint = convert(event.locationInWindow, from: nil)
        let anchor = characterIndexForInsertion(at: localPoint)
        // Click inside an existing selection starts text drag-and-drop —
        // that's native behavior, keep it.
        let existing = selectedRange()
        if existing.length > 0, NSLocationInRange(anchor, existing) {
            return false
        }

        window.makeFirstResponder(self)
        setSelectedRange(NSRange(location: anchor, length: 0))

        // `.began` (whose handler walks the WHOLE window's view tree to
        // snapshot drag candidates) is deferred until the pointer actually
        // moves — the overwhelming majority of these gestures are plain
        // clicks, which used to pay the full walk plus 20Hz periodic ticks
        // and a redundant finalizing setSelectedRange, all inside mouseDown.
        var began = false
        var escalated = false
        var periodicStarted = false
        var lastWindowPoint = event.locationInWindow
        var lastProcessedPoint = NSPoint(x: CGFloat.infinity, y: CGFloat.infinity)
        defer {
            if periodicStarted { NSEvent.stopPeriodicEvents() }
        }

        while true {
            guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .periodic]) else { break }
            if next.type == .leftMouseUp {
                if began {
                    let resolution = dragController.handleDrag?(next.locationInWindow, .ended, self) ?? .textLocal
                    if resolution == .textLocal {
                        setSelectedRange(selectedRange(), affinity: .downstream, stillSelecting: false)
                    }
                }
                break
            }
            if next.type == .leftMouseDragged {
                lastWindowPoint = next.locationInWindow
            }
            if !began {
                let dx = abs(lastWindowPoint.x - event.locationInWindow.x)
                let dy = abs(lastWindowPoint.y - event.locationInWindow.y)
                guard dx > 2 || dy > 2 else { continue }
                began = true
                _ = dragController.handleDrag?(event.locationInWindow, .began, self)
            }
            // A motionless pointer produces no new geometry — only escalated
            // drags keep processing (edge autoscroll must keep stepping).
            if lastWindowPoint == lastProcessedPoint, !escalated { continue }
            lastProcessedPoint = lastWindowPoint

            let resolution = dragController.handleDrag?(lastWindowPoint, .changed, self) ?? .textLocal
            if resolution == .escalated {
                if !escalated {
                    escalated = true
                    // Whole-block selection owns the gesture — collapse the
                    // partial text selection (Notion behavior).
                    setSelectedRange(NSRange(location: anchor, length: 0))
                    // Periodic ticks exist solely for edge autoscroll while
                    // an escalated drag hovers near the viewport edges.
                    if !periodicStarted {
                        periodicStarted = true
                        NSEvent.startPeriodicEvents(afterDelay: 0.1, withPeriod: 0.05)
                    }
                }
                autoscrollAncestorScrollView(towardWindowPoint: lastWindowPoint)
                continue
            }
            if escalated {
                escalated = false
            }
            let point = convert(lastWindowPoint, from: nil)
            let index = characterIndexForInsertion(at: point)
            let range = NSRange(location: min(anchor, index), length: abs(index - anchor))
            setSelectedRange(range, affinity: index < anchor ? .upstream : .downstream, stillSelecting: true)
        }
        return true
    }

    /// Scrolls the page (the nearest ancestor scroll view — the row's own
    /// scroll view is single-block-sized) while an escalated drag hovers near
    /// the viewport's edges.
    private func autoscrollAncestorScrollView(towardWindowPoint windowPoint: NSPoint) {
        guard let scrollView = nearestAncestorScrollView(excluding: enclosingScrollView) else { return }
        let clipView = scrollView.contentView
        let pointInClip = clipView.convert(windowPoint, from: nil)
        let visible = clipView.bounds
        let margin: CGFloat = 32
        let step: CGFloat = 14

        var origin = visible.origin
        if pointInClip.y < visible.minY + margin {
            origin.y = max(0, origin.y - step)
        } else if pointInClip.y > visible.maxY - margin {
            let documentHeight = scrollView.documentView?.bounds.height ?? 0
            origin.y = min(max(0, documentHeight - visible.height), origin.y + step)
        } else {
            return
        }
        guard origin != visible.origin else { return }
        clipView.setBoundsOrigin(origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    /// Hit-tests the ☐/☑ glyph at the head of a checklist line. Returns the
    /// line's character offset when the click lands on the checkbox itself
    /// (with a little hit comfort), nil for clicks anywhere else.
    fileprivate func checklistGlyphHit(at point: NSPoint) -> Int? {
        guard isEditable, onToggleChecklistItem != nil,
              let layoutManager, let textContainer else { return nil }
        // Block rows know their kind — non-checklist rows skip the glyph
        // layout query on every click, mouse-move, and cursor update.
        if blockRowMode, rowBlockKind != .checklist { return nil }
        let nsText = string as NSString
        guard nsText.length > 0 else { return nil }

        let adjusted = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )
        let glyphIndex = layoutManager.glyphIndex(for: adjusted, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard charIndex < nsText.length else { return nil }

        let lineRange = nsText.lineRange(for: NSRange(location: charIndex, length: 0))
        guard lineRange.length >= 1 else { return nil }
        let glyph = nsText.substring(with: NSRange(location: lineRange.location, length: 1))
        guard glyph == "☐" || glyph == "☑" else { return nil }

        let glyphCharRange = NSRange(location: lineRange.location, length: 1)
        let glyphGlyphRange = layoutManager.glyphRange(forCharacterRange: glyphCharRange, actualCharacterRange: nil)
        var glyphRect = layoutManager.boundingRect(forGlyphRange: glyphGlyphRange, in: textContainer)
        glyphRect.origin.x += textContainerInset.width
        glyphRect.origin.y += textContainerInset.height
        guard glyphRect.insetBy(dx: -4, dy: -2).contains(point) else { return nil }
        return lineRange.location
    }

    /// Hit-tests an inline image attachment. Returns the attachment's character range
    /// (length 1) when the click lands on the image itself, so the caller can select it and
    /// reveal the resize handles. Nil for any other click.
    fileprivate func imageAttachmentHit(at point: NSPoint) -> NSRange? {
        guard isEditable, let layoutManager, let textContainer, let textStorage else { return nil }
        // No attachments ⇒ no hit — skips the glyph/attribute queries on the
        // per-click path for ordinary text rows.
        guard textStorage.containsAttachments else { return nil }
        let nsText = string as NSString
        guard nsText.length > 0 else { return nil }

        let adjusted = NSPoint(x: point.x - textContainerInset.width, y: point.y - textContainerInset.height)
        let glyphIndex = layoutManager.glyphIndex(for: adjusted, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard charIndex < textStorage.length else { return nil }

        let attributes = textStorage.attributes(at: charIndex, effectiveRange: nil)
        guard attributes[.attachment] is NSTextAttachment,
              attributes[RichDocumentAttributeKeys.imagePath] != nil else { return nil }

        // glyphIndex(for:) snaps to the nearest glyph — confirm the click is inside it.
        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1), actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerInset.width
        rect.origin.y += textContainerInset.height
        guard rect.contains(point) else { return nil }

        return NSRange(location: charIndex, length: 1)
    }

    /// The text view's own menu (image presets, AppKit defaults) — the table
    /// cell override prepends its actions to this.
    private func standardMenu(for event: NSEvent) -> NSMenu? {
        let localPoint = convert(event.locationInWindow, from: nil)
        if isEditable, onImageResizePreset != nil, let range = imageAttachmentHit(at: localPoint) {
            return imageResizeMenu(charIndex: range.location)
        }
        return super.menu(for: event)
    }

    private func imageResizeMenu(charIndex: Int) -> NSMenu {
        let intrinsic = imageIntrinsicSize(at: charIndex)
        let maxWidth = max(ImageResizeMath.minWidth, bounds.width - 2 * textContainerInset.width)
        let presets: [(String, CGFloat?)] = [
            ("Small", intrinsic.width * 0.25),
            ("Medium", intrinsic.width * 0.5),
            ("Original size", intrinsic.width),
            ("Fit width", maxWidth),
            ("", nil)   // separator marker
        ]
        let menu = NSMenu()
        for (title, rawWidth) in presets {
            guard !title.isEmpty else { menu.addItem(.separator()); continue }
            let item = NSMenuItem(title: title, action: #selector(handleImageResizeMenu(_:)), keyEquivalent: "")
            item.target = self
            let clamped = rawWidth.map { ImageResizeMath.resolvedSize(displayWidth: $0, intrinsic: intrinsic, maxWidth: maxWidth).width }
            item.representedObject = ImageResizePresetPayload(charIndex: charIndex, width: clamped)
            menu.addItem(item)
        }
        let reset = NSMenuItem(title: "Reset size", action: #selector(handleImageResizeMenu(_:)), keyEquivalent: "")
        reset.target = self
        reset.representedObject = ImageResizePresetPayload(charIndex: charIndex, width: nil)
        menu.addItem(reset)
        return menu
    }

    private func imageIntrinsicSize(at charIndex: Int) -> CGSize {
        guard let storage = textStorage, charIndex < storage.length,
              let attachment = storage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? NSTextAttachment,
              let size = attachment.image?.size, size.width > 0, size.height > 0 else {
            return CGSize(width: 1, height: 1)
        }
        return size
    }

    @objc private func handleImageResizeMenu(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ImageResizePresetPayload else { return }
        onImageResizePreset?(payload.charIndex, payload.width)
    }

    override func updateTrackingAreas() {
        if let disclosureTrackingArea {
            removeTrackingArea(disclosureTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        disclosureTrackingArea = trackingArea
        addTrackingArea(trackingArea)
        super.updateTrackingAreas()
    }

    override func cursorUpdate(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        if updateDisclosureCursor(at: localPoint) {
            return
        }
        if checklistGlyphHit(at: localPoint) != nil {
            NSCursor.pointingHand.set()
            return
        }
        super.cursorUpdate(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        if updateDisclosureCursor(at: localPoint) {
            return
        }
        if checklistGlyphHit(at: localPoint) != nil {
            NSCursor.pointingHand.set()
            return
        }
        super.mouseMoved(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        if scrollsInternally {
            // Let the enclosing NSScrollView handle scrolling within the block
            super.scrollWheel(with: event)
        } else {
            // Forward scroll events to the nearest ancestor scroll view so the
            // surrounding SwiftUI page scrolls as one unit.
            if let ancestorScrollView = nearestAncestorScrollView(excluding: enclosingScrollView) {
                ancestorScrollView.scrollWheel(with: event)
            } else if let scrollView = enclosingScrollView {
                scrollView.nextResponder?.scrollWheel(with: event)
            } else {
                super.scrollWheel(with: event)
            }
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // While whole blocks are selected, the block list owns the clipboard.
        // The window's key-equivalent traversal reaches every block-row text
        // view regardless of first responder — activating self here and
        // performing copy on a collapsed text selection swallowed multi-block
        // ⌘C and wrote nothing to the pasteboard.
        if let blockAction = BlockSelectionClipboardTarget.action(for: event),
           BlockSelectionClipboardTarget.send(blockAction, in: window) {
            return true
        }
        // Only claim the clipboard target when we are actually the focused
        // editor. The window's key-equivalent traversal delivers this event to
        // EVERY CosmoTextView in the window (same reason the block-copy note
        // above exists), so activating a bystander here would collapse the real
        // first responder's live selection — which silently emptied ⌘C/⌘X when
        // two editors share one window (e.g. side-by-side Content Focus panes,
        // where copy produced an empty pasteboard so paste inserted nothing).
        // send() already routes the action to the focused view via
        // currentTextView, so bystanders can defer without losing the action.
        if window?.firstResponder === self {
            FocusModeTextClipboardTarget.activate(self)
        }
        if FocusModeTextClipboardTarget.performKeyEquivalent(event, fallback: self) {
            return true
        }

        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])

        // Block manipulation: ⌥⌘↑/↓ move the row, ⌥⌘1–3 toggle headings.
        if flags == [.command, .option] {
            switch event.keyCode {
            case 126: // ↑
                if shortcutDelegate?.textViewDidRequestBlockShortcut(.moveUp) == true { return true }
            case 125: // ↓
                if shortcutDelegate?.textViewDidRequestBlockShortcut(.moveDown) == true { return true }
            default:
                if let chars = event.charactersIgnoringModifiers,
                   let level = Int(chars), (1...3).contains(level),
                   shortcutDelegate?.textViewDidRequestBlockShortcut(.heading(level)) == true {
                    return true
                }
            }
            return super.performKeyEquivalent(with: event)
        }

        // ⇧⌘L — checklist toggle (the handle menu's To-do, from the keyboard).
        if flags == [.command, .shift],
           event.charactersIgnoringModifiers?.lowercased() == "l",
           shortcutDelegate?.textViewDidRequestBlockShortcut(.checklistToggle) == true {
            return true
        }

        // ⇧⌘H — highlight with the last-used tone (any editor).
        if flags == [.command, .shift],
           event.charactersIgnoringModifiers?.lowercased() == "h",
           window?.firstResponder === self {
            EditorCommandBus.shared.toggleLastHighlight()
            return true
        }

        // Table cells: ⌘Return adds a row, ⌥⌘←/→ move the column,
        // ⇧⌘M / ⇧⌘U merge / unmerge, ⌥⌘T opens the table options.
        if tableCellMode {
            if flags == .command, event.keyCode == 36,
               shortcutDelegate?.textViewDidRequestBlockShortcut(.tableAddRowBelow) == true {
                return true
            }
            if flags == [.command, .option] {
                if event.keyCode == 123, shortcutDelegate?.textViewDidRequestBlockShortcut(.tableMoveColumn(-1)) == true { return true }
                if event.keyCode == 124, shortcutDelegate?.textViewDidRequestBlockShortcut(.tableMoveColumn(1)) == true { return true }
                if event.charactersIgnoringModifiers?.lowercased() == "t",
                   shortcutDelegate?.textViewDidRequestBlockShortcut(.tableOptions) == true { return true }
            }
            if flags == [.command, .shift] {
                let key = event.charactersIgnoringModifiers?.lowercased()
                if key == "m", shortcutDelegate?.textViewDidRequestBlockShortcut(.tableMergeCells) == true { return true }
                if key == "u", shortcutDelegate?.textViewDidRequestBlockShortcut(.tableUnmergeCells) == true { return true }
            }
        }

        guard flags == .command,
              let chars = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch chars {
        case "b":
            shortcutDelegate?.textViewDidRequestFormattingShortcut(.bold)
            return true
        case "i":
            shortcutDelegate?.textViewDidRequestFormattingShortcut(.italic)
            return true
        case "u":
            shortcutDelegate?.textViewDidRequestFormattingShortcut(.underline)
            return true
        case "d":
            if shortcutDelegate?.textViewDidRequestBlockShortcut(.duplicate) == true {
                return true
            }
            return super.performKeyEquivalent(with: event)
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            FocusModeTextClipboardTarget.activate(self)
            onBecomeFirstResponder?()
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            onResignFirstResponder?()
        }
        return resigned
    }

    override func scrollRangeToVisible(_ range: NSRange) {
        // When embedded in a SwiftUI ScrollView (non-scrolling mode), suppress
        // internal scroll-to-cursor. NSTextView calls this during insertText,
        // which shifts the clip view BEFORE the frame has grown to fit the new
        // content — causing a visible upward jitter on newline insertion.
        guard scrollsInternally else {
            return
        }
        super.scrollRangeToVisible(range)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        // Rows without disclosure chrome have no custom cursor rects — skip
        // the forced layout + full line walk (this is scheduled by every
        // invalidateCursorRects, i.e. per keystroke on the active row).
        if blockRowMode, !rowHeadingIsCollapsible, !rendersElementChrome { return }
        guard let storage = textStorage,
              storage.length > 0,
              let layoutManager,
              let textContainer else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        if rendersElementChrome {
            for decoration in DocumentElementEditorDecoration.decorations(in: storage) {
                guard let layout = elementHeaderLayout(for: decoration, storageLength: storage.length) else { continue }
                addCursorRect(layout.chevronHitRect, cursor: .pointingHand)
            }
        }
        for decoration in headingDecorations(in: storage) {
            guard let layout = headingLayout(for: decoration, storageLength: storage.length) else { continue }
            addCursorRect(layout.hitRect, cursor: .pointingHand)
        }
    }

    private func updateDisclosureCursor(at point: NSPoint) -> Bool {
        guard isEditable else { return false }
        if (rendersElementChrome && elementHitTest(at: point)?.area == .collapseToggle) ||
            headingHitTest(at: point)?.area == .collapseToggle {
            NSCursor.pointingHand.set()
            return true
        }
        return false
    }

    private enum ElementHitArea {
        case collapseToggle
    }

    private struct ElementHit {
        let instanceID: UUID
        let area: ElementHitArea
    }

    private enum HeadingHitArea {
        case collapseToggle
    }

    private struct HeadingHit {
        let range: NSRange
        let area: HeadingHitArea
    }

    private struct HeadingDecoration {
        let range: NSRange
        let level: Int
        let isCollapsed: Bool
    }

    private func drawElementBlockDecorations(in dirtyRect: NSRect) {
        guard let storage = textStorage,
              storage.length > 0,
              let layoutManager,
              let textContainer else {
            return
        }

        let decorations = DocumentElementEditorDecoration.decorations(in: storage)
        guard !decorations.isEmpty else { return }

        layoutManager.ensureLayout(for: textContainer)

        for decoration in decorations {
            guard let headerLayout = elementHeaderLayout(for: decoration, storageLength: storage.length) else { continue }
            let chromeRect = headerLayout.chromeRect
            guard chromeRect.intersects(dirtyRect) else { continue }

            drawElementBlockChrome(in: chromeRect)
            drawElementChevron(
                collapsed: decoration.isCollapsed,
                in: headerLayout.chevronGlyphRect,
                color: elementBlockChevronColor
            )
            drawElementBlockSymbol(
                name: decoration.systemIcon,
                in: headerLayout.iconRect,
                color: elementBlockIconColor
            )
        }
    }

    private func drawHeadingDecorations(in dirtyRect: NSRect) {
        // No disclosure chrome ⇒ nothing to draw — skips the line walk on
        // every draw of every non-collapsible row (the active row redraws
        // per keystroke).
        if blockRowMode, !rowHeadingIsCollapsible { return }
        guard let storage = textStorage,
              storage.length > 0,
              let layoutManager,
              let textContainer else {
            return
        }

        let decorations = headingDecorations(in: storage)
        guard !decorations.isEmpty else { return }

        layoutManager.ensureLayout(for: textContainer)

        for decoration in decorations {
            guard let layout = headingLayout(for: decoration, storageLength: storage.length),
                  layout.hitRect.intersects(dirtyRect.insetBy(dx: -10, dy: -10)) else {
                continue
            }
            drawHeadingDisclosureTriangle(
                collapsed: decoration.isCollapsed,
                in: layout.glyphRect,
                color: headingChevronColor
            )
        }
    }

    private func elementHitTest(at point: NSPoint) -> ElementHit? {
        guard let storage = textStorage,
              storage.length > 0,
              let layoutManager,
              let textContainer else {
            return nil
        }

        layoutManager.ensureLayout(for: textContainer)
        let decorations = DocumentElementEditorDecoration.decorations(in: storage)
        for decoration in decorations.reversed() {
            guard let instanceID = decoration.instanceID,
                  let layout = elementHeaderLayout(for: decoration, storageLength: storage.length) else {
                continue
            }
            if layout.chevronHitRect.contains(point) {
                return ElementHit(instanceID: instanceID, area: .collapseToggle)
            }
        }
        return nil
    }

    private func headingHitTest(at point: NSPoint) -> HeadingHit? {
        // Block rows know their kind up front — skip the forced layout +
        // full line walk unless this row actually renders a disclosure.
        if blockRowMode && !rowHeadingIsCollapsible { return nil }
        guard let storage = textStorage,
              storage.length > 0,
              let layoutManager,
              let textContainer else {
            return nil
        }

        layoutManager.ensureLayout(for: textContainer)
        for decoration in headingDecorations(in: storage).reversed() {
            guard let layout = headingLayout(for: decoration, storageLength: storage.length) else {
                continue
            }
            if layout.hitRect.contains(point) {
                return HeadingHit(range: decoration.range, area: .collapseToggle)
            }
        }
        return nil
    }

    private func headingDecorations(in storage: NSAttributedString) -> [HeadingDecoration] {
        guard storage.length > 0 else { return [] }

        let string = storage.string as NSString
        let fullRange = NSRange(location: 0, length: storage.length)
        var decorations: [HeadingDecoration] = []
        var lineStart = 0

        while lineStart < storage.length {
            let lineRange = string.lineRange(for: NSRange(location: lineStart, length: 0))
            let safeRange = NSIntersectionRange(lineRange, fullRange)
            let trimmedRange = trimmingTrailingNewline(from: safeRange, in: string)

            if trimmedRange.length > 0,
               let level = intValue(storage.attribute(
                RichDocumentAttributeKeys.headingLevel,
                at: trimmedRange.location,
                effectiveRange: nil
               )) {
                let isCollapsed = boolValue(storage.attribute(
                    RichDocumentAttributeKeys.headingCollapsed,
                    at: trimmedRange.location,
                    effectiveRange: nil
                )) ?? false
                let isCollapsible = boolValue(storage.attribute(
                    RichDocumentAttributeKeys.headingCollapsible,
                    at: trimmedRange.location,
                    effectiveRange: nil
                )) ?? false
                // Plain headings draw no disclosure chrome. A collapsed
                // heading always keeps its chevron regardless of the flag —
                // the hidden section must stay expandable.
                if isCollapsible || isCollapsed {
                    decorations.append(HeadingDecoration(
                        range: trimmedRange,
                        level: max(1, min(3, level)),
                        isCollapsed: isCollapsed
                    ))
                }
            }

            lineStart = lineRange.location + lineRange.length
            if lineStart <= safeRange.location {
                break
            }
        }

        return decorations
    }

    private func headingLayout(
        for decoration: HeadingDecoration,
        storageLength: Int
    ) -> (hitRect: CGRect, glyphRect: CGRect)? {
        guard let layoutManager,
              let textContainer else {
            return nil
        }

        let characterRange = NSIntersectionRange(
            decoration.range,
            NSRange(location: 0, length: storageLength)
        )
        guard characterRange.length > 0 else { return nil }

        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: characterRange,
            actualCharacterRange: nil
        )
        let lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        guard lineRect.width.isFinite, lineRect.height.isFinite, lineRect.height > 0 else {
            return nil
        }

        let hitSize: CGFloat = 36
        let glyphSize: CGFloat = 14
        let glyphMinX = textContainerOrigin.x + lineRect.minX
        let targetMidX = max(textContainerOrigin.x + (hitSize / 2), glyphMinX - 18)
        let hitRect = CGRect(
            x: targetMidX - (hitSize / 2),
            y: textContainerOrigin.y + lineRect.midY - (hitSize / 2),
            width: hitSize,
            height: hitSize
        )
        return (
            hitRect,
            CGRect(
                x: hitRect.midX - (glyphSize / 2),
                y: hitRect.midY - (glyphSize / 2),
                width: glyphSize,
                height: glyphSize
            )
        )
    }

    private func elementHeaderLayout(
        for decoration: DocumentElementEditorDecoration,
        storageLength: Int
    ) -> DocumentElementHeaderLayout? {
        guard let layoutManager,
              let textContainer else {
            return nil
        }

        let characterRange = NSIntersectionRange(
            decoration.range,
            NSRange(location: 0, length: storageLength)
        )
        guard characterRange.length > 0 else { return nil }

        let headerGlyphRange = layoutManager.glyphRange(
            forCharacterRange: characterRange,
            actualCharacterRange: nil
        )
        let headerGlyphRect = layoutManager.boundingRect(forGlyphRange: headerGlyphRange, in: textContainer)
        guard headerGlyphRect.width.isFinite, headerGlyphRect.height.isFinite, headerGlyphRect.height > 0 else {
            return nil
        }

        let blockGlyphRange = layoutManager.glyphRange(
            forCharacterRange: NSIntersectionRange(
                decoration.blockRange,
                NSRange(location: 0, length: storageLength)
            ),
            actualCharacterRange: nil
        )
        let blockGlyphRect = layoutManager.boundingRect(forGlyphRange: blockGlyphRange, in: textContainer)
        guard blockGlyphRect.width.isFinite, blockGlyphRect.height.isFinite, blockGlyphRect.height > 0 else {
            return nil
        }

        let blockMinY = min(headerGlyphRect.minY, blockGlyphRect.minY)
        let blockMaxY = max(headerGlyphRect.maxY, blockGlyphRect.maxY)
        let chromeRect = NSRect(
            x: textContainerOrigin.x,
            y: textContainerOrigin.y + blockMinY - 4,
            width: max(80, bounds.width - (textContainerOrigin.x * 2)),
            height: max(blockMaxY - blockMinY + 10, DocumentElementHeaderLayout.headerHeight + 4)
        )
        return DocumentElementHeaderLayout(
            chromeRect: chromeRect,
            headerMidY: textContainerOrigin.y + headerGlyphRect.midY,
            depth: decoration.depth,
            fontSize: elementBlockBaseFontSize
        )
    }

    private func drawElementBlockChrome(in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let bodyRect = rect.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: bodyRect, xRadius: 10, yRadius: 10)

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -1),
            blur: 2.0,
            color: elementBlockShadowColor.cgColor
        )
        elementBlockFillColor.setFill()
        path.fill()
        context.restoreGState()

        elementBlockStrokeColor.setStroke()
        path.lineWidth = 0.7
        path.stroke()
    }

    private func drawHeadingDisclosureTriangle(collapsed: Bool, in rect: NSRect, color: NSColor) {
        let path = NSBezierPath()

        if collapsed {
            path.move(to: NSPoint(x: rect.minX + 3, y: rect.minY + 2))
            path.line(to: NSPoint(x: rect.maxX - 2, y: rect.midY))
            path.line(to: NSPoint(x: rect.minX + 3, y: rect.maxY - 2))
        } else {
            path.move(to: NSPoint(x: rect.minX + 1.5, y: rect.minY + 3))
            path.line(to: NSPoint(x: rect.maxX - 1.5, y: rect.minY + 3))
            path.line(to: NSPoint(x: rect.midX, y: rect.maxY - 2))
        }

        path.close()
        color.setFill()
        path.fill()
    }

    private func drawElementChevron(collapsed: Bool, in rect: NSRect, color: NSColor) {
        let path = NSBezierPath()
        path.lineWidth = 1.3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        if collapsed {
            path.move(to: NSPoint(x: rect.minX + 2, y: rect.minY + 1))
            path.line(to: NSPoint(x: rect.maxX - 1.5, y: rect.midY))
            path.line(to: NSPoint(x: rect.minX + 2, y: rect.maxY - 1))
        } else {
            path.move(to: NSPoint(x: rect.minX + 1, y: rect.minY + 2.5))
            path.line(to: NSPoint(x: rect.midX, y: rect.maxY - 1.5))
            path.line(to: NSPoint(x: rect.maxX - 1, y: rect.minY + 2.5))
        }

        color.setStroke()
        path.stroke()
    }

    private func drawElementBlockSymbol(name: String, in rect: NSRect, color: NSColor) {
        let validName = DocumentElementSymbol.validName(name)
        guard let baseImage = NSImage(systemSymbolName: validName, accessibilityDescription: nil) else { return }
        let configuration = NSImage.SymbolConfiguration(
            pointSize: min(rect.width, rect.height),
            weight: .regular
        )
        let image = baseImage.withSymbolConfiguration(configuration) ?? baseImage
        image.isTemplate = true
        color.set()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private var elementBlockFillColor: NSColor {
        effectiveElementBlockDarkMode
            ? NSColor(red: 0.105, green: 0.108, blue: 0.115, alpha: 1.0)
            : NSColor.white
    }

    private var elementBlockStrokeColor: NSColor {
        effectiveElementBlockDarkMode
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.black.withAlphaComponent(0.07)
    }

    private var elementBlockShadowColor: NSColor {
        effectiveElementBlockDarkMode
            ? NSColor.black.withAlphaComponent(0.30)
            : NSColor.black.withAlphaComponent(0.04)
    }

    private var elementBlockChevronColor: NSColor {
        effectiveElementBlockDarkMode
            ? NSColor.white.withAlphaComponent(0.48)
            : NSColor(DS.documentTextMuted).withAlphaComponent(0.78)
    }

    private var elementBlockIconColor: NSColor {
        effectiveElementBlockDarkMode
            ? NSColor.white.withAlphaComponent(0.65)
            : NSColor(DS.documentTextSecondary).withAlphaComponent(0.85)
    }

    private var elementBlockSecondaryColor: NSColor {
        effectiveElementBlockDarkMode
            ? NSColor.white.withAlphaComponent(0.58)
            : NSColor(DS.documentTextSecondary).withAlphaComponent(0.82)
    }

    private var headingChevronColor: NSColor {
        if let headingDisclosureColor {
            return headingDisclosureColor
        }
        return effectiveElementBlockDarkMode
            ? NSColor.white.withAlphaComponent(0.50)
            : NSColor(DS.documentTextSecondary).withAlphaComponent(0.70)
    }

    private var effectiveElementBlockDarkMode: Bool {
        elementBlockDarkMode
            || effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func trimmingTrailingNewline(from range: NSRange, in string: NSString) -> NSRange {
        var length = range.length
        while length > 0 {
            let character = string.substring(with: NSRange(location: range.location + length - 1, length: 1))
            if character == "\n" || character == "\r" {
                length -= 1
            } else {
                break
            }
        }
        return NSRange(location: range.location, length: length)
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}

extension CosmoTextView {
    static func scrollableCosmoTextView() -> CosmoScrollView {
        let scrollView = CosmoScrollView()
        let clipView = CosmoClipView()
        clipView.owningScrollView = scrollView
        scrollView.contentView = clipView

        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .none
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = CosmoTextView()
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.documentView = textView

        // ── Disable implicit Core Animation on geometry keys ─────────────────
        // The "ghost line above" jitter on Return / typing is Core Animation
        // implicitly animating bounds/position/frame whenever the layer's
        // geometry changes. We already wrap our own setFrameSize calls in an
        // NSAnimationContext with duration=0, but when SwiftUI (driven by our
        // `invalidateIntrinsicContentSize`) writes new frames to the hosting
        // NSView, those writes go through the default CA action map and
        // animate with the default ~0.25s curve. During that animation, both
        // the old and new layer positions are rendered, which the user sees
        // as the previous line "ghosting" above itself for a frame.
        //
        // The subclasses (CosmoScrollView/CosmoClipView/CosmoTextView) also
        // override `makeBackingLayer()` to set these actions on every layer
        // creation, so this loop just primes any layer that already exists.
        for view in [scrollView as NSView, clipView, textView] {
            view.wantsLayer = true
            view.layer?.actions = suppressedLayerActions
        }

        return scrollView
    }
}

enum EditorLayoutMetrics {
    static func singleLineVerticalInset(fontSize: CGFloat, compact: Bool) -> CGFloat {
        max(4, ceil(fontSize * 0.15))
    }

    static func singleLineHeight(
        fontSize: CGFloat,
        compact: Bool,
        baseFontWeight: NSFont.Weight = .regular
    ) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: baseFontWeight)
        let inset = singleLineVerticalInset(fontSize: fontSize, compact: compact)
        return ceil(font.ascender - font.descender + font.leading + inset * 2 + 2)
    }

    static func titleVerticalInset(fontSize: CGFloat, compact: Bool) -> CGFloat {
        max(compact ? 4 : 6, ceil(fontSize * (compact ? 0.10 : 0.12)))
    }

    static func titleHeight(
        fontSize: CGFloat,
        compact: Bool,
        baseFontWeight: NSFont.Weight = .regular,
        lineCount: Int
    ) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: baseFontWeight)
        let inset = titleVerticalInset(fontSize: fontSize, compact: compact)
        return ceil((font.ascender - font.descender + font.leading) * CGFloat(max(1, lineCount)) + inset * 2 + 2)
    }
}

// MARK: - Representable

/// The caret is the brand (iA Writer's blue caret, CosmoOS's forest green):
/// every editor surface shares one accent insertion point and a warm accent
/// selection wash instead of the system blue. macOS's native insertion
/// indicator already soft-fades and rounds the caret — color is our voice.
/// Deliberately pinned to the static Greenhouse green, NOT the palette-driven
/// DS.accent: mono themes resolve DS.accent to near-ink, which reads as a
/// stock black caret and a grey selection. The caret stays green everywhere.
enum EditorCaretPalette {
    static func insertionPoint(darkMode: Bool) -> NSColor {
        let accent = NSColor(CosmoColors.cosmoAI)
        guard darkMode else { return accent }
        return accent.blended(withFraction: 0.38, of: .white) ?? accent
    }

    static func selectionBackground(darkMode: Bool) -> NSColor {
        let accent = NSColor(CosmoColors.cosmoAI)
        if darkMode {
            let lifted = accent.blended(withFraction: 0.30, of: .white) ?? accent
            return lifted.withAlphaComponent(0.34)
        }
        return accent.withAlphaComponent(0.18)
    }
}

extension String {
    /// True when the string contains a block-splitting newline (\n, \r,
    /// \r\n). Soft separators (U+2028/U+2029) stay inside a block and don't
    /// count — the serializer only splits blocks on hard newlines.
    var containsHardNewline: Bool {
        contains("\n") || contains("\r")
    }

    /// Degrades hard newlines to soft line separators (U+2028) — the escape
    /// hatch that preserves the one-block-per-row invariant when a structural
    /// splice isn't possible.
    func replacingHardNewlinesWithLineSeparators() -> String {
        replacingOccurrences(of: "\r\n", with: "\u{2028}")
            .replacingOccurrences(of: "\n", with: "\u{2028}")
            .replacingOccurrences(of: "\r", with: "\u{2028}")
    }

    /// Normalizes newline flavors to \n for line-based parsing.
    func normalizingHardNewlines() -> String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

/// Keys the coordinator routes to an open slash menu while the text view
/// keeps first responder (type-through model — the menu never takes focus).
enum SlashMenuKeyEvent {
    case up
    case down
    case commit
    case dismiss
}

/// Replace the entire text storage out-of-band and drop the per-view undo
/// stack in the same breath. A full `setAttributedString` swaps the buffer
/// WITHOUT going through the NSTextView undo system, so every
/// `_undoRedoTextOperation:` the user's prior typing registered now points at
/// ranges/backing that no longer exist. Leaving them on the stack means a later
/// ⌘Z pops a stale operation and messages a freed undo target → EXC_BAD_ACCESS
/// (the "undo after applying an inline-assistant edit" crash). Undoing *across*
/// an out-of-band content replacement is meaningless anyway. No-op for block
/// rows, where `allowsUndo == false` makes `undoManager` nil. Document-editor
/// analog of the Command-K field-editor undo-drain fix.
@MainActor
private func replaceStorageDroppingUndo(_ textView: NSTextView, with attributed: NSAttributedString) {
    textView.textStorage?.setAttributedString(attributed)
    textView.undoManager?.removeAllActions()
}

/// An immutable snapshot of the text view's current content, for handing to
/// SwiftUI state.
///
/// INVARIANT: `NSTextView.attributedString()` returns the LIVE `NSTextStorage`,
/// not a copy. Assigning it straight into the `attributedText` binding stores
/// the SAME object SwiftUI already holds, so `onChange(of: attributedText)`
/// compares a value against itself, reports no change, and never fires — and
/// `syncDocumentFromEditor()`, the only path that turns typed text into a
/// `RichDocument`, never runs. The text view keeps accepting keystrokes while
/// the document silently freezes at whatever it last held, and the next save
/// persists that stale document. That is the July 20 2026 note data-loss bug:
/// only the first keystroke after an external content write changed the object
/// identity, so blocks kept exactly one character unless a Return-split (which
/// carries `livePlainText` explicitly) happened to rescue them.
///
/// Every write of view content into SwiftUI state MUST go through this. Set
/// `lastReconciledBindingText` to the same snapshot so the update-pass identity
/// fast path still recognises the binding as already-applied.
@MainActor
private func viewContentSnapshot(_ textView: NSTextView) -> NSAttributedString {
    NSAttributedString(attributedString: textView.attributedString())
}

struct TextKitEditorRepresentable: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString
    @Binding var plainText: String
    @Binding var shouldRefocus: Bool

    var fontSize: CGFloat = 16
    var fontDesign: NSFontDescriptor.SystemDesign = .default
    var compact: Bool = false
    /// Per-document line-spacing delta (the Aa menu's Compact/Standard/Airy)
    /// applied on top of the base body leading. Headings and titles keep
    /// their own fixed rhythm.
    var lineSpacingAdjustment: CGFloat = 0
    var darkMode: Bool = false
    var overrideTextColor: NSColor? = nil
    var overrideFont: NSFont? = nil
    var headingDisclosureColor: NSColor? = nil
    var allowSlashCommands: Bool = true
    var allowMentions: Bool = true
    var allowImages: Bool = true
    var allowSelectionMenu: Bool = true
    var rendersElementChrome: Bool = true
    var singleLine: Bool = false
    var titleConfiguration: TitleEditorConfiguration? = nil
    var baseFontWeight: NSFont.Weight = .regular
    var polishHighlights: WritingAnalysis? = nil
    var focusBandRange: NSRange? = nil
    var focusBandRangeProvider: ((String, NSRange) -> NSRange?)? = nil
    var editorTargetID: String? = nil
    var navigationTargetID: UUID? = nil
    var textAlignment: NSTextAlignment = .natural

    var typewriterMode: Bool = false

    var isEditable: Bool = true
    var scrollsInternally: Bool = false

    /// Slash menu trigger/update — caret-anchored position plus the live query
    /// typed after the "/" (type-through filtering: typing stays in the text
    /// view; the menu never takes focus).
    var onSlashCommand: ((CGPoint, String) -> Void)?
    /// Keyboard routed to the open slash menu (↑/↓/Return/Esc) while the text
    /// view keeps first responder. Returns true when the menu consumed the key.
    var onSlashMenuKey: ((SlashMenuKeyEvent) -> Bool)?
    var onMention: ((CGPoint, String) -> Void)?
    var onSelectionChange: ((EditorSelectionSnapshot) -> Void)?
    var onDismissMenus: (() -> Void)?
    /// Whether the host currently shows an overlay menu (slash, mention,
    /// selection). Lets Esc close menus before escalating to block selection.
    var menusVisible: (() -> Bool)?
    var onContentHeightChange: ((CGFloat) -> Void)?
    var onActivate: (() -> Void)?
    var onDeactivate: (() -> Void)?
    var onCommit: (() -> Void)?
    var onBoundaryCommand: ((EditorBoundaryCommand) -> Bool)?
    /// Block-row semantic slash execution (BlockTextEditorRow → BlockOperations).
    /// Receives the command plus the live plain text with the "/" trigger and
    /// query ALREADY removed. Returns true when the block pipeline applied it.
    var onSlashCommandSelected: ((SlashCommand, String) -> Bool)?
    /// Direct per-keystroke plain text callback — fires from syncBindings immediately,
    /// bypassing the SwiftUI @Binding→onChange chain which can coalesce/skip updates.
    var onPlainTextDidChange: ((String) -> Void)?
    /// Direct structured callback for edits that change block topology and need
    /// SwiftUI block views to update immediately.
    var onStructuredDocumentChange: ((RichDocument, String) -> Void)?
    /// Fired after this coordinator writes the attributed buffer into the
    /// (box-backed) binding — the host parses the document then.
    var onContentCommitted: (() -> Void)?
    /// Block-row mode: Return splits the block (boundary command) instead of
    /// inserting a newline into this text view.
    var splitsOnReturn: Bool = false
    /// Table cell mode: one rich paragraph in a table cell — Tab/Return/
    /// arrows at the edges navigate cells through boundary commands.
    var tableCellMode: Bool = false
    /// Table cell mode: builds the cell's context-menu items on demand.
    var tableContextMenu: (() -> NSMenu?)? = nil
    /// One-shot caret placement after an external structural edit (split/merge).
    var caretRequest: EditorCaretRequest? = nil
    /// Bumped by the host when editor content was rebuilt from the document by
    /// an EXTERNAL change — content must apply even while this view is focused.
    var externalContentToken: Int = 0
    /// Cross-block drag selection bridge (block rows; set via environment).
    var dragSelectionController: BlockDragSelectionController? = nil
    /// The block this row renders (block rows only) — for drag hit-testing.
    var rowBlockID: UUID? = nil
    /// The row's block kind (block rows only) — empty styled blocks need
    /// their typing attributes seeded, since there is no attributed run for
    /// the first character to inherit from.
    var rowBlockKind: RichBlockKind? = nil
    /// Whether the row's heading is collapsible (block rows only) — seeded
    /// typing attributes must round-trip the plain vs. toggle-heading choice.
    var rowHeadingIsCollapsible: Bool = false
    /// Identifies this editor instance for slash-command notifications —
    /// target IDs are shared across surfaces (focus-mode row vs canvas block
    /// of the same note), instance IDs are not.
    var editorInstanceID: UUID? = nil
    /// Mount-time content seed: makeNSView runs BEFORE onAppear's
    /// syncEditorFromDocument, so the binding text is still empty on first
    /// layout. Without a seed every row laid out empty, then re-laid out when
    /// the sync landed — a long note's open paid the whole document twice.
    var initialContent: (() -> NSAttributedString)? = nil

    var resolvedEditorTextColor: NSColor {
        overrideTextColor ?? (darkMode ? NSColor.white : NSColor(DS.documentText))
    }

    /// Every value input `configureTextView` renders from. When unchanged,
    /// updateNSView skips the full reconfiguration — the pass sets ~40 AppKit
    /// properties and re-derives fonts/styles, which is pure waste on the
    /// every-row updates a block list triggers for focus changes and
    /// structural edits. Live behavior (delegate callbacks) is NOT captured
    /// here: closures read `coordinator.parent` at call time, and the parent
    /// is refreshed on every update.
    struct EditorConfigSignature: Equatable {
        var fontSize: CGFloat
        var fontDesign: NSFontDescriptor.SystemDesign
        var compact: Bool
        var lineSpacingAdjustment: CGFloat
        var darkMode: Bool
        var overrideTextColor: NSColor?
        var overrideFont: NSFont?
        var headingDisclosureColor: NSColor?
        var allowImages: Bool
        var rendersElementChrome: Bool
        var singleLine: Bool
        var titleConfiguration: TitleEditorConfiguration?
        var baseFontWeight: NSFont.Weight
        var textAlignment: NSTextAlignment
        var isEditable: Bool
        var scrollsInternally: Bool
        var splitsOnReturn: Bool
        var tableCellMode: Bool
        var rowBlockID: UUID?
        var rowBlockKind: RichBlockKind?
        var rowHeadingIsCollapsible: Bool
        var dragControllerID: ObjectIdentifier?
    }

    /// The inputs `applyStorageOverrides` stamps into the text storage. The
    /// stamp dirties the storage (full-range addAttribute inside
    /// beginEditing/endEditing) and forces TextKit invalidation, so it must
    /// only run when content was replaced or one of these actually changed.
    struct StorageOverrideSignature: Equatable {
        var overrideTextColor: NSColor?
        var overrideFont: NSFont?
        var appliesHeadingIndents: Bool
    }

    private var configSignature: EditorConfigSignature {
        EditorConfigSignature(
            fontSize: fontSize,
            fontDesign: fontDesign,
            compact: compact,
            lineSpacingAdjustment: lineSpacingAdjustment,
            darkMode: darkMode,
            overrideTextColor: overrideTextColor,
            overrideFont: overrideFont,
            headingDisclosureColor: headingDisclosureColor,
            allowImages: allowImages,
            rendersElementChrome: rendersElementChrome,
            singleLine: singleLine,
            titleConfiguration: titleConfiguration,
            baseFontWeight: baseFontWeight,
            textAlignment: textAlignment,
            isEditable: isEditable,
            scrollsInternally: scrollsInternally,
            splitsOnReturn: splitsOnReturn,
            tableCellMode: tableCellMode,
            rowBlockID: rowBlockID,
            rowBlockKind: rowBlockKind,
            rowHeadingIsCollapsible: rowHeadingIsCollapsible,
            dragControllerID: dragSelectionController.map(ObjectIdentifier.init)
        )
    }

    private var storageOverrideSignature: StorageOverrideSignature {
        StorageOverrideSignature(
            overrideTextColor: overrideTextColor,
            overrideFont: overrideFont,
            appliesHeadingIndents: !singleLine && titleConfiguration == nil
        )
    }

    func makeNSView(context: Context) -> CosmoScrollView {
        let scrollView = CosmoTextView.scrollableCosmoTextView()
        scrollView.forwardsScrollEvents = !scrollsInternally

        guard let textView = scrollView.documentView as? CosmoTextView else {
            return scrollView
        }

        configureTextView(textView, context: context, isInitial: true)
        context.coordinator.lastConfigSignature = configSignature
        let mountSeed: NSAttributedString? =
            attributedText.length == 0 ? initialContent?() : nil
        if let mountSeed {
            replaceStorageDroppingUndo(textView, with: mountSeed)
            // The binding is still empty; keep the reconcile cache unset and
            // remember the seed so the first real binding write (onAppear's
            // sync of this same serialization) is recognized as already
            // applied instead of re-replacing — and so the deep compare runs
            // serialized-vs-serialized, immune to the override stamp below.
            context.coordinator.mountSeedContent = mountSeed
        } else {
            replaceStorageDroppingUndo(textView, with: attributedText)
            context.coordinator.lastReconciledBindingText = attributedText
        }
        applyStorageOverrides(textView.textStorage)
        context.coordinator.lastStorageOverrideSignature = storageOverrideSignature
        context.coordinator.applyPolishHighlights(to: textView)
        context.coordinator.applyFocusBand(to: textView)
        context.coordinator.textViewReference = textView
        textView.onSelectAllEscalation = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onBoundaryCommand?(.selectAllBlocks) == true
        }
        context.coordinator.installScrollDismissObserver(for: scrollView)
        context.coordinator.installFrameChangeObserver(for: scrollView)
        context.coordinator.normalizeSingleLineViewport(for: textView)
        context.coordinator.notifyContentHeightChange(for: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: CosmoScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CosmoTextView else { return }
        scrollView.forwardsScrollEvents = !scrollsInternally
        context.coordinator.parent = self
        // Flag that we're inside SwiftUI's layout pass — delegate callbacks must not
        // write @Binding values synchronously (causes "Modifying state during view update").
        context.coordinator.isUpdatingFromSwiftUI = true
        defer { context.coordinator.isUpdatingFromSwiftUI = false }
        // The input method owns its attributed buffer and selection until
        // commit; even a typography reconfiguration must wait.
        guard !textView.hasMarkedText() else { return }
        let signature = configSignature
        if context.coordinator.lastConfigSignature != signature {
            context.coordinator.lastConfigSignature = signature
            configureTextView(textView, context: context, isInitial: false)
        }
        // makeNSView runs before the view joins a window — window-scoped
        // config re-runs once the (or a new) window is attached.
        context.coordinator.attachWindowConfigIfNeeded(for: textView)

        // Skip text storage replacement when the change originated from user typing —
        // the text view already has the correct content, avoiding scroll position resets.
        // ALSO skip when the text view IS the first responder (user is actively editing).
        // The 50ms deferred attributedText sync means `attributedText` binding can be stale.
        // Without this guard, GRDB observation spam triggers updateNSView which overwrites
        // the NSTextView with stale binding content, destroying text the user just typed.
        let isFirstResponder = textView.window?.firstResponder == textView
        // Structural edits (split/merge/delete, style changes) rebuild the
        // content externally and MUST land even in the focused text view —
        // otherwise the view keeps stale text and later writes it back over
        // the document (the classic merge-corruption bug).
        let hasFreshExternalContent = context.coordinator.lastAppliedContentToken != externalContentToken
        guard (!context.coordinator.isUpdatingFromTextView && !isFirstResponder) || hasFreshExternalContent else {
            // Stamp only when an edit may have introduced un-overridden runs
            // (paste heal) or the override inputs changed. Unconditional, this
            // ran two full-range attribute scans on the ACTIVE editor for
            // every update — O(document) per keystroke in continuous editors.
            if context.coordinator.viewContentDirty
                || context.coordinator.lastStorageOverrideSignature != storageOverrideSignature {
                applyStorageOverrides(textView.textStorage)
                context.coordinator.lastStorageOverrideSignature = storageOverrideSignature
            }
            context.coordinator.applyPolishHighlights(to: textView)
            context.coordinator.applyFocusBand(to: textView)
            if shouldRefocus {
                context.coordinator.scheduleRefocus(to: textView)
            }
            context.coordinator.applyCaretRequestIfNeeded(to: textView)
            context.coordinator.navigateIfNeeded(to: navigationTargetID, in: textView)
            return
        }

        context.coordinator.lastAppliedContentToken = externalContentToken
        // The text view is being aligned with the binding — it's authoritative
        // again, so stale-write-back suppression can lift.
        context.coordinator.awaitingExternalContent = false
        // Identity fast path: the binding text is @State owned by this editor,
        // so a new INSTANCE is the only way its content changes. Skipping the
        // deep isEqual matters twice over: the compare is O(content) per row,
        // and for themed editors the post-replace override stamp makes the
        // view's storage permanently unequal to the serialized binding — the
        // deep compare then re-ran a full storage replace (and TextKit
        // relayout) for every idle row on every update.
        var storageWasReplaced = false
        if context.coordinator.lastReconciledBindingText !== attributedText {
            context.coordinator.lastReconciledBindingText = attributedText
            // One-shot: a seeded mount already applied this exact
            // serialization — compare against the pre-stamp seed (the view's
            // live storage carries override stamps and would never compare
            // equal to the serialized binding).
            let mountSeed = context.coordinator.mountSeedContent
            context.coordinator.mountSeedContent = nil
            // Pointer check first: the sync box now hands .onAppear the SAME
            // instance initialContent built, so the mount reconcile is free —
            // the deep compare only runs for a seed rebuilt in between.
            if let mountSeed, mountSeed === attributedText || mountSeed.isEqual(to: attributedText) {
                // Already applied at mount — heights and layout are current.
            } else if !textView.attributedString().isEqual(to: attributedText) {
                let selectedRange = textView.selectedRange()
                // The attachment objects the overlay points at are about to be replaced.
                context.coordinator.removeImageResizeOverlay()
                // Fresh external content (structural rebuild, inline-assistant apply,
                // GRDB reload) replaces the buffer out-of-band — drop the now-stale
                // per-view undo stack so a later ⌘Z can't message a freed undo target.
                replaceStorageDroppingUndo(textView, with: attributedText)
                storageWasReplaced = true
                // The view now mirrors the binding — nothing left to flush.
                context.coordinator.viewContentDirty = false
                applyStorageOverrides(textView.textStorage)
                // Skip the selection restore when a caret request is about to
                // place the caret anyway (merge seam, split landing) — the
                // restore fired a full extra selection-change fan-out only
                // for placeCaretWhenReady to move the caret again one tick
                // later.
                let caretRequestPending = caretRequest != nil
                    && caretRequest?.token != context.coordinator.lastAppliedCaretToken
                if !caretRequestPending {
                    let length = (textView.string as NSString).length
                    let safeLocation = min(selectedRange.location, length)
                    let safeLength = min(selectedRange.length, length - safeLocation)
                    textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
                }
                context.coordinator.normalizeSingleLineViewport(for: textView)
                context.coordinator.notifyContentHeightChange(for: textView)
            }
        }

        let overrideSignature = storageOverrideSignature
        if storageWasReplaced || context.coordinator.lastStorageOverrideSignature != overrideSignature {
            context.coordinator.lastStorageOverrideSignature = overrideSignature
            if !storageWasReplaced {
                applyStorageOverrides(textView.textStorage)
            }
        }
        // A replaced storage lost its painted backgrounds and temporary
        // attributes — force both passes to restamp onto the fresh buffer.
        context.coordinator.applyPolishHighlights(to: textView, force: storageWasReplaced)
        context.coordinator.applyFocusBand(to: textView, force: storageWasReplaced)
        context.coordinator.normalizeSingleLineViewport(for: textView)
        // Re-measure height whenever fresh external content lands, even if the
        // string itself is unchanged. A newly-split EMPTY block has empty
        // content that equals the binding, so the guarded branch above skips its
        // height update — yet the fresh row can briefly inherit the previous
        // editor's tall frame and, with nothing to re-measure it, stay
        // page-sized (the "one block became huge" gap on Return). Gated on
        // fresh external content so idle rows don't re-measure on every
        // keystroke; notifyContentHeightChange is tolerance-guarded (>1pt) and
        // idempotent regardless.
        if hasFreshExternalContent {
            // An EMPTY styled row (fresh heading from the slash menu) has no
            // attributed run for typing to inherit — seed the typing
            // attributes for its kind BEFORE measuring, so the caret and the
            // row height are heading-sized immediately (Notion behavior),
            // and the first character round-trips with the right kind.
            if splitsOnReturn, textView.string.isEmpty {
                seedTypingAttributesForEmptyRow(in: textView)
            }
            context.coordinator.notifyContentHeightChange(for: textView)
            // The invalidation above is deferred out of this update pass;
            // the watchdog confirms the hosting frame actually followed it.
            context.coordinator.scheduleIntrinsicHeightReconcile()
        }
        context.coordinator.applyCaretRequestIfNeeded(to: textView)
        context.coordinator.navigateIfNeeded(to: navigationTargetID, in: textView)

        if shouldRefocus {
            context.coordinator.scheduleRefocus(to: textView)
        }
    }

    private func configureTextView(_ textView: CosmoTextView, context: Context, isInitial: Bool = true) {
        textView.isRichText = true
        // Block rows use document-level snapshot undo (BlockUndoRegistrar):
        // per-view NSTextView undo stacks reference ranges that stop existing
        // after structural rebuilds and resurrect stale text on ⌘Z.
        textView.allowsUndo = !splitsOnReturn
        textView.isEditable = isEditable
        textView.isSelectable = isEditable

        // Wire tap-to-edit callback for canvas blocks (read-only → editable on click)
        textView.onTapWhileReadOnly = isEditable ? nil : { [weak coordinator = context.coordinator] in
            coordinator?.parent.onActivate?()
        }
        textView.onBecomeFirstResponder = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onActivate?()
            // Entering a row (a click into a suspicious gap) verifies it.
            coordinator?.scheduleIntrinsicHeightReconcile()
        }
        textView.onNativeMouseDown = { [weak coordinator = context.coordinator] in
            // Dismiss chrome and continue the ORIGINAL native event. An
            // invisible SwiftUI tap layer used to eat this caret click.
            coordinator?.dismissMenus()
        }
        textView.onResignFirstResponder = { [weak coordinator = context.coordinator] in
            // Leaving a row is the moment a stale height would be left
            // behind (Return/arrow/click away) — verify it on the way out.
            coordinator?.scheduleIntrinsicHeightReconcile()
            // Flush the deferred attributedText sync BEFORE firing onDeactivate.
            // syncBindings() debounces attributedText writes by 50ms — if the user
            // blurs before the deferred sync fires, flushPendingSync reads a stale
            // attributedText and the final keystrokes are lost.
            // Skipped while awaiting external content: after a split/merge the
            // text view is the stale side, and flushing it here would write
            // pre-split text back over the rebuilt block (duplication bug).
            // Also skipped when the view is CLEAN (no edits since the last
            // sync): the flush is only there to rescue keystrokes inside the
            // 50ms deferral window, and running it on every blur re-parsed
            // untouched rows synchronously inside mouseDown.
            if let coordinator, let tv = coordinator.textViewReference,
               !coordinator.awaitingExternalContent,
               coordinator.viewContentDirty {
                coordinator.deferredSyncWorkItem?.cancel()
                let flushed = viewContentSnapshot(tv)
                coordinator.parent.attributedText = flushed
                // Binding now mirrors the view — no compare/replace needed.
                coordinator.lastReconciledBindingText = flushed
                coordinator.isUpdatingFromTextView = false
                coordinator.viewContentDirty = false
                // Box-backed binding: no onChange fires — parse the flush.
                coordinator.parent.onContentCommitted?()
            }
            coordinator?.parent.onDeactivate?()
        }
        textView.scrollsInternally = scrollsInternally
        textView.blockRowMode = splitsOnReturn
        textView.tableCellMode = tableCellMode
        textView.tableContextMenu = tableContextMenu
        textView.onTableCellPaste = { [weak coordinator = context.coordinator] imported in
            guard let coordinator, let textView = coordinator.textViewReference else { return false }
            return coordinator.performTableCellPaste(imported, in: textView)
        }
        textView.blockDragSelectionController = splitsOnReturn ? dragSelectionController : nil
        textView.rowBlockID = rowBlockID
        // Hit-test gates: these are in EditorConfigSignature, so a kind or
        // collapsibility change re-runs this config and reaches the view.
        textView.rowBlockKind = rowBlockKind
        textView.rowHeadingIsCollapsible = rowHeadingIsCollapsible
        textView.onBlockPaste = { [weak coordinator = context.coordinator] pastedText in
            guard let coordinator, let textView = coordinator.textViewReference else { return false }
            return coordinator.performBlockPaste(pastedText, in: textView)
        }
        textView.onStructuredBlockPaste = { [weak coordinator = context.coordinator] data in
            guard let coordinator, let textView = coordinator.textViewReference else { return false }
            return coordinator.performStructuredBlockPaste(data, in: textView)
        }
        textView.rendersElementChrome = rendersElementChrome
        textView.elementBlockDarkMode = darkMode
        textView.elementBlockBaseFontSize = fontSize
        textView.headingDisclosureColor = headingDisclosureColor
        textView.window?.acceptsMouseMovedEvents = true
        textView.onToggleElementCollapse = { [weak coordinator = context.coordinator] instanceID in
            guard let coordinator, let textView = coordinator.textViewReference else { return }
            coordinator.toggleElementCollapse(instanceID: instanceID, in: textView)
        }
        textView.onToggleHeadingCollapse = { [weak coordinator = context.coordinator] range in
            guard let coordinator, let textView = coordinator.textViewReference else { return }
            coordinator.toggleHeadingCollapse(headingRange: range, in: textView)
        }
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.importsGraphics = allowImages
        textView.allowsImageEditing = allowImages
        textView.drawsBackground = false

        // Only set font/textColor/alignment on initial setup.
        // Setting these on every update overwrites the entire text storage,
        // destroying any rich text formatting (bold, italic, etc.).
        if isInitial {
            textView.font = overrideFont ?? resolvedBaseFont()
            textView.textColor = resolvedEditorTextColor
            textView.alignment = textAlignment
            textView.defaultParagraphStyle = baseParagraphStyle()
            textView.typingAttributes = defaultTypingAttributes()
        }

        textView.backgroundColor = .clear
        textView.insertionPointColor = EditorCaretPalette.insertionPoint(darkMode: darkMode)
        textView.selectedTextAttributes = [
            .backgroundColor: EditorCaretPalette.selectionBackground(darkMode: darkMode)
        ]
        textView.onToggleChecklistItem = { [weak coordinator = context.coordinator] lineStart in
            guard let coordinator, let textView = coordinator.textViewReference else { return }
            coordinator.toggleChecklistItem(atLineStart: lineStart, in: textView)
        }
        textView.onImageResizePreset = { [weak coordinator = context.coordinator] charIndex, width in
            guard let coordinator, let textView = coordinator.textViewReference else { return }
            coordinator.commitImageResize(width: width, at: charIndex, in: textView)
        }
        textView.textContainerInset = resolvedTextInsets()
        textView.textContainer?.lineFragmentPadding = 0
        let isTitleMode = titleConfiguration != nil
        textView.isVerticallyResizable = !singleLine || isTitleMode
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: singleLine ? resolvedSingleLineHeight() : CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = NSSize(
            width: 0,
            height: singleLine ? resolvedSingleLineHeight() : (isTitleMode ? resolvedTitleMinimumHeight() : 0)
        )
        // For multi-line mode, preserve the current container width (tracked from the text view)
        // so word-wrapping works correctly. Only override height.
        let currentContainerWidth = textView.textContainer?.containerSize.width ?? textView.frame.width
        let containerWidth = singleLine ? CGFloat.greatestFiniteMagnitude : max(1, currentContainerWidth)
        textView.textContainer?.containerSize = NSSize(
            width: containerWidth,
            height: singleLine ? resolvedSingleLineHeight() : CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.maximumNumberOfLines = singleLine ? 1 : 0
        textView.textContainer?.lineBreakMode = singleLine ? .byClipping : .byWordWrapping

        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isAutomaticTextCompletionEnabled = true
        textView.isAutomaticLinkDetectionEnabled = true

        textView.delegate = context.coordinator
        textView.shortcutDelegate = context.coordinator
        textView.window?.invalidateCursorRects(for: textView)
    }

    private func baseParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        if singleLine || titleConfiguration != nil {
            style.lineSpacing = 0
            style.paragraphSpacing = 0
        } else if compact {
            style.lineSpacing = max(0, 4 + lineSpacingAdjustment)
            style.paragraphSpacing = 8
        } else {
            style.lineSpacing = max(0, 6 + lineSpacingAdjustment)
            style.paragraphSpacing = 12
        }
        return style
    }

    private func defaultTypingAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: overrideFont ?? resolvedBaseFont(),
            .foregroundColor: resolvedEditorTextColor,
            .paragraphStyle: baseParagraphStyle()
        ]
    }

    /// Empty block rows have no attributed run for typing to inherit — seed
    /// the typing attributes for the row's kind so the first character is
    /// styled correctly AND round-trips through the serializer with the
    /// right kind (an empty heading typed with plain attributes parses back
    /// as a paragraph). GUARD-TWIN: this is the FOURTH copy of the heading
    /// ladder — RichDocumentSerializer.blockFont, applyHeading (below), and
    /// BlockStaticRowPlaceholder.editorFont must all change together.
    func seedTypingAttributesForEmptyRow(in textView: CosmoTextView) {
        guard let level = rowBlockKind?.headingLevelInt else {
            textView.typingAttributes = defaultTypingAttributes()
            return
        }
        let size: CGFloat
        let weight: NSFont.Weight
        switch level {
        case 1:
            size = min(34, (fontSize * 1.85).rounded())
            weight = .semibold
        case 2:
            size = (fontSize * 1.45).rounded()
            weight = .semibold
        default:
            size = (fontSize * 1.20).rounded()
            weight = .medium
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 12
        // Only collapsible headings reserve the chevron gutter.
        let headingGutter: CGFloat = rowHeadingIsCollapsible ? 34 : 0
        paragraph.firstLineHeadIndent = headingGutter
        paragraph.headIndent = headingGutter
        textView.typingAttributes = [
            .font: EditorFontPolicy.font(ofSize: size, weight: weight, design: fontDesign),
            .foregroundColor: resolvedEditorTextColor,
            RichDocumentAttributeKeys.headingLevel: level,
            RichDocumentAttributeKeys.headingCollapsible: NSNumber(value: rowHeadingIsCollapsible),
            .paragraphStyle: paragraph
        ]
    }

    /// Post-processes the text storage to force overrideTextColor and overrideFont
    /// across all ranges. The RichDocument serializer bakes theme colors into the
    /// attributed string, so passing overrideTextColor to the text view is not
    /// enough — stored per-character attributes win. This reapplies the overrides
    /// after each setAttributedString call. Diff-aware: a storage that already
    /// carries the overrides is left untouched (see EditorStorageOverridePass).
    func applyStorageOverrides(_ storage: NSTextStorage?) {
        guard let storage else { return }
        EditorStorageOverridePass.apply(
            to: storage,
            overrideTextColor: overrideTextColor,
            overrideFont: overrideFont,
            appliesHeadingIndents: !singleLine && titleConfiguration == nil
        )
    }

    /// The stored ☐/☑ checklist characters must never ink — the visible
    /// circle checkbox is painted over their rect by drawChecklistCheckboxes.
    /// Any pass that stamps foregroundColor across whole lines (ink
    /// overrides, block-toggle attribute resets) re-inks the glyph and the
    /// raw ballot-box character bleeds through under the painted circle, so
    /// every such pass must route back through here.
    static func reclearChecklistGlyphs(in storage: NSTextStorage, range: NSRange? = nil) {
        for glyphRange in EditorStorageOverridePass.checklistGlyphReclearRanges(in: storage, range: range) {
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: glyphRange)
        }
    }

    private func resolvedBaseFont() -> NSFont {
        EditorFontPolicy.font(ofSize: fontSize, weight: baseFontWeight, design: fontDesign)
    }

    private func resolvedTextInsets() -> NSSize {
        if splitsOnReturn { return .zero }
        return EditorTextInsetPolicy.textContainerInset(
            scrollsInternally: scrollsInternally,
            singleLine: singleLine,
            isTitleMode: titleConfiguration != nil,
            compact: compact,
            fontSize: fontSize
        )
    }

    private func resolvedSingleLineHeight() -> CGFloat {
        EditorLayoutMetrics.singleLineHeight(
            fontSize: fontSize,
            compact: compact,
            baseFontWeight: baseFontWeight
        )
    }

    private func resolvedTitleMinimumHeight() -> CGFloat {
        EditorLayoutMetrics.titleHeight(
            fontSize: fontSize,
            compact: compact,
            baseFontWeight: baseFontWeight,
            lineCount: 1
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, CosmoTextViewShortcutDelegate {
        var parent: TextKitEditorRepresentable

        weak var textViewReference: CosmoTextView?

        private weak var scrollContentView: NSClipView?
        private weak var observedScrollView: NSScrollView?
        private var mentionStartIndex: Int?
        /// UTF-16 offset of the "/" that opened the slash menu. Tracked like
        /// mentionStartIndex so the query filters live and the trigger can be
        /// removed by exact range on commit (never by guessing at the last "/").
        private var slashStartIndex: Int? {
            didSet {
                // The anchor is a function of the "/" position — any session
                // change (open, close, re-open elsewhere) invalidates it.
                if slashStartIndex != oldValue { slashSessionAnchor = nil }
            }
        }
        /// Cached menu anchor for the live slash session. `firstRect(for:)`
        /// forces TextKit layout plus a screen-coordinate round trip, and the
        /// "/" never moves while the session is open — computing it per query
        /// keystroke was pure waste. Row-local coordinates, so scrolling
        /// can't stale it (the publisher re-adds the row's frame each time).
        private var slashSessionAnchor: CGPoint?
        private var isInHeadingMode = false

        private enum ActiveBlockMode {
            case none
            case quote
            case bulletList
            case numberedList
            case checklist
        }
        private var activeBlockMode: ActiveBlockMode = .none
        private var hasAppliedHighlights = false
        /// Guards against updateNSView round-trip when change originated from user typing
        var isUpdatingFromTextView = false
        /// Whether the text view holds edits that have not yet reached the
        /// attributedText binding. Gates the resign-first-responder flush:
        /// clicking OUT of an untouched row used to write the storage back
        /// anyway (storage carries override stamps, so it never compares
        /// equal), re-parsing the row synchronously inside mouseDown.
        var viewContentDirty = false
        /// Guards against delegate callbacks writing bindings during SwiftUI's layout pass
        var isUpdatingFromSwiftUI = false
        /// Guards structural edits that call didChangeText only for TextKit/undo
        /// bookkeeping; bindings are synced once through syncStructuralEditBindings.
        private var isApplyingStructuralEdit = false
        /// Deferred attributedText sync — 50ms debounce for performance.
        /// Must be cancellable from resignFirstResponder to flush final state.
        var deferredSyncWorkItem: DispatchWorkItem?
        /// Last externalContentToken whose content this view has applied —
        /// a mismatch forces application even while first responder.
        var lastAppliedContentToken = 0
        /// True after a handled boundary command (split/merge/delete) rebuilt
        /// this row's content in the document — the text view is stale until
        /// updateNSView applies the fresh content or the user edits again.
        /// While set, stale write-backs (resign-flush, deferred attributedText
        /// sync) are suppressed so they can't resurrect pre-edit text.
        var awaitingExternalContent = false
        /// Last consumed one-shot caret request token.
        var lastAppliedCaretToken = 0
        /// updateNSView fast-path caches — see EditorConfigSignature /
        /// StorageOverrideSignature. A long block list re-runs updateNSView
        /// for every row on focus changes and structural edits; these keep
        /// each of those calls near-free when nothing relevant changed.
        var lastConfigSignature: TextKitEditorRepresentable.EditorConfigSignature?
        var lastStorageOverrideSignature: TextKitEditorRepresentable.StorageOverrideSignature?
        /// The last binding NSAttributedString reconciled with the view's
        /// storage (applied to it, or produced from it). Same instance ⇒
        /// nothing to compare or replace. Held strongly (it is the instance
        /// the binding already retains) so a recycled allocation can never
        /// masquerade as the reconciled one.
        var lastReconciledBindingText: NSAttributedString?
        /// Whether a focus-band dim is currently painted — lets applyFocusBand
        /// skip its full-range temporary-attribute clear when there is
        /// provably nothing to clear.
        var hasAppliedFocusBand = false
        /// The active range last painted by applyFocusBand — an unchanged band
        /// must not be cleared + restamped (full-document display invalidation)
        /// on every selection change.
        var lastAppliedFocusBandRange: NSRange?
        /// Content applied at makeNSView before the binding was populated —
        /// consumed by the first binding reconcile (see updateNSView).
        var mountSeedContent: NSAttributedString?
        private weak var lastConfiguredWindow: NSWindow?
        private var lastReportedHeight: CGFloat = 0
        private var lastObservedFrameWidth: CGFloat = 0
        /// One pending row-height reconcile at a time (see
        /// `scheduleIntrinsicHeightReconcile`).
        private var rowHeightReconcileScheduled = false
        private var lastNavigationTargetID: UUID?
        private var selectionChangeWorkItem: DispatchWorkItem?
        /// Grace period after opening a menu — ignores auto-scroll dismiss
        private var menuOpenedAt: CFAbsoluteTime = 0

        private struct AncestorScrollSnapshot {
            let scrollView: NSScrollView
            let origin: NSPoint
        }

        init(_ parent: TextKitEditorRepresentable) {
            self.parent = parent
            super.init()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAppWillResignActive(_:)),
                name: NSApplication.willResignActiveNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleInsertMentionInEditor(_:)),
                name: .insertMentionInEditor,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handlePerformMentionSelection(_:)),
                name: .performMentionSelection,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleInsertTextInEditor(_:)),
                name: .insertTextInEditor,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleReplaceSelectionInEditor(_:)),
                name: .replaceSelectionInEditor,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleSetTypingAttributes(_:)),
                name: .setEditorTypingAttributes,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handlePerformSlashCommand(_:)),
                name: .performSlashCommand,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleToggleFormatting(_:)),
                name: .toggleEditorFormatting,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleApplyInlineStyle(_:)),
                name: .applyEditorInlineStyle,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func installScrollDismissObserver(for scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollContentView = scrollView.contentView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleEditorScroll(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        func installFrameChangeObserver(for scrollView: NSScrollView) {
            scrollView.postsFrameChangedNotifications = true
            observedScrollView = scrollView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleFrameChange(_:)),
                name: NSView.frameDidChangeNotification,
                object: scrollView
            )
            // SwiftUI re-seats a row by moving its platform-view HOST, not
            // the scroll view (whose frame stays at the host's origin) — so
            // the scroll view never hears about a re-seat. Observe the host
            // once it exists; the watchdog uses re-seats as free
            // verification points for rows below an edit.
            if let cosmoScrollView = scrollView as? CosmoScrollView {
                cosmoScrollView.onDidMoveToSuperview = { [weak self, weak cosmoScrollView] in
                    guard let self, let cosmoScrollView else { return }
                    self.observeHostFrame(of: cosmoScrollView)
                }
                observeHostFrame(of: cosmoScrollView)
            }
        }

        private weak var observedHostView: NSView?

        private func observeHostFrame(of scrollView: CosmoScrollView) {
            guard let host = scrollView.superview, host !== observedHostView else { return }
            if let previous = observedHostView {
                NotificationCenter.default.removeObserver(
                    self, name: NSView.frameDidChangeNotification, object: previous
                )
            }
            observedHostView = host
            host.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleHostFrameChange(_:)),
                name: NSView.frameDidChangeNotification,
                object: host
            )
        }

        /// The row was re-seated by SwiftUI (a row above changed height).
        /// Two float compares: if the frame SwiftUI is showing disagrees
        /// with the height we asked for, an invalidation was dropped — heal
        /// it outside the layout pass.
        @objc private func handleHostFrameChange(_ notification: Notification) {
            guard let scrollView = observedScrollView as? CosmoScrollView,
                  let intrinsicHeight = scrollView.intrinsicHeight,
                  abs(scrollView.frame.height - intrinsicHeight) > 1.0 else { return }
            scheduleIntrinsicHeightReconcile()
        }

        @objc private func handleFrameChange(_ notification: Notification) {
            guard let textView = textViewReference,
                  let scrollView = notification.object as? NSScrollView else { return }
            let newWidth = scrollView.frame.width
            guard abs(newWidth - lastObservedFrameWidth) > 0.5 else {
                // Origin/height-only change (a row above grew, SwiftUI
                // re-seated this one). Cheap watchdog: if the frame SwiftUI
                // just gave us disagrees with the height we asked for, an
                // invalidation was dropped somewhere — heal it outside the
                // pass. Two float compares; no layout work on the hot path.
                if let cosmoScrollView = scrollView as? CosmoScrollView,
                   let intrinsicHeight = cosmoScrollView.intrinsicHeight,
                   abs(cosmoScrollView.frame.height - intrinsicHeight) > 1.0 {
                    scheduleIntrinsicHeightReconcile()
                }
                return
            }
            lastObservedFrameWidth = newWidth
            notifyContentHeightChange(for: textView)
            repositionImageResizeOverlay()
            scheduleIntrinsicHeightReconcile()
        }

        /// The row-height watchdog. A block row's SwiftUI height is the
        /// `CosmoScrollView.intrinsicHeight` cache, and several paths can
        /// leave it stale or leave SwiftUI holding a frame that never caught
        /// up to it — the user-facing "massive gap" under a block:
        ///
        /// - Frame-change notifications fire synchronously while SwiftUI is
        ///   mid-layout, so the `invalidateIntrinsicContentSize` inside
        ///   `notifyContentHeightChange` can land inside the very pass that
        ///   is consuming the OLD height, and SwiftUI sometimes drops it (a
        ///   freshly split row seeded paragraph-tall at ~1pt width, then
        ///   never re-laid out).
        /// - The per-keystroke immediate resize deliberately refuses shrinks
        ///   (jitter guard) and hands genuine shrinks to the deferred settle —
        ///   which bails without measuring while `awaitingExternalContent`
        ///   is armed. A Return at the END of a row leaves that row's block
        ///   value-identical, so no external content ever re-measures it.
        /// - The markdown-alias and hard-newline branches of `textDidChange`
        ///   return before the usual sync.
        ///
        /// Rather than patching each path, every content or geometry change
        /// schedules ONE coalesced async re-measure at the row's real width;
        /// it re-applies the intrinsic height and, if the hosting frame still
        /// disagrees, re-issues the invalidation outside any layout pass.
        /// Idempotent and tolerance-guarded, so a correct row costs one
        /// `usedRect` read. Never remove; any future "row keeps a stale
        /// height" report should first check that its path reaches this.
        func scheduleIntrinsicHeightReconcile() {
            guard !parent.scrollsInternally else { return }
            guard !rowHeightReconcileScheduled else { return }
            rowHeightReconcileScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.rowHeightReconcileScheduled = false
                self.reconcileRowHeightNow()
            }
        }

        private func reconcileRowHeightNow() {
            guard let textView = textViewReference,
                  let scrollView = textView.enclosingScrollView as? CosmoScrollView else { return }
            // Unmeasured mount (zero-width scroll view): the provisional
            // one-line seed stands until the real width arrives and
            // `handleFrameChange` reconciles at that width.
            guard scrollView.contentSize.width > 2 else { return }
            notifyContentHeightChange(for: textView)
            guard let intrinsicHeight = scrollView.intrinsicHeight,
                  abs(scrollView.frame.height - intrinsicHeight) > 1.0 else { return }
            scrollView.invalidateIntrinsicContentSize()
        }

        // MARK: - Image resize overlay (content editor)

        private var imageResizeOverlay: ImageResizeOverlayView?

        /// Show & position the resize overlay when exactly one inline image attachment is
        /// selected; hide it otherwise. Cheap enough to call on every selection change.
        func updateImageResizeOverlay(in textView: CosmoTextView) {
            guard textView.isEditable, let storage = textView.textStorage else {
                removeImageResizeOverlay()
                return
            }
            let selection = textView.selectedRange()
            guard selection.length == 1, selection.location < storage.length else {
                removeImageResizeOverlay()
                return
            }
            let attributes = storage.attributes(at: selection.location, effectiveRange: nil)
            guard let attachment = attributes[.attachment] as? NSTextAttachment,
                  attributes[RichDocumentAttributeKeys.imagePath] != nil else {
                removeImageResizeOverlay()
                return
            }

            let imageSize = attachment.image?.size ?? attachment.bounds.size
            let intrinsic = (imageSize.width > 0 && imageSize.height > 0) ? imageSize : CGSize(width: 1, height: 1)
            let maxWidth = max(ImageResizeMath.minWidth, textView.bounds.width - 2 * textView.textContainerInset.width)

            let overlay = imageResizeOverlay ?? makeImageResizeOverlay(in: textView)
            overlay.charIndex = selection.location
            overlay.intrinsic = intrinsic
            overlay.maxWidth = maxWidth
            if overlay.superview !== textView { textView.addSubview(overlay) }
            if !overlay.repositionToAttachment() { removeImageResizeOverlay() }
        }

        func repositionImageResizeOverlay() {
            guard let overlay = imageResizeOverlay else { return }
            if !overlay.repositionToAttachment() { removeImageResizeOverlay() }
        }

        func removeImageResizeOverlay() {
            imageResizeOverlay?.removeFromSuperview()
            imageResizeOverlay = nil
        }

        private func makeImageResizeOverlay(in textView: CosmoTextView) -> ImageResizeOverlayView {
            let overlay = ImageResizeOverlayView(frame: .zero)
            overlay.textView = textView
            overlay.onCommit = { [weak self, weak textView] width in
                guard let self, let textView, let charIndex = self.imageResizeOverlay?.charIndex else { return }
                self.commitImageResize(width: width, at: charIndex, in: textView)
            }
            imageResizeOverlay = overlay
            return overlay
        }

        /// Persist a resized image's display width by stamping the attribute the serializer
        /// reads (or removing it for a reset), updating the attachment bounds, then flushing
        /// through the normal binding sync so it lands in the document model.
        func commitImageResize(width: CGFloat?, at charIndex: Int, in textView: CosmoTextView) {
            guard let storage = textView.textStorage, charIndex < storage.length else { return }
            let range = NSRange(location: charIndex, length: 1)
            let attachment = storage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? NSTextAttachment
            let intrinsic = attachment?.image?.size ?? CGSize(width: 1, height: 1)

            if let width {
                storage.addAttribute(RichDocumentAttributeKeys.imageDisplayWidth, value: NSNumber(value: Double(width)), range: range)
                let aspect = ImageResizeMath.aspectRatio(intrinsic: intrinsic)
                attachment?.bounds = CGRect(x: 0, y: 0, width: width, height: (width / aspect).rounded())
            } else {
                storage.removeAttribute(RichDocumentAttributeKeys.imageDisplayWidth, range: range)
                attachment?.bounds = CGRect(origin: .zero, size: ImageResizeMath.resolvedSize(displayWidth: nil, intrinsic: intrinsic, maxWidth: 680))
            }

            textView.layoutManager?.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
            if let container = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: container)
            }
            textView.window?.invalidateCursorRects(for: textView)
            syncBindings(from: textView)
            updateImageResizeOverlay(in: textView)
        }

        /// `force` — the storage was just replaced, so painted backgrounds are
        /// gone and must restamp even when the analysis is unchanged. Ordinary
        /// re-renders with the same analysis touch nothing (each stamp dirties
        /// the storage and invalidates the full document's display).
        func applyPolishHighlights(to textView: NSTextView, force: Bool = false) {
            guard let storage = textView.textStorage else { return }

            guard let analysis = parent.polishHighlights else {
                lastAppliedPolishSignature = nil
                guard hasAppliedHighlights else { return }
                storage.beginEditing()
                storage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: storage.length))
                storage.endEditing()
                hasAppliedHighlights = false
                return
            }

            let signature = PolishHighlightSignature(analysis)
            if !force, hasAppliedHighlights, signature == lastAppliedPolishSignature {
                return
            }

            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.removeAttribute(.backgroundColor, range: fullRange)

            for range in analysis.complexSentenceRanges where NSMaxRange(range) <= storage.length {
                storage.addAttribute(.backgroundColor, value: PolishHighlightColors.complex, range: range)
            }
            for range in analysis.veryComplexSentenceRanges where NSMaxRange(range) <= storage.length {
                storage.addAttribute(.backgroundColor, value: PolishHighlightColors.veryComplex, range: range)
            }
            for range in analysis.passiveVoiceRanges where NSMaxRange(range) <= storage.length {
                storage.addAttribute(.backgroundColor, value: PolishHighlightColors.passive, range: range)
            }
            for range in analysis.adverbRanges where NSMaxRange(range) <= storage.length {
                storage.addAttribute(.backgroundColor, value: PolishHighlightColors.adverb, range: range)
            }

            storage.endEditing()
            hasAppliedHighlights = true
            lastAppliedPolishSignature = signature
        }

        /// An out-of-band buffer swap (structural rebuild) wiped painted
        /// temporary attributes and highlight backgrounds — the change-gates
        /// must not believe the paint is still there.
        func noteStorageWasReplacedOutOfBand() {
            hasAppliedFocusBand = false
            lastAppliedFocusBandRange = nil
            hasAppliedHighlights = false
            lastAppliedPolishSignature = nil
        }

        /// The range payload of the last analysis painted — the identity that
        /// decides whether a polish re-stamp is actually needed.
        private struct PolishHighlightSignature: Equatable {
            let complex: [NSRange]
            let veryComplex: [NSRange]
            let passive: [NSRange]
            let adverbs: [NSRange]

            init(_ analysis: WritingAnalysis) {
                complex = analysis.complexSentenceRanges
                veryComplex = analysis.veryComplexSentenceRanges
                passive = analysis.passiveVoiceRanges
                adverbs = analysis.adverbRanges
            }
        }
        private var lastAppliedPolishSignature: PolishHighlightSignature?

        /// Window-scoped config must land after the view joins a window —
        /// makeNSView runs before attachment, and config passes are now
        /// signature-gated so they no longer re-run on every update.
        func attachWindowConfigIfNeeded(for textView: NSTextView) {
            guard let window = textView.window, window !== lastConfiguredWindow else { return }
            lastConfiguredWindow = window
            window.acceptsMouseMovedEvents = true
            window.invalidateCursorRects(for: textView)
        }

        /// `force` — a content edit landed, so a painted band must restamp
        /// even when its range happens to match (positions shifted under it).
        /// Selection changes and plain updateNSView passes call without force:
        /// an unchanged band (or none at all — band mode off) touches nothing,
        /// because the full-range temporary-attribute clear invalidates the
        /// entire document's display and was the engine behind the manuscript
        /// blinking/blanking on every click.
        func applyFocusBand(to textView: NSTextView, force: Bool = false) {
            // No band requested and none painted — skip the full-range
            // temporary-attribute clear (it is O(content) and invalidates
            // display for every row on every update in a block list).
            if parent.focusBandRangeProvider == nil,
               parent.focusBandRange == nil,
               !hasAppliedFocusBand {
                return
            }
            guard let layoutManager = textView.layoutManager else { return }
            let fullRange = NSRange(location: 0, length: textView.string.utf16.count)
            guard fullRange.length > 0 else { return }

            let requestedRange: NSRange?
            if let provider = parent.focusBandRangeProvider {
                requestedRange = provider(textView.string, textView.selectedRange())
            } else {
                requestedRange = parent.focusBandRange
            }

            switch FocusBandPlanner.plan(
                requested: requestedRange,
                fullLength: fullRange.length,
                lastApplied: lastAppliedFocusBandRange,
                hasApplied: hasAppliedFocusBand,
                force: force
            ) {
            case .none:
                return
            case .clear:
                layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
                hasAppliedFocusBand = false
                lastAppliedFocusBandRange = nil
            case .apply(let activeRange):
                layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
                // The dim derives from the ACTIVE text color so it stays
                // legible on both paper and the immersive dark scriptorium —
                // DS.documentTextMuted is paper ink and rendered the dimmed
                // text invisible on the dark surface.
                let activeColor = parent.resolvedEditorTextColor
                let mutedColor = activeColor.withAlphaComponent(0.35)
                layoutManager.addTemporaryAttribute(.foregroundColor, value: mutedColor, forCharacterRange: fullRange)
                layoutManager.addTemporaryAttribute(.foregroundColor, value: activeColor, forCharacterRange: activeRange)
                hasAppliedFocusBand = true
                lastAppliedFocusBandRange = activeRange
            }
        }

        func navigateIfNeeded(to headingID: UUID?, in textView: CosmoTextView) {
            guard headingID != lastNavigationTargetID else { return }
            lastNavigationTargetID = headingID
            guard let headingID,
                  let headingRange = headingRange(for: headingID, in: textView) else {
                return
            }

            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: headingRange.location, length: 0))
            scrollRangeIntoAncestorViewport(headingRange, in: textView)
            textView.showFindIndicator(for: headingRange)
        }

        // MARK: - Shortcut Delegate

        func textViewDidRequestFormattingShortcut(_ shortcut: FormattingType) {
            guard let textView = textViewReference else { return }
            applyFormatting(shortcut, to: textView)
        }

        func textViewDidRequestBlockShortcut(_ shortcut: BlockKeyboardShortcut) -> Bool {
            // Block rows only — the continuous editors keep native behavior.
            guard parent.splitsOnReturn, let textView = textViewReference else { return false }
            beginAwaitingExternalContent()
            if parent.onBoundaryCommand?(.blockShortcut(shortcut, livePlainText: textView.string)) == true {
                return true
            }
            cancelAwaitingExternalContent()
            return false
        }

        func textView(_ textView: NSTextView, shouldHandleImagePaste pasteboard: NSPasteboard) -> Bool {
            guard parent.allowImages else { return false }

            // Image files first (Finder drops, copied files): keep the original
            // data and filename instead of a lossy NSImage → PNG round-trip.
            let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [
                .urlReadingFileURLsOnly: true,
                .urlReadingContentsConformToTypes: [UTType.image.identifier]
            ]
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [URL],
               !urls.isEmpty {
                var inserted = false
                for url in urls {
                    guard let data = try? Data(contentsOf: url) else { continue }
                    insertImage(data: data, filename: url.lastPathComponent, into: textView)
                    inserted = true
                }
                if inserted { return true }
            }

            if let image = NSImage(pasteboard: pasteboard),
               let data = image.pngData() ?? image.tiffRepresentation {
                insertImage(data: data, filename: "Pasted Image.png", into: textView)
                return true
            }

            return false
        }

        // MARK: - Delegate

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? CosmoTextView else { return }
            // Skip when triggered by setAttributedString inside updateNSView —
            // writing bindings here would cause "Modifying state during view update".
            guard !isUpdatingFromSwiftUI else {
                return
            }
            guard !isApplyingStructuralEdit else {
                return
            }
            guard !textView.hasMarkedText() else {
                // No markdown transform, hard-newline split, or model echo
                // may replace the input method's in-progress composition.
                // An earlier ordinary keystroke may already have queued a
                // snapshot of this live buffer; that job must wait too.
                deferredSyncWorkItem?.cancel()
                deferredSyncWorkItem = nil
                isUpdatingFromTextView = false
                viewContentDirty = true
                notifyContentHeightChange(for: textView)
                return
            }

            // Containment: a hard newline reached a block row anyway
            // (dictation, IME commit, RTF paste). Splice it into real blocks
            // SYNCHRONOUSLY — before the deferred sync can round-trip the
            // multi-line content through the document and re-splice it on the
            // next keystroke (the paste-duplication bug). While a rebuild is
            // already in flight the view is the stale side: swallow instead
            // of clearing the suppression flag below.
            if parent.splitsOnReturn, textView.string.containsHardNewline {
                if awaitingExternalContent { return }
                containHardNewlines(in: textView)
                scheduleIntrinsicHeightReconcile()
                return
            }

            // Table cells hold one paragraph: a hard newline that slipped in
            // (dictation, IME) becomes a soft break in place.
            if parent.tableCellMode, textView.string.containsHardNewline, let storage = textView.textStorage {
                let selection = textView.selectedRange()
                storage.beginEditing()
                storage.mutableString.replaceOccurrences(of: "\r\n", with: "\u{2028}", range: NSRange(location: 0, length: storage.length))
                storage.mutableString.replaceOccurrences(of: "\n", with: "\u{2028}", range: NSRange(location: 0, length: storage.length))
                storage.mutableString.replaceOccurrences(of: "\r", with: "\u{2028}", range: NSRange(location: 0, length: storage.length))
                storage.endEditing()
                let safeLocation = min(selection.location, storage.length)
                textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
            }

            // Live markdown aliases: "# ", "- ", "> ", "[] ", "1. ", "---"
            // completed at the start of a paragraph row convert the block.
            if parent.splitsOnReturn, applyMarkdownAliasIfNeeded(in: textView) {
                scheduleIntrinsicHeightReconcile()
                return
            }

            // A real edit landed in the text view — it's authoritative again.
            awaitingExternalContent = false

            normalizeSingleLineViewport(for: textView)
            syncBindings(from: textView)
            // Content edit: band positions shifted — restamp even if the
            // provider resolves to the same range values.
            applyFocusBand(to: textView, force: true)

            let text = textView.string
            let cursorLocation = textView.selectedRange().location

            handleMentionState(in: textView, text: text, cursorLocation: cursorLocation)
            handleSlashState(in: textView, text: text, cursorLocation: cursorLocation)

            // Scroll behavior — only when editor owns its own scroll (scrollsInternally)
            // Skip when embedded inside a SwiftUI ScrollView (the default for focus modes)
            if parent.scrollsInternally {
                if parent.typewriterMode {
                    scrollToCursorCenter(textView)
                } else {
                    ensureScrollMargin(textView)
                }
            } else if parent.typewriterMode {
                scheduleAncestorTypewriterScroll(for: textView)
            } else {
                scheduleAncestorComfortScroll(for: textView)
            }
        }

        // MARK: - Typewriter Scrolling

        /// Keep cursor vertically centered — text scrolls around it
        private func scrollToCursorCenter(_ textView: NSTextView) {
            guard !parent.singleLine,
                  !textView.string.isEmpty,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  let scrollView = textView.enclosingScrollView else { return }

            let cursorRange = textView.selectedRange()
            let glyphRange = layoutManager.glyphRange(forCharacterRange: cursorRange, actualCharacterRange: nil)
            let cursorRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let cursorY = cursorRect.midY + textView.textContainerInset.height

            let visibleHeight = scrollView.contentView.bounds.height
            // Don't center-scroll if document is shorter than viewport
            let documentHeight = layoutManager.usedRect(for: textContainer).height + textView.textContainerInset.height * 2
            guard documentHeight > visibleHeight else { return }

            let targetY = max(0, cursorY - visibleHeight / 2)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: targetY))
            }
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func shouldUseAncestorTypewriterScroll(for textView: NSTextView) -> Bool {
            guard parent.typewriterMode,
                  !parent.scrollsInternally,
                  !parent.singleLine else {
                return false
            }
            return textView.nearestAncestorScrollView(excluding: textView.enclosingScrollView) != nil
        }

        private func scheduleAncestorTypewriterScroll(for textView: NSTextView) {
            guard shouldUseAncestorTypewriterScroll(for: textView) else { return }

            let selectedRange = textView.selectedRange()

            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.scrollCursorToAncestorTypewriterBand(textView, selectedRange: selectedRange)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.scrollCursorToAncestorTypewriterBand(textView, selectedRange: selectedRange)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.scrollCursorToAncestorTypewriterBand(textView, selectedRange: selectedRange)
            }
        }

        private func scrollCursorToAncestorTypewriterBand(_ textView: NSTextView, selectedRange: NSRange) {
            guard shouldUseAncestorTypewriterScroll(for: textView),
                  let ancestorScrollView = textView.nearestAncestorScrollView(excluding: textView.enclosingScrollView),
                  let documentView = ancestorScrollView.documentView,
                  let cursorRect = cursorRectInAncestorDocument(
                    for: textView,
                    selectedRange: selectedRange,
                    ancestorScrollView: ancestorScrollView
                  ) else {
                return
            }

            let visibleRect = ancestorScrollView.documentVisibleRect
            let visibleHeight = max(visibleRect.height, 1)
            let targetY = visibleRect.minY + visibleHeight * 0.44
            let delta = cursorRect.midY - targetY
            guard abs(delta) > 10 else { return }

            let documentHeight = max(documentView.bounds.height, visibleHeight)
            let maxY = max(0, documentHeight - visibleHeight)
            let targetOriginY = min(max(0, visibleRect.minY + delta), maxY)
            guard abs(targetOriginY - visibleRect.minY) > 0.5 else { return }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ancestorScrollView.contentView.animator().setBoundsOrigin(
                    NSPoint(x: visibleRect.minX, y: targetOriginY)
                )
            }
            ancestorScrollView.reflectScrolledClipView(ancestorScrollView.contentView)
        }

        // MARK: - Comfort Band (soft scrolloff)

        /// Typewriter mode's gentler sibling, always on while typing: keeps
        /// the caret out of the bottom quarter of the viewport (Vim's
        /// scrolloff model) so eyes never chase the screen edge. It only ever
        /// shepherds the page when the caret drifts low — typing never yanks.
        private func shouldUseAncestorComfortScroll(for textView: NSTextView) -> Bool {
            guard !parent.typewriterMode,
                  !parent.scrollsInternally,
                  !parent.singleLine,
                  parent.titleConfiguration == nil else {
                return false
            }
            return textView.nearestAncestorScrollView(excluding: textView.enclosingScrollView) != nil
        }

        private func scheduleAncestorComfortScroll(for textView: NSTextView) {
            guard shouldUseAncestorComfortScroll(for: textView) else { return }

            let selectedRange = textView.selectedRange()
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.scrollCursorIntoAncestorComfortBand(textView, selectedRange: selectedRange)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.scrollCursorIntoAncestorComfortBand(textView, selectedRange: selectedRange)
            }
        }

        private func scrollCursorIntoAncestorComfortBand(_ textView: NSTextView, selectedRange: NSRange) {
            guard shouldUseAncestorComfortScroll(for: textView),
                  let ancestorScrollView = textView.nearestAncestorScrollView(excluding: textView.enclosingScrollView),
                  let documentView = ancestorScrollView.documentView,
                  let cursorRect = cursorRectInAncestorDocument(
                    for: textView,
                    selectedRange: selectedRange,
                    ancestorScrollView: ancestorScrollView
                  ) else {
                return
            }

            let visibleRect = ancestorScrollView.documentVisibleRect
            let visibleHeight = max(visibleRect.height, 1)
            // Nudge only once the caret enters the bottom 26% of the viewport.
            let bottomThreshold = visibleRect.minY + visibleHeight * 0.74
            guard cursorRect.maxY > bottomThreshold else { return }

            let targetY = visibleRect.minY + visibleHeight * 0.68
            let delta = cursorRect.maxY - targetY
            let documentHeight = max(documentView.bounds.height, visibleHeight)
            let maxY = max(0, documentHeight - visibleHeight)
            let targetOriginY = min(max(0, visibleRect.minY + delta), maxY)
            guard abs(targetOriginY - visibleRect.minY) > 0.5 else { return }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ancestorScrollView.contentView.animator().setBoundsOrigin(
                    NSPoint(x: visibleRect.minX, y: targetOriginY)
                )
            }
            ancestorScrollView.reflectScrolledClipView(ancestorScrollView.contentView)
        }

        // MARK: - Scroll Margin (30% Bottom)

        /// Start scrolling before cursor hits viewport bottom — keeps eyes in upper 2/3
        private func ensureScrollMargin(_ textView: NSTextView) {
            guard !parent.singleLine,
                  !textView.string.isEmpty,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  let scrollView = textView.enclosingScrollView else { return }

            let cursorRange = textView.selectedRange()
            let glyphRange = layoutManager.glyphRange(forCharacterRange: cursorRange, actualCharacterRange: nil)
            let cursorRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let cursorY = cursorRect.maxY + textView.textContainerInset.height

            let visibleRect = scrollView.contentView.bounds
            let bottomMargin = visibleRect.height * 0.3
            let bottomThreshold = visibleRect.maxY - bottomMargin

            if cursorY > bottomThreshold {
                let targetY = cursorY - visibleRect.height + bottomMargin
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.1
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: max(0, targetY)))
                }
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? CosmoTextView else { return }
            guard !textView.hasMarkedText() else { return }
            normalizeSingleLineViewport(for: textView)
            let selectedRange = textView.selectedRange()

            // Skip binding writes when called from updateNSView (e.g. setAttributedString
            // triggers selection change) — writing state here causes "Modifying state
            // during view update" and layout thrashing.
            guard !isUpdatingFromSwiftUI else { return }

            // No cursor-position binding write here: it was write-only state
            // on RichTextEditor, costing a full body + updateNSView pass per
            // caret move (every keystroke AND every click).
            applyFocusBand(to: textView)
            updateImageResizeOverlay(in: textView)

            // NSTextView recomputes typing attributes on every selection
            // change; in an EMPTY row it falls back to the view's base font,
            // shrinking a fresh heading's caret back to body size. Re-seed so
            // the caret stays heading-sized before the first character.
            if parent.splitsOnReturn, textView.string.isEmpty {
                parent.seedTypingAttributesForEmptyRow(in: textView)
            }

            // A caret that moved at or before the "/" trigger ends the slash
            // session (clicking before it, selecting across it, Home, etc.).
            if let startIndex = slashStartIndex, selectedRange.location <= startIndex {
                slashStartIndex = nil
                if parent.menusVisible?() == true {
                    dismissMenus()
                }
            }

            // Auto-detect block mode based on current line prefix (must run for ALL cursor positions)
            let lineRange = currentLineRange(in: textView)
            let lineText = (textView.string as NSString).substring(with: lineRange)
            if lineText.hasPrefix("│ ") {
                activeBlockMode = .quote
            } else if lineText.hasPrefix("• ") {
                activeBlockMode = .bulletList
            } else if lineText.hasPrefix("☐ ") || lineText.hasPrefix("☑ ") {
                activeBlockMode = .checklist
            } else if lineText.first?.isNumber == true,
                      lineText.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                // Digit guard first: String.range(of:.regularExpression)
                // compiles a fresh NSRegularExpression per call, and this
                // runs on EVERY selection change (every keystroke + click).
                activeBlockMode = .numberedList
            } else {
                activeBlockMode = .none
            }

            // No selection — dispatch empty immediately (cheap)
            guard selectedRange.length > 0 else {
                selectionChangeWorkItem?.cancel()
                parent.onSelectionChange?(cursorSnapshot(in: textView, selectedRange: selectedRange))
                return
            }

            // Debounce expensive rect computation for actual selections
            selectionChangeWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                // Use layoutManager for full selection bounding rect (covers all lines).
                // Then convert from textView coords to scrollView coords (what SwiftUI sees).
                let glyphRange = textView.layoutManager!.glyphRange(forCharacterRange: selectedRange, actualCharacterRange: nil)
                let boundingRect = textView.layoutManager!.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer!)
                let tcOrigin = textView.textContainerOrigin
                let textViewRect = CGRect(
                    x: boundingRect.origin.x + tcOrigin.x,
                    y: boundingRect.origin.y + tcOrigin.y,
                    width: boundingRect.width,
                    height: boundingRect.height
                )
                let localRect: CGRect
                if let scrollView = textView.enclosingScrollView {
                    localRect = textView.convert(textViewRect, to: scrollView)
                } else {
                    localRect = textViewRect
                }
                let selectedText = (textView.string as NSString).substring(with: selectedRange)
                let snapshot = EditorSelectionSnapshot(
                    range: selectedRange,
                    text: selectedText,
                    rectInEditor: localRect,
                    traits: self.formattingTraits(in: textView, range: selectedRange),
                    nearestHeadingBlockID: self.nearestHeadingBlockID(in: textView, before: selectedRange.location)
                )
                self.parent.onSelectionChange?(snapshot)
            }
            selectionChangeWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
        }

        private func cursorSnapshot(in textView: NSTextView, selectedRange: NSRange) -> EditorSelectionSnapshot {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return EditorSelectionSnapshot(range: selectedRange, text: "", rectInEditor: .zero)
            }

            let safeLocation = min(selectedRange.location, max(textView.string.utf16.count, 0))
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: safeLocation, length: 0),
                actualCharacterRange: nil
            )
            var cursorRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            if cursorRect.isEmpty {
                cursorRect = CGRect(x: 0, y: 0, width: 1, height: textView.font?.pointSize ?? 17)
            }
            let tcOrigin = textView.textContainerOrigin
            let textViewRect = CGRect(
                x: cursorRect.origin.x + tcOrigin.x,
                y: cursorRect.origin.y + tcOrigin.y,
                width: max(cursorRect.width, 1),
                height: max(cursorRect.height, textView.font?.pointSize ?? 17)
            )
            let localRect: CGRect
            if let scrollView = textView.enclosingScrollView {
                localRect = textView.convert(textViewRect, to: scrollView)
            } else {
                localRect = textViewRect
            }
            return EditorSelectionSnapshot(
                range: selectedRange,
                text: "",
                rectInEditor: localRect,
                traits: formattingTraits(in: textView, range: selectedRange),
                nearestHeadingBlockID: nearestHeadingBlockID(in: textView, before: selectedRange.location)
            )
        }

        /// The heading section the caret sits under: the nearest heading
        /// attribute at or before the caret. Reverse run enumeration stops at
        /// the first heading run, so this is cheap on typical documents.
        private func nearestHeadingBlockID(in textView: NSTextView, before location: Int) -> UUID? {
            guard let storage = textView.textStorage, storage.length > 0 else { return nil }
            let end = min(location + 1, storage.length)
            guard end > 0 else { return nil }
            var found: UUID?
            storage.enumerateAttribute(
                RichDocumentAttributeKeys.headingBlockID,
                in: NSRange(location: 0, length: end),
                options: [.reverse]
            ) { value, _, stop in
                if let idString = value as? String, let id = UUID(uuidString: idString) {
                    found = id
                    stop.pointee = true
                }
            }
            return found
        }

        /// Formatting state at the selection, for the formatting bar's active
        /// states. Inline traits count as active only when they cover the whole
        /// range; a caret reads the typing attributes instead.
        private func formattingTraits(in textView: NSTextView, range: NSRange) -> SelectionFormattingTraits {
            var traits = SelectionFormattingTraits()

            if range.length > 0, let storage = textView.textStorage, NSMaxRange(range) <= storage.length {
                var allBold = true, allItalic = true
                storage.enumerateAttribute(.font, in: range, options: []) { value, _, _ in
                    let symbolic = ((value as? NSFont) ?? NSFont.systemFont(ofSize: parent.fontSize))
                        .fontDescriptor.symbolicTraits
                    if !symbolic.contains(.bold) { allBold = false }
                    if !symbolic.contains(.italic) { allItalic = false }
                }
                traits.isBold = allBold
                traits.isItalic = allItalic
                traits.isUnderline = attributeCoversRange(.underlineStyle, in: storage, range: range)
                traits.isStrikethrough = attributeCoversRange(.strikethroughStyle, in: storage, range: range)
                traits.headingLevel = storage.attribute(
                    RichDocumentAttributeKeys.headingLevel, at: range.location, effectiveRange: nil
                ) as? Int
            } else {
                let attributes = textView.typingAttributes
                let symbolic = ((attributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: parent.fontSize))
                    .fontDescriptor.symbolicTraits
                traits.isBold = symbolic.contains(.bold)
                traits.isItalic = symbolic.contains(.italic)
                traits.isUnderline = (attributes[.underlineStyle] as? Int ?? 0) != 0
                traits.isStrikethrough = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
                traits.headingLevel = attributes[RichDocumentAttributeKeys.headingLevel] as? Int
            }

            switch activeBlockMode {
            case .none: traits.listKind = .none
            case .quote: traits.listKind = .quote
            case .bulletList: traits.listKind = .bullet
            case .numberedList: traits.listKind = .numbered
            case .checklist: traits.listKind = .checklist
            }
            return traits
        }

        private func attributeCoversRange(
            _ key: NSAttributedString.Key,
            in storage: NSTextStorage,
            range: NSRange
        ) -> Bool {
            var covered = true
            storage.enumerateAttribute(key, in: range, options: []) { value, _, _ in
                if (value as? Int ?? 0) == 0 { covered = false }
            }
            return covered
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let urlString: String?
            if let url = link as? URL {
                urlString = url.absoluteString
            } else if let string = link as? String {
                urlString = string
            } else {
                urlString = nil
            }

            guard let urlString,
                  let url = URL(string: urlString),
                  url.scheme == "cosmo",
                  let entityTypeString = url.host,
                  let entityType = EntityType(rawValue: entityTypeString),
                  let entityIDString = url.pathComponents.last,
                  let entityID = Int64(entityIDString) else {
                return false
            }

            NotificationCenter.default.post(
                name: .openMentionAsFloatingBlock,
                object: nil,
                userInfo: [
                    "entityType": entityType,
                    "entityId": entityID
                ]
            )
            return true
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Slash menu owns ↑/↓/Return/Tab/Esc while it's open — the text
            // view keeps first responder (type-through filtering), so these
            // keys must be routed to the menu BEFORE any editing behavior
            // (especially before the splitsOnReturn branch: Return during an
            // open menu commits the highlighted command, it must never split).
            if slashMenuIsActive {
                if commandSelector == #selector(NSResponder.moveUp(_:)),
                   parent.onSlashMenuKey?(.up) == true {
                    return true
                }
                if commandSelector == #selector(NSResponder.moveDown(_:)),
                   parent.onSlashMenuKey?(.down) == true {
                    return true
                }
                if commandSelector == #selector(NSResponder.insertNewline(_:))
                    || commandSelector == #selector(NSResponder.insertTab(_:)) {
                    if parent.onSlashMenuKey?(.commit) == true {
                        return true
                    }
                }
                if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                    _ = parent.onSlashMenuKey?(.dismiss)
                    dismissMenus()
                    return true
                }
            }

            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                if parent.menusVisible?() != true,
                   parent.onBoundaryCommand?(.escapeSelectBlock) == true {
                    dismissMenus()
                    return true
                }
                dismissMenus()
                return true
            }

            if parent.tableCellMode, let handled = handleTableCellCommand(commandSelector, in: textView) {
                return handled
            }

            if commandSelector == #selector(NSResponder.moveUp(_:)),
               selectionIsOnFirstLine(in: textView),
               parent.onBoundaryCommand?(.moveToPreviousBlock) == true {
                return true
            }

            if commandSelector == #selector(NSResponder.moveDown(_:)),
               selectionIsOnLastLine(in: textView),
               parent.onBoundaryCommand?(.moveToNextBlock) == true {
                return true
            }

            if commandSelector == #selector(NSResponder.deleteBackward(_:)),
               selectionIsAtDocumentStart(in: textView) {
                beginAwaitingExternalContent()
                if parent.onBoundaryCommand?(.deleteBackwardAtStart(livePlainText: textView.string)) == true {
                    return true
                }
                cancelAwaitingExternalContent()
            }

            // Shift+Enter — always continue current block
            if commandSelector == #selector(NSResponder.insertLineBreak(_:)) {
                // Block rows: a soft break (U+2028) stays inside the block.
                // The serializer only splits blocks on hard newlines, and
                // paragraph spacing doesn't apply at a line separator, so the
                // continuation renders with tight line spacing. Unconditional
                // on menu flags — a stale flag must never route a block row
                // into the legacy "\n + prefix" continuation below (raw \n
                // in a single-block row reads back as duplicated text).
                if parent.splitsOnReturn {
                    if parent.menusVisible?() == true {
                        dismissMenus()
                    }
                    textView.insertText("\u{2028}", replacementRange: textView.selectedRange())
                    syncBindings(from: textView)
                    scheduleAncestorTypewriterScroll(for: textView)
                    return true
                }
                if activeBlockMode != .none, let prefix = continuationPrefix(for: textView) {
                    textView.insertText("\n" + prefix, replacementRange: textView.selectedRange())
                    clearInsertedChecklistGlyph(prefix: prefix, in: textView)
                    syncBindings(from: textView)
                    scheduleAncestorTypewriterScroll(for: textView)
                    return true
                }
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if parent.singleLine || parent.titleConfiguration?.commitsOnReturn == true || parent.onCommit != nil {
                    dismissMenus()
                    parent.onCommit?()
                    return true
                }

                if selectionIsOnEmptyFinalLine(in: textView) {
                    // Exit-list/exit-code converts this block's kind out of
                    // band — suppress stale write-backs exactly like the
                    // split/deleteBackward paths, or the view's old "• "
                    // snapshot re-emits, parses as a bullet, and resurrects
                    // the list kind over the fresh paragraph.
                    beginAwaitingExternalContent()
                    if parent.onBoundaryCommand?(.insertNewlineOnEmptyFinalLine) == true {
                        return true
                    }
                    cancelAwaitingExternalContent()
                }

                // Code blocks: Return stays INSIDE the block as a soft break —
                // code is multiline by nature. The empty-final-line branch
                // above is the exit (double-Return leaves the block).
                if parent.splitsOnReturn, parent.rowBlockKind == .code {
                    if parent.menusVisible?() == true {
                        dismissMenus()
                    }
                    textView.insertText("\u{2028}", replacementRange: textView.selectedRange())
                    syncBindings(from: textView)
                    scheduleAncestorTypewriterScroll(for: textView)
                    return true
                }

                // Block rows: Return ALWAYS splits the block at the caret —
                // the Notion model. Shift+Return (insertLineBreak above) is
                // the only way to stay in the block. The caret offset is
                // measured from the END of the text so list/quote prefixes
                // rendered at the head don't shift it; the live string rides
                // along since the document binding can lag the view by ~50ms.
                //
                // A raw \n must NEVER enter a block row's text view: the
                // single-block document re-parses into two blocks while this
                // view keeps showing both lines, so the text appears
                // duplicated. A genuinely open menu owns the keyboard through
                // its own focus and this command never fires while one is up;
                // a menusVisible flag here is stale (e.g. a selection-menu
                // flag surviving a collapse) — clear the ghosts and split.
                if parent.splitsOnReturn {
                    if parent.menusVisible?() == true {
                        dismissMenus()
                    }
                    let selection = textView.selectedRange()
                    if selection.length > 0 {
                        textView.insertText("", replacementRange: selection)
                    }
                    let textLength = (textView.string as NSString).length
                    let caretOffsetFromEnd = max(0, textLength - textView.selectedRange().location)
                    beginAwaitingExternalContent()
                    if parent.onBoundaryCommand?(.splitBlock(
                        caretUTF16OffsetFromEnd: caretOffsetFromEnd,
                        livePlainText: textView.string
                    )) == true {
                        dismissMenus()
                        return true
                    }
                    cancelAwaitingExternalContent()
                    // Degenerate split failure — a soft break preserves the
                    // one-block-per-row invariant where a hard \n would not.
                    textView.insertText("\u{2028}", replacementRange: textView.selectedRange())
                    syncBindings(from: textView)
                    return true
                }

                if let collapsedHeadingRange = collapsedHeadingLineRangeContainingSelection(in: textView) {
                    insertParagraphAfterCollapsedHeading(headingRange: collapsedHeadingRange, in: textView)
                    return true
                }

                // Block continuation: quotes, bullets, numbered lists, checklists
                if activeBlockMode != .none {
                    if isEmptyBlockLine(in: textView) {
                        // Empty block line → exit block mode, remove prefix
                        let lineRange = currentLineRange(in: textView)
                        let prefixLen = blockPrefixLength(in: textView)
                        if prefixLen > 0 {
                            textView.textStorage?.replaceCharacters(
                                in: NSRange(location: lineRange.location, length: prefixLen),
                                with: ""
                            )
                        }
                        activeBlockMode = .none
                        resetToNormalTypingAttributes(textView)
                        syncBindings(from: textView)
                        return true
                    } else if activeBlockMode == .quote {
                        // Quote blocks: continue with prefix on single Enter
                        // Use tight paragraph spacing so quote lines stay visually connected
                        if let prefix = continuationPrefix(for: textView) {
                            let quoteStyle = NSMutableParagraphStyle()
                            quoteStyle.lineSpacing = parent.compact ? 2 : 4
                            quoteStyle.paragraphSpacing = parent.compact ? 2 : 4
                            var quoteAttrs = textView.typingAttributes
                            quoteAttrs[.paragraphStyle] = quoteStyle
                            textView.typingAttributes = quoteAttrs

                            textView.insertText("\n" + prefix, replacementRange: textView.selectedRange())
                            syncBindings(from: textView)
                            scheduleAncestorTypewriterScroll(for: textView)
                            return true
                        }
                    } else if let prefix = continuationPrefix(for: textView) {
                        // Bullets/numbered/checklists: continue with prefix, reset inline formatting
                        textView.insertText("\n" + prefix, replacementRange: textView.selectedRange())
                        clearInsertedChecklistGlyph(prefix: prefix, in: textView)
                        resetInlineFormattingOnly(textView)
                        syncBindings(from: textView)
                        scheduleAncestorTypewriterScroll(for: textView)
                        return true
                    }
                }

                insertNormalNewline(in: textView)
                return true
            }

            if commandSelector == #selector(NSResponder.insertTab(_:)) &&
                (parent.singleLine || parent.titleConfiguration != nil) {
                return true
            }

            return false
        }

        // MARK: - Block Continuation Helpers

        private func selectionIsOnFirstLine(in textView: NSTextView) -> Bool {
            let selection = textView.selectedRange()
            guard selection.length == 0 else { return false }
            return currentLineRange(in: textView).location == 0
        }

        private func selectionIsOnLastLine(in textView: NSTextView) -> Bool {
            let selection = textView.selectedRange()
            guard selection.length == 0 else { return false }
            let lineRange = currentLineRange(in: textView)
            return NSMaxRange(lineRange) >= textView.string.utf16.count
        }

        /// UTF-16 length of the chrome prefix this row's kind renders at the head
        /// of the text ("• ", "1. ", "☐ ", "│ "). Zero for the legacy continuous
        /// editor, which has no rowBlockKind and owns its prefixes as content.
        private func renderedRowPrefixLength(in textView: NSTextView) -> Int {
            guard let kind = parent.rowBlockKind else { return 0 }
            return kind.renderedPrefixLength(in: textView.string)
        }

        private func selectionIsAtDocumentStart(in textView: NSTextView) -> Bool {
            let selection = textView.selectedRange()
            guard selection.length == 0 else { return false }
            // The row's rendered prefix is chrome, not content — the caret's home
            // is the character right after it. Counting only location 0 made
            // Backspace delete the prefix a character at a time instead of
            // exiting the list, so leaving a bullet took three presses.
            return selection.location <= renderedRowPrefixLength(in: textView)
        }

        private func selectionIsOnEmptyFinalLine(in textView: NSTextView) -> Bool {
            guard selectionIsOnLastLine(in: textView) else { return false }
            let lineRange = currentLineRange(in: textView)
            let lineText = (textView.string as NSString).substring(with: lineRange) as NSString
            // Same chrome rule: "• " must read as empty here, or Return on an
            // empty bullet splits the row into ANOTHER empty bullet instead of
            // exiting the list.
            let prefixLength = lineRange.location == 0
                ? min(renderedRowPrefixLength(in: textView), lineText.length)
                : 0
            let content = lineText.substring(from: prefixLength)
            return content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        /// After a checklist continuation prefix ("☐ ") is inserted with live
        /// typing attributes, the box character must go clear — the visible
        /// circle checkbox is painted over its rect by drawChecklistCheckboxes.
        private func clearInsertedChecklistGlyph(prefix: String, in textView: NSTextView) {
            guard prefix.hasPrefix("☐") else { return }
            let glyphIndex = textView.selectedRange().location - prefix.utf16.count
            guard glyphIndex >= 0 else { return }
            textView.textStorage?.addAttribute(
                .foregroundColor,
                value: NSColor.clear,
                range: NSRange(location: glyphIndex, length: 1)
            )
        }

        private func continuationPrefix(for textView: NSTextView) -> String? {
            switch activeBlockMode {
            case .none: return nil
            case .quote: return "│ "
            case .bulletList: return "• "
            case .checklist: return "☐ "
            case .numberedList:
                let lineRange = currentLineRange(in: textView)
                let lineText = (textView.string as NSString).substring(with: lineRange)
                if let match = lineText.range(of: #"^(\d+)\."#, options: .regularExpression) {
                    let numStr = String(lineText[match])
                        .replacingOccurrences(of: ".", with: "")
                    if let num = Int(numStr) {
                        return "\(num + 1). "
                    }
                }
                return "1. "
            }
        }

        private func isEmptyBlockLine(in textView: NSTextView) -> Bool {
            let lineRange = currentLineRange(in: textView)
            let lineText = (textView.string as NSString).substring(with: lineRange)
            let trimmed = lineText.trimmingCharacters(in: .newlines)
            switch activeBlockMode {
            case .none: return false
            case .quote: return trimmed == "│" || trimmed == "│ "
            case .bulletList: return trimmed == "•" || trimmed == "• "
            case .checklist: return trimmed == "☐" || trimmed == "☐ " || trimmed == "☑" || trimmed == "☑ "
            case .numberedList: return trimmed.range(of: #"^\d+\.\s*$"#, options: .regularExpression) != nil
            }
        }

        private func blockPrefixLength(in textView: NSTextView) -> Int {
            let lineRange = currentLineRange(in: textView)
            let lineText = (textView.string as NSString).substring(with: lineRange)
            switch activeBlockMode {
            case .none: return 0
            case .quote: return lineText.hasPrefix("│ ") ? 2 : 1
            case .bulletList: return lineText.hasPrefix("• ") ? 2 : 1
            case .checklist: return (lineText.hasPrefix("☐ ") || lineText.hasPrefix("☑ ")) ? 2 : 1
            case .numberedList:
                if let match = lineText.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                    return lineText.distance(from: lineText.startIndex, to: match.upperBound)
                }
                return 0
            }
        }

        private func collapsedHeadingLineRangeContainingSelection(in textView: NSTextView) -> NSRange? {
            guard let storage = textView.textStorage,
                  storage.length > 0,
                  textView.selectedRange().length == 0 else {
                return nil
            }

            let lineRange = currentLineRange(in: textView)
            let trimmedRange = trimmingTrailingNewline(from: lineRange, in: textView.string as NSString)
            guard trimmedRange.length > 0,
                  trimmedRange.location < storage.length,
                  storage.attribute(RichDocumentAttributeKeys.headingLevel, at: trimmedRange.location, effectiveRange: nil) != nil,
                  boolAttribute(RichDocumentAttributeKeys.headingCollapsed, at: trimmedRange.location, in: storage) == true else {
                return nil
            }
            return trimmedRange
        }

        private func insertParagraphAfterCollapsedHeading(headingRange: NSRange, in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }

            let insertionLocation = min(NSMaxRange(headingRange), storage.length)
            let newline = NSAttributedString(string: "\n", attributes: elementInsertionBaseAttributes())
            storage.replaceCharacters(in: NSRange(location: insertionLocation, length: 0), with: newline)
            textView.setSelectedRange(NSRange(location: insertionLocation + 1, length: 0))
            resetToNormalTypingAttributes(textView)
            syncBindings(from: textView)

            if let container = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: container)
            }
            textView.needsDisplay = true
            textView.sizeToFit()
            notifyContentHeightChange(for: textView)
            scheduleAncestorTypewriterScroll(for: textView)
        }

        private func insertNormalNewline(in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }

            let replacementRange = textView.selectedRange()
            guard NSMaxRange(replacementRange) <= storage.length,
                  textView.shouldChangeText(in: replacementRange, replacementString: "\n") else {
                return
            }

            let shouldUseAncestorTypewriterScroll = shouldUseAncestorTypewriterScroll(for: textView)
            let ancestorSnapshot = shouldUseAncestorTypewriterScroll ? nil : captureAncestorScrollSnapshot(for: textView)
            resetToNormalTypingAttributes(textView)
            let newline = NSAttributedString(string: "\n", attributes: elementInsertionBaseAttributes())
            isApplyingStructuralEdit = true
            defer { isApplyingStructuralEdit = false }
            storage.replaceCharacters(in: replacementRange, with: newline)
            textView.setSelectedRange(NSRange(location: replacementRange.location + newline.length, length: 0))
            if !shouldUseAncestorTypewriterScroll {
                restoreAncestorScrollSnapshot(ancestorSnapshot)
            }
            textView.didChangeText()
            syncBindings(from: textView)
            if shouldUseAncestorTypewriterScroll {
                scheduleAncestorTypewriterScroll(for: textView)
            } else {
                restoreAncestorScrollSnapshot(ancestorSnapshot)
                scheduleAncestorScrollSnapshotRestores(ancestorSnapshot)
            }
        }

        // MARK: - Menu State

        private func handleMentionState(in textView: CosmoTextView, text: String, cursorLocation: Int) {
            guard parent.allowMentions else {
                mentionStartIndex = nil
                return
            }

            if let startIndex = mentionStartIndex {
                let stillValid = startIndex < text.count &&
                    text[text.index(text.startIndex, offsetBy: startIndex)] == "@" &&
                    cursorLocation >= startIndex

                if !stillValid {
                    mentionStartIndex = nil
                    dismissMenus()
                    return
                }

                let queryRange = NSRange(location: startIndex + 1, length: max(0, cursorLocation - startIndex - 1))
                if queryRange.location <= text.count, NSMaxRange(queryRange) <= text.count {
                    let query = (text as NSString).substring(with: queryRange)
                    if query.contains(" ") || query.contains("\n") {
                        mentionStartIndex = nil
                        dismissMenus()
                        return
                    }

                    let position = caretPosition(for: startIndex, in: textView)
                    parent.onMention?(position, query)
                    return
                }
            }

            guard cursorLocation > 0 else { return }
            let char = (text as NSString).substring(with: NSRange(location: cursorLocation - 1, length: 1))
            if char == "@" {
                mentionStartIndex = cursorLocation - 1
                menuOpenedAt = CFAbsoluteTimeGetCurrent()
                parent.onMention?(caretPosition(for: cursorLocation - 1, in: textView), "")
            }
        }

        private func handleSlashState(in textView: CosmoTextView, text: String, cursorLocation: Int) {
            guard parent.allowSlashCommands else {
                slashStartIndex = nil
                return
            }
            let nsText = text as NSString

            // Live session: keep the query (text between the "/" and the caret)
            // in sync, dismiss when the trigger breaks. Typing stays in the
            // text view the whole time — the menu never takes focus.
            if let startIndex = slashStartIndex {
                let stillValid = startIndex < nsText.length
                    && nsText.substring(with: NSRange(location: startIndex, length: 1)) == "/"
                    && cursorLocation > startIndex
                guard stillValid else {
                    slashStartIndex = nil
                    dismissMenus()
                    return
                }
                let queryRange = NSRange(location: startIndex + 1, length: cursorLocation - startIndex - 1)
                guard NSMaxRange(queryRange) <= nsText.length else {
                    slashStartIndex = nil
                    dismissMenus()
                    return
                }
                let query = nsText.substring(with: queryRange)
                if query.contains("\n") || query.contains("\u{2028}") {
                    slashStartIndex = nil
                    dismissMenus()
                    return
                }
                let anchor = slashSessionAnchor ?? caretPosition(for: startIndex, in: textView)
                slashSessionAnchor = anchor
                parent.onSlashCommand?(anchor, query)
                return
            }

            guard cursorLocation > 0 else { return }
            let currentChar = nsText.substring(with: NSRange(location: cursorLocation - 1, length: 1))
            guard currentChar == "/" else { return }

            let isStartOfDocument = cursorLocation == 1
            let precededByWhitespace: Bool = {
                guard cursorLocation >= 2 else { return true }
                let previous = nsText.substring(with: NSRange(location: cursorLocation - 2, length: 1))
                return previous.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }()

            if isStartOfDocument || precededByWhitespace {
                slashStartIndex = cursorLocation - 1
                menuOpenedAt = CFAbsoluteTimeGetCurrent()
                parent.onSlashCommand?(caretPosition(for: cursorLocation - 1, in: textView), "")
            }
        }

        /// Multi-line paste in a block row: delete any selection, then hand
        /// the pasted text to the host as ONE structural splice. The text
        /// view never holds the multi-line content, so there is no window in
        /// which a stale re-emission can duplicate blocks.
        func performBlockPaste(_ pastedText: String, in textView: CosmoTextView) -> Bool {
            guard parent.splitsOnReturn else { return false }
            let selection = textView.selectedRange()
            if selection.length > 0 {
                textView.insertText("", replacementRange: selection)
            }
            let textLength = (textView.string as NSString).length
            let caretOffsetFromEnd = max(0, textLength - textView.selectedRange().location)
            beginAwaitingExternalContent()
            if parent.onBoundaryCommand?(.pasteBlocks(
                pastedText: pastedText,
                caretUTF16OffsetFromEnd: caretOffsetFromEnd,
                livePlainText: textView.string
            )) == true {
                dismissMenus()
                return true
            }
            cancelAwaitingExternalContent()
            return false
        }

        /// Markdown alias completion — hand the conversion to the block
        /// pipeline. The row validates the block's kind (paragraphs only).
        private func applyMarkdownAliasIfNeeded(in textView: CosmoTextView) -> Bool {
            guard parent.allowSlashCommands,
                  slashStartIndex == nil,
                  let alias = MarkdownBlockAlias.match(
                    text: textView.string,
                    cursorLocation: textView.selectedRange().location
                  ) else {
                return false
            }
            beginAwaitingExternalContent()
            if parent.onBoundaryCommand?(.applyMarkdownAlias(
                kind: alias.kind,
                checked: alias.checked,
                aliasUTF16Length: alias.utf16Length,
                livePlainText: textView.string
            )) == true {
                return true
            }
            cancelAwaitingExternalContent()
            return false
        }

        /// Structured block paste (com.cosmo.blocks) — kinds survive within
        /// the app. Falls back to the plain-text splice when decode fails.
        func performStructuredBlockPaste(_ data: Data, in textView: CosmoTextView) -> Bool {
            guard parent.splitsOnReturn,
                  let blocks = try? JSONDecoder().decode([RichBlock].self, from: data),
                  !blocks.isEmpty else {
                return false
            }
            let selection = textView.selectedRange()
            if selection.length > 0 {
                textView.insertText("", replacementRange: selection)
            }
            let textLength = (textView.string as NSString).length
            let caretOffsetFromEnd = max(0, textLength - textView.selectedRange().location)
            beginAwaitingExternalContent()
            if parent.onBoundaryCommand?(.pasteBlockRun(
                blocks: blocks.map { $0.withRegeneratedIDs() },
                caretUTF16OffsetFromEnd: caretOffsetFromEnd,
                livePlainText: textView.string
            )) == true {
                dismissMenus()
                return true
            }
            cancelAwaitingExternalContent()
            return false
        }

        /// Backstop for hard newlines that entered a block row through paths
        /// paste interception can't see. Re-parses the live content into
        /// blocks synchronously with write-back suppression armed.
        private func containHardNewlines(in textView: CosmoTextView) {
            let textLength = (textView.string as NSString).length
            let caretOffsetFromEnd = max(0, textLength - textView.selectedRange().location)
            beginAwaitingExternalContent()
            if parent.onBoundaryCommand?(.normalizeHardNewlines(
                caretUTF16OffsetFromEnd: caretOffsetFromEnd,
                livePlainText: textView.string
            )) == true {
                return
            }
            // No host handled it — degrade the newlines to soft separators in
            // place so the one-block invariant holds.
            cancelAwaitingExternalContent()
            let sanitized = textView.string.replacingHardNewlinesWithLineSeparators()
            let fullRange = NSRange(location: 0, length: textLength)
            if textView.shouldChangeText(in: fullRange, replacementString: sanitized) {
                let selection = textView.selectedRange()
                isApplyingStructuralEdit = true
                textView.textStorage?.replaceCharacters(in: fullRange, with: sanitized)
                textView.setSelectedRange(NSRange(
                    location: min(selection.location, (textView.string as NSString).length),
                    length: 0
                ))
                textView.didChangeText()
                isApplyingStructuralEdit = false
                syncBindings(from: textView)
            }
        }

        /// Whether a slash session is live (trigger tracked and the host
        /// reports its menu visible) — gates the menu key routing.
        private var slashMenuIsActive: Bool {
            slashStartIndex != nil && parent.menusVisible?() == true
        }

        /// Deletes the tracked "/" trigger and any query typed after it, as one
        /// undoable text edit. Returns true when a trigger was removed.
        @discardableResult
        func consumeSlashTrigger(in textView: CosmoTextView) -> Bool {
            guard let startIndex = slashStartIndex else { return false }
            slashStartIndex = nil
            let nsText = textView.string as NSString
            guard startIndex < nsText.length,
                  nsText.substring(with: NSRange(location: startIndex, length: 1)) == "/" else {
                return false
            }
            let caret = textView.selectedRange().location
            let end = max(startIndex + 1, min(caret, nsText.length))
            let triggerRange = NSRange(location: startIndex, length: end - startIndex)
            guard textView.shouldChangeText(in: triggerRange, replacementString: "") else { return false }
            isApplyingStructuralEdit = true
            textView.textStorage?.replaceCharacters(in: triggerRange, with: "")
            textView.setSelectedRange(NSRange(location: startIndex, length: 0))
            textView.didChangeText()
            isApplyingStructuralEdit = false
            syncBindings(from: textView)
            return true
        }

        private func caretPosition(for location: Int, in textView: NSTextView) -> CGPoint {
            let safeLocation = max(0, min(location, textView.string.count))
            let screenRect = textView.firstRect(
                forCharacterRange: NSRange(location: safeLocation, length: 0),
                actualRange: nil
            )
            if let window = textView.window, let scrollView = textView.enclosingScrollView {
                let windowRect = window.convertFromScreen(screenRect)
                let local = scrollView.convert(windowRect.origin, from: nil)
                return CGPoint(x: local.x, y: local.y + screenRect.height)
            }
            return CGPoint(x: screenRect.origin.x, y: screenRect.origin.y + screenRect.height)
        }

        fileprivate func dismissMenus() {
            mentionStartIndex = nil
            slashStartIndex = nil
            parent.onDismissMenus?()
        }

        /// Consumes a one-shot caret request from a structural edit — focuses
        /// the view and places the caret measured from the END of the text so
        /// rendered list/quote prefixes at the head don't shift it.
        func applyCaretRequestIfNeeded(to textView: CosmoTextView) {
            guard let request = parent.caretRequest, request.token != lastAppliedCaretToken else { return }
            lastAppliedCaretToken = request.token
            placeCaretWhenReady(
                in: textView,
                utf16OffsetFromEnd: request.utf16OffsetFromEnd,
                windowPoint: request.windowPoint,
                requestToken: request.token,
                pointerGeneration: CosmoTextView.pointerInteractionGeneration
            )
        }

        func scheduleRefocus(to textView: CosmoTextView) {
            let pointerGeneration = CosmoTextView.pointerInteractionGeneration
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, self.parent.shouldRefocus else { return }
                self.parent.shouldRefocus = false
                guard pointerGeneration == CosmoTextView.pointerInteractionGeneration,
                      !textView.hasMarkedText() else { return }
                textView.window?.makeFirstResponder(textView)
            }
        }

        /// Focuses `textView` and places the caret after a structural edit
        /// (split/merge/delete). The new block's NSView may not be attached to a
        /// window on the very next runloop tick, in which case
        /// `makeFirstResponder` silently no-ops and the caret is stranded in the
        /// block the user just left. Retry across a few ticks until the view is
        /// in a window so focus reliably follows to the new block.
        private func placeCaretWhenReady(
            in textView: CosmoTextView,
            utf16OffsetFromEnd: Int,
            windowPoint: CGPoint? = nil,
            requestToken: Int,
            pointerGeneration: UInt64,
            attemptsRemaining: Int = 8
        ) {
            DispatchQueue.main.async { [weak textView] in
                guard let textView,
                      self.parent.caretRequest?.token == requestToken,
                      pointerGeneration == CosmoTextView.pointerInteractionGeneration,
                      !textView.hasMarkedText() else { return }
                guard let window = textView.window else {
                    if attemptsRemaining > 0 {
                        self.placeCaretWhenReady(
                            in: textView,
                            utf16OffsetFromEnd: utf16OffsetFromEnd,
                            windowPoint: windowPoint,
                            requestToken: requestToken,
                            pointerGeneration: pointerGeneration,
                            attemptsRemaining: attemptsRemaining - 1
                        )
                    }
                    return
                }
                let length = (textView.string as NSString).length
                var location = max(0, min(length, length - utf16OffsetFromEnd))
                if let windowPoint {
                    // A click on a static cell: land where the click was.
                    let local = textView.convert(windowPoint, from: nil)
                    location = max(0, min(length, textView.characterIndexForInsertion(at: local)))
                }
                window.makeFirstResponder(textView)
                textView.setSelectedRange(NSRange(location: location, length: 0))
                textView.scrollRangeToVisible(NSRange(location: location, length: 0))
            }
        }

        // MARK: - Checklist Toggle

        /// The one earned delight: clicking a ☐ checks it — the box turns
        /// accent green and the line settles into muted, struck-through done.
        /// The whole line is replaced as one attributed string through
        /// shouldChangeText/didChangeText so a single undo restores glyph and
        /// styling together, and the normal sync path persists the change.
        func toggleChecklistItem(atLineStart lineStart: Int, in textView: CosmoTextView) {
            guard let storage = textView.textStorage else { return }
            let nsText = textView.string as NSString
            guard lineStart < nsText.length else { return }

            let lineRange = nsText.lineRange(for: NSRange(location: lineStart, length: 0))
            var lineContentLength = lineRange.length
            if lineContentLength > 0 {
                let lastChar = nsText.substring(
                    with: NSRange(location: lineRange.location + lineRange.length - 1, length: 1)
                )
                if lastChar == "\n" || lastChar == "\r" {
                    lineContentLength -= 1
                }
            }
            guard lineContentLength >= 1 else { return }

            let lineContentRange = NSRange(location: lineRange.location, length: lineContentLength)
            let glyph = nsText.substring(with: NSRange(location: lineRange.location, length: 1))
            guard glyph == "☐" || glyph == "☑" else { return }
            let nowChecked = glyph == "☐"

            let updatedLine = NSMutableAttributedString(
                attributedString: storage.attributedSubstring(from: lineContentRange)
            )
            updatedLine.replaceCharacters(
                in: NSRange(location: 0, length: 1),
                with: nowChecked ? "☑" : "☐"
            )

            let baseColor = parent.overrideTextColor
                ?? (parent.darkMode ? NSColor.white : NSColor(DS.documentText))
            let prefixColor = nowChecked
                ? NSColor(CosmoColors.cosmoAI).withAlphaComponent(parent.darkMode ? 0.92 : 0.85)
                : baseColor
            updatedLine.addAttribute(
                .foregroundColor,
                value: prefixColor,
                range: NSRange(location: 0, length: min(2, updatedLine.length))
            )
            // The character never inks — the circle checkbox is painted over
            // its rect by drawChecklistCheckboxes.
            updatedLine.addAttribute(
                .foregroundColor,
                value: NSColor.clear,
                range: NSRange(location: 0, length: 1)
            )

            if updatedLine.length > 2 {
                let contentRange = NSRange(location: 2, length: updatedLine.length - 2)
                if nowChecked {
                    updatedLine.addAttribute(
                        .strikethroughStyle,
                        value: NSUnderlineStyle.single.rawValue,
                        range: contentRange
                    )
                    updatedLine.enumerateAttribute(.foregroundColor, in: contentRange, options: []) { value, range, _ in
                        guard let color = value as? NSColor else { return }
                        // GUARD-TWIN of the serializer's checked-content dim
                        // (0.55) — the live click must render the same state
                        // the same way a reload does.
                        updatedLine.addAttribute(
                            .foregroundColor,
                            value: color.withAlphaComponent(0.55),
                            range: range
                        )
                    }
                } else {
                    updatedLine.removeAttribute(.strikethroughStyle, range: contentRange)
                    updatedLine.enumerateAttribute(.foregroundColor, in: contentRange, options: []) { value, range, _ in
                        guard let color = value as? NSColor else { return }
                        updatedLine.addAttribute(
                            .foregroundColor,
                            value: color.withAlphaComponent(1.0),
                            range: range
                        )
                    }
                }
            }

            guard textView.shouldChangeText(in: lineContentRange, replacementString: updatedLine.string) else { return }
            storage.replaceCharacters(in: lineContentRange, with: updatedLine)
            textView.didChangeText()
        }

        // MARK: - Commands

        @objc private func handleEditorScroll(_ notification: Notification) {
            // Skip dismiss if a menu just opened — the scroll is auto-scroll
            // from the text insertion, not a user-initiated scroll.
            let elapsed = CFAbsoluteTimeGetCurrent() - menuOpenedAt
            guard elapsed > 0.3 else { return }
            dismissMenus()
        }

        @objc private func handleAppWillResignActive(_ notification: Notification) {
            dismissMenus()
        }

        @objc private func handleInsertMentionInEditor(_ notification: Notification) {
            guard let textView = activeTextView else { return }
            guard acceptsActiveEditorCommand(notification, textView: textView) else { return }

            guard let rawType = notification.userInfo?["entityType"] as? String,
                  let type = EntityType(rawValue: rawType),
                  let title = notification.userInfo?["title"] as? String else {
                return
            }

            let entityID = notification.userInfo?["entityId"] as? Int64
            let entityUUID = notification.userInfo?["entityUUID"] as? String ?? UUID().uuidString

            replaceCurrentMentionOrSelection(
                in: textView,
                mention: RichMention(entityUUID: entityUUID, entityID: entityID, entityType: type, titleSnapshot: title)
            )
        }

        @objc private func handlePerformMentionSelection(_ notification: Notification) {
            guard let textView = activeTextView else { return }
            guard acceptsActiveEditorCommand(notification, textView: textView) else { return }

            guard let rawType = notification.userInfo?["entityType"] as? String,
                  let type = EntityType(rawValue: rawType),
                  let title = notification.userInfo?["title"] as? String,
                  let uuid = notification.userInfo?["entityUUID"] as? String else {
                return
            }

            let entityID = notification.userInfo?["entityId"] as? Int64
            replaceCurrentMentionOrSelection(
                in: textView,
                mention: RichMention(entityUUID: uuid, entityID: entityID, entityType: type, titleSnapshot: title)
            )
            dismissMenus()
        }

        @objc private func handleInsertTextInEditor(_ notification: Notification) {
            guard let textView = activeTextView,
                  let text = notification.userInfo?["text"] as? String else { return }
            guard acceptsEditorCommand(notification) else { return }

            let allowInactive = notification.userInfo?["allowInactive"] as? Bool ?? false
            guard allowInactive || textView.window?.firstResponder === textView else { return }

            let positionRaw = notification.userInfo?["position"] as? String ?? EditorCommandBus.InsertPosition.cursor.rawValue
            insertText(text, position: positionRaw, into: textView)
        }

        @objc private func handleReplaceSelectionInEditor(_ notification: Notification) {
            guard let textView = activeTextView,
                  let text = notification.userInfo?["text"] as? String else { return }
            guard acceptsEditorCommand(notification) else { return }

            let allowInactive = notification.userInfo?["allowInactive"] as? Bool ?? false
            guard allowInactive || textView.window?.firstResponder === textView else { return }
            insertText(text, position: EditorCommandBus.InsertPosition.cursor.rawValue, into: textView)
        }

        private func acceptsEditorCommand(_ notification: Notification) -> Bool {
            guard let targetID = notification.userInfo?["targetEditorID"] as? String,
                  !targetID.isEmpty else {
                return true
            }
            return parent.editorTargetID == targetID
        }

        private func acceptsActiveEditorCommand(_ notification: Notification, textView: NSTextView) -> Bool {
            if let targetID = notification.userInfo?["targetEditorID"] as? String,
               !targetID.isEmpty {
                guard parent.editorTargetID == targetID else { return false }
                if textView.window?.firstResponder !== textView {
                    textView.window?.makeFirstResponder(textView)
                }
                return true
            }

            return textView.window?.firstResponder === textView
        }

        @objc private func handleSetTypingAttributes(_ notification: Notification) {
            guard let textView = activeTextView,
                  textView.window?.firstResponder === textView,
                  let font = notification.userInfo?["font"] as? NSFont,
                  let color = notification.userInfo?["color"] as? NSColor else {
                return
            }

            let isHeading = notification.userInfo?["isHeading"] as? Bool ?? false
            isInHeadingMode = isHeading

            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]

            if isHeading {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineSpacing = 4
                paragraphStyle.paragraphSpacing = 12
                paragraphStyle.paragraphSpacingBefore = 16
                attributes[.paragraphStyle] = paragraphStyle
            } else {
                attributes[.paragraphStyle] = defaultParagraphStyle()
            }

            textView.typingAttributes = attributes
            syncBindings(from: textView)
        }

        @objc private func handlePerformSlashCommand(_ notification: Notification) {
            guard parent.allowSlashCommands,
                  let textView = activeTextView,
                  let command = notification.userInfo?["command"] as? SlashCommand,
                  let storage = textView.textStorage else {
                return
            }
            // Only the editor that presented the menu may execute — target
            // IDs alone are ambiguous (focus-mode row and canvas block of the
            // same note share one), and a second executor corrupts the note.
            if let sourceInstanceID = notification.userInfo?["sourceEditorInstanceID"] as? UUID,
               parent.editorInstanceID != sourceInstanceID {
                return
            }
            guard acceptsActiveEditorCommand(notification, textView: textView) else { return }

            // Block rows execute synchronously through the block pipeline —
            // the legacy TextKit mutations below (heading fonts, "• " prefixes,
            // divider glyph runs) are continuous-editor behaviors and corrupt a
            // single-block row. Only .image and .writingAI fall through, with
            // the trigger already consumed.
            if parent.splitsOnReturn {
                handleBlockRowSlashCommand(command, in: textView)
                return
            }

            var insertionPoint = textView.selectedRange().location
            if consumeSlashTrigger(in: textView) {
                insertionPoint = textView.selectedRange().location
            } else if insertionPoint > 0 {
                let slashRange = NSRange(location: insertionPoint - 1, length: 1)
                if slashRange.location < storage.length,
                   (textView.string as NSString).substring(with: slashRange) == "/" {
                    storage.replaceCharacters(in: slashRange, with: "")
                    insertionPoint = slashRange.location
                    textView.setSelectedRange(NSRange(location: insertionPoint, length: 0))
                }
            }

            switch command.type {
            case .writingAI:
                NotificationCenter.default.post(name: .contentFocusOpenWritingAI, object: nil)
            case .image:
                guard parent.allowImages else { return }
                presentImagePicker(for: textView)
            case .elements:
                break
            case .newElement:
                break
            case .content:
                break
            case .research:
                break
            case .element:
                guard let definition = command.elementDefinition else { return }
                insertElement(definition, at: insertionPoint, in: textView)
            case .heading1:
                applyHeading(level: 1, collapsible: false, textView: textView)
            case .heading2:
                applyHeading(level: 2, collapsible: false, textView: textView)
            case .heading3:
                applyHeading(level: 3, collapsible: false, textView: textView)
            case .toggleHeading1:
                applyHeading(level: 1, collapsible: true, textView: textView)
            case .toggleHeading2:
                applyHeading(level: 2, collapsible: true, textView: textView)
            case .toggleHeading3:
                applyHeading(level: 3, collapsible: true, textView: textView)
            case .quote:
                toggleBlockPrefix("│ ", kind: .quote, in: textView)
            case .divider:
                insertTextBlock("───────────────", at: insertionPoint, in: textView, appendTrailingNewline: true)
            case .bulletList:
                toggleBlockPrefix("• ", kind: .bulletList, in: textView)
            case .numberedList:
                toggleNumberedList(in: textView)
            case .checkbox:
                toggleChecklist(in: textView)
            case .callout, .toggle, .codeBlock, .sketch, .table, .section:
                // Block-editor-only kinds; the legacy continuous editor has no
                // TextKit rendering for them, so the trigger is just consumed.
                break
            }

            syncBindings(from: textView)

            // Force layout update after format changes to prevent view clipping (Bug 2)
            if let textContainer = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: textContainer)
            }
            textView.sizeToFit()
            notifyContentHeightChange(for: textView)

            dismissMenus()
        }

        /// Block-row slash execution: consume the tracked trigger, then hand
        /// the command to the block pipeline (BlockOperations via the row's
        /// onSlashCommandSelected) in ONE synchronous step — no delays, no
        /// refocus hops, no raw TextKit mutations. The text view is the stale
        /// side once the document rebuilds, so write-backs are suppressed
        /// until the fresh content lands (same contract as split/merge).
        private func handleBlockRowSlashCommand(_ command: SlashCommand, in textView: CosmoTextView) {
            consumeSlashTrigger(in: textView)
            defer { dismissMenus() }

            switch command.type {
            case .writingAI:
                NotificationCenter.default.post(name: .contentFocusOpenWritingAI, object: nil)
                return
            case .image:
                guard parent.allowImages else { return }
                presentImagePicker(for: textView)
                return
            case .elements, .newElement:
                // Submenu navigation is handled by the menu itself.
                return
            default:
                break
            }

            guard let handler = parent.onSlashCommandSelected else { return }
            beginAwaitingExternalContent()
            let handled = handler(command, plainTextForBinding(from: textView))
            if !handled {
                cancelAwaitingExternalContent()
            }
        }

        @objc private func handleToggleFormatting(_ notification: Notification) {
            guard let textView = activeTextView,
                  textView.window?.firstResponder === textView,
                  let type = notification.userInfo?["type"] as? FormattingType else {
                return
            }

            // Ensure editor has focus (button click may have stolen it)
            if textView.window?.firstResponder !== textView {
                textView.window?.makeFirstResponder(textView)
            }

            applyFormatting(type, to: textView)
        }

        // MARK: - Inline colour (ink / highlight / link)

        @objc private func handleApplyInlineStyle(_ notification: Notification) {
            guard let textView = activeTextView,
                  textView.window?.firstResponder === textView else { return }
            if let target = notification.userInfo?["targetEditorID"] as? String,
               !target.isEmpty, target != parent.editorTargetID {
                return
            }
            if let ink = notification.userInfo?["ink"] as? String {
                applyInlineInk(ink.isEmpty ? nil : ink, to: textView)
            } else if let highlight = notification.userInfo?["highlight"] as? String {
                applyInlineHighlight(highlight.isEmpty ? nil : highlight, to: textView)
            } else if let link = notification.userInfo?["link"] as? String {
                applyInlineLink(link.isEmpty ? nil : link, to: textView)
            }
        }

        private var defaultInkColor: NSColor {
            parent.overrideTextColor ?? (parent.darkMode ? NSColor.white : NSColor(DS.documentText))
        }

        /// Ink: stamps the tone colour + `CosmoInkID` over the selection, or
        /// into the typing attributes when the caret is collapsed. nil
        /// restores the default ink.
        private func applyInlineInk(_ toneID: String?, to textView: CosmoTextView) {
            let range = textView.selectedRange()
            let color: NSColor
            if let toneID, RichInlineColor.isKnownTone(toneID) {
                color = NSColor(NoteInkPalette.tone(toneID).ink(darkMode: parent.darkMode))
            } else {
                color = defaultInkColor
            }
            if range.length > 0, let storage = textView.textStorage {
                storage.beginEditing()
                storage.enumerateAttribute(RichDocumentAttributeKeys.entityType, in: range, options: []) { value, subrange, _ in
                    guard value == nil else { return } // mentions keep their own colour
                    storage.addAttribute(.foregroundColor, value: color, range: subrange)
                    if let toneID {
                        storage.addAttribute(RichDocumentAttributeKeys.inkID, value: toneID, range: subrange)
                    } else {
                        storage.removeAttribute(RichDocumentAttributeKeys.inkID, range: subrange)
                    }
                }
                storage.endEditing()
                TextKitEditorRepresentable.reclearChecklistGlyphs(in: storage, range: range)
                textView.didChangeText()
            } else {
                var attributes = textView.typingAttributes
                attributes[.foregroundColor] = color
                if let toneID { attributes[RichDocumentAttributeKeys.inkID] = toneID } else { attributes[RichDocumentAttributeKeys.inkID] = nil }
                textView.typingAttributes = attributes
            }
            syncBindings(from: textView)
        }

        /// Highlight: toggles — applying the tone the whole selection already
        /// carries clears it (the ⇧⌘H rhythm).
        private func applyInlineHighlight(_ toneID: String?, to textView: CosmoTextView) {
            let range = textView.selectedRange()
            var resolvedTone = toneID
            if let toneID, range.length > 0, let storage = textView.textStorage {
                var allCarryTone = true
                storage.enumerateAttribute(RichDocumentAttributeKeys.highlightID, in: range, options: []) { value, _, stop in
                    if (value as? String) != toneID { allCarryTone = false; stop.pointee = true }
                }
                if allCarryTone { resolvedTone = nil }
            }
            let wash: NSColor? = resolvedTone.flatMap { id in
                guard RichInlineColor.isKnownTone(id) else { return nil }
                return NSColor(NoteInkPalette.tone(id).ink(darkMode: parent.darkMode)).withAlphaComponent(parent.darkMode ? 0.28 : 0.18)
            }
            if range.length > 0, let storage = textView.textStorage {
                storage.beginEditing()
                if let wash, let resolvedTone {
                    storage.addAttribute(.backgroundColor, value: wash, range: range)
                    storage.addAttribute(RichDocumentAttributeKeys.highlightID, value: resolvedTone, range: range)
                } else {
                    storage.removeAttribute(.backgroundColor, range: range)
                    storage.removeAttribute(RichDocumentAttributeKeys.highlightID, range: range)
                }
                storage.endEditing()
                textView.didChangeText()
            } else {
                var attributes = textView.typingAttributes
                if let wash, let resolvedTone {
                    attributes[.backgroundColor] = wash
                    attributes[RichDocumentAttributeKeys.highlightID] = resolvedTone
                } else {
                    attributes[.backgroundColor] = nil
                    attributes[RichDocumentAttributeKeys.highlightID] = nil
                }
                textView.typingAttributes = attributes
            }
            syncBindings(from: textView)
        }

        private func applyInlineLink(_ href: String?, to textView: CosmoTextView) {
            let range = textView.selectedRange()
            guard range.length > 0, let storage = textView.textStorage else { return }
            storage.beginEditing()
            if let href, let url = URL(string: href) {
                storage.addAttribute(.link, value: url, range: range)
            } else {
                storage.removeAttribute(.link, range: range)
            }
            storage.endEditing()
            textView.didChangeText()
            syncBindings(from: textView)
        }

        // MARK: - Table cell mode

        /// Cell-mode command routing. Returns nil when the selector is not a
        /// cell command so normal routing continues.
        private func handleTableCellCommand(_ selector: Selector, in textView: NSTextView) -> Bool? {
            func navigate(_ direction: RichTableDirection) -> Bool {
                let textLength = (textView.string as NSString).length
                let offsetFromEnd = max(0, textLength - textView.selectedRange().location)
                return parent.onBoundaryCommand?(.tableNavigate(
                    direction,
                    caretUTF16OffsetFromEnd: offsetFromEnd,
                    livePlainText: textView.string
                )) == true
            }
            let selection = textView.selectedRange()
            let textLength = (textView.string as NSString).length
            let atStart = selection.length == 0 && selection.location == 0
            let atEnd = selection.length == 0 && selection.location >= textLength

            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                _ = navigate(.nextCell)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                _ = navigate(.previousCell)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                if parent.menusVisible?() == true { dismissMenus() }
                let offsetFromEnd = max(0, textLength - selection.location)
                _ = parent.onBoundaryCommand?(.tableReturn(
                    caretUTF16OffsetFromEnd: offsetFromEnd,
                    livePlainText: textView.string
                ))
                return true
            case #selector(NSResponder.insertLineBreak(_:)):
                textView.insertText("\u{2028}", replacementRange: textView.selectedRange())
                syncBindings(from: textView)
                return true
            case #selector(NSResponder.moveUp(_:)):
                return selectionIsOnFirstLine(in: textView) && navigate(.up) ? true : nil
            case #selector(NSResponder.moveDown(_:)):
                return selectionIsOnLastLine(in: textView) && navigate(.down) ? true : nil
            case #selector(NSResponder.moveLeft(_:)), #selector(NSResponder.moveBackward(_:)):
                return atStart && navigate(.left) ? true : nil
            case #selector(NSResponder.moveRight(_:)), #selector(NSResponder.moveForward(_:)):
                return atEnd && navigate(.right) ? true : nil
            case #selector(NSResponder.moveToBeginningOfDocument(_:)):
                return parent.onBoundaryCommand?(.tableEdge(.up)) == true ? true : nil
            case #selector(NSResponder.moveToEndOfDocument(_:)):
                return parent.onBoundaryCommand?(.tableEdge(.down)) == true ? true : nil
            case #selector(NSResponder.moveToBeginningOfLine(_:)), #selector(NSResponder.moveToLeftEndOfLine(_:)):
                return atStart && parent.onBoundaryCommand?(.tableEdge(.left)) == true ? true : nil
            case #selector(NSResponder.moveToEndOfLine(_:)), #selector(NSResponder.moveToRightEndOfLine(_:)):
                return atEnd && parent.onBoundaryCommand?(.tableEdge(.right)) == true ? true : nil
            default:
                return nil
            }
        }

        /// A tabular paste in a cell → the table fills cells from here;
        /// inline text → normal insertion. Returns true when consumed.
        func performTableCellPaste(_ imported: ClipboardImport, in textView: CosmoTextView) -> Bool {
            func grid(fromBlocks blocks: [RichBlock]) -> [[[RichInlineNode]]] {
                if blocks.count == 1, blocks[0].kind == .table, let table = blocks[0].table {
                    return grid(fromTable: table)
                }
                return blocks.map { block in
                    if block.kind == .table, let table = block.table {
                        return [[RichInlineNode.text(table.markdown)]]
                    }
                    return [block.inlines]
                }
            }
            func grid(fromTable table: RichTable) -> [[[RichInlineNode]]] {
                table.rows.map { row in row.cells.map { $0.isCovered ? [] : $0.inlines } }
            }
            func emit(_ grid: [[[RichInlineNode]]]) -> Bool {
                guard !grid.isEmpty else { return false }
                return parent.onBoundaryCommand?(.tablePasteGrid(grid: grid, livePlainText: textView.string)) == true
            }
            switch imported {
            case .table(let table):
                return emit(grid(fromTable: table))
            case .blocks(let blocks):
                if blocks.count == 1, blocks[0].kind != .table {
                    // One block: inline paste of its text.
                    return insertInlineNodes(blocks[0].inlines, in: textView)
                }
                return emit(grid(fromBlocks: blocks))
            case .inline(let nodes):
                return insertInlineNodes(nodes, in: textView)
            case .text(let text):
                if text.containsHardNewline {
                    let rows = text.replacingOccurrences(of: "\r\n", with: "\n")
                        .split(separator: "\n", omittingEmptySubsequences: false)
                        .map { [[RichInlineNode.text(String($0))]] }
                    return emit(rows)
                }
                return false
            case .none:
                return false
            }
        }

        /// Inserts rich inline runs at the caret with the editor's own fonts
        /// (marks and inks survive; hard newlines become soft breaks).
        private func insertInlineNodes(_ nodes: [RichInlineNode], in textView: CosmoTextView) -> Bool {
            guard !nodes.isEmpty else { return false }
            var block = RichBlock(kind: .paragraph)
            block.inlines = nodes.map { node in
                var copy = node
                copy.text = node.text?.replacingHardNewlinesWithLineSeparators()
                return copy
            }
            let attributed = RichDocumentSerializer.attributedString(
                from: RichDocument(blocks: [block]),
                fontSize: parent.fontSize,
                darkMode: parent.darkMode,
                baseFontWeight: parent.baseFontWeight
            )
            let designed = EditorFontPolicy.applyingDesign(parent.fontDesign, to: attributed)
            let range = textView.selectedRange()
            guard textView.shouldChangeText(in: range, replacementString: designed.string) else { return false }
            textView.textStorage?.replaceCharacters(in: range, with: designed)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: range.location + designed.length, length: 0))
            return true
        }

        // MARK: - Formatting

        private func applyFormatting(_ type: FormattingType, to textView: CosmoTextView) {
            switch type {
            case .bold, .italic:
                toggleFontTrait(type == .bold ? .boldFontMask : .italicFontMask, in: textView)
            case .underline:
                toggleAttribute(.underlineStyle, onValue: NSUnderlineStyle.single.rawValue, in: textView)
            case .strikethrough:
                toggleAttribute(.strikethroughStyle, onValue: NSUnderlineStyle.single.rawValue, in: textView)
            case .heading1:
                applyHeading(level: 1, collapsible: false, textView: textView)
            case .heading2:
                applyHeading(level: 2, collapsible: false, textView: textView)
            case .heading3:
                applyHeading(level: 3, collapsible: false, textView: textView)
            case .bulletList:
                toggleBlockPrefix("• ", kind: .bulletList, in: textView)
            case .numberedList:
                toggleNumberedList(in: textView)
            case .checklist:
                toggleChecklist(in: textView)
            }

            syncBindings(from: textView)
        }

        private func toggleFontTrait(_ trait: NSFontTraitMask, in textView: NSTextView) {
            let range = textView.selectedRange()

            if range.length > 0 {
                textView.textStorage?.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
                    let currentFont = (value as? NSFont) ?? NSFont.systemFont(ofSize: self.parent.fontSize)
                    let currentTraits = currentFont.fontDescriptor.symbolicTraits
                    let shouldRemove = (trait == .boldFontMask && currentTraits.contains(.bold)) ||
                        (trait == .italicFontMask && currentTraits.contains(.italic))
                    let newFont = shouldRemove
                        ? self.fontByRemovingTrait(trait, from: currentFont)
                        : NSFontManager.shared.convert(currentFont, toHaveTrait: trait)
                    textView.textStorage?.addAttribute(.font, value: newFont, range: subrange)
                }
                return
            }

            var attributes = textView.typingAttributes
            let currentFont = (attributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: parent.fontSize)
            let currentTraits = currentFont.fontDescriptor.symbolicTraits
            let shouldRemove = (trait == .boldFontMask && currentTraits.contains(.bold)) ||
                (trait == .italicFontMask && currentTraits.contains(.italic))
            attributes[.font] = shouldRemove
                ? fontByRemovingTrait(trait, from: currentFont)
                : NSFontManager.shared.convert(currentFont, toHaveTrait: trait)
            textView.typingAttributes = attributes
        }

        private func fontByRemovingTrait(_ trait: NSFontTraitMask, from font: NSFont) -> NSFont {
            var traits = font.fontDescriptor.symbolicTraits
            if trait == .boldFontMask {
                traits.remove(.bold)
            } else if trait == .italicFontMask {
                traits.remove(.italic)
            }

            let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
            if let converted = NSFont(descriptor: descriptor, size: font.pointSize) {
                return converted
            }

            return NSFont.systemFont(ofSize: font.pointSize)
        }

        private func toggleAttribute(_ key: NSAttributedString.Key, onValue: Int, in textView: NSTextView) {
            let range = textView.selectedRange()

            if range.length > 0 {
                let current = textView.textStorage?.attribute(key, at: range.location, effectiveRange: nil) as? Int ?? 0
                if current == onValue {
                    textView.textStorage?.removeAttribute(key, range: range)
                } else {
                    textView.textStorage?.addAttribute(key, value: onValue, range: range)
                }
                return
            }

            var attributes = textView.typingAttributes
            let current = attributes[key] as? Int ?? 0
            attributes[key] = current == onValue ? 0 : onValue
            textView.typingAttributes = attributes
        }

        private func applyHeading(level: Int, collapsible: Bool, textView: NSTextView) {
            let font: NSFont

            // GUARD-TWIN of RichDocumentSerializer.blockFont's heading ladder
            // (with seedTypingAttributesForEmptyRow and
            // BlockStaticRowPlaceholder.editorFont) — change all FOUR together.
            switch level {
            case 1:
                font = EditorFontPolicy.font(ofSize: min(34, (parent.fontSize * 1.85).rounded()), weight: .semibold, design: parent.fontDesign)
            case 2:
                font = EditorFontPolicy.font(ofSize: (parent.fontSize * 1.45).rounded(), weight: .semibold, design: parent.fontDesign)
            default:
                font = EditorFontPolicy.font(ofSize: (parent.fontSize * 1.20).rounded(), weight: .medium, design: parent.fontDesign)
            }

            let lineRange = currentLineRange(in: textView)
            let lineText = (textView.string as NSString).substring(with: lineRange)

            // Strip legacy visible prefixes if present (backward compat)
            let existingPrefixes = ["### ", "## ", "# "]
            if let existingPrefix = existingPrefixes.first(where: { lineText.hasPrefix($0) }) {
                textView.textStorage?.replaceCharacters(
                    in: NSRange(location: lineRange.location, length: existingPrefix.count),
                    with: ""
                )
            }

            // A folded heading about to be restamped or removed must surface
            // its hidden section first — restamping alone would strand the
            // stashed blocks in an attribute nothing renders.
            let foldCheckRange = currentLineRange(in: textView)
            if let storage = textView.textStorage,
               foldCheckRange.length > 0,
               boolAttribute(RichDocumentAttributeKeys.headingCollapsed, at: foldCheckRange.location, in: storage) == true {
                _ = expandHeadingInPlace(headingRange: foldCheckRange, in: storage)
            }

            // Check if line already has this exact heading — toggle off.
            // A variant switch (plain ↔ toggle heading) restamps instead.
            let checkRange = currentLineRange(in: textView)
            if checkRange.length > 0,
               let storage = textView.textStorage,
               let currentLevel = storage.attribute(
                   RichDocumentAttributeKeys.headingLevel,
                   at: checkRange.location,
                   effectiveRange: nil
               ) as? Int,
               currentLevel == level,
               (boolAttribute(RichDocumentAttributeKeys.headingCollapsible, at: checkRange.location, in: storage) ?? false) == collapsible {
                // Remove heading — reset to normal
                storage.removeAttribute(RichDocumentAttributeKeys.headingLevel, range: checkRange)
                storage.removeAttribute(RichDocumentAttributeKeys.headingBlockID, range: checkRange)
                storage.removeAttribute(RichDocumentAttributeKeys.headingCollapsed, range: checkRange)
                storage.removeAttribute(RichDocumentAttributeKeys.headingCollapsible, range: checkRange)
                storage.removeAttribute(RichDocumentAttributeKeys.headingCollapsedChildrenJSON, range: checkRange)
                storage.addAttributes([
                    .font: NSFont.systemFont(ofSize: parent.fontSize, weight: parent.baseFontWeight),
                    .foregroundColor: parent.resolvedEditorTextColor,
                    .paragraphStyle: defaultParagraphStyle()
                ], range: checkRange)
                isInHeadingMode = false
                resetToNormalTypingAttributes(textView)
                syncBindings(from: textView)
                return
            }

            // Apply heading attributes (no prefix insertion)
            let updatedLineRange = currentLineRange(in: textView)
            let headingBlockID = existingHeadingBlockID(in: textView, lineRange: updatedLineRange) ?? UUID().uuidString
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4
            paragraphStyle.paragraphSpacing = 12
            // Only collapsible headings reserve the chevron gutter — plain
            // headings sit flush with body text.
            let headingGutter: CGFloat = collapsible ? 34 : 0
            paragraphStyle.firstLineHeadIndent = headingGutter
            paragraphStyle.headIndent = headingGutter
            // Proportional top margin — larger headings get more breathing room above
            switch level {
            case 1: paragraphStyle.paragraphSpacingBefore = 32
            case 2: paragraphStyle.paragraphSpacingBefore = 24
            default: paragraphStyle.paragraphSpacingBefore = 16
            }

            if updatedLineRange.length > 0 {
                textView.textStorage?.addAttributes([
                    .font: font,
                    .foregroundColor: parent.resolvedEditorTextColor,
                    .paragraphStyle: paragraphStyle,
                    RichDocumentAttributeKeys.headingLevel: level,
                    RichDocumentAttributeKeys.headingBlockID: headingBlockID,
                    RichDocumentAttributeKeys.headingCollapsed: NSNumber(value: false),
                    RichDocumentAttributeKeys.headingCollapsible: NSNumber(value: collapsible)
                ], range: updatedLineRange)
            }

            textView.typingAttributes = [
                .font: font,
                .foregroundColor: parent.resolvedEditorTextColor,
                .paragraphStyle: paragraphStyle,
                RichDocumentAttributeKeys.headingLevel: level,
                RichDocumentAttributeKeys.headingBlockID: headingBlockID,
                RichDocumentAttributeKeys.headingCollapsed: NSNumber(value: false),
                RichDocumentAttributeKeys.headingCollapsible: NSNumber(value: collapsible)
            ]
            isInHeadingMode = true

            // Force layout update to prevent clipping (Bug 2)
            if let container = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: container)
            }
            textView.sizeToFit()
            textView.window?.invalidateCursorRects(for: textView)
        }

        private func toggleBlockPrefix(_ prefix: String, kind: RichBlockKind, in textView: NSTextView) {
            let lineRange = currentLineRange(in: textView)
            let lineText = (textView.string as NSString).substring(with: lineRange)
            var newMode: ActiveBlockMode = .none
            if lineText.hasPrefix(prefix) {
                textView.textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: prefix.count), with: "")
                newMode = .none
            } else {
                textView.textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: 0), with: prefix)
                switch kind {
                case .quote: newMode = .quote
                case .bulletList: newMode = .bulletList
                case .checklist: newMode = .checklist
                case .numberedList: newMode = .numberedList
                default: break
                }
            }

            if kind == .quote {
                // Quote blocks use tight paragraph spacing so lines stay visually connected
                let quoteStyle = NSMutableParagraphStyle()
                quoteStyle.lineSpacing = parent.compact ? 2 : 4
                quoteStyle.paragraphSpacing = parent.compact ? 2 : 4
                var quoteAttrs = textView.typingAttributes
                quoteAttrs[.paragraphStyle] = quoteStyle
                textView.typingAttributes = quoteAttrs

                let updatedLineRange = currentLineRange(in: textView)
                if updatedLineRange.length > 0 {
                    textView.textStorage?.addAttribute(.paragraphStyle, value: quoteStyle, range: updatedLineRange)
                }
            } else {
                resetToNormalTypingAttributes(textView)

                // Stamp normal paragraph attributes on the entire line to clear any
                // inherited heading/bold attributes from adjacent text storage
                let updatedLineRange = currentLineRange(in: textView)
                if updatedLineRange.length > 0 {
                    textView.textStorage?.addAttributes([
                        .font: NSFont.systemFont(ofSize: parent.fontSize, weight: parent.baseFontWeight),
                        .foregroundColor: parent.resolvedEditorTextColor,
                        .paragraphStyle: defaultParagraphStyle()
                    ], range: updatedLineRange)
                    textView.textStorage?.removeAttribute(RichDocumentAttributeKeys.headingLevel, range: updatedLineRange)
                    textView.textStorage?.removeAttribute(RichDocumentAttributeKeys.headingBlockID, range: updatedLineRange)
                    textView.textStorage?.removeAttribute(RichDocumentAttributeKeys.headingCollapsed, range: updatedLineRange)
                    textView.textStorage?.removeAttribute(RichDocumentAttributeKeys.headingCollapsible, range: updatedLineRange)
                    textView.textStorage?.removeAttribute(RichDocumentAttributeKeys.headingCollapsedChildrenJSON, range: updatedLineRange)
                    if kind == .checklist, let storage = textView.textStorage {
                        TextKitEditorRepresentable.reclearChecklistGlyphs(in: storage, range: updatedLineRange)
                    }
                }
            }

            // Set block mode AFTER reset so it isn't overwritten
            activeBlockMode = newMode

            // Force layout update to prevent clipping (Bug 2)
            if let container = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: container)
            }
            textView.sizeToFit()
        }

        private func toggleNumberedList(in textView: NSTextView) {
            let lineRange = currentLineRange(in: textView)
            let lineText = (textView.string as NSString).substring(with: lineRange)
            var newMode: ActiveBlockMode = .none
            if let match = lineText.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                let count = lineText.distance(from: lineText.startIndex, to: match.upperBound)
                textView.textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: count), with: "")
                newMode = .none
            } else {
                textView.textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: 0), with: "1. ")
                newMode = .numberedList
            }
            resetToNormalTypingAttributes(textView)

            // Clear inherited heading/bold attributes from the line
            let updatedLineRange = currentLineRange(in: textView)
            if updatedLineRange.length > 0 {
                textView.textStorage?.addAttributes([
                    .font: NSFont.systemFont(ofSize: parent.fontSize, weight: parent.baseFontWeight),
                    .foregroundColor: parent.resolvedEditorTextColor,
                    .paragraphStyle: defaultParagraphStyle()
                ], range: updatedLineRange)
                textView.textStorage?.removeAttribute(RichDocumentAttributeKeys.headingLevel, range: updatedLineRange)
                textView.textStorage?.removeAttribute(RichDocumentAttributeKeys.headingBlockID, range: updatedLineRange)
                textView.textStorage?.removeAttribute(RichDocumentAttributeKeys.headingCollapsed, range: updatedLineRange)
                textView.textStorage?.removeAttribute(RichDocumentAttributeKeys.headingCollapsible, range: updatedLineRange)
                textView.textStorage?.removeAttribute(RichDocumentAttributeKeys.headingCollapsedChildrenJSON, range: updatedLineRange)
            }

            activeBlockMode = newMode

            if let container = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: container)
            }
            textView.sizeToFit()
        }

        private func toggleChecklist(in textView: NSTextView) {
            let lineRange = currentLineRange(in: textView)
            let lineText = (textView.string as NSString).substring(with: lineRange)
            var newMode: ActiveBlockMode = .none
            if lineText.hasPrefix("☐ ") || lineText.hasPrefix("☑ ") {
                textView.textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: 2), with: "")
                newMode = .none
            } else {
                textView.textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: 0), with: "☐ ")
                // Keep the stored glyph invisible — the circle checkbox is
                // painted over its rect by drawChecklistCheckboxes.
                textView.textStorage?.addAttribute(
                    .foregroundColor,
                    value: NSColor.clear,
                    range: NSRange(location: lineRange.location, length: 1)
                )
                newMode = .checklist
            }
            resetToNormalTypingAttributes(textView)
            activeBlockMode = newMode

            if let container = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: container)
            }
            textView.sizeToFit()
        }

        private func currentLineRange(in textView: NSTextView) -> NSRange {
            (textView.string as NSString).lineRange(for: textView.selectedRange())
        }

        private func trimmingTrailingNewline(from range: NSRange, in string: NSString) -> NSRange {
            var length = min(range.length, max(0, string.length - range.location))
            while length > 0 {
                let character = string.substring(with: NSRange(location: range.location + length - 1, length: 1))
                if character == "\n" || character == "\r" {
                    length -= 1
                } else {
                    break
                }
            }
            return NSRange(location: range.location, length: length)
        }

        private func existingHeadingBlockID(in textView: NSTextView, lineRange: NSRange) -> String? {
            guard let storage = textView.textStorage,
                  lineRange.location < storage.length else {
                return nil
            }
            if let value = storage.attribute(
                RichDocumentAttributeKeys.headingBlockID,
                at: lineRange.location,
                effectiveRange: nil
            ) as? String {
                return value
            }
            if let value = storage.attribute(
                RichDocumentAttributeKeys.headingBlockID,
                at: lineRange.location,
                effectiveRange: nil
            ) as? UUID {
                return value.uuidString
            }
            return nil
        }

        private func ensureHeadingBlockID(in storage: NSTextStorage, headingRange: NSRange) {
            guard headingRange.length > 0,
                  headingRange.location < storage.length,
                  headingBlockID(in: storage, location: headingRange.location) == nil else {
                return
            }
            storage.addAttributes([
                RichDocumentAttributeKeys.headingBlockID: UUID().uuidString,
                RichDocumentAttributeKeys.headingCollapsed: NSNumber(value: false)
            ], range: headingRange)
        }

        private func headingBlockID(in storage: NSTextStorage, location: Int) -> UUID? {
            guard location < storage.length else { return nil }
            let value = storage.attribute(
                RichDocumentAttributeKeys.headingBlockID,
                at: location,
                effectiveRange: nil
            )
            if let value = value as? UUID { return value }
            if let value = value as? String { return UUID(uuidString: value) }
            return nil
        }

        private func headingRange(for headingID: UUID, in textView: NSTextView) -> NSRange? {
            guard let storage = textView.textStorage,
                  storage.length > 0 else {
                return nil
            }

            let string = storage.string as NSString
            let fullRange = NSRange(location: 0, length: storage.length)
            var lineStart = 0

            while lineStart < storage.length {
                let lineRange = string.lineRange(for: NSRange(location: lineStart, length: 0))
                let safeRange = NSIntersectionRange(lineRange, fullRange)
                let trimmedRange = trimmingTrailingNewline(from: safeRange, in: string)

                if trimmedRange.length > 0,
                   let id = headingBlockID(in: storage, location: trimmedRange.location),
                   id == headingID {
                    return trimmedRange
                }

                lineStart = lineRange.location + lineRange.length
                if lineStart <= safeRange.location {
                    break
                }
            }

            return nil
        }

        private func scrollRangeIntoAncestorViewport(_ range: NSRange, in textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  let ancestorScrollView = textView.nearestAncestorScrollView(excluding: textView.enclosingScrollView),
                  let documentView = ancestorScrollView.documentView else {
                textView.scrollRangeToVisible(range)
                return
            }

            layoutManager.ensureLayout(for: textContainer)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            if rect.isEmpty {
                rect = CGRect(x: 0, y: 0, width: 1, height: textView.font?.pointSize ?? parent.fontSize)
            }

            let textViewRect = CGRect(
                x: rect.origin.x + textView.textContainerOrigin.x,
                y: rect.origin.y + textView.textContainerOrigin.y,
                width: max(rect.width, 1),
                height: max(rect.height, textView.font?.pointSize ?? parent.fontSize)
            )
            let targetRect = textView.convert(textViewRect, to: documentView)
            let visibleRect = ancestorScrollView.documentVisibleRect
            let visibleHeight = max(visibleRect.height, 1)
            let documentHeight = max(documentView.bounds.height, visibleHeight)
            let maxY = max(0, documentHeight - visibleHeight)
            let targetY = min(max(0, targetRect.minY - visibleHeight * 0.18), maxY)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ancestorScrollView.contentView.animator().setBoundsOrigin(NSPoint(x: visibleRect.minX, y: targetY))
            }
            ancestorScrollView.reflectScrolledClipView(ancestorScrollView.contentView)
        }

        private func cursorRectInAncestorDocument(
            for textView: NSTextView,
            selectedRange: NSRange,
            ancestorScrollView: NSScrollView
        ) -> CGRect? {
            guard !textView.string.isEmpty,
                  let documentView = ancestorScrollView.documentView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return nil
            }

            layoutManager.ensureLayout(for: textContainer)
            let textLength = textView.string.utf16.count
            let characterLocation = min(max(selectedRange.location, 0), textLength)
            let nsText = textView.string as NSString

            var usesExtraLineFragment = false
            var cursorRect: CGRect
            if characterLocation == textLength,
               textLength > 0,
               nsText.substring(with: NSRange(location: textLength - 1, length: 1)) == "\n",
               !layoutManager.extraLineFragmentRect.isEmpty {
                usesExtraLineFragment = true
                cursorRect = layoutManager.extraLineFragmentRect
            } else {
                let measuredLocation = min(characterLocation, max(textLength - 1, 0))
                let glyphRange = layoutManager.glyphRange(
                    forCharacterRange: NSRange(location: measuredLocation, length: 1),
                    actualCharacterRange: nil
                )
                cursorRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            }

            if cursorRect.isEmpty {
                cursorRect = CGRect(x: 0, y: 0, width: 1, height: textView.font?.pointSize ?? parent.fontSize)
            } else if characterLocation >= textLength, !usesExtraLineFragment {
                cursorRect.origin.x = cursorRect.maxX
                cursorRect.size.width = 1
            } else {
                cursorRect.size.width = max(cursorRect.width, 1)
            }
            cursorRect.size.height = max(cursorRect.height, textView.font?.pointSize ?? parent.fontSize)

            let textContainerOrigin = textView.textContainerOrigin
            let rectInTextView = cursorRect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            return textView.convert(rectInTextView, to: documentView)
        }

        private func boolAttribute(_ key: NSAttributedString.Key, at location: Int, in storage: NSTextStorage) -> Bool? {
            guard location < storage.length else { return nil }
            let value = storage.attribute(key, at: location, effectiveRange: nil)
            if let value = value as? Bool { return value }
            if let value = value as? NSNumber { return value.boolValue }
            return nil
        }

        private func intAttribute(_ key: NSAttributedString.Key, at location: Int, in storage: NSTextStorage) -> Int? {
            guard location < storage.length else { return nil }
            let value = storage.attribute(key, at: location, effectiveRange: nil)
            if let value = value as? Int { return value }
            if let value = value as? NSNumber { return value.intValue }
            return nil
        }

        private func resetToNormalTypingAttributes(_ textView: NSTextView) {
            isInHeadingMode = false
            activeBlockMode = .none
            textView.typingAttributes = [
                .font: EditorFontPolicy.font(ofSize: parent.fontSize, weight: parent.baseFontWeight, design: parent.fontDesign),
                .foregroundColor: parent.resolvedEditorTextColor,
                .paragraphStyle: defaultParagraphStyle()
            ]
        }

        /// Reset only inline formatting (bold/italic/heading font) but preserve block mode
        /// so bullet/list continuation still works on the new line.
        private func resetInlineFormattingOnly(_ textView: NSTextView) {
            isInHeadingMode = false
            var attrs = textView.typingAttributes
            attrs[.font] = EditorFontPolicy.font(ofSize: parent.fontSize, weight: parent.baseFontWeight, design: parent.fontDesign)
            attrs[.foregroundColor] = parent.resolvedEditorTextColor
            attrs.removeValue(forKey: RichDocumentAttributeKeys.headingLevel)
            attrs.removeValue(forKey: RichDocumentAttributeKeys.headingBlockID)
            attrs.removeValue(forKey: RichDocumentAttributeKeys.headingCollapsed)
            attrs.removeValue(forKey: RichDocumentAttributeKeys.headingCollapsible)
            attrs.removeValue(forKey: RichDocumentAttributeKeys.headingCollapsedChildrenJSON)
            // Preserve existing paragraphStyle (block indentation) if in a list
            if attrs[.paragraphStyle] == nil {
                attrs[.paragraphStyle] = defaultParagraphStyle()
            }
            textView.typingAttributes = attrs
        }

        private func defaultParagraphStyle() -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            if parent.singleLine || parent.titleConfiguration != nil {
                style.lineSpacing = 0
                style.paragraphSpacing = 0
            } else if parent.compact {
                style.lineSpacing = max(0, 4 + parent.lineSpacingAdjustment)
                style.paragraphSpacing = 8
            } else {
                style.lineSpacing = max(0, 6 + parent.lineSpacingAdjustment)
                style.paragraphSpacing = 12
            }
            return style
        }

        // MARK: - Insertion

        private func insertText(_ text: String, position: String, into textView: NSTextView) {
            guard let storage = textView.textStorage else { return }

            let range: NSRange
            switch position {
            case EditorCommandBus.InsertPosition.endOfDocument.rawValue:
                range = NSRange(location: storage.length, length: 0)
            case EditorCommandBus.InsertPosition.newParagraph.rawValue:
                range = textView.selectedRange()
                storage.replaceCharacters(in: range, with: "\n\n\(text)")
                textView.setSelectedRange(NSRange(location: range.location + text.count + 2, length: 0))
                syncBindings(from: textView)
                return
            default:
                range = textView.selectedRange()
            }

            storage.replaceCharacters(in: range, with: text)
            textView.setSelectedRange(NSRange(location: range.location + text.count, length: 0))
            syncBindings(from: textView)
        }

        private func insertElement(_ definition: DocumentElementDefinition, at insertionPoint: Int, in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }

            let elementBlock = RichBlock.element(definition, instanceTitle: definition.title)
            let elementAttributedString = RichDocumentSerializer.attributedString(
                from: RichDocument(blocks: [elementBlock]),
                fontSize: parent.fontSize,
                darkMode: parent.darkMode,
                singleLine: parent.singleLine,
                baseFontWeight: parent.baseFontWeight,
                titleMode: parent.titleConfiguration != nil
            )
            let replacement = NSMutableAttributedString()
            let safeInsertionPoint = max(0, min(insertionPoint, storage.length))
            if safeInsertionPoint > 0 {
                let previousCharacter = (storage.string as NSString).substring(
                    with: NSRange(location: safeInsertionPoint - 1, length: 1)
                )
                if previousCharacter != "\n" {
                    replacement.append(NSAttributedString(string: "\n", attributes: elementInsertionBaseAttributes()))
                }
            }

            replacement.append(elementAttributedString)
            replacement.append(NSAttributedString(string: "\n", attributes: elementInsertionBaseAttributes()))

            let replacementRange = NSRange(location: safeInsertionPoint, length: 0)
            guard textView.shouldChangeText(in: replacementRange, replacementString: replacement.string) else {
                return
            }

            isApplyingStructuralEdit = true
            defer { isApplyingStructuralEdit = false }
            storage.replaceCharacters(in: replacementRange, with: replacement)
            textView.setSelectedRange(NSRange(location: safeInsertionPoint + replacement.length, length: 0))
            textView.didChangeText()
            resetToNormalTypingAttributes(textView)
            syncStructuralEditBindings(from: textView)
        }

        func toggleElementCollapse(instanceID: UUID, in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }

            let selectedRange = textView.selectedRange()
            let document = RichDocumentSerializer.document(from: storage)
            let updated = DocumentElementMutation.toggledCollapse(instanceID: instanceID, in: document)
            guard updated != document else { return }

            let serialized = RichDocumentSerializer.attributedString(
                from: updated,
                fontSize: parent.fontSize,
                darkMode: parent.darkMode,
                singleLine: parent.singleLine,
                baseFontWeight: parent.baseFontWeight,
                titleMode: parent.titleConfiguration != nil
            )

            // Structural rebuild swaps the whole buffer out-of-band; drop the
            // stale per-view undo stack so a later ⌘Z can't hit a freed target.
            replaceStorageDroppingUndo(textView, with: serialized)
            // The swap wiped painted temporary attributes and backgrounds —
            // reset the bookkeeping so the next band/polish pass restamps.
            noteStorageWasReplacedOutOfBand()
            let safeLocation = min(selectedRange.location, storage.length)
            let safeLength = min(selectedRange.length, storage.length - safeLocation)
            textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
            resetToNormalTypingAttributes(textView)
            syncStructuralEditBindings(from: textView)

            if let container = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: container)
            }
            textView.needsDisplay = true
            textView.sizeToFit()
            textView.window?.invalidateCursorRects(for: textView)
            notifyContentHeightChange(for: textView)
        }

        func toggleHeadingCollapse(headingRange: NSRange, in textView: NSTextView) {
            guard let storage = textView.textStorage,
                  storage.length > 0,
                  headingRange.location < storage.length else {
                return
            }

            ensureHeadingBlockID(in: storage, headingRange: headingRange)

            let selectedRange = textView.selectedRange()
            let fallbackLocation: Int
            if boolAttribute(RichDocumentAttributeKeys.headingCollapsed, at: headingRange.location, in: storage) == true {
                fallbackLocation = expandHeadingInPlace(headingRange: headingRange, in: storage)
            } else {
                fallbackLocation = collapseHeadingInPlace(headingRange: headingRange, in: storage)
            }
            parent.applyStorageOverrides(storage)
            let safeLocation = min(selectedRange.location, storage.length)
            let safeLength = min(selectedRange.length, storage.length - safeLocation)
            let restoredRange = NSRange(
                location: safeLocation < storage.length ? safeLocation : fallbackLocation,
                length: safeLength
            )
            textView.setSelectedRange(restoredRange)
            resetToNormalTypingAttributes(textView)

            if let container = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: container)
            }
            textView.needsDisplay = true
            syncStructuralEditBindings(from: textView)
        }

        private func collapseHeadingInPlace(headingRange: NSRange, in storage: NSTextStorage) -> Int {
            guard let level = intAttribute(RichDocumentAttributeKeys.headingLevel, at: headingRange.location, in: storage) else {
                return min(NSMaxRange(headingRange), storage.length)
            }
            let string = storage.string as NSString
            let headingLineRange = string.lineRange(for: headingRange)
            let contentRange = sectionContentRange(after: headingLineRange, headingLevel: level, in: storage)
            let hiddenBlocks: [RichBlock]
            if contentRange.length > 0 {
                hiddenBlocks = RichDocumentSerializer.document(from: storage.attributedSubstring(from: contentRange)).blocks
            } else {
                hiddenBlocks = []
            }
            var headingAttributes: [NSAttributedString.Key: Any] = [
                RichDocumentAttributeKeys.headingCollapsed: NSNumber(value: true)
            ]
            if let data = try? JSONEncoder().encode(hiddenBlocks),
               let json = String(data: data, encoding: .utf8) {
                headingAttributes[RichDocumentAttributeKeys.headingCollapsedChildrenJSON] = json
            }

            storage.beginEditing()
            storage.addAttributes(headingAttributes, range: headingRange)
            if contentRange.length > 0 {
                storage.deleteCharacters(in: contentRange)
            }
            storage.endEditing()
            return min(NSMaxRange(headingLineRange), storage.length)
        }

        private func expandHeadingInPlace(headingRange: NSRange, in storage: NSTextStorage) -> Int {
            let string = storage.string as NSString
            let headingLineRange = string.lineRange(for: headingRange)
            let insertionLocation = min(NSMaxRange(headingLineRange), storage.length)
            let collapsedBlocks = collapsedBlocksAttribute(in: storage, at: headingRange.location)
            let restored = RichDocumentSerializer.attributedString(
                from: RichDocument(blocks: collapsedBlocks),
                fontSize: parent.fontSize,
                darkMode: parent.darkMode,
                singleLine: parent.singleLine,
                baseFontWeight: parent.baseFontWeight,
                titleMode: parent.titleConfiguration != nil
            )

            storage.beginEditing()
            storage.addAttribute(RichDocumentAttributeKeys.headingCollapsed, value: NSNumber(value: false), range: headingRange)
            storage.removeAttribute(RichDocumentAttributeKeys.headingCollapsedChildrenJSON, range: headingRange)
            if restored.length > 0 {
                if headingLineRange.length == headingRange.length && insertionLocation == storage.length {
                    storage.insert(NSAttributedString(string: "\n", attributes: elementInsertionBaseAttributes()), at: insertionLocation)
                    storage.insert(restored, at: insertionLocation + 1)
                } else {
                    storage.insert(restored, at: insertionLocation)
                }
            }
            storage.endEditing()
            return insertionLocation
        }

        private func sectionContentRange(after headingLineRange: NSRange, headingLevel: Int, in storage: NSTextStorage) -> NSRange {
            let string = storage.string as NSString
            let fullRange = NSRange(location: 0, length: storage.length)
            var cursor = min(NSMaxRange(headingLineRange), storage.length)
            let start = cursor

            while cursor < storage.length {
                let lineRange = string.lineRange(for: NSRange(location: cursor, length: 0))
                let safeRange = NSIntersectionRange(lineRange, fullRange)
                let trimmedRange = trimmingTrailingNewline(from: safeRange, in: string)
                if trimmedRange.length > 0,
                   let nextLevel = intAttribute(RichDocumentAttributeKeys.headingLevel, at: trimmedRange.location, in: storage),
                   nextLevel <= headingLevel {
                    break
                }
                cursor = lineRange.location + lineRange.length
                if cursor <= safeRange.location {
                    break
                }
            }

            return NSRange(location: start, length: max(0, cursor - start))
        }

        private func collapsedBlocksAttribute(in storage: NSTextStorage, at location: Int) -> [RichBlock] {
            guard location < storage.length,
                  let json = storage.attribute(
                    RichDocumentAttributeKeys.headingCollapsedChildrenJSON,
                    at: location,
                    effectiveRange: nil
                  ) as? String,
                  let data = json.data(using: .utf8),
                  let blocks = try? JSONDecoder().decode([RichBlock].self, from: data) else {
                return []
            }
            return blocks
        }

        private func elementInsertionBaseAttributes() -> [NSAttributedString.Key: Any] {
            [
                .font: NSFont.systemFont(ofSize: parent.fontSize, weight: parent.baseFontWeight),
                .foregroundColor: parent.resolvedEditorTextColor,
                .paragraphStyle: defaultParagraphStyle()
            ]
        }

        private func replaceCurrentMentionOrSelection(in textView: NSTextView, mention: RichMention) {
            guard let storage = textView.textStorage else { return }

            let replacementRange: NSRange
            if let mentionStartIndex,
               mentionStartIndex <= textView.selectedRange().location {
                replacementRange = NSRange(
                    location: mentionStartIndex,
                    length: textView.selectedRange().location - mentionStartIndex
                )
            } else {
                replacementRange = textView.selectedRange()
            }

            let mentionString = NSMutableAttributedString(
                string: mention.displayText,
                attributes: mentionAttributes(for: mention)
            )
            mentionString.append(NSAttributedString(
                string: " ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: parent.fontSize),
                    .foregroundColor: parent.resolvedEditorTextColor
                ]
            ))

            storage.replaceCharacters(in: replacementRange, with: mentionString)
            let newCursor = replacementRange.location + mentionString.length
            textView.setSelectedRange(NSRange(location: newCursor, length: 0))
            mentionStartIndex = nil
            syncBindings(from: textView)
        }

        private func mentionAttributes(for mention: RichMention) -> [NSAttributedString.Key: Any] {
            let color = CosmoMentionColors.nsColor(for: mention.entityType)
            var attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: max(15, parent.fontSize - 1), weight: .semibold),
                .foregroundColor: color,
                .backgroundColor: color.withAlphaComponent(0.12),
                .underlineStyle: 0,
                RichDocumentAttributeKeys.entityType: mention.entityType.rawValue,
                RichDocumentAttributeKeys.entityUUID: mention.entityUUID
            ]

            if let entityID = mention.entityID {
                attributes[RichDocumentAttributeKeys.entityID] = entityID
                attributes[.link] = "cosmo://\(mention.entityType.rawValue)/\(entityID)"
            }

            return attributes
        }

        private func presentImagePicker(for textView: NSTextView) {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.png, .jpeg, .gif, .heic, .tiff, .image]
            panel.title = "Insert Image"

            guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else {
                return
            }

            insertImage(data: data, filename: url.lastPathComponent, into: textView)
        }

        private func insertImage(data: Data, filename: String?, into textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            guard let saved = try? ImageStore.save(data, originalFilename: filename),
                  let image = ImageStore.load(path: saved.path) else {
                return
            }

            let attachment = NSTextAttachment()
            // Crisp bitmap (no height cap); `bounds` drives the on-screen size so the resize
            // overlay can change it with a pure layout update.
            attachment.image = image.scaled(toFit: CGSize(width: min(680, saved.width), height: 10_000))
            let intrinsic = CGSize(width: saved.width, height: saved.height)
            attachment.bounds = CGRect(origin: .zero, size: ImageResizeMath.resolvedSize(displayWidth: nil, intrinsic: intrinsic, maxWidth: 680))

            let attributed = NSMutableAttributedString(attachment: attachment)
            attributed.addAttributes([
                RichDocumentAttributeKeys.imagePath: saved.path
            ], range: NSRange(location: 0, length: attributed.length))

            let replacementRange = textView.selectedRange()
            let prefix = replacementRange.location > 0 && !(textView.string as NSString).substring(with: NSRange(location: replacementRange.location - 1, length: 1)).hasSuffix("\n")
                ? "\n"
                : ""
            let suffix = "\n"

            let wrapped = NSMutableAttributedString(string: prefix)
            wrapped.append(attributed)
            wrapped.append(NSAttributedString(string: suffix))

            storage.replaceCharacters(in: replacementRange, with: wrapped)
            let cursor = replacementRange.location + wrapped.length
            textView.setSelectedRange(NSRange(location: cursor, length: 0))
            syncBindings(from: textView)
        }

        private func insertTextBlock(_ text: String, at location: Int, in textView: NSTextView, appendTrailingNewline: Bool) {
            let prefix = location > 0 && !(textView.string as NSString).substring(with: NSRange(location: location - 1, length: 1)).hasSuffix("\n") ? "\n" : ""
            let suffix = appendTrailingNewline ? "\n" : ""
            let output = prefix + text + suffix
            textView.textStorage?.replaceCharacters(in: NSRange(location: location, length: 0), with: output)
            textView.setSelectedRange(NSRange(location: location + output.count, length: 0))
        }

        // MARK: - Shared helpers

        private var activeTextView: CosmoTextView? {
            textViewReference
        }

        /// A handled boundary command rebuilt this row's document externally —
        /// the text view's content is stale until the rebuild lands. Cancel
        /// any pending write-back so it can't push pre-edit text over the
        /// freshly edited document (the Enter-at-block-start duplication bug).
        func beginAwaitingExternalContent() {
            awaitingExternalContent = true
            deferredSyncWorkItem?.cancel()
            isUpdatingFromTextView = false
            // The cancelled settle owned any pending shrink — a value-
            // identical rebuild (Return at the end of a row) never lands
            // external content here, so reconcile the height regardless.
            scheduleIntrinsicHeightReconcile()
        }

        func cancelAwaitingExternalContent() {
            awaitingExternalContent = false
        }

        private func syncBindings(from textView: NSTextView) {
            // Lightweight per-keystroke sync: plain text + cursor position only
            viewContentDirty = true
            let currentString = plainTextForBinding(from: textView)
            parent.plainText = currentString
            // Fire direct callback immediately — SwiftUI's @Binding→onChange chain
            // can coalesce/skip when mutations come from AppKit outside the update cycle.
            parent.onPlainTextDidChange?(currentString)

            // Immediately resize AppKit frame so there's no visual gap
            // between text insertion and container resize (the deferred
            // notifyContentHeightChange fires 50ms later for the SwiftUI callback,
            // but AppKit needs to match right now to prevent a visible glitch).
            resizeAppKitFrameIfNeeded(for: textView)
            textView.window?.invalidateCursorRects(for: textView)

            // Coalesce expensive attributedText sync + height measurement.
            // Fires after 50ms of inactivity — fast enough to feel instant,
            // slow enough to skip during rapid typing bursts.
            deferredSyncWorkItem?.cancel()
            isUpdatingFromTextView = true
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard !textView.hasMarkedText() else {
                    self.isUpdatingFromTextView = false
                    return
                }
                guard !self.awaitingExternalContent else {
                    // The view is the stale side of a structural rebuild —
                    // never write its content back, but its HEIGHT is still
                    // ours to keep true (the immediate path refused any
                    // shrink and this settle was the only thing left to
                    // apply it).
                    self.scheduleIntrinsicHeightReconcile()
                    DispatchQueue.main.async { self.isUpdatingFromTextView = false }
                    return
                }
                let synced = viewContentSnapshot(textView)
                self.parent.attributedText = synced
                // Binding now mirrors the view — no compare/replace needed.
                self.lastReconciledBindingText = synced
                self.viewContentDirty = false
                self.notifyContentHeightChange(for: textView)
                // Box-backed binding: no onChange fires — tell the host to
                // parse the committed buffer into the document.
                self.parent.onContentCommitted?()
                DispatchQueue.main.async { self.isUpdatingFromTextView = false }
            }
            deferredSyncWorkItem = workItem
            // Block rows coalesce typing commits at ~250ms of idle: each
            // commit runs the whole-document pipeline (parse → binding →
            // list re-diff → stack re-layout), so committing per keystroke
            // burned ~a frame of work per character. Everything that needs
            // the text sooner reads the LIVE view (boundary ops carry
            // livePlainText; resign/disappear flush; slash reads storage),
            // and the plain mirror + onPlainTextDidChange stay per-keystroke.
            // Continuous editors keep the tighter 50ms (their consumers pull
            // from the document more aggressively).
            let commitDelay = parent.splitsOnReturn ? 0.25 : 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + commitDelay, execute: workItem)
        }

        private func syncStructuralEditBindings(from textView: NSTextView) {
            deferredSyncWorkItem?.cancel()

            let currentAttributedText = viewContentSnapshot(textView)
            let currentString = plainTextForBinding(from: textView, attributedText: currentAttributedText)

            isUpdatingFromTextView = true

            // Settle AppKit-side geometry before invalidating SwiftUI for true
            // structural edits. Ordinary Return uses the lightweight typing path;
            // this path remains for edits that must remount block UI immediately.
            resizeAppKitFrameIfNeeded(for: textView)
            textView.window?.invalidateCursorRects(for: textView)

            parent.plainText = currentString
            parent.onPlainTextDidChange?(currentString)

            let currentDocument = RichDocumentSerializer.document(from: currentAttributedText)
            parent.onStructuredDocumentChange?(currentDocument, currentString)
            parent.attributedText = currentAttributedText
            // Binding now mirrors the view — no compare/replace needed.
            lastReconciledBindingText = currentAttributedText
            viewContentDirty = false

            DispatchQueue.main.async { [weak self] in
                self?.isUpdatingFromTextView = false
            }
        }

        private func plainTextForBinding(
            from textView: NSTextView,
            attributedText providedAttributedText: NSAttributedString? = nil
        ) -> String {
            guard parent.titleConfiguration == nil else {
                return textView.string
            }
            // Hidden content (collapsed headings/elements) can only exist in
            // rows that render disclosure chrome — plain block rows skip the
            // full-range attribute enumeration on every keystroke.
            if parent.splitsOnReturn, !parent.rowHeadingIsCollapsible, !parent.rendersElementChrome {
                return textView.string
            }
            let attributedText = providedAttributedText ?? textView.attributedString()
            guard attributedTextContainsHiddenContent(attributedText) else {
                return textView.string
            }
            return RichDocumentSerializer.document(from: attributedText).plainText
        }

        private func captureAncestorScrollSnapshot(for textView: NSTextView) -> AncestorScrollSnapshot? {
            guard !parent.scrollsInternally,
                  let ancestorScrollView = textView.nearestAncestorScrollView(excluding: textView.enclosingScrollView) else {
                return nil
            }

            return AncestorScrollSnapshot(
                scrollView: ancestorScrollView,
                origin: ancestorScrollView.contentView.bounds.origin
            )
        }

        private func scheduleAncestorScrollSnapshotRestores(_ snapshot: AncestorScrollSnapshot?) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.restoreAncestorScrollSnapshot(snapshot)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
                guard let self else { return }
                self.restoreAncestorScrollSnapshot(snapshot)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self else { return }
                self.restoreAncestorScrollSnapshot(snapshot)
            }
        }

        private func restoreAncestorScrollSnapshot(_ snapshot: AncestorScrollSnapshot?) {
            guard !parent.scrollsInternally,
                  let snapshot,
                  let documentView = snapshot.scrollView.documentView else {
                return
            }

            let clipView = snapshot.scrollView.contentView
            let maxX = max(0, documentView.bounds.width - clipView.bounds.width)
            let maxY = max(0, documentView.bounds.height - clipView.bounds.height)
            let targetOrigin = NSPoint(
                x: min(max(0, snapshot.origin.x), maxX),
                y: min(max(0, snapshot.origin.y), maxY)
            )
            let currentOrigin = clipView.bounds.origin
            guard abs(currentOrigin.x - targetOrigin.x) > 0.05
                    || abs(currentOrigin.y - targetOrigin.y) > 0.05 else {
                return
            }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                clipView.setBoundsOrigin(targetOrigin)
            }
            snapshot.scrollView.reflectScrolledClipView(clipView)
        }

        private func attributedTextContainsHiddenContent(_ attributedText: NSAttributedString) -> Bool {
            guard attributedText.length > 0 else { return false }
            var containsHiddenContent = false
            attributedText.enumerateAttributes(
                in: NSRange(location: 0, length: attributedText.length),
                options: [.longestEffectiveRangeNotRequired]
            ) { attributes, _, stop in
                if attributes[RichDocumentAttributeKeys.headingCollapsedChildrenJSON] != nil {
                    containsHiddenContent = true
                    stop.pointee = true
                    return
                }
                if boolAttributeValue(attributes[RichDocumentAttributeKeys.elementCollapsed]) == true,
                   attributes[RichDocumentAttributeKeys.elementChildrenJSON] != nil {
                    containsHiddenContent = true
                    stop.pointee = true
                }
            }
            return containsHiddenContent
        }

        private func boolAttributeValue(_ value: Any?) -> Bool? {
            if let value = value as? Bool { return value }
            if let value = value as? NSNumber { return value.boolValue }
            return nil
        }

        /// Immediate AppKit resize + single coordinated SwiftUI update.
        /// Resizes the NSTextView frame, updates intrinsicContentSize, AND fires
        /// the SwiftUI height callback in one synchronous pass. This prevents the
        /// double-jitter caused by intrinsicContentSize invalidation and the deferred
        /// SwiftUI callback landing in separate layout passes.
        private func resizeAppKitFrameIfNeeded(for textView: NSTextView) {
            guard !parent.scrollsInternally,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  let scrollView = textView.enclosingScrollView as? CosmoScrollView else { return }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let measuredHeight = measuredSingleLineContentHeight(for: textView)
                ?? ceil(usedRect.height + (textView.textContainerInset.height * 2))
            let newHeight = max(0, measuredHeight)

            let currentWidth = max(scrollView.contentSize.width, scrollView.frame.width, textView.frame.width)
            // Jitter guard. Inside the per-keystroke path NSLayoutManager.usedRect
            // can briefly return a height that is 1-2 pt smaller than the settled
            // value — the just-edited storage isn't fully reflected yet. When that
            // happens we shrink the wrapper + intrinsic to the stale measurement,
            // the deferred sync 50 ms later re-measures the correct value, and
            // the wrapper grows back. The user sees a visible 52→50→52 oscillation
            // on every keystroke and Return — what they describe as a "ghost" of
            // every line. Only allow this immediate path to grow OR keep the same
            // height; let `notifyContentHeightChange` (which runs after layout has
            // fully settled) handle any genuine shrink.
            let widthChanged = abs(scrollView.frame.width - currentWidth) > 0.5
                || abs(textView.frame.width - currentWidth) > 0.5
            let shouldApplyImmediateResize = EditorImmediateResizePolicy.shouldApplyImmediateResize(
                newHeight: newHeight,
                textViewHeight: textView.frame.height,
                scrollViewHeight: scrollView.frame.height,
                intrinsicHeight: scrollView.intrinsicHeight,
                widthChanged: widthChanged,
                plainText: textView.string
            )
            if !shouldApplyImmediateResize {
                return
            }

            // Tolerance-based comparison: see notifyContentHeightChange for the
            // full reasoning. SwiftUI sub-pixel positioning (e.g. h=356.72) vs.
            // our ceil'd integer measurement (356) was driving a subpixel resize
            // loop on every layout pass.
            if abs(textView.frame.height - newHeight) > 0.5 || abs(textView.frame.width - currentWidth) > 0.5 {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    context.allowsImplicitAnimation = false
                    textView.setFrameSize(NSSize(width: currentWidth, height: newHeight))
                }
            }
            if abs((scrollView.intrinsicHeight ?? 0) - newHeight) > 1.0 {
                scrollView.intrinsicHeight = newHeight
                scrollView.invalidateIntrinsicContentSize()
            }

            // Report SwiftUI-facing height changes on the next run loop. This helper
            // can run from NSTextView delegate/layout work, where mutating SwiftUI
            // state synchronously causes re-entrant render passes.
            if abs(newHeight - lastReportedHeight) > 1.0 {
                lastReportedHeight = newHeight
                let callback = parent.onContentHeightChange
                DispatchQueue.main.async {
                    callback?(newHeight)
                }
            }

            // Reset any internal scroll offset — in non-scrolling mode the clip
            // view should always sit at origin so content doesn't shift visually.
            let clipView = scrollView.contentView
            if clipView.bounds.origin != .zero {
                clipView.scroll(to: .zero)
                scrollView.reflectScrolledClipView(clipView)
            }
        }

        fileprivate func notifyContentHeightChange(for textView: NSTextView) {
            guard let callback = parent.onContentHeightChange else {
                return
            }
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return
            }

            var nonScrollingViewportWidth: CGFloat?
            if !parent.scrollsInternally,
               let scrollView = textView.enclosingScrollView as? CosmoScrollView {
                let targetWidth = max(scrollView.contentSize.width, 1)
                // Unmeasured mount (a freshly split row's scroll view is born
                // at zero width): measuring at ~1pt word-wraps the whole
                // block one word per line and seeds a PAGE-TALL intrinsic —
                // the "Return leaves a big gap" bug, previously band-aided
                // after the fact by scheduleIntrinsicHeightReconcile. Seed a
                // single provisional line instead; handleFrameChange
                // re-measures at the real width one layout tick later.
                if !parent.singleLine, targetWidth <= 2 {
                    if scrollView.intrinsicHeight == nil {
                        let font = textView.font ?? NSFont.systemFont(ofSize: parent.fontSize)
                        let provisional = ceil(
                            NSLayoutManager().defaultLineHeight(for: font)
                                + textView.textContainerInset.height * 2
                        )
                        scrollView.intrinsicHeight = provisional
                        lastReportedHeight = provisional
                        if isUpdatingFromSwiftUI {
                            DispatchQueue.main.async {
                                scrollView.invalidateIntrinsicContentSize()
                            }
                        } else {
                            scrollView.invalidateIntrinsicContentSize()
                        }
                    }
                    return
                }
                // For singleLine editors, override container width to prevent wrapping.
                // For multi-line editors, widthTracksTextView handles the container width
                // automatically — do NOT set it manually (the double-change breaks layout).
                if parent.singleLine {
                    let targetContainerWidth = CGFloat.greatestFiniteMagnitude
                    if abs(textContainer.containerSize.width - targetContainerWidth) > 0.5 {
                        textContainer.containerSize = NSSize(
                            width: targetContainerWidth,
                            height: parent.resolvedSingleLineHeight()
                        )
                    }
                }
                if abs(textView.frame.width - targetWidth) > 0.5 {
                    textView.setFrameSize(NSSize(width: targetWidth, height: max(textView.frame.height, 1)))
                }
                nonScrollingViewportWidth = targetWidth
            }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let measuredHeight = measuredSingleLineContentHeight(for: textView)
                ?? ceil(usedRect.height + (textView.textContainerInset.height * 2))
            let minimum: CGFloat
            if parent.singleLine {
                minimum = parent.resolvedSingleLineHeight()
            } else if parent.titleConfiguration != nil {
                minimum = parent.resolvedTitleMinimumHeight()
            } else {
                minimum = 0
            }
            let newHeight = max(minimum, measuredHeight)

            if !parent.scrollsInternally,
               let scrollView = textView.enclosingScrollView as? CosmoScrollView {
                let currentWidth = nonScrollingViewportWidth ?? max(scrollView.contentSize.width, textView.frame.width)
                // Use tolerance (> 0.5pt) for the height comparison as well — `newHeight`
                // is always ceil()'d to an integer, while SwiftUI/AppKit position views
                // at sub-pixel boundaries for Retina alignment (e.g. frame.h=356.72).
                // A raw `!=` triggers a resize on every layout pass, which AppKit re-
                // positions to subpixel, which triggers another measure → another
                // resize. That positive feedback loop is the visible "ghost line"
                // jitter — every layout pass nudges the inner frame, the SwiftUI
                // ScrollView re-anchors, and the user sees the content shimmer.
                if abs(textView.frame.height - newHeight) > 0.5 || abs(textView.frame.width - currentWidth) > 0.5 {
                    textView.setFrameSize(NSSize(width: currentWidth, height: newHeight))
                }
                if abs((scrollView.intrinsicHeight ?? 0) - newHeight) > 1.0 {
                    scrollView.intrinsicHeight = newHeight
                    // Defer invalidation when called during SwiftUI's layout pass
                    // to avoid "Modifying state during view update" re-entrancy.
                    if isUpdatingFromSwiftUI {
                        DispatchQueue.main.async {
                            scrollView.invalidateIntrinsicContentSize()
                        }
                    } else {
                        scrollView.invalidateIntrinsicContentSize()
                    }
                }
            }
            // Only notify when height changes by >1pt to prevent sub-pixel jitter
            guard abs(newHeight - lastReportedHeight) > 1.0 else {
                return
            }
            lastReportedHeight = newHeight
            // Defer callback to next run loop — notifyContentHeightChange may be called
            // from makeNSView/updateNSView during SwiftUI's layout pass.
            DispatchQueue.main.async {
                callback(newHeight)
            }
        }

        fileprivate func normalizeSingleLineViewport(for textView: NSTextView) {
            guard parent.singleLine,
                  let scrollView = textView.enclosingScrollView else {
                return
            }

            let targetHeight = max(
                parent.resolvedSingleLineHeight(),
                measuredSingleLineContentHeight(for: textView) ?? 0
            )
            let currentWidth = max(scrollView.contentSize.width, textView.frame.width)
            if textView.frame.height != targetHeight || textView.frame.width != currentWidth {
                textView.setFrameSize(NSSize(width: currentWidth, height: targetHeight))
            }

            let clipView = scrollView.contentView
            if clipView.bounds.origin != .zero {
                clipView.scroll(to: .zero)
                scrollView.reflectScrolledClipView(clipView)
            }
        }

        private func measuredSingleLineContentHeight(for textView: NSTextView) -> CGFloat? {
            guard parent.singleLine,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return nil
            }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            return ceil(usedRect.height + (textView.textContainerInset.height * 2))
        }
    }
}

fileprivate extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

// MARK: - Redraw hygiene (full-document invalidation guards)

/// What applyFocusBand should do for the current selection. Computed BEFORE
/// touching the layout manager: the band used to clear + restamp temporary
/// attributes across the whole document on every selection change (Content
/// focus always supplies a provider, even with the band mode off), which
/// invalidated the entire manuscript's display per click — the mechanism
/// behind the draft blinking or staying blank until the next click.
enum FocusBandPlan: Equatable {
    /// Nothing changed — do not touch the layout manager at all.
    case none
    /// A painted band must go away — one full-range clear, then quiet.
    case clear
    /// Paint (or move) the band to this clamped active range.
    case apply(NSRange)
}

enum FocusBandPlanner {
    static func plan(
        requested: NSRange?,
        fullLength: Int,
        lastApplied: NSRange?,
        hasApplied: Bool,
        force: Bool
    ) -> FocusBandPlan {
        guard fullLength > 0 else { return .none }

        var resolved: NSRange?
        if let requested, requested.location != NSNotFound {
            let location = min(max(0, requested.location), fullLength)
            let length = min(max(0, requested.length), fullLength - location)
            let candidate = NSRange(location: location, length: max(length, 1))
            if candidate.location < fullLength {
                resolved = candidate
            }
        }

        guard let resolved else {
            return hasApplied ? .clear : .none
        }
        if !force, hasApplied, resolved == lastApplied {
            return .none
        }
        return .apply(resolved)
    }
}

/// Diff-aware storage override stamping. The stamp used to run unconditionally
/// (full-range addAttribute inside beginEditing/endEditing) on every focused
/// updateNSView — a full-document display invalidation per click/selection.
/// This pass computes what actually differs first and only opens an editing
/// transaction when a real change is needed. Returns whether the storage was
/// edited.
enum EditorStorageOverridePass {
    @discardableResult
    static func apply(
        to storage: NSTextStorage,
        overrideTextColor: NSColor?,
        overrideFont: NSFont?,
        appliesHeadingIndents: Bool
    ) -> Bool {
        guard storage.length > 0 else { return false }
        let fullRange = NSRange(location: 0, length: storage.length)

        var colorStamps: [NSRange] = []
        if let color = overrideTextColor {
            storage.enumerateAttribute(RichDocumentAttributeKeys.entityType, in: fullRange, options: []) { value, entityRange, _ in
                // Preserve mention colors (entities carry their own color).
                guard value == nil else { return }
                storage.enumerateAttribute(.foregroundColor, in: entityRange, options: []) { current, runRange, _ in
                    let currentColor = current as? NSColor
                    guard currentColor != color else { return }
                    // Deliberate inline ink keeps its tone under any theme.
                    if storage.attribute(RichDocumentAttributeKeys.inkID, at: runRange.location, effectiveRange: nil) != nil {
                        return
                    }
                    // A line-leading checklist glyph is deliberately clear
                    // (the circle checkbox is painted over its rect) — leave
                    // it alone instead of re-inking + re-clearing each pass.
                    if currentColor == NSColor.clear,
                       isLineLeadingChecklistGlyph(runRange, in: storage.string as NSString) {
                        return
                    }
                    colorStamps.append(runRange)
                }
            }
        }

        var fontStamps: [NSRange] = []
        if let font = overrideFont {
            storage.enumerateAttribute(.font, in: fullRange, options: []) { current, runRange, _ in
                guard (current as? NSFont) != font else { return }
                fontStamps.append(runRange)
            }
        }

        var headingParagraphUpdates: [(range: NSRange, style: NSMutableParagraphStyle)] = []
        if appliesHeadingIndents {
            let headingFlag: (NSAttributedString.Key, Int) -> Bool = { key, location in
                let value = storage.attribute(key, at: location, effectiveRange: nil)
                if let number = value as? NSNumber { return number.boolValue }
                return (value as? Bool) ?? false
            }
            storage.enumerateAttribute(RichDocumentAttributeKeys.headingLevel, in: fullRange, options: []) { value, range, _ in
                guard value != nil else { return }
                // Only collapsible (or still-collapsed) headings own the
                // chevron gutter — plain headings sit flush with body text
                // and must not have the indent re-imposed here.
                let isCollapsible = headingFlag(RichDocumentAttributeKeys.headingCollapsible, range.location)
                let isCollapsed = headingFlag(RichDocumentAttributeKeys.headingCollapsed, range.location)
                guard isCollapsible || isCollapsed else { return }
                let existingStyle = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
                let currentFirstLineIndent = existingStyle?.firstLineHeadIndent ?? 0
                let currentHeadIndent = existingStyle?.headIndent ?? 0
                guard currentFirstLineIndent < 34 || currentHeadIndent < 34 else { return }

                let headingStyle = (existingStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                headingStyle.firstLineHeadIndent = max(currentFirstLineIndent, 34)
                headingStyle.headIndent = max(currentHeadIndent, 34)
                headingParagraphUpdates.append((range, headingStyle))
            }
        }

        let glyphReclears = checklistGlyphReclearRanges(in: storage)

        guard !colorStamps.isEmpty || !fontStamps.isEmpty
                || !headingParagraphUpdates.isEmpty || !glyphReclears.isEmpty else {
            return false
        }

        storage.beginEditing()
        if let color = overrideTextColor {
            for range in colorStamps {
                storage.addAttribute(.foregroundColor, value: color, range: range)
            }
        }
        if let font = overrideFont {
            for range in fontStamps {
                storage.addAttribute(.font, value: font, range: range)
            }
        }
        for update in headingParagraphUpdates {
            storage.addAttribute(.paragraphStyle, value: update.style, range: update.range)
        }
        for range in glyphReclears {
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
        }
        storage.endEditing()
        return true
    }

    /// Line-leading ☐/☑ glyphs whose ink is not yet clear — the ranges
    /// reclearChecklistGlyphs must stamp. Read-only; performs no edits.
    static func checklistGlyphReclearRanges(
        in storage: NSAttributedString,
        range: NSRange? = nil
    ) -> [NSRange] {
        let nsText = storage.string as NSString
        guard nsText.length > 0 else { return [] }
        let scanRange = range.map { nsText.lineRange(for: $0) } ?? NSRange(location: 0, length: nsText.length)
        var results: [NSRange] = []
        var location = scanRange.location
        let end = NSMaxRange(scanRange)
        while location < end {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            defer { location = max(NSMaxRange(lineRange), location + 1) }
            guard lineRange.length >= 1 else { continue }
            let glyph = nsText.substring(with: NSRange(location: lineRange.location, length: 1))
            guard glyph == "☐" || glyph == "☑" else { continue }
            let glyphRange = NSRange(location: lineRange.location, length: 1)
            let current = storage.attribute(.foregroundColor, at: glyphRange.location, effectiveRange: nil) as? NSColor
            guard current != NSColor.clear else { continue }
            results.append(glyphRange)
        }
        return results
    }

    private static func isLineLeadingChecklistGlyph(_ range: NSRange, in text: NSString) -> Bool {
        guard range.length == 1, range.location < text.length else { return false }
        let lineRange = text.lineRange(for: NSRange(location: range.location, length: 0))
        guard lineRange.location == range.location else { return false }
        let glyph = text.substring(with: NSRange(location: range.location, length: 1))
        return glyph == "☐" || glyph == "☑"
    }
}
