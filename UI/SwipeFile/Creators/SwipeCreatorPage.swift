// CosmoOS/UI/SwipeFile/Creators/SwipeCreatorPage.swift
// The creator page, rebuilt: a profile masthead with the real avatar and the
// platform's mark, the numbers that matter, the creator's signature (what
// they keep doing), a Best Hooks shelf, then lanes — Saved (every post you
// kept from them), Catalog (the pulled posts, cumulative), Outliers (the
// catalog's 2×+ posts) and Discover (the cloud graph). Pull the latest
// posts from the masthead: one confirm, a progress strip, the catalog grows.
// September 2026

import SwiftUI
import AppKit

enum CreatorLane: String, CaseIterable, Identifiable, Hashable {
    case saved, catalog, outliers, discover
    var id: String { rawValue }
    var title: String {
        switch self {
        case .saved: return "Saved"
        case .catalog: return "Catalog"
        case .outliers: return "Outliers"
        case .discover: return "Discover"
        }
    }
}

enum CreatorSavedSort: String, CaseIterable, Identifiable {
    case hookScore, recent, likes, views
    var id: String { rawValue }
    var label: String {
        switch self {
        case .hookScore: return "Hook score"
        case .recent: return "Recently saved"
        case .likes: return "Most liked"
        case .views: return "Most viewed"
        }
    }
}

struct SwipeCreatorPage: View {
    let creator: CreatorProfileSummary
    @Bindable var model: CreatorDirectoryModel
    @Bindable var discover: SwipeDiscoverModel
    let onBack: () -> Void

