import SwiftUI

// MARK: - Cursor

extension View {
    /// Shows the pointing-hand cursor on hover. SwiftUI buttons layered over an
    /// `NSTextView` otherwise inherit the editor's I-beam; `pointerStyle` installs a
    /// real cursor rect that wins over the text surface underneath.
    func cosmoClickCursor() -> some View {
        pointerStyle(.link)
    }
}

// MARK: - Inline document diff review

/// Renders a surface's text *in place* with the proposed changes woven inline:
/// untouched prose reads normally (dimmed), each change shows the removed lines in red
/// and the added lines in green with its own accept / reject controls. This replaces a
/// surface's editor while a proposal is being reviewed, so the user scrolls the real
/// document and reads every change in context — no floating menu.
struct CosmoInlineDiffReviewView: View {
    // Plain reference, not observed: the host surface re-feeds `proposal` and
    // `sourceText` whenever the store changes, so observing here would only add
    // redundant re-renders on every composer keystroke.
    let store: CosmoInlineAssistantStore
    let proposal: CosmoAssistantProposal
    let sourceText: String
    var bodyFont: Font = .system(size: 17)
    var textColor: Color = DS.text
    var unchangedOpacity: Double = 0.5
    var onAcceptOperation: ((UUID) -> Void)?
    var onRejectOperation: ((UUID) -> Void)?

    /// Drives the swap-in centering scroll. Owned per mounted review, so a
    /// fresh proposal re-centers while accept/reject churn on the open one
    /// does not.
    @State private var centeringDriver = CosmoInlineReviewCenteringDriver()

    private var segments: [CosmoInlineDiffSegment] {
        CosmoInlineDiffReviewBuilder.segments(
            sourceText: sourceText,
            operations: proposal.operations
        )
    }

