import SwiftUI
import AppKit

/// List/block context of the current selection's line, mirrored from the
/// coordinator's prefix detection so the formatting bar can light its controls.
enum SelectionListKind: Equatable {
    case none
    case bullet
    case numbered
    case checklist
    case quote
}

/// Formatting state of the current selection. An inline trait is active only
/// when it covers the *entire* selected range (NSTextView convention); for a
/// caret it reflects the typing attributes.
struct SelectionFormattingTraits: Equatable {
    var isBold = false
    var isItalic = false
    var isUnderline = false
    var isStrikethrough = false
    var headingLevel: Int? = nil
    var listKind: SelectionListKind = .none

    static let none = SelectionFormattingTraits()
}

struct EditorSelectionSnapshot: Equatable {
    var range: NSRange
    var text: String
    var rectInEditor: CGRect
    var traits: SelectionFormattingTraits = .none
    /// The heading section the caret currently sits under (nearest heading at
    /// or before the caret) — drives the live outline in the margin rails.
    var nearestHeadingBlockID: UUID? = nil

    static let empty = EditorSelectionSnapshot(
        range: NSRange(location: NSNotFound, length: 0),
        text: "",
        rectInEditor: .zero
    )
}

/// Resolves content fonts for the editor, honoring a per-document font design
/// (sans / serif / rounded / mono — the Craft-style document styles).
enum EditorFontPolicy {
    static func font(
        ofSize size: CGFloat,
        weight: NSFont.Weight,
        design: NSFontDescriptor.SystemDesign
    ) -> NSFont {
        designed(NSFont.systemFont(ofSize: size, weight: weight), design: design)
    }

    static func designed(_ font: NSFont, design: NSFontDescriptor.SystemDesign) -> NSFont {
        // Code stays code: a serif/rounded note must not convert its
        // monospaced runs (code blocks) out of monospace.
        guard design != .default,
              !font.fontDescriptor.symbolicTraits.contains(.monoSpace),
              let descriptor = font.fontDescriptor.withDesign(design),
              let next = NSFont(descriptor: descriptor, size: font.pointSize) else {
            return font
        }
        return next
    }

    /// Re-styles every font run of a serialized document. Sizes, weights, and
    /// bold/italic traits are preserved — only the design axis changes.
    static func applyingDesign(
        _ design: NSFontDescriptor.SystemDesign,
        to attributed: NSAttributedString
    ) -> NSAttributedString {
        guard design != .default, attributed.length > 0 else { return attributed }
        let result = NSMutableAttributedString(attributedString: attributed)
        result.beginEditing()
        result.enumerateAttribute(.font, in: NSRange(location: 0, length: result.length)) { value, range, _ in
            guard let font = value as? NSFont else { return }
            result.addAttribute(.font, value: designed(font, design: design), range: range)
        }
        result.endEditing()
        return result
    }

    static func swiftUIDesign(_ design: NSFontDescriptor.SystemDesign) -> Font.Design {
        switch design {
        case .serif: return .serif
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        default: return .default
        }
    }
}

/// Applies the per-document line-spacing preset (the Aa menu's Compact /
/// Standard / Airy) to a serialized document as a post-pass, the same way
/// EditorFontPolicy applies the font design. Body paragraphs breathe; titles,
/// single-line surfaces (lineSpacing 0), and headings keep their own rhythm.
enum EditorRhythmPolicy {
    static func applyingLineSpacing(
        _ delta: CGFloat,
        to attributed: NSAttributedString
    ) -> NSAttributedString {
        guard delta != 0, attributed.length > 0 else { return attributed }
        let result = NSMutableAttributedString(attributedString: attributed)
        let fullRange = NSRange(location: 0, length: result.length)
        result.beginEditing()
        result.enumerateAttribute(.paragraphStyle, in: fullRange, options: []) { value, range, _ in
            guard let style = value as? NSParagraphStyle,
                  style.lineSpacing > 0,
                  result.attribute(RichDocumentAttributeKeys.headingLevel, at: range.location, effectiveRange: nil) == nil,
                  let updated = style.mutableCopy() as? NSMutableParagraphStyle else {
                return
            }
            updated.lineSpacing = max(0, style.lineSpacing + delta)
            result.addAttribute(.paragraphStyle, value: updated, range: range)
        }
        result.endEditing()
        return result
    }
}

