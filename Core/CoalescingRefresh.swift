import Foundation

/// One refresh at a time, with at most one pending pass. New invalidations
/// replace the pending work; a visit/prewarm can simply join the current pass.
/// Cancelling a view's waiter never cancels a refresh another view still needs.
@MainActor
final class CoalescingRefresh {
    private var task: Task<Void, Never>?
    private var pending: (@MainActor () async -> Void)?

    func run(
        invalidate: Bool = true,
        _ operation: @escaping @MainActor () async -> Void
    ) async {
        if let task {
            if invalidate { pending = operation }
            await task.value
            return
        }

        pending = operation
        let next = Task {
            while let operation = self.pending {
                self.pending = nil
                await operation()
            }
            self.task = nil
        }
        task = next
        await next.value
    }
}
