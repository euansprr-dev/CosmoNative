# Command Center Planning Pages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build full Command Center pages for the existing sidebar Planning rows: Habits, Reports, and Objectives.

**Architecture:** Keep the current sidebar exactly as the navigation source. Extend the same `DashboardViewMode` routing that already opens Today, Upcoming, Anytime, Someday, and Logbook so the existing Habits, Reports, and Objectives rows open full main-content pages. Do not add a floating section toolbar, do not redesign the sidebar, and do not create a second navigation model.

**Tech Stack:** macOS 26 SwiftUI, existing `CommandCenterDashboardViewModel`, `DashboardViewMode`, `CommandCenterHabitEngine`, `ObjectiveEngine`, `ReportData`, `HabitReportData`, DS tokens, `CosmoGlassPanel`, `ProMotionSprings`, XCTest, Xcode build. SwiftPM manifest exists (`CosmoOS` executable product, `CosmoOSTests` test target), but final app verification should use `xcodebuild` per Peak UI's truth pass.

---

## Product Rules

- The sidebar remains visually and structurally unchanged: Smart Lists stay Today, Upcoming, Anytime, Someday, Logbook; Planning stays Habits, Reports, Objectives.
- Clicking Habits, Reports, or Objectives must behave like clicking Upcoming: it selects the sidebar row and swaps the main Command Center content.
- The existing Today right rail may keep its compact Habits/Reports tabs. The new sidebar Planning pages are expanded versions, not replacements for the right rail.
- Reports is where time tracking and habit tracking history merge. Habits is today's operating surface. Objectives is strategic pacing and planning.
- No new floating toolbar. Any page controls live inside the page masthead/content, using the current Command Center visual language.

## Research Decisions

- Habit research: users value fast logging, flexible cadence, forgiving consistency, skip/recovery, and useful pattern feedback. Avoid brittle streak worship and shame states.
- Time/reporting research: the best reports start from review rituals and timeline correction, then summarize allocation. Avoid a giant productivity score, surveillance-coded views, and pretty charts that do not change the next plan.
- Objectives research: objectives matter only when they shape today's choices. Avoid trophy-shelf goals, raw task-count incentives, and hidden objective panels.
- Peak UI: content is the hero; real glass is only chrome; page cards use warm fills; one hero per page; hover/press states and keyboard paths are required.

## File Structure

Create:
- `Canvas/CommandCenter/HabitsSectionView.swift` - full Habits page.
- `Canvas/CommandCenter/ReportsSectionView.swift` - full Reports page.
- `Canvas/CommandCenter/ObjectivesSectionView.swift` - full Objectives page.
- `Canvas/CommandCenter/CommandCenterPlanningPageScaffold.swift` - shared non-floating page masthead, action row, and content width helpers.
- `Tests/CosmoOSTests/CommandCenterPlanningNavigationTests.swift` - routing and mode invariants.

Modify:
- `Canvas/CommandCenter/DashboardViewModeBar.swift` - add planning page cases to `DashboardViewMode`; keep `smartLists` unchanged.
- `Canvas/UnifiedSidebar/UnifiedSidebar.swift` - wire existing Planning rows to those new modes, using the same pattern as Smart Lists.
- `Canvas/CommandCenter/CommandCenterDashboard.swift` - route main content to the three new pages and hide the right rail for full Planning pages.
- `Canvas/CommandCenter/CommandCenterDashboardViewModel.swift` - support planning modes in task accessors and add objective CRUD proxies.
- `Canvas/CommandCenter/CommandCenterMasthead.swift` - add labels/summaries for planning modes if the shared masthead remains used for task modes.
- `Canvas/CommandCenter/WeeklyReportData.swift` - no planned changes for the first implementation; keep report display scope local to `ReportsSectionView.swift`.
- `CosmoOS.xcodeproj/project.pbxproj` - add new Swift files to the Xcode target if this project does not auto-include files.

Do not modify:
- Sidebar layout, spacing, labels, row order, top icon rail, account footer, or global destination model.
- `SidebarDestination`, `WorkspaceSnapshot`, or pane/workbench routing unless a build error proves the existing Command Center route cannot carry the page mode.

---

### Task 1: Preserve Current Navigation And Add Planning Modes

**Files:**
- Modify: `Canvas/CommandCenter/DashboardViewModeBar.swift`
- Modify: `Canvas/CommandCenter/CommandCenterDashboardViewModel.swift`
- Test: `Tests/CosmoOSTests/CommandCenterPlanningNavigationTests.swift`

- [ ] **Step 1: Write routing invariant tests**

