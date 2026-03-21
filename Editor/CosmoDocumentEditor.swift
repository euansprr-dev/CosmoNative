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
    @State private var lastEmittedPlainText = ""

    var fontSize: CGFloat = 16
    var compact: Bool = false
    var placeholder: String = "Start typing..."
    var darkMode: Bool = false
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
            onActivate: onActivate,
            onDeactivate: onDeactivate,
            onCommit: onCommit,
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
        guard !isApplyingExternalUpdate else { return }
        let resolvedPlainText = resolvedPlainTextForCallbacks(from: plainText)
        guard resolvedPlainText != lastEmittedPlainText else { return }
        lastEmittedPlainText = resolvedPlainText
        onPlainTextChange?(resolvedPlainText)
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
            DispatchQueue.main.async { isSyncingFromEditor = false }
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

    /// Force-sync any pending document changes immediately (called before view disappears)
    private func flushPendingSync() {
        documentSyncWorkItem?.cancel()
        guard !isApplyingExternalUpdate else { return }

        if titleConfiguration != nil {
            let payload = TitleDocumentChangePayloadFactory.payload(from: attributedText)
            guard payload.document != document else { return }
            isSyncingFromEditor = true
            document = payload.document
            plainTextMirror = payload.plainText
            onStructuredDocumentChange?(payload.document, payload.plainText)
            onDocumentChange?(payload.document, payload.plainText)
            isSyncingFromEditor = false
            return
        }

        let updated = RichDocumentSerializer.document(from: attributedText)
        guard updated != document else { return }
        isSyncingFromEditor = true
        document = updated
        plainTextMirror = updated.plainText
        onStructuredDocumentChange?(updated, updated.plainText)
        onDocumentChange?(updated, updated.plainText)
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
