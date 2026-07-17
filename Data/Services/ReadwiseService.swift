// CosmoOS/Data/Services/ReadwiseService.swift
// Real Readwise API v2 integration.
// Two layers: the Command-K Library browse cache (fetchBooksWithHighlights →
// ReadwiseBookStore), and the knowledge-graph MIRROR (syncHighlights): one
// `.research` atom per book with highlights in structured JSON, feeding
// search, recall, the evidence matcher, and iPhone sync. See
// READWISE_INTEGRATION_PLAN.md.

import Foundation
import GRDB

// MARK: - Readwise API Data Models

struct ReadwiseHighlight: Codable, Sendable {
    let id: Int
    let text: String
    let note: String?
    let location: Int?
    let locationType: String?
    let highlightedAt: String?
    let url: String?
    let color: String?
    let updated: String?
    let bookId: Int?
    let tags: [ReadwiseTag]?
}

struct ReadwiseTag: Codable, Sendable {
    let id: Int?
    let name: String
}

struct ReadwiseBook: Codable, Sendable {
    let id: Int
    let title: String
    let author: String?
    let category: String?
    let source: String?
    let numHighlights: Int?
    let lastHighlightAt: String?
    let updated: String?
    let coverImageUrl: String?
    let highlightsUrl: String?
    let sourceUrl: String?
}

struct ReadwisePaginatedResponse<T: Codable & Sendable>: Codable, Sendable {
    let count: Int?
    let next: String?
    let previous: String?
    let results: [T]
}

// MARK: - Export API Models (books with nested highlights)

struct ReadwiseExportResponse: Codable, Sendable {
    let count: Int
    let nextPageCursor: String?
    let results: [ReadwiseExportBook]
}

struct ReadwiseExportBook: Codable, Sendable {
    let userBookId: Int
    let title: String
    let author: String?
    let readableTitle: String?
    let source: String?
    let coverImageUrl: String?
    let uniqueUrl: String?
    let bookTags: [ReadwiseTag]?
    let category: String?
    let sourceUrl: String?
    let asin: String?
    let highlights: [ReadwiseExportHighlight]
}

struct ReadwiseExportHighlight: Codable, Sendable {
    let id: Int
    let text: String
    let note: String?
    let location: Int?
    let locationType: String?
    let url: String?
    let color: String?
    let updated: String?
    let bookId: Int?
    let tags: [ReadwiseTag]?
    let highlightedAt: String?
    let isDiscard: Bool?
    /// Present when the export is called with includeDeleted=true — the
    /// mirror prunes these rows.
    let isDeleted: Bool?
}

// MARK: - ReadwiseService

@MainActor
class ReadwiseService: ObservableObject {
    static let shared = ReadwiseService()

    @Published var isConnected: Bool = false
    @Published var highlightCount: Int = 0
    @Published var lastSyncDate: Date?
    @Published var isSyncing: Bool = false
    @Published var syncError: String?
    @Published var isTokenValid: Bool?

    private let baseURL = "https://readwise.io/api/v2/"

    private var apiToken: String? {
        get { UserDefaults.standard.string(forKey: "readwiseAPIKey") }
        set {
            UserDefaults.standard.set(newValue, forKey: "readwiseAPIKey")
            isConnected = newValue != nil && !(newValue?.isEmpty ?? true)
        }
    }

