// CosmoOS/Voice/VoiceUI/FloatingCardsController.swift
// Speculative UI controller for "Ghost Cards"
// Spawns cards BEFORE LLM completes for instant-feel experience
// Includes TTL safety valve to prevent zombie cards
// macOS 26+ optimized

import Foundation
import SwiftUI
import Combine

// MARK: - Ghost Card State

public enum GhostState: String, Sendable {
    case spawning      // 0-50ms: Empty glass card at predicted position
    case streaming     // 50-200ms: Title streaming in as STT finalizes
    case confirming    // 200-300ms: LLM confirms action, card solidifies
    case committed     // 300ms+: Card fully rendered with content
    case dismissed     // Card is being removed
}

// MARK: - Detected Intent

public struct DetectedIntent: Sendable, Identifiable {
    public let id = UUID()
    public let type: IntentType
    public let confidence: Double
    public let keywords: [String]
    public let nouns: [String]
    public let timestamp: Date

    public enum IntentType: String, Sendable {
        case create = "create"
        case search = "search"
        case navigate = "navigate"
        case modify = "modify"
        case delete = "delete"
        case arrange = "arrange"
        case unknown = "unknown"
    }

    public init(
        type: IntentType,
        confidence: Double,
        keywords: [String] = [],
        nouns: [String] = []
    ) {
        self.type = type
        self.confidence = confidence
        self.keywords = keywords
        self.nouns = nouns
        self.timestamp = Date()
    }

    /// Check if intent has enough context for speculative UI
    public var isActionable: Bool {
        confidence >= 0.6 && !nouns.isEmpty
    }
}

// MARK: - Ghost Card

public struct GhostCard: Identifiable, Sendable {
    public let id: UUID
    public var state: GhostState
    public var position: CGPoint
    public var size: CGSize
    public let intent: DetectedIntent
    public var streamingTitle: String
    public var streamingSubtitle: String?
    public var entityType: String?
    public var entityId: Int64?
    public var progress: Double  // 0.0 to 1.0
    public let createdAt: Date
    public var ttlExpiry: Date

    public init(
        id: UUID = UUID(),
        state: GhostState = .spawning,
        position: CGPoint,
        size: CGSize = CGSize(width: 280, height: 180),
        intent: DetectedIntent,
        streamingTitle: String = "",
        ttlSeconds: TimeInterval = 2.0
    ) {
        self.id = id
        self.state = state
        self.position = position
        self.size = size
        self.intent = intent
        self.streamingTitle = streamingTitle
        self.streamingSubtitle = nil
        self.entityType = nil
        self.entityId = nil
        self.progress = 0
        self.createdAt = Date()
        self.ttlExpiry = Date().addingTimeInterval(ttlSeconds)
    }

    /// Check if card has exceeded TTL
    public var isExpired: Bool {
        Date() > ttlExpiry
    }

    /// Time until expiry
    public var timeToLive: TimeInterval {
        max(0, ttlExpiry.timeIntervalSinceNow)
    }
}

// MARK: - Floating Cards Controller

@MainActor
public final class FloatingCardsController: ObservableObject {
    // MARK: - Singleton

    public static let shared = FloatingCardsController()

    // MARK: - Published State

    @Published public private(set) var ghostCards: [GhostCard] = []
    @Published public private(set) var activeCardId: UUID?
    @Published public private(set) var isShowingCards = false

    // MARK: - Configuration

    private let defaultTTL: TimeInterval = 2.0  // Zombie prevention
    private let maxConcurrentCards = 5
    private let spawnAnimationDuration: TimeInterval = 0.2
    private let dismissAnimationDuration: TimeInterval = 0.3

    // MARK: - TTL Management

    private var ttlTasks: [UUID: Task<Void, Never>] = [:]
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Canvas Reference

    private var canvasSize: CGSize = CGSize(width: 1200, height: 800)

    // MARK: - Initialization

    private init() {
        setupNotificationObservers()
    }

    // MARK: - Card Spawning

    /// Spawn a ghost card from detected intent
    public func spawnGhostCard(
        intent: DetectedIntent,
        predictedPosition: CGPoint? = nil
    ) {
        // Limit concurrent cards
        guard ghostCards.count < maxConcurrentCards else {
            print("FloatingCardsController: Max concurrent cards reached")
            return
        }

        // Calculate position
        let position = predictedPosition ?? calculateSpawnPosition(for: intent)

        // Create card
        let card = GhostCard(
            state: .spawning,
            position: position,
            intent: intent,
            ttlSeconds: defaultTTL
        )

        // Add with animation
        withAnimation(.spring(response: spawnAnimationDuration, dampingFraction: 0.8)) {
            ghostCards.append(card)
            isShowingCards = true
        }

        // Start TTL timer
        startTTLTimer(for: card.id)

        // Post notification
        NotificationCenter.default.post(
            name: .ghostCardSpawned,
            object: nil,
            userInfo: ["cardId": card.id, "intent": intent.type.rawValue]
        )

        print("FloatingCardsController: Spawned ghost card (intent: \(intent.type))")
    }

