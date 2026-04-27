// CosmoOS/UI/FocusMode/Inquiry/Source/InternalSourceView.swift
// Renders an internal Note / Research / Swipe atom as a read-only document.

import SwiftUI

@MainActor
struct InternalSourceView: View {
    let sourceUUID: String
    @Binding var lastSelectedText: String

    @State private var atom: Atom?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space12) {
                if isLoading {
                    ProgressView().padding(.top, DS.space32)
                } else if let atom {
                    Text(atom.title ?? "Untitled")
                        .font(.system(size: 26, weight: .semibold, design: .serif))
                        .foregroundStyle(CosmoColors.textPrimary)
                    Text(atom.type.displayName)
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textTertiary)
                    if let body = atom.body, !body.isEmpty {
                        SelectableText(text: body, lastSelectedText: $lastSelectedText)
                    } else {
                        Text("No body content.")
                            .font(CosmoTypography.body)
                            .foregroundStyle(CosmoColors.textTertiary)
                    }
                } else {
                    Text("Source not found.")
                        .font(CosmoTypography.body)
                        .foregroundStyle(CosmoColors.textSecondary)
                }
            }
            .padding(.horizontal, DS.space24)
            .padding(.vertical, DS.space20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .task { await load() }
    }

    private func load() async {
        if let loaded = try? await AtomRepository.shared.fetch(uuid: sourceUUID) {
            atom = loaded
        }
        isLoading = false
    }
}

/// AppKit-backed selectable text that pushes the current selection up to a binding.
struct SelectableText: NSViewRepresentable {
    let text: String
    @Binding var lastSelectedText: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let textView = NSTextView()
        textView.string = text
        textView.isEditable = false
        textView.isSelectable = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.font = NSFont(name: "New York", size: 16) ?? NSFont.systemFont(ofSize: 16)
        textView.textColor = NSColor.labelColor
        textView.drawsBackground = false
        textView.delegate = context.coordinator
        textView.textContainer?.containerSize = NSSize(width: 720, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scroll.documentView = textView
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        if let tv = scroll.documentView as? NSTextView, tv.string != text {
            tv.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SelectableText
        init(parent: SelectableText) { self.parent = parent }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let range = tv.selectedRange()
            if range.length > 0 {
                let nsString = tv.string as NSString
                if range.location + range.length <= nsString.length {
                    let selected = nsString.substring(with: range)
                    Task { @MainActor in
                        parent.lastSelectedText = selected
                    }
                }
            }
        }
    }
}
