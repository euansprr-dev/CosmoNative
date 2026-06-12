import SwiftUI

/// Boards overview: cover-mosaic cards with live counts, inline rename, and a
/// dashed New Board ghost tile. Board detail is the library page scoped to a board.
struct SwipeBoardsHubPage: View {
    @Bindable var viewModel: SwipeLibraryViewModel
    let onOpenBoard: (String) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            SwipePageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space16) {
                    masthead
                    boardGrid
                }
                .padding(.horizontal, 48)
                .padding(.top, 36)
                .padding(.bottom, 72)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
        }
        .coordinateSpace(name: "swipePage")
        .task {
            await SwipeBoardStore.shared.loadIfNeeded()
            await viewModel.loadIfNeeded(section: .boards)
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Boards")
                .font(DS.pageTitle)
                .foregroundStyle(DS.text)
            Text("\(SwipeBoardStore.shared.boards.count) collections")
                .font(DS.subheadline.monospacedDigit())
                .foregroundStyle(DS.textMuted)
        }
    }

    private var boardGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 248), spacing: 16)], spacing: 16) {
            ForEach(SwipeBoardStore.shared.boards) { board in
                SwipeBoardCard(
                    board: board,
                    count: memberItems(for: board).count,
                    coverItems: Array(memberItems(for: board).prefix(4)),
                    onOpen: { onOpenBoard(board.uuid) }
                )
            }
            SwipeNewBoardTile { name in
                Task {
                    if let board = await SwipeBoardStore.shared.create(name: name) {
                        onOpenBoard(board.uuid)
                    }
                }
            }
        }
    }

    private func memberItems(for board: SwipeBoard) -> [SwipeCardModel] {
        viewModel.allItems
            .filter { $0.boardIDs.contains(board.uuid) }
            .compactMap { viewModel.cardModelsByID[$0.id] ?? SwipeCardModel(item: $0) }
    }
}

// MARK: - Board card

private struct SwipeBoardCard: View {
    let board: SwipeBoard
    let count: Int
    let coverItems: [SwipeCardModel]
    let onOpen: () -> Void

    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var confirmDelete = false
    @FocusState private var renameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SwipeBoardMosaic(coverItems: coverItems, icon: board.icon)
            nameRow
            Text(count == 1 ? "1 swipe" : "\(count) swipes")
                .font(DS.caption.monospacedDigit())
                .foregroundStyle(DS.textMuted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .swipeCardSurface(isHovered: isHovered, tint: DS.entitySwipe)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture(perform: handleTap)
        .contextMenu { contextMenuItems }
        .confirmationDialog(
            "Delete “\(board.name)”?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Board", role: .destructive) {
                Task { await SwipeBoardStore.shared.archive(uuid: board.uuid) }
            }
        } message: {
            Text("Swipes stay in your library — only the board goes away.")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(board.name), \(count) swipes")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var nameRow: some View {
        if isRenaming {
            TextField("Board name", text: $draftName)
                .textFieldStyle(.plain)
                .font(DS.headline)
                .foregroundStyle(DS.text)
                .focused($renameFocused)
                .onSubmit(commitRename)
                .onChange(of: renameFocused) { _, focused in
                    if !focused { commitRename() }
                }
        } else {
            HStack(spacing: 6) {
                Image(systemName: board.icon)
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .accessibilityHidden(true)
                Text(board.name)
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Open", systemImage: "arrow.up.forward") { onOpen() }
        Button("Rename…", systemImage: "pencil") { beginRename() }
        Divider()
        Button("Delete…", systemImage: "trash", role: .destructive) { confirmDelete = true }
    }

    private func handleTap() {
        guard !isRenaming else { return }
        onOpen()
    }

    private func beginRename() {
        draftName = board.name
        isRenaming = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            renameFocused = true
        }
    }

    private func commitRename() {
        guard isRenaming else { return }
        isRenaming = false
        let name = draftName
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name != board.name else { return }
        Task { await SwipeBoardStore.shared.rename(uuid: board.uuid, to: name) }
    }
}

// MARK: - Cover mosaic

private struct SwipeBoardMosaic: View {
    let coverItems: [SwipeCardModel]
    let icon: String

    private let gutter: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let cell = (proxy.size.width - gutter) / 2
            VStack(spacing: gutter) {
                HStack(spacing: gutter) {
                    tile(0, size: cell)
                    tile(1, size: cell)
                }
                HStack(spacing: gutter) {
                    tile(2, size: cell)
                    tile(3, size: cell)
                }
            }
        }
        .frame(height: 148)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func tile(_ index: Int, size: CGFloat) -> some View {
        if index < coverItems.count, coverItems[index].mediaURL != nil || coverItems[index].aspect == .paper {
            mosaicCell(coverItems[index], size: size)
        } else {
            Rectangle()
                .fill(DS.glassSectionFill)
                .frame(width: size, height: 73)
                .overlay {
                    if index == 0 && coverItems.isEmpty {
                        Image(systemName: icon)
                            .font(DS.subheadline)
                            .foregroundStyle(DS.textMuted)
                    }
                }
        }
    }

    private func mosaicCell(_ model: SwipeCardModel, size: CGFloat) -> some View {
        Group {
            if model.aspect == .paper {
                Rectangle()
                    .fill(DS.glassSectionFill)
                    .overlay {
                        Text(model.hookText)
                            .font(DS.caption2)
                            .foregroundStyle(DS.textMuted)
                            .lineLimit(3)
                            .padding(6)
                    }
            } else {
                CachedAsyncImage(url: model.mediaURL, stableKey: model.mediaStableKey) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty, .failure:
                        Rectangle().fill(DS.glassSectionFill)
                    }
                }
            }
        }
        .frame(width: size, height: 73)
        .clipped()
    }
}

// MARK: - New board tile

private struct SwipeNewBoardTile: View {
    let onCreate: (String) -> Void

    @State private var isCreating = false
    @State private var draftName = ""
    @State private var isHovered = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            if isCreating {
                creationField
            } else {
                ghostContent
            }
        }
        .frame(maxWidth: .infinity, minHeight: 222)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isHovered ? DS.glassBorderFocused : DS.glassBorder, style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { value in withAnimation(ProMotionSprings.hover) { isHovered = value } }
        .onTapGesture(perform: beginCreating)
        .accessibilityLabel("New board")
        .accessibilityAddTraits(.isButton)
    }

    private var ghostContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus")
                .font(DS.title2)
                .foregroundStyle(isHovered ? DS.accent : DS.textMuted)
            Text("New Board")
                .font(DS.subheadline.weight(.medium))
                .foregroundStyle(isHovered ? DS.text : DS.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var creationField: some View {
        VStack(spacing: 12) {
            TextField("Board name", text: $draftName)
                .textFieldStyle(.plain)
                .font(DS.callout.weight(.medium))
                .foregroundStyle(DS.text)
                .multilineTextAlignment(.center)
                .focused($nameFocused)
                .onSubmit(commit)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .dsGlassInput(isFocused: nameFocused, cornerRadius: 10)
                .frame(maxWidth: 200)
            Text("Press Return to create")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand {
            isCreating = false
            draftName = ""
        }
    }

    private func beginCreating() {
        guard !isCreating else { return }
        withAnimation(ProMotionSprings.snappy) { isCreating = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            nameFocused = true
        }
    }

    private func commit() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        isCreating = false
        draftName = ""
        guard !name.isEmpty else { return }
        onCreate(name)
    }
}
