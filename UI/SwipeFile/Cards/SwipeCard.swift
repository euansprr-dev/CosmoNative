import SwiftUI

// MARK: - Actions

struct SwipeCardActions {
    /// Single click — select + quick look.
    var onOpen: () -> Void = {}
    /// Double click / Return — straight into Swipe Study (or Save on Discover).
    var onStudy: () -> Void = {}
    /// Hover bookmark quick action; nil hides it (ignored when `boardMenu` is set).
    var onBookmark: (() -> Void)?
    /// Board membership menu for the bookmark quick action (library cards).
    var boardMenu: SwipeCardBoardMenu?
}

struct SwipeCardBoardMenu {
    let boards: [SwipeBoard]
    let memberIDs: Set<String>
    let onToggle: (SwipeBoard) -> Void
}

// MARK: - Card

/// The canonical swipe card: the media IS the card, chrome is a whisper.
/// Fixed height (`model.height(forWidth:)`) so the masonry never measures views.
struct SwipeCard: View {
    let model: SwipeCardModel
    let width: CGFloat
    var isSelected = false
    var actions = SwipeCardActions()

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SwipeCardMedia(model: model, width: width, isHovered: isHovered, actions: actions)
            SwipeCardFooter(model: model)
        }
        .frame(width: width, height: model.height(forWidth: width), alignment: .topLeading)
        .swipeCardSurface(isHovered: isHovered, isSelected: isSelected)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        // Library card ids ARE atom uuids — those cards drag as atom refs
        // (droppable on a concept board's gallery/sections). Discover ids are
        // platform post ids, so they don't offer the drag at all.
        .modifier(SwipeCardAtomDrag(atomUUID: UUID(uuidString: model.id) != nil ? model.id : nil))
        .scaleEffect(isHovered ? 1.02 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2, perform: actions.onStudy)
        .onTapGesture(perform: actions.onOpen)
        // A visible card is a click away from Swipe Study — prewarm its media
        // + decoded analysis so the bench opens with zero loading. Library
        // ids ARE atom uuids; Discover ids simply miss the lookup (no-op).
        .onAppear { SwipeStudyPrewarmer.shared.prewarm(uuid: model.id) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.hookText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Open study", actions.onStudy)
    }
}

// MARK: - Atom drag

/// Conditional `.draggable` — applied only when the card is atom-backed, so
/// Discover cards keep an unmodified view tree.
private struct SwipeCardAtomDrag: ViewModifier {
    let atomUUID: String?

    func body(content: Content) -> some View {
        if let atomUUID {
            content.draggable(AtomDragPayload(atomUUID: atomUUID))
        } else {
            content
        }
    }
}

// MARK: - Media well

private struct SwipeCardMedia: View {
    let model: SwipeCardModel
    let width: CGFloat
    let isHovered: Bool
    let actions: SwipeCardActions

    private var mediaHeight: CGFloat { model.mediaHeight(forWidth: width) }

    var body: some View {
        Group {
            if model.kind == .flow, !model.mosaicURLs.isEmpty {
                // A funnel's artwork is its steps — a mosaic reads as a
                // container, never as any one member.
                SwipeCardFlowMosaic(urls: model.mosaicURLs)
            } else if model.aspect == .paper {
                SwipeCardPaperWell(text: model.paperText ?? model.hookText)
            } else {
                thumbnail
            }
        }
        .frame(width: width, height: mediaHeight)
        .clipped()
        .overlay(alignment: .topLeading) { outlierBadge; genreBadge }
        .overlay(alignment: .bottomTrailing) { durationBadge }
        .overlay(alignment: .bottomLeading) { unitBadge }
        .overlay(alignment: .topTrailing) {
            // Mounted only on hover: the glass container + Menu are the most
            // expensive views on the card, and a masonry keeps 30–80 cards
            // live — parked at opacity 0 they still cost every scroll frame.
            if isHovered {
                SwipeCardQuickActions(actions: actions)
                    .transition(.opacity)
            }
        }
    }

    private var thumbnail: some View {
        CachedAsyncImage(url: model.mediaURL, stableKey: model.mediaStableKey) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .empty:
                Rectangle().fill(DS.glassSectionFill)
            case .failure:
                // Dead media degrades to content, never a broken-image glyph —
                // the hook carries the card until a live thumbnail exists.
                SwipeCardPaperWell(text: model.hookText)
            }
        }
        .frame(width: width, height: mediaHeight)
    }

    /// Outlier multiplier reads like the duration stamp — quiet metadata on the
    /// media, never an accent shout (accent is reserved for the live state).
    @ViewBuilder
    private var outlierBadge: some View {
        if let outlier = model.outlierLabel {
            Text(outlier)
                .font(DS.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .frame(height: 18)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(8)
                .accessibilityLabel("Outlier \(outlier)")
        }
    }

    /// "14 sections" / "3 images" — says a card holds more than the one frame
    /// you can see. Same quiet register as the duration stamp (Law 6: accent is
    /// punctuation, and this is metadata), with the kind's glyph so a page and
    /// a screenshot set are distinguishable at a glance in a mixed masonry.
    @ViewBuilder
    private var unitBadge: some View {
        if let badge = model.unitBadge {
            HStack(spacing: 4) {
                Image(systemName: model.kind.iconName)
                    .font(DS.caption2.weight(.semibold))
                Text(badge)
                    .font(DS.caption2.weight(.medium).monospacedDigit())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(model.kind.displayName), \(badge)")
        }
    }

    /// In mixed contexts a non-post card names its space ("Newsletter") —
    /// rendered on the media, never in the footer: footer heights are exact
    /// slot sums the masonry precomputes, and a new footer line would drift
    /// every column. Shares the outlier's slot; outliers only exist on
    /// Discover cards, which never set `showsGenreChip`.
    @ViewBuilder
    private var genreBadge: some View {
        if model.showsGenreChip, model.outlierLabel == nil {
            Text(model.genre.displayName)
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .frame(height: 18)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(8)
                .accessibilityLabel("Filed under \(model.genre.pluralName)")
        }
    }

    @ViewBuilder
    private var durationBadge: some View {
        if let duration = model.durationLabel {
            Text(duration)
                .font(DS.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .frame(height: 18)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(8)
                .accessibilityLabel("Duration \(duration)")
        }
    }
}

// MARK: - Paper well (text-only posts)

private struct SwipeCardPaperWell: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Fill the page: seven lines left half the well as dead air.
            // Bounded (not nil) so a transcript-length body never pays a
            // full typesetting pass — the frame clips the rest anyway.
            Text(text)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .lineSpacing(3)
                .lineLimit(14)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.glassSectionFill)
    }
}

