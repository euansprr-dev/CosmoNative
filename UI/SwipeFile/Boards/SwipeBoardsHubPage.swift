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
                .swipeContentMeasure()
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
        }
        .coordinateSpace(name: "swipePage")
        .task {
            await SwipeBoardStore.shared.loadIfNeeded()
            await viewModel.loadIfNeeded(section: .boards)
        }
        .onAppear { viewModel.surfaceDidAppear() }
        .onDisappear { viewModel.surfaceDidDisappear() }
    }

    private var masthead: some View {
        SwipeMasthead(title: "Boards", detail: "\(SwipeBoardStore.shared.boards.count) collections")
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
        .swipeCardSurface(isHovered: isHovered)
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
            // Board identity, the App Store register: a typed emoji wins and
            // cleans the label; then the curated keyword pass; SF glyph last.
            let identity = CollectionEmoji.resolve(name: board.name)
            HStack(spacing: 6) {
                if let emoji = identity.emoji {
                    Text(emoji)
                        .font(DS.caption)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: board.icon)
                        .font(DS.caption.weight(.semibold))
                        .foregroundStyle(DS.textMuted)
                        .accessibilityHidden(true)
                }
                Text(identity.label)
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Open", systemImage: "arrow.up.forward") { onOpen() }
        SwipeLabLaunchButton(scope: .board(board), title: "Study in Swipe Lab")
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
