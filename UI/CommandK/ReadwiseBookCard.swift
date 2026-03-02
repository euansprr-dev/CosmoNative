// CosmoOS/UI/CommandK/ReadwiseBookCard.swift
// Premium book cover card with 3D tilt effect on hover
// Used in the Readwise Library tab's book shelf grid

import SwiftUI

struct ReadwiseBookCard: View {
    let book: ReadwiseLibraryBook
    let appearDelay: Double
    let hasAppeared: Bool
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var hoverLocation: CGPoint = .zero

    private let cognac = DS.entityReadwise
    private let coverWidth: CGFloat = 120
    private let coverHeight: CGFloat = 170

    var body: some View {
        Button(action: onTap) {
            cardContent
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }
            if !hovering {
                hoverLocation = CGPoint(x: coverWidth / 2, y: coverHeight / 2)
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoverLocation = location
            case .ended:
                break
            @unknown default:
                break
            }
        }
        .opacity(hasAppeared ? 1.0 : 0.0)
        .offset(y: hasAppeared ? 0 : 20)
        .animation(
            ProMotionSprings.snappy.delay(appearDelay),
            value: hasAppeared
        )
    }

    // MARK: - Card Content

    private var cardContent: some View {
        VStack(spacing: 8) {
            bookCover
                .rotation3DEffect(
                    .degrees(isHovered ? tiltX : 0),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.5
                )
                .rotation3DEffect(
                    .degrees(isHovered ? tiltY : 0),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: 0.5
                )

            bookInfo
        }
        .frame(width: 140)
    }

    // MARK: - Cover

    private var bookCover: some View {
        Group {
            if let urlString = book.coverImageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        coverPlaceholder
                    case .empty:
                        coverPlaceholder
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .tint(DS.textMuted)
                            )
                    @unknown default:
                        coverPlaceholder
                    }
                }
            } else {
                coverPlaceholder
            }
        }
        .frame(width: coverWidth, height: coverHeight)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isHovered ? cognac.opacity(0.4) : DS.border,
                    lineWidth: 1
                )
        )
        .shadow(
            color: isHovered ? cognac.opacity(0.2) : .black.opacity(0.08),
            radius: isHovered ? 12 : 4,
            y: isHovered ? 6 : 2
        )
    }

    private var coverPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [cognac.opacity(0.15), cognac.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 6) {
                Image(systemName: book.category.icon)
                    .font(.system(size: 24))
                    .foregroundColor(cognac.opacity(0.4))

                Text(book.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(cognac.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - Info

    private var bookInfo: some View {
        VStack(spacing: 3) {
            Text(book.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let author = book.author, !author.isEmpty {
                Text(author)
                    .font(.system(size: 10))
                    .foregroundColor(DS.textMuted)
                    .lineLimit(1)
            }

            highlightCountPill
        }
    }

    private var highlightCountPill: some View {
        HStack(spacing: 3) {
            Image(systemName: "text.quote")
                .font(.system(size: 8))
            Text("\(book.numHighlights)")
                .font(.system(size: 9, weight: .medium).monospacedDigit())
        }
        .foregroundColor(cognac)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(cognac.opacity(0.12))
        )
    }

    // MARK: - Tilt Calculation

    /// Horizontal tilt: card tilts toward cursor X position
    private var tiltX: Double {
        let centerX = coverWidth / 2
        let offset = (hoverLocation.x - centerX) / centerX
        return Double(offset) * 8
    }

    /// Vertical tilt: card tilts toward cursor Y position
    private var tiltY: Double {
        let centerY = coverHeight / 2
        let offset = (hoverLocation.y - centerY) / centerY
        return Double(-offset) * 5
    }
}

// MARK: - Preview

#Preview("Book Card") {
    HStack(spacing: 20) {
        ReadwiseBookCard(
            book: ReadwiseLibraryBook(
                id: 1,
                title: "Thinking, Fast and Slow",
                author: "Daniel Kahneman",
                category: .books,
                coverImageUrl: nil,
                sourceUrl: nil,
                numHighlights: 42,
                highlights: [],
                bookTags: []
            ),
            appearDelay: 0,
            hasAppeared: true
        ) {}

        ReadwiseBookCard(
            book: ReadwiseLibraryBook(
                id: 2,
                title: "The Art of War",
                author: "Sun Tzu",
                category: .books,
                coverImageUrl: nil,
                sourceUrl: nil,
                numHighlights: 18,
                highlights: [],
                bookTags: []
            ),
            appearDelay: 0.04,
            hasAppeared: true
        ) {}
    }
    .padding(40)
    .background(DS.bg)
}
