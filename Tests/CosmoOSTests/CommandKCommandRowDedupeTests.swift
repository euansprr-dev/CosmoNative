// Tests/CosmoOSTests/CommandKCommandRowDedupeTests.swift
// The navigation-target law (July 9 2026): the ⌘K COMMANDS section shows
// each destination exactly once — the parsed primary action claims its
// target first, then system commands, then quicklinks. Quicklink identity
// (quicklinkID) never defeats the dedupe, which was how "Browse Swipes",
// "Open Swipe Gallery", and a "Swipe Gallery" quicklink all rendered at once.

import XCTest
@testable import CosmoOS

@MainActor
final class CommandKCommandRowDedupeTests: XCTestCase {

    private func row(_ title: String, action: CommandKAction) -> CommandKUserCommandRow {
        CommandKUserCommandRow(id: "row-\(title)", title: title, subtitle: "", icon: action.icon, action: action)
    }

    private func domainAction(_ domain: String, title: String, quicklinkID: String? = nil) -> CommandKAction {
        CommandKAction(
            kind: .openDomain,
            title: title,
            subtitle: nil,
            icon: "bolt.fill",
            payload: CommandKActionPayload(domain: domain, quicklinkID: quicklinkID)
        )
    }

    func testQuicklinkIDDoesNotDefeatTargetKey() {
        let system = domainAction("swipeGallery", title: "Browse Swipes")
        let quicklink = domainAction("swipeGallery", title: "Swipe Gallery", quicklinkID: "swipes")
        XCTAssertNotEqual(system.id, quicklink.id, "ids stay distinct for selection")
        XCTAssertEqual(system.navigationTargetKey, quicklink.navigationTargetKey)
    }

    func testGalleryPageAndBrowseDomainAreDistinctTargets() {
        let page = CommandKAction(
            kind: .openSwipeGallery, title: "Open Swipe Gallery", subtitle: nil,
            icon: "rectangle.stack.fill", payload: CommandKActionPayload()
        )
        let browse = domainAction("swipeGallery", title: "Browse Swipes")
        XCTAssertNotEqual(page.navigationTargetKey, browse.navigationTargetKey)
    }

    /// The exact reported bug: typing "swipes" produced three rows. After
    /// dedupe: the primary action owns Browse Swipes, the system row keeps
    /// Open Swipe Gallery (a different destination), the quicklink vanishes.
    func testThreeSwipeRowsCollapse() {
        let primary = domainAction("swipeGallery", title: "Browse Swipes")
        let systemRows = [
            row("Open Swipe Gallery", action: CommandKAction(
                kind: .openSwipeGallery, title: "Open Swipe Gallery", subtitle: nil,
                icon: "rectangle.stack.fill", payload: CommandKActionPayload()
            )),
            row("Browse Swipes", action: domainAction("swipeGallery", title: "Browse Swipes"))
        ]
        let quicklinkRows = [
            row("Swipe Gallery", action: domainAction("swipeGallery", title: "Swipe Gallery", quicklinkID: "swipes"))
        ]

        let deduped = CommandKViewModel.dedupedCommandRows(
            primaryAction: primary,
            systemRows: systemRows,
            quicklinkRows: quicklinkRows
        )

        XCTAssertEqual(deduped.map(\.title), ["Open Swipe Gallery"])
    }

    func testIdeasQuicklinkYieldsToSystemRow() {
        let systemRows = [row("Open Ideas", action: domainAction("ideas", title: "Open Ideas"))]
        let quicklinkRows = [
            row("Ideas", action: domainAction("ideas", title: "Ideas", quicklinkID: "ideas"))
        ]

        let deduped = CommandKViewModel.dedupedCommandRows(
            primaryAction: nil,
            systemRows: systemRows,
            quicklinkRows: quicklinkRows
        )

        XCTAssertEqual(deduped.map(\.title), ["Open Ideas"])
    }

    /// Creation/capture actions are not navigations — they never dedupe.
    func testCreationRowsNeverDedupe() {
        let newTask = CommandKAction(
            kind: .createTask, title: "New Task", subtitle: nil,
            icon: "checkmark.circle.fill", payload: CommandKActionPayload(rawText: "new task")
        )
        let newNote = CommandKAction(
            kind: .createNote, title: "New Note", subtitle: nil,
            icon: "doc.text", payload: CommandKActionPayload(rawText: "new note")
        )
        XCTAssertNil(newTask.navigationTargetKey)

        let deduped = CommandKViewModel.dedupedCommandRows(
            primaryAction: nil,
            systemRows: [row("New Task", action: newTask), row("New Note", action: newNote)],
            quicklinkRows: []
        )

        XCTAssertEqual(deduped.count, 2)
    }

    /// A saved-search quicklink has no system equivalent and survives.
    func testUniqueQuicklinkSurvives() {
        let inquiry = CommandKAction(
            kind: .savedSearch, title: "Inquiries", subtitle: nil,
            icon: "magnifyingglass.circle.fill",
            payload: CommandKActionPayload(queryText: "inquiry", quicklinkID: "inquiries")
        )

        let deduped = CommandKViewModel.dedupedCommandRows(
            primaryAction: nil,
            systemRows: [row("Open Ideas", action: domainAction("ideas", title: "Open Ideas"))],
            quicklinkRows: [row("Inquiries", action: inquiry)]
        )

        XCTAssertEqual(deduped.map(\.title), ["Open Ideas", "Inquiries"])
    }
}
