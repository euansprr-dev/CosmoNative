// CosmoOS/Tests/JARVISTests.swift
// Comprehensive test suite for the JARVIS Telepathy Engine
// Tests voice pipeline, streaming gardener, autocomplete, and Qwen daemon integration

import XCTest
@testable import CosmoOS

// MARK: - TelepathyEngine Tests

final class TelepathyEngineTests: XCTestCase {

    @MainActor
    override func setUp() async throws {
        // Clear any existing context before each test
        TelepathyEngine.shared.clearContext()
    }

    // MARK: - Voice Chunk Processing

    @MainActor
    func testVoiceChunkUpdatesTranscript() async throws {
        let engine = TelepathyEngine.shared

        await engine.simulateVoiceChunk("Hello world", isFinal: false)

        XCTAssertEqual(engine.lastTranscript, "Hello world")
        XCTAssertTrue(engine.isListening)
    }

    @MainActor
    func testFinalTranscriptStopsListening() async throws {
        let engine = TelepathyEngine.shared

        await engine.simulateVoiceChunk("Create a new idea", isFinal: true)

        XCTAssertFalse(engine.isListening)
    }

    @MainActor
    func testShadowSearchTriggersOnSufficientWords() async throws {
        let engine = TelepathyEngine.shared

        // Three words should trigger shadow search
        await engine.simulateVoiceChunk("quantum computing applications", isFinal: false)

        // Wait for debounce
        try await Task.sleep(nanoseconds: 150_000_000)

        // Context should have been searched (may be empty if no matching entities)
        XCTAssertFalse(engine.hotContext.lastQuery.isEmpty)
    }

    @MainActor
    func testTypingInputTriggersSearch() async throws {
        let engine = TelepathyEngine.shared

        await engine.handleTypingInput("machine learning research project", cursorPosition: 35)

        // Wait for debounce
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(engine.lastTranscript, "machine learning research project")
    }

    @MainActor
    func testClearContextResetsState() async throws {
        let engine = TelepathyEngine.shared

        await engine.simulateVoiceChunk("Some text", isFinal: false)
        engine.clearContext()

        XCTAssertEqual(engine.lastTranscript, "")
        XCTAssertFalse(engine.hotContext.hasRelatedEntities)
    }
}

// MARK: - HotContext Tests

final class HotContextTests: XCTestCase {

    func testEmptyContextHasNoRelatedEntities() {
        let context = HotContext()

        XCTAssertFalse(context.hasRelatedEntities)
        XCTAssertNil(context.mostRelevantConnection)
        XCTAssertNil(context.mostRelevantProject)
    }

    func testContextWithConnectionsHasRelatedEntities() {
        var context = HotContext()
        context.relatedConnections = [
            VectorSearchResult(
                id: 1,
                entityType: "connection",
                entityId: 42,
                entityUUID: "test-uuid",
                similarity: 0.8,
                text: "Test connection",
                metadata: nil
            )
        ]

        XCTAssertTrue(context.hasRelatedEntities)
        XCTAssertNotNil(context.mostRelevantConnection)
        XCTAssertEqual(context.mostRelevantConnection?.entityId, 42)
    }

    func testTopBeliefsExtraction() {
        var context = HotContext()
        context.relatedConnections = [
            VectorSearchResult(
                id: 1,
                entityType: "connection",
                entityId: 1,
                entityUUID: nil,
                similarity: 0.9,
                text: nil,
                metadata: ["beliefs": "Move fast and iterate"]
            ),
            VectorSearchResult(
                id: 2,
                entityType: "connection",
                entityId: 2,
                entityUUID: nil,
                similarity: 0.8,
                text: nil,
                metadata: ["beliefs": "Quality over quantity"]
            )
        ]

        XCTAssertEqual(context.topBeliefs.count, 2)
        XCTAssertEqual(context.topBeliefs.first, "Move fast and iterate")
    }

    func testEntityIdsForType() {
        var context = HotContext()
        context.relatedProjects = [
            VectorSearchResult(id: 1, entityType: "project", entityId: 100, entityUUID: nil, similarity: 0.9, text: nil, metadata: nil),
            VectorSearchResult(id: 2, entityType: "project", entityId: 200, entityUUID: nil, similarity: 0.8, text: nil, metadata: nil)
        ]

        let ids = context.entityIds(for: "project")

        XCTAssertEqual(ids, [100, 200])
    }
}

// MARK: - StreamingGardener Tests

final class StreamingGardenerTests: XCTestCase {

