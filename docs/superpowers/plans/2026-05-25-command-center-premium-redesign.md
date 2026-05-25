# Command Center Premium Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the Command Center Today, Upcoming, and Habits surfaces so they feel like a premium Apple-quality CosmoOS glass workspace while preserving the current simple three-zone structure.

**Architecture:** Keep `CommandCenterDashboard` as the scene root and add a small shared chrome layer for Command Center-specific glass rows, rails, section headers, and panel treatments. Apply those primitives to the masthead, time tracker, task ledger, objectives bar, habit rail, and calendar blocks without changing task, habit, calendar, or persistence behavior.

**Tech Stack:** Swift 5, SwiftUI, macOS, existing `DS` design tokens, `CosmoGlassPanel`, `ProMotionSprings`, existing Command Center view models and XCTest target.

---

## File Structure

- Create: `Canvas/CommandCenter/CommandCenterSurfaceChrome.swift`
  - Shared visual primitives for the Command Center redesign.
- Modify: `Canvas/CommandCenter/CommandCenterDashboard.swift`
  - Wrap the right rail and tighten the shell spacing and transitions.
- Modify: `Canvas/CommandCenter/CommandCenterMasthead.swift`
  - Refine masthead hierarchy and date controls.
- Modify: `Canvas/CommandCenter/DashboardTimeTracker.swift`
  - Convert the tracker into a premium command strip with shared chrome.
- Modify: `Canvas/CommandCenter/DashboardTaskList.swift`
  - Upgrade task rows, section headers, empty states, and add row integration.
- Modify: `Canvas/CommandCenter/DashboardHabitPanel.swift`
  - Make the habits rail feel like a glass inspector.
- Modify: `Canvas/CommandCenter/DashboardObjectivesBar.swift`
  - Match the bottom objectives surface to the new panel language.
- Modify: `Canvas/CommandCenter/UpcomingBoardView.swift`
  - Polish calendar grid, day headers, entries, all-day chips, and editor popover.
- Modify: `CosmoOS.xcodeproj/project.pbxproj`
  - Add `CommandCenterSurfaceChrome.swift` only when the app target does not compile the new Swift file automatically.

---

### Task 1: Shared Command Center Chrome

**Files:**
- Create: `Canvas/CommandCenter/CommandCenterSurfaceChrome.swift`
- Modify: `CosmoOS.xcodeproj/project.pbxproj` only when the new file is not part of the app target

- [ ] **Step 1: Create shared chrome primitives**

Create `Canvas/CommandCenter/CommandCenterSurfaceChrome.swift` with these types:

```swift
import SwiftUI

struct CommandCenterGlassRail<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content

    init(cornerRadius: CGFloat = 22, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(DS.space12)
            .cosmoGlassPanel(sceneMaterial: .neutral, role: .globalSidebar, cornerRadius: cornerRadius)
    }
}

struct CommandCenterMaterialPanel<Content: View>: View {
    let cornerRadius: CGFloat
    let contentPadding: CGFloat
    @ViewBuilder let content: Content

    init(cornerRadius: CGFloat = 10, contentPadding: CGFloat = DS.space10, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(contentPadding)
            .background(DS.commandChromePanelFill, in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DS.commandChromeBorder, lineWidth: 0.5)
            }
    }
}

struct CommandCenterLedgerSectionHeader: View {
    let title: String
    let count: String?
    let tint: Color
    var actionTitle: String?
    var actionIcon: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: DS.space6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)

            if let count {
                Text(count)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(tint.opacity(0.62))
                    .monospacedDigit()
            }

            Rectangle()
                .fill(DS.commandCenterSeparator)
                .frame(height: 0.5)
                .padding(.leading, DS.space8)

            Spacer(minLength: 0)

            if let actionTitle, let actionIcon, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: actionIcon)
                        .font(DS.caption)
                        .foregroundStyle(tint.opacity(0.9))
                        .padding(.horizontal, DS.space6)
                        .padding(.vertical, DS.space4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.space10)
        .padding(.top, DS.space12)
        .padding(.bottom, DS.space6)
    }
}

struct CommandCenterRowGlass: View {
    let isActive: Bool
    let isSelected: Bool
    let isHovered: Bool
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(fill)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(stroke, lineWidth: isSelected ? 1 : 0.5)
            }
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
    }

    private var fill: Color {
        if isActive { return DS.glassInputFillFocused }
        if isSelected { return tint.opacity(0.10) }
        if isHovered { return DS.glassCardFill }
        return Color.clear
    }

    private var stroke: Color {
        if isActive { return tint.opacity(0.36) }
        if isSelected { return tint.opacity(0.26) }
        if isHovered { return DS.glassBorder }
        return Color.clear
    }

    private var shadowColor: Color {
        (isActive || isSelected || isHovered) ? Color.black.opacity(0.055) : Color.clear
    }

    private var shadowRadius: CGFloat {
        isActive || isSelected ? 8 : (isHovered ? 4 : 0)
    }

    private var shadowY: CGFloat {
        isActive || isSelected ? 2 : (isHovered ? 1 : 0)
    }
}

struct CommandCenterEmptyPane: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: DS.space8) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(DS.textMuted)
                .frame(width: 44, height: 44)

            Text(title)
                .font(DS.headline)
                .foregroundStyle(DS.text)

            Text(subtitle)
                .font(DS.subheadline)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space24)
        .padding(.horizontal, DS.space16)
        .dsGlassCard(cornerRadius: 12)
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 2: Confirm target membership**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build
```

