// CosmoOS/UI/Ideas/IdeaDeskCards.swift
// The Desk's card family (July 2026 Ideas reinvention). Three honest objects
// in the app's paper voice: the hero card for committed work (readiness
// ticks, scheduled chip, poster thumb), the proposal card that explains
// itself (why-line + quiet hover verbs), and the spark chip for the triage
// tray. One shared surface, one shared context menu, Mac manners throughout —
// hover, tooltips, drag out, swipe drop, ⌘Z-registered verbs behind every
// menu item.

import SwiftUI

// MARK: - Verb bundle (the desk's actions, closed over the model)

/// Everything a desk card can do, bundled so cards stay declarative. The
/// desk view builds ONE of these per idea from the page model's verbs.
struct IdeaDeskActions {
    var open: () -> Void
    var openAsPane: () -> Void
    var togglePin: () -> Void
    var pass: () -> Void
    var setStatus: (IdeaStatus) -> Void
    var assignClient: (String) -> Void
    var schedule: (Date) -> Void
    var delete: () -> Void
    var dropSwipe: (String) -> Void
    var assignableClients: [(uuid: String, name: String)] = []

    /// The schedule submenu's quick landings (the bench popover's grammar,
    /// menu-sized): today, tomorrow, the upcoming Saturday, next Monday.
    static func quickDays(from now: Date = .now) -> [(label: String, day: Date)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var days: [(String, Date)] = [
            ("Today", today),
            ("Tomorrow", calendar.date(byAdding: .day, value: 1, to: today) ?? today),
        ]
        if let saturday = calendar.nextDate(after: today, matching: DateComponents(weekday: 7), matchingPolicy: .nextTime),
           !calendar.isDate(saturday, inSameDayAs: days[1].1) {
            days.append(("This Weekend", saturday))
        }
        if let monday = calendar.nextDate(after: today, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime) {
            days.append(("Next Week", monday))
        }
        return days
    }
}

// MARK: - Shared context menu

/// The one menu every desk card carries — two `.contextMenu` modifiers on a
/// row silently drop the first, so all actions live here together.
struct IdeaDeskMenu: View {
    let idea: IdeaGalleryItem
    let actions: IdeaDeskActions

    var body: some View {
        Button(action: actions.open) {
            Label("Open", systemImage: "arrow.up.left.and.arrow.down.right")
        }
        Button(action: actions.openAsPane) {
            Label("Open in New Pane", systemImage: "rectangle.split.2x1")
        }
        Divider()
        Button(action: actions.togglePin) {
            Label(idea.isPinned ? "Remove from Up Next" : "Move Up Next", systemImage: idea.isPinned ? "pin.slash" : "pin")
        }
        Menu("Schedule Development") {
            ForEach(IdeaDeskActions.quickDays(), id: \.label) { quick in
                Button(quick.label) { actions.schedule(quick.day) }
            }
        }
        Menu("Set Status") {
            ForEach([IdeaStatus.spark, .developing, .ready], id: \.self) { status in
                Button {
                    actions.setStatus(status)
                } label: {
                    if idea.status == status {
                        Label(status.displayName, systemImage: "checkmark")
                    } else {
                        Text(status.displayName)
                    }
                }
            }
        }
        if !actions.assignableClients.isEmpty {
            Menu("Assign to Client") {
                ForEach(actions.assignableClients, id: \.uuid) { client in
                    Button {
                        actions.assignClient(client.uuid)
                    } label: {
                        if idea.clientUUID == client.uuid {
                            Label(client.name, systemImage: "checkmark")
                        } else {
                            Text(client.name)
                        }
                    }
                }
            }
        }
        Button(action: actions.pass) {
            Label("Pass — Archive", systemImage: "archivebox")
        }
        Divider()
        Button(role: .destructive, action: actions.delete) {
            Label("Delete Idea", systemImage: "trash")
        }
    }
}

// MARK: - Shared card chrome

