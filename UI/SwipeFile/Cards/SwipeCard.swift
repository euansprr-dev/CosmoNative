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
        .scaleEffect(isHovered ? 1.01 : 1)
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

// MARK: - Media well

private struct SwipeCardMedia: View {
    let model: SwipeCardModel
    let width: CGFloat
    let isHovered: Bool
    let actions: SwipeCardActions

    private var mediaHeight: CGFloat { model.mediaHeight(forWidth: width) }

    var body: some View {
        Group {
            if model.aspect == .paper {
                SwipeCardPaperWell(text: model.paperText ?? model.hookText)
            } else {
                thumbnail
            }
        }
        .frame(width: width, height: mediaHeight)
        .clipped()
        .overlay(alignment: .bottom) { hoverScrim }
        .overlay(alignment: .topLeading) { outlierBadge }
        .overlay(alignment: .bottomTrailing) { durationBadge }
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

    /// The only scrim on the card — bottom gradient, hover-only, carries the badges.
    private var hoverScrim: some View {
        LinearGradient(
            colors: [.black.opacity(0), .black.opacity(0.38)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: mediaHeight * 0.35)
        .opacity(isHovered && model.aspect != .paper ? 1 : 0)
        .allowsHitTesting(false)
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
            if model.aspect != .paper {
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