// MARK: - Flow mosaic

/// Step-mosaic artwork for funnel cards: up to four member thumbnails on a
/// hairline grid. One member fills the well; two split it; three or more take
/// quadrants, with any empty quadrant staying a warm fill.
private struct SwipeCardFlowMosaic: View {
    let urls: [URL]

    var body: some View {
        Group {
            if urls.count == 1 {
                tile(urls[0])
            } else if urls.count == 2 {
                HStack(spacing: 1) {
                    tile(urls[0])
                    tile(urls[1])
                }
            } else {
                VStack(spacing: 1) {
                    HStack(spacing: 1) {
                        tile(urls[0])
                        tile(urls[1])
                    }
                    HStack(spacing: 1) {
                        tile(urls[2])
                        if urls.count > 3 { tile(urls[3]) } else { emptyQuadrant }
                    }
                }
            }
        }
        .background(DS.glassSectionFill)
    }

    private func tile(_ url: URL) -> some View {
        Color.clear.overlay {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Rectangle().fill(DS.glassSectionFill)
                }
            }
        }
        .clipped()
    }

    private var emptyQuadrant: some View {
        Rectangle().fill(DS.glassSectionFill)
    }
}

// MARK: - Quick actions

private struct SwipeCardQuickActions: View {
    let actions: SwipeCardActions

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                if let boardMenu = actions.boardMenu {
                    boardMenuButton(boardMenu)
                } else if let onBookmark = actions.onBookmark {
                    quickAction("bookmark", help: "Save", action: onBookmark)
                }
                quickAction("arrow.up.forward", help: "Open study (⏎)", action: actions.onStudy)
            }
        }
        .padding(8)
    }

    private func boardMenuButton(_ menu: SwipeCardBoardMenu) -> some View {
        Menu {
            ForEach(menu.boards) { board in
                Button {
                    menu.onToggle(board)
                } label: {
                    if menu.memberIDs.contains(board.uuid) {
                        Label(board.name, systemImage: "checkmark")
                    } else {
                        Label(board.name, systemImage: board.icon)
                    }
                }
            }
        } label: {
            Image(systemName: menu.memberIDs.isEmpty ? "bookmark" : "bookmark.fill")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(menu.memberIDs.isEmpty ? DS.text : DS.accent)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .help("Add to board")
        .accessibilityLabel("Add to board")
    }

    private func quickAction(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.text)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Footer

private struct SwipeCardFooter: View {
    let model: SwipeCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.aspect != .paper && model.showsHookLine {
                hookLine
            }
            metaRow
            if let metrics = model.metricsLine {
                Text(metrics)
                    .font(DS.caption.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
                    .frame(height: 13)
            }
        }
        .padding(.top, 9)
        .padding(.horizontal, 11)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: model.footerHeight, alignment: .top)
    }

    @ViewBuilder
    private var hookLine: some View {
        switch model.processing {
        case .ready:
            Text(model.hookText)
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(DS.text)
                .lineLimit(2)
                .frame(height: 36, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .pending:
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(DS.glassSectionFill)
                .frame(width: 140, height: 12)
                .frame(height: 36, alignment: .topLeading)
                .accessibilityLabel("Processing")
        case .failed:
            Label("Extraction failed", systemImage: "exclamationmark.triangle")
                .font(DS.callout.weight(.medium))
                .foregroundStyle(DS.textMuted)
                .frame(height: 36, alignment: .topLeading)
        }
    }

    private var metaRow: some View {
        HStack(spacing: 5) {
            if model.isUnstudied {
                Circle()
                    .fill(DS.accent)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel("Unstudied")
            }
            SwipePlatformGlyph(source: model.platformKey)
                .frame(width: 11, height: 11)
                .foregroundStyle(DS.textMuted)
            if let creator = model.creatorLine {
                Text(creator)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }
            // "·" separates TEXT tokens only — after a bare glyph it read as
            // an orphaned "· 9.2 · 2d".
            if let score = model.scoreLabel {
                Text(model.creatorLine == nil ? score : "· \(score)")
                    .font(DS.caption.monospacedDigit())
                    .foregroundStyle(model.scoreTint ?? DS.textMuted)
            }
            if let age = model.ageLabel {
                Text(model.creatorLine == nil && model.scoreLabel == nil ? age : "· \(age)")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 15)
    }
}