Expected after Task 1 alone: build succeeds because the new file compiles and no caller uses it yet. If the app target does not compile the new file, add it to `CosmoOS.xcodeproj/project.pbxproj` using the repo's existing project file pattern, then run the same build command again.

- [ ] **Step 3: Commit shared chrome**

```bash
git add Canvas/CommandCenter/CommandCenterSurfaceChrome.swift CosmoOS.xcodeproj/project.pbxproj
git commit -m "style: add command center glass chrome primitives"
```

---

### Task 2: Dashboard Shell And Right Rail

**Files:**
- Modify: `Canvas/CommandCenter/CommandCenterDashboard.swift`

- [ ] **Step 1: Wrap the right column in the glass rail**

In `rightColumn`, keep the existing tab and switch logic, but wrap the `VStack` content in `CommandCenterGlassRail(cornerRadius: 22)`. Keep the `.frame(width: 280)` outside the rail so layout remains stable.

```swift
private var rightColumn: some View {
    CommandCenterGlassRail(cornerRadius: 22) {
        VStack(alignment: .leading, spacing: DS.space16) {
            rightColumnTabs
            rightColumnContent
            Spacer(minLength: 0)
        }
    }
    .frame(width: 280)
    .padding(.leading, DS.space20)
    .onChange(of: visibleTaskUUIDs) { _, taskUUIDs in
        clearDeletedTaskState(visibleTaskUUIDs: taskUUIDs)
    }
}
```

- [ ] **Step 2: Extract `rightColumnTabs` and `rightColumnContent`**

Add these helpers below `rightColumn`:

```swift
private var rightColumnTabs: some View {
    HStack(spacing: 0) {
        if selectedTaskForDetail != nil {
            rightColumnTab("Details", icon: "info.circle", isActive: showingDetailTab == .details)
        }
        rightColumnTab("Habits", icon: "checkmark.circle", isActive: showingDetailTab == .habits)
        rightColumnTab("Reports", icon: "chart.bar", isActive: showingDetailTab == .reports)
    }
}

@ViewBuilder
private var rightColumnContent: some View {
    switch showingDetailTab {
    case .details:
        if let task = resolvedSelectedTask {
            TaskDetailPanel(
                task: task,
                viewModel: viewModel,
                composer: composer,
                onDeleted: { deletedTaskUUID in
                    handleDeletedSelectedTask(uuid: deletedTaskUUID)
                }
            )
            .id(task.uuid)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .cosmoGlassSceneSignal(
                id: "command-center-task-detail-\(task.uuid)",
                source: .commandTask,
                color: DS.entityTask,
                intensity: 0.26
            )
        }
    case .reports:
        ScrollView(.vertical) {
            DashboardReportsPanel(viewModel: viewModel)
        }
        .scrollIndicators(.never)
        .cosmoGlassSceneSignal(
            id: "command-center-reports",
            source: .commandCalendar,
            color: DS.info,
            intensity: 0.24
        )
    case .habits:
        DashboardHabitPanel(viewModel: viewModel, composer: composer)
            .cosmoGlassSceneSignal(
                id: "command-center-habits",
                source: .commandHabit,
                color: DS.green,
                intensity: 0.28
            )
    }
}
```

- [ ] **Step 3: Remove the old leading separator overlay**

Delete the old `.overlay(alignment: .leading)` separator from `rightColumn`. The glass panel edge now provides separation.

