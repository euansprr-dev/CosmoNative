// CosmoOS/UI/SwipeFile/Creators/SwipeCreatorsPage.swift
// Explore ▸ Creators: every creator in the library in one directory — the
// ones you pulled a catalog for on top, the ones that exist only through
// saved posts beneath — with the creator page pushed in place. One model
// (`CreatorDirectoryModel`) owns the truth; this page owns navigation.
// Rebuilt from the ground up, September 2026.

import SwiftUI
import AppKit

struct SwipeCreatorsPage: View {
    @Bindable var model: CreatorDirectoryModel
    @Bindable var discover: SwipeDiscoverModel
    /// A creator another surface asked for (the Study chip, ⌘K).
    @Binding var openRequest: String?

    @State private var selectedID: String?
    @State private var contextPillVisible = false
    @State private var scrollPosition = ScrollPosition()
    @State private var addText = ""
    @State private var isAdding = false
    @FocusState private var searchFocused: Bool
    @FocusState private var addFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            SwipePageBackground()
            if let id = selectedID, let creator = model.summary(id: id) {
                SwipeCreatorPage(creator: creator, model: model, discover: discover, onBack: back)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                directory.transition(.opacity)
            }
        }
        .coordinateSpace(name: "swipePage")
        .task { await model.start() }
        .onChange(of: openRequest, initial: true) { _, id in consumeOpenRequest(id) }
        .onChange(of: model.hasLoaded) { _, _ in consumeOpenRequest(openRequest) }
        .overlay(alignment: .bottom) { SwipeSaveToast(message: $model.toast) }
        .animation(reduceMotion ? nil : ProMotionSprings.focusTransition, value: selectedID)
    }

    private func back() {
        selectedID = nil
    }

    private func consumeOpenRequest(_ id: String?) {
        guard let id, model.summary(id: id) != nil else { return }
        selectedID = id
        openRequest = nil
    }

    // MARK: - Directory

    private var directory: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space24) {
                masthead
                controls
                if let error = model.errorMessage {
                    SwipeDiscoverNotice(text: error, isError: true)
                }
                if model.isLoading && model.summaries.isEmpty {
                    SwipeSkeletonGrid(targetColumnWidth: 300)
                } else if model.summaries.isEmpty {
                    emptyState
                } else if model.filtered.isEmpty {
                    SwipeLibraryErrorState(message: "No creators match — try fewer words.", onRetry: { model.searchText = "" })
                } else {
                    sections
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 36)
            .padding(.bottom, 72)
            .swipeContentMeasure()
        }
        .scrollPosition($scrollPosition)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y > 88 }) { _, show in
            if show != contextPillVisible { contextPillVisible = show }
        }
        .overlay(alignment: .top) {
            SwipeContextPill(title: "Creators", detail: "\(model.filtered.count) profiles", visible: contextPillVisible) {
                withAnimation(ProMotionSprings.gentle) { scrollPosition.scrollTo(edge: .top) }
            }
            .padding(.top, DS.space12)
        }
    }

    private var masthead: some View {
        HStack(alignment: .top, spacing: DS.space12) {
            SwipeMasthead(title: "Creators")
            Spacer(minLength: DS.space16)
            HStack(spacing: DS.space8) {
                SwipeLibrarySearchField(text: $model.searchText, isFocused: $searchFocused, placeholder: "Find a creator")
                sortMenu
            }
        }
    }

    /// Scope pills lead; the add field trails — "whose posts" then "add more".
    private var controls: some View {
        HStack(alignment: .center, spacing: DS.space12) {
            HStack(spacing: DS.space6) {
                ForEach(CreatorDirectoryScope.allCases) { scope in
                    CreatorScopePill(title: scope.title, count: count(for: scope), isSelected: model.scope == scope) {
                        withAnimation(ProMotionSprings.snappy) { model.scope = scope }
                    }
                }
            }
            Spacer(minLength: DS.space12)
            addField
        }
    }

    private func count(for scope: CreatorDirectoryScope) -> Int {
        switch scope {
        case .all: return model.summaries.count
        case .catalogued: return model.summaries.count(where: \.hasCatalog)
        case .fromSwipes: return model.summaries.count { !$0.hasCatalog }
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(CreatorDirectorySort.allCases) { sort in
                Button {
                    withAnimation(ProMotionSprings.snappy) { model.sort = sort }
                } label: {
                    if model.sort == sort { Label(sort.label, systemImage: "checkmark") } else { Text(sort.label) }
                }
            }
        } label: {
            HStack(spacing: DS.space6) {
                Image(systemName: "arrow.up.arrow.down").font(DS.caption.weight(.semibold))
                Text(model.sort.label).font(DS.subheadline.weight(.medium))
            }
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, DS.space12)
            .frame(height: 32)
            .background(Capsule().fill(DS.glassInputFill))
            .overlay(Capsule().strokeBorder(DS.glassBorder, lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort creators")
        .accessibilityLabel("Sort: \(model.sort.label)")
    }

    /// Paste a profile URL or a handle. The creator joins the directory at
    /// once; when Apify is configured the page opens with a catalog pull
    /// ready to confirm — the same ~150-post pull a manual add always did.
    private var addField: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: "person.badge.plus")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            TextField("Add a creator — profile URL or @handle", text: $addText)
                .textFieldStyle(.plain)
                .font(DS.subheadline)
                .foregroundStyle(DS.text)
                .focused($addFocused)
                .onSubmit(addCreator)
            Button(action: addCreator) {
                Text(isAdding ? "Adding…" : "Add")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.textOnAccent)
                    .padding(.horizontal, DS.space10)
                    .frame(height: 24)
                    .background(DS.accent, in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(isAdding || addText.trimmingCharacters(in: .whitespaces).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Add this creator and pull their latest posts")
        }
        .padding(.leading, DS.space12)
        .padding(.trailing, DS.space4)
        .frame(width: 360, height: 32)
        .dsGlassInput(isFocused: addFocused, cornerRadius: 16)
        .accessibilityLabel("Add a creator")
    }

    private func addCreator() {
        let input = addText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !isAdding else { return }
        isAdding = true
        Task { @MainActor in
            defer { isAdding = false }
            guard let created = await model.addCreator(input: input) else { return }
            addText = ""
            selectedID = created.id
            if model.apifyConfigured, !created.hasCatalog {
                await model.preparePull(for: created.id)
            }
        }
    }

    @ViewBuilder
    private var sections: some View {
        if model.scope == .all {
            if !model.catalogued.isEmpty {
                section(title: "Pulled catalogs", detail: "\(model.catalogued.count)", creators: model.catalogued)
            }
            if !model.fromSwipes.isEmpty {
                section(title: "From your swipes", detail: "\(model.fromSwipes.count)", creators: model.fromSwipes)
            }
        } else {
            grid(model.filtered)
        }
    }

    private func section(title: String, detail: String, creators: [CreatorProfileSummary]) -> some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            CosmoShelfHeader(title: title, detail: detail)
            grid(creators)
        }
    }

    private func grid(_ creators: [CreatorProfileSummary]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 440), spacing: 16)], spacing: 16) {
            ForEach(creators) { creator in
                CreatorDirectoryCard(
                    creator: creator,
                    onOpen: { selectedID = creator.id },
                    onPull: {
                        selectedID = creator.id
                        Task { await model.preparePull(for: creator.id) }
                    },
                    onDelete: { Task { await model.delete(creator.id) } }
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Image(systemName: "person.2").font(DS.pageTitle).foregroundStyle(DS.textMuted)
            Text("Your creators gather here").font(DS.title2).foregroundStyle(DS.text)
            Text("Save a post and its creator appears with every post you keep from them. Paste a profile URL above to pull a creator's catalog and find their outliers.")
                .font(DS.body).foregroundStyle(DS.textSecondary).frame(maxWidth: 520, alignment: .leading)
        }
        .padding(.vertical, DS.space32)
    }
}

