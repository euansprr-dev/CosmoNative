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
        guard design != .default,
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
        ("> ", .quote, nil)
    ]

    static func match(text: String, cursorLocation: Int) -> MarkdownBlockAlias? {
        if text == "---", cursorLocation == 3 {
            return MarkdownBlockAlias(kind: .divider, checked: nil, utf16Length: 3)
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

struct CosmoDocumentEditor: View {
    @Binding var document: RichDocument

    @State private var attributedText = NSAttributedString()
    @State private var plainTextMirror = ""
    @State private var isApplyingExternalUpdate = false
    @State private var isSyncingFromEditor = false
    @State private var documentSyncWorkItem: DispatchWorkItem?
    @State private var lastEmittedPlainText = ""

    var fontSize: CGFloat = 16
    var fontDesign: NSFontDescriptor.SystemDesign = .default
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

    var body: some View {
        RichTextEditor(
            text: $attributedText,
            plainText: $plainTextMirror,
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
            caretRequest: caretRequest,
            externalContentToken: externalContentToken,
            onPlainTextDidChange: { plainText in
                // Direct per-keystroke callback from the NSTextView coordinator.
                // This bypasses the SwiftUI @Binding→onChange chain which can
                // coalesce/skip updates when mutations come from AppKit.
                handleDirectPlainTextChange(plainText)
            },
            onStructuredDocumentChange: handleDirectStructuredDocumentChange,
            autoFocus: autoFocus,
            onSave: { _ in syncDocumentFromEditor() }
        )
        .onAppear {
            syncEditorFromDocument()
        }
        .onChange(of: document) { _, _ in
            if splitsOnReturn {
            }
            guard !isApplyingExternalUpdate, !isSyncingFromEditor else { return }
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
        .onChange(of: plainTextMirror) { _, newValue in
            handlePlainTextMirrorChange(newValue)
        }
        .onChange(of: attributedText) { _, _ in
            syncDocumentFromEditor()
        }
        .onDisappear {
            flushPendingSync()
        }
    }

    private func syncEditorFromDocument(preferLivePlainText: Bool = false) {
        isApplyingExternalUpdate = true
        let resolved = resolvedDocumentForEditor(preferLivePlainText: preferLivePlainText)
        if splitsOnReturn {
        }
        attributedText = EditorRhythmPolicy.applyingLineSpacing(
            lineSpacingAdjustment,
            to: EditorFontPolicy.applyingDesign(
                fontDesign,
                to: RichDocumentSerializer.attributedString(
                    from: resolved,
                    fontSize: fontSize,
                    darkMode: darkMode,
                    singleLine: singleLine,
                    baseFontWeight: baseFontWeight,
                    titleMode: titleConfiguration != nil
                )
            )
        )
        let resolvedPlainText = resolvedPlainTextForCallbacks(from: resolved)
        plainTextMirror = resolvedPlainText
        lastEmittedPlainText = resolvedPlainText
        externalContentToken += 1
        DispatchQueue.main.async {
            isApplyingExternalUpdate = false
        }
    }

    private func syncEditorForPresentationChange() {
        syncEditorFromDocument(preferLivePlainText: true)
    }

    private func handlePlainTextMirrorChange(_ plainText: String) {
        // NO guards on isSyncingFromEditor or isApplyingExternalUpdate.
        // Both flags use async resets that create one-tick dead windows where
        // keystrokes are silently dropped. The lastEmittedPlainText dedup below
        // is sufficient to prevent echo loops.
        let resolvedPlainText = resolvedPlainTextForCallbacks(from: plainText)
        guard resolvedPlainText != lastEmittedPlainText else { return }
        lastEmittedPlainText = resolvedPlainText
        onPlainTextChange?(resolvedPlainText)
        // Don't fire onDocumentChange here — it's handled by handleDirectPlainTextChange
        // with throttling. Firing it here too would double the callbacks and cause jitter.
    }

    /// Direct per-keystroke callback from the NSTextView coordinator.
    /// This is the PRIMARY path for propagating text changes to consumers.
    /// The SwiftUI @Binding→onChange chain (handlePlainTextMirrorChange) is unreliable
    /// because SwiftUI can coalesce/skip onChange when @Binding is mutated from AppKit.
    private func handleDirectPlainTextChange(_ plainText: String) {
        // NO guards on isSyncingFromEditor or isApplyingExternalUpdate here.
        // Both flags use async resets (DispatchQueue.main.async) which create
        // one-tick dead windows where keystrokes arriving from the NSTextView
        // delegate are silently dropped. The lastEmittedPlainText dedup below
        // is sufficient to prevent echo loops.
        let resolvedPlainText = resolvedPlainTextForCallbacks(from: plainText)
        guard resolvedPlainText != lastEmittedPlainText else { return }
        lastEmittedPlainText = resolvedPlainText
        plainTextMirror = resolvedPlainText
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
        guard !isApplyingExternalUpdate else { return }

        documentSyncWorkItem?.cancel()
        let resolvedPlainText = resolvedPlainTextForCallbacks(from: plainText)
        lastEmittedPlainText = resolvedPlainText
        plainTextMirror = resolvedPlainText

        guard updated != document else { return }

        isSyncingFromEditor = true
        document = updated
        onStructuredDocumentChange?(updated, resolvedPlainText)
        onDocumentChange?(updated, resolvedPlainText)
        DispatchQueue.main.async {
            isSyncingFromEditor = false
        }
    }

    private func syncDocumentFromEditor() {
        guard !isApplyingExternalUpdate else { return }

        if titleConfiguration != nil {
            syncTitleDocumentFromEditor()
            return
        }

        // Debounce expensive RichDocument serialization (parses every line)
        documentSyncWorkItem?.cancel()
        let capturedText = attributedText
        let workItem = DispatchWorkItem {
            let updated = RichDocumentSerializer.document(from: capturedText)
            guard updated != document else { return }
            isSyncingFromEditor = true
            document = updated
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
                isSyncingFromEditor = false
                if needsRowRebuild {
                    syncEditorFromDocument()
                }
            }
        }
        if immediateDocumentSync {
            workItem.perform()
        } else {
            documentSyncWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
        }
    }

    private func syncTitleDocumentFromEditor() {
        documentSyncWorkItem?.cancel()

        let payload = TitleDocumentChangePayloadFactory.payload(from: attributedText)
        let normalizedAttributedText = RichDocumentSerializer.attributedString(
            from: payload.document,
            fontSize: fontSize,
            darkMode: darkMode,
            baseFontWeight: baseFontWeight,
            titleMode: true
        )

        if !normalizedAttributedText.isEqual(to: attributedText) {
            isApplyingExternalUpdate = true
            attributedText = normalizedAttributedText
            plainTextMirror = payload.plainText
            lastEmittedPlainText = payload.plainText
            DispatchQueue.main.async {
                isApplyingExternalUpdate = false
            }
        }

        guard payload.document != document else { return }

        isSyncingFromEditor = true
        document = payload.document
        onStructuredDocumentChange?(payload.document, payload.plainText)
        onDocumentChange?(payload.document, payload.plainText)
        DispatchQueue.main.async {
            isSyncingFromEditor = false
        }
    }

    /// Force-sync any pending document changes immediately (called before view disappears).
    ///
    /// TextKitCoordinator syncs `plainText` immediately on every keystroke but defers
    /// `attributedText` by 50ms. If the view disappears within that window, `attributedText`
    /// is stale while `plainTextMirror` is current. We use `plainTextMirror` as the
    /// authoritative plain-text source to avoid losing the last keystrokes.
    private func flushPendingSync() {
        documentSyncWorkItem?.cancel()
        guard !isApplyingExternalUpdate else { return }

        // plainTextMirror is synced immediately from NSTextView on every keystroke.
        // attributedText may be 50ms stale (deferred sync for performance).
        let latestPlainText = plainTextMirror

        if titleConfiguration != nil {
            let payload = TitleDocumentChangePayloadFactory.payload(from: attributedText)
            // Also check if plain text diverged from what attributedText reports
            let plainTextDiverged = latestPlainText != payload.plainText && latestPlainText != lastEmittedPlainText
            guard payload.document != document || plainTextDiverged else { return }
            isSyncingFromEditor = true
            document = payload.document
            let emitPlainText = plainTextDiverged ? latestPlainText : payload.plainText
            plainTextMirror = emitPlainText
            onStructuredDocumentChange?(payload.document, emitPlainText)
            onDocumentChange?(payload.document, emitPlainText)
            isSyncingFromEditor = false
            return
        }

        let updated = RichDocumentSerializer.document(from: attributedText)
        // Check if plain text advanced beyond what attributedText contains
        // (i.e. user typed but the 50ms deferred sync hasn't fired yet)
        let plainTextDiverged = latestPlainText != updated.plainText && latestPlainText != lastEmittedPlainText
        guard updated != document || plainTextDiverged else { return }
        isSyncingFromEditor = true
        document = updated
        let emitPlainText = plainTextForEmission(
            latestPlainText: latestPlainText,
            parsedDocument: updated,
            plainTextDiverged: plainTextDiverged
        )
        plainTextMirror = emitPlainText
        onStructuredDocumentChange?(updated, emitPlainText)
        onDocumentChange?(updated, emitPlainText)
        isSyncingFromEditor = false
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

            if livePlainText == plainTextMirror, !(liveDocument.isEmpty && !document.isEmpty) {
                resolved = liveDocument
            } else if documentPlainText != plainTextMirror {
                resolved = RichDocument.migrateLegacy(plainTextMirror)
            } else {
                resolved = document
            }
        } else if document.isEmpty && !plainTextMirror.isEmpty {
            resolved = RichDocument.migrateLegacy(plainTextMirror)
        } else {
            resolved = document
        }

        return titleConfiguration == nil
            ? resolved
            : RichDocumentPersistence.normalizedTitleDocument(resolved)
    }

    private func liveDocumentForPresentationChange() -> RichDocument {
        if titleConfiguration != nil {
            return TitleDocumentChangePayloadFactory.payload(from: attributedText).document
        }
        return RichDocumentSerializer.document(from: attributedText)
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
