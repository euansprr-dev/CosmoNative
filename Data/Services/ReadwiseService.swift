// CosmoOS/Data/Services/ReadwiseService.swift
// Real Readwise API v2 integration
// Syncs highlights from books/articles into CosmoOS knowledge graph as .research atoms

import Foundation

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

    // Book metadata cache (keyed by book ID)
    private var bookCache: [Int: ReadwiseBook] = [:]

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
        bookCache = [:]
    }

    // MARK: - Sync Highlights

    /// Full sync: fetches highlights from Readwise and creates .research atoms in GRDB
    /// Uses incremental sync if lastSyncDate is available
    func syncHighlights() async throws {
        guard let token = apiToken, !token.isEmpty else {
            throw ReadwiseError.noToken
        }

        isSyncing = true
        syncError = nil

        defer {
            Task { @MainActor in
                self.isSyncing = false
            }
        }

        // First sync books for metadata enrichment
        try await syncBooks()

        // Build initial URL with pagination
        var urlString = "\(baseURL)highlights/?page_size=1000"

        // Incremental sync: only fetch highlights updated after last sync
        if let lastSync = storedLastSyncDate {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let dateStr = formatter.string(from: lastSync)
            urlString += "&updated__gt=\(dateStr)"
        }

        var allHighlights: [ReadwiseHighlight] = []
        var nextURL: String? = urlString

        // Paginate through all results
        while let currentURL = nextURL {
            let (highlights, next) = try await fetchHighlightsPage(urlString: currentURL, token: token)
            allHighlights.append(contentsOf: highlights)
            nextURL = next
        }

        // Get existing Readwise IDs to detect duplicates
        let existingIds = await getExistingReadwiseIds()

        // Create atoms for new highlights
        var newCount = 0
        let repo = AtomRepository.shared

        for highlight in allHighlights {
            let readwiseId = String(highlight.id)

            // Skip duplicates
            if existingIds.contains(readwiseId) {
                continue
            }

            // Look up book metadata
            let book = highlight.bookId.flatMap { bookCache[$0] }

            // Build structured JSON
            var structuredDict: [String: Any] = [
                "readwiseId": readwiseId
            ]
            if let note = highlight.note, !note.isEmpty {
                structuredDict["note"] = note
            }
            if let bookTitle = book?.title {
                structuredDict["bookTitle"] = bookTitle
            }
            if let author = book?.author {
                structuredDict["author"] = author
            }
            if let category = book?.category {
                structuredDict["category"] = category
            }
            if let highlightedAt = highlight.highlightedAt {
                structuredDict["highlightedAt"] = highlightedAt
            }
            if let sourceUrl = highlight.url ?? book?.sourceUrl {
                structuredDict["sourceUrl"] = sourceUrl
            }
            if let tags = highlight.tags, !tags.isEmpty {
                structuredDict["tags"] = tags.map { $0.name }
            }

            let structuredJson = try? JSONSerialization.data(withJSONObject: structuredDict)
            let structuredString = structuredJson.flatMap { String(data: $0, encoding: .utf8) }

            // Build metadata JSON
            var metadataDict: [String: Any] = [
                "source": "readwise",
                "readwiseId": readwiseId,
                "researchType": "highlight"
            ]
            if let bookId = highlight.bookId {
                metadataDict["bookId"] = bookId
            }
            if let sourceUrl = highlight.url ?? book?.sourceUrl {
                metadataDict["sourceUrl"] = sourceUrl
            }

            let metadataJson = try? JSONSerialization.data(withJSONObject: metadataDict)
            let metadataString = metadataJson.flatMap { String(data: $0, encoding: .utf8) }

            // Compose title from book info
            let title: String
            if let bookTitle = book?.title {
                let authorSuffix = book?.author.map { " — \($0)" } ?? ""
                title = "\(bookTitle)\(authorSuffix)"
            } else {
                title = "Readwise Highlight"
            }

            do {
                try await repo.create(
                    type: .research,
                    title: title,
                    body: highlight.text,
                    structured: structuredString,
                    metadata: metadataString
                )
                newCount += 1
            } catch {
                print("Failed to create atom for Readwise highlight \(highlight.id): \(error)")
            }
        }

        // Update sync state
        let totalCount = existingIds.count + newCount
        storedLastSyncDate = Date()
        storedHighlightCount = totalCount
        lastSyncDate = storedLastSyncDate
        highlightCount = totalCount

        print("Readwise sync complete: \(newCount) new highlights, \(totalCount) total")
    }

    // MARK: - Sync Books

    /// Fetch all books from Readwise and cache metadata
    func syncBooks() async throws {
        guard let token = apiToken, !token.isEmpty else {
            throw ReadwiseError.noToken
        }

        var nextURL: String? = "\(baseURL)books/?page_size=1000"

        while let currentURL = nextURL {
            guard let url = URL(string: currentURL) else { break }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 30

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ReadwiseError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 {
                    throw ReadwiseError.unauthorized
                }
                if httpResponse.statusCode == 429 {
                    throw ReadwiseError.rateLimited
                }
                throw ReadwiseError.httpError(httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let page = try decoder.decode(ReadwisePaginatedResponse<ReadwiseBook>.self, from: data)

            for book in page.results {
                bookCache[book.id] = book
            }

            nextURL = page.next
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

    // MARK: - Private Helpers

    /// Fetch a single page of highlights
    private func fetchHighlightsPage(urlString: String, token: String) async throws -> ([ReadwiseHighlight], String?) {
        guard let url = URL(string: urlString) else {
            throw ReadwiseError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReadwiseError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                isConnected = false
                isTokenValid = false
                throw ReadwiseError.unauthorized
            }
            if httpResponse.statusCode == 429 {
                throw ReadwiseError.rateLimited
            }
            throw ReadwiseError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let page = try decoder.decode(ReadwisePaginatedResponse<ReadwiseHighlight>.self, from: data)

        return (page.results, page.next)
    }

    /// Get all existing Readwise highlight IDs from GRDB to avoid duplicates
    private func getExistingReadwiseIds() async -> Set<String> {
        do {
            let atoms = try await AtomRepository.shared.search(
                metadataKey: "source",
                value: "readwise",
                type: .research
            )
            var ids = Set<String>()
            for atom in atoms {
                if let metadataStr = atom.metadata,
                   let data = metadataStr.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let readwiseId = dict["readwiseId"] as? String {
                    ids.insert(readwiseId)
                } else if let metadataStr = atom.metadata,
                          let data = metadataStr.data(using: .utf8),
                          let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let readwiseId = dict["readwiseId"] as? Int {
                    ids.insert(String(readwiseId))
                }
            }
            return ids
        } catch {
            print("Failed to fetch existing Readwise IDs: \(error)")
            return []
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
