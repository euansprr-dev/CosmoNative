import SwiftUI
import AppKit

struct EditorSelectionSnapshot: Equatable {
    var range: NSRange
    var text: String
    var rectInEditor: CGRect

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
            guard !isApplyingExternalUpdate, !isSyncingFromEditor else { return }
            syncEditorFromDocument()
        }
        .onChange(of: fontSize) { _, _ in
            syncEditorFromDocument()
        }
        .onChange(of: fontDesign) { _, _ in
            syncEditorFromDocument()
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

    private func syncEditorFromDocument() {
        isApplyingExternalUpdate = true
        let resolved = resolvedDocumentForEditor()
        attributedText = EditorFontPolicy.applyingDesign(
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
        let resolvedPlainText = resolvedPlainTextForCallbacks(from: resolved)
        plainTextMirror = resolvedPlainText
        lastEmittedPlainText = resolvedPlainText
        externalContentToken += 1
        DispatchQueue.main.async {
            isApplyingExternalUpdate = false
        }
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
            DispatchQueue.main.async {
                isSyncingFromEditor = false
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

    private func resolvedDocumentForEditor() -> RichDocument {
        let resolved = document.isEmpty && !plainTextMirror.isEmpty
            ? RichDocument.migrateLegacy(plainTextMirror)
            : document
        return titleConfiguration == nil
            ? resolved
            : RichDocumentPersistence.normalizedTitleDocument(resolved)
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