Create `Tests/CosmoOSTests/CommandCenterPlanningNavigationTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run the narrow test and confirm it fails**

Run:

```bash
swift test --filter CommandCenterPlanningNavigationTests
```

Expected: FAIL because `planningLists`, `showsTaskList`, and planning enum cases do not exist yet. If SwiftPM cannot compile the app target, record the blocker and use the Xcode test command in Task 10.

- [ ] **Step 3: Extend `DashboardViewMode` with planning cases**

In `Canvas/CommandCenter/DashboardViewModeBar.swift`, update the enum:

```swift
enum DashboardViewMode: String, CaseIterable {
    case today
    case upcoming
    case anytime
    case someday
    case logbook
    case habits
    case reports
    case objectives
    case project
    case area

    static var smartLists: [DashboardViewMode] {
        [.today, .upcoming, .anytime, .someday, .logbook]
    }

    static var planningLists: [DashboardViewMode] {
        [.habits, .reports, .objectives]
    }

    var showsTaskList: Bool {
        switch self {
        case .today, .upcoming, .anytime, .someday, .logbook, .project, .area:
            return true
        case .habits, .reports, .objectives:
            return false
        }
    }
}
```

Update `label`, `icon`, and `activeTint`:

```swift
case .habits: return "Habits"
case .reports: return "Reports"
case .objectives: return "Objectives"
```

```swift
case .habits: return "repeat"
case .reports: return "chart.bar"
case .objectives: return "scope"
```

```swift
case .habits: return DS.entityIdea
case .reports: return DS.info
case .objectives: return DS.accent
```

- [ ] **Step 4: Make planning modes task-safe**

In `CommandCenterDashboardViewModel.currentVisibleTasks`, add:

```swift
case .habits, .reports, .objectives:
    return []
```

In `refreshTaskCollectionsAfterMutation`, add:

```swift
case .habits, .reports, .objectives:
    break
```

- [ ] **Step 5: Run the test again**

Run:

```bash
swift test --filter CommandCenterPlanningNavigationTests
```

Expected: PASS, or document the SwiftPM blocker and defer verification to Task 10.

---

### Task 2: Wire Existing Sidebar Planning Rows To Full Pages

**Files:**
- Modify: `Canvas/UnifiedSidebar/UnifiedSidebar.swift`
- Test: `Tests/CosmoOSTests/CommandCenterPlanningNavigationTests.swift`

- [ ] **Step 1: Add source-check tests for sidebar wiring**

Append to `CommandCenterPlanningNavigationTests`:

```swift
func testUnifiedSidebarUsesPlanningModesInsteadOfShowReportsForPlanningRows() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sidebar = root.appendingPathComponent("Canvas/UnifiedSidebar/UnifiedSidebar.swift")
    let source = try String(contentsOf: sidebar)

    XCTAssertTrue(source.contains("ForEach(DashboardViewMode.planningLists"))
    XCTAssertTrue(source.contains("viewModel.viewMode = mode"))
    XCTAssertFalse(source.contains("planningRow(\"Reports\", icon: \"chart.bar\", isActive: viewModel.showReports)"))
}
```

- [ ] **Step 2: Run and confirm failure**

Run:

```bash
swift test --filter CommandCenterPlanningNavigationTests/testUnifiedSidebarUsesPlanningModesInsteadOfShowReportsForPlanningRows
```

Expected: FAIL because the sidebar currently hard-codes Habits/Reports/Objectives.

- [ ] **Step 3: Replace hard-coded Planning rows with mode rows**

In `SidebarCommandCenterContext`, replace:

```swift
planningRow("Habits", icon: "repeat", isActive: false)
planningRow("Reports", icon: "chart.bar", isActive: viewModel.showReports)
planningRow("Objectives", icon: "scope", isActive: false)
```

with:

```swift
ForEach(DashboardViewMode.planningLists, id: \.self) { mode in
    planningRow(mode)
}
```

Replace the string-based `planningRow` function with:

```swift
private func planningRow(_ mode: DashboardViewMode) -> some View {
    SidebarContextRow(
        title: mode.label,
        icon: mode.icon,
        isActive: currentDestination == .commandCenter &&
            viewModel.viewMode == mode &&
            viewModel.selectedProjectUUID == nil &&
            viewModel.selectedAreaUUID == nil,
        activeTint: mode.activeTint
    ) {
        openCommandCenter()
        withAnimation(ProMotionSprings.snappy) {
            viewModel.selectedProjectUUID = nil
            viewModel.selectedAreaUUID = nil
            viewModel.showReports = false
            viewModel.viewMode = mode
        }
    }
}
```

- [ ] **Step 4: Preserve smart list behavior**

In `smartListRow`, keep the existing pattern but ensure it clears full planning modes:

```swift
viewModel.selectedProjectUUID = nil
viewModel.selectedAreaUUID = nil
viewModel.showReports = false
viewModel.viewMode = mode
```

- [ ] **Step 5: Run the sidebar wiring test**

Run:

```bash
swift test --filter CommandCenterPlanningNavigationTests/testUnifiedSidebarUsesPlanningModesInsteadOfShowReportsForPlanningRows
```

Expected: PASS, or document SwiftPM blocker and defer to Task 10.

---

### Task 3: Route Main Content Without A Floating Toolbar

**Files:**
- Modify: `Canvas/CommandCenter/CommandCenterDashboard.swift`
- Create: `Canvas/CommandCenter/CommandCenterPlanningPageScaffold.swift`

- [ ] **Step 1: Create a shared page scaffold**

Create `CommandCenterPlanningPageScaffold.swift`:

```swift
import SwiftUI

