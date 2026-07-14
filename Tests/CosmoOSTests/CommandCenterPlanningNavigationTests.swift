import XCTest
@testable import CosmoOS

final class CommandCenterPlanningNavigationTests: XCTestCase {
    func testSmartListsRemainUnchanged() {
        XCTAssertEqual(DashboardViewMode.smartLists, [.today, .upcoming, .anytime, .someday, .logbook])
    }

    func testPlanningModesMatchSidebarOrder() {
        // The queue page retired July 2026 — content planning lives in
        // Upcoming's Content lens; `.queue` survives only as a redirect.
        XCTAssertEqual(DashboardViewMode.planningLists, [.habits, .reports])
        XCTAssertEqual(DashboardViewMode.planningLists.map(\.label), ["Habits", "Reports"])
        XCTAssertEqual(DashboardViewMode.planningLists.map(\.icon), ["repeat", "chart.bar"])
    }

    func testUpcomingLensVocabulary() {
        XCTAssertEqual(UpcomingLens.allCases, [.schedule, .content])
        XCTAssertEqual(UpcomingLens.allCases.map(\.label), ["Schedule", "Content"])
    }

    func testPlanningModesAreNotTaskLists() {
        XCTAssertFalse(DashboardViewMode.habits.showsTaskList)
        XCTAssertFalse(DashboardViewMode.reports.showsTaskList)
        XCTAssertTrue(DashboardViewMode.today.showsTaskList)
        XCTAssertTrue(DashboardViewMode.anytime.showsTaskList)
    }

    func testUnifiedSidebarUsesPlanningModesInsteadOfShowReportsForPlanningRows() throws {
        let sidebar = repositoryRoot.appendingPathComponent("Canvas/UnifiedSidebar/UnifiedSidebar.swift")
        let source = try String(contentsOf: sidebar)

        XCTAssertTrue(source.contains("ForEach(DashboardViewMode.planningLists"))
        XCTAssertTrue(source.contains("viewModel.viewMode = mode"))
        XCTAssertFalse(source.contains("planningRow(\"Reports\", icon: \"chart.bar\", isActive: viewModel.showReports)"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
