// CosmoOS/AI/IncubationEngine.swift
// Spaced repetition engine for knowledge incubation
// Leitner box system: atoms that haven't been deeply processed
// gently pulse on the canvas and appear in "Due for Review"

import Foundation
import Combine

@MainActor
class IncubationEngine: ObservableObject {
    static let shared = IncubationEngine()

    @Published var dueAtoms: [Atom] = []
    @Published var heartbeatingUUIDs: Set<String> = []  // max 2 at a time

    private let maxHeartbeats = 2
    private let maxIgnoresBeforeDormant = 3

    // MARK: - Leitner Box Intervals (days)

    private func intervalDays(for box: Int) -> Int {
        switch box {
        case 1: return 1
        case 2: return 3
        case 3: return 7
        default: return 7
        }
    }

    // MARK: - Enrollment

    /// Enroll an atom in the review queue if it meets criteria:
    /// crystallizationLevel < .distilled AND linkCount < 3 AND annotationCount < 3
    func enrollAtom(uuid: String) async {
        guard var atom = try? await AtomRepository.shared.fetch(uuid: uuid) else { return }

        // Skip if already enrolled
        if atom.reviewQueueMetadata != nil { return }

        // Check enrollment criteria
        let crystLevel = atom.crystallizationLevel
        let linkCount = atom.crystallizationMetadata?.linkCount ?? atom.linksList.count
        let annotationCount = atom.crystallizationMetadata?.annotationCount ?? 0

        guard crystLevel < .distilled, linkCount < 3, annotationCount < 3 else { return }

        // Only enroll core knowledge types
        let enrollableTypes: Set<AtomType> = [.idea, .research, .connection, .note, .content]
        guard enrollableTypes.contains(atom.type) else { return }

        let now = ISO8601DateFormatter().string(from: Date())
        let dueAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400)) // 1 day from now

        atom.reviewQueueMetadata = ReviewQueueMetadata(
            leitnerBox: 1,
            dueAt: dueAt,
            ignoreCount: 0,
            snoozedUntil: nil,
            interactionHistory: [],
            enrolledAt: now,
            isDormant: false
        )

        _ = try? await AtomRepository.shared.update(atom)
    }

    // MARK: - Interaction Recording

    /// Record that the user interacted with an atom (opened focus mode, added annotation, created link)
    func recordInteraction(uuid: String) async {
        guard var atom = try? await AtomRepository.shared.fetch(uuid: uuid) else { return }
        guard var rq = atom.reviewQueueMetadata else { return }

        let now = ISO8601DateFormatter().string(from: Date())
        rq.interactionHistory.append(now)

        // Advance to next Leitner box
        if rq.leitnerBox < 3 {
            rq.leitnerBox += 1
        }

        // Reset due date based on new box interval
        let nextDue = Date().addingTimeInterval(Double(intervalDays(for: rq.leitnerBox)) * 86400)
        rq.dueAt = ISO8601DateFormatter().string(from: nextDue)

        // Reset ignore count on successful interaction
        rq.ignoreCount = 0
        rq.isDormant = false

        atom.reviewQueueMetadata = rq
        _ = try? await AtomRepository.shared.update(atom)

        // Remove from heartbeating if it was pulsing
        heartbeatingUUIDs.remove(uuid)
    }

    // MARK: - Queue Evaluation (called from heartbeat scheduler)

    /// Evaluate the review queue: find due atoms, select heartbeat targets
    func evaluateQueue() async {
        let fetchTypes: [AtomType] = [.idea, .research, .connection, .note, .content]
        var allDue: [Atom] = []

        for atomType in fetchTypes {
            let atoms = (try? await AtomRepository.shared.fetchAll(type: atomType)) ?? []
            for atom in atoms {
                guard let rq = atom.reviewQueueMetadata,
                      !rq.isDormant else { continue }

                let now = ISO8601DateFormatter().string(from: Date())

                // Check snooze
                if let snoozed = rq.snoozedUntil, snoozed > now { continue }

                // Check if due
                if rq.dueAt <= now {
                    allDue.append(atom)
                }
            }
        }

        // Sort by most overdue first (earliest dueAt first)
        allDue.sort { ($0.reviewQueueMetadata?.dueAt ?? "") < ($1.reviewQueueMetadata?.dueAt ?? "") }

        dueAtoms = allDue

        // Select top 2 for heartbeat animation
        let topUUIDs = Set(allDue.prefix(maxHeartbeats).map { $0.uuid })
        heartbeatingUUIDs = topUUIDs
    }

    // MARK: - Advance Box

    /// Manually advance an atom to the next Leitner box
    func advanceBox(uuid: String) async {
        await recordInteraction(uuid: uuid)
    }

    // MARK: - Mark Dormant

    /// Mark an atom as dormant (stop resurfacing)
    func markDormant(uuid: String) async {
        guard var atom = try? await AtomRepository.shared.fetch(uuid: uuid) else { return }
        guard var rq = atom.reviewQueueMetadata else { return }

        rq.isDormant = true
        atom.reviewQueueMetadata = rq
        _ = try? await AtomRepository.shared.update(atom)

        heartbeatingUUIDs.remove(uuid)
        dueAtoms.removeAll { $0.uuid == uuid }
    }

    // MARK: - Snooze

    /// Snooze an atom until a specific date
    func snooze(uuid: String, until: Date) async {
        guard var atom = try? await AtomRepository.shared.fetch(uuid: uuid) else { return }
        guard var rq = atom.reviewQueueMetadata else { return }

        rq.snoozedUntil = ISO8601DateFormatter().string(from: until)
        atom.reviewQueueMetadata = rq
        _ = try? await AtomRepository.shared.update(atom)

        heartbeatingUUIDs.remove(uuid)
        dueAtoms.removeAll { $0.uuid == uuid }
    }

    // MARK: - Ignore Tracking

    /// Increment ignore count for atoms that were surfaced but not interacted with
    func processIgnores() async {
        for atom in dueAtoms {
            guard var mutableAtom = try? await AtomRepository.shared.fetch(uuid: atom.uuid) else { continue }
            guard var rq = mutableAtom.reviewQueueMetadata else { continue }

            // Only increment if the atom was surfaced (in dueAtoms) and not interacted with today
            let today = ISO8601DateFormatter().string(from: Date()).prefix(10) // YYYY-MM-DD
            let interactedToday = rq.interactionHistory.contains { $0.hasPrefix(String(today)) }

            if !interactedToday {
                rq.ignoreCount += 1
                if rq.ignoreCount >= maxIgnoresBeforeDormant {
                    rq.isDormant = true
                }
                mutableAtom.reviewQueueMetadata = rq
                _ = try? await AtomRepository.shared.update(mutableAtom)
            }
        }
    }

    // MARK: - Auto-Enrollment Check

    /// Check recent atoms and auto-enroll eligible ones
    func autoEnrollEligibleAtoms() async {
        let enrollableTypes: [AtomType] = [.idea, .research, .connection, .note, .content]

        for atomType in enrollableTypes {
            let atoms = (try? await AtomRepository.shared.fetchAll(type: atomType)) ?? []
            for atom in atoms {
                // Skip if already enrolled or if deeply processed
                if atom.reviewQueueMetadata != nil { continue }
                if atom.crystallizationLevel >= .distilled { continue }

                let linkCount = atom.crystallizationMetadata?.linkCount ?? atom.linksList.count
                let annotationCount = atom.crystallizationMetadata?.annotationCount ?? 0

                if linkCount < 3 && annotationCount < 3 {
                    await enrollAtom(uuid: atom.uuid)
                }
            }
        }
    }
}
