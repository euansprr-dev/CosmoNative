// CosmoOS/UI/SwipeFile/Creators/SwipeCreatorLanes.swift
// The creator page's lanes. Saved = the library's own cards over every post
// kept from this creator (open = Study, prev/next walk the lane). Catalog =
// the pulled posts as Discover cards with a Saved tick, quick look, and a
// save that attributes the creator. Both grids are windowed waterfalls.
// September 2026

import SwiftUI

// MARK: - Saved lane

struct CreatorSavedLane: View {
    let swipes: [Atom]
    let onOpen: (String) -> Void
    let onUnlink: (String) -> Void
    let onDelete: (String) -> Void

    @State private var memo = SavedModelMemo()
    @State private var revealDate = Date()

    var body: some View {
        let models = memo.models(for: swipes)
        if models.isEmpty {
            CreatorLaneEmpty(
                title: "Nothing saved from this creator yet",
                line: "Save a post from the catalog, or capture one — it lands here and on the board."
            )
        } else {
            SwipeWaterfallGrid(
                items: models,
                targetColumnWidth: 248,
                spacing: 14,
                maxColumns: 4,
                itemHeight: { model, width in model.height(forWidth: width) },
                onPrefetch: { SwipeThumbnailPrewarmer.shared.warmAhead(models: $0) },
                cell: { model, width, index in
                    CreatorSavedCell(model: model, width: width, index: index, revealDate: revealDate,
                                     onOpen: { onOpen(model.id) }, onUnlink: { onUnlink(model.id) }, onDelete: { onDelete(model.id) })
                }
            )
            .onChange(of: swipes.map(\.uuid)) { revealDate = Date() }
        }
    }

    final class SavedModelMemo {
        private var key: [String] = []
        private var models: [SwipeCardModel] = []
        func models(for swipes: [Atom]) -> [SwipeCardModel] {
            let next = swipes.map { $0.uuid + String($0.localVersion) }
            if next != key {
                key = next
                models = swipes.compactMap { $0.toSwipeGalleryItem() }.map(SwipeCardModel.init(item:))
            }
            return models
        }
    }
}

private struct CreatorSavedCell: View {
    let model: SwipeCardModel
    let width: CGFloat
    let index: Int
    let revealDate: Date
    let onOpen: () -> Void
    let onUnlink: () -> Void
    let onDelete: () -> Void

    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SwipeCard(model: model, width: width, actions: SwipeCardActions(onOpen: onOpen, onStudy: onOpen, onBookmark: nil))
            .contextMenu {
                Button("Open in Study", systemImage: "arrow.up.left.and.arrow.down.right", action: onOpen)
                Button("Add to Canvas", systemImage: "plus.rectangle.on.rectangle") {
                    NotificationCenter.default.post(name: Notification.Name("addSwipeToCanvas"), object: nil, userInfo: ["atomUUID": model.id])
                }
                Divider()
                Button("Unlink from creator", systemImage: "person.crop.circle.badge.minus", action: onUnlink)
                Button("Delete swipe", systemImage: "trash", role: .destructive, action: onDelete)
            }
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared ? 1 : 0.96)
            .onAppear(perform: animateEntrance)
    }

    private func animateEntrance() {
        guard !hasAppeared else { return }
        let inWindow = Date().timeIntervalSince(revealDate) < 0.8
        guard inWindow, index < 12, !reduceMotion else { hasAppeared = true; return }
        withAnimation(ProMotionSprings.cascade(index: min(index, 8))) { hasAppeared = true }
    }
}

// MARK: - Catalog lane

struct CreatorCatalogLane: View {
    let posts: [SocialPostSnapshot]
    let creatorID: String
    @Bindable var model: CreatorDirectoryModel