    var body: some View {
        let segments = self.segments
        let firstChangeID = segments.first {
            if case .change = $0 { return true } else { return false }
        }?.id

        VStack(alignment: .leading, spacing: 14) {
            ForEach(segments) { segment in
                segmentView(segment, isFirstChange: segment.id == firstChangeID)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(ProMotionSprings.gentle, value: sourceText)
        .onAppear { centeringDriver.centerOnAnchor() }
        .onChange(of: proposal.id) { centeringDriver.centerOnAnchor() }
    }

    @ViewBuilder
    private func segmentView(_ segment: CosmoInlineDiffSegment, isFirstChange: Bool) -> some View {
        switch segment {
        case let .unchanged(_, text):
            Text(text)
                .font(bodyFont)
                .foregroundStyle(textColor.opacity(unchangedOpacity))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        case let .change(change):
            CosmoInlineDiffChangeRow(
                change: change,
                onAccept: { accept(change.id) },
                onReject: { reject(change.id) }
            )
            .background {
                if isFirstChange {
                    CosmoInlineReviewCenterAnchor(driver: centeringDriver)
                }
            }
            .transition(.asymmetric(
                insertion: .opacity,
                removal: .opacity.combined(with: .scale(scale: 0.97))
            ))
        }
    }

    private func accept(_ operationID: UUID) {
        if let onAcceptOperation {
            onAcceptOperation(operationID)
        } else {
            Task { await store.accept(operationID: operationID) }
        }
    }

    private func reject(_ operationID: UUID) {
        if let onRejectOperation {
            onRejectOperation(operationID)
        } else {
            Task { await store.reject(operationID: operationID) }
        }
    }
}

private struct CosmoInlineDiffChangeRow: View {
    let change: CosmoInlineDiffChange
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill((change.isConflicted ? DS.orange : DS.green).opacity(0.45))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 5) {
                if change.isConflicted {
                    Label("Nothing to apply on this document — dismiss to clear", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.orange)
                } else if !change.rationale.isEmpty {
                    Text(change.rationale)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(1)
                }

                ForEach(Array(change.removedLines.enumerated()), id: \.offset) { _, line in
                    CosmoInlineDiffLineView(text: line, kind: .removed)
                }
                ForEach(Array(change.addedLines.enumerated()), id: \.offset) { _, line in
                    CosmoInlineDiffLineView(text: line, kind: .added, formatMark: change.formatMark)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            controls
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(DS.surface.opacity(0.45), in: .rect(cornerRadius: 12))
    }

    private var controls: some View {
        HStack(spacing: 6) {
            if !change.isConflicted {
                Button(action: onAccept) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.textOnAccent)
                        .frame(width: 30, height: 30)
                        .background(DS.green, in: Circle())
                }
                .buttonStyle(.plain)
                .cosmoClickCursor()
                .help("Accept change")
                .accessibilityLabel("Accept change")
            }

            Button(action: onReject) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(DS.surface, in: Circle())
                    .overlay { Circle().stroke(DS.borderSubtle, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .cosmoClickCursor()
            .help(change.isConflicted ? "Dismiss" : "Reject change")
            .accessibilityLabel(change.isConflicted ? "Dismiss change" : "Reject change")
        }
    }
}

// MARK: - Review swap scroll preservation

/// Preserves a focus mode's scroll position across the review ⇄ editor swap.
///
/// While a proposal is under review the editor is replaced by
/// `CosmoInlineDiffReviewView`; resolving the last operation swaps the editor
/// back in. The fresh editor reports its height asynchronously, so for a few
/// frames the scroll content collapses and AppKit clamps the offset to the
/// top — the user lands at the start of the document instead of the edit they
/// just accepted. The host captures the offset *before* flipping the branch,
/// then this keeper re-asserts it while layout settles (the target may exceed
/// the document height until hydration finishes). A user scroll during that
/// window wins immediately.
///
/// Main-thread only, like the scroll views it drives.
final class CosmoInlineReviewScrollPositionKeeper {
    private weak var scrollView: NSScrollView?
    private var targetOffsetY: CGFloat?
    private var lastAppliedOffsetY: CGFloat?
    private var restoreGeneration = 0

    /// Delays (from the swap) at which the offset is re-asserted. Early
    /// attempts catch the common single-frame relayout; later ones cover
    /// progressive block hydration on long notes.
    private static let attemptDelays: [TimeInterval] = [0, 0.03, 0.08, 0.16, 0.3, 0.6, 1.0]

    func attach(to scrollView: NSScrollView) {
        self.scrollView = scrollView
    }

    /// Call BEFORE the state change that swaps the review/editor branch, while
    /// the outgoing branch still owns the scroll geometry.
    func captureBeforeSwap() {
        guard let scrollView else { return }
        targetOffsetY = scrollView.documentVisibleRect.origin.y
        lastAppliedOffsetY = nil
    }

    /// Call right after the state change; replays the captured offset until it
    /// sticks or the user takes over.
    func restoreAfterSwap() {
        guard targetOffsetY != nil else { return }
        restoreGeneration += 1
        let generation = restoreGeneration
        for delay in Self.attemptDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.performRestoreAttempt(generation: generation)
            }
        }
    }

