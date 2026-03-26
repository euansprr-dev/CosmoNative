// CosmoOS/Tests/JARVISTests.swift
// Test suite for voice pipeline and Qwen daemon integration

import XCTest
@testable import CosmoOS

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