- [ ] **Step 4: Build**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build
```

Expected: build succeeds.

- [ ] **Step 5: Commit shell polish**

```bash
git add Canvas/CommandCenter/CommandCenterDashboard.swift
git commit -m "style: apply glass rail to command center inspector"
```

---

### Task 3: Masthead, Time Tracker, And Objectives

**Files:**
- Modify: `Canvas/CommandCenter/CommandCenterMasthead.swift`
- Modify: `Canvas/CommandCenter/DashboardTimeTracker.swift`
- Modify: `Canvas/CommandCenter/DashboardObjectivesBar.swift`

- [ ] **Step 1: Refine masthead controls**

In `CommandCenterMasthead`, keep the serif title and existing date logic. Update the Today and Upcoming date reset buttons to use `DS.glassInputFill` plus `DS.glassBorder` so they match Command-K chips:

```swift
.background(DS.glassInputFill, in: .rect(cornerRadius: 8))
.overlay(
    RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(DS.glassBorder, lineWidth: 0.5)
)
```

Keep icon-only chevrons at `30 x 30` minimum and preserve their accessibility labels.

- [ ] **Step 2: Convert `DashboardTimeTracker` to `CommandCenterMaterialPanel`**

Replace the final `.padding`, `.background`, and `.overlay` chain in `compactCommandStrip` with:

```swift
.padding(.horizontal, DS.space10)
.padding(.vertical, DS.space8)
.background {
    RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(DS.commandChromePanelFill)
}
.overlay {
    RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(DS.commandChromeBorder, lineWidth: 0.5)
}
```

Then update `commandButton` to use `DS.glassInputFill` for secondary buttons and `DS.accent` only for the active primary action.

- [ ] **Step 3: Match `activeTimerCard` to the panel language**

In `activeTimerCard`, use `DS.glassCardFill` for the background and `DS.glassBorder` for the stroke. Keep the timer typography unchanged because the monospaced light timer is already the right focal element.

- [ ] **Step 4: Update `DashboardObjectivesBar` to share the same radius and border**

Change the objectives container radius from `8` to `10` and use:

```swift
.background(DS.commandChromePanelFill, in: .rect(cornerRadius: 10))
.overlay(
    RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(DS.commandChromeBorder, lineWidth: 0.5)
)
```

- [ ] **Step 5: Build**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build
```

Expected: build succeeds.

- [ ] **Step 6: Commit masthead and command strips**

```bash
git add Canvas/CommandCenter/CommandCenterMasthead.swift Canvas/CommandCenter/DashboardTimeTracker.swift Canvas/CommandCenter/DashboardObjectivesBar.swift
git commit -m "style: polish command center masthead and tracker"
```

---

### Task 4: Today Task Ledger

**Files:**
- Modify: `Canvas/CommandCenter/DashboardTaskList.swift`

- [ ] **Step 1: Replace section header rendering with ledger styling**

In `sectionHeader`, keep `CommandCenterComposerTrigger` for the reschedule action so the popover receives a real anchor. Replace the visual structure with the ledger styling below:

```swift
HStack(spacing: DS.space6) {
    Text(title)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(color)

    if let trailing {
        Text(trailing)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(color.opacity(0.62))
            .monospacedDigit()
    }

    Rectangle()
        .fill(DS.commandCenterSeparator)
        .frame(height: 0.5)
        .padding(.leading, DS.space8)

    Spacer(minLength: 0)

    if showReschedule {
        CommandCenterComposerTrigger(composer: composer, alignment: .trailing) { anchor in
            .batchSchedule(
                title: "Reschedule overdue tasks",
                taskUUIDs: viewModel.overdueTasks.map(\.uuid),
                anchor: anchor
            )
        } label: {
            Label("Reschedule", systemImage: "calendar.badge.clock")
                .font(DS.caption)
                .foregroundStyle(DS.red.opacity(0.85))
                .padding(.horizontal, DS.space6)
                .padding(.vertical, DS.space4)
        }
    }
}
.padding(.horizontal, DS.space10)
.padding(.top, DS.space12)
.padding(.bottom, DS.space6)
```

- [ ] **Step 2: Upgrade row background**

Replace `rowBackground` with `CommandCenterRowGlass`:

```swift
private func rowBackground(
    task: TaskViewModel,
    isActiveSession: Bool,
    isMultiSelected: Bool,
    isKeyboardSelected: Bool,
    isHovered: Bool
) -> some View {
    CommandCenterRowGlass(
        isActive: isActiveSession,
        isSelected: isMultiSelected || isKeyboardSelected,
        isHovered: isHovered,
        tint: task.priority.color
    )
}
```

Update the call site:

```swift
.background(
    rowBackground(
        task: task,
        isActiveSession: isActiveSession,
        isMultiSelected: isMultiSelected,
        isKeyboardSelected: isKeyboardSelected,
        isHovered: isHovered
    )
)
```

