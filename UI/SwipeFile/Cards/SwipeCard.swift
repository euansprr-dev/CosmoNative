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
        .swipeCardSurface(isHovered: isHovered, isSelected: isSelected, tint: model.platformColor ?? DS.entitySwipe)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2, perform: actions.onStudy)
        .onTapGesture(perform: actions.onOpen)
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
        .overlay(alignment: .bottomLeading) { platformGlyph }
        .overlay(alignment: .bottomTrailing) { durationBadge }
        .overlay(alignment: .topTrailing) {
            SwipeCardQuickActions(isVisible: isHovered, actions: actions)
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
                Rectangle()
                    .fill(DS.glassSectionFill)
                    .overlay {
                        Image(systemName: model.platformGlyph ?? "photo")
                            .font(DS.title2)
                            .foregroundStyle(DS.textMuted)
                    }
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

    @ViewBuilder
    private var outlierBadge: some View {
        if let outlier = model.outlierLabel {
            Text(outlier)
                .font(DS.caption.weight(.bold))
                .foregroundStyle(DS.textOnAccent)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(DS.accent, in: Capsule())
                .padding(8)
                .accessibilityLabel("Outlier \(outlier)")
        }
    }

    @ViewBuilder
    private var platformGlyph: some View {
        if let glyph = model.platformGlyph, model.aspect != .paper {
            Image(systemName: glyph)
                .font(DS.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(model.platformColor ?? DS.textMuted, in: Circle())
                .padding(8)
                .accessibilityHidden(true)
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
            Text(text)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .lineSpacing(3)
                .lineLimit(7)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.glassSectionFill)
    }
}

// MARK: - Quick actions

private struct SwipeCardQuickActions: View {
    let isVisible: Bool
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
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .animation(ProMotionSprings.hover, value: isVisible)
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
        VStack(alignment: .leading, spacing: 5) {
            if model.aspect != .paper {
                hookLine
            }
            metaRow
            if let metrics = model.metricsLine {
                Text(metrics)
                    .font(DS.caption.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(.top, 10)
        .padding(.horizontal, 12)
        .padding(.bottom, 11)
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
            if let creator = model.creatorLine {
                Text(creator)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }
            if let score = model.scoreLabel {
                Text("· \(score)")
                    .font(DS.caption.monospacedDigit())
                    .foregroundStyle(model.scoreTint ?? DS.textMuted)
            }
            if let age = model.ageLabel {
                Text("· \(age)")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 16)
    }
}