enum EditorBoundaryCommand: Equatable {
    case moveToPreviousBlock
    case moveToNextBlock
    /// Backspace at the very start of a block row — delete or merge backward.
    /// livePlainText is the text view's current truth (the document binding
    /// can lag ~50ms), so just-deleted characters don't resurrect in a merge.
    case deleteBackwardAtStart(livePlainText: String)
    case insertNewlineOnEmptyFinalLine
    /// Return in a block row — split the block at the caret (Notion model).
    /// The offset is measured from the END of the text view's content so list
    /// and quote prefixes rendered at the head don't shift it. livePlainText
    /// is the text view's current truth (the document binding can lag ~50ms).
    case splitBlock(caretUTF16OffsetFromEnd: Int, livePlainText: String)
    /// Esc with no menus open — the host selects the whole block (Notion-style).
    case escapeSelectBlock
    /// ⌘A when the block's text is already fully selected — escalate to all blocks.
    case selectAllBlocks
    /// Multi-line paste into a block row — the host splices the pasted text
    /// into real blocks in ONE synchronous operation. Hard newlines must
    /// never enter the row's text view (the transient multi-line state is the
    /// root of the paste-duplication class of bugs).
    case pasteBlocks(pastedText: String, caretUTF16OffsetFromEnd: Int, livePlainText: String)
    /// Backstop: a hard newline reached the row's text view anyway
    /// (dictation, IME, RTF paste). The host re-parses the live text into
    /// blocks synchronously, before any stale re-emission can splice twice.
    case normalizeHardNewlines(caretUTF16OffsetFromEnd: Int, livePlainText: String)
    /// A markdown prefix ("# ", "- ", "> ", "[] ", "1. ", "---") completed at
    /// the start of a paragraph row — convert the block live (Notion model).
    case applyMarkdownAlias(kind: RichBlockKind, checked: Bool?, aliasUTF16Length: Int, livePlainText: String)
    /// Structured block paste (com.cosmo.blocks pasteboard flavor) — kinds
    /// survive copy/paste within the app.
    case pasteBlockRun(blocks: [RichBlock], caretUTF16OffsetFromEnd: Int, livePlainText: String)
    /// A block-manipulation key equivalent (⌘D, ⌥⌘↑/↓, ⌥⌘1–3, ⇧⌘L) landed in
    /// a block row — the host applies it structurally.
    case blockShortcut(BlockKeyboardShortcut, livePlainText: String)
}

/// Keyboard block manipulation — the handle menu's actions without the mouse.
enum BlockKeyboardShortcut: Equatable {
    case duplicate
    case moveUp
    case moveDown
    case heading(Int)
    case checklistToggle
}

/// Live markdown-alias detection for block rows: a recognized prefix typed
/// at the very start of the block (caret sitting right after it) converts
/// the block's kind in place.
struct MarkdownBlockAlias {
    let kind: RichBlockKind
    let checked: Bool?
    let utf16Length: Int

    private static let prefixes: [(String, RichBlockKind, Bool?)] = [
        ("# ", .heading1, nil),
        ("## ", .heading2, nil),
        ("### ", .heading3, nil),
        ("- [ ] ", .checklist, false),
        ("- [x] ", .checklist, true),
        ("- [X] ", .checklist, true),
        ("[ ] ", .checklist, false),
        ("[] ", .checklist, false),
        ("- ", .bulletList, nil),
        ("* ", .bulletList, nil),
        ("> ", .quote, nil),
        ("!! ", .callout, nil)
    ]

