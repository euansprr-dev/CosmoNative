// CosmoOS/UI/CommandK/ReadwiseLibraryTab.swift
// Readwise Library tab for Command-K — premium book shelf with annotation detail view
// Books displayed in a grid with 3D tilt covers; click into a book to see highlights
// Clicking a highlight creates a .research atom and places it on the current canvas

import SwiftUI

// MARK: - ReadwiseLibraryTab

struct ReadwiseLibraryTab: View {

    var viewModel: CommandKViewModel
    let searchQuery: String

    @StateObject private var bookStore = ReadwiseBookStore.shared
    @State private var hasAppeared = false
    @State private var categoryFilter: ReadwiseCategory? = nil
    @State private var sortMode: ReadwiseSortMode = .recent
    @State private var selectedBook: ReadwiseLibraryBook? = nil
    @State private var highlightSearchText = ""

    private let cognac = DS.entityReadwise

    // MARK: - Filtered & Sorted Books

    private var filteredBooks: [ReadwiseLibraryBook] {
        var result = searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
            ? bookStore.books
            : bookStore.search(query: searchQuery)

        if let categoryFilter {
            result = result.filter { $0.category == categoryFilter }
        }

        switch sortMode {
        case .recent:
            break // Already sorted by recent in BookStore
        case .mostHighlights:
            result.sort { $0.numHighlights > $1.numHighlights }
        case .authorAZ:
            result.sort { ($0.author ?? "") < ($1.author ?? "") }
        case .titleAZ:
            result.sort { $0.title < $1.title }
        }

        return result
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            DS.surface

            if !ReadwiseService.shared.isConnected {
                setupPrompt
            } else if let book = selectedBook {
                bookDetailView(book)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            } else {
                shelfView
            }
        }
        .task {
            if ReadwiseService.shared.isConnected {
                await bookStore.loadBooks()
            }
            withAnimation(ProMotionSprings.gentle) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Shelf View

    private var shelfView: some View {
        VStack(spacing: 0) {
            filterBar

            Divider().background(DS.borderSubtle)

            if bookStore.isLoading && bookStore.books.isEmpty {
                loadingView
            } else if filteredBooks.isEmpty {
                emptyState
            } else {
                bookShelfGrid
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: CommandKMetrics.toolbarSpacing) {
            statsLabel

            Spacer()

            categoryMenu

            filterSeparator

            sortMenu

            if categoryFilter != nil {
                clearButton
            }

            if bookStore.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(DS.textMuted)
            }
        }
        .padding(.horizontal, CommandKMetrics.contentPadding)
        .padding(.vertical, 12)
    }

    private var statsLabel: some View {
        HStack(spacing: 6) {
            Text("\(filteredBooks.count) \(filteredBooks.count == 1 ? "book" : "books")")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.textSecondary)

            Text("·")
                .foregroundColor(DS.textMuted)

            let totalHighlights = filteredBooks.reduce(0) { $0 + $1.numHighlights }
            Text("\(totalHighlights) highlights")
                .font(.system(size: 13))
                .foregroundColor(DS.textMuted)
        }
    }