/// The desk's paper surface: adaptive elevated fill + palette sepia hairline
/// (never the paper-doctrine document tokens — dark palettes need dark
/// cards), drop-target wash, cursor ring.
private struct IdeaDeskCardSurface: ViewModifier {
    var isCursor: Bool
    var isDropTarget: Bool
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .background(isDropTarget ? DS.entityIdea.opacity(0.06) : .clear)
            .background(DS.surfaceElevated)
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isDropTarget ? DS.entityIdea.opacity(0.45)
                            : isCursor ? DS.focusRing
                            : DS.palette.sepiaBorder,
                        lineWidth: isDropTarget ? 2 : isCursor ? 1.5 : 0.5
                    )
            )
            .contentShape(.rect(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Hover lift + press compress + drag out + swipe drop — the interaction
/// envelope every desk card shares.
private struct IdeaDeskCardManners: ViewModifier {
    let idea: IdeaGalleryItem
    let headline: String
    let thumbnailURL: String?
    let onDropSwipe: (String) -> Void
    @Binding var isHovered: Bool
    @Binding var isDropTarget: Bool

    func body(content: Content) -> some View {
        content
            .dsRestingShadow()
            .shadow(color: .black.opacity(isHovered ? 0.07 : 0), radius: 10, y: 3)
            .scaleEffect(isHovered ? 1.01 : 1)
            .animation(ProMotionSprings.hover, value: isHovered)
            .animation(ProMotionSprings.snappy, value: isDropTarget)
            .onHover { isHovered = $0 }
            .modifier(CommandKDragOutModifier(
                uuid: idea.atomUUID,
                title: headline,
                subtitle: idea.clientName ?? "Idea",
                accent: DS.entityIdea,
                symbolName: "lightbulb",
                thumbnailURL: thumbnailURL
            ))
            .dropDestination(for: String.self) { items, _ in
                guard let dropped = items.first.flatMap({ CommandKDragSession.Payload.uuids(fromDropped: $0).first }),
                      dropped != idea.atomUUID else { return false }
                onDropSwipe(dropped)
                return true
            } isTargeted: { targeted in
                isDropTarget = targeted
            }
    }
}

// MARK: - Readiness ticks

/// Four quiet dots — hooks, outline, inspiration, research — the idea's
/// development substance at a glance (the bench's ripening ladder, card-sized).
struct IdeaReadinessTicks: View {
    let idea: IdeaGalleryItem
    let hasInspiration: Bool

    private var ticks: [(filled: Bool, name: String)] {
        [
            (!idea.hooks.isEmpty, "hooks"),
            (!idea.outline.isEmpty, "outline"),
            (hasInspiration, "inspiration"),
            (idea.hasResearch, "research"),
        ]
    }

    var body: some View {
        HStack(spacing: DS.space4) {
            ForEach(Array(ticks.enumerated()), id: \.offset) { _, tick in
                Circle()
                    .fill(tick.filled ? DS.entityIdea.opacity(0.55) : DS.textMuted.opacity(0.22))
                    .frame(width: 5, height: 5)
            }
        }
        .help(ticksHelp)
        .accessibilityLabel(ticksHelp)
    }

    private var ticksHelp: String {
        let filled = ticks.filter(\.filled).map(\.name)
        return filled.isEmpty ? "Nothing developed yet" : "Has \(filled.joined(separator: ", "))"
    }
}

// MARK: - Hero card (the committed lane)

/// Committed work wears the desk's richest object: identity row, the hook in
/// its honest register, readiness ticks, the session chip, and the
/// inspiration thumb grown into a poster. Two compositions, one layout: a
/// short bare hook is a PULL QUOTE (display serif — the sentence is the
/// product, set like it matters); anything with substance is a document
/// (reading serif + up to two muted context lines, the Spotlight full-preview
/// law). The text block centers between the identity row and the footer so
/// neither state leaves a void. The whole card resumes the bench.
struct IdeaHeroCard: View {
    let idea: IdeaGalleryItem
    var inspirationThumbs: [String] = []
    var clientTint: Color?
    var scheduledDay: Date?
    var fixedHeight: CGFloat = 180
    var isCursor = false
    let actions: IdeaDeskActions

    @State private var isHovered = false
    @State private var isDropTarget = false

    /// Above this, display serif would wrap past two lines and crowd the
    /// card — the quote treatment is reserved for lines that can carry it.
    private static let quoteThreshold = 40

    private var headline: String {
        if let hook = idea.hooks.first, !hook.isEmpty { return hook }
        return idea.title
    }

    /// The idea's own body, flattened to flowing lines (context falls back
    /// to body upstream in `toIdeaGalleryItem`).
    private var excerpt: String? {
        guard let context = idea.context?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !context.isEmpty else { return nil }
        return context
    }

    /// Quote or document — binary, data-derived, never a sliding scale
    /// (three type sizes in one shelf reads ransom-note, not editorial).
    private var isQuoteCard: Bool {
        excerpt == nil && headline.count <= Self.quoteThreshold
    }

    var body: some View {
        Button(action: actions.open) {
            HStack(alignment: .center, spacing: DS.space12) {
                VStack(alignment: .leading, spacing: 0) {
                    identityRow
                    Spacer(minLength: DS.space6)
                    textBlock
                    Spacer(minLength: DS.space6)
                    footerRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !inspirationThumbs.isEmpty {
                    IdeaInspirationThumb(
                        candidates: inspirationThumbs,
                        hairline: DS.palette.sepiaBorder,
                        width: 72,
                        height: 92
                    )
                }
            }
            .padding(DS.space16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: fixedHeight)
            .modifier(IdeaDeskCardSurface(isCursor: isCursor, isDropTarget: isDropTarget))
        }
        .buttonStyle(IdeaCardPressStyle())
        .modifier(IdeaDeskCardManners(
            idea: idea,
            headline: headline,
            thumbnailURL: inspirationThumbs.first,
            onDropSwipe: actions.dropSwipe,
            isHovered: $isHovered,
            isDropTarget: $isDropTarget
        ))
        .contextMenu { IdeaDeskMenu(idea: idea, actions: actions) }
        .help("Continue \(headline) (⏎)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(.isButton)
    }

    private var identityRow: some View {
        HStack(spacing: DS.space6) {
            if let clientName = idea.clientName, !clientName.isEmpty {
                Circle()
                    .fill(clientTint ?? DS.textMuted)
                    .frame(width: 6, height: 6)
                Text(clientName)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.space8)
            if let scheduledDay {
                HStack(spacing: 3) {
                    Image(systemName: "calendar")
                        .accessibilityHidden(true)
                    Text(IdeasPageModel.dayLabel(scheduledDay))
                        .lineLimit(1)
                }
                .foregroundStyle(DS.entityIdea.opacity(0.9))
            } else if idea.status == .ready {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.seal.fill")
                        .accessibilityHidden(true)
                    Text("Ready")
                }
                .foregroundStyle(DS.entityIdea.opacity(0.9))
            }
        }
        .font(DS.caption2)
        .foregroundStyle(DS.textMuted)
    }

    /// Hook (+ excerpt when the idea has a body). Quote cards set the line
    /// at display scale; document cards keep the reading register and show
    /// their own material beneath — never both treatments at once.
    private var textBlock: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text(headline)
                .font(isQuoteCard ? DS.heroTitleSerif : DS.blockTitleSerif)
                .foregroundStyle(DS.text)
                .lineSpacing(isQuoteCard ? 3 : 2)
                .lineLimit(isQuoteCard ? 2 : 3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let excerpt {
                // No fixedSize: the excerpt yields (truncates) before it can
                // ever push a long hook against the card's fixed height.
                Text(excerpt)
                    .font(DS.subheadline)
                    .foregroundStyle(DS.textSecondary)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var footerRow: some View {
        HStack(spacing: DS.space8) {
            IdeaReadinessTicks(idea: idea, hasInspiration: !inspirationThumbs.isEmpty)
            Text(ageText)
                .font(DS.caption2)
                .monospacedDigit()
                .foregroundStyle(DS.textMuted)
            Spacer(minLength: DS.space8)
            HStack(spacing: 3) {
                Text("Continue")
                Image(systemName: "arrow.right")
                    .accessibilityHidden(true)
            }
            .font(DS.caption.weight(.medium))
            .foregroundStyle(DS.accent)
            .opacity(isHovered ? 1 : 0)
        }
    }

    private var ageText: String {
        guard let date = ISO8601.date(from: idea.updatedAt) else { return "" }
        return date.cosmoCompactAge
    }

    private var accessibilitySummary: String {
        var parts = [headline]
        if let client = idea.clientName { parts.append(client) }
        if let scheduledDay { parts.append("Scheduled \(IdeasPageModel.dayLabel(scheduledDay))") }
        else if idea.status == .ready { parts.append("Ready") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Proposal card (the choose-next grid)

/// A ranked candidate that explains itself: serif hook, the engine's
/// why-line, one quiet meta line — and on hover, the two lane verbs (Up
/// Next, Pass). The whole card opens the bench; the verbs move it instead.
struct IdeaProposalCard: View {
    let proposal: IdeasDeskEngine.Proposal
    var inspirationThumbs: [String] = []
    var fixedHeight: CGFloat = 150
    var isCursor = false
    let actions: IdeaDeskActions

    @State private var isHovered = false
    @State private var isDropTarget = false

    private var idea: IdeaGalleryItem { proposal.item }

    private var headline: String {
        if let hook = idea.hooks.first, !hook.isEmpty { return hook }
        return idea.title
    }

    var body: some View {
        Button(action: actions.open) {
            HStack(alignment: .top, spacing: DS.space12) {
                VStack(alignment: .leading, spacing: DS.space6) {
                    hookText
                    Text(proposal.whyLine)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    metaRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !inspirationThumbs.isEmpty {
                    IdeaInspirationThumb(candidates: inspirationThumbs, hairline: DS.palette.sepiaBorder)
                }
            }
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: fixedHeight)
            .modifier(IdeaDeskCardSurface(isCursor: isCursor, isDropTarget: isDropTarget))
        }
        .buttonStyle(IdeaCardPressStyle())
        .modifier(IdeaDeskCardManners(
            idea: idea,
            headline: headline,
            thumbnailURL: inspirationThumbs.first,
            onDropSwipe: actions.dropSwipe,
            isHovered: $isHovered,
            isDropTarget: $isDropTarget
        ))
        .overlay(alignment: .bottomTrailing) { hoverVerbs }
        .contextMenu { IdeaDeskMenu(idea: idea, actions: actions) }
        .help("Open \(headline) (⏎)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headline), \(proposal.whyLine)")
        .accessibilityAddTraits(.isButton)
    }

    private var hookText: some View {
        Text(headline)
            .font(DS.blockTitleSerif)
            .foregroundStyle(DS.text)
            .lineSpacing(2)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Format · platform · age — the compact register (marks carry identity).
    private var metaRow: some View {
        HStack(spacing: DS.space6) {
            if let format = idea.contentFormat {
                Text(CollectionEmoji.formatMark(format))
                    .font(.system(size: 12))
                Text("·")
            }
            if let family = platformFamily {
                SwipePlatformGlyph(source: family)
                    .frame(width: 9, height: 9)
                Text("·")
            }
            Text(ageText)
                .monospacedDigit()
        }
        .font(DS.caption2)
        .foregroundStyle(DS.textMuted)
    }

    /// The two lane verbs, hover-quiet (keyboard: P pins; menu carries all).
    private var hoverVerbs: some View {
        HStack(spacing: DS.space6) {
            DeskVerbButton(
                systemName: "pin",
                help: "Move Up Next (P)",
                action: actions.togglePin
            )
            DeskVerbButton(
                systemName: "archivebox",
                help: "Pass — archive this idea",
                action: actions.pass
            )
        }
        .padding(DS.space10)
        .opacity(isHovered ? 1 : 0)
        .animation(ProMotionSprings.hover, value: isHovered)
        .accessibilityHidden(!isHovered)
    }

    private var platformFamily: String? {
        guard let raw = idea.platform?.rawValue else { return nil }
        return raw == "x" ? "x_post" : raw
    }

    private var ageText: String {
        guard let date = ISO8601.date(from: idea.updatedAt) else { return "" }
        return date.cosmoCompactAge
    }
}

/// A quiet 24pt verb — warm fill, hairline, tooltip. Flat on the card
/// (cards are content; glass is for chrome). Shared with the ledger rows.
struct DeskVerbButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(DS.caption.weight(.medium))
                .foregroundStyle(isHovered ? DS.entityIdea : DS.textSecondary)
                .frame(width: 24, height: 24)
                .background(DS.glassSectionFill, in: .circle)
                .overlay(Circle().strokeBorder(DS.palette.sepiaBorder, lineWidth: 0.5))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Spark chip (the triage tray)

/// An unassigned capture, tray-sized: the hook's first breath + age. Click
/// opens the bench; the menu assigns it home.
struct IdeaSparkChip: View {
    let idea: IdeaGalleryItem
    var isCursor = false
    let actions: IdeaDeskActions

    @State private var isHovered = false
    @State private var isDropTarget = false

    private var headline: String {
        if let hook = idea.hooks.first, !hook.isEmpty { return hook }
        return idea.title
    }

    var body: some View {
        Button(action: actions.open) {
            VStack(alignment: .leading, spacing: DS.space4) {
                Text(headline)
                    .font(DS.subheadline.weight(.medium))
                    .foregroundStyle(DS.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(ageText)
                    .font(DS.caption2)
                    .monospacedDigit()
                    .foregroundStyle(DS.textMuted)
            }
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space10)
            .frame(width: 220, height: 72, alignment: .topLeading)
            .modifier(IdeaDeskCardSurface(isCursor: isCursor, isDropTarget: isDropTarget, cornerRadius: 12))
        }
        .buttonStyle(IdeaCardPressStyle())
        .modifier(IdeaDeskCardManners(
            idea: idea,
            headline: headline,
            thumbnailURL: nil,
            onDropSwipe: actions.dropSwipe,
            isHovered: $isHovered,
            isDropTarget: $isDropTarget
        ))
        .contextMenu { IdeaDeskMenu(idea: idea, actions: actions) }
        .help("Open \(headline) (⏎)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headline), unassigned spark")
        .accessibilityAddTraits(.isButton)
    }

    private var ageText: String {
        guard let date = ISO8601.date(from: idea.createdAt) else { return "" }
        return date.cosmoCompactAge
    }
}

// MARK: - Press style (the compress-and-spring answer)

/// The card answers the click before the focus transition begins. Shared by
/// every idea card on the page. (`ButtonStyleConfiguration` spelled out — the
/// repo has a top-level `Configuration` type that hijacks the shorthand.)
struct IdeaCardPressStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(ProMotionSprings.snappy, value: configuration.isPressed)
    }
}

// MARK: - Inspiration thumb (shared with the bench inspector)

/// The inspired-by swipe thumb with a fallback chain: the durable Supabase
/// mirror first, the origin CDN url second. If every candidate fails the
/// thumb collapses — an empty grey well is worse than no anchor at all.
/// Shared with the Idea Focus inspector so a swipe wears the same face
/// everywhere it appears (identity outranks type).
struct IdeaInspirationThumb: View {
    let candidates: [String]
    let hairline: Color
    var width: CGFloat = 44
    var height: CGFloat = 56

    @State private var index = 0
    @State private var exhausted = false

    var body: some View {
        if !exhausted, candidates.indices.contains(index) {
            let candidate = candidates[index]
            CachedAsyncImage(url: URL(string: candidate), stableKey: candidate) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .empty:
                    Rectangle().fill(DS.glassSectionFill)
                case .failure:
                    Rectangle().fill(DS.glassSectionFill)
                        .onAppear { advance() }
                }
            }
            .frame(width: width, height: height)
            .clipShape(.rect(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(hairline, lineWidth: 0.5)
            )
            .accessibilityHidden(true)
        }
    }

    private func advance() {
        if index + 1 < candidates.count {
            index += 1
        } else {
            exhausted = true
        }
    }
}