struct CommandCenterPlanningPageScaffold<Content: View, Actions: View>: View {
    let title: String
    let icon: String
    let subtitle: String
    let accent: Color
    @ViewBuilder let actions: Actions
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space18) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            HStack(alignment: .top, spacing: DS.space12) {
                VStack(alignment: .leading, spacing: DS.space6) {
                    Text(title)
                        .font(DS.pageTitle)
                        .foregroundStyle(DS.commandCenterTitleText)

                    HStack(spacing: DS.space8) {
                        Image(systemName: icon)
                            .font(DS.caption.weight(.semibold))
                            .foregroundStyle(accent)
                        Text(subtitle)
                            .font(DS.callout)
                            .foregroundStyle(DS.commandCenterSecondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: DS.space16)
                actions
            }

            Rectangle()
                .fill(DS.commandCenterSeparator)
                .frame(height: 0.5)
        }
    }
}

extension CommandCenterPlanningPageScaffold where Actions == EmptyView {
    init(
        title: String,
        icon: String,
        subtitle: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.accent = accent
        self.actions = EmptyView()
        self.content = content()
    }
}
```

- [ ] **Step 2: Split dashboard center routing into page cases**

In `CommandCenterDashboard.centerColumn`, route planning modes before the task-list content:

```swift
private var centerColumn: some View {
    VStack(alignment: .leading, spacing: DS.space16) {
        Group {
            switch viewModel.viewMode {
            case .habits:
                HabitsSectionView(viewModel: viewModel, composer: composer)
            case .reports:
                ReportsSectionView(viewModel: viewModel)
            case .objectives:
                ObjectivesSectionView(viewModel: viewModel)
            default:
                existingTaskOrProjectContent
            }
        }
        .id(centerContentTransitionID)
        .transition(.opacity)

        Spacer(minLength: 0)

        if shouldShowObjectivesFooter {
            DashboardObjectivesBar(viewModel: viewModel)
        }
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, DS.space16)
    .animation(ProMotionSprings.gentle, value: centerContentTransitionID)
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("com.cosmo.commandCenter.keyboardAction"))) { notification in
        guard viewModel.viewMode.showsTaskList else { return }
        handleKeyboardAction(notification)
    }
}
```

Extract the current project/upcoming/today logic into:

```swift
@ViewBuilder
private var existingTaskOrProjectContent: some View {
    if viewModel.viewMode == .project, let projectUUID = viewModel.selectedProjectUUID,
       let project = viewModel.projects.first(where: { $0.uuid == projectUUID }) {
        ProjectDetailView(project: project, viewModel: viewModel)
    } else if viewModel.viewMode == .upcoming {
        CommandCenterMasthead(viewModel: viewModel)
        UpcomingBoardView(viewModel: viewModel, composer: composer)
            .frame(maxHeight: .infinity)
    } else {
        CommandCenterMasthead(viewModel: viewModel)
        DashboardTimeTracker(viewModel: viewModel)
        gradientDivider
        DashboardTaskList(viewModel: viewModel, composer: composer) { task in
            withAnimation(ProMotionSprings.snappy) {
                selectedTaskForDetail = task
                viewModel.showReports = false
            }
        }
    }
}
```

- [ ] **Step 3: Hide the right rail for full planning pages**

In the dashboard body, replace unconditional `rightColumn` with:

```swift
if !viewModel.viewMode.isFullPlanningPage {
    rightColumn
}
```

Add to `DashboardViewMode`:

```swift
var isFullPlanningPage: Bool {
    switch self {
    case .habits, .reports, .objectives: return true
    default: return false
    }
}
```

- [ ] **Step 4: Preserve the objectives footer only for task/project surfaces**

Add:

```swift
private var shouldShowObjectivesFooter: Bool {
    viewModel.viewMode != .today &&
    viewModel.viewMode != .upcoming &&
    !viewModel.viewMode.isFullPlanningPage
}
```

- [ ] **Step 5: Update transition identity**

Keep `centerContentTransitionID` simple:

```swift
private var centerContentTransitionID: String {
    [
        viewModel.viewMode.rawValue,
        viewModel.selectedProjectUUID ?? "no-project",
        viewModel.selectedAreaUUID ?? "no-area",
        viewModel.showReports ? "rail-reports" : "rail-main"
    ].joined(separator: ":")
}
```

---

### Task 4: Build The Full Habits Page

**Files:**
- Create: `Canvas/CommandCenter/HabitsSectionView.swift`
- Modify: `Canvas/CommandCenter/CommandCenterDashboardViewModel.swift` only if helper computed properties are needed.

- [ ] **Step 1: Create the page shell**

Create `HabitsSectionView.swift`:

```swift
import SwiftUI

