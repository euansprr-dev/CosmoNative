// CosmoOS/UI/InlineAssistant/CosmoInlineRiffDirectionsCard.swift
// The /riff deliverable as an interactive pane card: every direction is its own
// block. Hovering a block (or moving with ↑/↓ once a peek is open) previews the
// variation woven into the live draft through the same in-place diff review the
// reviewed-edit pipeline owns; "Use" applies that one direction immediately
// (the preview WAS the review), and "Reject all" passes on the whole set.
// July 2026

import SwiftUI

struct CosmoInlineRiffDirectionsCardView: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    let card: CosmoAssistantRiffDirectionsCard

    /// Debounces hover intent: entering the first block waits a beat before
    /// swapping the editor for the woven diff; leaving waits slightly longer so
    /// moving between blocks never flickers the swap.
    @State private var hoverIntentTask: Task<Void, Never>?
    @State private var keyMonitor: Any?

    private var isPreviewingThisCard: Bool {
        store.riffPreview?.cardID == card.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if card.status != .dismissed {
                Divider().overlay(DS.borderSubtle)
                currentBeatLine
                directionBlocks
                Divider().overlay(DS.borderSubtle)
                footer
            }
        }
        .background(DS.surfaceCard, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(DS.borderSubtle, lineWidth: 1)
        }
        .animation(ProMotionSprings.focusTransition, value: card.status)
        .animation(ProMotionSprings.hover, value: store.riffPreview)
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: teardown)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: DS.space12) {
            Image(systemName: "arrow.triangle.branch")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(surfaceTint)
                .frame(width: 32, height: 32)
                .background(surfaceTint.opacity(0.12), in: .rect(cornerRadius: 9))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(card.riff.beatLabel)
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                Text(headerSubline)
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(DS.textMuted)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            Spacer()

            if card.status == .applied {
                CosmoPanePillButton(label: "Undo", icon: "arrow.uturn.backward", help: "Revert this variation and pick again") {
                    Task { await store.undoRiffVariation(cardID: card.id) }
                }
            }
        }
        .padding(DS.space12)
    }

    private var headerSubline: String {
        switch card.status {
        case .pending:
            let count = card.riff.variations.count
            return "\(count) \(count == 1 ? "direction" : "directions") — hover to preview in the draft"
        case .applied:
            let index = card.appliedVariationIndex ?? 0
            return "Variation \(index) applied"
        case .dismissed:
            return "Passed on \(card.riff.variations.count) directions"
        }
    }

    // MARK: - Current beat

    @ViewBuilder
    private var currentBeatLine: some View {
        if card.replacesExistingText {
            Text("Current: \u{201C}\(card.riff.targetOriginalText)\u{201D}")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .lineLimit(2)
                .padding(.horizontal, DS.space12)
                .padding(.top, DS.space8)
        } else {
            Text("New beat — applying inserts it into the draft")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .padding(.horizontal, DS.space12)
                .padding(.top, DS.space8)
        }
    }

    // MARK: - Blocks

    private var directionBlocks: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            ForEach(Array(card.riff.variations.enumerated()), id: \.offset) { pair in
                CosmoInlineRiffDirectionBlock(
                    index: pair.offset + 1,
                    variation: pair.element,
                    state: blockState(index: pair.offset + 1),
                    isInteractive: card.status == .pending,
                    onHoverChanged: { hovering in
                        blockHoverChanged(hovering, index: pair.offset + 1)
                    },
                    onSelect: { store.previewRiffVariation(cardID: card.id, index: pair.offset + 1) },
                    onUse: { apply(index: pair.offset + 1) }
                )
            }
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
    }

    private func blockState(index: Int) -> CosmoInlineRiffDirectionBlock.BlockState {
        if card.status == .applied {
            return card.appliedVariationIndex == index ? .applied : .dimmed
        }
        if isPreviewingThisCard, store.riffPreview?.variationIndex == index {
            return .previewing
        }
        return .resting
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: DS.space8) {
            footerHint
            Spacer(minLength: DS.space8)
            Text(card.receiptLine)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)
            if card.status == .pending {
                CosmoPanePillButton(label: "Reject all", icon: nil, help: "Pass on every direction — the draft stays untouched") {
                    store.dismissRiffDirections(cardID: card.id)
                }
            }
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
    }

    @ViewBuilder
    private var footerHint: some View {
        let bet = card.riff.bet.trimmingCharacters(in: .whitespacesAndNewlines)
        if card.status == .pending, !bet.isEmpty, bet.lowercased() != "x" {
            Text("Bet: \(bet)")
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(2)
        } else if card.status == .pending {
            Text("↑↓ to browse · Return applies · Esc closes the preview")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
    }

    // MARK: - Interactions

    private func apply(index: Int) {
        hoverIntentTask?.cancel()
        Task { await store.applyRiffVariation(cardID: card.id, index: index) }
    }

    private func blockHoverChanged(_ hovering: Bool, index: Int) {
        guard card.status == .pending else { return }
        hoverIntentTask?.cancel()
        if hovering {
            let alreadyOpen = isPreviewingThisCard
            hoverIntentTask = Task {
                if !alreadyOpen {
                    try? await Task.sleep(nanoseconds: 140_000_000)
                }
                guard !Task.isCancelled else { return }
                store.previewRiffVariation(cardID: card.id, index: index)
            }
        } else {
            hoverIntentTask = Task {
                try? await Task.sleep(nanoseconds: 260_000_000)
                guard !Task.isCancelled else { return }
                if store.riffPreview?.cardID == card.id, store.riffPreview?.variationIndex == index {
                    store.endRiffPreview()
                }
            }
        }
    }

    // MARK: - Keyboard (active only while this card's peek is open)

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKey(event)
        }
    }

    private func teardown() {
        hoverIntentTask?.cancel()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if isPreviewingThisCard {
            store.endRiffPreview()
        }
    }

    /// ↑/↓ browse directions, Return applies the previewed one, Esc closes the
    /// peek. Inert unless THIS card's preview is open, so the composer and
    /// every other shortcut keep their keys. The monitor closure outlives this
    /// view value, so the card's status is read live from the store — never
    /// from the captured snapshot.
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard let preview = store.riffPreview, preview.cardID == card.id,
              store.riffDirectionsCard(id: card.id)?.status == .pending else { return event }
        switch event.keyCode {
        case 125: // down
            movePreview(from: preview.variationIndex, delta: 1)
            return nil
        case 126: // up
            movePreview(from: preview.variationIndex, delta: -1)
            return nil
        case 36: // return
            apply(index: preview.variationIndex)
            return nil
        case 53: // esc
            hoverIntentTask?.cancel()
            store.endRiffPreview()
            return nil
        default:
            return event
        }
    }

    private func movePreview(from index: Int, delta: Int) {
        hoverIntentTask?.cancel()
        let count = card.riff.variations.count
        guard count > 0 else { return }
        let next = ((index - 1 + delta) % count + count) % count + 1
        store.previewRiffVariation(cardID: card.id, index: next)
    }

    private var surfaceTint: Color {
        CosmoInlineAssistantSurfaceTint.color(forSurfaceID: card.surfaceID)
    }
}