    /// Spawn multiple ghost cards for search results
    public func spawnGhostCards(for searchResults: [VectorSearchResult]) {
        let availableSlots = maxConcurrentCards - ghostCards.count
        let resultsToShow = Array(searchResults.prefix(availableSlots))

        for (index, result) in resultsToShow.enumerated() {
            let intent = DetectedIntent(
                type: .search,
                confidence: Double(result.similarity),
                keywords: [],
                nouns: [result.text ?? result.entityType]
            )

            let position = calculateGridPosition(index: index, total: resultsToShow.count)

            var card = GhostCard(
                state: .streaming,
                position: position,
                intent: intent,
                streamingTitle: result.text?.prefix(50).description ?? "Result",
                ttlSeconds: defaultTTL
            )
            card.entityType = result.entityType
            card.entityId = result.entityId

            withAnimation(.spring(response: spawnAnimationDuration, dampingFraction: 0.8).delay(Double(index) * 0.05)) {
                ghostCards.append(card)
            }

            startTTLTimer(for: card.id)
        }

        if !resultsToShow.isEmpty {
            isShowingCards = true
            print("FloatingCardsController: Spawned \(resultsToShow.count) search result cards")
        }
    }

    // MARK: - Card Updates

    /// Update streaming content on a card
    public func updateStreaming(cardId: UUID, title: String, subtitle: String? = nil) {
        guard let index = ghostCards.firstIndex(where: { $0.id == cardId }) else {
            return
        }

        ghostCards[index].streamingTitle = title
        ghostCards[index].streamingSubtitle = subtitle

        if ghostCards[index].state == .spawning {
            ghostCards[index].state = .streaming
        }

        // Reset TTL when we get updates
        resetTTL(for: cardId)
    }

    /// Update progress on a card
    public func updateProgress(cardId: UUID, progress: Double) {
        guard let index = ghostCards.firstIndex(where: { $0.id == cardId }) else {
            return
        }

        ghostCards[index].progress = min(1.0, max(0.0, progress))

        // Reset TTL on progress updates
        resetTTL(for: cardId)
    }

