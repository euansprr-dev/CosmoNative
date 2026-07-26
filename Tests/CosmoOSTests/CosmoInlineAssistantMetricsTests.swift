// Tests/CosmoOSTests/CosmoInlineAssistantMetricsTests.swift
// The studio scorecard's honesty guarantees: numbers survive relaunches,
// latency is attributed to the run that produced it (first diff only, never
// a dead run's clock), and first-token samples once per run.

import XCTest
@testable import CosmoOS

@MainActor
final class CosmoInlineAssistantMetricsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "metrics-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testScorecardSurvivesRelaunch() {
        let metrics = CosmoInlineAssistantMetrics(defaults: defaults)
        metrics.requestStarted()
        metrics.firstTokenArrived()
        metrics.proposalStaged()
        metrics.operationResolved(status: .accepted)
        metrics.operationResolved(status: .rejected)
        metrics.paneAnswerDelivered()
        metrics.requestEnded()

        // A fresh instance over the same store is "the next launch".
        let relaunched = CosmoInlineAssistantMetrics(defaults: defaults)
        XCTAssertEqual(relaunched.requestCount, 1)
        XCTAssertEqual(relaunched.proposalsStaged, 1)
        XCTAssertEqual(relaunched.operationsAccepted, 1)
        XCTAssertEqual(relaunched.operationsRejected, 1)
        XCTAssertEqual(relaunched.paneAnswers, 1)
        XCTAssertNotNil(relaunched.averageTTFTMs)
        XCTAssertNotNil(relaunched.averageProposalLatencyMs)
        XCTAssertEqual(relaunched.acceptRate, 0.5)
    }

    func testOnlyFirstProposalOfARunSamplesLatency() {
        let metrics = CosmoInlineAssistantMetrics(defaults: defaults)
        metrics.requestStarted()
        metrics.proposalStaged()
        metrics.proposalStaged()
        metrics.proposalStaged()
        metrics.requestEnded()

        XCTAssertEqual(metrics.proposalsStaged, 3)
        // Exactly one latency sample — the second and third proposals would
        // otherwise sample cumulative loop time and inflate the average.
        XCTAssertEqual(latencySampleCount(in: defaults), 1)
    }

    func testStagingAfterRunEndRecordsCountButNoLatency() {
        let metrics = CosmoInlineAssistantMetrics(defaults: defaults)
        metrics.requestStarted()
        metrics.requestEnded()
        metrics.proposalStaged()

        XCTAssertEqual(metrics.proposalsStaged, 1)
        XCTAssertEqual(latencySampleCount(in: defaults), 0)
        XCTAssertNil(metrics.averageProposalLatencyMs)
    }

    func testFirstTokenSamplesOncePerRun() {
        let metrics = CosmoInlineAssistantMetrics(defaults: defaults)
        metrics.requestStarted()
        metrics.firstTokenArrived()
        metrics.firstTokenArrived()
        metrics.firstTokenArrived()
        metrics.requestEnded()
        // A token arriving with no active run must not sample either.
        metrics.firstTokenArrived()

        XCTAssertEqual(ttftSampleCount(in: defaults), 1)
    }

    func testRevertIsNotAVerdictAndResetZeroes() {
        let metrics = CosmoInlineAssistantMetrics(defaults: defaults)
        metrics.requestStarted()
        metrics.operationResolved(status: .accepted)
        metrics.operationResolved(status: .reverted)
        XCTAssertEqual(metrics.operationsAccepted, 1)
        XCTAssertEqual(metrics.acceptRate, 1.0)

        metrics.reset()
        XCTAssertEqual(metrics.requestCount, 0)
        XCTAssertEqual(metrics.operationsAccepted, 0)
        XCTAssertNil(metrics.acceptRate)
        XCTAssertNil(metrics.averageTTFTMs)
    }

    // MARK: - Persisted-blob introspection

    private struct PersistedShape: Decodable {
        var ttftSampleCount: Int
        var proposalLatencySampleCount: Int
    }

    private func decodePersisted(in defaults: UserDefaults) -> PersistedShape? {
        guard let data = defaults.data(forKey: "inlineAssistant.metrics.v1") else { return nil }
        return try? JSONDecoder().decode(PersistedShape.self, from: data)
    }

    private func latencySampleCount(in defaults: UserDefaults) -> Int {
        decodePersisted(in: defaults)?.proposalLatencySampleCount ?? -1
    }

    private func ttftSampleCount(in defaults: UserDefaults) -> Int {
        decodePersisted(in: defaults)?.ttftSampleCount ?? -1
    }
}
