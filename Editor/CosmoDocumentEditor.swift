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

struct CosmoDocumentEditor: View {
    @Binding var document: RichDocument

    @State private var attributedText = NSAttributedString()
    @State private var plainTextMirror = ""
    @State private var isApplyingExternalUpdate = false
    @State private var isSyncingFromEditor = false
    @State private var documentSyncWorkItem: DispatchWorkItem?
    @State private var directChangeWorkItem: DispatchWorkItem?
    @State private var lastEmittedPlainText = ""

    var fontSize: CGFloat = 16
    var compact: Bool = false
    var placeholder: String = "Start typing..."
    var darkMode: Bool = false
    var overrideTextColor: NSColor? = nil
    var overrideFont: NSFont? = nil
    var allowSlashCommands: Bool = true
    var allowMentions: Bool = true
    var allowSelectionMenu: Bool = true
    var allowImages: Bool = true
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
    var onPlainTextChange: ((String) -> Void)? = nil
    var onStructuredDocumentChange: ((RichDocument, String) -> Void)? = nil
    var onDocumentChange: ((RichDocument, String) -> Void)? = nil
    var onActivate: (() -> Void)? = nil
    var onDeactivate: (() -> Void)? = nil
    var onCommit: (() -> Void)? = nil
    var autoFocus: Bool = false

    var body: some View {
        RichTextEditor(
            text: $attributedText,
            plainText: $plainTextMirror,
            fontSize: fontSize,
            compact: compact,
            placeholder: placeholder,
            darkMode: darkMode,
            overrideTextColor: overrideTextColor,
            overrideFont: overrideFont,
            allowSlashCommands: allowSlashCommands,
            allowMentions: allowMentions,
            allowSelectionMenu: allowSelectionMenu,
            allowImages: allowImages,
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
            onActivate: onActivate,
            onDeactivate: onDeactivate,
            onCommit: onCommit,
            onPlainTextDidChange: { plainText in
                // Direct per-keystroke callback from the NSTextView coordinator.
                // This bypasses the SwiftUI @Binding→onChange chain which can
                // coalesce/skip updates when mutations come from AppKit.
                handleDirectPlainTextChange(plainText)
            },
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
        attributedText = RichDocumentSerializer.attributedString(
            from: resolved,
            fontSize: fontSize,
            darkMode: darkMode,
            singleLine: singleLine,
            baseFontWeight: baseFontWeight,
            titleMode: titleConfiguration != nil
        )
        let resolvedPlainText = resolvedPlainTextForCallbacks(from: resolved)
        plainTextMirror = resolvedPlainText
        lastEmittedPlainText = resolvedPlainText
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
        // Throttle onDocumentChange to ~100ms — it triggers SwiftUI view body re-evaluation
        // and updateNSView, which causes visible text jitter if fired per-keystroke.
        directChangeWorkItem?.cancel()
        let capturedPlainText = resolvedPlainText
        let workItem = DispatchWorkItem {
            onDocumentChange?(document, capturedPlainText)
        }
        directChangeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func syncDocumentFromEditor() {
        guard !isApplyingExternalUpdate else { return }

        if titleConfiguration != nil {
            syncTitleDocumentFromEditor()
            return
        }

        // Immediately update plain text (cheap) for downstream consumers
        let currentPlain = attributedText.string
        if currentPlain != plainTextMirror {
            plainTextMirror = currentPlain
            onDocumentChange?(document, currentPlain)
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
            isSyncingFromEditor = false
        }
        documentSyncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
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
        // Fire any pending throttled direct change immediately before disappearing
        if let pending = directChangeWorkItem {
            pending.cancel()
            directChangeWorkItem = nil
            onDocumentChange?(document, plainTextMirror)
        }
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
        let emitPlainText = plainTextDiverged ? latestPlainText : updated.plainText
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