    static func match(text: String, cursorLocation: Int) -> MarkdownBlockAlias? {
        if text == "---", cursorLocation == 3 {
            return MarkdownBlockAlias(kind: .divider, checked: nil, utf16Length: 3)
        }
        if text == "```", cursorLocation == 3 {
            return MarkdownBlockAlias(kind: .code, checked: nil, utf16Length: 3)
        }
        for (prefix, kind, checked) in prefixes {
            let length = (prefix as NSString).length
            if cursorLocation == length, text.hasPrefix(prefix) {
                return MarkdownBlockAlias(kind: kind, checked: checked, utf16Length: length)
            }
        }
        // Digit guard before the regex — this matcher runs per keystroke.
        if let first = text.first, first.isNumber,
           let match = text.range(of: #"^\d+\.\s"#, options: .regularExpression) {
            let length = (String(text[match]) as NSString).length
            if cursorLocation == length {
                return MarkdownBlockAlias(kind: .numberedList, checked: nil, utf16Length: length)
            }
        }
        return nil
    }
}

/// A one-shot caret placement consumed by the text view after an external
/// structural edit (split/merge/delete). Offset is from the END of the text
/// in UTF-16, which is immune to rendered list/quote prefixes at the head.
struct EditorCaretRequest: Equatable {
    var utf16OffsetFromEnd: Int
    var token: Int
}

/// Non-invalidating sync bookkeeping for CosmoDocumentEditor. Held in @State
/// for identity but deliberately not observable — nothing here is read in
/// body, so writes (per keystroke and per async flag reset) must not
/// invalidate the view.
@MainActor
final class DocumentEditorSyncBox {
    /// The editor's content channel. NOT @State: the coordinator writes the
    /// plain mirror on every keystroke and the attributed text on every
    /// deferred (50ms) commit — as @State each write re-ran the editor's
    /// whole body chain (CosmoDocumentEditor → RichTextEditor → representable
    /// → full stack re-layout) for content the NSTextView already displays.
    /// External applies invalidate through `externalContentToken` instead.
    var attributedText = NSAttributedString()
    var plainTextMirror = ""
    var isApplyingExternalUpdate = false
    var isSyncingFromEditor = false
    var documentSyncWorkItem: DispatchWorkItem?
    var lastEmittedPlainText = ""
    /// The last document value THIS editor wrote to the binding. Guards
    /// `.onChange(of: document)` against echoes of our own writes — the
    /// async-reset `isSyncingFromEditor` flag alone has a one-tick dead
    /// window, and an echo slipping through re-serialized and force-replaced
    /// the row's storage per keystroke. Cleared when external content is
    /// applied so a later external revert to this value is not mistaken for
    /// an echo.
    var lastSelfWrittenDocument: RichDocument?
}

struct CosmoDocumentEditor: View {
    @Binding var document: RichDocument

    /// Sync bookkeeping + the content channel — flags, debounce item, dedup
    /// text, and the attributed/plain mirrors. Lives in a box, not @State:
    /// none of it is read in body, and as @State every write (once or twice
    /// per keystroke, plus every async flag reset) bought a full extra body +
    /// updateNSView pass for the active row.
    @State private var syncBox = DocumentEditorSyncBox()
    /// The ONE piece of per-keystroke state the body genuinely renders from:
    /// whether the content is empty (drives the placeholder). Flips rarely.
    @State private var isTextEmptyFlag = true