    private var categoryMenu: some View {
        Menu {
            Button {
                categoryFilter = nil
            } label: {
                HStack {
                    Text("All Categories")
                    if categoryFilter == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            ForEach(ReadwiseCategory.allCases, id: \.rawValue) { category in
                Button {
                    categoryFilter = category
                } label: {
                    HStack {
                        Label(category.displayName, systemImage: category.icon)
                        if categoryFilter == category {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            categoryMenuLabel
        }
        .menuStyle(.borderlessButton)
        .tint(DS.text)
    }

    @ViewBuilder
    private var categoryMenuLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: categoryFilter?.icon ?? "line.3.horizontal.decrease")
                .font(.system(size: 11))
            Text(categoryFilter?.displayName ?? "All Categories")
                .font(.system(size: 12, weight: .medium))
            Image(systemName: "chevron.down")
                .font(.system(size: 10))
        }
        .foregroundColor(categoryFilter != nil ? cognac : DS.text)
        .commandKToolbarChip(
            isActive: categoryFilter != nil,
            activeFill: cognac.opacity(0.12),
            activeBorder: cognac.opacity(0.18)
        )
    }

    private var sortMenu: some View {
        Menu {
            ForEach(ReadwiseSortMode.allCases, id: \.rawValue) { mode in
                Button {
                    sortMode = mode
                } label: {
                    HStack {
                        Text(mode.displayName)
                        if sortMode == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(sortMode.displayName)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
            }
            .foregroundColor(DS.text)
            .commandKToolbarChip()
        }
        .menuStyle(.borderlessButton)
        .tint(DS.text)
    }

    private var filterSeparator: some View {
        Rectangle()
            .fill(DS.border)
            .frame(width: 1, height: 22)
    }

    private var clearButton: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                categoryFilter = nil
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                Text("Clear")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(DS.textSecondary)
            .commandKToolbarChip(
                isActive: true,
                activeFill: cognac.opacity(0.10),
                activeBorder: cognac.opacity(0.18)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Book Shelf Grid

    private var bookShelfGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140, maximum: 160), spacing: 20)],
                spacing: 24
            ) {
                ForEach(Array(filteredBooks.enumerated()), id: \.element.id) { index, book in
                    ReadwiseBookCard(
                        book: book,
                        appearDelay: Double(index % 16) * 0.04,
                        hasAppeared: hasAppeared
                    ) {
                        withAnimation(ProMotionSprings.snappy) {
                            selectedBook = book
                            highlightSearchText = ""
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Book Detail View

    @ViewBuilder
    private func bookDetailView(_ book: ReadwiseLibraryBook) -> some View {
        VStack(spacing: 0) {
            detailNavBar(book)

            Divider().background(DS.borderActive)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    bookHeader(book)

                    Divider().background(DS.border)

                    highlightsList(book)
                }
                .padding(24)
            }
        }
    }

    private func detailNavBar(_ book: ReadwiseLibraryBook) -> some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    selectedBook = nil
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                    Text("Library")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(cognac)
            }
            .buttonStyle(.plain)

            Spacer()

            // Search within this book's highlights
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(DS.textMuted)
                TextField("Search highlights...", text: $highlightSearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(DS.text)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(DS.bg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(DS.borderSubtle, lineWidth: 1)
                    )
            )
            .frame(width: 220)
        }
        .padding(.horizontal, 24)
        .frame(height: 44)
    }

    private func bookHeader(_ book: ReadwiseLibraryBook) -> some View {
        HStack(alignment: .top, spacing: 20) {
            // Cover image (large)
            Group {
                if let urlString = book.coverImageUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            headerCoverPlaceholder(book)
                        }
                    }
                } else {
                    headerCoverPlaceholder(book)
                }
            }
            .frame(width: 100, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(DS.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)

            // Book info
            VStack(alignment: .leading, spacing: 8) {
                Text(book.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(DS.text)

                if let author = book.author, !author.isEmpty {
                    Text(author)
                        .font(.system(size: 14))
                        .foregroundColor(DS.textSecondary)
                }

                HStack(spacing: 12) {
                    // Category badge
                    HStack(spacing: 4) {
                        Image(systemName: book.category.icon)
                            .font(.system(size: 10))
                        Text(book.category.displayName)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(cognac)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(cognac.opacity(0.12))
                    )

                    // Highlight count
                    HStack(spacing: 4) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 10))
                        Text("\(book.numHighlights) highlights")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(DS.textSecondary)
                }

                // Tags
                if !book.bookTags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(book.bookTags.prefix(5), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(cognac.opacity(0.7))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(cognac.opacity(0.08)))
                        }
                    }
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func headerCoverPlaceholder(_ book: ReadwiseLibraryBook) -> some View {
        ZStack {
            LinearGradient(
                colors: [cognac.opacity(0.15), cognac.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: book.category.icon)
                .font(.system(size: 28))
                .foregroundColor(cognac.opacity(0.3))
        }
    }

    // MARK: - Highlights List

    @ViewBuilder
    private func highlightsList(_ book: ReadwiseLibraryBook) -> some View {
        let filtered = filteredHighlights(for: book)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HIGHLIGHTS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.textMuted)
                    .kerning(0.8)

                Text("\(filtered.count)")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundColor(cognac)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(cognac.opacity(0.12)))

                Spacer()

                Text("Click a highlight to add it to your canvas")
                    .font(.system(size: 11))
                    .foregroundColor(DS.textMuted)
            }

            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, highlight in
                highlightRow(highlight, book: book, index: index)
            }
        }
    }

    private func filteredHighlights(for book: ReadwiseLibraryBook) -> [ReadwiseLibraryHighlight] {
        let trimmed = highlightSearchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return book.highlights }
        return book.highlights.filter { Self.matchesSearch($0, query: trimmed) }
    }

    nonisolated static func matchesSearch(_ highlight: ReadwiseLibraryHighlight, query: String) -> Bool {
        CommandKSearchMatcher.matches(query, inAny: [highlight.text, highlight.note] + highlight.tags.map(Optional.some))
    }

    @ViewBuilder
    private func highlightRow(_ highlight: ReadwiseLibraryHighlight, book: ReadwiseLibraryBook, index: Int) -> some View {
        HighlightRowView(
            highlight: highlight,
            book: book,
            cognac: cognac,
            index: index,
            hasAppeared: hasAppeared
        )
    }

    // MARK: - Empty & Loading States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(cognac)
            Text("Loading your library...")
                .font(.system(size: 14))
                .foregroundColor(DS.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty && categoryFilter == nil {
                Image(systemName: "books.vertical")
                    .font(.system(size: 48))
                    .foregroundColor(cognac.opacity(0.3))
                Text("No books yet")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                Text("Your Readwise books and highlights will appear here")
                    .font(.system(size: 13))
                    .foregroundColor(DS.textMuted)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundColor(DS.textMuted)
                Text("No results found")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DS.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Setup Prompt

    private var setupPrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 48))
                .foregroundColor(cognac.opacity(0.4))

            Text("Connect Your Reading Library")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(DS.text)

            Text("Import your highlights from books, articles, and podcasts via Readwise.")
                .font(.system(size: 14))
                .foregroundColor(DS.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            ReadwiseSetupField(cognac: cognac)

            Button {
                NSWorkspace.shared.open(URL(string: "https://readwise.io/access_token")!)
            } label: {
                Text("Get your API token →")
                    .font(.system(size: 12))
                    .foregroundColor(cognac)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Highlight Row View

/// Extracted to its own struct to avoid complex view expressions in ForEach
private struct HighlightRowView: View {
    let highlight: ReadwiseLibraryHighlight
    let book: ReadwiseLibraryBook
    let cognac: Color
    let index: Int
    let hasAppeared: Bool

    @State private var isHovered = false
    @State private var isPlacing = false

    var body: some View {
        Button {
            placeOnCanvas()
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .opacity(hasAppeared ? 1.0 : 0.0)
        .animation(
            ProMotionSprings.gentle.delay(Double(index % 20) * 0.02),
            value: hasAppeared
        )
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                // Highlight text
                Text(highlight.text)
                    .font(.system(size: 13))
                    .foregroundColor(DS.text)
                    .lineLimit(isHovered ? nil : 4)
                    .multilineTextAlignment(.leading)

                // Note
                if let note = highlight.note, !note.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text")
                            .font(.system(size: 9))
                        Text(note)
                            .font(.system(size: 11))
                            .lineLimit(isHovered ? nil : 2)
                    }
                    .foregroundColor(DS.textSecondary)
                }

                // Tags
                if !highlight.tags.isEmpty {
                    tagsRow
                }

                // Hover action hint
                if isHovered {
                    actionHint
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? cognac.opacity(0.04) : DS.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHovered ? cognac.opacity(0.3) : DS.border, lineWidth: 1)
        )
    }

    private var tagsRow: some View {
        HStack(spacing: 4) {
            ForEach(highlight.tags.prefix(4), id: \.self) { tag in
                Text("#\(tag)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(cognac.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(cognac.opacity(0.08)))
            }
        }
    }

    private var actionHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.rectangle.on.rectangle")
                .font(.system(size: 10))
            Text("Click to add to canvas")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(cognac)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Place on Canvas

    private func placeOnCanvas() {
        guard !isPlacing else { return }
        isPlacing = true

        Task { @MainActor in
            // Create or find existing .research atom for this highlight
            let atom = await findOrCreateAtom()

            guard let atom else {
                isPlacing = false
                return
            }

            // Place on current canvas
            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.addItemToCurrentCanvas,
                object: nil,
                userInfo: [
                    "atomUUID": atom.uuid,
                    "atomType": atom.type.rawValue,
                    "title": atom.title ?? book.title
                ]
            )

            // Close Command-K
            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.closeCommandK,
                object: nil
            )

            isPlacing = false
        }
    }

    private func findOrCreateAtom() async -> Atom? {
        let readwiseId = String(highlight.id)

        // Check if atom already exists for this highlight
        do {
            let existing = try await AtomRepository.shared.search(
                metadataKey: "readwiseId",
                value: readwiseId,
                type: .research
            )
            if let found = existing.first {
                return found
            }
        } catch {
            print("ReadwiseLibraryTab: Error searching for existing atom: \(error)")
        }

        // Build structured JSON
        var structuredDict: [String: Any] = [
            "readwiseId": readwiseId
        ]
        if let note = highlight.note, !note.isEmpty {
            structuredDict["note"] = note
        }
        structuredDict["bookTitle"] = book.title
        if let author = book.author {
            structuredDict["author"] = author
        }
        structuredDict["category"] = book.category.rawValue
        if let highlightedAt = highlight.highlightedAt {
            structuredDict["highlightedAt"] = highlightedAt
        }
        if let sourceUrl = book.sourceUrl {
            structuredDict["sourceUrl"] = sourceUrl
        }
        if !highlight.tags.isEmpty {
            structuredDict["tags"] = highlight.tags
        }

        let structuredJson = try? JSONSerialization.data(withJSONObject: structuredDict)
        let structuredString = structuredJson.flatMap { String(data: $0, encoding: .utf8) }

        // Build metadata JSON
        var metadataDict: [String: Any] = [
            "source": "readwise",
            "readwiseId": readwiseId,
            "researchType": "highlight",
            "bookId": highlight.bookId
        ]
        if let sourceUrl = book.sourceUrl {
            metadataDict["sourceUrl"] = sourceUrl
        }

        let metadataJson = try? JSONSerialization.data(withJSONObject: metadataDict)
        let metadataString = metadataJson.flatMap { String(data: $0, encoding: .utf8) }

        // Title: "Book Title — Author"
        let authorSuffix = book.author.map { " — \($0)" } ?? ""
        let title = "\(book.title)\(authorSuffix)"

        do {
            return try await AtomRepository.shared.create(
                type: .research,
                title: title,
                body: highlight.text,
                structured: structuredString,
                metadata: metadataString
            )
        } catch {
            print("ReadwiseLibraryTab: Failed to create atom: \(error)")
            return nil
        }
    }
}

