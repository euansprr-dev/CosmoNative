// Tests/CosmoOSTests/DailyBriefQueriesTests.swift
// Pins the Daily Return's SQL predicates to how atoms actually store their
// metadata. The original completed-tasks query looked for "status":"completed"
// while tasks write "isCompleted":true — it counted zero forever and the brief
// starved. These tests make that class of drift loud.

import XCTest
import GRDB
@testable import CosmoOS

@MainActor
final class DailyBriefQueriesTests: XCTestCase {
    private var cleanupUUIDs: [String] = []

    override func tearDown() async throws {
        let uuids = cleanupUUIDs.reversed()
        cleanupUUIDs.removeAll()
        for uuid in uuids {
            try? await AtomRepository.shared.hardDelete(uuid: uuid, confirmed: true)
        }
        try await super.tearDown()
    }

    private func insertAtom(
        type: AtomType,
        title: String,
        metadata: String?,
        createdAt: String,
        updatedAt: String? = nil
    ) async throws -> String {
        var atom = Atom.new(type: type, title: title, body: nil)
        atom.metadata = metadata
        atom.createdAt = createdAt
        atom.updatedAt = updatedAt ?? createdAt
        let captured = atom
        try await CosmoDatabase.shared.asyncWrite { db in
            try captured.insert(db)
        }
        cleanupUUIDs.append(atom.uuid)
        return atom.uuid
    }

    func testCompletedTaskCountMatchesIsCompletedTrue() async throws {
        let from = "2030-01-01T00:00:00Z"
        let to = "2030-01-02T00:00:00Z"

        // A completed task inside the window (real storage shape).
        _ = try await insertAtom(
            type: .task,
            title: "Shipped",
            metadata: #"{"isCompleted":true,"dueDate":"2030-01-01T09:00:00Z"}"#,
            createdAt: "2030-01-01T08:00:00Z"
        )
        // An open task inside the window — must not count.
        _ = try await insertAtom(
            type: .task,
            title: "Open",
            metadata: #"{"isCompleted":false}"#,
            createdAt: "2030-01-01T08:00:00Z"
        )
        // A completed task outside the window — must not count.
        _ = try await insertAtom(
            type: .task,
            title: "Old win",
            metadata: #"{"isCompleted":true}"#,
            createdAt: "2029-12-30T08:00:00Z"
        )

        let count = try await CosmoDatabase.shared.asyncRead { db in
            try DailyBriefQueries.completedTaskCount(db, from: from, to: to)
        }
        XCTAssertEqual(count, 1)
    }

    func testCapturedCountSeesIndexedTypesInWindow() async throws {
        let from = "2030-02-01T00:00:00Z"
        let to = "2030-02-02T00:00:00Z"

        _ = try await insertAtom(
            type: .idea,
            title: "A captured idea",
            metadata: nil,
            createdAt: "2030-02-01T10:00:00Z"
        )
        _ = try await insertAtom(
            type: .idea,
            title: "Yesterday's idea",
            metadata: nil,
            createdAt: "2030-01-31T10:00:00Z"
        )

        let count = try await CosmoDatabase.shared.asyncRead { db in
            try DailyBriefQueries.capturedCount(db, from: from, to: to)
        }
        XCTAssertEqual(count, 1)
    }

    func testContentDueMatchesScheduledAtDayPrefix() async throws {
        let uuid = try await insertAtom(
            type: .content,
            title: "Reel for Josh",
            metadata: #"{"scheduledAt":"2030-03-04T17:00:00Z","status":"scheduled"}"#,
            createdAt: "2030-03-01T08:00:00Z"
        )
        _ = try await insertAtom(
            type: .content,
            title: "Different day",
            metadata: #"{"scheduledAt":"2030-03-06T17:00:00Z"}"#,
            createdAt: "2030-03-01T08:00:00Z"
        )

        let due = try await CosmoDatabase.shared.asyncRead { db in
            try DailyBriefQueries.contentDue(db, dayPrefix: "2030-03-04")
        }
        XCTAssertEqual(due.map(\.uuid), [uuid])
        XCTAssertEqual(due.first?.title, "Reel for Josh")
    }
}
