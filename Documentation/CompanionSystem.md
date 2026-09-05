# Companion system

The companion is the personal face of the Cosmo assistant, with its own earned journey alongside tasks and focus time. Every character uses the same assistant capabilities. The same cast, artwork, journey model and ritual UI run on iPhone and Mac.

The assistant integration and current validation are recorded in [CompanionAssistantImplementation-2026-09-05.md](Design/CompanionAssistantImplementation-2026-09-05.md).

## What changed

- Replaced all twelve badge illustrations with a new vector cast. Each character has a clear silhouette, a face, a fixed palette, a greeting, and its own celebration copy. The artwork is resolution independent; no remote assets or image loading are required.
- Added four illustrated forms: Beginning, Budding (3 active days), Flourishing (10) and Wondrous (30). Growth changes leaves, blossoms, wings, shell gardens and other details in the drawings. The cast screen previews every form without awarding progress.
- Replaced the picker with Together, The cast, Rituals and Assistant. Together includes a large interactive portrait, growth, a guarded 25-minute focus action and an inspectable 14-day activity history. Assistant includes presentation preferences, a local practice conversation and the ritual tutorial.
- The iPhone navigation portrait opens the assistant sheet; its header opens the companion world. Mac has an optional corner entrance, compact chat and the existing assistant pane, with world access in the header, sidebar footer and Settings.
- Added an interactive tutorial: greet the companion, choose a real event, preview its response, then enable the ritual. Previewing has no task, timer or growth side effects.
- Added two editable rituals: task completed and focus session saved. Responses celebrate, invite a breathing break, or prompt a next step. They start disabled. An enabled ritual produces an in-app companion message after a successful local save.

## Activity and growth

The journey reads existing `task` and `deep_work_block` atoms. Actual seconds are preferred; legacy actual minutes remain supported. Planned durations, future records, negative durations and sub-three-second touches do not count. Recurring task history uses distinct task/day occurrences and avoids counting the template twice.

One day with a completed task or saved focus time is one active day. The whole cast shares earned growth, so switching companions does not reset the journey. This is cumulative growth, independent of the existing consecutive-day focus streak and vitality ring. An earned-day high-water mark preserves growth through rest days and history corrections. The visible activity history still reflects corrections.

## Persistence and sync

`cosmo.companion` continues to store `{ id, updatedAt }` for compatibility with older clients.

`cosmo.companion.journey` stores earned days, tutorial completion, and independently timestamped ritual settings. Merging takes the greatest earned-day count, preserves completed onboarding, and chooses the newest edit per ritual. Duplicate preference rows from offline first launches are folded together. Unknown top-level JSON keys survive writes.

Changes are cached immediately in UserDefaults, including a pending-write flag. Writes are serialized; pending changes retry when the companion is hydrated. A sync error is visible and offers retry. Both apps must include this update for journey and ritual UI parity.

## Event boundaries

- Mac: Command Center and timed-goal task completion, plus successfully saved deep-work blocks.
- iPhone: Today and task-detail completion, plus successfully recorded in-app focus sessions.
- Synced/imported history updates growth without replaying reactions.
- Timer ticks and paused time do not independently award growth.
- Ritual responses are local in-app interactions. They do not schedule background reminders, send messages, execute arbitrary code, or replace the Mac’s broader workflow automation engine.
- Focus actions check for an existing session before starting, including paused sessions.

## Verification

`Tests/CosmoOSTests/CompanionJourneyTests.swift` exercises actual-time accounting, record deduplication, recurring completions, reopened tasks, all growth thresholds, independent ritual merges, deterministic equal-timestamp merges and daylight-saving day boundaries.

The seven journey checks now also pass against the built Mac module, alongside ten companion-continuity checks and eighteen existing pane, streaming, scroll-follow and promotion regressions. Mac and iPhone Debug builds pass in isolated build directories. Native simulator walkthroughs verified character selection, future-form previews, tutorial gating and ritual persistence, starting focus, blocking a second session while paused, and ending a session back to idle with the configured companion response. The iPhone response sits above the global Create control. See the implementation report for assistant verification and remaining release checks.

Visual entry points on iPhone: `-cosmo-demo-data -cosmo-demo-tab today -cosmo-demo-companions`; the existing `-cosmo-demo-companion-gallery` now shows the new cast across all four forms. Demo history supplies real focus records for the journey. Review the portrait, cast selection, future-form preview, tutorial, enabled/disabled rituals, active focus guard, large type and Reduce Motion.
