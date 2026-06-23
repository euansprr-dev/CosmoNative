// CosmoOS/Canvas/ConstellationView.swift
// The Constellation — zoom out of any canvas into a Mission Control of all
// thinkspaces: live miniatures in project lanes, activity halos, search that
// sinks non-matches instead of unmounting them. Click a card to dive in.

import SwiftUI

/// Reports each card's thumbnail frame so the zoom dissolve can land exactly.
struct ConstellationCardFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct ConstellationView: View {
    let thinkspaces: [Thinkspace]
    var originThinkspaceId: String? = nil
    /// True when the pinch scrub mounted this view: the gesture drives the
    /// reveal externally (opacity in the host), so the internal fade, the
    /// entrance dissolve, and the search-focus grab are all skipped — the
    /// live canvas shrinking beneath provides the continuity instead.
    var interactiveReveal: Bool = false
    /// False while the scrub is still reversible; flips true on commit.
    var isCommitted: Bool = true
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var appeared = false
    @State private var suppressEntranceDissolve = false
    @State private var cardFrames: [String: CGRect] = [:]
    /// The zoom dissolve: a thumbnail flying between full-window and its card.
    @State private var zoomImage: NSImage?
    @State private var zoomCardId: String?
    @State private var zoomExpanded = false
    @State private var hasPlayedEntrance = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                field
                content
                zoomOverlay(in: geo.size)
            }
            .coordinateSpace(name: "constellation")
            .onPreferenceChange(ConstellationCardFramesKey.self) { frames in
                cardFrames = frames
                beginEntranceDissolveIfReady(in: geo.size)
            }
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            suppressEntranceDissolve = interactiveReveal
            if interactiveReveal {
                appeared = true
            } else {
                searchFocused = true
                withAnimation(reduceMotion ? .linear(duration: 0.01) : ProMotionSprings.modal) {
                    appeared = true
                }
            }
            prewarmLikelyDestinations()
        }
        .onChange(of: isCommitted) { _, committed in
            if committed { searchFocused = true }
        }
        .onExitCommand(perform: onDismiss)
    }

    // MARK: Zoom dissolve

    /// On entry from a canvas: its thumbnail starts full-window and shrinks
    /// into its own card — the canvas visibly *becomes* a card in the field.
    /// Plays at most once per presentation: card frames keep changing on
    /// hover, and replaying would read as zoom spam.
    private func beginEntranceDissolveIfReady(in size: CGSize) {
        guard !reduceMotion,
              !suppressEntranceDissolve,
              !hasPlayedEntrance,
              zoomCardId == nil,
              let origin = originThinkspaceId,
              cardFrames[origin] != nil,
              let image = ThinkspaceThumbnailService.shared.cachedThumbnail(for: origin) else { return }

        hasPlayedEntrance = true
        zoomImage = image
        zoomCardId = origin
        zoomExpanded = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            withAnimation(ProMotionSprings.modal) { zoomExpanded = false }
            try? await Task.sleep(for: .milliseconds(520))
            zoomCardId = nil
            zoomImage = nil
        }
    }

    /// On dive: the chosen card's thumbnail grows to fill the window while
    /// the real canvas swaps thinkspaces UNDERNEATH — the switch starts at
    /// click, so the zoom animation doubles as the loading window. For a
    /// prewarmed space the canvas is live before the expansion lands; the
    /// dive cover (under the fading Constellation) holds for slower loads.
    private func dive(into thinkspaceId: String) {
        guard !reduceMotion,
              cardFrames[thinkspaceId] != nil,
              let image = ThinkspaceThumbnailService.shared.cachedThumbnail(for: thinkspaceId) else {
            onSelect(thinkspaceId)
            return
        }
        zoomImage = image
        zoomCardId = thinkspaceId
        zoomExpanded = false
        onSelect(thinkspaceId)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            withAnimation(ProMotionSprings.modal) { zoomExpanded = true }
        }
    }

    @ViewBuilder
    private func zoomOverlay(in size: CGSize) -> some View {
        if let zoomImage, let zoomCardId, let cardFrame = cardFrames[zoomCardId] {
            let fullRect = CGRect(origin: .zero, size: size)
            let rect = zoomExpanded ? fullRect : cardFrame
            Image(nsImage: zoomImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: rect.width, height: rect.height)
                .clipShape(RoundedRectangle(cornerRadius: zoomExpanded ? 0 : 14, style: .continuous))
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
                .zIndex(10)
        }
    }

    // MARK: Field

    private var field: some View {
        DS.canvas
            .filmGrain()
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
    }

    private var content: some View {
        let library = library
        return VStack(spacing: 0) {
            header
                .padding(.horizontal, contentMargin)
                .padding(.top, DS.space36)
                .padding(.bottom, DS.space24)

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: DS.space40) {
                    if !library.featured.isEmpty {
                        continueShelf(library.featured)
                    }
                    ForEach(library.lanes) { lane in
                        laneSection(lane, cascadeOffset: library.featured.count)
                    }
                }
                .padding(.horizontal, contentMargin)
                .padding(.bottom, DS.space48)
            }
            .scrollIndicators(.hidden)
        }
        .scaleEffect(appeared ? 1 : 1.05)
    }

    private var contentMargin: CGFloat { DS.space48 }

    // MARK: Header

    /// The screen's voice: one hero title, the count demoted beside it, the
    /// search field quiet at the trailing edge.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.space16) {
            Text("Thinkspaces")
                .font(DS.pageTitle)
                .foregroundStyle(DS.text)
            Text("\(thinkspaces.count)")
                .font(DS.title3)
                .foregroundStyle(DS.textMuted)
                .monospacedDigit()
            Spacer(minLength: DS.space16)
            searchField
        }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(DS.subheadline)
                .foregroundStyle(searchFocused ? DS.accent : DS.textMuted)
            TextField("Find a thinkspace", text: $query)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .focused($searchFocused)
                .onSubmit(diveIntoTopMatch)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(width: 300)
        .dsGlassInput(isFocused: searchFocused, cornerRadius: 12)
        .accessibilityLabel("Find a thinkspace")
    }

    private func diveIntoTopMatch() {
        guard !trimmedQuery.isEmpty else { return }
        if let match = thinkspaces.first(where: { matches($0) }) {
            dive(into: match.id)
        }
    }

    /// The most recent spaces are where dives usually go — warm their
    /// snapshots the moment the Constellation opens so entry is instant
    /// even without hover dwell. (Hovering any card prewarms it too.)
    private func prewarmLikelyDestinations() {
        let recent = thinkspaces.sorted { $0.lastOpened > $1.lastOpened }.prefix(3)
        for space in recent {
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.prewarmThinkspace,
                object: nil,
                userInfo: ["thinkspaceId": space.id]
            )
        }
    }

    // MARK: Library structure

    private struct Lane: Identifiable {
        let id: String
        let title: String
        let spaces: [Thinkspace]
    }

    private struct Library {
        var featured: [Thinkspace]
        var lanes: [Lane]
    }

    /// Featured tier + lanes. The three most recent unassigned spaces are
    /// promoted into the Continue shelf (and removed from their lane — every
    /// space appears exactly once, so the zoom dissolve always has one
    /// unambiguous card to land on). Project lanes are never broken up.
    private var library: Library {
        var projectLanes: [Lane] = []
        let roots = thinkspaces.filter { $0.isRootThinkspace }
        var claimed: Set<String> = []

        for root in roots {
            guard let projectUuid = root.projectUuid else { continue }
            var members = thinkspaces.filter { $0.projectUuid == projectUuid && $0.id != root.id }
            members.sort { $0.lastOpened > $1.lastOpened }
            let spaces = [root] + members
            claimed.formUnion(spaces.map(\.id))
            projectLanes.append(Lane(id: projectUuid, title: root.name, spaces: spaces))
        }

        var unassigned = thinkspaces
            .filter { !claimed.contains($0.id) }
            .sorted { $0.lastOpened > $1.lastOpened }

        projectLanes.sort { ($0.spaces.first?.lastOpened ?? .distantPast) > ($1.spaces.first?.lastOpened ?? .distantPast) }

        var featured: [Thinkspace] = []
        if unassigned.count >= 6 {
            featured = Array(unassigned.prefix(3))
            unassigned = Array(unassigned.dropFirst(3))
        }

        var lanes = projectLanes
        if !unassigned.isEmpty {
            lanes.append(Lane(id: "open-ground", title: "Open ground", spaces: unassigned))
        }
        return Library(featured: featured, lanes: lanes)
    }

    // MARK: Sections

    /// The recency tier: the spaces you were just in, one size up — the
    /// screen's focal point and the usual exit ramp.
    @ViewBuilder
    private func continueShelf(_ spaces: [Thinkspace]) -> some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Text("Continue")
                .font(DS.title3.weight(.semibold))
                .foregroundStyle(DS.textSecondary)

            HStack(alignment: .top, spacing: DS.space20) {
                ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                    ConstellationCard(
                        thinkspace: space,
                        isFeatured: true,
                        appearIndex: index,
                        dimmed: !trimmedQuery.isEmpty && !matches(space),
                        onSelect: { dive(into: space.id) }
                    )
                    .frame(maxWidth: 360)
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func laneSection(_ lane: Lane, cascadeOffset: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack(spacing: DS.space8) {
                Text(lane.title)
                    .font(DS.title3.weight(.semibold))
                    .foregroundStyle(DS.textSecondary)
                Text("\(lane.spaces.count)")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .monospacedDigit()
                    .padding(.horizontal, DS.space8)
                    .padding(.vertical, 3)
                    .background(DS.glassInputFill, in: Capsule())
                    .overlay(Capsule().stroke(DS.glassBorder, lineWidth: 0.5))
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 224, maximum: 264), spacing: DS.space20)],
                alignment: .leading,
                spacing: DS.space24
            ) {
                ForEach(Array(lane.spaces.enumerated()), id: \.element.id) { index, space in
                    ConstellationCard(
                        thinkspace: space,
                        isFeatured: false,
                        appearIndex: index + cascadeOffset,
                        dimmed: !trimmedQuery.isEmpty && !matches(space),
                        onSelect: { dive(into: space.id) }
                    )
                }
            }
        }
    }

    // MARK: Query

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matches(_ thinkspace: Thinkspace) -> Bool {
        guard !trimmedQuery.isEmpty else { return true }
        return thinkspace.name.localizedCaseInsensitiveContains(trimmedQuery)
    }
}

