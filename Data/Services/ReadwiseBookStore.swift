// CosmoOS/Data/Services/ReadwiseBookStore.swift
// Local cache for Readwise books + highlights — fast UI access for the Library tab
// Persists to UserDefaults as JSON, refreshes via ReadwiseService Export API

import Foundation
import SwiftUI

@MainActor
class ReadwiseBookStore: ObservableObject {
    static let shared = ReadwiseBookStore()

    @Published var books: [ReadwiseLibraryBook] = []
    @Published var isLoaded: Bool = false
    @Published var isLoading: Bool = false
    @Published var loadError: String?

    private let cacheKey = "readwise_library_cache"
    private let cacheTimestampKey = "readwise_library_cache_timestamp"
    private let cacheMaxAge: TimeInterval = 15 * 60 // 15 minutes

    private init() {
        loadFromCache()
    }

    // MARK: - Public API

    /// Load books from cache or API. Only fetches from API if cache is stale or forceRefresh is true.
    func loadBooks(forceRefresh: Bool = false) async {
        guard !isLoading else { return }

        // If already loaded and cache is fresh, skip
        if isLoaded && !forceRefresh && !needsRefresh {
            return
        }

        isLoading = true
        loadError = nil

        do {
            let fetchedBooks = try await ReadwiseService.shared.fetchBooksWithHighlights()
            books = fetchedBooks.sorted { ($0.highlights.first?.highlightedAt ?? "") > ($1.highlights.first?.highlightedAt ?? "") }
            isLoaded = true
            saveToCache()
        } catch {
            loadError = error.localizedDescription
            // If we have cached data, keep showing it
            if books.isEmpty {
                isLoaded = false
            }
        }

        isLoading = false
    }

    /// Search across all books and their highlights
    func search(query: String) -> [ReadwiseLibraryBook] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return books }

        return books.filter { Self.matchesSearch($0, query: trimmed) }
    }

    nonisolated static func matchesSearch(_ book: ReadwiseLibraryBook, query: String) -> Bool {
        CommandKSearchMatcher.matches(query, in: book.title) ||
        CommandKSearchMatcher.matches(query, in: book.author) ||
        book.highlights.contains { highlight in
            ReadwiseLibraryTab.matchesSearch(highlight, query: query)
        }
    }

    /// Total highlight count across all books
    var totalHighlightCount: Int {
        books.reduce(0) { $0 + $1.numHighlights }
    }

    /// Whether cache needs refresh
    var needsRefresh: Bool {
        guard let timestamp = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(timestamp) > cacheMaxAge
    }

    // MARK: - Cache

    private func loadFromCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return }
        do {
            books = try JSONDecoder().decode([ReadwiseLibraryBook].self, from: data)
            if !books.isEmpty {
                isLoaded = true
            }
        } catch {
            print("ReadwiseBookStore: Failed to load cache: \(error)")
        }
    }

    private func saveToCache() {
        do {
            let data = try JSONEncoder().encode(books)
            UserDefaults.standard.set(data, forKey: cacheKey)
            UserDefaults.standard.set(Date(), forKey: cacheTimestampKey)
        } catch {
            print("ReadwiseBookStore: Failed to save cache: \(error)")
        }
    }

    /// Clear all cached data
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: cacheTimestampKey)
        books = []
        isLoaded = false
    }
}
