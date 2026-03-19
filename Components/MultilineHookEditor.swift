import SwiftUI
import AppKit

/// A multiline text editor for hook editing that supports:
/// - **Shift+Enter** to insert a newline
/// - **Enter** to commit the edit
/// - Auto-grows vertically to fit content
struct MultilineHookEditor: NSViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var fontSize: CGFloat
    var onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = HookNSTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: fontSize, weight: .medium)
        textView.textColor = NSColor(DS.text)
        textView.insertionPointColor = NSColor(DS.text)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.delegate = context.coordinator
        textView.onCommit = onCommit
        textView.string = text

        scrollView.documentView = textView

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MultilineHookEditor

        init(_ parent: MultilineHookEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused.wrappedValue = false
        }
    }
}

/// Custom NSTextView that intercepts Enter vs Shift+Enter
private final class HookNSTextView: NSTextView {
    var onCommit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { // Return key
            if event.modifierFlags.contains(.shift) {
                // Shift+Enter: insert newline
                insertNewline(nil)
            } else {
                // Enter: commit edit
                onCommit?()
            }
        } else {
            super.keyDown(with: event)
        }
    }
}
