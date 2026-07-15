// CosmoOS/UI/FocusMode/Ideas/IdeaManuscriptEditors.swift
// June 2026 — Idea Focus Mode v2.
// The manuscript column's AppKit-backed editors, moved verbatim from
// IdeaFocusModeView.swift: the context editor (with the coordinator-echo /
// first-responder guard that keeps the caret stable while autosave churns),
// hook line editors, and outline slide note editors + focus registry.
// OutlineSlideNoteTextView / OutlineSlideFocusRegistry / IdeaOutlineLayoutMetrics
// stay internal — CodexOutlineEditingTests and EditorLayoutMetricsTests
// instantiate them directly.

import SwiftUI
import AppKit

enum IdeaOutlineLayoutMetrics {
    static let minimumEditorHeight: CGFloat = 22
    static let normalRowSpacing: CGFloat = 12

    static func editorHeight(forMeasuredHeight measuredHeight: CGFloat) -> CGFloat {
        max(minimumEditorHeight, ceil(measuredHeight))
    }
}

enum HookEditorFocus: Hashable {
    case existing(Int)
    case draft
}

enum HookLineLayoutMetrics {
    static let minimumEditorHeight: CGFloat = 22

    static func editorHeight(forMeasuredHeight measuredHeight: CGFloat) -> CGFloat {
        max(minimumEditorHeight, ceil(measuredHeight))
    }
}

enum OutlineSlideNavigationDirection: Equatable {
    case previous
    case next
}


struct IdeaContextTextEditor: NSViewRepresentable {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let onTextChange: (String) -> Void

    func makeNSView(context: Context) -> IdeaContextTextView {
        let textView = IdeaContextTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: IdeaContextTextView.minimumHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        // .height keeps the text view tracking the host when SwiftUI resizes
        // it (paired with the setFrameSize floor in IdeaContextTextView).
        textView.autoresizingMask = [.width, .height]
        textView.applyManuscriptStyle()
        textView.string = text
        return textView
    }

    func updateNSView(_ textView: IdeaContextTextView, context: Context) {
        context.coordinator.parent = self

        // Only apply EXTERNAL text changes. While the user is typing, the
        // binding echoes back through SwiftUI — sometimes with a stale value
        // (fast typing coalesces binding writes) — and rewriting the storage
        // here clamps the caret against the stale length, teleporting it to
        // the end so the next keystroke inserts at the bottom. Same guard as
        // the flagship editor (TextKitCoordinator). Tradeoff: a programmatic
        // body mutation made while the caret is in this editor renders on
        // blur — textDidEndEditing flips focus, which re-runs this update
        // without the first-responder guard.
        let isFirstResponder = textView.window?.firstResponder === textView
        guard !context.coordinator.isUpdatingFromTextView, !isFirstResponder else { return }

        textView.applyManuscriptStyle()

        if textView.string != text {
            let selectedRange = textView.selectedRange()
            let textLength = (text as NSString).length
            let selectionLocation = min(selectedRange.location, textLength)
            textView.string = text
            textView.setSelectedRange(NSRange(
                location: selectionLocation,
                length: min(selectedRange.length, max(0, textLength - selectionLocation))
            ))
            textView.invalidateIntrinsicContentSize()
        }

        // Let AppKit own first-responder changes for this freeform editor.
        // Forcing focus from SwiftUI updates can reset the insertion point or
        // briefly resign first responder while a keystroke is being committed.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: IdeaContextTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? nsView.frame.width
        let measured = nsView.measuredHeight(for: width)
        return CGSize(width: width, height: max(IdeaContextTextView.minimumHeight, measured))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: IdeaContextTextEditor
        /// True while a user keystroke is round-tripping through the binding.
        /// Reset on the next runloop turn so the same-pass `updateNSView`
        /// echo is ignored (it would rewrite the storage with stale text).
        var isUpdatingFromTextView = false

        init(parent: IdeaContextTextEditor) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            if let textView = notification.object as? NSTextView {
                FocusModeTextClipboardTarget.activate(textView)
            }
            parent.isFocused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? IdeaContextTextView else { return }
            FocusModeTextClipboardTarget.activate(textView)
            parent.isFocused = true
            isUpdatingFromTextView = true
            parent.text = textView.string
            parent.onTextChange(textView.string)
            textView.invalidateIntrinsicContentSize()
            DispatchQueue.main.async { [weak self] in
                self?.isUpdatingFromTextView = false
            }
        }
    }
}

