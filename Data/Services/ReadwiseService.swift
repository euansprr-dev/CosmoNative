// CosmoOS/Data/Services/ReadwiseService.swift
// Placeholder for Readwise API integration
// Future: sync highlights from books/articles into CosmoOS knowledge graph

import Foundation

@MainActor
class ReadwiseService: ObservableObject {
    static let shared = ReadwiseService()

    @Published var isConnected: Bool = false
    @Published var highlightCount: Int = 0
    @Published var lastSyncDate: Date?

    private var apiToken: String? {
        get { UserDefaults.standard.string(forKey: "readwiseAPIToken") }
        set { UserDefaults.standard.set(newValue, forKey: "readwiseAPIToken") }
    }

    private init() {
        isConnected = apiToken != nil
    }

    func connect(token: String) {
        self.apiToken = token
        isConnected = true
    }

    func disconnect() {
        self.apiToken = nil
        isConnected = false
        highlightCount = 0
        lastSyncDate = nil
    }

    func syncHighlights() async {
        guard apiToken != nil else { return }
        // Placeholder: will call Readwise API v2
        // GET https://readwise.io/api/v2/highlights/
        // Each highlight -> .research atom with metadata
    }

    func getDailyReview() async -> [String] {
        // Return 5 random highlights for spaced repetition
        return []
    }
}
