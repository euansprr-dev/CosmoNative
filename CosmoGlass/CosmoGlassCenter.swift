// CosmoOS/CosmoGlass/CosmoGlassCenter.swift
// Central coordinator for glass overlay cards
// Manages presentation, dismissal, selection, and auto-dismiss timers

import Foundation
import SwiftUI
import Combine

@MainActor
final class CosmoGlassCenter: ObservableObject {
    static let shared = CosmoGlassCenter()

    // MARK: - Published State

    /// Currently displayed glass cards (max 5 visible at once)
    @Published private(set) var cards: [CosmoGlassCard] = []

    /// Selection context for voice follow-ups ("place this one", "the second one")
    @Published var selection: GlassSelectionContext = GlassSelectionContext()

    /// Whether the glass overlay is visible
    @Published var isVisible: Bool = false

    /// Current streaming content for AI response
    @Published var streamingContent: String = ""
    @Published var isStreaming: Bool = false
    private var streamingCardId: String?

    // MARK: - Configuration

    private let maxVisibleCards = 5
    private var autoDismissTimers: [String: AnyCancellable] = [:]

    private init() {
        setupGeminiObserver()
        print("✅ CosmoGlassCenter initialized")
    }

    // MARK: - Gemini Observer

    /// Listen for Gemini processing events (start, stream, complete)
    private func setupGeminiObserver() {
        // Listen for processing STARTED - create empty streaming card
        NotificationCenter.default.addObserver(
            forName: CosmoNotification.AI.geminiProcessingStarted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                let query = notification.userInfo?["query"] as? String ?? ""
                self?.startStreamingResponse(query: query)
            }
        }

