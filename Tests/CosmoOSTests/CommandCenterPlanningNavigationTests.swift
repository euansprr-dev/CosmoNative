import XCTest
@testable import CosmoOS

final class CommandCenterPlanningNavigationTests: XCTestCase {
    func testSmartListsRemainUnchanged() {
        XCTAssertEqual(DashboardViewMode.smartLists, [.today, .upcoming, .anytime, .someday, .logbook])
    }

    func testPlanningModesMatchSidebarOrder() {
        XCTAssertEqual(DashboardViewMode.planningLists, [.habits, .reports, .objectives])
        XCTAssertEqual(DashboardViewMode.planningLists.map(\.label), ["Habits", "Reports", "Objectives"])
        XCTAssertEqual(DashboardViewMode.planningLists.map(\.icon), ["repeat", "chart.bar", "scope"])
    }

    func testPlanningModesAreNotTaskLists() {
        XCTAssertFalse(DashboardViewMode.habits.showsTaskList)
        XCTAssertFalse(DashboardViewMode.reports.showsTaskList)
        XCTAssertFalse(DashboardViewMode.objectives.showsTaskList)
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
