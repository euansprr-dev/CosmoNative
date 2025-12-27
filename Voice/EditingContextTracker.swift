// CosmoOS/Voice/EditingContextTracker.swift
// Real-time editing awareness for telepathic voice assistant
// Tracks what the user is actively working on for context-aware search

import Foundation
import Combine

/// Tracks the user's current editing context for context-aware voice queries
/// Updates embeddings on debounce to provide real-time semantic understanding
@MainActor
final class EditingContextTracker: ObservableObject {
    static let shared = EditingContextTracker()

    // MARK: - Current Editing State

    /// The type of entity currently being edited
    @Published private(set) var activeEntityType: EntityType?

    /// The ID of the entity currently being edited
    @Published private(set) var activeEntityId: Int64?

    /// UUID of the entity being edited (for sync compatibility)
    @Published private(set) var activeEntityUUID: String?

    /// The title of the entity being edited
    @Published private(set) var activeTitle: String = ""

    /// The full content being edited
    @Published private(set) var activeContent: String = ""

    /// Text around the cursor (±200 characters)
    @Published private(set) var cursorContext: String = ""

    /// Current cursor position in the content
    @Published private(set) var cursorPosition: Int = 0

    // MARK: - Computed Context

    /// Pre-computed embedding vector for the editing context
    /// Updated on debounce (500ms after typing stops)
    @Published private(set) var contextVector: [Float]?

    /// Key concepts extracted from the editing context
    @Published private(set) var extractedConcepts: [String] = []

    /// Whether the context vector is currently being updated
    @Published private(set) var isUpdatingContext: Bool = false

    /// Last time context was updated
    @Published private(set) var lastContextUpdate: Date?

    // MARK: - Configuration

    /// Debounce delay for context updates (ms)
    private let contextUpdateDebounce: UInt64 = 500_000_000  // 500ms in nanoseconds

    /// Characters to extract around cursor for immediate context
    private let cursorContextRadius = 200

    /// Minimum content length to trigger context embedding
    private let minContentForEmbedding = 20

    // MARK: - Private

    private var updateTask: Task<Void, Never>?
    private let mlxService = MLXEmbeddingService.shared

    private init() {}

    // MARK: - Update Editing Context

    /// Update the current editing context when user types or switches entities
    /// - Parameters:
    ///   - entityType: Type of entity being edited
    ///   - entityId: Database ID of the entity
    ///   - entityUUID: UUID of the entity (for sync)
    ///   - title: Title of the entity
    ///   - content: Full content being edited
    ///   - cursorPosition: Current cursor position in content
    func updateEditingContext(
        entityType: EntityType,
        entityId: Int64,
        entityUUID: String? = nil,
        title: String,
        content: String,
        cursorPosition: Int
    ) {
        // Check if we switched to a different entity
        let entityChanged = activeEntityType != entityType || activeEntityId != entityId

        // Update state
        activeEntityType = entityType
        activeEntityId = entityId
        activeEntityUUID = entityUUID
        activeTitle = title
        activeContent = content
        self.cursorPosition = cursorPosition

        // Extract cursor context immediately (fast, no async)
        cursorContext = extractCursorContext(from: content, position: cursorPosition)

        // If entity changed, clear old context and update immediately
        if entityChanged {
            contextVector = nil
            extractedConcepts = []
            Task {
                await updateContextVectorImmediately()
            }
            return
        }

        // Debounce context vector updates for typing
        updateTask?.cancel()
        updateTask = Task {
            do {
                try await Task.sleep(nanoseconds: contextUpdateDebounce)
                await updateContextVector()
            } catch {
                // Task was cancelled (user kept typing)
            }
        }
    }

    /// Clear editing context (when user closes editor)
    func clearEditingContext() {
        updateTask?.cancel()

        activeEntityType = nil
        activeEntityId = nil
        activeEntityUUID = nil
        activeTitle = ""
        activeContent = ""
        cursorContext = ""
        cursorPosition = 0
        contextVector = nil
        extractedConcepts = []
        lastContextUpdate = nil
    }

    // MARK: - Context Vector Update

    /// Update context vector immediately (for entity switches)
    private func updateContextVectorImmediately() async {
        await updateContextVector()
    }

    /// Update the context embedding vector
    private func updateContextVector() async {
        // Build context text: prioritize title + cursor context for relevance
        let contextText = buildContextText()

        guard contextText.count >= minContentForEmbedding else {
            // Not enough content for meaningful embedding
            contextVector = nil
            return
        }

        isUpdatingContext = true
        defer { isUpdatingContext = false }

        do {
            // Generate embedding for context
            let embedding = try await mlxService.embed(contextText)
            contextVector = embedding
            lastContextUpdate = Date()

            // Extract concepts (simple keyword extraction)
            extractedConcepts = extractKeywords(from: contextText)

            print("📝 Context updated: \(extractedConcepts.prefix(3).joined(separator: ", "))")

        } catch {
            print("⚠️ Context embedding failed: \(error.localizedDescription)")
            // Keep existing context vector if update fails
        }
    }

