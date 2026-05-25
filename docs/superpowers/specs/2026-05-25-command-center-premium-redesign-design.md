# Command Center Premium Redesign Design

## Context

The current Command Center already has the right product structure: an internal navigation sidebar, a central work surface for Today or Upcoming, and a right-side detail or habits rail. The issue is not the information architecture. The issue is that the Today list, Upcoming calendar, and habit rail feel flatter and more utilitarian than the rest of CosmoOS, especially compared with the glass sidebar, Thinkspace canvas, and Command-K overlay.

The screenshots establish the target language:

- The global sidebar uses a premium frosted panel with soft edge separation, restrained selection fills, and calm iconography.
- Thinkspace uses dark canvas space, glass chrome, hairline geometry, and material depth.
- Command-K uses a premium overlay: frosted backdrop, inner glass panes, compact rows, and a strong master-detail preview.
- The Make task view has useful density and clarity, but it is too plain to be the final CosmoOS direction.

## Decision

Use the "Frosted Ledger" direction.

Keep the current three-zone Command Center architecture, but make the surfaces, rows, tabs, calendar blocks, and habit rail feel like part of the same Apple-like material system used by the rest of the app. Do not convert the task list into a card wall. Keep it simple, dense, and calm, then use material, hairlines, precise spacing, hover states, and spring motion to create the premium feeling.

## Radical Structure Option Considered

A more radical redesign would replace the current shell with a dedicated Apple Reminders plus Calendar workspace:

- A full `NavigationSplitView` command workspace with native macOS source-list behavior.
- A persistent top toolbar for date, search, add, focus, and view switching.
- A collapsible inspector instead of the current fixed right column.
- A Today view that can switch between task list, schedule timeline, and habit focus.
- An Upcoming view that becomes the primary planning canvas, with tasks and habits unified as time blocks.

That would be a bigger product and architecture change. It is not required for the premium goal because the current layout already gives the user the right spatial model: sidebar, work surface, inspector. The better move is to preserve that model and upgrade the execution quality. This keeps scope focused while still allowing a high-end result.

## The Moment

When the user opens Command Center, they should feel that the day has been made calm, structured, and immediately actionable. The view should feel like a premium Apple productivity surface, not a plain task database.

## Visual Layout

```text
+------------------------------------------------------------------------------+
| Cosmo glass sidebar        Today work surface                    Glass rail    |
| already premium            calm, open, ledger-like              habits/detail  |
|                                                                              |
| +----------------+      Today                              Mon, May 25        |
| | Smart Lists    |      6 scheduled tasks · 0m tracked     < Today >          |
| | Today          |      ------------------------------------------------      |
| | Upcoming       |                                                          |
| | Anytime        |      + Time Tracking ------ 0m today ----- Start focus +  |
| | Someday        |      +-------------------------------------------------+  |
| +----------------+                                                          |
|                        Overdue 2                         Reschedule          |
|                        o Write personal reel/thread daily                    |
|                          11:00 · Repeats · Personal content                  |
|                                                                              |
|                        Scheduled 6                                           |
|                        o Create reel/thread for Ben                          |
|                          09:00 · Repeats · Client posts                      |
|                        o Find 1 new viral ad to test per client              |
|                                                                              |
|                        + Add task...                                         |
|                                                                              |
|                        + Objectives -------------------------- Q2 -------+    |
|                        | Complete 45 posts                    0% -------|    |
|                        +------------------------------------------------+    |
|                                                                              |
|                                                            Habits             |
|                                                            --------           |
|                                                            O Content Research |
|                                                            O Personal content |
|                                                            O Client posts     |
+------------------------------------------------------------------------------+
```

## Today View

The Today view remains a ledger, not a card layout.

- The masthead keeps the serif display moment because it matches the current Command Center identity.
- The time tracker becomes a compact material command strip.
- Section headers become crisp ledger headers with a subtle rule and compact count.
- Task rows become quiet glass rows on hover, keyboard selection, and active focus. Resting rows remain nearly flat.
- The objectives bar remains pinned and compact, but uses the same panel chrome as the time tracker.

