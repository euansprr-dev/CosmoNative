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

    var fontSize: CGFloat = 16
    var compact: Bool = false
    var placeholder: String = "Start typing..."
    var darkMode: Bool = false
    var allowSlashCommands: Bool = true
    var allowMentions: Bool = true
    var allowSelectionMenu: Bool = true
    var allowImages: Bool = true
    var singleLine: Bool = false
    var baseFontWeight: NSFont.Weight = .regular
    var textAlignment: NSTextAlignment = .natural
    var polishHighlights: WritingAnalysis? = nil
    var onSelectionChanged: ((EditorSelectionSnapshot) -> Void)? = nil
    var onContentHeightChange: ((CGFloat) -> Void)? = nil
    var onAIAction: ((AIWritingAction) -> Void)? = nil
    var onCustomPrompt: ((String) -> Void)? = nil
    var onDocumentChange: ((RichDocument, String) -> Void)? = nil

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
            baseFontWeight: baseFontWeight,
            polishHighlights: polishHighlights,
            textAlignment: textAlignment,
            onSelectionChanged: onSelectionChanged,
            onContentHeightChange: onContentHeightChange,
            onAIAction: onAIAction,
            onCustomPrompt: onCustomPrompt,
            onSave: { _ in syncDocumentFromEditor() }
        )
        .onAppear {
            syncEditorFromDocument()
        }
        .onChange(of: document) { _, _ in
            guard !isApplyingExternalUpdate, !isSyncingFromEditor else { return }
            syncEditorFromDocument()
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
        let resolved = document.isEmpty && !plainTextMirror.isEmpty
            ? RichDocument.migrateLegacy(plainTextMirror)
            : document
        attributedText = RichDocumentSerializer.attributedString(
            from: resolved,
            fontSize: fontSize,
            darkMode: darkMode,
            singleLine: singleLine,
            baseFontWeight: baseFontWeight
        )
        plainTextMirror = resolved.plainText
        DispatchQueue.main.async {
            isApplyingExternalUpdate = false
        }
    }

    private func syncDocumentFromEditor() {
        guard !isApplyingExternalUpdate else { return }

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
            onDocumentChange?(updated, updated.plainText)
            DispatchQueue.main.async { isSyncingFromEditor = false }
        }
        documentSyncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    /// Force-sync any pending document changes immediately (called before view disappears)
    private func flushPendingSync() {
        documentSyncWorkItem?.cancel()
        guard !isApplyingExternalUpdate else { return }
        let updated = RichDocumentSerializer.document(from: attributedText)
        guard updated != document else { return }
        isSyncingFromEditor = true
        document = updated
        plainTextMirror = updated.plainText
        onDocumentChange?(updated, updated.plainText)
        isSyncingFromEditor = false
    }
}