    // MARK: - Context Text Building

    /// Build the text used for context embedding
    /// Prioritizes title + cursor context for focused relevance
    private func buildContextText() -> String {
        var parts: [String] = []

        // Title is high-signal
        if !activeTitle.isEmpty {
            parts.append(activeTitle)
        }

        // Cursor context gives immediate focus
        if !cursorContext.isEmpty {
            parts.append(cursorContext)
        }

        // If cursor context is small, add more content
        if cursorContext.count < 100 && !activeContent.isEmpty {
            // Add first 500 chars of content
            parts.append(String(activeContent.prefix(500)))
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Cursor Context Extraction

    /// Extract text around the cursor position
    private func extractCursorContext(from content: String, position: Int) -> String {
        guard !content.isEmpty else { return "" }

        let nsContent = content as NSString
        let length = nsContent.length

        // Clamp position to valid range
        let safePosition = max(0, min(position, length))

        // Calculate range
        let startPos = max(0, safePosition - cursorContextRadius)
        let endPos = min(length, safePosition + cursorContextRadius)

        // Extract substring
        let range = NSRange(location: startPos, length: endPos - startPos)
        let extracted = nsContent.substring(with: range)

        // Find word boundaries to avoid cutting words
        return trimToWordBoundaries(extracted)
    }

    /// Trim string to word boundaries
    private func trimToWordBoundaries(_ text: String) -> String {
        var result = text

        // Trim leading partial word
        if let firstSpace = result.firstIndex(of: " ") {
            let prefix = result[..<firstSpace]
            if !prefix.isEmpty && !CharacterSet.letters.isSuperset(of: CharacterSet(charactersIn: String(prefix.first!))) {
                result = String(result[result.index(after: firstSpace)...])
            }
        }

        // Trim trailing partial word
        if let lastSpace = result.lastIndex(of: " ") {
            let suffix = result[result.index(after: lastSpace)...]
            if !suffix.isEmpty && suffix.last?.isPunctuation == false {
                result = String(result[..<lastSpace])
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Keyword Extraction

    /// Extract key concepts/keywords from text
    /// Simple approach: most frequent non-stopword terms
    private func extractKeywords(from text: String) -> [String] {
        // Stopwords to filter out
        let stopwords: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did", "will", "would", "could",
            "should", "may", "might", "must", "shall", "can", "to", "of", "in",
            "for", "on", "with", "at", "by", "from", "as", "into", "through",
            "during", "before", "after", "above", "below", "between", "under",
            "again", "further", "then", "once", "here", "there", "when", "where",
            "why", "how", "all", "each", "few", "more", "most", "other", "some",
            "such", "no", "nor", "not", "only", "own", "same", "so", "than",
            "too", "very", "just", "and", "but", "if", "or", "because", "until",
            "while", "this", "that", "these", "those", "i", "you", "he", "she",
            "it", "we", "they", "what", "which", "who", "whom", "my", "your",
            "his", "her", "its", "our", "their", "about", "also"
        ]

        // Tokenize and count
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { word in
                word.count >= 3 &&
                !stopwords.contains(word) &&
                !word.allSatisfy { $0.isNumber }
            }

        // Count frequencies
        var frequencies: [String: Int] = [:]
        for word in words {
            frequencies[word, default: 0] += 1
        }

        // Sort by frequency and return top keywords
        let sorted = frequencies.sorted { $0.value > $1.value }
        return sorted.prefix(10).map { $0.key }
    }

    // MARK: - Snapshot

    /// Get current editing context for voice command routing
    func snapshot() -> EditingContextSnapshot {
        EditingContextSnapshot(
            entityType: activeEntityType,
            entityId: activeEntityId,
            entityUUID: activeEntityUUID,
            title: activeTitle,
            cursorContext: cursorContext,
            extractedConcepts: extractedConcepts,
            contextVector: contextVector,
            lastUpdate: lastContextUpdate
        )
    }
}

// MARK: - Editing Context Snapshot

/// Sendable snapshot of editing context for voice command routing
struct EditingContextSnapshot: Sendable {
    let entityType: EntityType?
    let entityId: Int64?
    let entityUUID: String?
    let title: String?
    let cursorContext: String?
    let extractedConcepts: [String]
    let contextVector: [Float]?
    let lastUpdate: Date?

    /// Whether there's active editing context
    var hasContext: Bool {
        entityType != nil && entityId != nil
    }

    /// Whether the context vector is available
    var hasVector: Bool {
        contextVector != nil && !(contextVector?.isEmpty ?? true)
    }

    /// Combined text for fallback queries
    var combinedText: String {
        [title, cursorContext]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
