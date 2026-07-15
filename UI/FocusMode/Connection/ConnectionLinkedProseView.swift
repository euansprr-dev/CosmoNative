// CosmoOS/UI/FocusMode/Connection/ConnectionLinkedProseView.swift
// NSTextView-backed twin of ConnectionLinkedText for the section detail's
// item rows: same render-time mention linkification (retroactive by
// construction), but with a REAL text selection the app can read — so the
// concept-mint pill works on the user's own bullets, not just the
// conversation. Self-sizing on the CosmoAssistantProseTextView pattern.

import SwiftUI
import AppKit

struct ConnectionLinkedProseView: NSViewRepresentable {
    let text: String
    /// Where this item lives — rides selection reports so a minted page can
    /// carry the bullet as its first claim with provenance.
    var originSection: ConnectionSectionType?

    @Environment(\.connectionLinkTargets) private var linkTargets
    @Environment(\.conceptMintReporter) private var mintReporter

    private static let bodyFont = NSFont.systemFont(ofSize: 13)

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.textContainerInset = .zero
        textView.delegate = context.coordinator
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.lineFragmentPadding = 0
        textView.linkTextAttributes = [
            .foregroundColor: NSColor(CosmoMentionColors.connection),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand
        ]
        _ = textView.layoutManager   // Pin to TextKit 1 (matches the prose view).
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.shouldUpdate(text: text, targets: linkTargets) else { return }
        textView.textStorage?.beginEditing()
        textView.textStorage?.setAttributedString(Self.attributedString(text: text, targets: linkTargets))
        textView.textStorage?.endEditing()
        context.coordinator.record(text: text, targets: linkTargets)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        let measuredWidth = proposal.width ?? nsView.bounds.width
        let width = max(1, measuredWidth > 0 ? measuredWidth : 260)
        guard let layoutManager = nsView.layoutManager,
              let textContainer = nsView.textContainer else {
            return CGSize(width: width, height: 20)
        }
        if let cached = context.coordinator.cachedSize(forWidth: width) {
            return cached
        }
        if abs(textContainer.containerSize.width - width) > 0.25 {
            textContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        let size = CGSize(width: width, height: ceil(used.height) + 2)
        context.coordinator.cacheSize(size, forWidth: width)
        return size
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Attributed content (mirror of ConnectionLinkedText.attributed)

    static func attributedString(text: String, targets: ConnectionLinkTargets) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        let result = NSMutableAttributedString(string: text, attributes: [
            .foregroundColor: NSColor(DS.text),
            .font: bodyFont,
            .paragraphStyle: paragraph
        ])
        guard !targets.isEmpty else { return result }
        let nsText = text as NSString
        var claimed: [NSRange] = []
        for target in targets.targets {
            let range = nsText.range(of: target.title, options: [.caseInsensitive])
            guard range.location != NSNotFound,
                  !claimed.contains(where: { NSIntersectionRange($0, range).length > 0 }),
                  let url = URL(string: "cosmo://connection/\(target.uuid)") else { continue }
            result.addAttribute(.link, value: url, range: range)
            claimed.append(range)
        }
        return result
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ConnectionLinkedProseView
        private var lastText: String = ""
        private var lastTargets = ConnectionLinkTargets.empty
        private var sizeCache: [CGFloat: CGSize] = [:]

        init(parent: ConnectionLinkedProseView) {
            self.parent = parent
        }

        func shouldUpdate(text: String, targets: ConnectionLinkTargets) -> Bool {
            text != lastText || targets != lastTargets
        }

        func record(text: String, targets: ConnectionLinkTargets) {
            lastText = text
            lastTargets = targets
            sizeCache.removeAll()
        }

        func cachedSize(forWidth width: CGFloat) -> CGSize? { sizeCache[width] }
        func cacheSize(_ size: CGSize, forWidth width: CGFloat) { sizeCache[width] = size }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL, url.scheme == "cosmo", url.host == "connection" else { return false }
            let uuid = url.lastPathComponent
            guard !uuid.isEmpty else { return false }
            ConnectionLinkOpener.open(uuid: uuid)
            return true
        }

        /// Item-text selections carry the whole bullet as context — a minted
        /// page is born with it as its first claim (with provenance).
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let reporter = parent.mintReporter,
                  let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            let nsString = textView.string as NSString
            guard range.length > 0, range.location + range.length <= nsString.length else {
                Task { @MainActor in reporter(nil) }
                return
            }
            let selected = nsString.substring(with: range)
            let anchor = SelectionAnchorSpace.globalRect(
                fromScreen: textView.firstRect(forCharacterRange: range, actualRange: nil),
                for: textView
            )
            let snippet = parent.text
            let section = parent.originSection
            Task { @MainActor in
                guard let anchor else {
                    reporter(nil)
                    return
                }
                reporter(ConceptMintSelectionReport(
                    text: selected,
                    anchor: anchor,
                    contextSnippet: snippet,
                    originSection: section
                ))
            }
        }
    }
}