final class IdeaContextTextView: NSTextView {
    static let minimumHeight: CGFloat = 200

    override var textContainerOrigin: NSPoint {
        NSPoint(x: textContainerInset.width, y: textContainerInset.height)
    }

    // AppKit clamps `minSize` down whenever a smaller frame is set, so the
    // minimumHeight floor configured in makeNSView dies silently and the
    // vertically-resizable text view shrinks itself to its content height
    // (~32pt when empty). SwiftUI's platform-view host is NOT flipped, so the
    // shorter child bottom-anchors inside the reserved frame: caret, typing,
    // and clicks all land at the bottom while the top of the editor is dead
    // space. Never let the view be shorter than the height SwiftUI reserved.
    override func setFrameSize(_ newSize: NSSize) {
        var size = newSize
        let reserved = superview?.bounds.height ?? Self.minimumHeight
        size.height = max(size.height, reserved, Self.minimumHeight)
        super.setFrameSize(size)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: NSView.noIntrinsicMetric,
            height: max(Self.minimumHeight, measuredHeight(for: bounds.width))
        )
    }

    func applyManuscriptStyle() {
        let font = Self.manuscriptFont
        // The manuscript sits on the focus paper, so its ink is the focus
        // pair — DS.text flips light in dark palettes and would vanish
        // against the paper-doctrine sheet.
        let color = NSColor(DS.usesImmersiveFocusAppearance ? DS.focusImmersiveText : DS.documentText)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 7

        self.font = font
        self.textColor = color
        self.defaultParagraphStyle = paragraphStyle
        self.typingAttributes = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]

        guard let textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.addAttributes([
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ], range: fullRange)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if FocusModeTextClipboardTarget.performKeyEquivalent(event, fallback: self) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        FocusModeTextClipboardTarget.activate(self)
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    func measuredHeight(for width: CGFloat) -> CGFloat {
        guard width > 0 else { return Self.minimumHeight }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 7

        let storage = NSTextStorage(string: string.isEmpty ? " " : string)
        let container = NSTextContainer(size: NSSize(
            width: max(0, width - textContainerInset.width * 2),
            height: .greatestFiniteMagnitude
        ))
        let manager = NSLayoutManager()
        container.lineFragmentPadding = 0
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        storage.addAttributes([
            .font: Self.manuscriptFont,
            .paragraphStyle: paragraphStyle
        ], range: NSRange(location: 0, length: storage.length))
        manager.ensureLayout(for: container)
        return ceil(manager.usedRect(for: container).height + textContainerInset.height * 2)
    }

    private static var manuscriptFont: NSFont {
        let base = NSFont.systemFont(ofSize: 17, weight: .regular)
        guard let descriptor = base.fontDescriptor.withDesign(.serif),
              let font = NSFont(descriptor: descriptor, size: 17) else {
            return base
        }
        return font
    }
}

struct HookLineEditor: NSViewRepresentable {
    @Binding var text: String
    let editorID: HookEditorFocus
    @FocusState.Binding var focusedEditor: HookEditorFocus?
    let placeholder: String
    let font: NSFont
    let textColor: NSColor
    let placeholderColor: NSColor
    let onReturn: () -> Void
    let onDeleteEmpty: () -> Bool
    /// ⌥↑ / ⌥↓ — move this line within its list (keyboard reorder).
    var onMoveLine: ((OutlineSlideNavigationDirection) -> Void)? = nil

    func makeNSView(context: Context) -> HookLineTextView {
        let textView = HookLineTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: HookLineLayoutMetrics.minimumEditorHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.font = font
        textView.textColor = textColor
        textView.placeholderColor = placeholderColor
        textView.placeholder = placeholder
        textView.onReturn = onReturn
        textView.onDeleteEmpty = onDeleteEmpty
        textView.onMoveLine = onMoveLine
        return textView
    }

