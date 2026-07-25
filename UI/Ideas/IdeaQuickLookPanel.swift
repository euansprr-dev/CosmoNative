// CosmoOS/UI/Ideas/IdeaQuickLookPanel.swift
// Space bar Quick Look for ideas (Phase 2 of the Desk reinvention): judge an
// idea in two seconds without opening its bench. One paper panel — the hook
// at hero scale, the source still, then the idea's actual substance (hooks,
// context, outline beats) as a flat ledger. Arrows retarget it while open
// (the shell moves the cursor; the panel follows), ⏎ opens the bench, and
// "Study source" walks into the Swipe Studio with a live session. Depth
// lives in the study room — the panel answers, it doesn't play reels.

import SwiftUI

struct IdeaQuickLookPanel: View {
    let idea: IdeaGalleryItem
    let model: IdeasPageModel
    let onOpen: () -> Void
    let onOpenAsPane: () -> Void
    let onClose: () -> Void

    /// The linked swipe, fetched on arrival — powers attribution + the door.
    @State private var sourceSwipe: SwipeGalleryItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var thumbs: [String] { model.inspirationThumbs[idea.atomUUID] ?? [] }

    private var headline: String {
        if let hook = idea.hooks.first, !hook.isEmpty { return hook }
        return idea.title
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)
            panel
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, DS.space20)
                .padding(.top, DS.space16)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space16) {
                    heroRow
                    substance
                }
                .padding(.horizontal, DS.space20)
                .padding(.vertical, DS.space16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Hug short sparks instead of stretching to the cap — the outer
            // maxHeight clamps tall ideas and scrolling takes over.
            .fixedSize(horizontal: false, vertical: true)
            .scrollBounceBehavior(.basedOnSize)
            Divider().overlay(DS.palette.sepiaBorder)
            footer
                .padding(.horizontal, DS.space20)
                .padding(.vertical, DS.space12)
        }
        .frame(width: 560)
        .frame(maxHeight: 660)
        .background(DS.surfaceElevated)
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(DS.palette.sepiaBorder, lineWidth: 0.5)
        )
        .dsFloatingShadow()
        .task(id: idea.atomUUID) { await loadSource() }
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("Quick look: \(headline)")
    }

    // MARK: Header (identity + the one ✕)

    private var header: some View {
        HStack(spacing: DS.space6) {
            if let clientName = idea.clientName {
                Circle()
                    .fill(idea.clientUUID.map { DS.clientColor(for: $0) } ?? DS.textMuted)
                    .frame(width: 6, height: 6)
                Text(clientName)
                Text("·")
            }
            Text(idea.status.displayName)
                .foregroundStyle(idea.status == .ready ? DS.entityIdea : DS.textMuted)
            Text("·")
            Text(ageText)
                .monospacedDigit()
            if let day = model.scheduledDays[idea.atomUUID] {
                Text("·")
                HStack(spacing: 3) {
                    Image(systemName: "calendar")
                        .accessibilityHidden(true)
                    Text(IdeasPageModel.dayLabel(day))
                }
                .foregroundStyle(DS.entityIdea.opacity(0.9))
            }
            Spacer(minLength: DS.space12)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(DS.glassSectionFill, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .help("Close (Esc or Space)")
            .accessibilityLabel("Close quick look")
        }
        .font(DS.caption)
        .foregroundStyle(DS.textMuted)
    }

    // MARK: Hero (the hook + the source still)

    private var heroRow: some View {
        HStack(alignment: .top, spacing: DS.space16) {
            VStack(alignment: .leading, spacing: DS.space8) {
                Text(headline)
                    .font(DS.heroTitleSerif)
                    .foregroundStyle(DS.text)
                    .lineSpacing(3)
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(IdeasDeskEngine.whyLine(for: idea, inspiration: thumbs.isEmpty ? [] : [idea.atomUUID]))
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !thumbs.isEmpty {
                VStack(alignment: .trailing, spacing: DS.space6) {
                    IdeaInspirationThumb(
                        candidates: thumbs,
                        hairline: DS.palette.sepiaBorder,
                        width: 132,
                        height: 168
                    )
                    if let source = sourceSwipe {
                        Text(sourceAttribution(source))
                            .font(DS.caption2)
                            .foregroundStyle(DS.textMuted)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: Substance (hooks · context · outline — flat ledgers)

    @ViewBuilder
    private var substance: some View {
        if idea.hooks.count > 1 {
            substanceSection(label: "Hooks", detail: "\(idea.hooks.count)") {
                ForEach(Array(idea.hooks.dropFirst().prefix(4).enumerated()), id: \.offset) { _, hook in
                    Text(hook)
                        .font(DS.subheadline)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        if let context = idea.context, !context.isEmpty {
            substanceSection(label: "Context", detail: nil) {
                Text(context)
                    .font(DS.subheadline)
                    .foregroundStyle(DS.textSecondary)
                    .lineSpacing(3)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if !idea.outline.isEmpty {
            substanceSection(label: "Outline", detail: "\(idea.outline.count)") {
                ForEach(Array(idea.outline.prefix(5).enumerated()), id: \.offset) { index, beat in
                    HStack(alignment: .firstTextBaseline, spacing: DS.space8) {
                        Text("\(index + 1)")
                            .font(DS.caption2.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(DS.entityIdea.opacity(0.7))
                        Text(beat)
                            .font(DS.subheadline)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if idea.outline.count > 5 {
                    Text("\(idea.outline.count - 5) more beats in the bench")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }
            }
        }
        if idea.hooks.count <= 1, idea.context == nil, idea.outline.isEmpty {
            Text("A raw spark — open it to start shaping.")
                .font(DS.subheadline)
                .foregroundStyle(DS.textMuted)
        }
    }

    private func substanceSection<Content: View>(
        label: String,
        detail: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            CosmoSectionHeader(label: label, detail: detail)
            content()
        }
    }

    // MARK: Footer (the doors)

    private var footer: some View {
        HStack(spacing: DS.space12) {
            if let source = sourceSwipe {
                Button {
                    openSource(source)
                } label: {
                    HStack(spacing: DS.space4) {
                        Image(systemName: "film")
                            .accessibilityHidden(true)
                        Text("Study source")
                    }
                    .font(DS.callout.weight(.medium))
                    .foregroundStyle(DS.textSecondary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Open the saved swipe in the Swipe Studio")
            }
            Spacer(minLength: DS.space12)
            Button("Open in New Pane", action: onOpenAsPane)
                .buttonStyle(.plain)
                .font(DS.callout.weight(.medium))
                .foregroundStyle(DS.textSecondary)
                .help("Work on it beside what's open")
            Button {
                onOpen()
            } label: {
                HStack(spacing: DS.space4) {
                    Text("Open")
                    Text("⏎")
                        .font(DS.caption2)
                        .opacity(0.7)
                }
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, DS.space12)
                .frame(height: 30)
                .background(DS.accent, in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .help("Open the development bench (⏎)")
        }
    }

    // MARK: Source plumbing

    private func loadSource() async {
        sourceSwipe = nil
        guard let atom = try? await AtomRepository.shared.fetch(uuid: idea.atomUUID) else { return }
        let meta = atom.ideaMetadata
        guard let swipeUUID = meta?.linkedSwipeIds?.first
            ?? meta?.originSwipeUUID
            ?? meta?.supportingSwipeUUIDs?.first,
            let swipe = try? await AtomRepository.shared.fetch(uuid: swipeUUID) else { return }
        sourceSwipe = swipe.toSwipeGalleryItem()
    }

    private func sourceAttribution(_ source: SwipeGalleryItem) -> String {
        if let creator = source.creatorName ?? source.author, !creator.isEmpty {
            return "Saved swipe · \(creator)"
        }
        return "Saved swipe"
    }

    /// Into the Swipe Studio with a one-item session — the swipe home page's
    /// own open grammar.
    private func openSource(_ source: SwipeGalleryItem) {
        guard source.entityId > 0 else { return }
        onClose()
        SwipeStudySession.shared.begin(order: [source.entityId], current: source.entityId)
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: [
                "type": EntityType.research,
                "id": source.entityId
            ]
        )
    }

    private var ageText: String {
        guard let date = ISO8601.date(from: idea.updatedAt) else { return "" }
        return date.cosmoCompactAge
    }
}