struct HabitsSectionView: View {
    @ObservedObject var viewModel: CommandCenterDashboardViewModel
    let composer: CommandCenterComposerController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CommandCenterPlanningPageScaffold(
            title: "Habits",
            icon: "repeat",
            subtitle: subtitle,
            accent: DS.entityIdea,
            actions: { headerActions },
            content: { content }
        )
        .task {
            await viewModel.loadHabits()
            await viewModel.loadHabitReport()
            await viewModel.loadTodayTimeData()
        }
    }

    private var subtitle: String {
        let complete = viewModel.habits.filter(\.isTodayComplete).count
        return "\(complete)/\(viewModel.habits.count) complete today · \(viewModel.todayTrackedMinutes)m tracked"
    }
}
```

- [ ] **Step 2: Add header actions without creating a toolbar**

Inside `HabitsSectionView`:

```swift
private var headerActions: some View {
    HStack(spacing: DS.space8) {
        CommandCenterComposerTrigger(composer: composer, alignment: .trailing) { anchor in
            .habitLibrary(anchor: anchor)
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(DS.commandCenterSecondaryText)
                .frame(width: 36, height: 36)
                .background(DS.glassInputFill, in: Circle())
                .overlay(Circle().stroke(DS.glassBorder, lineWidth: 0.5))
        }
        .help("Manage habits")
        .accessibilityLabel("Manage habits")

        CommandCenterComposerTrigger(composer: composer, alignment: .trailing) { anchor in
            .habitEditor(habit: nil, anchor: anchor)
        } label: {
            Image(systemName: "plus")
                .font(DS.callout.weight(.bold))
                .foregroundStyle(DS.textOnAccent)
                .frame(width: 36, height: 36)
                .background(DS.accent, in: Circle())
        }
        .help("Add habit")
        .accessibilityLabel("Add habit")
    }
}
```

- [ ] **Step 3: Add the content layout**

Use one hero and two supporting columns:

```swift
private var content: some View {
    ScrollView(.vertical) {
        LazyVStack(alignment: .leading, spacing: DS.space16) {
            HabitTodayHero(viewModel: viewModel)

            HStack(alignment: .top, spacing: DS.space16) {
                HabitPracticeList(viewModel: viewModel, composer: composer)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: DS.space12) {
                    HabitRecoveryPane(viewModel: viewModel)
                    HabitConsistencyPane(viewModel: viewModel)
                }
                .frame(width: 320)
            }
        }
        .padding(.bottom, DS.space24)
    }
    .scrollIndicators(.hidden)
    .scrollEdgeEffectStyle(.soft, for: .all)
}
```

- [ ] **Step 4: Implement `HabitTodayHero`**

Hero purpose: fast read, not a chart wall.

```swift
private struct HabitTodayHero: View {
    @ObservedObject var viewModel: CommandCenterDashboardViewModel

    var body: some View {
        CommandCenterMaterialPanel(cornerRadius: 14, contentPadding: DS.space16) {
            HStack(alignment: .center, spacing: DS.space18) {
                VStack(alignment: .leading, spacing: DS.space6) {
                    Text("Today's practice")
                        .font(DS.title2)
                        .foregroundStyle(DS.commandCenterTitleText)
                    Text(summary)
                        .font(DS.callout)
                        .foregroundStyle(DS.commandCenterSecondaryText)
                }

                Spacer()

                Text("\(completionPercent)%")
                    .font(DS.pageTitle)
                    .monospacedDigit()
                    .foregroundStyle(DS.accent)
                    .accessibilityLabel("\(completionPercent) percent of habits complete today")
            }
        }
    }