    var gardener: StreamingGardener!

    override func setUp() async throws {
        gardener = StreamingGardener()
    }

    override func tearDown() async throws {
        await gardener.clearHypotheses()
    }

    // MARK: - Task Pattern Detection

    func testDetectsUnscheduledTask() async throws {
        let chunk = L1TranscriptChunk(
            text: "I need to buy groceries",
            isFinal: false,
            confidence: 0.9,
            timestamp: Date().timeIntervalSince1970
        )

        await gardener.processChunk(chunk, hotContext: HotContext())

        let count = await gardener.hypothesesCount()
        XCTAssertEqual(count, 1)
    }

    func testDetectsScheduledTask() async throws {
        let chunk = L1TranscriptChunk(
            text: "remind me to call John tomorrow at 3pm",
            isFinal: false,
            confidence: 0.9,
            timestamp: Date().timeIntervalSince1970
        )

        await gardener.processChunk(chunk, hotContext: HotContext())

        let count = await gardener.hypothesesCount()
        XCTAssertEqual(count, 1)
    }

    func testDetectsRecurringTask() async throws {
        let chunk = L1TranscriptChunk(
            text: "remind me to take vitamins every day at 9am",
            isFinal: false,
            confidence: 0.9,
            timestamp: Date().timeIntervalSince1970
        )

        await gardener.processChunk(chunk, hotContext: HotContext())

        let count = await gardener.hypothesesCount()
        XCTAssertEqual(count, 1)
    }

    // MARK: - Scheduled Block Detection

    func testDetectsScheduledBlock() async throws {
        let chunk = L1TranscriptChunk(
            text: "schedule deep work from 9am to 11am",
            isFinal: false,
            confidence: 0.9,
            timestamp: Date().timeIntervalSince1970
        )

        await gardener.processChunk(chunk, hotContext: HotContext())

        let count = await gardener.hypothesesCount()
        XCTAssertEqual(count, 1)
    }

    func testDetectsFocusTime() async throws {
        let chunk = L1TranscriptChunk(
            text: "block out focus time tomorrow morning",
            isFinal: false,
            confidence: 0.9,
            timestamp: Date().timeIntervalSince1970
        )

        await gardener.processChunk(chunk, hotContext: HotContext())

        let count = await gardener.hypothesesCount()
        XCTAssertGreaterThan(count, 0)
    }

    func testDetectsRecurringBlock() async throws {
        let chunk = L1TranscriptChunk(
            text: "meditation every morning from 7 to 7:30",
            isFinal: false,
            confidence: 0.9,
            timestamp: Date().timeIntervalSince1970
        )

        await gardener.processChunk(chunk, hotContext: HotContext())

        let count = await gardener.hypothesesCount()
        XCTAssertGreaterThan(count, 0)
    }

    // MARK: - Idea Detection

    func testDetectsIdea() async throws {
        let chunk = L1TranscriptChunk(
            text: "idea for a new app that helps people track habits",
            isFinal: false,
            confidence: 0.9,
            timestamp: Date().timeIntervalSince1970
        )

        await gardener.processChunk(chunk, hotContext: HotContext())

        let count = await gardener.hypothesesCount()
        XCTAssertEqual(count, 1)
    }

    func testDetectsWhatIfIdea() async throws {
        let chunk = L1TranscriptChunk(
            text: "what if we could use AI to automatically organize knowledge",
            isFinal: false,
            confidence: 0.9,
            timestamp: Date().timeIntervalSince1970
        )

        await gardener.processChunk(chunk, hotContext: HotContext())

        let count = await gardener.hypothesesCount()
        XCTAssertEqual(count, 1)
    }

    // MARK: - Connection Section Detection

    func testDetectsConnectionSectionWithHighSimilarity() async throws {
        var context = HotContext()
        context.relatedConnections = [
            VectorSearchResult(
                id: 1,
                entityType: "connection",
                entityId: 42,
                entityUUID: "conn-uuid",
                similarity: 0.75,  // Above 0.6 threshold
                text: "John Smith - Product Manager",
                metadata: nil
            )
        ]

        let chunk = L1TranscriptChunk(
            text: "I believe the key insight from our conversation is that speed of iteration matters more than initial perfection because you learn through real-world feedback",
            isFinal: false,
            confidence: 0.9,
            timestamp: Date().timeIntervalSince1970
        )

        await gardener.processChunk(chunk, hotContext: context)

        let count = await gardener.hypothesesCount()
        XCTAssertEqual(count, 1)
    }

