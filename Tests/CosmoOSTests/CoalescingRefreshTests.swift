import XCTest
@testable import CosmoOS

@MainActor
final class CoalescingRefreshTests: XCTestCase {
    func testVisitsJoinAnInFlightRefresh() async {
        let refresh = CoalescingRefresh()
        let gate = Gate()
        var calls = 0
        let first = Task { await refresh.run { calls += 1; await gate.wait() } }
        await gate.waitUntilStarted()
        var visitStarted = false
        let visit = Task { visitStarted = true; await refresh.run(invalidate: false) { calls += 1 } }
        while !visitStarted { await Task.yield() }
        gate.release()
        await first.value
        await visit.value
        XCTAssertEqual(calls, 1)
    }

    func testBurstKeepsOnlyLatestPendingPassAndWaitersAwaitIt() async {
        let refresh = CoalescingRefresh()
        let gate = Gate()
        var values: [Int] = []
        let first = Task { await refresh.run { values.append(0); await gate.wait() } }
        await gate.waitUntilStarted()
        var waiters: [Task<Void, Never>] = []
        var submitted = 0
        for value in 1...20 {
            waiters.append(Task { submitted = value; await refresh.run { values.append(value) } })
            while submitted < value { await Task.yield() }
        }
        gate.release()
        await first.value
        for waiter in waiters { await waiter.value }
        XCTAssertEqual(values, [0, 20])
        await refresh.run { values.append(21) }
        XCTAssertEqual(values, [0, 20, 21], "Completed work must not leave a stuck in-flight task")
    }

    func testCancelledWaiterDoesNotCancelSharedWork() async {
        let refresh = CoalescingRefresh()
        let gate = Gate()
        var finished = false
        let first = Task { await refresh.run { await gate.wait(); finished = !Task.isCancelled } }
        await gate.waitUntilStarted()
        first.cancel()
        gate.release()
        await first.value
        XCTAssertTrue(finished)
    }

    private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        func wait() async { await withCheckedContinuation { continuation = $0 } }
        func waitUntilStarted() async { while continuation == nil { await Task.yield() } }
        func release() { continuation?.resume(); continuation = nil }
    }
}
