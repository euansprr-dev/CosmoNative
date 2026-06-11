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
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var appeared = false
    @State private var cardFrames: [String: CGRect] = [:]
    /// The zoom dissolve: a thumbnail flying between full-window and its card.
    @State private var zoomImage: NSImage?
    @State private var zoomCardId: String?
    @State private var zoomExpanded = false
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
            searchFocused = true
            withAnimation(reduceMotion ? .linear(duration: 0.01) : ProMotionSprings.modal) {
                appeared = true
            }
        }
        .onExitCommand(perform: onDismiss)
    }

    // MARK: Zoom dissolve

    /// On entry from a canvas: its thumbnail starts full-window and shrinks
    /// into its own card — the canvas visibly *becomes* a card in the field.
    private func beginEntranceDissolveIfReady(in size: CGSize) {
        guard !reduceMotion,
              zoomCardId == nil,
              let origin = originThinkspaceId,
              cardFrames[origin] != nil,
              let image = ThinkspaceThumbnailService.shared.cachedThumbnail(for: origin) else { return }

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

    /// On dive: the chosen card's thumbnail grows to fill the window, then
    /// the real canvas takes over underneath.
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
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            withAnimation(ProMotionSprings.modal) { zoomExpanded = true }
            try? await Task.sleep(for: .milliseconds(380))
            onSelect(thinkspaceId)
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
        VStack(spacing: 18) {
            searchField
                .padding(.top, 28)

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(lanes) { lane in
                        laneSection(lane)
                    }
                }
                .padding(.horizontal, 48)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
        }
        .scaleEffect(appeared ? 1 : 1.05)
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(DS.subheadline)
                .foregroundStyle(DS.textMuted)
            TextField("Find a thinkspace", text: $query)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .focused($searchFocused)
                .onSubmit(diveIntoTopMatch)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(width: 360)
        .dsGlassInput(isFocused: searchFocused, cornerRadius: 12)
        .accessibilityLabel("Find a thinkspace")
    }

    private func diveIntoTopMatch() {
        guard !trimmedQuery.isEmpty else { return }
        if let match = thinkspaces.first(where: { matches($0) }) {
            dive(into: match.id)
        }
    }

    // MARK: Lanes

    private struct Lane: Identifiable {
        let id: String
        let title: String
        let accent: Color
        let spaces: [Thinkspace]
    }

    private var lanes: [Lane] {
        var projectLanes: [Lane] = []
        var unassigned: [Thinkspace] = []

        let roots = thinkspaces.filter { $0.isRootThinkspace }
        var claimed: Set<String> = []

        for root in roots {
            guard let projectUuid = root.projectUuid else { continue }
            var members = thinkspaces.filter { $0.projectUuid == projectUuid && $0.id != root.id }
            members.sort { $0.lastOpened > $1.lastOpened }
            let spaces = [root] + members
            claimed.formUnion(spaces.map(\.id))
            projectLanes.append(Lane(id: projectUuid, title: root.name, accent: root.accentColor, spaces: spaces))
        }

        unassigned = thinkspaces
            .filter { !claimed.contains($0.id) }
            .sorted { $0.lastOpened > $1.lastOpened }

        projectLanes.sort { ($0.spaces.first?.lastOpened ?? .distantPast) > ($1.spaces.first?.lastOpened ?? .distantPast) }

        var result = projectLanes
        if !unassigned.isEmpty {
            result.append(Lane(id: "open-ground", title: "Open ground", accent: DS.accent, spaces: unassigned))
        }
        return result
    }

    @ViewBuilder
    private func laneSection(_ lane: Lane) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(lane.accent)
                    .frame(width: 3, height: 16)
                Text(lane.title)
                    .font(DS.title2)
                    .foregroundStyle(DS.text)
                Text("\(lane.spaces.count)")
                    .font(DS.caption.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 16)],
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(Array(lane.spaces.enumerated()), id: \.element.id) { index, space in
                    ConstellationCard(
                        thinkspace: space,
                        isRoot: space.isRootThinkspace,
                        appearIndex: index,
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

// MARK: - Card

private struct ConstellationCard: View {
    let thinkspace: Thinkspace
    let isRoot: Bool
    let appearIndex: Int
    let dimmed: Bool
    let onSelect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var thumbnail: NSImage?
    @State private var hasAppeared = false
    @State private var isHovered = false

    private var isRecentlyActive: Bool {
        Date().timeIntervalSince(thinkspace.lastOpened) < 24 * 3600
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
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
        }
        .onAppear(perform: animateIn)
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

    // MARK: Thumbnail

    private var thumbnailView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.surfaceElevated)

            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "rectangle.3.group")
                    .font(DS.title2)
                    .foregroundStyle(DS.textMuted.opacity(0.4))
            }
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ConstellationCardFramesKey.self,
                    value: [thinkspace.id: proxy.frame(in: .named("constellation"))]
                )
            }
        )
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(thinkspace.accentColor)
                .frame(height: 3)
                .padding(.horizontal, 14)
                .padding(.top, 0)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(DS.glassBorder, lineWidth: 0.5)
        )
        .shadow(
            color: haloColor,
            radius: isRecentlyActive ? 12 : (isHovered ? 16 : 8),
            y: isHovered ? 4 : 2
        )
    }

    private var haloColor: Color {
        if isRecentlyActive {
            return thinkspace.accentColor.opacity(0.18)
        }
        return .black.opacity(isHovered ? 0.08 : 0.05)
    }

    // MARK: Meta

    private var meta: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(thinkspace.name)
                .font(isRoot ? DS.headline.weight(.semibold) : DS.headline)
                .foregroundStyle(DS.text)
                .lineLimit(1)

            HStack(spacing: 4) {
                Text("\(thinkspace.blockCount)")
                    .monospacedDigit()
                Text("blocks ·")
                Text(thinkspace.lastOpened, format: .relative(presentation: .named))
            }
            .font(DS.caption)
            .foregroundStyle(DS.textMuted)
        }
        .padding(.horizontal, 2)
    }
}