// MARK: - Overlay host

/// Owns the Constellation's presence in MainView's ZStack. Deliberately tiny:
/// it is the only view that reads `ConstellationZoomScrubState.progress`, so
/// the pinch gesture's 120Hz writes re-evaluate just this body — never
/// MainView's. Mounts the Constellation the moment a scrub begins (opacity
/// tied 1:1 to pull depth, hit-testing off until committed), handles the
/// recede animation when a shallow pull is released, and the classic fade
/// when a committed Constellation is dismissed.
struct ConstellationOverlayHost: View {
    let thinkspaces: [Thinkspace]
    let originThinkspaceId: String?
    /// MainView's `showConstellation` — true once presentation has committed.
    let isCommitted: Bool
    let onSelect: (String) -> Void
    let onDismiss: () -> Void
    /// Fired when the overlay has fully left the screen (cancel fade done or
    /// dismissal transition finished) — MainView decides whether captures are
    /// safe again (a dive cover may still be holding the screen).
    let onFullyDismissed: () -> Void

    /// Once committed, the reveal opacity stays pinned at 1 — including
    /// during the dismissal transition, when `isCommitted` is already false
    /// again. Without this the view would snap invisible the moment a
    /// dismissal starts instead of fading.
    @State private var hasBeenCommitted = false
    /// Drives the recede animation after a shallow pull is released: the
    /// model `progress` is already 0, so a local animatable value carries
    /// the fade and the view unmounts when it lands.
    @State private var isCancelFading = false
    @State private var cancelFadeOpacity: CGFloat = 0