    /// Transition card to confirming state
    public func confirmCard(cardId: UUID, entityType: String? = nil, entityId: Int64? = nil) {
        guard let index = ghostCards.firstIndex(where: { $0.id == cardId }) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.15)) {
            ghostCards[index].state = .confirming
            ghostCards[index].entityType = entityType
            ghostCards[index].entityId = entityId
        }

        // Extend TTL during confirmation
        extendTTL(for: cardId, by: 1.0)
    }

    /// Commit card - transition from ghost to real block
    public func commitCard(cardId: UUID, block: Any) {  // Would be CanvasBlock type
        // Cancel TTL - card is being committed
        ttlTasks[cardId]?.cancel()
        ttlTasks[cardId] = nil

        guard let index = ghostCards.firstIndex(where: { $0.id == cardId }) else {
            return
        }

        withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
            ghostCards[index].state = .committed
            ghostCards[index].progress = 1.0
        }

        // Post notification for SpatialEngine to add real block
        NotificationCenter.default.post(
            name: .commitGhostCard,
            object: nil,
            userInfo: [
                "block": block,
                "ghostId": cardId,
                "position": ghostCards[index].position
            ]
        )

        // Remove ghost card after short delay (real block replaces it)
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            await MainActor.run {
                self.removeCard(cardId)
            }
        }

        print("FloatingCardsController: Committed card \(cardId)")
    }

    // MARK: - Card Dismissal

    /// Dismiss a specific ghost card
    public func dismissGhostCard(_ cardId: UUID) {
        ttlTasks[cardId]?.cancel()
        ttlTasks[cardId] = nil

        guard let index = ghostCards.firstIndex(where: { $0.id == cardId }) else {
            return
        }

        withAnimation(.easeOut(duration: dismissAnimationDuration)) {
            ghostCards[index].state = .dismissed
        }

        // Remove after animation
        Task {
            try? await Task.sleep(for: .milliseconds(Int(dismissAnimationDuration * 1000)))
            await MainActor.run {
                self.removeCard(cardId)
            }
        }
    }

    /// Dismiss all ghost cards
    public func dismissAllCards() {
        for cardId in ghostCards.map(\.id) {
            dismissGhostCard(cardId)
        }
    }

    /// Remove card immediately (internal)
    private func removeCard(_ cardId: UUID) {
        ghostCards.removeAll { $0.id == cardId }
        ttlTasks[cardId]?.cancel()
        ttlTasks[cardId] = nil

        if ghostCards.isEmpty {
            isShowingCards = false
        }
    }

    // MARK: - TTL Management (Zombie Prevention)

    private func startTTLTimer(for cardId: UUID) {
        ttlTasks[cardId]?.cancel()

        ttlTasks[cardId] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.defaultTTL ?? 2.0))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                // Only dismiss if still in spawning/streaming state
                if let index = self?.ghostCards.firstIndex(where: { $0.id == cardId }),
                   self?.ghostCards[index].state == .spawning || self?.ghostCards[index].state == .streaming {
                    print("FloatingCardsController: TTL expired for card \(cardId)")
                    self?.dismissGhostCard(cardId)
                }
            }
        }
    }

    private func resetTTL(for cardId: UUID) {
        guard let index = ghostCards.firstIndex(where: { $0.id == cardId }) else {
            return
        }

        // Update expiry time
        ghostCards[index].ttlExpiry = Date().addingTimeInterval(defaultTTL)

        // Restart timer
        startTTLTimer(for: cardId)
    }

    private func extendTTL(for cardId: UUID, by seconds: TimeInterval) {
        guard let index = ghostCards.firstIndex(where: { $0.id == cardId }) else {
            return
        }

        ghostCards[index].ttlExpiry = ghostCards[index].ttlExpiry.addingTimeInterval(seconds)
        startTTLTimer(for: cardId)
    }

    // MARK: - Position Calculation

    private func calculateSpawnPosition(for intent: DetectedIntent) -> CGPoint {
        // Center by default, offset based on existing cards
        let baseX = canvasSize.width / 2
        let baseY = canvasSize.height / 2

        // Offset based on current card count
        let offset = CGFloat(ghostCards.count) * 30

        return CGPoint(
            x: baseX + offset,
            y: baseY + offset
        )
    }

    private func calculateGridPosition(index: Int, total: Int) -> CGPoint {
        let columns = min(total, 3)
        let col = index % columns
        let row = index / columns

        let cardWidth: CGFloat = 280
        let cardHeight: CGFloat = 180
        let spacing: CGFloat = 20

        let totalWidth = CGFloat(columns) * cardWidth + CGFloat(columns - 1) * spacing
        let startX = (canvasSize.width - totalWidth) / 2

        let x = startX + CGFloat(col) * (cardWidth + spacing) + cardWidth / 2
        let y = canvasSize.height / 2 + CGFloat(row) * (cardHeight + spacing)

        return CGPoint(x: x, y: y)
    }

    // MARK: - Canvas Integration

    public func setCanvasSize(_ size: CGSize) {
        canvasSize = size
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        // Listen for ASR intent detection
        NotificationCenter.default.publisher(for: .asrIntentDetected)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let text = notification.userInfo?["text"] as? String,
                      let wordCount = notification.userInfo?["wordCount"] as? Int,
                      let confidence = notification.userInfo?["confidence"] as? Double else {
                    return
                }

                // Parse intent from text
                let intent = self?.parseIntent(from: text, confidence: confidence, wordCount: wordCount)
                if let intent = intent, intent.isActionable {
                    self?.spawnGhostCard(intent: intent)
                }
            }
            .store(in: &cancellables)

        // Listen for L1 partial transcripts
        NotificationCenter.default.publisher(for: .l1PartialTranscript)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let text = notification.userInfo?["text"] as? String else {
                    return
                }

                // Update active card if we have one
                if let activeId = self?.activeCardId {
                    self?.updateStreaming(cardId: activeId, title: text)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Intent Parsing

    private func parseIntent(from text: String, confidence: Double, wordCount: Int) -> DetectedIntent? {
        let lowercased = text.lowercased()
        var intentType: DetectedIntent.IntentType = .unknown
        var keywords: [String] = []
        var nouns: [String] = []

        // Simple keyword-based intent detection
        if lowercased.contains("create") || lowercased.contains("new") || lowercased.contains("add") {
            intentType = .create
            keywords = ["create", "new", "add"]
        } else if lowercased.contains("search") || lowercased.contains("find") || lowercased.contains("show") {
            intentType = .search
            keywords = ["search", "find", "show"]
        } else if lowercased.contains("go to") || lowercased.contains("open") || lowercased.contains("navigate") {
            intentType = .navigate
            keywords = ["go to", "open", "navigate"]
        } else if lowercased.contains("move") || lowercased.contains("arrange") || lowercased.contains("organize") {
            intentType = .arrange
            keywords = ["move", "arrange", "organize"]
        } else if lowercased.contains("delete") || lowercased.contains("remove") {
            intentType = .delete
            keywords = ["delete", "remove"]
        } else if lowercased.contains("change") || lowercased.contains("update") || lowercased.contains("edit") {
            intentType = .modify
            keywords = ["change", "update", "edit"]
        }

        // Extract potential nouns (simple heuristic)
        let words = text.split(separator: " ")
        nouns = words.filter { word in
            let w = word.lowercased()
            return !["the", "a", "an", "to", "in", "on", "at", "for", "with", "please", "can", "you", "i", "my"].contains(w)
        }.map(String.init)

        return DetectedIntent(
            type: intentType,
            confidence: confidence,
            keywords: keywords,
            nouns: Array(nouns.suffix(5))  // Last 5 nouns
        )
    }

    deinit {
        for task in ttlTasks.values {
            task.cancel()
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let ghostCardSpawned = Notification.Name("com.cosmo.ghostCardSpawned")
    static let commitGhostCard = Notification.Name("com.cosmo.commitGhostCard")
    static let ghostCardDismissed = Notification.Name("com.cosmo.ghostCardDismissed")
}