    func updateNSView(_ textView: HookLineTextView, context: Context) {
        context.coordinator.parent = self
        textView.onReturn = onReturn
        textView.onDeleteEmpty = onDeleteEmpty
        textView.onMoveLine = onMoveLine
        textView.placeholder = placeholder
        textView.placeholderColor = placeholderColor

        if textView.font != font {
            textView.font = font
            textView.invalidateIntrinsicContentSize()
        }
        if textView.textColor != textColor {
            textView.textColor = textColor
        }

        if textView.string != text {
            textView.string = text
            textView.invalidateIntrinsicContentSize()
        }

        if focusedEditor == editorID {
            textView.requestFocusWhenReady()
        } else if focusedEditor != nil, textView.window?.firstResponder === textView {
            textView.window?.makeFirstResponder(nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HookLineTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? nsView.frame.width
        let measured = nsView.measuredHeight(for: width)
        return CGSize(width: width, height: HookLineLayoutMetrics.editorHeight(forMeasuredHeight: measured))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HookLineEditor

        init(parent: HookLineEditor) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            if let textView = notification.object as? NSTextView {
                FocusModeTextClipboardTarget.activate(textView)
            }
            parent.focusedEditor = parent.editorID
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? HookLineTextView else { return }
            FocusModeTextClipboardTarget.activate(textView)
            parent.focusedEditor = parent.editorID
            parent.text = textView.string
            textView.invalidateIntrinsicContentSize()
        }
    }
}

final class HookLineTextView: NSTextView {
    var placeholder: String = ""
    var placeholderColor: NSColor = .secondaryLabelColor
    var onReturn: (() -> Void)?
    var onDeleteEmpty: (() -> Bool)?
    var onMoveLine: ((OutlineSlideNavigationDirection) -> Void)?
    private var shouldFocusWhenAttached = false

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: NSView.noIntrinsicMetric,
            height: HookLineLayoutMetrics.editorHeight(forMeasuredHeight: measuredHeight(for: bounds.width))
        )
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyPendingFocusIfPossible()
    }

    func requestFocusWhenReady() {
        shouldFocusWhenAttached = true
        DispatchQueue.main.async { [weak self] in
            self?.applyPendingFocusIfPossible()
        }
    }

    private func applyPendingFocusIfPossible() {
        guard shouldFocusWhenAttached, let window else { return }
        shouldFocusWhenAttached = false
        guard window.firstResponder !== self else { return }

        window.makeFirstResponder(self)
        FocusModeTextClipboardTarget.activate(self)
        setSelectedRange(NSRange(location: string.count, length: 0))
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isPlainReturn = event.keyCode == 36 && flags.isEmpty
        if isPlainReturn {
            onReturn?()
            return
        }

        let isShiftReturn = event.keyCode == 36 && flags == .shift
        if isShiftReturn {
            insertText("\n", replacementRange: selectedRange())
            return
        }

        // ⌥↑ / ⌥↓ — reorder the line within its list.
        if flags == .option, event.keyCode == 126 {
            onMoveLine?(.previous)
            return
        }
        if flags == .option, event.keyCode == 125 {
            onMoveLine?(.next)
            return
        }

        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if FocusModeTextClipboardTarget.performKeyEquivalent(event, fallback: self) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        FocusModeTextClipboardTarget.activate(self)
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(deleteBackward(_:)),
           string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           onDeleteEmpty?() == true {
            return
        }

        if selector == #selector(insertNewline(_:)) {
            onReturn?()
            return
        }

        super.doCommand(by: selector)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard string.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 15),
            .foregroundColor: placeholderColor
        ]
        placeholder.draw(at: NSPoint(x: 0, y: 1), withAttributes: attributes)
    }

    func measuredHeight(for width: CGFloat) -> CGFloat {
        guard width > 0 else { return HookLineLayoutMetrics.minimumEditorHeight }
        let storage = NSTextStorage(string: string.isEmpty ? " " : string)
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        let manager = NSLayoutManager()
        container.lineFragmentPadding = 0
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        storage.addAttribute(.font, value: font ?? NSFont.systemFont(ofSize: 15), range: NSRange(location: 0, length: storage.length))
        manager.ensureLayout(for: container)
        return ceil(manager.usedRect(for: container).height)
    }
}