    var fontSize: CGFloat = 16
    var fontDesign: NSFontDescriptor.SystemDesign = .default
    /// Count of consecutive numbered-list blocks immediately BEFORE this
    /// editor's document — block rows serialize a single-block document, so
    /// without the seed every numbered item renders "1.".
    var numberedListSeed: Int = 0
    var compact: Bool = false
    /// Per-document line-spacing delta from the Aa menu (Compact/Standard/Airy).
    var lineSpacingAdjustment: CGFloat = 0
    var placeholder: String = "Start typing..."
    var darkMode: Bool = false
    var overrideTextColor: NSColor? = nil
    var overrideFont: NSFont? = nil
    var headingDisclosureColor: NSColor? = nil
    var allowSlashCommands: Bool = true
    var allowMentions: Bool = true
    var allowSelectionMenu: Bool = true
    var allowImages: Bool = true
    var rendersElementChrome: Bool = true
    var singleLine: Bool = false
    var titleConfiguration: TitleEditorConfiguration? = nil
    var baseFontWeight: NSFont.Weight = .regular
    var typewriterMode: Bool = false
    var isEditable: Bool = true
    var scrollsInternally: Bool = false
    var textAlignment: NSTextAlignment = .natural
    var polishHighlights: WritingAnalysis? = nil
    var onSelectionChanged: ((EditorSelectionSnapshot) -> Void)? = nil
    var onContentHeightChange: ((CGFloat) -> Void)? = nil
    var onAIAction: ((AIWritingAction) -> Void)? = nil
    var onCustomPrompt: ((String) -> Void)? = nil
    var onWritingAIRequest: (() -> Void)? = nil
    var focusBandRange: NSRange? = nil
    var focusBandRangeProvider: ((String, NSRange) -> NSRange?)? = nil
    var editorTargetID: String? = nil
    var navigationTargetID: UUID? = nil
    var onPlainTextChange: ((String) -> Void)? = nil
    var onStructuredDocumentChange: ((RichDocument, String) -> Void)? = nil
    var onDocumentChange: ((RichDocument, String) -> Void)? = nil
    var onActivate: (() -> Void)? = nil
    var onDeactivate: (() -> Void)? = nil
    var onCommit: (() -> Void)? = nil
    var onBoundaryCommand: ((EditorBoundaryCommand) -> Bool)? = nil
    var onSlashCommandSelected: ((SlashCommand, String) -> Bool)? = nil
    /// Block-row mode: Return splits the block instead of inserting a newline.
    var splitsOnReturn: Bool = false
    /// The block this row renders (block rows only) — drag hit-testing.
    var rowBlockID: UUID? = nil
    /// Block-row mode: document sync runs synchronously per keystroke (the
    /// per-block document is one block, so serialization is trivial) — a
    /// debounce here lets stale content race structural edits like merges.
    var immediateDocumentSync: Bool = false
    /// One-shot caret placement after an external structural edit.
    var caretRequest: EditorCaretRequest? = nil
    var autoFocus: Bool = false

    /// Bumped whenever the editor content is rebuilt from the document by an
    /// EXTERNAL change — tells the text view to apply it even while focused.
    @State private var externalContentToken = 0

    /// Box-backed bindings for the representable. Reads are always live;
    /// writes never invalidate (the coordinator writes per keystroke) —
    /// except the plain-text setter, which flips the empty flag when
    /// emptiness changes so the placeholder shows/hides.
    private var attributedTextBinding: Binding<NSAttributedString> {
        Binding(
            get: { syncBox.attributedText },
            set: { syncBox.attributedText = $0 }
        )
    }

    private var plainTextBinding: Binding<String> {
        Binding(
            get: { syncBox.plainTextMirror },
            set: { setMirror($0) }
        )
    }

    /// The one writer of the plain mirror — keeps the placeholder's empty
    /// flag in sync without re-rendering on every keystroke.
    private func setMirror(_ newValue: String) {
        syncBox.plainTextMirror = newValue
        if isTextEmptyFlag != newValue.isEmpty {
            isTextEmptyFlag = newValue.isEmpty
        }
    }