- [ ] **Step 3: Remove duplicate row border when shared row glass handles it**

Keep `rowBorder` only for multi-selection if the shared row glass does not give enough selection clarity. Otherwise delete the `.overlay(rowBorder(...))` call to avoid double strokes.

- [ ] **Step 4: Refine empty states**

Replace plain `emptyState(message:icon:)` content with `CommandCenterEmptyPane`. Use these copy strings:

```swift
CommandCenterEmptyPane(
    icon: "calendar",
    title: "Today is clear",
    subtitle: "Add a task or drag one into Today when you are ready to schedule it."
)
```

For Anytime:

```swift
CommandCenterEmptyPane(
    icon: "tray.full",
    title: "No anytime tasks",
    subtitle: "Tasks without a date will wait here until you are ready to plan them."
)
```

For Someday:

```swift
CommandCenterEmptyPane(
    icon: "archivebox",
    title: "Someday is empty",
    subtitle: "Park ideas here when they matter, but not today."
)
```

- [ ] **Step 5: Build and run focused tests**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandCenterComposerTests test
```

Expected: build succeeds and `CommandCenterComposerTests` passes. If the local scheme does not expose `CosmoOSTests`, run the build and record the scheme limitation.

- [ ] **Step 6: Commit Today ledger polish**

```bash
git add Canvas/CommandCenter/DashboardTaskList.swift
git commit -m "style: polish command center task ledger"
```

---

### Task 5: Habit Inspector Rail

**Files:**
- Modify: `Canvas/CommandCenter/DashboardHabitPanel.swift`

- [ ] **Step 1: Make habit rows inner glass panes**

In `DashboardHabitOrbitCard`, replace the completed-only background with a hover-capable glass pane. Add local hover state:

```swift
@State private var isHovered = false
```

Then replace the row background with:

```swift
.background {
    if isHovered || isComplete {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isComplete ? habit.accentColor.opacity(0.075) : DS.glassCardFill)
    }
}
.overlay {
    RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(isHovered || isComplete ? habit.accentColor.opacity(0.20) : Color.clear, lineWidth: 0.5)
}
.onHover { hovering in
    withAnimation(reduceMotion ? .easeOut(duration: 0.12) : ProMotionSprings.hover) {
        isHovered = hovering
    }
}
```

- [ ] **Step 2: Keep text hierarchy compact**

Keep the title at 12pt medium. Ensure the seven-day dots remain aligned to the trailing edge by keeping `Spacer(minLength: 0)` inside `titleRow`.

- [ ] **Step 3: Update empty state**

Replace the custom empty state card with:

```swift
CommandCenterEmptyPane(
    icon: "repeat",
    title: "No habits yet",
    subtitle: "Create a habit and completed tasks can begin feeding progress automatically."
)
```

- [ ] **Step 4: Build**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build
```

Expected: build succeeds.

- [ ] **Step 5: Commit habit rail polish**

```bash
git add Canvas/CommandCenter/DashboardHabitPanel.swift
git commit -m "style: polish command center habit rail"
```

---

### Task 6: Upcoming Calendar Polish

**Files:**
- Modify: `Canvas/CommandCenter/UpcomingBoardView.swift`

- [ ] **Step 1: Refine day headers**

In `CalendarDayHeaderCell`, keep the current layout, but change today's day capsule to use `DS.glassInputFillFocused` plus an accent stroke instead of a solid accent fill:

```swift
.foregroundStyle(Calendar.current.isDateInToday(date) ? DS.accent : DS.text)
.background(Calendar.current.isDateInToday(date) ? DS.glassInputFillFocused : Color.clear, in: Capsule())
.overlay {
    if Calendar.current.isDateInToday(date) {
        Capsule().stroke(DS.accent.opacity(0.35), lineWidth: 0.5)
    }
}
```

- [ ] **Step 2: Soften today column and grid lines**

In `hourGrid`, change the today column fill to `DS.glassSectionFill.opacity(0.55)` and keep hour lines at `DS.borderSubtle.opacity(0.72)`. This should make the grid premium without hiding density.

- [ ] **Step 3: Upgrade `CalendarEntryBlock`**

In `CalendarEntryBlock`, replace the current background, stroke, and shadow with:

```swift
.background(blockFill, in: .rect(cornerRadius: 6))
.overlay(
    RoundedRectangle(cornerRadius: 6, style: .continuous)
        .stroke(borderColor, lineWidth: isSelected ? 1 : 0.5)
)
.shadow(
    color: .black.opacity(isSelected ? 0.12 : (isHovered ? 0.07 : 0.035)),
    radius: isSelected ? 6 : (isHovered ? 4 : 1),
    x: 0,
    y: isSelected ? 2 : 1
)
```