    private func performRestoreAttempt(generation: Int) {
        guard generation == restoreGeneration,
              let scrollView,
              let target = targetOffsetY else { return }

        let current = scrollView.documentVisibleRect.origin.y
        let documentHeight = scrollView.documentView?.frame.height ?? 0
        let maxOffsetY = max(0, documentHeight - scrollView.contentView.bounds.height)
        let desired = min(target, maxOffsetY)

        // The user scrolled between attempts — their position wins, stop.
        // A drift that sits exactly at the clamp limit is layout (the document
        // momentarily shrank and AppKit clamped), not the user; keep going.
        if let lastApplied = lastAppliedOffsetY,
           abs(current - lastApplied) > 1,
           abs(current - maxOffsetY) > 1 {
            targetOffsetY = nil
            return
        }

        if abs(current - desired) > 0.5 {
            scrollView.contentView.setBoundsOrigin(
                NSPoint(x: scrollView.contentView.bounds.origin.x, y: desired)
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        // Attempts past this point are no-ops while the offset holds — the
        // window stays open (never ends early) because the first attempt can
        // land BEFORE the swap renders, when everything still looks settled.
        lastAppliedOffsetY = desired
    }
}

// MARK: - Review swap-in centering

/// Centers the first staged change when a review swaps IN.
///
/// Opening a review replaces the editor with `CosmoInlineDiffReviewView`, whose
/// layout shares nothing with the editor it displaced — the scroll view keeps
/// its old pixel offset, which now lands on arbitrary prose, often a long way
/// from the change the user is being asked to judge. This driver scrolls the
/// first change row to the vertical center of the viewport once the swapped-in
/// layout settles, replaying over the same delay ladder as
/// `CosmoInlineReviewScrollPositionKeeper` because the diff rows report their
/// heights asynchronously. A user scroll during the window wins immediately.
///
/// Main-thread only, like the scroll views it drives.
final class CosmoInlineReviewCenteringDriver {
    fileprivate weak var anchorView: NSView?
    private var lastAppliedOffsetY: CGFloat?
    private var generation = 0

    /// Same ladder as the position keeper: early attempts catch the common
    /// single-frame relayout, later ones cover slow settles on long documents.
    private static let attemptDelays: [TimeInterval] = [0, 0.03, 0.08, 0.16, 0.3, 0.6, 1.0]

    /// Where the viewport should land so the anchor sits mid-viewport, clamped
    /// to the scrollable range. Pure math, split out for tests.
    static func desiredOffsetY(
        anchorMidY: CGFloat,
        viewportHeight: CGFloat,
        documentHeight: CGFloat
    ) -> CGFloat {
        let maxOffsetY = max(0, documentHeight - viewportHeight)
        return min(max(0, anchorMidY - viewportHeight / 2), maxOffsetY)
    }

    /// Call when the review swaps in, or a new proposal replaces the open one.
    func centerOnAnchor() {
        generation += 1
        lastAppliedOffsetY = nil
        let generation = self.generation
        for delay in Self.attemptDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.performCenterAttempt(generation: generation)
            }
        }
    }

    private func performCenterAttempt(generation: Int) {
        guard generation == self.generation,
              let anchorView,
              anchorView.window != nil,
              let scrollView = anchorView.enclosingScrollView,
              let documentView = scrollView.documentView else { return }

        let clipView = scrollView.contentView
        let current = scrollView.documentVisibleRect.origin.y
        let maxOffsetY = max(0, documentView.frame.height - clipView.bounds.height)

        // The user scrolled between attempts — their position wins, stop for
        // good. A drift pinned at the clamp limit is layout (the document
        // momentarily shrank and AppKit clamped), not the user; keep going.
        if let lastApplied = lastAppliedOffsetY,
           abs(current - lastApplied) > 1,
           abs(current - maxOffsetY) > 1 {
            self.generation += 1
            return
        }

        // Recomputed per attempt: the anchor row migrates as segments above it
        // finish laying out, so a stale rect would center the wrong spot.
        let anchorRect = documentView.convert(anchorView.bounds, from: anchorView)
        let desired = Self.desiredOffsetY(
            anchorMidY: anchorRect.midY,
            viewportHeight: clipView.bounds.height,
            documentHeight: documentView.frame.height
        )

        if abs(current - desired) > 0.5 {
            clipView.setBoundsOrigin(NSPoint(x: clipView.bounds.origin.x, y: desired))
            scrollView.reflectScrolledClipView(clipView)
        }
        lastAppliedOffsetY = desired
    }
}