    var body: some View {
        RichTextEditor(
            text: attributedTextBinding,
            plainText: plainTextBinding,
            fontSize: fontSize,
            fontDesign: fontDesign,
            compact: compact,
            lineSpacingAdjustment: lineSpacingAdjustment,
            placeholder: placeholder,
            darkMode: darkMode,
            overrideTextColor: overrideTextColor,
            overrideFont: overrideFont,
            headingDisclosureColor: headingDisclosureColor,
            allowSlashCommands: allowSlashCommands,
            allowMentions: allowMentions,
            allowSelectionMenu: allowSelectionMenu,
            allowImages: allowImages,
            rendersElementChrome: rendersElementChrome,
            singleLine: singleLine,
            titleConfiguration: titleConfiguration,
            baseFontWeight: baseFontWeight,
            typewriterMode: typewriterMode,
            isEditable: isEditable,
            scrollsInternally: scrollsInternally,
            polishHighlights: polishHighlights,
            textAlignment: textAlignment,
            onSelectionChanged: onSelectionChanged,
            onContentHeightChange: onContentHeightChange,
            onAIAction: onAIAction,
            onCustomPrompt: onCustomPrompt,
            onWritingAIRequest: onWritingAIRequest,
                focusBandRange: focusBandRange,
                focusBandRangeProvider: focusBandRangeProvider,
                editorTargetID: editorTargetID,
                navigationTargetID: navigationTargetID,
                onActivate: onActivate,
            onDeactivate: onDeactivate,
            onCommit: onCommit,
            onBoundaryCommand: onBoundaryCommand,
            onSlashCommandSelected: onSlashCommandSelected,
            splitsOnReturn: splitsOnReturn,
            rowBlockID: rowBlockID,
            rowBlockKind: splitsOnReturn ? document.blocks.first?.kind : nil,
            rowHeadingIsCollapsible: splitsOnReturn
                ? (document.blocks.first?.heading?.isCollapsible ?? false)
                : false,
            caretRequest: caretRequest,
            externalContentToken: externalContentToken,
            onPlainTextDidChange: { plainText in
                // Direct per-keystroke callback from the NSTextView coordinator.
                // This bypasses the SwiftUI @Binding→onChange chain which can
                // coalesce/skip updates when mutations come from AppKit.
                handleDirectPlainTextChange(plainText)
            },
            onStructuredDocumentChange: handleDirectStructuredDocumentChange,
            onContentCommitted: {
                // The coordinator committed the attributed buffer into the
                // (box-backed) binding — parse it into the document. This
                // replaces the old .onChange(of: attributedText) trigger,
                // which died with the box migration.
                syncDocumentFromEditor()
            },
            autoFocus: autoFocus,
            initialContent: { serializedEditorContent() },
            onSave: { _ in syncDocumentFromEditor() }
        )
        .onAppear {
            syncEditorFromDocument()
        }
        .onChange(of: document) { _, newValue in
            // Echo guard by VALUE: the async-reset flags below have a
            // one-tick dead window, and a self-write echo slipping through
            // re-serialized + force-replaced the storage per keystroke.
            if let selfWritten = syncBox.lastSelfWrittenDocument, selfWritten == newValue {
                return
            }
            guard !syncBox.isApplyingExternalUpdate, !syncBox.isSyncingFromEditor else { return }
            syncEditorFromDocument()
        }
        .onChange(of: fontSize) { _, _ in
            syncEditorForPresentationChange()
        }
        .onChange(of: fontDesign) { _, _ in
            syncEditorForPresentationChange()
        }
        .onChange(of: lineSpacingAdjustment) { _, _ in
            syncEditorForPresentationChange()
        }
        .onChange(of: numberedListSeed) { _, _ in
            // A sibling inserted above leaves this row's own document
            // value-identical, so onChange(of: document) can't re-number it.
            syncEditorForPresentationChange()
        }
        // No .onChange on the content mirrors: they live in the box now
        // (per-keystroke writes must not re-run this body). The coordinator
        // reports keystrokes through onPlainTextDidChange and commits the
        // attributed buffer through onContentCommitted below.
        .onDisappear {
            flushPendingSync()
        }
    }

    /// The fully styled editor content for the current document — the one
    /// serialization used by external syncs AND by the representable's
    /// mount-time seed (so both sides are always byte-identical).
    private func serializedEditorContent(preferLivePlainText: Bool = false) -> NSAttributedString {
        let resolved = resolvedDocumentForEditor(preferLivePlainText: preferLivePlainText)
        return EditorRhythmPolicy.applyingLineSpacing(
            lineSpacingAdjustment,
            to: EditorFontPolicy.applyingDesign(
                fontDesign,
                to: RichDocumentSerializer.attributedString(
                    from: resolved,
                    fontSize: fontSize,
                    darkMode: darkMode,
                    singleLine: singleLine,
                    baseFontWeight: baseFontWeight,
                    titleMode: titleConfiguration != nil,
                    numberedListSeed: numberedListSeed
                )
            )
        )
    }

    private func syncEditorFromDocument(preferLivePlainText: Bool = false) {
        syncBox.isApplyingExternalUpdate = true
        // External content now owns the view — a later external revert to a
        // previously self-written value must not be mistaken for an echo.
        syncBox.lastSelfWrittenDocument = nil
        let resolved = resolvedDocumentForEditor(preferLivePlainText: preferLivePlainText)
        syncBox.attributedText = serializedEditorContent(preferLivePlainText: preferLivePlainText)
        let resolvedPlainText = resolvedPlainTextForCallbacks(from: resolved)
        setMirror(resolvedPlainText)
        syncBox.lastEmittedPlainText = resolvedPlainText
        externalContentToken += 1
        DispatchQueue.main.async {
            syncBox.isApplyingExternalUpdate = false
        }
    }