    private var completionPercent: Int {
        guard !viewModel.habits.isEmpty else { return 0 }
        let complete = viewModel.habits.filter(\.isTodayComplete).count
        return Int(Double(complete) / Double(viewModel.habits.count) * 100)
    }

    private var summary: String {
        let remaining = viewModel.habits.filter { !$0.isTodayComplete }.count
        if remaining == 0 { return "Everything planned for today is complete." }
        return "\(remaining) still open · complete, reschedule, or leave it for review."
    }
}
```

- [ ] **Step 5: Implement `HabitPracticeList`**

Rows must support <5 second logging:

```swift
private struct HabitPracticeList: View {
    @ObservedObject var viewModel: CommandCenterDashboardViewModel
    let composer: CommandCenterComposerController

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            sectionTitle("Today")

            if viewModel.habits.isEmpty {
                CommandCenterEmptyPane(
                    icon: "repeat",
                    title: "Start with one practice",
                    subtitle: "Add a habit that your tasks or focus sessions can feed automatically."
                )
            } else {
                ForEach(viewModel.habits) { habit in
                    HabitPlanningRow(habit: habit, viewModel: viewModel, composer: composer)
                }
            }
        }
    }
}
```

`HabitPlanningRow` should reuse the visual language from `DashboardHabitOrbitCard`: ring, title, 7-day dots, completion count, tracked minutes, and a single icon button for manual completion. Add `.help()`, accessibility labels, hover lift, and no raw `.font(.system(size:))`.

- [ ] **Step 6: Implement recovery and consistency panes**

`HabitRecoveryPane` should list incomplete habits with weak recent consistency:

```swift
private var recoveryHabits: [HabitState] {
    viewModel.habits
        .filter { !$0.isTodayComplete && $0.consistencyCount <= 3 }
        .prefix(5)
        .map { $0 }
}
```

Use recovery language:
- "Needs a lighter target"
- "No work logged this week"
- "Complete once today"

Do not use red failure language unless the user is actively at risk of losing meaningful data.

`HabitConsistencyPane` should show a 7-day matrix from `last7Days`, plus overall completion if `habitReportData` is loaded.

---

### Task 5: Build The Full Reports Page

**Files:**
- Create: `Canvas/CommandCenter/ReportsSectionView.swift`
- Modify: `Canvas/CommandCenter/WeeklyReportData.swift` only if adding a local `ReportPageScope` is cleaner.

- [ ] **Step 1: Create the page shell**

Create `ReportsSectionView.swift`:

```swift
import SwiftUI

struct ReportsSectionView: View {
    @ObservedObject var viewModel: CommandCenterDashboardViewModel
    @State private var scope: ReportPageScope = .week
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CommandCenterPlanningPageScaffold(
            title: "Reports",
            icon: "chart.bar",
            subtitle: subtitle,
            accent: DS.info,
            actions: { scopeControl },
            content: { content }
        )
        .task { await loadScope() }
        .onChange(of: scope) { _, _ in Task { await loadScope() } }
    }
}