    private var storedLastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: "readwiseLastSyncDate") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "readwiseLastSyncDate") }
    }

    private var storedHighlightCount: Int {
        get { UserDefaults.standard.integer(forKey: "readwiseHighlightCount") }
        set { UserDefaults.standard.set(newValue, forKey: "readwiseHighlightCount") }
    }

    /// Launch + 6-hourly mirror scheduling (startAutoSync).
    private var autoSyncTask: Task<Void, Never>?

    private init() {
        let token = UserDefaults.standard.string(forKey: "readwiseAPIKey")
        isConnected = token != nil && !(token?.isEmpty ?? true)
        lastSyncDate = storedLastSyncDate
        highlightCount = storedHighlightCount
    }

    // MARK: - Token Validation

    /// Validate the stored API token against Readwise
    /// Returns true if the token is valid (204 response)
    func validateToken() async -> Bool {
        guard let token = apiToken, !token.isEmpty else {
            isTokenValid = false
            isConnected = false
            return false
        }

        guard let url = URL(string: "\(baseURL)auth/") else {
            isTokenValid = false
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let valid = httpResponse.statusCode == 204
                isTokenValid = valid
                isConnected = valid
                return valid
            }
            isTokenValid = false
            return false
        } catch {
            isTokenValid = false
            return false
        }
    }

    /// Connect with a new token — validates and stores if valid
    func connect(token: String) async -> Bool {
        // Temporarily set the token so validateToken() can use it
        UserDefaults.standard.set(token, forKey: "readwiseAPIKey")
        let valid = await validateToken()
        if !valid {
            // Clear invalid token
            UserDefaults.standard.removeObject(forKey: "readwiseAPIKey")
            isConnected = false
        }
        return valid
    }

    // MARK: - Disconnect

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: "readwiseAPIKey")
        UserDefaults.standard.removeObject(forKey: "readwiseLastSyncDate")
        UserDefaults.standard.removeObject(forKey: "readwiseHighlightCount")
        isConnected = false
        isTokenValid = nil
        highlightCount = 0
        lastSyncDate = nil
    }

    // MARK: - Sync Highlights (the book mirror — July 2026)

    /// Mirror sync: one `.research` atom per Readwise book/article, highlights
    /// in structured JSON (`ReadwiseMirrorReducer` owns the pure mapping).
    /// Incremental via `updatedAfter` + `includeDeleted`; idempotent (an
    /// unchanged book writes nothing). The first mirror pass runs FULL and
    /// consolidates the legacy one-atom-per-highlight rows.
    func syncHighlights() async throws {
        guard let token = apiToken, !token.isEmpty else {
            throw ReadwiseError.noToken
        }
        _ = token

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        let startedAt = Date()
        let mirrorFlagDone = await Self.readFlag(Self.mirrorFlagKey)
        // Until the mirror is complete once, every pass is a full export —
        // consolidating legacy rows against a partial mirror would lose data.
        let cursor = mirrorFlagDone ? storedLastSyncDate : nil

        let books = try await fetchExportBooks(updatedAfter: cursor, includeDeleted: cursor != nil)

        // Existing mirror snapshot once per pass — upserts key on bookId.
        var mirrorByBookId: [String: Atom] = [:]
        for atom in await Self.mirrorAtoms() {
            if let bookId = atom.readwiseBookId {
                mirrorByBookId[bookId] = atom
            }
        }

        var booksTouched = 0
        for book in books {
            let existing = mirrorByBookId[String(book.userBookId)]
            let merged = ReadwiseMirrorReducer.mergedStructured(
                existing: existing?.readwiseStructured,
                incoming: book
            )

            // Every highlight pruned → the mirror forgets the book.
            if merged.structured.highlights.isEmpty {
                if let existing {
                    try? await AtomRepository.shared.delete(uuid: existing.uuid)
                    mirrorByBookId.removeValue(forKey: String(book.userBookId))
                    booksTouched += 1
                }
                continue
            }

            let title = ReadwiseMirrorReducer.displayTitle(for: book)
            let body = ReadwiseMirrorReducer.indexableBody(merged.structured)
            let overlay = ReadwiseMirrorReducer.metadataOverlay(for: book)

            if let existing {
                guard merged.changed || existing.title != title else { continue }
                let structuredJSON = merged.structured.toJSON()
                if let updated = try? await AtomRepository.shared.update(uuid: existing.uuid, updates: { atom in
                    atom.title = title
                    atom.body = body
                    atom.structured = structuredJSON
                    atom = atom.mergingMetadataKeys(overlay)
                }) {
                    mirrorByBookId[String(book.userBookId)] = updated
                    await RecallIndexer.shared.noteAtomChanged(updated)
                    booksTouched += 1
                }
            } else {
                var atom = Atom.new(type: .research, title: title, body: body)
                atom.structured = merged.structured.toJSON()
                atom = atom.mergingMetadataKeys(overlay)
                if let created = try? await AtomRepository.shared.create(atom) {
                    mirrorByBookId[String(book.userBookId)] = created
                    await RecallIndexer.shared.noteAtomChanged(created)
                    booksTouched += 1
                }
            }
        }

        if !mirrorFlagDone {
            await consolidateLegacyHighlightAtoms()
            await Self.writeFlag(Self.mirrorFlagKey)
        }

        // Cursor = the moment this pass STARTED, so highlights updated while
        // we paged are re-covered next pass instead of silently skipped.
        storedLastSyncDate = startedAt
        let mirrored = mirrorByBookId.values.reduce(0) { $0 + ($1.readwiseStructured?.highlights.count ?? 0) }
        storedHighlightCount = mirrored
        lastSyncDate = Date()
        highlightCount = mirrored

        print("Readwise mirror sync complete: \(booksTouched) sources touched, \(mirrored) highlights mirrored")
    }

    /// Launch + 6-hourly mirror passes. No-op without a token; the first
    /// pass defers so it never competes with interactive startup.
    func startAutoSync() {
        guard autoSyncTask == nil else { return }
        autoSyncTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            while !Task.isCancelled {
                if self?.isConnected == true, self?.isSyncing == false {
                    try? await self?.syncHighlights()
                }
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    /// The legacy pre-mirror shape: one `.research` atom per highlight
    /// (metadata.source == "readwise"). Their content now lives inside the
    /// complete book mirror — soft-delete them so the library and search
    /// stop double-serving every quote. Runs once, only after a FULL pass.
    private func consolidateLegacyHighlightAtoms() async {
        let legacy = ((try? await AtomRepository.shared.fetchAll(type: .research)) ?? [])
            .filter { $0.isReadwiseContent && !$0.isReadwiseMirror && !$0.isDeleted }
        guard !legacy.isEmpty else { return }
        for atom in legacy {
            try? await AtomRepository.shared.delete(uuid: atom.uuid)
        }
        print("Readwise mirror: consolidated \(legacy.count) legacy per-highlight atoms")
    }

    // MARK: - Mirror queries + flags

    static func mirrorAtoms() async -> [Atom] {
        ((try? await AtomRepository.shared.fetchAll(type: .research)) ?? [])
            .filter { $0.isReadwiseMirror && !$0.isDeleted }
    }

    private static let mirrorFlagKey = "readwise_book_mirror_v1"

    private static func readFlag(_ key: String) async -> Bool {
        ((try? await CosmoDatabase.shared.asyncRead { db in
            try Row.fetchOne(db, sql: "SELECT value FROM app_flags WHERE key = ?", arguments: [key]) != nil
        }) ?? false)
    }

    private static func writeFlag(_ key: String) async {
        try? await CosmoDatabase.shared.asyncWrite { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO app_flags (key, value, updated_at) VALUES (?, '1', ?)",
                arguments: [key, ISO8601.string(from: Date())]
            )
        }
    }

    // MARK: - Daily Review

    /// Fetch the daily review highlights from Readwise
    func getDailyReview() async -> [ReadwiseHighlight] {
        guard let token = apiToken, !token.isEmpty else { return [] }
        guard let url = URL(string: "\(baseURL)review/") else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return [] }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            // The review endpoint returns { highlights: [...] }
            struct ReviewResponse: Codable {
                let highlights: [ReadwiseHighlight]
            }

            let review = try decoder.decode(ReviewResponse.self, from: data)
            return review.highlights
        } catch {
            print("Failed to fetch Readwise daily review: \(error)")
            return []
        }
    }

    // MARK: - Export API (Books with Highlights)

    /// Raw export pages — the shared fetch behind both the browse cache and
    /// the mirror sync. `includeDeleted` only matters on incremental passes
    /// (the mirror prunes what Readwise removed).
    func fetchExportBooks(updatedAfter: Date? = nil, includeDeleted: Bool = false) async throws -> [ReadwiseExportBook] {
        guard let token = apiToken, !token.isEmpty else {
            throw ReadwiseError.noToken
        }

        var allExportBooks: [ReadwiseExportBook] = []
        var cursor: String? = nil
        var isFirstPage = true

        while isFirstPage || cursor != nil {
            isFirstPage = false

            var urlString = "\(baseURL)export/"
            var queryParams: [String] = []

            if let cursor {
                queryParams.append("pageCursor=\(cursor)")
            }
            if let updatedAfter {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                queryParams.append("updatedAfter=\(formatter.string(from: updatedAfter))")
            }
            if includeDeleted {
                queryParams.append("includeDeleted=true")
            }
            if !queryParams.isEmpty {
                urlString += "?" + queryParams.joined(separator: "&")
            }

            guard let url = URL(string: urlString) else {
                throw ReadwiseError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 30

            let (data, httpResponse) = try await withNetworkRetry(
                maxAttempts: 3,
                baseBackoff: 2.0,
                label: "ReadwiseExport"
            ) {
                try await URLSession.shared.data(for: request)
            }

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 {
                    isConnected = false
                    isTokenValid = false
                    throw ReadwiseError.unauthorized
                }
                throw ReadwiseError.httpError(httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let page = try decoder.decode(ReadwiseExportResponse.self, from: data)

            allExportBooks.append(contentsOf: page.results)
            cursor = page.nextPageCursor
        }

        return allExportBooks
    }

    /// Fetch all books with nested highlights via the Export API
    /// Returns ReadwiseLibraryBook models ready for the Library tab UI
    func fetchBooksWithHighlights(updatedAfter: Date? = nil) async throws -> [ReadwiseLibraryBook] {
        let allExportBooks = try await fetchExportBooks(updatedAfter: updatedAfter)

        // Convert to UI-ready models
        return allExportBooks.compactMap { exportBook -> ReadwiseLibraryBook? in
            let category = ReadwiseCategory(rawValue: exportBook.category ?? "books") ?? .books
            let activeHighlights = exportBook.highlights.filter { !($0.isDiscard ?? false) }

            let highlights = activeHighlights.map { h in
                ReadwiseLibraryHighlight(
                    id: h.id,
                    text: h.text,
                    note: h.note,
                    location: h.location,
                    color: h.color,
                    tags: h.tags?.map(\.name) ?? [],
                    bookId: h.bookId ?? exportBook.userBookId,
                    highlightedAt: h.highlightedAt
                )
            }

            guard !highlights.isEmpty else { return nil }

            return ReadwiseLibraryBook(
                id: exportBook.userBookId,
                title: exportBook.title,
                author: exportBook.author,
                category: category,
                coverImageUrl: exportBook.coverImageUrl,
                sourceUrl: exportBook.sourceUrl,
                numHighlights: highlights.count,
                highlights: highlights,
                bookTags: exportBook.bookTags?.map(\.name) ?? []
            )
        }
    }

}

// MARK: - Errors

enum ReadwiseError: LocalizedError {
    case noToken
    case invalidURL
    case invalidResponse
    case unauthorized
    case rateLimited
    case httpError(Int)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .noToken:
            return "No Readwise API token configured"
        case .invalidURL:
            return "Invalid Readwise API URL"
        case .invalidResponse:
            return "Invalid response from Readwise"
        case .unauthorized:
            return "Invalid Readwise API token"
        case .rateLimited:
            return "Readwise rate limit exceeded (25 requests/hour). Try again later."
        case .httpError(let code):
            return "Readwise API error (HTTP \(code))"
        case .decodingError(let error):
            return "Failed to decode Readwise response: \(error.localizedDescription)"
        }
    }
}
