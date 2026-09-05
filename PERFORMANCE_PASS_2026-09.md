# Interaction performance pass — September 5, 2026

This pass covers the shared navigation, observation, loading, filtering and action
paths for Spaces, Command Center, Content, Swipe File and Inbox. Existing work in
the checkout was preserved. Visual styling, image resolution, canvas rendering,
document persistence guarantees and undo semantics were not reduced for speed.

## Changes

| Surface | Changes and affected interactions |
| --- | --- |
| Spaces | Keep the Home document model when switching to Library/Canvas/Deep Dive, without retaining a hidden editor. Observe membership and inquiry revisions separately from working notes: autosaving notes no longer refetches every material/session. Coalesce overlapping refreshes. Scope research queries in SQL. Open newly saved notes/ideas before refreshing the rails. Avoid duplicate first-load material-group reads. Isolate library scroll metrics from filtering, sorting and selection rendering. |
| Command Center | Remove the obsolete Plannerum Today mirror and its delayed subscription. Share a fresh task snapshot across Today/completed/Anytime/Someday at startup and across task-refresh waves. Fetch schedule blocks once for the visible date range and decode metadata once per block. Reject stale Today/Upcoming results after rapid date navigation. Cancel optional sound prewarming when leaving the page. Existing task/habit/calendar/report actions retain their persistence and notification paths. |
| Content | Coalesce overlapping pipeline and idea refreshes. Read content, archived content and client profiles in one consistent database snapshot; reuse the client names for the idea rail. Build board and list projections off the main actor and reject superseded results. Open saved ideas/drafts before gallery refresh. Isolate Idea focus-mode scroll updates. Existing scope, stage, schedule, client assignment, archive/restore, bulk, promotion and undo paths use the refreshed models. |
| Swipe File | Defer observation setup until a real load. Share cold loads between prewarm and visits; coalesce reloads. Defer sync-driven loads while hidden, catching up on return. Remove the 250 ms local-change debounce and all unused shelf construction/types. Filter/sort off the main actor with revision checks. Build card adapters once per data load. Wait for the initial projection before declaring loading complete. Keep selection attached to the refreshed item. Move original image file reads off the main actor and reject cancelled page/image loads. |
| Inbox | Keep the view model, capture draft and selection across visits. Remove the 350 ms repository debounce; apply transaction-coalesced updates immediately. Skip hidden queue regrouping and catch up on appearance. Coalesce history loads and read independent history data concurrently. Prevent overlapping single/bulk actions on the same captures. Preserve text typed during a pending capture write. Batch lane attachments in one query and reject stale lane results. Read imported image files off the main actor. Honour cancellation of old undo-toast timers. |

## Work removed, rather than made faster

- Inbox repository delivery: **350 ms of intentional delay removed**.
- Local Swipe File refresh notification: **250 ms of intentional delay removed**.
- Unused Swipe File shelves: **three sorts and their supporting code removed**.
- Seven-day schedule-block loading: **seven database reads become one**.
- Lane media loading: **one attachment query per capture becomes one query per lane**.
- Task startup collections and the Upcoming task refresh domain: **four task-table reads become one**.
- Pipeline client resolution: **up to four separate client reads become one**.
- Task create/complete: **one obsolete Today-table read and a second delayed refresh removed**.

These are code-path reductions, not measured end-to-end speedup percentages.

## Review of the implementation

- A small `CoalescingRefresh` helper is shared by refresh paths that previously
  overlapped. It permits one running pass and one latest pending pass. Visits can
  join a cold load without invalidating it. Cancelling one waiter does not cancel
  work another surface needs. There is no time-based freshness cache.
- Data survives view changes in the existing models. Hidden text editors and an
  unbounded collection of retained space views were deliberately avoided.
- Writes still report failure and retain their undo/persistence contracts. The
  editor opens after its new atom commits, before unrelated gallery work finishes.
- Original study images retain their original resolution. The image change moves
  file loading off the main actor; it does not claim to eliminate every draw-time
  image decode or impose a smaller thumbnail on a study page.
- No app-wide observation framework, database schema migration, new automation,
  animation removal, or visual redesign was introduced by this pass.
- Runtime inspection found the retained, invisible canvas in other destinations'
  accessibility trees. It is now accessibility-hidden whenever it is inactive or
  covered by focus mode, preserving its state without exposing background content.

## Verification

- Baseline and updated Debug builds succeeded with `xcodebuild`.
- **153 targeted regression tests passed with zero failures.** A final Debug build
  also passed after the accessibility-only visibility fix.
- Targeted regression suites cover refresh joining/bursts/cancellation, immediate
  Inbox updates, dependency invalidation, scoped inquiry reads, ordered media
  batches, combined pipeline reads, recurring schedule projection, filtering,
  navigation, viewport transforms, retained Content lifecycle, thumbnail prewarm,
  and Content/Idea persistence.
- Test databases are process-specific scratch databases through the checkout's
  test configuration; batch media/dependency fixtures do not use real files.
- `git diff --check` passes.
- New Instruments intervals use the existing `com.cosmo.os` / `AppPerformance`
  signposter: `space-home-refresh`, `content-pipeline-refresh`,
  `content-ideas-refresh`, and `swipe-library-refresh`.

## Runtime limits

Three older CosmoOS processes made the initial UI target ambiguous. A temporary
copy of the updated build with a unique bundle identity resolved that ambiguity.
Live checks confirmed Inbox draft retention across Command round trips, clearing
that unsent draft, loading a 17-capture lane, Content Ideas/Pipeline/Calendar,
Pipeline search and reset, calendar month navigation, Swipe File search and reset,
Command Today/Upcoming, and Upcoming week navigation. No test captures were saved.

Native automation intermittently reported missing frames/windows or timed out.
A three-second process sample after a timeout found the main thread waiting in
the event loop in 1,865 of 1,954 samples (about 95%); this does not establish click
latency or rule out transient stalls. Individual Space selection could not be
reliably driven through that native automation session; its model behavior is
covered by regression tests. The final accessibility fix was build-verified,
not reinstalled into the temporary live-test copy.

No frame-rate, p95 switch latency, pixel-perfect before/after comparison, or
exhaustive A–Z runtime certification is claimed. Network-bound AI, OCR, sync,
remote media and publishing operations are outside a claim of instant local
execution.

For a repeatable latency benchmark, use one current app process and record repeated
round trips through all five destinations with Instruments. Include rapid date
and scope changes, long-list scrolling/search, editor open/close, task completion,
bulk triage, media paging and undo while sync arrives. The new intervals distinguish
refresh work from navigation and layout. Verify Reduce Motion and narrow-window
layout in that same isolated process before calling the visual runtime audit final.
