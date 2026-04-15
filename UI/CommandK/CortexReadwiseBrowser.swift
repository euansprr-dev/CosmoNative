// CosmoOS/UI/CommandK/CortexReadwiseBrowser.swift
// Compact book shelf reusing the premium ReadwiseBookCard with 3D tilt effect

import SwiftUI

struct CortexReadwiseBrowser: View {
    @ObservedObject var viewModel: CommandKViewModel
    @StateObject private var bookStore = ReadwiseBookStore.shared
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider().foregroundStyle(DS.border.opacity(0.2))
            content
        }
        .task {
            if bookStore.books.isEmpty { await bookStore.loadBooks() }
            withAnimation(ProMotionSprings.cardEntrance) { hasAppeared = true }
        }
    }

    @ViewBuilder
    private var content: some View {
        if bookStore.books.isEmpty && !hasAppeared {
            skeletonGrid
        } else if bookStore.books.isEmpty {
            emptyState
        } else {
            bookGrid
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: DS.space8) {
            Text("\(bookStore.books.count) books")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)

            let totalHighlights = bookStore.books.reduce(0) { $0 + $1.numHighlights }
            Text("· \(totalHighlights) highlights")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
            Spacer()
        }
        .padding(.horizontal, DS.space16)
        .frame(height: 32)
    }

    // MARK: - Book Grid (reuses ReadwiseBookCard)

    private var bookGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140, maximum: 160), spacing: DS.space16)],
                spacing: DS.space20
            ) {
                ForEach(Array(bookStore.books.enumerated()), id: \.element.id) { index, book in
                    ReadwiseBookCard(
                        book: book,
                        appearDelay: Double(index) * 0.03,
                        hasAppeared: hasAppeared
                    ) {
                        viewModel.selectedReadwiseBookId = book.id
                    }
                }
            }
            .padding(DS.space16)
        }
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