    private func syncEditorForPresentationChange() {
        syncEditorFromDocument(preferLivePlainText: true)
    }

    /// Direct per-keystroke callback from the NSTextView coordinator — the
    /// ONE path for propagating text changes to consumers (the old
    /// @Binding→onChange fallback died with the box migration: the mirror is
    /// no longer @State, and the direct callback was already primary because
    /// SwiftUI could coalesce/skip onChange for AppKit-driven mutations).
    private func handleDirectPlainTextChange(_ plainText: String) {
        // NO guards on syncBox.isSyncingFromEditor or syncBox.isApplyingExternalUpdate here.
        // Both flags use async resets (DispatchQueue.main.async) which create
        // one-tick dead windows where keystrokes arriving from the NSTextView
        // delegate are silently dropped. The syncBox.lastEmittedPlainText dedup below
        // is sufficient to prevent echo loops.
        let resolvedPlainText = resolvedPlainTextForCallbacks(from: plainText)
        guard resolvedPlainText != syncBox.lastEmittedPlainText else { return }
        syncBox.lastEmittedPlainText = resolvedPlainText
        setMirror(resolvedPlainText)
        // Fire onPlainTextChange per-keystroke — it's lightweight (sets a String @State).
        // This keeps noteText/newItemText accurate for saves.
        onPlainTextChange?(resolvedPlainText)
        // Do not emit onDocumentChange from this plain-text-only path. The structured
        // RichDocument is produced from attributedText in syncDocumentFromEditor().
        // Emitting here with the previous document races parent views into writing
        // stale structured state back into the editor, which can reset selection/scroll
        // after Backspace or Return.
    }

    /// Immediate structured update for edits that must remount block UI, such as
    /// element insertion and collapse changes. Ordinary typing, including Return,
    /// stays on the lightweight path to avoid forcing the enclosing SwiftUI scroll
    /// view to relayout from inside AppKit's key handling.
    private func handleDirectStructuredDocumentChange(_ updated: RichDocument, plainText: String) {
        guard !syncBox.isApplyingExternalUpdate else { return }

        syncBox.documentSyncWorkItem?.cancel()
        let resolvedPlainText = resolvedPlainTextForCallbacks(from: plainText)
        syncBox.lastEmittedPlainText = resolvedPlainText
        setMirror(resolvedPlainText)

        guard updated != document else { return }

        syncBox.isSyncingFromEditor = true
        syncBox.lastSelfWrittenDocument = updated
        document = updated
        // The row reconciles IDs/kinds on the way in (BlockRowSyncPolicy) —
        // re-read the binding so the echo guard compares against the value
        // that will actually come back through onChange.
        syncBox.lastSelfWrittenDocument = document
        onStructuredDocumentChange?(updated, resolvedPlainText)
        onDocumentChange?(updated, resolvedPlainText)
        DispatchQueue.main.async {
            syncBox.isSyncingFromEditor = false
        }
    }

    private func syncDocumentFromEditor() {
        guard !syncBox.isApplyingExternalUpdate else { return }

        if titleConfiguration != nil {
            syncTitleDocumentFromEditor()
            return
        }

        // Debounce expensive RichDocument serialization (parses every line)
        syncBox.documentSyncWorkItem?.cancel()
        let capturedText = syncBox.attributedText
        let workItem = DispatchWorkItem {
            let updated = RichDocumentSerializer.document(from: capturedText)
            guard updated != document else { return }
            syncBox.isSyncingFromEditor = true
            syncBox.lastSelfWrittenDocument = updated
            document = updated
            // Re-read: the row's splice reconciles IDs (a parsed block carries
            // a fresh UUID) — without this, every deferred commit read as an
            // EXTERNAL change and re-serialized + replaced the row's storage.
            syncBox.lastSelfWrittenDocument = document
            onStructuredDocumentChange?(updated, updated.plainText)
            onDocumentChange?(updated, updated.plainText)
            // Self-heal for block rows: a row should only ever hold ONE
            // block. If a hard newline slipped into the text view (multi-line
            // paste, dictation), the content parses into several blocks and
            // the host splits them into separate rows — but this view would
            // keep showing every line, reading as duplicated text. Rebuild
            // from the row's (single-block) document once the split lands.
            let needsRowRebuild = splitsOnReturn && updated.blocks.count > 1
            DispatchQueue.main.async {
                syncBox.isSyncingFromEditor = false
                if needsRowRebuild {
                    syncEditorFromDocument()
                }
            }
        }
        if immediateDocumentSync {
            workItem.perform()
        } else {
            syncBox.documentSyncWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
        }
    }

