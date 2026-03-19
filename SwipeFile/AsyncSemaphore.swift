// CosmoOS/SwipeFile/AsyncSemaphore.swift
// Actor-based semaphore for limiting concurrent async operations
// March 2026

/// Bounds the number of concurrent async tasks.
/// Used by SwipeProcessingService to cap parallel transcriptions.
actor AsyncSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.count = value
    }

    /// Wait until a slot is available. Suspends if all slots are taken.
    func wait() async {
        if count > 0 {
            count -= 1
        } else {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    /// Release a slot, resuming the next waiter if any.
    func signal() {
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume()
        } else {
            count += 1
        }
    }
}