// MARK: - Scope pill

private struct CreatorScopePill: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space6) {
                Text(title).font(DS.subheadline.weight(.medium))
                Text("\(count)")
                    .font(DS.caption2.weight(.medium).monospacedDigit())
                    .foregroundStyle(isSelected ? DS.accent : DS.textMuted)
                    .contentTransition(.numericText())
            }
            .foregroundStyle(isSelected || hovered ? DS.text : DS.textSecondary)
            .padding(.horizontal, DS.space12)
            .frame(height: 30)
            .background(Capsule().fill(isSelected ? DS.accentSoft : (hovered ? DS.glassInputFill : Color.clear)))
            .overlay(Capsule().strokeBorder(isSelected ? DS.accent.opacity(0.42) : DS.glassBorder, lineWidth: isSelected ? 1 : 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(ProMotionSprings.hover, value: hovered)
        .help(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Card

/// A creator as an object: avatar, name, the platform's real mark, a strip of
/// their strongest saved posts, and one honest meta line.
private struct CreatorDirectoryCard: View {
    let creator: CreatorProfileSummary
    let onOpen: () -> Void
    let onPull: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: DS.space12) {
                identityRow
                strip
                Text(meta)
                    .font(DS.caption.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .swipeCardSurface(isHovered: isHovered)
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Open", systemImage: "arrow.up.right.square", action: onOpen)
            Button("Pull latest posts…", systemImage: "arrow.down.circle", action: onPull)
            if let url = creator.profileURL {
                Button("Open profile in browser", systemImage: "safari") { NSWorkspace.shared.open(url) }
            }
            Divider()
            Button("Remove creator", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .help("Open \(creator.name)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(creator.name), \(creator.handle), \(creator.savedCount) saved")
        .accessibilityAddTraits(.isButton)
    }

    private var identityRow: some View {
        HStack(spacing: DS.space10) {
            SwipeCreatorAvatar(url: creator.avatarURL, name: creator.name, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(creator.name).font(DS.headline).foregroundStyle(DS.text).lineLimit(1)
                Text(handleLine).font(DS.caption).foregroundStyle(DS.textMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let platform = creator.platform {
                PlatformBrandMark(platform: platform.rawValue, size: 13)
            }
        }
    }

    private var handleLine: String {
        var parts = [creator.handle]
        if let followers = creator.followerCount, followers > 0 { parts.append("\(SwipeFormatting.count(followers)) followers") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var strip: some View {
        if creator.thumbnailURLs.isEmpty {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DS.glassSectionFill)
                .frame(height: 56)
                .overlay {
                    Text(creator.hasCatalog ? "Catalog pulled — nothing saved yet" : "No posts saved yet")
                        .font(DS.caption).foregroundStyle(DS.textMuted)
                }
        } else {
            HStack(spacing: 6) {
                ForEach(Array(creator.thumbnailURLs.prefix(3).enumerated()), id: \.offset) { _, url in
                    CachedAsyncImage(url: url, stableKey: "creator-strip-\(url.absoluteString)") { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        case .empty, .failure: Rectangle().fill(DS.glassSectionFill)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                }
            }
        }
    }

    private var meta: String {
        var parts = ["\(creator.savedCount) saved"]
        if let score = creator.averageHookScore { parts.append(String(format: "%.1f hook", score)) }
        if creator.hasCatalog { parts.append("catalog \(creator.catalogCount)") }
        if let latest = creator.latestSavedAt { parts.append(latest.cosmoCompactAge) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Avatar

struct SwipeCreatorAvatar: View {
    let url: URL?
    let name: String
    let size: CGFloat

    var body: some View {
        // Key on the URL string itself — Swift's hashValue is seeded per
        // launch, so a hash key missed the cache on every run.
        CachedAsyncImage(url: url, stableKey: url.map { "avatar-\($0.absoluteString)" }) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .empty, .failure:
                Circle()
                    .fill(DS.glassSectionFill)
                    .overlay {
                        Text(String(name.prefix(1)).uppercased())
                            .font(size > 56 ? DS.title2 : DS.subheadline.weight(.semibold))
                            .foregroundStyle(DS.textMuted)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(DS.glassBorder, lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}