        // Listen for STREAM CHUNKS - update card content
        NotificationCenter.default.addObserver(
            forName: CosmoNotification.AI.geminiStreamChunk,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let chunk = notification.userInfo?["chunk"] as? String else { return }
                self?.appendStreamingContent(chunk)
            }
        }

        // Listen for processing COMPLETED - finalize the card
        NotificationCenter.default.addObserver(
            forName: CosmoNotification.AI.geminiProcessingCompleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                let content = notification.userInfo?["content"] as? String
                self?.finalizeStreamingResponse(finalContent: content)
            }
        }

        // Listen for processing FAILED - show error state
        NotificationCenter.default.addObserver(
            forName: CosmoNotification.AI.geminiProcessingFailed,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                let error = notification.userInfo?["error"] as? String ?? "Unknown error"
                self?.handleStreamingError(error: error)
            }
        }
    }

    // MARK: - Streaming Methods

    /// Start a new streaming AI response
    private func startStreamingResponse(query: String) {
        streamingContent = ""
        isStreaming = true

        // Create streaming card with fixed ID
        let card = CosmoGlassCard.streamingAIResponse(query: query)
        streamingCardId = card.id
        present(card)
        print("🧠 Started streaming AI response")
    }

    /// Append chunk to streaming content
    private func appendStreamingContent(_ chunk: String) {
        streamingContent += chunk

        // Update the card's message
        if let cardId = streamingCardId,
           let index = cards.firstIndex(where: { $0.id == cardId }) {
            cards[index].message = streamingContent
        }
    }

    /// Finalize the streaming response
    private func finalizeStreamingResponse(finalContent: String?) {
        isStreaming = false

        // If final content provided, use it (may be cleaned up version)
        if let final = finalContent {
            streamingContent = final
            if let cardId = streamingCardId,
               let index = cards.firstIndex(where: { $0.id == cardId }) {
                cards[index].message = final
            }
        }

        streamingCardId = nil
        print("🧠 Finalized streaming AI response (\(streamingContent.count) chars)")
    }

    /// Handle streaming error
    private func handleStreamingError(error: String) {
        isStreaming = false

        if let cardId = streamingCardId,
           let index = cards.firstIndex(where: { $0.id == cardId }) {
            cards[index].message = "⚠️ " + error
        }

        streamingCardId = nil
        print("🧠 Streaming error: \(error)")
    }

    // MARK: - Present Cards

    /// Present a new glass card
    func present(_ card: CosmoGlassCard) {
        // Remove existing card with same ID if present
        cards.removeAll { $0.id == card.id }

        // Insert at front (newest first)
        cards.insert(card, at: 0)

        // Limit visible cards
        if cards.count > maxVisibleCards {
            let removed = cards.removeLast()
            cancelAutoDismissTimer(for: removed.id)
        }

        // Update selection context for search results
        if card.type == .searchResults && !card.entities.isEmpty {
            selection = GlassSelectionContext(
                activeCardId: card.id,
                lastResultEntities: card.entities,
                selectedIndex: 0
            )

            // Also update VoiceContextStore for voice follow-ups
            VoiceContextStore.shared.setGlassResults(card.entities)

            // Post notification for observers
            NotificationCenter.default.post(
                name: .glassCardPresented,
                object: nil,
                userInfo: ["cardId": card.id, "cardType": card.type.rawValue]
            )
        }

        // Setup auto-dismiss timer if configured
        if card.autoDismissAfter > 0 {
            setupAutoDismissTimer(for: card)
        }

        isVisible = true

        print("🔔 Glass card presented: \(card.type.rawValue) - \(card.title)")
    }

    /// Present search results as a glass card
    func presentSearchResults(title: String, entities: [CosmoGlassEntityRef]) {
        let card = CosmoGlassCard.searchResults(title: title, entities: entities)
        present(card)
    }

    /// Present a clarification request
    func presentClarification(question: String, options: [CosmoGlassClarificationOption]) {
        let card = CosmoGlassCard.clarification(question: question, options: options)
        present(card)
    }

    /// Present research progress
    func presentResearch(query: String) -> String {
        let card = CosmoGlassCard.research(query: query)
        present(card)
        return card.id
    }

    /// Update research progress
    func updateResearchProgress(cardId: String, progress: Double, findings: [CosmoGlassResearchFinding] = [], isComplete: Bool = false) {
        guard let index = cards.firstIndex(where: { $0.id == cardId }) else { return }

        cards[index].researchProgress = progress
        cards[index].researchFindings = findings
        cards[index].isResearchComplete = isComplete

        if isComplete {
            cards[index].autoDismissAfter = 30
            setupAutoDismissTimer(for: cards[index])
        }
    }

    /// Present a proactive suggestion
    func presentProactive(title: String, message: String, entityType: String? = nil, entityId: Int64? = nil) {
        let card = CosmoGlassCard.proactive(
            title: title,
            message: message,
            entityType: entityType,
            entityId: entityId
        )
        present(card)
    }

    /// Present a system notification mirrored into glass
    func presentNotification(title: String, message: String, entityType: String, entityId: Int64) {
        let card = CosmoGlassCard.notification(
            title: title,
            message: message,
            entityType: entityType,
            entityId: entityId
        )
        present(card)
    }

    /// Present an AI response from Gemini synthesis
    func presentAIResponse(query: String, response: String, sourceCount: Int = 0) {
        let card = CosmoGlassCard.aiResponse(
            query: query,
            response: response,
            sourceCount: sourceCount
        )
        present(card)
        print("🧠 AI response card presented")
    }

    // MARK: - Dismiss Cards

    /// Dismiss a specific card by ID
    func dismiss(id: String) {
        cancelAutoDismissTimer(for: id)

        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            cards.removeAll { $0.id == id }

            // Clear selection if dismissed card was active
            if selection.activeCardId == id {
                selection = GlassSelectionContext()
            }

            if cards.isEmpty {
                isVisible = false
            }
        }

        print("🔔 Glass card dismissed: \(id)")
    }

    /// Dismiss all cards of a specific type
    func clear(type: CosmoGlassCardType) {
        let idsToRemove = cards.filter { $0.type == type }.map { $0.id }
        for id in idsToRemove {
            cancelAutoDismissTimer(for: id)
        }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            cards.removeAll { $0.type == type }

            if cards.isEmpty {
                isVisible = false
                selection = GlassSelectionContext()
            }
        }
    }

    /// Dismiss all cards
    func clearAll() {
        for card in cards {
            cancelAutoDismissTimer(for: card.id)
        }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            cards.removeAll()
            selection = GlassSelectionContext()
            isVisible = false
        }

        // Clear voice context glass results
        VoiceContextStore.shared.clearGlassResults()
    }

    // MARK: - Selection

    /// Select an item in the current results
    func select(index: Int) {
        guard selection.isValid, index >= 0, index < selection.lastResultEntities.count else { return }
        selection.selectedIndex = index
    }

    /// Select by entity ID
    func select(entityId: String) {
        guard selection.isValid else { return }
        if let index = selection.lastResultEntities.firstIndex(where: { $0.id == entityId }) {
            selection.selectedIndex = index
        }
    }

    /// Get entity by ordinal ("first", "second", etc.)
    func entityByOrdinal(_ ordinal: Int) -> CosmoGlassEntityRef? {
        guard selection.isValid else { return nil }
        return selection.entity(at: ordinal)
    }

    /// Get currently selected entity
    var selectedEntity: CosmoGlassEntityRef? {
        guard selection.isValid else { return nil }
        return selection.selectedEntity
    }

    // MARK: - Auto-Dismiss Timers

    private func setupAutoDismissTimer(for card: CosmoGlassCard) {
        guard card.autoDismissAfter > 0 else { return }

        let timer = Timer.publish(every: card.autoDismissAfter, on: .main, in: .common)
            .autoconnect()
            .first()
            .sink { [weak self] _ in
                self?.dismiss(id: card.id)
            }

        autoDismissTimers[card.id] = timer
    }

    private func cancelAutoDismissTimer(for id: String) {
        autoDismissTimers[id]?.cancel()
        autoDismissTimers.removeValue(forKey: id)
    }

    // MARK: - Card Actions

    /// Execute an action on a card (open, place, insert, etc.)
    func executeAction(_ action: CosmoGlassCardAction, cardId: String, entityRef: CosmoGlassEntityRef? = nil, optionId: String? = nil) {
        switch action {
        case .openEntity:
            if let entity = entityRef {
                NotificationCenter.default.post(
                    name: .openEntity,
                    object: nil,
                    userInfo: [
                        "type": EntityType(rawValue: entity.entityType) ?? EntityType.idea,
                        "id": entity.entityId
                    ]
                )
            }
            dismiss(id: cardId)

        case .placeOnCanvas:
            if let entity = entityRef {
                NotificationCenter.default.post(
                    name: .placeEntityOnCanvas,
                    object: nil,
                    userInfo: [
                        "entityType": entity.entityType,
                        "entityId": entity.entityId,
                        "entityUUID": entity.id,
                        "title": entity.title,
                        "position": "center"
                    ]
                )
            }
            dismiss(id: cardId)

        case .insertIntoEditor:
            if let entity = entityRef {
                EditorCommandBus.shared.insertMention(
                    entityType: EntityType(rawValue: entity.entityType) ?? .idea,
                    entityId: entity.entityId,
                    title: entity.title
                )
            }
            dismiss(id: cardId)

        case .proceed:
            // Handle clarification proceed - post notification with selected option
            if let optId = optionId,
               let card = cards.first(where: { $0.id == cardId }),
               let option = card.clarificationOptions.first(where: { $0.id == optId }) {
                NotificationCenter.default.post(
                    name: .glassClarificationSelected,
                    object: nil,
                    userInfo: [
                        "action": option.action,
                        "parameters": option.parameters
                    ]
                )
            }
            dismiss(id: cardId)

        case .cancel, .dismiss:
            dismiss(id: cardId)

        case .scheduleTask, .snooze:
            // TODO: Implement scheduling/snoozing
            dismiss(id: cardId)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let glassClarificationSelected = Notification.Name("com.cosmo.glassClarificationSelected")
    static let glassCardPresented = Notification.Name("com.cosmo.glassCardPresented")
    static let glassCardDismissed = Notification.Name("com.cosmo.glassCardDismissed")
}