    var body: some View {
        let progress = ConstellationZoomScrubState.shared.progress
        if isCommitted || progress > 0 || isCancelFading {
            ConstellationView(
                thinkspaces: thinkspaces,
                originThinkspaceId: originThinkspaceId,
                interactiveReveal: !isCommitted,
                isCommitted: isCommitted,
                onSelect: onSelect,
                onDismiss: onDismiss
            )
            .opacity(revealOpacity(progress: progress))
            .allowsHitTesting(isCommitted)
            .transition(.opacity)
            .onAppear {
                // A keyboard present mounts already-committed; onChange below
                // never fires in that case, so pin the opacity here too.
                if isCommitted { hasBeenCommitted = true }
            }
            .onChange(of: isCommitted) { _, committed in
                if committed {
                    hasBeenCommitted = true
                    isCancelFading = false
                }
            }
            .onChange(of: progress) { old, new in
                guard !isCommitted, !hasBeenCommitted else { return }
                if new > 0 {
                    isCancelFading = false
                } else if old > 0 {
                    beginCancelFade(from: old)
                }
            }
            .onDisappear {
                hasBeenCommitted = false
                isCancelFading = false
                onFullyDismissed()
            }
        }
    }

    private func revealOpacity(progress: CGFloat) -> CGFloat {
        if isCommitted || hasBeenCommitted { return 1 }
        if isCancelFading { return cancelFadeOpacity }
        return progress
    }