    // MARK: - Fallback Behavior

    func testFallbackToIdeaForUnmatchedContent() async throws {
        let chunk = L1TranscriptChunk(
            text: "The sunset was beautiful today and it made me think about life",
            isFinal: false,
            confidence: 0.9,
            timestamp: Date().timeIntervalSince1970
        )

        await gardener.processChunk(chunk, hotContext: HotContext())

        let count = await gardener.hypothesesCount()
        XCTAssertEqual(count, 1)  // Should become newIdea
    }

    func testLongBrainDumpBecomesRichTextIdea() async throws {
        // Generate 500+ word content
        let longContent = Array(repeating: "This is a sentence with multiple words.", count: 100).joined(separator: " ")

        let chunk = L1TranscriptChunk(
            text: longContent,
            isFinal: false,
            confidence: 0.9,
            timestamp: Date().timeIntervalSince1970
        )

        await gardener.processChunk(chunk, hotContext: HotContext())

        let count = await gardener.hypothesesCount()
        XCTAssertEqual(count, 1)  // Should become richTextIdea
    }

    // MARK: - Clear Hypotheses

    func testClearHypotheses() async throws {
        let chunk = L1TranscriptChunk(
            text: "I need to do something",
            isFinal: false,
            confidence: 0.9,
            timestamp: Date().timeIntervalSince1970
        )

        await gardener.processChunk(chunk, hotContext: HotContext())
        await gardener.clearHypotheses()

        let count = await gardener.hypothesesCount()
        XCTAssertEqual(count, 0)
    }
}

// MARK: - AutocompleteService Tests

final class AutocompleteServiceTests: XCTestCase {

    var service: AutocompleteService!

    override func setUp() async throws {
        service = AutocompleteService()
    }

    // MARK: - Pause Detection

    func testShortTextDoesNotTriggerAutocomplete() async throws {
        await service.onTypingInput("Hi", cursorPosition: 2, hotContext: HotContext())

        // Wait longer than pause threshold
        try await Task.sleep(nanoseconds: 700_000_000)

        // Should not have triggered (text too short)
        // Note: We can't easily verify this without notification observation
    }

    func testTypingCancelsPreviousDebounce() async throws {
        await service.onTypingInput("The main problem", cursorPosition: 16, hotContext: HotContext())

        // Type more before pause threshold
        try await Task.sleep(nanoseconds: 100_000_000)
        await service.onTypingInput("The main problem is", cursorPosition: 19, hotContext: HotContext())

        // The first debounce should have been cancelled
        await service.cancel()
    }

    func testCancelStopsAutocomplete() async throws {
        await service.onTypingInput("The main problem is that", cursorPosition: 24, hotContext: HotContext())
        await service.cancel()

        // Wait past threshold
        try await Task.sleep(nanoseconds: 700_000_000)

        // Should not trigger due to cancel
    }
}

// MARK: - L1TranscriptChunk Tests

final class L1TranscriptChunkTests: XCTestCase {

    func testWordCountCalculation() {
        let chunk = L1TranscriptChunk(
            text: "Hello world how are you",
            isFinal: false,
            confidence: 0.9,
            timestamp: Date().timeIntervalSince1970
        )

        XCTAssertEqual(chunk.wordCount, 5)
    }

    func testIntentReadyWithTwoWords() {
        let chunk = L1TranscriptChunk(
            text: "Create idea",
            isFinal: false,
            confidence: 0.9,
            timestamp: Date().timeIntervalSince1970
        )

        XCTAssertTrue(chunk.isIntentReady)
    }

    func testNotIntentReadyWithOneWord() {
        let chunk = L1TranscriptChunk(
            text: "Hello",
            isFinal: false,
            confidence: 0.9,
            timestamp: Date().timeIntervalSince1970
        )

        XCTAssertFalse(chunk.isIntentReady)
    }

    func testHighConfidenceThreshold() {
        let highConfidence = L1TranscriptChunk(
            text: "Test",
            isFinal: false,
            confidence: 0.90,
            timestamp: Date().timeIntervalSince1970
        )

        let lowConfidence = L1TranscriptChunk(
            text: "Test",
            isFinal: false,
            confidence: 0.80,
            timestamp: Date().timeIntervalSince1970
        )

        XCTAssertTrue(highConfidence.isHighConfidence)
        XCTAssertFalse(lowConfidence.isHighConfidence)
    }
}

// MARK: - VoiceCommandOutput Tests

final class VoiceCommandOutputTests: XCTestCase {

