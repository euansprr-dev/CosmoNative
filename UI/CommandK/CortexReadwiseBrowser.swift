// CosmoOS/UI/CommandK/CortexReadwiseBrowser.swift
// Compact book shelf reusing the premium ReadwiseBookCard with 3D tilt effect

import SwiftUI
import AppKit

struct CortexReadwiseBrowser: View {
    var viewModel: CommandKViewModel
    @StateObject private var bookStore = ReadwiseBookStore.shared
    @State private var hasAppeared = false
    @State private var selectedBookID: Int?

    var body: some View {
        content
        .task {
            if bookStore.books.isEmpty { await bookStore.loadBooks() }
            if selectedBookID == nil {
                selectedBookID = bookStore.books.first?.id
            }
            withAnimation(ProMotionSprings.cardEntrance) { hasAppeared = true }
        }
        .onChange(of: bookStore.books.map(\.id)) { _, ids in
            if selectedBookID == nil || !ids.contains(selectedBookID ?? -1) {
                selectedBookID = ids.first
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if bookStore.books.isEmpty && !hasAppeared {
            skeletonGrid
        } else if bookStore.books.isEmpty {
            emptyState
        } else {
            librarySurface
        }
    }

    private var selectedBook: ReadwiseLibraryBook? {
        if let selectedBookID, let book = bookStore.books.first(where: { $0.id == selectedBookID }) {
            return book
        }
        return bookStore.books.first
    }

    // MARK: - Library Surface

    private var librarySurface: some View {
        VStack(spacing: 0) {
            libraryToolbar
            Divider().foregroundStyle(DS.glassBorder.opacity(0.62))
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: DS.space16) {
                    Text("Sources")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(DS.text)

                    bookGrid
                }
                .padding(.horizontal, DS.space24)
                .padding(.vertical, DS.space20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().foregroundStyle(DS.glassBorder.opacity(0.62))

                if let selectedBook {
                    CommandKReadwisePreviewPane(book: selectedBook) {
                        openBook(selectedBook)
                    }
                    .frame(width: 372)
                }
            }
        }
        .frame(minHeight: 470)
    }

    private var libraryToolbar: some View {
        HStack(spacing: DS.space12) {
            librarySegment("Books", icon: "book.closed", isSelected: false)
            librarySegment("Sources", icon: "doc.text", isSelected: true)
            librarySegment("PDFs", icon: "doc.richtext", isSelected: false)
            Spacer()
            HStack(spacing: 0) {
                toolbarIcon("square.grid.2x2", isSelected: true)
                toolbarIcon("line.3.horizontal")
            }
        }
        .padding(.horizontal, DS.space24)
        .frame(height: 64)
    }

    private var bookGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 156, maximum: 176), spacing: DS.space12)],
                spacing: DS.space12
            ) {
                ForEach(Array(bookStore.books.enumerated()), id: \.element.id) { index, book in
                    CommandKReadwiseSourceCard(
                        book: book,
                        isSelected: book.id == selectedBook?.id
                    ) {
                        withAnimation(ProMotionSprings.snappy) {
                            selectedBookID = book.id
                        }
                    } onOpen: {
                        openBook(book)
                    }
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 8)
                    .animation(CommandKAnimationPolicy.entranceAnimation(index: index), value: hasAppeared)
                }
            }
            .padding(.bottom, DS.space12)
        }
    }

    private func librarySegment(_ title: String, icon: String, isSelected: Bool) -> some View {
        Button { } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? .white : DS.textSecondary)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(isSelected ? DS.entityReadwise : DS.glassCardFill.opacity(0.42), in: Capsule())
                .overlay(Capsule().stroke(DS.glassBorder.opacity(0.60), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func toolbarIcon(_ icon: String, isSelected: Bool = false) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(isSelected ? DS.text : DS.textSecondary)
            .frame(width: 36, height: 34)
            .background(isSelected ? DS.glassCardFill.opacity(0.72) : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)
    }

    private func openBook(_ book: ReadwiseLibraryBook) {
        viewModel.selectedReadwiseBookId = book.id
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
    }

    // MARK: - Skeleton

    private var skeletonGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 140, maximum: 160), spacing: DS.space16)],
            spacing: DS.space20
        ) {
            ForEach(0..<6, id: \.self) { _ in
                VStack(spacing: DS.space8) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(DS.glassCardFill.opacity(0.3))
                        .frame(width: 120, height: 170)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(DS.glassCardFill.opacity(0.2))
                        .frame(width: 100, height: 12)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(DS.glassCardFill.opacity(0.15))
                        .frame(width: 70, height: 10)
                }
            }
        }
        .padding(DS.space16)
    }

    private var emptyState: some View {
        VStack(spacing: DS.space8) {
            Image(systemName: "books.vertical")
                .font(.system(size: 28))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            Text("Connect Readwise to browse books")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space32)
    }
}