    private func beginCancelFade(from value: CGFloat) {
        isCancelFading = true
        cancelFadeOpacity = value
        withAnimation(.easeOut(duration: 0.16)) {
            cancelFadeOpacity = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard isCancelFading,
                  ConstellationZoomScrubState.shared.progress <= 0 else { return }
            isCancelFading = false
        }
    }
}

// MARK: - Card

private struct ConstellationCard: View {
    let thinkspace: Thinkspace
    let isFeatured: Bool
    let appearIndex: Int
    let dimmed: Bool
    let onSelect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var thumbnail: NSImage?
    @State private var hasAppeared = false
    @State private var isHovered = false
    @State private var prewarmTask: Task<Void, Never>?

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: DS.space8) {
                thumbnailView
                meta
            }
        }
        .buttonStyle(.plain)
        .opacity(dimmed ? 0.3 : (hasAppeared ? 1 : 0))
        .scaleEffect(dimmed ? 0.97 : (hasAppeared ? (isHovered ? 1.01 : 1) : 0.96))
        .animation(ProMotionSprings.gentle, value: dimmed)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : ProMotionSprings.hover) { isHovered = hovering }
            schedulePrewarm(hovering)
        }
        .onAppear(perform: animateIn)
        .onDisappear { prewarmTask?.cancel() }
        .task(id: thinkspace.id) {
            thumbnail = ThinkspaceThumbnailService.shared.cachedThumbnail(for: thinkspace.id)
            thumbnail = await ThinkspaceThumbnailService.shared.thumbnail(
                for: thinkspace.id,
                size: CGSize(width: 280, height: 170)
            ) ?? thumbnail
        }
        .help("Open \(thinkspace.name)")
        .accessibilityLabel("Open thinkspace \(thinkspace.name)")
    }

    private func animateIn() {
        guard !reduceMotion else {
            hasAppeared = true
            return
        }
        guard !hasAppeared else { return }
        withAnimation(ProMotionSprings.cascade(index: min(appearIndex, 8))) {
            hasAppeared = true
        }
    }

    /// Hover intent → prewarm: a brief dwell predicts a dive, so the
    /// thinkspace's blocks load into the snapshot cache before the click.
    /// Debounced so sweeping the pointer across the grid stays free.
    private func schedulePrewarm(_ hovering: Bool) {
        prewarmTask?.cancel()
        guard hovering else { return }
        let targetId = thinkspace.id
        prewarmTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.prewarmThinkspace,
                object: nil,
                userInfo: ["thinkspaceId": targetId]
            )
        }
    }

    // MARK: Thumbnail

    /// One neutral material for every card: surface fill, hairline, soft
    /// black shadow. No accent bars, no tinted halos — the thumbnail's own
    /// content is the only color, so spaces with work in them naturally draw
    /// the eye and empty ones recede into quiet parchment wells.
    private var thumbnailView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.surfaceElevated)

            if let thumbnail, thinkspace.blockCount > 0 {
                // Color.clear drives layout; the fill image only paints —
                // a bare .fill image would force the card wider than its
                // grid cell and make neighbors overlap.
                Color.clear
                    .overlay(
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    )
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.glassSectionFill)
                Image(systemName: "rectangle.3.group")
                    .font(isFeatured ? DS.title2 : DS.title3)
                    .foregroundStyle(DS.textMuted.opacity(0.35))
            }
        }
        .frame(height: isFeatured ? 184 : 141)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ConstellationCardFramesKey.self,
                    value: [thinkspace.id: proxy.frame(in: .named("constellation"))]
                )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(DS.glassBorder, lineWidth: 0.5)
        )
        .shadow(
            color: .black.opacity(isHovered ? 0.08 : 0.05),
            radius: isHovered ? 14 : 8,
            y: isHovered ? 4 : 2
        )
    }

    // MARK: Meta

    private var meta: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(thinkspace.name)
                .font(isFeatured ? DS.headline : DS.callout.weight(.semibold))
                .foregroundStyle(DS.text)
                .lineLimit(1)

            Group {
                if thinkspace.blockCount == 0 {
                    Text("Empty · \(thinkspace.lastOpened, format: .relative(presentation: .named))")
                } else {
                    Text("\(thinkspace.blockCount) blocks · \(thinkspace.lastOpened, format: .relative(presentation: .named))")
                        .monospacedDigit()
                }
            }
            .font(DS.caption)
            .foregroundStyle(DS.textMuted)
        }
        .padding(.horizontal, 2)
    }
}