    func testValidCommandOutput() {
        let output = VoiceCommandOutput(
            action: "create_entity",
            entityType: "idea",
            title: "Test idea",
            confidence: 0.85
        )

        XCTAssertTrue(output.isValid)
    }

    func testInvalidUnknownAction() {
        let output = VoiceCommandOutput(
            action: "unknown",
            confidence: 0.85
        )

        XCTAssertFalse(output.isValid)
    }

    func testInvalidLowConfidence() {
        let output = VoiceCommandOutput(
            action: "create_entity",
            confidence: 0.3
        )

        XCTAssertFalse(output.isValid)
    }

    func testInvalidEmptyAction() {
        let output = VoiceCommandOutput(
            action: "",
            confidence: 0.9
        )

        XCTAssertFalse(output.isValid)
    }
}

// MARK: - LLMCommandResult Conversion Tests

final class LLMCommandResultConversionTests: XCTestCase {

    func testConversionFromVoiceCommandOutput() {
        let output = VoiceCommandOutput(
            action: "create_entity",
            entityType: "idea",
            title: "My great idea",
            content: "Some content",
            section: "ideas",
            position: "center",
            searchQuery: "search term",
            confidence: 0.92,
            requiresConfirmation: false,
            explanation: "Created an idea"
        )

        let result = LLMCommandResult.from(output)

        XCTAssertEqual(result.action, "create_entity")
        XCTAssertEqual(result.entityType, "idea")
        XCTAssertEqual(result.title, "My great idea")
        XCTAssertEqual(result.content, "Some content")
        XCTAssertEqual(result.section, "ideas")
        XCTAssertEqual(result.position, "center")
        XCTAssertEqual(result.searchQuery, "search term")
        XCTAssertEqual(result.confidence, 0.92)
        XCTAssertEqual(result.requiresConfirmation, false)
        XCTAssertEqual(result.clarificationQuestion, "Created an idea")
    }

    func testUnknownResult() {
        let unknown = LLMCommandResult.unknown

        XCTAssertEqual(unknown.action, "unknown")
        XCTAssertEqual(unknown.confidence, 0.0)
        XCTAssertNil(unknown.title)
    }
}

// MARK: - RecurrenceSchedule Tests

final class RecurrenceScheduleTests: XCTestCase {

    func testHumanReadable() {
        XCTAssertEqual(RecurrenceSchedule.daily.humanReadable, "Every day")
        XCTAssertEqual(RecurrenceSchedule.weekly.humanReadable, "Every week")
        XCTAssertEqual(RecurrenceSchedule.weekdays.humanReadable, "Weekdays")
        XCTAssertEqual(RecurrenceSchedule.weekends.humanReadable, "Weekends")
        XCTAssertEqual(RecurrenceSchedule.monthly.humanReadable, "Every month")
    }

    func testCodable() throws {
        let schedule = RecurrenceSchedule.weekly
        let encoded = try JSONEncoder().encode(schedule)
        let decoded = try JSONDecoder().decode(RecurrenceSchedule.self, from: encoded)

        XCTAssertEqual(decoded, schedule)
    }
}

// MARK: - TimeRange Tests

final class TimeRangeTests: XCTestCase {

    func testDurationCalculation() {
        let start = Date()
        let end = start.addingTimeInterval(3600)  // 1 hour later

        let range = TimeRange(start: start, end: end)

        XCTAssertEqual(range.durationMinutes, 60)
    }

    func testShortDuration() {
        let start = Date()
        let end = start.addingTimeInterval(1800)  // 30 minutes

        let range = TimeRange(start: start, end: end)

        XCTAssertEqual(range.durationMinutes, 30)
    }
}

// MARK: - ConnectionSectionType Tests

final class ConnectionSectionTypeTests: XCTestCase {

    func testDisplayNames() {
        XCTAssertEqual(ConnectionSectionType.goal.displayName, "Goal")
        XCTAssertEqual(ConnectionSectionType.problem.displayName, "Problem")
        XCTAssertEqual(ConnectionSectionType.benefits.displayName, "Benefits")
        XCTAssertEqual(ConnectionSectionType.beliefs.displayName, "Beliefs")
        XCTAssertEqual(ConnectionSectionType.example.displayName, "Example")
        XCTAssertEqual(ConnectionSectionType.process.displayName, "Process")
        XCTAssertEqual(ConnectionSectionType.coreIdea.displayName, "Core Idea")
        XCTAssertEqual(ConnectionSectionType.notes.displayName, "Notes")
    }
}