struct OutlineSlideNoteEditor: NSViewRepresentable {
    @Binding var text: String
    let slideID: UUID
    @FocusState.Binding var focusedSlideID: UUID?
    let placeholder: String
    let onReturn: () -> Void
    let onMoveFocus: (OutlineSlideNavigationDirection) -> Void
    let onDeleteEmpty: () -> Bool
    /// ⌥↑ / ⌥↓ — move this slide within the outline (keyboard reorder).
    var onMoveLine: ((OutlineSlideNavigationDirection) -> Void)? = nil

    func makeNSView(context: Context) -> OutlineSlideNoteTextView {
        let textView = OutlineSlideNoteTextView()
        textView.slideID = slideID
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.minSize = NSSize(width: 0, height: IdeaOutlineLayoutMetrics.minimumEditorHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.font = NSFont.systemFont(ofSize: 14)
        // Focus-paired ink — the outline sits on the focus paper.
        textView.textColor = NSColor(DS.usesImmersiveFocusAppearance ? DS.focusImmersiveText : DS.documentText)
        textView.placeholder = placeholder
        textView.onReturn = onReturn
        textView.onMoveFocus = onMoveFocus
        textView.onDeleteEmpty = onDeleteEmpty
        textView.onMoveLine = onMoveLine
        return textView
    }

    func updateNSView(_ textView: OutlineSlideNoteTextView, context: Context) {
        context.coordinator.parent = self
        textView.slideID = slideID
        OutlineSlideFocusRegistry.shared.register(textView, for: slideID)
        textView.onReturn = onReturn
        textView.onMoveFocus = onMoveFocus
        textView.onDeleteEmpty = onDeleteEmpty
        textView.onMoveLine = onMoveLine
        textView.placeholder = placeholder

        if textView.string != text {
            textView.string = text
            textView.invalidateIntrinsicContentSize()
        }

        if focusedSlideID == slideID {
            textView.requestFocusWhenReady()
        }
    }

    static func dismantleNSView(_ textView: OutlineSlideNoteTextView, coordinator: Coordinator) {
        if let slideID = textView.slideID {
            OutlineSlideFocusRegistry.shared.unregister(textView, for: slideID)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: OutlineSlideNoteTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? nsView.frame.width
        let measured = nsView.measuredHeight(for: width)
        return CGSize(width: width, height: IdeaOutlineLayoutMetrics.editorHeight(forMeasuredHeight: measured))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: OutlineSlideNoteEditor

        init(parent: OutlineSlideNoteEditor) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            if let textView = notification.object as? NSTextView {
                FocusModeTextClipboardTarget.activate(textView)
            }
            parent.focusedSlideID = parent.slideID
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? OutlineSlideNoteTextView else { return }
            FocusModeTextClipboardTarget.activate(textView)
            parent.text = textView.string
            textView.invalidateIntrinsicContentSize()
        }
    }
}

final class OutlineSlideFocusRegistry {
    static let shared = OutlineSlideFocusRegistry()

    private struct Entry {
        weak var textView: OutlineSlideNoteTextView?
    }

    private var textViewsBySlideID: [UUID: Entry] = [:]
    private var pendingFocusSlideIDs: Set<UUID> = []

    private init() {}

    func register(_ textView: OutlineSlideNoteTextView, for slideID: UUID) {
        textViewsBySlideID[slideID] = Entry(textView: textView)
        if pendingFocusSlideIDs.contains(slideID) {
            requestFocus(slideID)
        }
    }

    func unregister(_ textView: OutlineSlideNoteTextView, for slideID: UUID) {
        if textViewsBySlideID[slideID]?.textView === textView {
            textViewsBySlideID.removeValue(forKey: slideID)
        }
    }