// MARK: - Setup Field

/// Inline API key entry for the not-connected state
private struct ReadwiseSetupField: View {
    let cognac: Color
    @State private var apiToken = ""
    @State private var isValidating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 12) {
            SecureField("Paste your Readwise API token...", text: $apiToken)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(DS.text)
                .padding(12)
                .frame(width: 320)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DS.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(DS.borderActive, lineWidth: 1)
                        )
                )
                .onSubmit { connect() }

            Button { connect() } label: {
                HStack(spacing: 6) {
                    if isValidating {
                        ProgressView()
                            .scaleEffect(0.5)
                            .tint(.white)
                    }
                    Text(isValidating ? "Connecting..." : "Connect")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(DS.textOnAccent)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(apiToken.trimmingCharacters(in: .whitespaces).isEmpty
                              ? cognac.opacity(0.4) : cognac)
                )
            }
            .buttonStyle(.plain)
            .disabled(apiToken.trimmingCharacters(in: .whitespaces).isEmpty || isValidating)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(DS.red)
            }
        }
    }

    private func connect() {
        let token = apiToken.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else { return }

        isValidating = true
        errorMessage = nil

        Task { @MainActor in
            let valid = await ReadwiseService.shared.connect(token: token)
            isValidating = false

            if valid {
                // Trigger library load
                await ReadwiseBookStore.shared.loadBooks(forceRefresh: true)
            } else {
                errorMessage = "Invalid API token. Please check and try again."
            }
        }
    }
}

// MARK: - Preview

#Preview("Readwise Library Tab") {
    ReadwiseLibraryTab(viewModel: CommandKViewModel(), searchQuery: "")
        .frame(width: 1000, height: 600)
}