// MARK: - Direction block

/// One direction as a selectable block. Resting blocks are monochrome; hover
/// swaps the fill and reveals "Use" (opacity swap, never layout); the
/// previewing block wears the selection grammar (accentSoft wash + accent
/// hairline) while its variation shows live in the draft.
struct CosmoInlineRiffDirectionBlock: View {
    enum BlockState: Equatable {
        case resting
        case previewing
        case applied
        case dimmed
    }

    let index: Int
    let variation: CraftRiffVariation
    let state: BlockState
    let isInteractive: Bool
    let onHoverChanged: (Bool) -> Void
    let onSelect: () -> Void
    let onUse: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.space10) {
            indexBadge
            content
            Spacer(minLength: DS.space6)
            trailing
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 44)
        .background(fill, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor, lineWidth: 1)
        }
        .contentShape(.rect(cornerRadius: 10))
        .opacity(state == .dimmed ? 0.45 : 1)
        .onHover { hovering in
            guard isInteractive else { return }
            withCosmoHoverAnimation { isHovered = hovering }
            // Stays outside the animation transaction — it drives the parent's
            // dimming, which was never animated from here.
            onHoverChanged(hovering)
        }
        .onTapGesture {
            guard isInteractive else { return }
            onSelect()
        }
        .animation(ProMotionSprings.hover, value: state)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Direction \(index): \(variation.mechanism). \(variation.text)")
        .accessibilityAddTraits(state == .previewing ? [.isSelected] : [])
    }

    private var indexBadge: some View {
        Text("\(index)")
            .font(DS.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(state == .previewing || state == .applied ? DS.accent : DS.textMuted)
            .frame(width: 22, height: 22)
            .background(
                state == .previewing || state == .applied ? DS.accentSoft : DS.surfaceElevated,
                in: Circle()
            )
            .accessibilityHidden(true)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(variation.mechanism)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
            Text(variation.text)
                .font(DS.body)
                .foregroundStyle(DS.text)
                .fixedSize(horizontal: false, vertical: true)
            if let source = sourceLine {
                Text(source)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if state == .applied {
            Image(systemName: "checkmark.circle.fill")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(DS.accent)
                .accessibilityLabel("Applied")
        } else if isInteractive {
            CosmoPanePillButton(label: "Use", icon: "checkmark", help: "Apply this direction to the draft", isProminent: true) {
                onUse()
            }
            .opacity(isHovered || state == .previewing ? 1 : 0)
            .accessibilityHidden(!(isHovered || state == .previewing))
        }
    }

    private var sourceLine: String? {
        let from = variation.borrowedFrom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, from.lowercased() != "none" else { return nil }
        let numbers = variation.numbers.trimmingCharacters(in: .whitespacesAndNewlines)
        return numbers.isEmpty ? "from \(from)" : "from \(from) · \(numbers)"
    }

    private var fill: Color {
        switch state {
        case .previewing: return DS.accentSoft.opacity(0.6)
        case .applied: return DS.accentSoft.opacity(0.4)
        case .resting, .dimmed: return isHovered ? DS.surfaceElevated : DS.surfaceElevated.opacity(0.55)
        }
    }

    private var borderColor: Color {
        switch state {
        case .previewing, .applied: return DS.accent.opacity(0.35)
        case .resting, .dimmed: return DS.borderSubtle
        }
    }
}

#Preview("Riff directions card") {
    let store = CosmoInlineAssistantStore(agentBridge: .mock, sessionPersistence: .inMemory())
    let riff = CraftRiffResult(
        beatLabel: "Slide 7 — sober-living income beat",
        targetOriginalText: "",
        variations: [
            CraftRiffVariation(text: "Each bed brings in $600-$1,000/mo. Six beds is $3,600-$6,000 before the mortgage even notices.", mechanism: "number-first math", borrowedFrom: "Government pays reel", numbers: "480K views"),
            CraftRiffVariation(text: "You don't rent the house. You rent the beds.", mechanism: "reframe via unit shift", borrowedFrom: "none", numbers: ""),
            CraftRiffVariation(text: "One house. Six residents. Each one covered by the state.", mechanism: "stacked-specifics build", borrowedFrom: "150 people reel", numbers: "1.2M views")
        ],
        bet: "Variation 1 — the per-bed math is the scroll-stopper."
    )
    store.receiveRiffDirections(
        riff: riff,
        snapshot: CosmoEditableSourceSnapshot(
            surfaceID: "content:preview",
            targetID: "content:preview:body",
            kind: .text,
            title: "DSCR carousel",
            text: "SLIDE 7",
            sourceHash: "preview",
            anchors: []
        ),
        receiptLine: "≈$0.31 · 24.8K in (72% cached) · 6.9K out",
        fallbackMarkdown: "fallback"
    )
    return CosmoInlineRiffDirectionsCardView(store: store, card: store.riffDirectionCards.last!)
        .padding(24)
        .frame(width: 460)
        .background(DS.bg)
}