private enum ReportPageScope: String, CaseIterable, Identifiable {
    case today
    case week
    case month
    case habits

    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "Today"
        case .week: return "Week"
        case .month: return "Month"
        case .habits: return "Habits"
        }
    }
}
```

This is an internal report scope control, not a Command Center navigation toolbar.

- [ ] **Step 2: Implement scope control inside the masthead**

Use a flat warm segmented control:

```swift
private var scopeControl: some View {
    HStack(spacing: DS.space2) {
        ForEach(ReportPageScope.allCases) { item in
            Button {
                withAnimation(ProMotionSprings.snappy) { scope = item }
            } label: {
                Text(item.title)
                    .font(DS.buttonText)
                    .foregroundStyle(scope == item ? DS.text : DS.textMuted)
                    .padding(.horizontal, DS.space10)
                    .frame(height: 32)
                    .background(scope == item ? DS.surfaceElevated : Color.clear, in: Capsule())
            }
            .buttonStyle(.plain)
            .help(item.title)
            .accessibilityAddTraits(scope == item ? .isSelected : [])
        }
    }
    .padding(DS.space2)
    .background(DS.glassInputFill, in: Capsule())
    .overlay(Capsule().stroke(DS.glassBorder, lineWidth: 0.5))
}
```

- [ ] **Step 3: Load data by scope**

```swift
@MainActor
private func loadScope() async {
    switch scope {
    case .today:
        await viewModel.loadTodayTimeData()
        await viewModel.loadTodaySessions()
        await viewModel.loadHabits()
    case .week:
        viewModel.selectedReportTab = .week
        await viewModel.loadWeeklyReport()
        await viewModel.loadHabitReport()
    case .month:
        viewModel.selectedReportTab = .month
        await viewModel.loadMonthReport()
        await viewModel.loadHabitReport()
    case .habits:
        viewModel.selectedReportTab = .habits
        await viewModel.loadHabitReport()
    }
}
```

- [ ] **Step 4: Build Today Review**

Today Review answers "Did the plan survive contact with the day?"

```swift
private var todayReview: some View {
    HStack(alignment: .top, spacing: DS.space16) {
        TodaySessionTimeline(viewModel: viewModel)
            .frame(maxWidth: .infinity)

        VStack(alignment: .leading, spacing: DS.space12) {
            FocusQualityPane(viewModel: viewModel)
            AttributionPane(viewModel: viewModel)
        }
        .frame(width: 320)
    }
}
```

`TodaySessionTimeline` uses `viewModel.todaySessions`, not raw app logs. It should display session title, habit/intent label, start/end, duration, and focus score. Empty state: "Start a focus session from Today to build your review timeline."

- [ ] **Step 5: Build Week/Month allocation**

Use existing `weeklyReportData` for week and month. Build:
- `ReportHeroTotals`: total tracked time, tasks completed, sessions, average focus.
- `AllocationBars`: stacked or vertical bars by day using `DayReportEntry.trackedMinutes` and `dominantIntent`.
- `IntentBreakdownList`: top habit/intent allocations with minutes and percentage.
- `ScheduleRealityPane`: first pass can show completed tasks and sessions; planned-vs-actual can be added when schedule-block data is wired.

Use this layout:

```swift
private func reportOverview(_ report: ReportData) -> some View {
    LazyVStack(alignment: .leading, spacing: DS.space16) {
        ReportHeroTotals(report: report)
        AllocationBars(report: report)
        HStack(alignment: .top, spacing: DS.space16) {
            IntentBreakdownList(report: report)
            FocusPatternPane(report: report)
        }
    }
}
```

- [ ] **Step 6: Build habit history as part of Reports**

For `scope == .habits`, show:
- overall completion
- per-habit completion rows
- 7/30 day heat strips
- "needs attention" insights

Reuse `HabitReportData` and `HabitReportEntry`. Do not duplicate the operational quick-log UI from Habits.

- [ ] **Step 7: Avoid report fluff**

Do not add:
- a global productivity score
- gamified ranks
- shame-colored failure cards
- AI prose that cannot trace back to sessions
- pie charts that do not lead to a next action

Every insight row should have a small action label, such as "review habit", "start focus", "schedule work", or "adjust target", even if the first pass only shows the label.

---

### Task 6: Build The Full Objectives Page

**Files:**
- Create: `Canvas/CommandCenter/ObjectivesSectionView.swift`
- Modify: `Canvas/CommandCenter/CommandCenterDashboardViewModel.swift`
- Test: `Tests/CosmoOSTests/CommandCenterPlanningNavigationTests.swift`

- [ ] **Step 1: Add objective VM proxies**

In `CommandCenterDashboardViewModel`, add:

```swift
func createObjective(
    title: String,
    targetValue: Double,
    unit: String,
    dataSource: ObjectiveDataSource,
    quarter: Int? = nil,
    year: Int? = nil
) async {
    do {
        try await objectiveEngine.createObjective(
            title: title,
            targetValue: targetValue,
            unit: unit,
            dataSource: dataSource,
            quarter: quarter,
            year: year
        )
    } catch {
        PersistenceHealth.note(.writeFailure, context: "Dashboard.createObjective", detail: error.localizedDescription)
    }
}

func updateObjective(
    id: String,
    title: String,
    targetValue: Double,
    unit: String,
    dataSource: ObjectiveDataSource
) async {
    do {
        try await objectiveEngine.updateObjective(
            id: id,
            title: title,
            targetValue: targetValue,
            unit: unit,
            dataSource: dataSource
        )
    } catch {
        PersistenceHealth.note(.writeFailure, context: "Dashboard.updateObjective(\(id.prefix(8)))", detail: error.localizedDescription)
    }
}

