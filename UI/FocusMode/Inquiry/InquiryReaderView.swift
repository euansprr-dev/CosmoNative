// CosmoOS/UI/FocusMode/Inquiry/InquiryReaderView.swift
// Reader morph — when the user opens a source from the right rail, the center stele
// transforms into a clean reader hosting WebSourceView or InternalSourceView.

import SwiftUI

@MainActor
struct InquiryReaderView: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let tab: SourceTab

    @State private var lastSelectedText: String = ""
    @State private var selectionTimestamp: Int?
    @State private var selectionAnchor: CGRect?
    @State private var loadState: WebSourceLoadState = .loading

    var body: some View {
        // Pure content: chrome (back / title / browser / reader toggle) lives
        // in the Study's center island; the shell frames this view as a
        // document sheet.
        content
            .overlay { capturePillLayer }
            .animation(ProMotionSprings.gentle, value: lastSelectedText.isEmpty)
    }

    /// Highlighting shows ONE verb next to the selection — Capture. The
    /// highlight then rides the same routed pipeline as a typed thought;
    /// the classifier and router do the sorting, never the user.
    @ViewBuilder
    private var capturePillLayer: some View {
        if !lastSelectedText.isEmpty {
            GeometryReader { geo in
                let frame = geo.frame(in: .global)
                // No rect from the source (shouldn't happen) → land the pill
                // on the reader's calm bottom zone instead of vanishing.
                let fallback = CGRect(x: geo.size.width / 2, y: geo.size.height - 72, width: 0, height: 0)
                let anchor = selectionAnchor.map { $0.offsetBy(dx: -frame.minX, dy: -frame.minY) } ?? fallback
                SelectionCapturePill(anchor: anchor, container: geo.size) {
                    let selection = lastSelectedText
                    let timestamp = selectionTimestamp
                    dismissSelection()
                    Task {
                        _ = await viewModel.captureSelection(
                            selection,
                            sourceTab: tab,
                            timestampSeconds: timestamp
                        )
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
    }

    private func dismissSelection() {
        lastSelectedText = ""
        selectionTimestamp = nil
        selectionAnchor = nil
    }

    private var readerMode: Bool {
        viewModel.readerPrefersReaderMode
    }

    @ViewBuilder
    private var content: some View {
        switch tab.kind {
        case .web, .pdf:
            if let urlString = tab.url, let url = URL(string: urlString) {
                webContent(url: url, readerMode: readerMode)
            } else {
                missingURLState
            }
        case .youTube:
            // The study reader: just the video and its transcript — never the
            // watch page with its feed, comments, and recommendations.
            StudyYouTubeReaderView(
                viewModel: viewModel,
                tab: tab,
                lastSelectedText: $lastSelectedText,
                selectionTimestamp: $selectionTimestamp,
                selectionAnchor: $selectionAnchor
            )
        case .internalAtom, .swipe:
            if let sourceUUID = tab.sourceUUID {
                InternalSourceView(
                    sourceUUID: sourceUUID,
                    lastSelectedText: $lastSelectedText,
                    selectionAnchor: $selectionAnchor
                )
            } else {
                missingURLState
            }
        case .pageScan:
            if let sourceUUID = tab.sourceUUID {
                PageScanSourceView(viewModel: viewModel, sourceUUID: sourceUUID)
            } else {
                missingURLState
            }
        }
    }

    @ViewBuilder
    private func webContent(url: URL, readerMode: Bool) -> some View {
        ZStack {
            WebSourceView(
                url: url,
                readerMode: readerMode,
                lastSelectedText: $lastSelectedText,
                selectionAnchor: $selectionAnchor,
                loadState: $loadState
            )
            switch loadState {
            case .loading:
                loadingState
            case .failed(let message):
                failureState(url: url, message: message)
            case .loaded:
                EmptyView()
            }
        }
        .animation(ProMotionSprings.gentle, value: loadState)
    }

    private var loadingState: some View {
        VStack(spacing: DS.space10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading source…")
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.bg)
        .transition(.opacity)
    }

    private func failureState(url: URL, message: String) -> some View {
        VStack(spacing: DS.space10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(CosmoColors.textTertiary)
                .accessibilityHidden(true)
            Text("This page couldn't be loaded here.")
                .font(.system(.body, design: .serif))
                .foregroundStyle(CosmoColors.textSecondary)
            Text(message)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textTertiary)
                .lineLimit(2)
                .frame(maxWidth: 360)
                .multilineTextAlignment(.center)
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Text("Open in Browser")
                    .font(CosmoTypography.label)
                    .padding(.horizontal, DS.space12)
                    .padding(.vertical, 6)
                    .background(DS.accent, in: Capsule())
                    .foregroundStyle(DS.textOnAccent)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open source in browser")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.bg)
        .transition(.opacity)
    }

    private var missingURLState: some View {
        VStack(spacing: DS.space8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(CosmoColors.textTertiary)
                .accessibilityHidden(true)
            Text("This source has no readable address.")
                .font(.system(.body, design: .serif))
                .foregroundStyle(CosmoColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Selection capture pill

/// The reader's answer to the note editor's quill bar: one small glass pill
/// floating next to the highlight, with exactly ONE verb. No kind choices —
/// the capture routes like a typed thought and the classifier does the rest.
/// Positioning follows the quill-bar grammar: clamp horizontally, sit above
/// the selection, flip below when there's no headroom.
struct SelectionCapturePill: View {
    /// Selection rect in the host's coordinate space.
    let anchor: CGRect
    /// Host bounds the pill must stay inside.
    let container: CGSize
    let onCapture: () -> Void

    @State private var pillSize: CGSize = .zero
    @State private var isHovered = false

    /// Estimated size before the first geometry pass lands.
    private var effectivePillSize: CGSize {
        pillSize == .zero ? CGSize(width: 104, height: 36) : pillSize
    }

    private var resolvedPosition: CGPoint {
        let pad: CGFloat = CosmoMenuChrome.shadowClearance
        let gap: CGFloat = 10
        let size = effectivePillSize
        let half = size.width / 2

        let x: CGFloat
        if container.width < size.width + pad * 2 {
            x = container.width / 2
        } else {
            x = min(max(anchor.midX, half + pad), container.width - half - pad)
        }

        let fitsAbove = anchor.minY - size.height - gap >= 0
        let y = fitsAbove
            ? anchor.minY - size.height / 2 - gap
            : min(anchor.maxY + size.height / 2 + gap, container.height - size.height / 2 - pad)
        return CGPoint(x: x, y: y)
    }

    var body: some View {
        Button(action: onCapture) {
            HStack(spacing: DS.space6) {
                Image(systemName: "sparkle")
                    .font(DS.caption2.weight(.semibold))
                    .accessibilityHidden(true)
                Text("Capture")
                    .font(DS.caption.weight(.medium))
            }
            .foregroundStyle(isHovered ? DS.accent : DS.textSecondary)
            .padding(.horizontal, DS.space12)
            .frame(height: 36)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .cosmoMenuChrome(cornerRadius: 18)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newValue in
            pillSize = newValue
        }
        .position(resolvedPosition)
        .animation(ProMotionSprings.snappy, value: anchor)
        .help("Capture selection")
        .accessibilityLabel("Capture selection")
    }
}

// MARK: - Selection anchor space

/// Bridges AppKit selection rects into SwiftUI's `.global` space (the window
/// content view, top-left origin) so a SwiftUI overlay hosted elsewhere in
/// the hierarchy can anchor to a highlight made inside an NSView.
enum SelectionAnchorSpace {
    /// Rect already in `view`'s local coordinate space (e.g. a web page's
    /// viewport rect at default zoom).
    static func globalRect(fromLocal local: CGRect, in view: NSView) -> CGRect? {
        guard let content = view.window?.contentView else { return nil }
        return normalize(view.convert(local, to: content), in: content)
    }

    /// Rect in screen coordinates (e.g. `NSTextView.firstRect(forCharacterRange:)`).
    static func globalRect(fromScreen screenRect: CGRect, for view: NSView) -> CGRect? {
        guard let window = view.window, let content = window.contentView else { return nil }
        return normalize(content.convert(window.convertFromScreen(screenRect), from: nil), in: content)
    }

    private static func normalize(_ rect: CGRect, in content: NSView) -> CGRect {
        guard !content.isFlipped else { return rect }
        var flipped = rect
        flipped.origin.y = content.bounds.height - rect.maxY
        return flipped
    }
}