    private func syncTitleDocumentFromEditor() {
        syncBox.documentSyncWorkItem?.cancel()

        let payload = TitleDocumentChangePayloadFactory.payload(from: syncBox.attributedText)
        let normalizedAttributedText = RichDocumentSerializer.attributedString(
            from: payload.document,
            fontSize: fontSize,
            darkMode: darkMode,
            baseFontWeight: baseFontWeight,
            titleMode: true
        )

        if !normalizedAttributedText.isEqual(to: syncBox.attributedText) {
            syncBox.isApplyingExternalUpdate = true
            syncBox.attributedText = normalizedAttributedText
            setMirror(payload.plainText)
            syncBox.lastEmittedPlainText = payload.plainText
            DispatchQueue.main.async {
                syncBox.isApplyingExternalUpdate = false
            }
        }

        guard payload.document != document else { return }

        syncBox.isSyncingFromEditor = true
        syncBox.lastSelfWrittenDocument = payload.document
        document = payload.document
        syncBox.lastSelfWrittenDocument = document
        onStructuredDocumentChange?(payload.document, payload.plainText)
        onDocumentChange?(payload.document, payload.plainText)
        DispatchQueue.main.async {
            syncBox.isSyncingFromEditor = false
        }
    }

    /// Force-sync any pending document changes immediately (called before view disappears).
    ///
    /// TextKitCoordinator syncs `plainText` immediately on every keystroke but defers
    /// `attributedText` by 50ms. If the view disappears within that window, `attributedText`
    /// is stale while `plainTextMirror` is current. We use `plainTextMirror` as the
    /// authoritative plain-text source to avoid losing the last keystrokes.
    private func flushPendingSync() {
        syncBox.documentSyncWorkItem?.cancel()
        guard !syncBox.isApplyingExternalUpdate else { return }

        // Dead-row guard: a block row whose block was merged/deleted away
        // tears down AFTER the document already dropped it — its binding
        // resolves to an empty document. Flushing then re-parses the dead
        // row's stale text and emits a full-document change for nothing
        // (a live block row always holds exactly one block).
        if splitsOnReturn && document.blocks.isEmpty { return }

        // plainTextMirror is synced immediately from NSTextView on every keystroke.
        // attributedText may be 50ms stale (deferred sync for performance).
        let latestPlainText = syncBox.plainTextMirror

        if titleConfiguration != nil {
            let payload = TitleDocumentChangePayloadFactory.payload(from: syncBox.attributedText)
            // Also check if plain text diverged from what attributedText reports
            let plainTextDiverged = latestPlainText != payload.plainText && latestPlainText != syncBox.lastEmittedPlainText
            guard payload.document != document || plainTextDiverged else { return }
            syncBox.isSyncingFromEditor = true
            syncBox.lastSelfWrittenDocument = payload.document
            document = payload.document
            syncBox.lastSelfWrittenDocument = document
            let emitPlainText = plainTextDiverged ? latestPlainText : payload.plainText
            setMirror(emitPlainText)
            onStructuredDocumentChange?(payload.document, emitPlainText)
            onDocumentChange?(payload.document, emitPlainText)
            syncBox.isSyncingFromEditor = false
            return
        }

        let updated = RichDocumentSerializer.document(from: syncBox.attributedText)
        // Check if plain text advanced beyond what attributedText contains
        // (i.e. user typed but the 50ms deferred sync hasn't fired yet)
        let plainTextDiverged = latestPlainText != updated.plainText && latestPlainText != syncBox.lastEmittedPlainText
        guard updated != document || plainTextDiverged else { return }
        syncBox.isSyncingFromEditor = true
        syncBox.lastSelfWrittenDocument = updated
        document = updated
        syncBox.lastSelfWrittenDocument = document
        let emitPlainText = plainTextForEmission(
            latestPlainText: latestPlainText,
            parsedDocument: updated,
            plainTextDiverged: plainTextDiverged
        )
        setMirror(emitPlainText)
        onStructuredDocumentChange?(updated, emitPlainText)
        onDocumentChange?(updated, emitPlainText)
        syncBox.isSyncingFromEditor = false
    }