func deleteObjective(id: String) async {
    do {
        try await objectiveEngine.deleteObjective(id: id)
    } catch {
        PersistenceHealth.note(.writeFailure, context: "Dashboard.deleteObjective(\(id.prefix(8)))", detail: error.localizedDescription)
    }
}
```

- [ ] **Step 2: Create the page shell**

Create `ObjectivesSectionView.swift`:

```swift
import SwiftUI

struct ObjectivesSectionView: View {
    @ObservedObject var viewModel: CommandCenterDashboardViewModel
    @State private var showingEditor = false

    var body: some View {
        CommandCenterPlanningPageScaffold(
            title: "Objectives",
            icon: "scope",
            subtitle: subtitle,
            accent: DS.accent,
            actions: { addButton },
            content: { content }
        )
        .sheet(isPresented: $showingEditor) {
            ObjectiveEditorSheet(viewModel: viewModel)
        }
    }

    private var subtitle: String {
        let active = viewModel.objectives.filter { $0.progress < 1 }.count
        return "Q\(currentQuarter) · \(active) active · pacing from real work"
    }
}
```

- [ ] **Step 3: Add the objective hero**

Hero purpose: "Are we on pace?"

```swift
private var content: some View {
    ScrollView(.vertical) {
        LazyVStack(alignment: .leading, spacing: DS.space16) {
            ObjectiveQuarterHero(objectives: viewModel.objectives)

            HStack(alignment: .top, spacing: DS.space16) {
                ObjectivePacingGrid(viewModel: viewModel)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: DS.space12) {
                    ObjectiveReviewPane(viewModel: viewModel)
                    ObjectiveDataSourcesPane()
                }
                .frame(width: 320)
            }
        }
        .padding(.bottom, DS.space24)
    }
    .scrollIndicators(.hidden)
    .scrollEdgeEffectStyle(.soft, for: .all)
}
```

`ObjectiveQuarterHero` should show active count, completed count, average progress, and one calm health line. It must not use a trophy/gamification tone.

- [ ] **Step 4: Add `ObjectivePacingGrid`**

Each `ObjectivePacingCard` shows:
- title
- current value / target value / unit
- `TrackAndBead` or equivalent pacing line
- `PaceStatus` chip
- "Next planning move" row:
  - `.behind`: "schedule a focus block"
  - `.atRisk`: "review target"
  - `.onTrack`: "keep cadence"
  - `.completed`: "close or archive"
  - `.justStarted`: "choose first session"

Use `DS.accent` as punctuation only. Use `objective.paceStatus.color` carefully; if it is a raw color from `ObjectiveEngine`, do not let it dominate the page.

- [ ] **Step 5: Add `ObjectiveEditorSheet`**

Fields:
- title
- target value
- unit
- data source picker from `ObjectiveDataSource.allCases`

Use DS input styles and explicit labels. Primary button: "Create Objective". No decorative hero inside the sheet.

- [ ] **Step 6: Keep objective-to-task linking out of this implementation**

Do not add `objectiveUUID` to `TaskMetadata` in this implementation. The current model has habit attribution but no objective attribution. The Objectives page must rely on existing `ObjectiveDataSource` computation, existing `.objective` atoms, and `ObjectiveEngine` progress. Explicit objective links to tasks, projects, sessions, and output atoms are out of scope for this plan.

---

### Task 7: Keep Today Right Rail Behavior Intact

**Files:**
- Modify: `Canvas/CommandCenter/CommandCenterDashboard.swift`

- [ ] **Step 1: Preserve compact right rail tabs**

The existing right rail `Habits` and `Reports` tabs should still work on task pages. Keep `viewModel.showReports` scoped to that rail.

- [ ] **Step 2: Prevent rail state from selecting sidebar Planning rows**

Sidebar Planning row active state must be based on `viewModel.viewMode == .reports`, not `viewModel.showReports`.

- [ ] **Step 3: Clear selected task when opening full planning pages**

In the sidebar planning row action, clear:

```swift
viewModel.selectedProjectUUID = nil
viewModel.selectedAreaUUID = nil
viewModel.showReports = false
viewModel.viewMode = mode
```

If `selectedTaskForDetail` remains inside `CommandCenterDashboard`, add an `onChange`:

```swift
.onChange(of: viewModel.viewMode) { _, mode in
    if mode.isFullPlanningPage {
        selectedTaskForDetail = nil
        composer.dismiss()
    }
}
```

---

### Task 8: Peak UI Polish Pass

**Files:**
- Modify all new section files from Tasks 4-6.

- [ ] **Step 1: Hierarchy pass**

Ensure:
- Habits hero: today's completion and remaining action.
- Reports hero: selected review scope and total tracked/focus signal.
- Objectives hero: quarter pacing.

No page gets two equally loud hero elements.

- [ ] **Step 2: Material pass**

Use:
- Page background inherited from Command Center.
- `CommandCenterMaterialPanel` or `.dsGlassCard()` for content cards.
- `.cosmoGlassPanel` only for existing sidebar/right rail chrome.
- No `.regularMaterial`, `.ultraThinMaterial`, fake blur, or glass-on-glass.

- [ ] **Step 3: Motion pass**

Use:
- `ProMotionSprings.snappy` for selection.
- `ProMotionSprings.hover` for card hover.
- `ProMotionSprings.gentle` for page transitions.
- `ProMotionSprings.cascade(index: min(index, 8))` only for entrance lists, gated by Reduce Motion.

- [ ] **Step 4: Manners pass**

Every interactive control in the new section files must have:
- `.buttonStyle(.plain)` for every custom-styled `Button`
- hover feedback
- `.help()`
- accessibility label
- 44 pt hit target for icon-only actions
- no `.onTapGesture` for button behavior

- [ ] **Step 5: Typography/color pass**

Search new files for:

```bash
rg "font\\(\\.system|foregroundColor|cornerRadius\\(" Canvas/CommandCenter/HabitsSectionView.swift Canvas/CommandCenter/ReportsSectionView.swift Canvas/CommandCenter/ObjectivesSectionView.swift Canvas/CommandCenter/CommandCenterPlanningPageScaffold.swift
```

Expected: no matches except any unavoidable SF Symbol sizing. Prefer DS fonts, `foregroundStyle`, and `clipShape(.rect(cornerRadius:style:))`.

---

### Task 9: Xcode Project Integration

**Files:**
- Modify: `CosmoOS.xcodeproj/project.pbxproj` if needed.

- [ ] **Step 1: Check whether new files are compiled**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build
```