    func requestFocus(_ slideID: UUID) {
        guard let textView = textViewsBySlideID[slideID]?.textView else {
            pendingFocusSlideIDs.insert(slideID)
            return
        }

        pendingFocusSlideIDs.remove(slideID)
        textView.requestFocusWhenReady()
    }
}

final class OutlineSlideNoteTextView: NSTextView {
    var slideID: UUID?
    var placeholder: String = ""
    var onReturn: (() -> Void)?
    var onMoveFocus: ((OutlineSlideNavigationDirection) -> Void)?
    var onDeleteEmpty: (() -> Bool)?
    var onMoveLine: ((OutlineSlideNavigationDirection) -> Void)?
    private var shouldFocusWhenAttached = false
    private var focusAttemptCount = 0
    private let maxFocusAttemptCount = 5

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: NSView.noIntrinsicMetric,
            height: IdeaOutlineLayoutMetrics.editorHeight(forMeasuredHeight: measuredHeight(for: bounds.width))
        )
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyPendingFocusIfPossible()
    }

    func requestFocusWhenReady() {
        shouldFocusWhenAttached = true
        focusAttemptCount = 0
        DispatchQueue.main.async { [weak self] in
            self?.applyPendingFocusIfPossible()
        }
    }

    private func applyPendingFocusIfPossible() {
        guard shouldFocusWhenAttached, let window else { return }
        guard window.firstResponder !== self else {
            shouldFocusWhenAttached = false
            FocusModeTextClipboardTarget.activate(self)
            setSelectedRange(NSRange(location: string.count, length: 0))
            return
        }

        guard window.makeFirstResponder(self) else {
            focusAttemptCount += 1
            if focusAttemptCount < maxFocusAttemptCount {
                DispatchQueue.main.async { [weak self] in
                    self?.applyPendingFocusIfPossible()
                }
            } else {
                shouldFocusWhenAttached = false
            }
            return
        }

        shouldFocusWhenAttached = false
        FocusModeTextClipboardTarget.activate(self)
        setSelectedRange(NSRange(location: string.count, length: 0))
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isPlainReturn = event.keyCode == 36 && flags.isEmpty
        if isPlainReturn {
            onReturn?()
            return
        }

        let isShiftReturn = event.keyCode == 36 && flags == .shift
        if isShiftReturn {
            insertText("\n", replacementRange: selectedRange())
            return
        }

        if flags.isEmpty, event.keyCode == 126, selectedRange().location == 0 {
            onMoveFocus?(.previous)
            return
        }

        if flags.isEmpty, event.keyCode == 125, NSMaxRange(selectedRange()) >= string.count {
            onMoveFocus?(.next)
            return
        }

        // ⌥↑ / ⌥↓ — reorder the slide within the outline.
        if flags == .option, event.keyCode == 126 {
            onMoveLine?(.previous)
            return
        }
        if flags == .option, event.keyCode == 125 {
            onMoveLine?(.next)
            return
        }

        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if FocusModeTextClipboardTarget.performKeyEquivalent(event, fallback: self) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        FocusModeTextClipboardTarget.activate(self)
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(deleteBackward(_:)),
           string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           onDeleteEmpty?() == true {
            return
        }

        if selector == #selector(insertNewline(_:)) {
            onReturn?()
            return
        }

        super.doCommand(by: selector)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard string.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor(DS.usesImmersiveFocusAppearance ? DS.focusImmersiveTextMuted : DS.documentTextMuted)
        ]
        placeholder.draw(at: NSPoint(x: 0, y: 1), withAttributes: attributes)
    }

    func measuredHeight(for width: CGFloat) -> CGFloat {
        guard width > 0 else { return IdeaOutlineLayoutMetrics.minimumEditorHeight }
        let storage = NSTextStorage(string: string.isEmpty ? " " : string)
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        let manager = NSLayoutManager()
        container.lineFragmentPadding = 0
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        storage.addAttribute(.font, value: font ?? NSFont.systemFont(ofSize: 14), range: NSRange(location: 0, length: storage.length))
        manager.ensureLayout(for: container)
        return ceil(manager.usedRect(for: container).height)
    }
}

