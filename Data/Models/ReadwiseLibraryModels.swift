// CosmoOS/Data/Models/ReadwiseLibraryModels.swift
// UI-ready models for the Readwise Library tab in Command-K

import SwiftUI

// MARK: - ReadwiseLibraryBook

struct ReadwiseLibraryBook: Identifiable, Codable, Sendable, Equatable {
    let id: Int
    let title: String
    let author: String?
    let category: ReadwiseCategory
    let coverImageUrl: String?
    let sourceUrl: String?
    let numHighlights: Int
    let highlights: [ReadwiseLibraryHighlight]
    let bookTags: [String]
}

// MARK: - ReadwiseLibraryHighlight

struct ReadwiseLibraryHighlight: Identifiable, Codable, Sendable, Equatable {
    let id: Int
    let text: String
    let note: String?
    let location: Int?
    let color: String?
    let tags: [String]
    let bookId: Int
    let highlightedAt: String?

    /// Map Readwise highlight color string to SwiftUI Color
    var highlightColor: Color {
        switch color?.lowercased() {
        case "yellow": return Color(hex: "F6C744")
        case "blue": return Color(hex: "5B9BD5")
        case "pink": return Color(hex: "E06C9F")
        case "orange": return Color(hex: "E8945A")
        default: return Color(hex: "A0785A")
        }
    }
}

// MARK: - ReadwiseCategory

enum ReadwiseCategory: String, Codable, CaseIterable, Sendable {
    case books
    case articles
    case tweets
    case podcasts
    case supplementals

    var displayName: String {
        switch self {
        case .books: return "Books"
        case .articles: return "Articles"
        case .tweets: return "Tweets"
        case .podcasts: return "Podcasts"
        case .supplementals: return "Supplementals"
        }
    }

    var icon: String {
        switch self {
        case .books: return "book.closed.fill"
        case .articles: return "doc.text.fill"
        case .tweets: return "bubble.left.fill"
        case .podcasts: return "headphones"
        case .supplementals: return "doc.append.fill"
        }
    }
}

// MARK: - Sort Mode

enum ReadwiseSortMode: String, CaseIterable {
    case recent = "Recent"
    case mostHighlights = "Most Highlights"
    case authorAZ = "Author A–Z"
    case titleAZ = "Title A–Z"

    var displayName: String { rawValue }
}