    @State private var lane: CreatorLane = .saved
    @State private var laneSearch = ""
    @State private var formatFilter: ContentFormat?
    @State private var savedSort: CreatorSavedSort = .hookScore
    @State private var showsPullConfirm = false
    @State private var showsPullHelp = false
    @State private var pullCount = 150
    @State private var showsEdit = false
    @State private var confirmDelete = false
    @State private var scrollPosition = ScrollPosition()
    @State private var contextPillVisible = false
    @State private var shelfFrameStore = SwipeFrameStore()
    @State private var laneMemo = CreatorLaneMemo()
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var swipes: [Atom] { model.swipes(for: creator.id) }
    private var catalog: CreatorCatalog { model.catalog(for: creator.id) }
    private var discoverPosts: [SocialPostSnapshot] {
        guard let key = creator.handleKey,
              let record = discover.creators.first(where: { CreatorIdentity.key($0.handle) == key }) else { return [] }
        return discover.posts(for: record)
    }
    private var isPullingHere: Bool { model.pullingCreatorID == creator.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space24) {
                breadcrumb
                masthead
                if isPullingHere { pullStrip }
                signature
                bestHooks
                lanesHeader
                laneContent
            }
            .padding(.horizontal, 48)
            .padding(.top, 28)
            .padding(.bottom, 96)
            .swipeContentMeasure()
        }
        .scrollPosition($scrollPosition)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y > 120 }) { _, show in
            if show != contextPillVisible { contextPillVisible = show }
        }
        .overlay(alignment: .top) {
            SwipeContextPill(title: creator.name, detail: "\(creator.savedCount) saved", visible: contextPillVisible) {
                withAnimation(ProMotionSprings.gentle) { scrollPosition.scrollTo(edge: .top) }
            }
            .padding(.top, DS.space12)
        }
        .task(id: creator.id) {
            await model.loadCatalog(for: creator.id)
            if swipes.isEmpty, !catalog.posts.isEmpty { lane = .catalog }
        }
        .onChange(of: model.pullEstimate) { _, estimate in
            showsPullConfirm = estimate != nil && isPullingHere
        }
        .onChange(of: availableLanes) { _, lanes in if !lanes.contains(lane) { lane = .saved } }
        .onExitCommand(perform: onBack)
        .sheet(isPresented: $showsEdit) { CreatorEditSheet(creator: creator, model: model) }
        .alert("Remove \(creator.name)?", isPresented: $confirmDelete) {
            Button("Remove", role: .destructive) { Task { await model.delete(creator.id); onBack() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved posts stay in your library. Only the creator record and its pulled catalog go.")
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumb: some View {
        Button(action: onBack) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left").font(DS.caption.weight(.semibold))
                Text("Creators").font(DS.subheadline.weight(.medium))
            }
            .foregroundStyle(DS.textSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("[", modifiers: .command)
        .help("Back to creators (Esc)")
    }

    // MARK: - Masthead

    private var masthead: some View {
        HStack(alignment: .top, spacing: DS.space20) {
            SwipeCreatorAvatar(url: creator.avatarURL, name: creator.name, size: 84)
            VStack(alignment: .leading, spacing: DS.space6) {
                Text(creator.name).font(DS.pageTitle).foregroundStyle(DS.text).lineLimit(2)
                HStack(spacing: DS.space6) {
                    if let platform = creator.platform {
                        PlatformBrandMark(platform: platform.rawValue, size: 12)
                    }
                    Text(metaLine).font(DS.subheadline).foregroundStyle(DS.textMuted).monospacedDigit()
                }
                if let bio = creator.bio, !bio.isEmpty {
                    Text(bio).font(DS.subheadline).foregroundStyle(DS.textSecondary)
                        .lineLimit(2).frame(maxWidth: 560, alignment: .leading)
                }
                chips
            }
            Spacer(minLength: DS.space16)
            VStack(alignment: .trailing, spacing: DS.space12) {
                actions
                stats
            }
        }
    }

    private var metaLine: String {
        var parts = [creator.handle]
        if let platform = creator.platform { parts.append(platform.displayName) }
        if let followers = creator.followerCount, followers > 0 { parts.append("\(SwipeFormatting.count(followers)) followers") }
        return parts.joined(separator: " · ")
    }

    private var chips: some View {
        HStack(spacing: DS.space6) {
            if let url = creator.profileURL {
                CreatorChip(title: "Profile", icon: "arrow.up.right") { NSWorkspace.shared.open(url) }
                    .help("Open the profile in your browser")
            }
            CreatorChip(title: creator.isTracked ? "Tracked" : "Track", icon: creator.isTracked ? "eye.fill" : "eye",
                        tint: creator.isTracked ? DS.accent : nil) {
                Task { await model.update(creator.id, name: nil, handle: nil, niche: nil, notes: nil, tracked: !creator.isTracked) }
            }
            .help(creator.isTracked ? "Tracked — new posts from this creator matter to you" : "Track this creator")
            if let niche = creator.niche, !niche.isEmpty {
                CreatorChip(title: niche, icon: nil) { showsEdit = true }
            }
        }
        .padding(.top, DS.space4)
    }

    private var actions: some View {
        HStack(spacing: DS.space8) {
            pullButton
            Menu {
                Button("Edit creator…", systemImage: "pencil") { showsEdit = true }
                if let url = creator.profileURL {
                    Button("Open profile in browser", systemImage: "safari") { NSWorkspace.shared.open(url) }
                }
                Button("Copy handle", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(creator.handle, forType: .string)
                }
                Divider()
                Button("Remove creator", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis").font(DS.callout.weight(.semibold))
                    .foregroundStyle(DS.textSecondary).frame(width: 34, height: 34)
                    .background(Circle().fill(DS.glassInputFill))
                    .overlay(Circle().strokeBorder(DS.glassBorder, lineWidth: 0.5))
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Creator actions").accessibilityLabel("Creator actions")
        }
    }

    /// The masthead's one hero: pull the creator's latest posts into the
    /// catalog. Confirm shows the honest cost; the strip shows progress.
    private var pullButton: some View {
        Button {
            if model.apifyConfigured {
                Task { await model.preparePull(for: creator.id) }
            } else {
                showsPullHelp = true
            }
        } label: {
            HStack(spacing: DS.space6) {
                Image(systemName: creator.hasCatalog ? "arrow.clockwise" : "arrow.down.circle")
                    .font(DS.callout.weight(.semibold))
                Text(creator.hasCatalog ? "Pull latest posts" : "Pull posts")
            }
        }
        .buttonStyle(CreatorPrimaryButtonStyle())
        .disabled(model.isPulling)
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .help(creator.hasCatalog ? "Fetch the newest posts into the catalog (⇧⌘R)" : "Pull this creator's posts to find their outliers (⇧⌘R)")
        .popover(isPresented: $showsPullConfirm, arrowEdge: .bottom) { pullConfirm }
        .popover(isPresented: $showsPullHelp, arrowEdge: .bottom) { pullHelp }
    }

    private var pullConfirm: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Text("Pull \(creator.handle)").font(DS.headline).foregroundStyle(DS.text)
            CosmoSegmentedSwitcher(options: [50, 150, 300], label: { "\($0)" },
                                   help: { "Pull the latest \($0) posts" }, selection: $pullCount)
            if let estimate = model.pullEstimate {
                let provider = ApifyInstagramProvider.shared
                let scaled = provider.estimateCost(postCount: pullCount)
                Text("About \(String(format: "$%.2f", scaled.estimatedCostUSD)) · ~\(scaled.estimatedDurationSeconds)s")
                    .font(DS.caption).foregroundStyle(DS.textMuted).monospacedDigit()
                if let warning = estimate.warning ?? scaled.warning {
                    Text(warning).font(DS.caption2).foregroundStyle(DS.orange)
                }
            }
            Text(creator.hasCatalog ? "New posts join the \(creator.catalogCount) already pulled." : "Posts land in the Catalog lane; nothing is saved until you choose.")
                .font(DS.caption2).foregroundStyle(DS.textMuted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel") { showsPullConfirm = false; model.cancelPull() }.buttonStyle(.plain).foregroundStyle(DS.textSecondary)
                Spacer()
                Button {
                    showsPullConfirm = false
                    Task { await model.confirmPull(count: pullCount) }
                } label: { Label("Pull \(pullCount)", systemImage: "arrow.down.circle") }
                    .buttonStyle(CreatorPrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(DS.space16)
        .frame(width: 320)
    }

    private var pullHelp: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            Text("Pulling needs an Apify key").font(DS.headline).foregroundStyle(DS.text)
            Text("Cosmo fetches a creator's posts and engagement through Apify. Add the key once in Settings and every creator can be pulled.")
                .font(DS.caption).foregroundStyle(DS.textSecondary).fixedSize(horizontal: false, vertical: true)
            Button("Open Settings", systemImage: "gear") {
                showsPullHelp = false
                NotificationCenter.default.post(name: .showSettings, object: nil)
            }
            .buttonStyle(CreatorPrimaryButtonStyle())
        }
        .padding(DS.space16)
        .frame(width: 300)
    }

    private var stats: some View {
        HStack(spacing: 0) {
            stat("\(creator.savedCount)", "saved")
            statDivider
            stat("\(creator.studiedCount)", "studied")
            statDivider
            stat(creator.averageHookScore.map { String(format: "%.1f", $0) } ?? "—", "hook")
            if creator.hasCatalog {
                statDivider
                stat("\(creator.catalogCount)", "catalog")
            }
            if let top = catalog.outliers.first?.derived.outlierMultiplier {
                statDivider
                stat("\(Int(top.rounded()))×", "top outlier")
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value).font(DS.title2.monospacedDigit()).foregroundStyle(DS.text).contentTransition(.numericText())
            Text(label.uppercased()).font(DS.smallCaps).tracking(DS.smallCapsTracking).foregroundStyle(DS.textMuted)
        }
        .padding(.horizontal, DS.space12)
        .accessibilityElement(children: .combine)
    }

    private var statDivider: some View {
        Rectangle().fill(DS.commandChromeSeparator).frame(width: 0.5, height: 28)
    }

    // MARK: - Pull strip

    @ViewBuilder
    private var pullStrip: some View {
        HStack(spacing: DS.space12) {
            if let error = model.pullError {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(DS.orange)
                Text(error).font(DS.caption).foregroundStyle(DS.textSecondary).lineLimit(2)
                Spacer(minLength: 0)
                Button("Dismiss") { model.cancelPull() }.buttonStyle(.plain).font(DS.caption).foregroundStyle(DS.textSecondary)
            } else if let progress = model.pullProgress {
                ProgressView(value: Double(progress.fetched), total: Double(max(progress.total, 1)))
                    .progressViewStyle(.linear).tint(DS.accent).frame(maxWidth: 240)
                Text("Pulling \(progress.fetched) of \(progress.total) posts…")
                    .font(DS.caption).foregroundStyle(DS.textSecondary).monospacedDigit().contentTransition(.numericText())
                Spacer(minLength: 0)
            } else if model.pullEstimate != nil {
                Image(systemName: "checkmark.circle").foregroundStyle(DS.accent)
                Text("Profile found — confirm the pull above.").font(DS.caption).foregroundStyle(DS.textSecondary)
                Spacer(minLength: 0)
            } else {
                ProgressView().controlSize(.small)
                Text("Looking up \(creator.handle)…").font(DS.caption).foregroundStyle(DS.textSecondary)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space10)
        .background(DS.glassSectionFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(ProMotionSprings.gentle, value: model.pullProgress?.fetched)
    }

    // MARK: - Signature

    @ViewBuilder
    private var signature: some View {
        if !creator.topNarratives.isEmpty || !creator.topFrameworks.isEmpty || !creator.topFormats.isEmpty {
            VStack(alignment: .leading, spacing: DS.space10) {
                CosmoSectionHeader(label: "SIGNATURE")
                HStack(alignment: .top, spacing: DS.space24) {
                    tallyColumn("Narratives", creator.topNarratives)
                    tallyColumn("Frameworks", creator.topFrameworks)
                    tallyColumn("Formats", creator.topFormats)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private func tallyColumn(_ title: String, _ tallies: [CreatorTally]) -> some View {
        if !tallies.isEmpty {
            let peak = max(1, tallies.first?.count ?? 1)
            VStack(alignment: .leading, spacing: DS.space6) {
                Text(title).font(DS.caption.weight(.semibold)).foregroundStyle(DS.textSecondary)
                ForEach(tallies) { tally in
                    HStack(spacing: DS.space8) {
                        Text(tally.label).font(DS.subheadline).foregroundStyle(DS.text).lineLimit(1)
                        Spacer(minLength: DS.space8)
                        Text("\(tally.count)").font(DS.caption.monospacedDigit()).foregroundStyle(DS.textMuted)
                    }
                    .frame(width: 220)
                    .background(alignment: .bottomLeading) {
                        Capsule().fill(DS.accent.opacity(0.18))
                            .frame(width: 220 * CGFloat(tally.count) / CGFloat(peak), height: 2)
                            .offset(y: 4)
                    }
                }
            }
        }
    }

    // MARK: - Best hooks

    @ViewBuilder
    private var bestHooks: some View {
        let best = bestHookModels
        if best.count >= 4 {
            SwipeShelf(
                label: "BEST HOOKS", count: best.count, onSeeAll: nil,
                models: best, hiddenItemID: nil, frameStore: shelfFrameStore
            ) { cardModel in
                SwipeCardActions(onOpen: { openSaved(cardModel.id) }, onStudy: { openSaved(cardModel.id) }, onBookmark: nil)
            }
        }
    }

    private var bestHookModels: [SwipeCardModel] {
        let byUUID = Dictionary(uniqueKeysWithValues: swipes.map { ($0.uuid, $0) })
        return creator.bestSwipeUUIDs.compactMap { byUUID[$0] }
            .compactMap { $0.toSwipeGalleryItem() }
            .map { SwipeCardModel(item: $0).poster() }
    }

    // MARK: - Lanes

    private var availableLanes: [CreatorLane] {
        var lanes: [CreatorLane] = [.saved]
        if !catalog.posts.isEmpty { lanes.append(.catalog) }
        if !catalog.outliers.isEmpty { lanes.append(.outliers) }
        if !discoverPosts.isEmpty { lanes.append(.discover) }
        return lanes
    }

    private func laneCount(_ lane: CreatorLane) -> Int {
        switch lane {
        case .saved: return swipes.count
        case .catalog: return catalog.posts.count
        case .outliers: return catalog.outliers.count
        case .discover: return discoverPosts.count
        }
    }

    private var lanesHeader: some View {
        HStack(spacing: DS.space12) {
            CosmoSegmentedSwitcher(
                options: availableLanes,
                label: { "\($0.title) \(laneCount($0))" },
                help: { $0.title },
                selection: $lane
            )
            .fixedSize()
            Spacer(minLength: DS.space8)
            if lane != .discover {
                SwipeLibrarySearchField(text: $laneSearch, isFocused: $searchFocused, placeholder: "Find in \(lane.title.lowercased())")
            }
            if lane == .saved {
                savedSortMenu
                formatMenu
            }
            if lane == .catalog || lane == .outliers {
                catalogVerbs
            }
        }
    }

    private var savedSortMenu: some View {
        Menu {
            ForEach(CreatorSavedSort.allCases) { sort in
                Button { savedSort = sort } label: {
                    if savedSort == sort { Label(sort.label, systemImage: "checkmark") } else { Text(sort.label) }
                }
            }
        } label: { laneChip(savedSort.label, icon: "arrow.up.arrow.down", active: savedSort != .hookScore) }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Sort saved posts")
    }

    private var formatMenu: some View {
        Menu {
            Button("Any format") { formatFilter = nil }
            Divider()
            ForEach(ContentFormat.allCases, id: \.self) { format in
                Button { formatFilter = formatFilter == format ? nil : format } label: {
                    if formatFilter == format { Label(format.displayName, systemImage: "checkmark") } else { Text(format.displayName) }
                }
            }
        } label: { laneChip(formatFilter?.displayName ?? "Format", icon: nil, active: formatFilter != nil) }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Filter by format")
    }

    private var catalogVerbs: some View {
        Menu {
            Button("Save top 10 by likes", systemImage: "square.and.arrow.down") { saveTop(10, byOutlier: false) }
            Button("Save top 25 by likes", systemImage: "square.and.arrow.down") { saveTop(25, byOutlier: false) }
            Button("Save every outlier (2×+)", systemImage: "flame") { saveOutliers() }
            Button("Save all unsaved reels", systemImage: "play.rectangle") { saveReels() }
        } label: { laneChip("Save…", icon: "square.and.arrow.down", active: false) }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Save a slice of the catalog into your swipes")
    }

    private func laneChip(_ title: String, icon: String?, active: Bool) -> some View {
        HStack(spacing: DS.space4) {
            if let icon { Image(systemName: icon).font(DS.caption.weight(.semibold)) }
            Text(title).font(DS.callout.weight(.medium))
            Image(systemName: "chevron.down").font(DS.caption2.weight(.semibold))
        }
        .foregroundStyle(active ? DS.accent : DS.textSecondary)
        .padding(.horizontal, DS.space10)
        .frame(height: 32)
        .background(active ? DS.accentSoft : DS.glassInputFill, in: .capsule)
        .overlay(Capsule().strokeBorder(active ? DS.accent.opacity(0.42) : DS.glassBorder, lineWidth: 0.5))
        .contentShape(.capsule)
    }

    @ViewBuilder
    private var laneContent: some View {
        switch lane {
        case .saved:
            CreatorSavedLane(
                swipes: filteredSwipes,
                onOpen: { openSaved($0) },
                onUnlink: { uuid in Task { await model.unlink(swipeUUID: uuid, from: creator.id) } },
                onDelete: { uuid in Task { await model.deleteSwipe(uuid) } }
            )
        case .catalog:
            CreatorCatalogLane(posts: filteredCatalog(catalog.posts), creatorID: creator.id, model: model)
        case .outliers:
            CreatorCatalogLane(posts: filteredCatalog(catalog.outliers), creatorID: creator.id, model: model)
        case .discover:
            SwipeDiscoverPostGrid(posts: discoverPosts, model: discover)
        }
    }

    private var searchTokens: [String] {
        laneSearch.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private var filteredSwipes: [Atom] {
        laneMemo.swipes(swipes, tokens: searchTokens, format: formatFilter, sort: savedSort)
    }

    private func filteredCatalog(_ posts: [SocialPostSnapshot]) -> [SocialPostSnapshot] {
        let tokens = searchTokens
        guard !tokens.isEmpty else { return posts }
        return posts.filter { post in
            let haystack = [post.title ?? "", post.body ?? ""].joined(separator: " ").lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    // MARK: - Verbs

    private func openSaved(_ uuid: String) {
        guard let atom = swipes.first(where: { $0.uuid == uuid }) else { return }
        model.openStudy(atom, within: filteredSwipes)
    }

    private func saveTop(_ n: Int, byOutlier: Bool) {
        let ranked = byOutlier ? catalog.outliers : catalog.posts.sorted { ($0.metrics.likes ?? 0) > ($1.metrics.likes ?? 0) }
        let picks = ranked.filter { !model.isSaved($0, in: creator.id) }.prefix(n)
            .compactMap { catalog.importedByID[$0.id] }
        Task { _ = await model.save(posts: Array(picks), for: creator.id) }
    }

    private func saveOutliers() {
        let picks = catalog.outliers.filter { !model.isSaved($0, in: creator.id) }.compactMap { catalog.importedByID[$0.id] }
        Task { _ = await model.save(posts: picks, for: creator.id) }
    }

    private func saveReels() {
        let picks = catalog.posts.filter { $0.format == .shortVideo && !model.isSaved($0, in: creator.id) }
            .compactMap { catalog.importedByID[$0.id] }
        Task { _ = await model.save(posts: picks, for: creator.id) }
    }
}

// MARK: - Saved-lane memo (filter + sort once per input, never per body)

final class CreatorLaneMemo {
    private var key = ""
    private var result: [Atom] = []
    private var index: [String: SavedIndex] = [:]

    struct SavedIndex {
        let text: String
        let format: ContentFormat?
        let hookScore: Double
        let likes: Int
        let views: Int
        let createdAt: String
    }

    func swipes(_ swipes: [Atom], tokens: [String], format: ContentFormat?, sort: CreatorSavedSort) -> [Atom] {
        let rowKey: String = swipes.map { "\($0.uuid)|\($0.localVersion)" }.joined()
        let nextKey: String = [rowKey, tokens.joined(separator: " "), format?.rawValue ?? "", sort.rawValue].joined(separator: "|")
        if nextKey == key { return result }
        for swipe in swipes where index[swipe.uuid + String(swipe.localVersion)] == nil {
            let analysis = swipe.swipeAnalysis
            index[swipe.uuid + String(swipe.localVersion)] = SavedIndex(
                text: [swipe.title ?? "", analysis?.hookText ?? "", swipe.richContent?.author ?? ""].joined(separator: " ").lowercased(),
                format: analysis?.swipeContentFormat,
                hookScore: analysis?.hookScore ?? 0,
                likes: analysis?.likesCount ?? 0,
                views: analysis?.viewsCount ?? 0,
                createdAt: swipe.createdAt
            )
        }
        var items = swipes
        if !tokens.isEmpty {
            items = items.filter { swipe in
                let text = index[swipe.uuid + String(swipe.localVersion)]?.text ?? ""
                return tokens.allSatisfy { text.contains($0) }
            }
        }
        if let format {
            items = items.filter { index[$0.uuid + String($0.localVersion)]?.format == format }
        }
        func entry(_ swipe: Atom) -> SavedIndex? { index[swipe.uuid + String(swipe.localVersion)] }
        switch sort {
        case .hookScore: items.sort { (entry($0)?.hookScore ?? 0) > (entry($1)?.hookScore ?? 0) }
        case .recent: items.sort { (entry($0)?.createdAt ?? "") > (entry($1)?.createdAt ?? "") }
        case .likes: items.sort { (entry($0)?.likes ?? 0) > (entry($1)?.likes ?? 0) }
        case .views: items.sort { (entry($0)?.views ?? 0) > (entry($1)?.views ?? 0) }
        }
        key = nextKey
        result = items
        return items
    }
}

// MARK: - Chips and buttons

private struct CreatorChip: View {
    let title: String
    let icon: String?
    var tint: Color? = nil
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space4) {
                if let icon { Image(systemName: icon).font(DS.caption2.weight(.semibold)) }
                Text(title).font(DS.caption.weight(.medium)).lineLimit(1)
            }
            .foregroundStyle(tint ?? (hovered ? DS.text : DS.textSecondary))
            .padding(.horizontal, DS.space10)
            .frame(height: 26)
            .background(Capsule().fill(tint.map { $0.opacity(0.12) } ?? DS.glassInputFill))
            .overlay(Capsule().strokeBorder(tint.map { $0.opacity(0.4) } ?? DS.glassBorder, lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(ProMotionSprings.hover, value: hovered)
    }
}

struct CreatorPrimaryButtonStyle: ButtonStyle {
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(DS.callout.weight(.semibold))
            .foregroundStyle(DS.textOnAccent)
            .padding(.horizontal, DS.space12)
            .frame(height: 34)
            .background(hovered ? DS.accentHover : DS.accent, in: .capsule)
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : ProMotionSprings.hover, value: hovered)
            .animation(reduceMotion ? nil : ProMotionSprings.press, value: configuration.isPressed)
            .contentShape(.capsule)
            .onHover { hovered = $0 }
    }
}

// MARK: - Edit sheet

struct CreatorEditSheet: View {
    let creator: CreatorProfileSummary
    let model: CreatorDirectoryModel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var handle: String
    @State private var niche: String
    @State private var notes: String
    @State private var tracked: Bool
    @State private var saving = false

    init(creator: CreatorProfileSummary, model: CreatorDirectoryModel) {
        self.creator = creator
        self.model = model
        _name = State(initialValue: creator.name)
        _handle = State(initialValue: creator.handle)
        _niche = State(initialValue: creator.niche ?? "")
        _notes = State(initialValue: creator.notes ?? "")
        _tracked = State(initialValue: creator.isTracked)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            HStack {
                Text("Edit creator").font(DS.headline).foregroundStyle(DS.text)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.plain).foregroundStyle(DS.textSecondary).keyboardShortcut(.cancelAction)
            }
            field("Name", text: $name)
            field("Handle", text: $handle)
            field("Niche", text: $niche)
            VStack(alignment: .leading, spacing: DS.space6) {
                Text("Notes").font(DS.smallCaps).tracking(DS.smallCapsTracking).foregroundStyle(DS.textMuted)
                TextEditor(text: $notes)
                    .font(DS.callout).foregroundStyle(DS.text).scrollContentBackground(.hidden)
                    .frame(height: 96).padding(DS.space8)
                    .dsGlassInput(isFocused: false, cornerRadius: 10)
            }
            Toggle(isOn: $tracked) { Text("Tracked").font(DS.callout).foregroundStyle(DS.text) }
                .toggleStyle(.switch).tint(DS.accent).controlSize(.small)
            HStack {
                Spacer()
                Button(saving ? "Saving…" : "Save") {
                    saving = true
                    Task {
                        await model.update(creator.id, name: name, handle: handle, niche: niche, notes: notes, tracked: tracked)
                        dismiss()
                    }
                }
                .buttonStyle(CreatorPrimaryButtonStyle()).disabled(saving).keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.space20)
        .frame(width: 400)
        .background(DS.bg)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text(label).font(DS.smallCaps).tracking(DS.smallCapsTracking).foregroundStyle(DS.textMuted)
            TextField(label, text: text)
                .textFieldStyle(.plain).font(DS.callout).foregroundStyle(DS.text)
                .padding(.horizontal, DS.space12).frame(height: 32)
                .dsGlassInput(isFocused: false, cornerRadius: 16)
        }
    }
}
