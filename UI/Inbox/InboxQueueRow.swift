// CosmoOS/UI/Inbox/InboxQueueRow.swift
// One capture, one calm row. The capture text is the hero; the AI's entire
// presence is a single trailing suggestion pill. Everything else — rationale,
// alternates, minimap — lives in the inspector.
// June 2026 — Inbox Revamp (INBOX_REVAMP_PLAN.md §3)

import SwiftUI

struct InboxQueueRow: View {
    let item: InboxItem
    let isFocused: Bool
    let isSelected: Bool
    let isProcessing: Bool
    let onOpen: () -> Void
    let onAccept: () -> Void
    let onDismiss: () -> Void
    let onToggleSelect: () -> Void
    /// Right-click routing — the row offers the same direct moves the
    /// inspector does (lanes, inquiry Spaces) without opening it. Empty
    /// lists hide their submenus; nil handlers hide their items.
    var lanes: [CaptureDestination] = []
    var inquirySpaces: [InquirySpaceOption] = []
    var seedlings: [Seedling] = []
    var onMoveToLane: ((CaptureDestination) -> Void)? = nil
    var onStartInquiry: ((InquirySpaceOption?) -> Void)? = nil
    /// nil seedling = "New concept…" (names it in the destination sheet).
    var onGrowSeedling: ((Seedling?) -> Void)? = nil
    var onSaveAsResearch: (() -> Void)? = nil
    var onChooseDestination: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        Button(action: handleTap) {
            rowContent
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .contextMenu { contextMenuItems }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isFocused ? [.isSelected] : [])
        .help(item.hasActionableSuggestion ? "Open inspector — ⏎ accepts the suggestion" : "Open inspector")
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        if item.hasActionableSuggestion {
            Button("Accept suggestion", systemImage: "checkmark", action: onAccept)
        }
        if let onMoveToLane, !lanes.isEmpty {
            Menu {
                ForEach(lanes, id: \.uuid) { lane in
                    Button(lane.name, systemImage: lane.icon) { onMoveToLane(lane) }
                }
            } label: {
                Label("Move to lane", systemImage: "tray.2")
            }
        }
        if let onStartInquiry {
            Menu {
                ForEach(inquirySpaces) { space in
                    Button(space.name) { onStartInquiry(space) }
                }
                if !inquirySpaces.isEmpty { Divider() }
                Button("New Space…", systemImage: "plus") { onStartInquiry(nil) }
            } label: {
                Label("Start inquiry in", systemImage: "text.magnifyingglass")
            }
        }
        if let onGrowSeedling {
            Menu {
                ForEach(seedlings, id: \.uuid) { seedling in
                    Button("\(seedling.name) · \(seedling.massSummary)", systemImage: "leaf") { onGrowSeedling(seedling) }
                }
                if !seedlings.isEmpty { Divider() }
                Button("New concept…", systemImage: "plus") { onGrowSeedling(nil) }
            } label: {
                Label("Grow a concept", systemImage: "leaf")
            }
        }
        if let onSaveAsResearch, item.canBecomeResearch {
            Button("Save as Research…", systemImage: "books.vertical", action: onSaveAsResearch)
        }
        if let onChooseDestination {
            Button("Choose destination…", systemImage: "tray.and.arrow.down", action: onChooseDestination)
        }
        Divider()
        Button("Dismiss", systemImage: "xmark", action: onDismiss)
    }

    private var rowContent: some View {
        HStack(spacing: DS.space12) {
            statusDot
            titleColumn
            Spacer(minLength: DS.space12)
            pageThumb
            trailingArea
        }
        .padding(.horizontal, DS.space16)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .background(rowBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.borderSubtle)
                .frame(height: 0.5)
                .padding(.leading, DS.space16 + 6 + DS.space12)
        }
        .opacity(isProcessing ? 0.55 : 1)
    }

    // MARK: - Pieces

    /// A captured page announces itself as an object: one mini original,
    /// extra pages whispered as a count in the corner.
    @ViewBuilder
    private var pageThumb: some View {
        if let firstAttachment = item.attachmentUUIDs.first {
            InboxRowPageThumb(
                firstAttachmentUUID: firstAttachment,
                pageCount: item.attachmentUUIDs.count
            )
        }
    }

    private var statusDot: some View {
        Circle()
            .strokeBorder(dotColor, lineWidth: item.hasActionableSuggestion ? 0 : 1.2)
            .background(Circle().fill(item.hasActionableSuggestion ? dotColor : .clear))
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }

    private var dotColor: Color {
        if item.classification == .merge { return DS.orange }
        if item.hasActionableSuggestion { return DS.accent }
        return DS.textMuted.opacity(0.6)
    }

    private var titleColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title ?? String(item.rawText.prefix(120)))
                .font(DS.body)
                .foregroundStyle(DS.text)
                .lineLimit(1)

            Text("\(sourceLabel) · \(relativeTime)")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
    }

    @ViewBuilder
    private var trailingArea: some View {
        if isHovered || isSelected {
            hoverVerbs
        } else {
            suggestionPill
        }
    }

    // The single AI presence in the row.
    @ViewBuilder
    private var suggestionPill: some View {
        if item.status == .pending {
            Text("Reading…")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        } else if item.routesToTask {
            pill(icon: "checkmark.circle", text: "Task", tint: DS.entityTask, prominent: true)
        } else if item.classification == .merge, let target = item.mergeTargetTitle {
            pill(icon: "arrow.triangle.merge", text: target, tint: DS.orange, prominent: true)
        } else if item.classification == .place {
            // The icon says what the capture BECOMES (leaf = grows a concept,
            // bubble = new question…) — the destination path says where.
            let kind = item.primaryRouteKindValue
            pill(
                icon: kind?.outcomeIcon ?? "arrow.turn.down.right",
                text: item.spatialDestinationTitle,
                tint: kind?.outcomeTint ?? DS.accent,
                prominent: item.confidence >= InboxRoutingConfig.shared.confidentTier
            )
        } else {
            Text("Unsorted")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
    }

    private func pill(icon: String, text: String, tint: Color, prominent: Bool) -> some View {
        HStack(spacing: DS.space4) {
            Image(systemName: icon)
                .font(DS.caption2.weight(.semibold))
            Text(text)
                .font(DS.caption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(prominent ? tint : DS.textSecondary)
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space4 + 1)
        .background(
            prominent ? tint.opacity(0.10) : DS.glassSectionFill,
            in: .capsule
        )
        .overlay(
            Capsule().strokeBorder(prominent ? tint.opacity(0.25) : DS.borderSubtle, lineWidth: 0.5)
        )
        .frame(maxWidth: 260, alignment: .trailing)
        .accessibilityLabel("Suggested: \(text)")
    }

    private var hoverVerbs: some View {
        HStack(spacing: DS.space6) {
            if item.hasActionableSuggestion {
                verbButton(icon: "checkmark", tint: DS.accent, label: "Accept suggestion (⏎)", action: onAccept)
            }
            verbButton(icon: "xmark", tint: DS.textMuted, label: "Dismiss (⌫)", action: onDismiss)
        }
        .transition(.opacity)
    }

    private func verbButton(icon: String, tint: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(DS.glassSectionFill, in: .circle)
                .overlay(Circle().strokeBorder(DS.borderSubtle, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isFocused {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.accentSoft.opacity(0.45))
                .padding(.horizontal, DS.space6)
        } else if isSelected {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.accentSoft.opacity(0.25))
                .padding(.horizontal, DS.space6)
        } else if isHovered {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.glassSectionFill)
                .padding(.horizontal, DS.space6)
        }
    }

    // MARK: - Interaction

    private func handleTap() {
        if NSEvent.modifierFlags.contains(.command) {
            onToggleSelect()
        } else {
            onOpen()
        }
    }

    // MARK: - Metadata

    private var sourceLabel: String {
        switch item.source {
        case .telegramVoice: return "Telegram voice"
        case .telegramText: return "Telegram"
        case .quickCapture: return "Capture"
        }
    }

    private var relativeTime: String {
        // The one age voice — "5m" / "2d", never "ago" (a ledger column
        // repeating "ago" down every row is noise).
        guard let date = ISO8601.date(from: item.createdAt) else { return "" }
        if Date().timeIntervalSince(date) < 60 { return "now" }
        return date.cosmoCompactAge
    }
}