## Upcoming View

The Upcoming view should feel closer to Apple Calendar, but with CosmoOS material polish.

- The week grid stays the primary structure.
- The today column gets a faint material wash.
- Calendar blocks keep color semantics, but gain a refined surface: translucent accent fill, fine accent stroke, and compact text hierarchy.
- External calendar events stay slightly more muted than editable tasks.
- The calendar editor popover uses the shared glass/floating panel language.

## Habit Rail

The habit rail should become an inspector-like glass surface.

- The rail itself gets a glass panel treatment aligned with Command-K and the global sidebar.
- Each habit row becomes an inner glass pane only when selected, hovered, completed, or semantically emphasized.
- Habit rings remain useful, but the surrounding row gets better spacing, text hierarchy, and seven-day bead alignment.
- Completed habits use color as punctuation, not as a full-width colored banner.

## Why This Works

- It preserves the core simplicity the user wants.
- It uses the existing CosmoOS glass system rather than adding a separate visual language.
- It makes the experience premium through restraint: material depth, hairline borders, hover response, typography, and motion.
- It avoids the common failure mode where productivity apps become decorative and slow to scan.
- It keeps the implementation mostly in the existing `Canvas/CommandCenter` module.

## Motion

- View transitions use `ProMotionSprings.cardEntrance`: opacity plus a small scale from 0.96 to 1.0.
- Hover states use `ProMotionSprings.hover`: 1pt lift, brighter glass fill, and a sharper hairline.
- Keyboard row selection uses `ProMotionSprings.snappy`: quick but not jumpy.
- Habit completion uses ring progress plus a small check badge pulse, capped around 400ms.
- Calendar drag and resize keep the current snap behavior, but selected entries brighten and lift slightly.
- Reduced Motion falls back to short opacity changes without scale or bounce.

## Edge Cases

- Empty Today: show a useful empty state with icon, title, short guidance, and inline add affordance.
- Empty Habits: keep a compact glass empty pane with the add habit action available.
- Empty Upcoming week: keep the calendar grid visible and make creation by drag obvious through hover feedback.
- Reduced Transparency: glass panels use solid fallback colors from `CosmoGlassPanel`.
- Small widths: right rail can remain fixed initially, but central content must keep task text from overlapping due chips and controls.
- Large task counts: lists remain `ScrollView` plus lazy-capable structure where needed, with no per-row heavy effects at rest.

## Architecture

The implementation should keep the current root layout in `CommandCenterDashboard`. The redesign is a presentation pass, supported by a small set of shared Command Center chrome components.

Files to create:

- `Canvas/CommandCenter/CommandCenterSurfaceChrome.swift`

Files to modify:

- `Canvas/CommandCenter/CommandCenterDashboard.swift`
- `Canvas/CommandCenter/CommandCenterMasthead.swift`
- `Canvas/CommandCenter/DashboardTimeTracker.swift`
- `Canvas/CommandCenter/DashboardTaskList.swift`
- `Canvas/CommandCenter/DashboardHabitPanel.swift`
- `Canvas/CommandCenter/DashboardObjectivesBar.swift`
- `Canvas/CommandCenter/UpcomingBoardView.swift`
- `CosmoOS.xcodeproj/project.pbxproj` if the new Swift file is not automatically included by the project setup.

Testing and verification:

- Build the app target.
- Run focused Command Center tests.
- Manually inspect Today, Upcoming, Habits, Reports, task detail, hover, keyboard selection, drag/drop, reduced motion, and reduced transparency.

## Self-Review

- Placeholder scan: no placeholders remain.
- Internal consistency: the design keeps the existing three-zone architecture and applies one material direction across Today, Upcoming, and Habits.
- Scope check: this is one implementation plan because it is a cohesive visual-system pass inside `Canvas/CommandCenter`.
- Ambiguity check: the radical structure option is explicitly rejected for this pass; the plan should polish the existing architecture rather than replace it.