    private func resolvedDocumentForEditor(preferLivePlainText: Bool = false) -> RichDocument {
        // Block rows: the document is ALWAYS authoritative. The legacy
        // plain-text fallbacks below exist for old notes opened before the
        // structured document existed — in a block row they are poison: a
        // block that just became empty (Return-at-start split, backspace,
        // slash transform) reads as an "empty document" while plainTextMirror
        // still lags ~50ms with the pre-edit text, and migrating the mirror
        // RESURRECTS that text, which then writes back over the document.
        // That was the entire duplication class.
        if splitsOnReturn {
            return document
        }

        let documentPlainText = resolvedPlainTextForCallbacks(from: document)
        let resolved: RichDocument

        if preferLivePlainText {
            let liveDocument = liveDocumentForPresentationChange()
            let livePlainText = resolvedPlainTextForCallbacks(from: liveDocument)

            if livePlainText == syncBox.plainTextMirror, !(liveDocument.isEmpty && !document.isEmpty) {
                resolved = liveDocument
            } else if documentPlainText != syncBox.plainTextMirror {
                resolved = RichDocument.migrateLegacy(syncBox.plainTextMirror)
            } else {
                resolved = document
            }
        } else if document.isEmpty && !syncBox.plainTextMirror.isEmpty {
            resolved = RichDocument.migrateLegacy(syncBox.plainTextMirror)
        } else {
            resolved = document
        }

        return titleConfiguration == nil
            ? resolved
            : RichDocumentPersistence.normalizedTitleDocument(resolved)
    }

    private func liveDocumentForPresentationChange() -> RichDocument {
        if titleConfiguration != nil {
            return TitleDocumentChangePayloadFactory.payload(from: syncBox.attributedText).document
        }
        return RichDocumentSerializer.document(from: syncBox.attributedText)
    }

    private func resolvedPlainTextForCallbacks(from document: RichDocument) -> String {
        titleConfiguration == nil
            ? document.plainText
            : RichDocumentPersistence.titlePlainText(from: document)
    }

    private func resolvedPlainTextForCallbacks(from plainText: String) -> String {
        titleConfiguration == nil
            ? plainText
            : RichDocumentPersistence.normalizedTitleString(plainText)
    }

    private func plainTextForEmission(
        latestPlainText: String,
        parsedDocument: RichDocument,
        plainTextDiverged: Bool
    ) -> String {
        guard titleConfiguration == nil else {
            return plainTextDiverged
                ? RichDocumentPersistence.normalizedTitleString(latestPlainText)
                : RichDocumentPersistence.titlePlainText(from: parsedDocument)
        }
        if parsedDocument.containsCollapsedHiddenContent {
            return parsedDocument.plainText
        }
        return plainTextDiverged ? latestPlainText : parsedDocument.plainText
    }
}

struct TitleDocumentChangePayload: Equatable {
    let document: RichDocument
    let plainText: String
}

enum TitleDocumentChangePayloadFactory {
    static func payload(from attributedText: NSAttributedString) -> TitleDocumentChangePayload {
        let normalizedDocument = RichDocumentPersistence.normalizedTitleDocument(
            RichDocumentSerializer.document(from: attributedText)
        )
        return TitleDocumentChangePayload(
            document: normalizedDocument,
            plainText: RichDocumentPersistence.titlePlainText(from: normalizedDocument)
        )
    }
}