/// Marks the first change row so the centering driver can locate it inside the
/// host's scroll view. Place as the row's background.
private struct CosmoInlineReviewCenterAnchor: NSViewRepresentable {
    let driver: CosmoInlineReviewCenteringDriver

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        driver.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        driver.anchorView = nsView
    }
}

/// Minimal enclosing-`NSScrollView` resolver for hosts that don't already
/// introspect their scroll view. Place anywhere INSIDE the ScrollView content.
struct CosmoInlineReviewScrollResolver: NSViewRepresentable {
    var onResolve: (NSScrollView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let scrollView = view.enclosingScrollView {
                onResolve(scrollView)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let scrollView = nsView.enclosingScrollView {
                onResolve(scrollView)
            }
        }
    }
}

private struct CosmoInlineDiffLineView: View {
    enum Kind { case removed, added }

    let text: String
    let kind: Kind
    /// For formatting changes: render the line with the mark ACTUALLY applied —
    /// a real bold line reads as the result, not a description of it.
    var formatMark: CosmoAssistantFormatMark? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(kind == .removed ? "−" : (formatMark == nil ? "+" : "Aa"))
                .font(.system(size: formatMark == nil ? 14 : 11, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .frame(width: formatMark == nil ? 12 : 18, alignment: .center)

            Text(text)
                .font(styledFont)
                .italic(formatMark == .italic)
                .underline(formatMark == .underline, color: accent.opacity(0.8))
                .foregroundStyle(accent)
                .strikethrough(kind == .removed || formatMark == .strikethrough, color: accent.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(fill, in: .rect(cornerRadius: 8))
    }

    private var styledFont: Font {
        switch formatMark {
        case .bold: return .system(size: 15, weight: .bold)
        case .heading1: return .system(size: 22, weight: .bold)
        case .heading2: return .system(size: 18, weight: .semibold)
        case .heading3: return .system(size: 16, weight: .medium)
        default: return .system(size: 15)
        }
    }

    private var accent: Color {
        kind == .removed ? DS.red : DS.green
    }

    private var fill: Color {
        kind == .removed ? DS.redSoft : DS.greenSoft
    }
}

// MARK: - Global review bar

/// Slim accept-all / reject-all bar that floats just above the composer when a proposal
/// has more than one change. Single-change proposals are handled entirely by the inline
/// controls, so this only appears when a batch decision is useful.
struct CosmoInlineAssistantReviewOverlay: View {
    @ObservedObject var store: CosmoInlineAssistantStore

    var body: some View {
        Group {
            if let proposal = store.activePendingProposal,
               proposal.reviewableOperationCount > 1 {
                globalBar(proposal)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(ProMotionSprings.gentle, value: store.activePendingProposal?.id)
    }

    private func globalBar(_ proposal: CosmoAssistantProposal) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(proposal.reviewableOperationCount) changes to review")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.text)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(ProMotionSprings.gentle, value: proposal.reviewableOperationCount)
                if !proposal.title.isEmpty {
                    Text(proposal.title)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            Button {
                Task { await store.rejectAll(proposalID: proposal.id) }
            } label: {
                pillLabel("Reject all", systemImage: "xmark")
                    .foregroundStyle(DS.textSecondary)
                    .background(DS.surface, in: Capsule())
                    .overlay { Capsule().stroke(DS.borderSubtle, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .cosmoClickCursor()
            .accessibilityLabel("Reject all changes")

            Button {
                Task { await store.acceptAll(proposalID: proposal.id) }
            } label: {
                pillLabel("Accept all", systemImage: "checkmark")
                    .foregroundStyle(DS.textOnAccent)
                    .background(DS.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .cosmoClickCursor()
            .accessibilityLabel("Accept all changes")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: 640)
        // Same instrument family as the quill bar and slash menu — one glass
        // chrome for every floating editor instrument.
        .cosmoMenuChrome(cornerRadius: 22)
        .padding(.horizontal, max(28, CosmoMenuChrome.shadowClearance))
    }

    private func pillLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
    }
}
