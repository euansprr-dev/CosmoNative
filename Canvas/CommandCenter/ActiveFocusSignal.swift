// Canvas/CommandCenter/ActiveFocusSignal.swift
// "Which task is running right now" as an observable value that changes only
// when the answer changes.
//
// DeepWorkSessionEngine is an ObservableObject whose `elapsedSeconds` ticks
// every second, and an @ObservedObject sees objectWillChange for *every*
// published property — so any view holding the engine repainted once a second
// for a number it never read. The Command Center's task ledger held it, which
// meant every row, every section and every closure in the list was rebuilt each
// second a focus session ran. This is the narrow signal the ledger actually
// wanted.
// July 2026

import Foundation
import Combine

@MainActor
@Observable
final class ActiveFocusSignal {

    static let shared = ActiveFocusSignal()

    /// The uuid of the task whose session is running — nil while paused or idle.
    /// (`isActiveSession` in the row grammar: session belongs to this task AND
    /// the clock is moving.)
    private(set) var runningTaskUUID: String?

    /// Whether any session's clock is moving. Ticks twice per session, not once
    /// per second.
    private(set) var isTimerRunning = false

    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []

    private init() {
        let engine = DeepWorkSessionEngine.shared

        engine.$isTimerRunning
            .removeDuplicates()
            .sink { [weak self] running in
                self?.isTimerRunning = running
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(engine.$activeSession, engine.$isTimerRunning)
            .map { session, running in running ? session?.taskUUID : nil }
            .removeDuplicates()
            .sink { [weak self] uuid in
                self?.runningTaskUUID = uuid
            }
            .store(in: &cancellables)
    }
}