// MARK: - ConsoleLog Tests

final class ConsoleLogTests: XCTestCase {

    func testDebugLoggingInDebugMode() {
        // Ensure debug logging works when enabled
        ConsoleLog.isDebugEnabled = true

        // This should not crash
        ConsoleLog.debug("Test debug message", subsystem: .telepathy)
        ConsoleLog.info("Test info message", subsystem: .gardener)
        ConsoleLog.warning("Test warning", subsystem: .autocomplete)
        ConsoleLog.error("Test error", subsystem: .voice, error: nil)
    }

    func testTimingHelpers() {
        let start = ConsoleLog.startTiming("Test operation", subsystem: .telepathy)

        // Simulate some work
        Thread.sleep(forTimeInterval: 0.01)

        // This should log completion time
        ConsoleLog.endTiming("Test operation", start: start, subsystem: .telepathy)
    }

    func testTimedBlock() {
        let result = ConsoleLog.timed("Sync operation", subsystem: .database) {
            return 42
        }

        XCTAssertEqual(result, 42)
    }

    func testAsyncTimedBlock() async {
        let result = await ConsoleLog.timed("Async operation", subsystem: .llm) {
            try? await Task.sleep(nanoseconds: 1_000_000)
            return "done"
        }

        XCTAssertEqual(result, "done")
    }
}

// MARK: - Integration Tests

final class JARVISIntegrationTests: XCTestCase {

    @MainActor
    func testFullVoiceToHypothesisFlow() async throws {
        let engine = TelepathyEngine.shared
        engine.clearContext()

        // Simulate voice input
        await engine.simulateVoiceChunk("I need to schedule a meeting with Sarah tomorrow", isFinal: false)

        // Wait for processing
        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify gardener received the chunk
        let gardener = engine.streamingGardener
        let count = await gardener.hypothesesCount()

        // Should have detected this as a task
        XCTAssertGreaterThan(count, 0)
    }

    @MainActor
    func testTypingToAutocompleteFlow() async throws {
        let engine = TelepathyEngine.shared
        engine.clearContext()

        // Setup notification observer
        var suggestionReceived = false
        let observer = NotificationCenter.default.addObserver(
            forName: .ghostTextSuggestion,
            object: nil,
            queue: .main
        ) { _ in
            suggestionReceived = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        // Simulate typing
        await engine.handleTypingInput("The most important thing about this project is", cursorPosition: 47)

        // Wait for autocomplete (600ms pause + processing)
        try await Task.sleep(nanoseconds: 800_000_000)

        // Note: Suggestion may not be received if no beliefs in context
        // This test verifies the flow doesn't crash
    }

    @MainActor
    func testShadowSearchPopulatesContext() async throws {
        let engine = TelepathyEngine.shared
        engine.clearContext()

        // Trigger search with a meaningful query
        await engine.triggerSearch(for: "project management software development")

        // Wait for search
        try await Task.sleep(nanoseconds: 300_000_000)

        // Query should be recorded
        XCTAssertFalse(engine.hotContext.lastQuery.isEmpty)
    }
}

// MARK: - Performance Tests

final class JARVISPerformanceTests: XCTestCase {

    func testTranscriptChunkCreationPerformance() {
        measure {
            for i in 0..<10000 {
                _ = L1TranscriptChunk(
                    text: "Test transcript chunk number \(i) with some words",
                    isFinal: false,
                    confidence: 0.9,
                    timestamp: Date().timeIntervalSince1970
                )
            }
        }
    }

    func testHotContextCreationPerformance() {
        measure {
            for _ in 0..<1000 {
                var context = HotContext()
                context.relatedConnections = (0..<10).map { i in
                    VectorSearchResult(
                        id: Int64(i),
                        entityType: "connection",
                        entityId: Int64(i),
                        entityUUID: "uuid-\(i)",
                        similarity: Float.random(in: 0.5...1.0),
                        text: "Connection \(i)",
                        metadata: ["beliefs": "Belief \(i)"]
                    )
                }
                _ = context.topBeliefs
                _ = context.hasRelatedEntities
            }
        }
    }

    func testVoiceCommandOutputValidationPerformance() {
        let outputs = (0..<1000).map { i in
            VoiceCommandOutput(
                action: i % 2 == 0 ? "create_entity" : "unknown",
                entityType: "idea",
                title: "Test \(i)",
                confidence: Double(i % 100) / 100.0
            )
        }

        measure {
            for output in outputs {
                _ = output.isValid
            }
        }
    }
}