Use:

```swift
private var blockFill: Color {
    if entry.source == .draft { return DS.glassInputFillFocused }
    if entry.event?.isExternal == true { return DS.glassCardFill.opacity(0.72) }
    return entry.accent.opacity(DS.palette.isDark ? 0.18 : 0.105)
}
```

- [ ] **Step 4: Polish all-day chips**

In `AllDayLaneCell`, keep the chip structure but use `DS.glassCardFill` behind the accent dot and title, with accent-only text for editable tasks.

- [ ] **Step 5: Polish calendar popover**

In `CalendarEditorPopover`, apply `.cortexInspectorPanel(cornerRadius: 18)` or `.cosmoGlassPanel(sceneMaterial: .neutral, role: .floatingAssistant, cornerRadius: 18)` to the outer popover. Keep the existing save/delete/dismiss behavior unchanged.

- [ ] **Step 6: Build and run calendar layout tests**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandCenterCalendarLayoutTests test
```

Expected: build succeeds and calendar layout tests pass. If the test scheme is unavailable, record the scheme limitation and run the build.

- [ ] **Step 7: Commit upcoming polish**

```bash
git add Canvas/CommandCenter/UpcomingBoardView.swift
git commit -m "style: polish command center upcoming calendar"
```

---

### Task 7: Accessibility, Reduced Settings, And Visual QA

**Files:**
- Modify: `Canvas/CommandCenter/CommandCenterDashboard.swift`
- Modify: `Canvas/CommandCenter/DashboardTaskList.swift`
- Modify: `Canvas/CommandCenter/DashboardHabitPanel.swift`
- Modify: `Canvas/CommandCenter/UpcomingBoardView.swift`

- [ ] **Step 1: Check icon-only buttons**

Confirm every icon-only button in modified files has an `accessibilityLabel`. Add labels where missing:

```swift
.accessibilityLabel("Add habit")
.accessibilityLabel("Manage habits")
.accessibilityLabel("Previous Day")
.accessibilityLabel("Next Day")
```

- [ ] **Step 2: Check reduced motion branches**

Any new hover or completion animation should use:

```swift
reduceMotion ? .easeOut(duration: 0.12) : ProMotionSprings.hover
```

or:

```swift
reduceMotion ? .none : ProMotionSprings.cardEntrance
```

- [ ] **Step 3: Check reduced transparency behavior**

Do not bypass `CosmoGlassPanel` fallbacks with custom blur layers. For fixed inner panes, use `DS.glassCardFill`, `DS.commandChromePanelFill`, and `DS.commandChromeBorder`, not raw `.ultraThinMaterial`.

- [ ] **Step 4: Run final build and focused tests**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandCenterComposerTests test
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandCenterCalendarLayoutTests test
```

Expected: build succeeds and focused tests pass. If the test scheme is unavailable locally, document the exact `xcodebuild` error and keep the successful app build as the required verification.

- [ ] **Step 5: Manual visual QA**

Launch the app and inspect:

- Today view with sidebar open and closed.
- Today with no tasks, a few tasks, and enough tasks to scroll.
- Hovered task, keyboard-selected task, active focus task, overdue task, and completed task.
- Habits rail empty, partially complete, complete, and manual completion pulse.
- Reports tab and task detail tab inside the glass rail.
- Upcoming week at early morning, midday, and crowded task clusters.
- Calendar drag-create, move, resize, and edit popover.
- Reduce Motion enabled.
- Reduce Transparency enabled.

- [ ] **Step 6: Commit accessibility and QA fixes**

```bash
git add Canvas/CommandCenter/CommandCenterDashboard.swift Canvas/CommandCenter/DashboardTaskList.swift Canvas/CommandCenter/DashboardHabitPanel.swift Canvas/CommandCenter/UpcomingBoardView.swift
git commit -m "style: finalize command center accessibility polish"
```

---

## Self-Review

- Spec coverage: The plan covers shared chrome, Today, Upcoming, Habits, right rail, motion, accessibility, reduced transparency, and verification.
- Placeholder scan: No task contains placeholder instructions.
- Type consistency: Shared types are named consistently as `CommandCenterGlassRail`, `CommandCenterMaterialPanel`, `CommandCenterLedgerSectionHeader`, `CommandCenterRowGlass`, and `CommandCenterEmptyPane`.
- Scope control: The plan keeps the current three-zone architecture and avoids replacing the Command Center navigation model.