Expected: either PASS or FAIL with missing symbols/files.

- [ ] **Step 2: Add files to the Xcode target if missing**

If build cannot find new views, add:
- `CommandCenterPlanningPageScaffold.swift`
- `HabitsSectionView.swift`
- `ReportsSectionView.swift`
- `ObjectivesSectionView.swift`
- `CommandCenterPlanningNavigationTests.swift`

Use `add_file_to_project.py` for Xcode project insertion. If that script fails, stop and report the script error before editing `project.pbxproj` manually.

---

### Task 10: Verification

**Files:**
- No source edits unless tests expose issues.

- [ ] **Step 1: SwiftPM narrow test attempt**

Because `Package.swift` exists with executable product `CosmoOS` and test target `CosmoOSTests`, attempt:

```bash
swift test --filter CommandCenterPlanningNavigationTests
```

Expected: PASS. If SwiftPM fails due app-target package graph or platform-resource issues, summarize the top blocker and rely on Xcode tests/build.

- [ ] **Step 2: Xcode tests for Command Center**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/CommandCenterPlanningNavigationTests test
```

Expected: PASS.

- [ ] **Step 3: Existing Command Center regression tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/CommandCenterCalendarLayoutTests -only-testing:CosmoOSTests/CommandCenterComposerTests test
```

Expected: PASS.

- [ ] **Step 4: Full debug build**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build
```

Expected: PASS.

- [ ] **Step 5: Manual UI checks**

Run the app and verify:
- Clicking Today opens Today, unchanged.
- Clicking Upcoming opens Upcoming, unchanged.
- Clicking Anytime opens Anytime, unchanged.
- Clicking Someday opens Someday, unchanged.
- Clicking Logbook opens Logbook, unchanged.
- Clicking Habits selects the Habits row and opens the full Habits page.
- Clicking Reports selects the Reports row and opens the full Reports page.
- Clicking Objectives selects the Objectives row and opens the full Objectives page.
- No floating section toolbar appears.
- Today right rail Habits/Reports still works on task pages.
- Keyboard task actions do not complete/start hidden tasks while viewing Habits, Reports, or Objectives.
- Reduce Motion removes decorative entrance animation.
- Sidebar screenshot still matches the user's provided structure.

---

## Execution Handoff

Plan complete. Recommended implementation mode: subagent-driven development, one worker per page after Task 1-3 routing lands:

- Worker A: routing + sidebar wiring + tests.
- Worker B: Habits full page.
- Worker C: Reports full page.
- Worker D: Objectives full page.
- Main agent: Peak UI pass, Xcode project integration, final verification.