    @State private var frameStore = SwipeFrameStore()
    @State private var quickLookID: String?
    @State private var quickLookExpanded = false
    @State private var quickLookSource: CGRect?
    @State private var memo = CatalogModelMemo()
    @State private var revealDate = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let models = memo.models(for: posts)
        ZStack(alignment: .topLeading) {
            if models.isEmpty {
                CreatorLaneEmpty(title: "Nothing here", line: "Pull the latest posts from the masthead to fill the catalog.")
            } else {
                SwipeWaterfallGrid(
                    items: models,
                    targetColumnWidth: 248,
                    spacing: 14,
                    maxColumns: 4,
                    itemHeight: { model, width in model.height(forWidth: width) },
                    onPrefetch: { SwipeThumbnailPrewarmer.shared.warmAhead(models: $0) },
                    cell: { cardModel, width, index in
                        CreatorCatalogCell(
                            model: cardModel, width: width, index: index,
                            isHidden: quickLookID == cardModel.id,
                            isSaved: isSaved(cardModel.id),
                            revealDate: revealDate,
                            frameStore: frameStore,
                            onOpen: { openQuickLook(postID: $0) },
                            onStudy: { study(postID: $0) },
                            onSave: { save(postID: $0) }
                        )
                    }
                )
            }
        }
        .onChange(of: posts.map(\.id)) { revealDate = Date() }
        .overlay {
            if let post = quickLookPost { quickLook(post) }
        }
    }

    final class CatalogModelMemo {
        private var posts: [SocialPostSnapshot] = []
        private var models: [SwipeCardModel] = []
        func models(for posts: [SocialPostSnapshot]) -> [SwipeCardModel] {
            if posts != self.posts {
                self.posts = posts
                models = posts.map(SwipeCardModel.init(post:))
            }
            return models
        }
    }

    private func isSaved(_ postID: String) -> Bool {
        guard let post = posts.first(where: { $0.id == postID }) else { return false }
        return model.isSaved(post, in: creatorID)
    }

    private var quickLookPost: SocialPostSnapshot? {
        guard let quickLookID else { return nil }
        return posts.first { $0.id == quickLookID }
    }

    private func quickLook(_ post: SocialPostSnapshot) -> some View {
        let index = posts.firstIndex { $0.id == post.id }
        return SwipeQuickLook(expanded: $quickLookExpanded, sourceFrame: quickLookSource,
                              heroModel: SwipeCardModel(post: post), onRequestClose: closeQuickLook) {
            SwipeQuickLookDiscoverContent(
                post: post,
                model: SwipeCardModel(post: post),
                hasPrevious: (index ?? 0) > 0,
                hasNext: index.map { $0 < posts.count - 1 } ?? false,
                onSave: { _ in save(postID: post.id) },
                onTranscript: { study(postID: post.id) },
                onPrevious: { step(-1) },
                onNext: { step(1) },
                onClose: closeQuickLook
            )
        }
    }

    private func openQuickLook(postID: String) {
        quickLookSource = frameStore.frames[postID]
        quickLookID = postID
    }

    private func closeQuickLook() {
        guard quickLookID != nil else { return }
        if let id = quickLookID, let frame = frameStore.frames[id] { quickLookSource = frame }
        guard !reduceMotion else { quickLookExpanded = false; quickLookID = nil; return }
        withAnimation(ProMotionSprings.modal, completionCriteria: .logicallyComplete) {
            quickLookExpanded = false
        } completion: {
            quickLookID = nil
        }
    }

    private func step(_ delta: Int) {
        guard let quickLookID, let index = posts.firstIndex(where: { $0.id == quickLookID }) else { return }
        let target = max(0, min(posts.count - 1, index + delta))
        self.quickLookID = posts[target].id
    }

    private func save(postID: String) {
        guard let post = posts.first(where: { $0.id == postID }), !model.isSaved(post, in: creatorID) else { return }
        Task { _ = await model.save(post: post, for: creatorID) }
    }

    /// Save, then straight into Study — transcription starts on arrival.
    private func study(postID: String) {
        guard let post = posts.first(where: { $0.id == postID }) else { return }
        quickLookExpanded = false
        quickLookID = nil
        Task { @MainActor in
            let saved: Atom?
            if model.isSaved(post, in: creatorID) {
                saved = model.swipes(for: creatorID).first { swipe in
                    model.catalog(for: creatorID).importedByID[post.id]?.shortcode == swipe.swipeAnalysis?.postShortcode
                }
            } else {
                saved = await model.save(post: post, for: creatorID)
            }
            guard let saved else { return }
            model.openStudy(saved, within: model.swipes(for: creatorID))
        }
    }
}

private struct CreatorCatalogCell: View {
    let model: SwipeCardModel
    let width: CGFloat
    let index: Int
    let isHidden: Bool
    let isSaved: Bool
    let revealDate: Date
    let frameStore: SwipeFrameStore
    let onOpen: (String) -> Void
    let onStudy: (String) -> Void
    let onSave: (String) -> Void

    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SwipeCard(
            model: model, width: width,
            actions: SwipeCardActions(onOpen: { onOpen(model.id) }, onStudy: { onStudy(model.id) },
                                      onBookmark: isSaved ? nil : { onSave(model.id) })
        )
        .overlay(alignment: .topTrailing) {
            if isSaved {
                Label("Saved", systemImage: "checkmark")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textOnAccent)
                    .padding(.horizontal, DS.space8).frame(height: 20)
                    .background(DS.accent, in: .capsule)
                    .padding(DS.space8)
                    .allowsHitTesting(false)
            }
        }
        .contextMenu {
            Button("Quick Look", systemImage: "eye") { onOpen(model.id) }
            Button("Save & Study", systemImage: "text.quote") { onStudy(model.id) }
            if !isSaved {
                Divider()
                Button("Save to your swipes", systemImage: "square.and.arrow.down") { onSave(model.id) }
            }
        }
        .opacity(isHidden ? 0 : (hasAppeared ? 1 : 0))
        .scaleEffect(hasAppeared ? 1 : 0.96)
        .onAppear(perform: animateEntrance)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("swipePage")) }) { frame in
            frameStore.frames[model.id] = frame
        }
    }

    private func animateEntrance() {
        guard !hasAppeared else { return }
        let inWindow = Date().timeIntervalSince(revealDate) < 0.8
        guard inWindow, index < 12, !reduceMotion else { hasAppeared = true; return }
        withAnimation(ProMotionSprings.cascade(index: min(index, 8))) { hasAppeared = true }
    }
}

// MARK: - Empty

struct CreatorLaneEmpty: View {
    let title: String
    let line: String
    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text(title).font(DS.headline).foregroundStyle(DS.textSecondary)
            Text(line).font(DS.callout).foregroundStyle(DS.textMuted).frame(maxWidth: 480, alignment: .leading)
        }
        .padding(.vertical, DS.space24)
        .accessibilityElement(children: .combine)
    }
}