// MARK: - Polished Library Cards

private struct CommandKReadwiseSourceCard: View {
    let book: ReadwiseLibraryBook
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DS.space10) {
                CommandKBookCover(book: book)
                    .frame(width: 52, height: 78)

                VStack(alignment: .leading, spacing: DS.space6) {
                    Text(book.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.text)
                        .lineLimit(3)

                    Text(book.author ?? book.category.displayName)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)

                    Text(book.category.displayName)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(DS.textMuted)
                }

                Spacer(minLength: 0)
            }
            .padding(DS.space12)
            .frame(height: 112)
            .background(DS.glassCardFill.opacity(isSelected ? 0.78 : 0.38), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? DS.entityReadwise.opacity(0.82) : DS.glassBorder.opacity(0.64), lineWidth: isSelected ? 1.1 : 0.5)
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.07 : 0.025), radius: isHovered ? 12 : 6, x: 0, y: isHovered ? 5 : 2)
            .scaleEffect(isHovered ? 1.006 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
        .contextMenu {
            Button(action: onOpen) {
                Label("Open", systemImage: "arrow.up.right.square")
            }

            if let sourceURL = book.sourceUrl, let url = URL(string: sourceURL) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open Source", systemImage: "safari")
                }
            }
        }
        .accessibilityLabel(book.title)
    }
}

private struct CommandKReadwisePreviewPane: View {
    let book: ReadwiseLibraryBook
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space18) {
            HStack(alignment: .top, spacing: DS.space16) {
                CommandKBookCover(book: book)
                    .frame(width: 76, height: 112)

                VStack(alignment: .leading, spacing: DS.space8) {
                    Text(book.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(DS.text)
                        .lineLimit(3)

                    if let author = book.author {
                        Text(author)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(DS.textSecondary)
                    }

                    Label(book.category.displayName, systemImage: book.category.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.textSecondary)
                }
            }

            quoteCard

            tags

            Spacer()

            HStack(spacing: DS.space12) {
                primaryAction("Open", icon: "arrow.up.right.square", action: onOpen)
                secondaryAction("Attach", icon: "paperclip")
                secondaryAction("Canvas", icon: "square.grid.2x2")
            }
        }
        .padding(DS.space20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DS.glassCardFill.opacity(0.24))
    }

    private var quoteCard: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            Text("\"\(book.highlights.first?.text ?? "\(book.numHighlights) saved highlights.")\"")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(DS.text)
                .lineSpacing(4)
                .lineLimit(5)
            if let author = book.author {
                Text("— \(author)")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(DS.textSecondary)
            }
        }
        .padding(DS.space16)
        .background(DS.vellum.opacity(0.44), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.glassBorder.opacity(0.60), lineWidth: 0.5)
        )
    }

    private var tags: some View {
        HStack(spacing: DS.space8) {
            ForEach(Array(book.bookTags.prefix(3)), id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, DS.space10)
                    .frame(height: 28)
                    .background(DS.entityReadwise.opacity(0.11), in: Capsule())
            }
            if book.bookTags.count > 3 {
                Text("+\(book.bookTags.count - 3)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, DS.space10)
                    .frame(height: 28)
                    .background(DS.glassCardFill.opacity(0.52), in: Capsule())
            }
        }
    }

    private func primaryAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(DS.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func secondaryAction(_ title: String, icon: String) -> some View {
        Button { } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DS.text)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(DS.glassCardFill.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DS.glassBorder.opacity(0.62), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct CommandKBookCover: View {
    let book: ReadwiseLibraryBook

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(DS.vellum)

            if let cover = book.coverImageUrl, let url = URL(string: cover) {
                CachedAsyncImage(url: url, stableKey: "\(book.id)") { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty:
                        ProgressView().scaleEffect(0.55).tint(DS.textMuted)
                    case .failure:
                        fallbackCover
                    }
                }
            } else {
                fallbackCover
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(DS.glassBorder.opacity(0.72), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 7, x: 0, y: 3)
    }

    private var fallbackCover: some View {
        VStack(spacing: DS.space6) {
            Text(book.title.prefix(22).description)
                .font(.system(size: 10, weight: .semibold, design: .serif))
                .foregroundStyle(DS.entityReadwise)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Rectangle()
                .fill(DS.entityReadwise.opacity(0.28))
                .frame(height: 1)
        }
        .padding(DS.space8)
    }
}
