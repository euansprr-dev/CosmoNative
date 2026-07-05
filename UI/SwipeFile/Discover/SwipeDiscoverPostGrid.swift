import SwiftUI

/// Shared masonry of Discover post cards with quick look — used by the Discover
/// feed and the creator profile. Owns its frame store and preview state.
struct SwipeDiscoverPostGrid: View {
    let posts: [SocialPostSnapshot]
    @Bindable var model: SwipeDiscoverModel
    var targetColumnWidth: CGFloat = 248

    @State private var frameStore = SwipeFrameStore()
    @State private var quickLookID: String?
    @State private var quickLookExpanded = false
    @State private var quickLookSource: CGRect?
    @State private var revealDate = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let cardModels = posts.map(SwipeCardModel.init(post:))

        ZStack(alignment: .topLeading) {
            SwipeWaterfallGrid(
                items: cardModels,
                targetColumnWidth: targetColumnWidth,
                spacing: 14,
                maxColumns: 4,
                itemHeight: { model, width in model.height(forWidth: width) },
                cell: { cardModel, width, index in
                    SwipeDiscoverCardCell(
                        model: cardModel,
                        width: width,
                        index: index,
                        isHidden: quickLookID == cardModel.id,
                        revealDate: revealDate,
                        frameStore: frameStore,
                        boards: SwipeBoardStore.shared.boards,
                        onOpen: { openQuickLook(postID: $0) },
                        onTranscript: { transcript(postID: $0) },
                        onSave: { id, boardID in save(postID: id, boardID: boardID) }
                    )
                }
            )
        }
        .onChange(of: posts.map(\.id)) { revealDate = Date() }
        .overlay {
            if let post = quickLookPost {
                quickLook(post)
            }
        }
    }

    private var quickLookPost: SocialPostSnapshot? {
        guard let quickLookID else { return nil }
        return posts.first { $0.id == quickLookID }
    }

    private func quickLook(_ post: SocialPostSnapshot) -> some View {
        let index = posts.firstIndex { $0.id == post.id }
        return SwipeQuickLook(
            expanded: $quickLookExpanded,
            sourceFrame: quickLookSource,
            heroModel: SwipeCardModel(post: post),
            onRequestClose: closeQuickLook
        ) {
            SwipeQuickLookDiscoverContent(
                post: post,
                model: SwipeCardModel(post: post),
                hasPrevious: (index ?? 0) > 0,
                hasNext: index.map { $0 < posts.count - 1 } ?? false,
                onSave: { boardID in save(postID: post.id, boardID: boardID) },
                onTranscript: { transcript(postID: post.id) },
                onPrevious: { step(-1) },
                onNext: { step(1) },
                onClose: closeQuickLook
            )
        }
    }

    // MARK: - Actions

    private func openQuickLook(postID: String) {
        quickLookSource = frameStore.frames[postID]
        quickLookID = postID
    }

    private func closeQuickLook() {
        guard quickLookID != nil else { return }
        if let id = quickLookID, let frame = frameStore.frames[id] {
            quickLookSource = frame
        }
        guard !reduceMotion else {
            quickLookExpanded = false
            quickLookID = nil
            return
        }
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

    private func save(postID: String, boardID: String?) {
        guard let post = posts.first(where: { $0.id == postID }) else { return }
        model.save(post, boardID: boardID)
    }

    private func transcript(postID: String) {
        guard let post = posts.first(where: { $0.id == postID }) else { return }
        quickLookExpanded = false
        quickLookID = nil
        Task { await model.saveAndOpenForTranscription(post) }
    }
}

// MARK: - Cell

private struct SwipeDiscoverCardCell: View {
    let model: SwipeCardModel
    let width: CGFloat
    let index: Int
    var isHidden = false
    let revealDate: Date
    let frameStore: SwipeFrameStore
    let boards: [SwipeBoard]
    let onOpen: (String) -> Void
    let onTranscript: (String) -> Void
    let onSave: (String, String?) -> Void

    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SwipeCard(
            model: model,
            width: width,
            actions: SwipeCardActions(
                onOpen: { onOpen(model.id) },
                onStudy: { onTranscript(model.id) },
                onBookmark: { onSave(model.id, nil) }
            )
        )
        .contextMenu { contextMenuItems }
        .opacity(isHidden ? 0 : (hasAppeared ? 1 : 0))
        .scaleEffect(hasAppeared ? 1 : 0.96)
        .onAppear(perform: animateEntrance)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("swipePage")) }) { frame in
            frameStore.frames[model.id] = frame
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Quick Look", systemImage: "eye") { onOpen(model.id) }
        Button("Transcript & Study", systemImage: "text.quote") { onTranscript(model.id) }
        Divider()
        Button("Save to All Swipes", systemImage: "rectangle.stack.badge.plus") { onSave(model.id, nil) }
        ForEach(boards) { board in
            Button("Save to \(board.name)", systemImage: board.icon) { onSave(model.id, board.uuid) }
        }
    }

    private func animateEntrance() {
        guard !hasAppeared else { return }
        let isRevealWindow = Date().timeIntervalSince(revealDate) < 0.8
        guard isRevealWindow, index < 12, !reduceMotion else {
            hasAppeared = true
            return
        }
        withAnimation(ProMotionSprings.cascade(index: min(index, 8))) {
            hasAppeared = true
        }
    }
}
