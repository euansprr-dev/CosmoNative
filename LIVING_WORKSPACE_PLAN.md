# The Living Workspace Plan

Nine features that turn CosmoOS from "an app with views" into one continuous spatial
instrument. Every UI in this plan is specced to the peakui bar: native Liquid Glass via
`cosmoGlassPanel`, DS tokens only, named `ProMotionSprings`, macOS manners (hover, tooltips,
keyboard, Esc), and the audit checklist run before any phase ships. No rushed chrome.

**Build order** (dependency-driven, each phase shippable alone):

| Phase | Features | Why this order |
|---|---|---|
| 0 | Navigation Trail (back/forward) + Canvas Bookmarks | Small, foundational — everything later pushes onto the trail |
| 1 | Focus + Spine pane deck, Peek before pane | Biggest daily-feel win; they share the PaneManager rework |
| 2 | Workbenches | Needs pane serialization (Phase 1) + trail (Phase 0) |
| 3 | The Constellation | Needs the thumbnail pipeline (built here, reused later) |
| 4 | Portals | Reuses the Constellation's thumbnail renderer |
| 5 | Spokes Compiler | Independent content-side track — can run parallel to 3/4 |
| 6 | Living Workflows | The moat. Rules engine exists; this is its spatial face |

**Shared infrastructure built once, used everywhere:**

- `WorkspaceSnapshot` — a serializable capture of {main destination, thinkspace camera,
  pane set, focused pane}. Used by: Workbenches (save/restore), Navigation Trail (moments),
  Constellation (return position).
- `ThinkspaceThumbnailService` — renders cached miniatures of canvases (blocks as tinted
  rounded rects at true positions, cluster zones as washes). Built on the existing minimap
  renderer + `CanvasRenderSnapshot` (Canvas/CanvasRenderSnapshot.swift) and
  `ThumbnailCacheService`. Used by: Constellation cards, Portal blocks, Workbench preview
  miniatures, bookmark dots on the minimap.
- New files must be registered in `project.pbxproj` manually (known requirement).

---

## Phase 0a — Universal Back/Forward (the Navigation Trail)

### Vision
CosmoOS finally gets what browsers solved 30 years ago: Cmd+[ takes you back through
*everywhere you've been* — thinkspaces (with camera position), focus modes, inbox, command
center, library — as one time-ordered trail. Navigation stops being one-way doors.

### Architecture
- **New:** `Navigation/NavigationTrail.swift` — `@Observable final class NavigationTrail`.
  - `struct NavigationMoment: Equatable { let destination: TrailDestination; let timestamp: Date }`
  - `enum TrailDestination { case sidebar(SidebarDestination); case thinkspace(id: String, camera: CameraState?); case focusMode(EntitySelection); case workbench(uuid: String) }`
  - `back()`, `forward()`, `push(_:)`, `canGoBack/Forward`, `recentTrail(limit:)`.
  - Dedupe consecutive identical moments; cap at 100; forward stack clears on new push.
- **Hook points:** MainView already has a single destination-change funnel
  (Navigation/MainView.swift:675–704) — push there. Focus-mode entry/exit pushes via the
  existing FocusModePresentation transitions (MainView.swift:29–51). Thinkspace switches
  capture the *outgoing* camera (`ThinkspaceMetadata.zoomLevel/panOffset` is already
  persisted) so "back" restores exactly where you were looking.
- Pane focus changes are **not** trail moments in v1 (too noisy). Peek is never a moment.

### UI spec
- **Chevrons:** two ghost buttons in the top-left of the masthead area, `chevron.left` /
  `chevron.right`, 28pt circular hit area inside a shared capsule
  `.glassEffect(.regular.interactive(), in: .capsule)`. Disabled state = `DS.textMuted`
  at 40%; enabled = `DS.textSecondary`, hover brightens to `DS.text` + 1.01 lift
  (`.hover`). Tooltips: `.help("Back (⌘[)")`.
- **Trail popover:** click-and-hold (or right-click) the back chevron → popover listing
  the last ~10 moments (Safari idiom). Rows: type glyph in entity tint, title in
  `DS.callout`, relative time in `DS.caption`/`DS.textMuted`. Mount with `.menuAppear`,
  rows cascade capped at 8. Esc closes.
- **Keyboard:** Cmd+[ / Cmd+] (verify no collision with editor indent — scope to when no
  text view has focus). Also support mouse buttons 4/5.
- **Motion:** trail jumps reuse the *destination's own* transition (canvas camera flight,
  focus-mode morph). The trail never invents a new transition — it replays existing ones.

### Acceptance
- Back from a focus mode returns to the exact canvas camera you left.
- Ten rapid navigations then ten Cmd+[ lands you precisely at the start. No dead moments
  (deleted atoms/thinkspaces are skipped with a quiet toast, removed from the trail).

---

## Phase 0b — Canvas Bookmarks (Places)

### Vision
Cmd+D anywhere on a canvas saves *this view* — zoom + position — as a named Place.
Jump between Places instantly. Large thinkspaces stop being something you scroll around
hunting; they become a building with rooms.

### Architecture
- Extend `ThinkspaceMetadata` (Canvas/ThinkspaceManager.swift:12) with
  `var places: [CanvasPlace] = []` —
  `struct CanvasPlace: Codable { uuid, name, zoom: Double, offsetX/Y: Double, createdAt }`.
  It's already Codable + persisted; this is additive and migration-free.
- **New:** `Canvas/CanvasPlacesController.swift` (capture/jump/rename/delete + flight
  animation) and a small save popover view.

### UI spec
- **Capture (Cmd+D):** a compact glass popover blooms from the cursor position
  (`.bouncy`, `cosmoGlassPanel` 18pt radius): a `dsGlassInput` name field pre-filled with
  the nearest cluster's name (or "Place N"), Return saves, Esc cancels. One field, zero
  ceremony — the Things 3 quick-entry feel.
- **Jumping:**
  - Cmd+K gains a "Places" section when a thinkspace is frontmost — rows show name +
    a 64×40 thumbnail crop from `ThinkspaceThumbnailService`.
  - `Cmd+⌥+1…9` jumps by recency order.
  - **Minimap integration:** Places render as 5pt accent diamonds on the existing
    `CanvasMinimapOverlay`; click = fly. Hover shows name in a `DS.caption` tag.
- **The flight (signature motion):** never hard-cut. Animate `CanvasViewportTransform`
  along a zoom arc — ease out ~10% zoom, pan, settle in — driven by `.modal` spring,
  ~450ms total. The arc is what makes teleporting feel *spatial* instead of disorienting.
  Reduce Motion = instant jump. Flight pushes a trail moment.

### Acceptance
- Save → jump → Cmd+[ returns to pre-jump camera. Places survive relaunch. Minimap
  diamonds align with true canvas positions at every zoom level.

---

## Phase 1 — The Pane Revolution

Two features, one rework. The root problem is `PaneManager.redistributeSizes()`
(Navigation/PaneManager.swift:430): every pane gets 1/n of a half-width column, so three
panes are three unreadable slivers. We replace *even distribution* with *focus + spines*,
and stop most panes from ever being born via Peek.

### 1A. Focus + Spine Deck

#### Vision
The pane column holds one **focused** pane at full readable width. Every other open pane
collapses into a **spine** — a 44pt vertical bar with the title running vertically,
its entity tint as a hairline, and a live activity dot. Click a spine and it becomes the
focused pane with a single spring slide. Panes stop competing for space; they queue for
attention. (Arc's sidebar insight, turned 90° and applied to panes.)

#### Architecture — PaneManager v2
- Add `@Published var focusedPaneId: String?` and
  `@Published var pinnedPaneId: String?` (one pane may be *pinned* to stay visible —
  focused + pinned split the column 60/40; pinning a second replaces the first).
- `paneSizes` and `updateDivider` are deleted. Layout becomes deterministic:
  `columnWidth = spines(44pt × n) + focused (+ pinned)`.
- `maxPanes` rises 4 → 6 (spines are cheap).
- `openPane` keeps duplicate prevention; new panes open focused, previous focus collapses
  to a spine.
- **Rewrite** `PaneColumnView` in Navigation/SplitPaneContainer.swift from a `VStack` of
  evenly-sized panes to an `HStack`: `[spine][spine][focused pane][spine]` — spines keep
  their *opening order* position so they don't shuffle when focus moves.
- View identity: focused content must keep state when collapsing to spine and back —
  render all pane bodies once and animate width, never `if/else` structure on focus state
  (the structural-identity law). Collapsed bodies get `.opacity(0).allowsHitTesting(false)`
  behind the spine chrome with `drawingGroup` suspended.

#### UI spec — the spine
- 44pt wide, full column height, `DS.glassCardFill` with `DS.glassBorder` hairline;
  the *leading* edge carries a 2pt entity-tint rule (research green, idea indigo…).
- Top: 18pt type glyph in entity tint. Below it, the title rendered vertically
  (`.rotationEffect(.degrees(90))`, fixed-width frame) in `DS.subheadline` /
  `DS.textSecondary`, truncated middle. Bottom: activity dot (6pt, `DS.accent`, appears
  with `.snappy` when the pane has unseen changes — e.g. assistant finished streaming).
- Hover: fill brightens to `DS.glassSectionFill`, 1.01 lift, close glyph fades in at top
  (`.hover`). **Hover dwell 350ms → Peek-preview**: the spine's pane slides over the
  focused pane as a 320pt overlay (`.move(edge:)` + opacity on `.focusTransition`) —
  read without committing; click anywhere inside to commit focus. Mouse-out retracts.
- Focus swap choreography: spine expands 44 → full width with `.focusTransition` while
  the outgoing pane compresses to its spine slot; the two widths animate as one
  continuous gesture. Content cross-fades 0.10s. The chrome morphs via shared
  `glassEffectID` per pane inside one `GlassEffectContainer` so the glass *flows* —
  this is the premium move; do not replace-and-fade.
- Pin affordance: small `pin` glyph in the focused pane's header, `.help("Pin beside
  focus (⌘⇧P)")`. Pinned pane shows a `DS.accentSoft` header wash.

#### Keyboard & manners
- `Cmd+1…6` focus pane by position; `Cmd+⇧+]`/`[` cycle focus; `Cmd+⇧+P` pin; Esc closes
  the focused pane (falls back to most recent spine — `closeLastPane` semantics retire).
- Every spine: `.help(title)`, `accessibilityLabel("\(title) pane, collapsed")`,
  `.isButton`, 44pt hit target by construction.

#### Acceptance
- Six panes open: focused pane is never narrower than ~420pt at default window size.
- Swap focus 20× rapidly: no dropped frames at 120Hz (test with the performance overlay),
  no view-state loss (editor cursor position survives collapse/expand).
- Reduce Motion: swaps become opacity fades, spines still functional.

### 1B. Peek Before Pane

#### Vision
The macOS Quick Look idiom, app-wide: **select anything, press Space** (or click a
mention pill) and it opens as a floating glass *peek* — read it, then either dismiss
(nothing polluted) or promote it to a real pane / focus mode. Most opens are glances;
Peek makes glancing free. Pane clutter dies at the source.

#### Architecture
- **New:** `Navigation/PeekController.swift` (`@Observable`; `peek(_ target: PeekTarget,
  from anchor: CGRect?)`, internal mini-trail for link-hops inside a peek) and
  `Navigation/PeekOverlayView.swift`, mounted once in MainView's top ZStack
  (above SplitPaneContainer, below Cmd+K).
- `PeekTarget` = `EntitySelection | URL | InboxItem`. Reuses existing pane body views
  (`PaneContentView` content builders) in read-mostly mode — no new renderers.
- Entry points wired in v1: mention pills (CosmoMentionPillKit), Cmd+K results (Space on
  highlighted row — Raycast idiom), canvas blocks (Space with selection), inbox rows,
  related-atom chips in inspectors. All currently call `openPane`/focus directly; they
  route through `PeekController` instead.

#### UI spec
- **Panel:** `cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 24)`, sized 64% ×
  78% of the window, centered. Behind it a 6% black scrim (just enough to focus the eye —
  the glass itself does the separation; don't go greyer). Click-out or Esc dismisses.
- **Entrance:** grows *from its trigger* — scale 0.92 → 1.0 + opacity, anchored at the
  source pill/row/block rect, on `.bouncy`. The element lifts out of the page; a centered
  generic fade is exactly the "sheet" feel we're avoiding. Dismiss reverses to anchor.
- **Header (inner chrome on glass — flat fills only):** type glyph + title
  (`DS.headline`), then a right-aligned action cluster:
  - `Open` (primary, `DS.accent` capsule) — replaces peek with the full focus mode.
  - `Open in Pane` (`Cmd+Return`) — **the panel flies to the pane column**: animated
    frame morph from peek rect to the new focused-pane rect via shared `glassEffectID`,
    `.modal` spring. This one transition teaches the whole pane system.
  - Back chevron appears when you've followed links inside the peek (internal trail).
- **Footer:** quick captures only — "Add to canvas", "Link to current atom" as ghost
  capsule buttons. Editing inside peek is out of scope v1 (read + light actions).
- Space-to-peek follows selection focus; pressing Space again closes (Quick Look parity).

#### Acceptance
- A link in a note → Space-peek → Esc leaves zero panes opened, zero trail moments.
- Peek → "Open in Pane" lands focused with the morph; Cmd+[ afterwards returns to the
  pre-peek context.

---

## Phase 2 — Workbenches

### Vision
A Workbench is a named, restorable working context: main view + thinkspace camera + the
whole pane deck + focus. "Newsletter Tuesday" = content draft focused, swipe gallery
pinned, research thinkspace spine, camera on the outline cluster. One keystroke rebuilds
the room exactly as you left it. (Arc Spaces, applied to knowledge work.)

### Architecture
- **New table:** `WorkbenchRecord` (GRDB): `uuid, name, glyph (SF symbol), tintHex,
  snapshot (JSON WorkspaceSnapshot), sortOrder, lastUsedAt, useCount`.
- **New:** `Navigation/WorkbenchStore.swift` (`@Observable`; CRUD + apply/restore) and
  `Navigation/WorkbenchComposerView.swift` (creation/edit sheet).
- `WorkspaceSnapshot` serializes: sidebar destination, thinkspace id + camera,
  `[PaneContent]` (entity panes by atom UUID — resolve and *skip* deleted atoms on
  restore with a quiet note), focused/pinned pane ids.
- Restoring sets state through existing managers (`ThinkspaceManager`, `PaneManager`,
  AppState) — no parallel state paths. Applying a bench pushes one trail moment.

### UI spec — invocation
- **Cmd+K, first-class:** a "Workbenches" section at top when query is empty; type
  `bench` to filter. Rows: glyph in tint, name `DS.callout`, a micro-diagram on the right
  (see below), `Ctrl+1…9` badges. Return applies.
- **Sidebar:** a quiet bench strip at the very top of the global sidebar — glyph-only
  20pt buttons in a capsule group, active bench gets `DS.accentSoft` fill. Hover = name
  tooltip. (Glyph-only is acceptable here because every bench also lives in Cmd+K with
  full names.)

### UI spec — the Composer (the "premium creation UI somewhere smart")
Three entry points, one surface:
1. **"Save layout…"** in the pane column header overflow menu — the moment you have a
   layout you like.
2. Cmd+K verb: "Save current layout as Workbench".
3. **Proactive-but-suggestive:** when the app notices you've manually assembled the same
   combination (same main destination + ≥2 same panes) on 3 separate days, a dismissible
   suggestion card appears once in the masthead: "You build this layout often — save it
   as a Workbench?" Never a popup mid-work; it waits in the masthead.

The Composer itself **morphs out of Cmd+K's glass** (same `GlassEffectContainer` /
`glassEffectID` trick as the existing cortex-pill→panel morph — the panel grows into the
composer, `.modal` spring):
- **Hero: a live miniature of the layout** — an auto-generated diagram of the current
  workspace: main view as a large rounded rect containing the thinkspace thumbnail
  (`ThinkspaceThumbnailService`), pane deck as labeled slivers, focused pane highlighted
  in the bench tint. This *is* the premium move — you see what you're saving. Rendered
  from `WorkspaceSnapshot`, it's the same component reused at micro scale in Cmd+K rows.
- Below: name field (`dsGlassInput`, auto-focused), glyph picker (curated 24-symbol grid,
  capsule cells, `.snappy` selection with travelling highlight via
  `matchedGeometryEffect`), tint row (the 8 thinkspace accents).
- Footer: "Save Workbench" accent capsule; `Return` saves; Esc collapses back into Cmd+K.

### Restore choreography (≤ 600ms, every time)
1. Main content cross-fades through the existing destination transition (`.focusTransition`).
2. Camera flies to the saved position (the Phase 0b flight).
3. Panes materialize right-to-left as spines with `cascade(index:)` capped at 4; the
   focused pane expands last.
Reduce Motion: single cross-fade, instant camera.

### Acceptance
- Bench → quit → relaunch → Ctrl+1 rebuilds the identical workspace (camera within 1pt).
- Deleted atom in a saved bench: restore proceeds, sliver skipped, one quiet toast.

---

## Phase 3 — The Constellation

### Vision
Pinch out (or one key) from any canvas and the canvas itself shrinks into a card among
all your thinkspaces — live miniatures arranged by project, activity glowing softly —
then dive into another one. Mission Control for your knowledge. Navigation becomes one
continuous space, and the app's "one loop" thesis becomes something you *feel*.
The bar: indistinguishable in quality from macOS Exposé (the reference screenshot).

### Architecture
- **New:** `Canvas/ConstellationView.swift`, `Canvas/ConstellationViewModel.swift`,
  `Canvas/ThinkspaceThumbnailService.swift` (the shared renderer — built in this phase).
- Thumbnails: rendered off-main from `CanvasRenderSnapshot` data (blocks → entity-tinted
  rounded rects at true positions, cluster zones → 8% tint washes, connection lines as
  hairlines) into bitmaps cached by `ThumbnailCacheService` with
  `stableKey = thinkspaceId + lastSavedRevision`. Re-rendered on the canvas save debounce
  (`DebouncedPositionSaver` already batches writes — hook its flush). Constellation
  renders **cached bitmaps only** — never live canvases. 60 thinkspaces must scroll at
  120Hz.
- Layout data comes from `ThinkspaceManager.thinkspaces` (+ `projectUuid` grouping,
  `hasChildren` for nesting badges).

### The transition (the whole feature lives or dies here)
**Continuous zoom, two stages, one gesture:**
- Stage 1 (existing): pinch zooms the canvas via `CanvasViewportTransform`.
- Stage 2: when zoom crosses ~0.18× *and the pinch continues*, the live canvas
  cross-dissolves into its own thumbnail card at matching scale/position
  (`CanvasViewportTransform.canvasToScreenAffineTransform()` gives exact alignment math —
  the card must land pixel-true so the dissolve is invisible), and sibling cards fade in
  around it with `cascade` (cap 8). Releasing the pinch past the threshold commits;
  reversing rubber-bands back into the canvas (`.gentle`).
- Diving in reverses it: click a card → it scales up to fill the window while its
  thumbnail cross-dissolves into the live canvas at the saved camera (`.modal`,
  ~500ms). The trail gets one moment.
- Also reachable without trackpad: a masthead button (`square.grid.3x3` glyph) and a
  keyboard chord (proposal: `Cmd+⇧+Space`; verify against the global shortcut map before
  committing). Esc returns to the originating canvas.

### UI spec — the field
- Background: `DS.canvas` with `.filmGrain()` (this is a hero *content* surface, the one
  place grain belongs). No glass backdrop wall.
- **Cards:** thumbnail bitmap clipped to 14pt continuous rect, hairline `DS.glassBorder`,
  resting shadow → hover lift (`dsRestingShadow → dsHoverShadow`, 1.01, `.hover`).
  Beneath: name in `DS.headline`, `blockCount` + relative `lastOpened` in `DS.caption` /
  `DS.textMuted` with `.monospacedDigit()`. Thinkspace accent as a 3pt top rule on the
  card. Root/project thinkspaces render 1.35× larger (hierarchy pass: the field still
  needs heroes).
- **Activity glow:** thinkspaces edited in the last 24h get a 12pt soft outer halo in
  their accent at 18% (static — no idle pulsing; the promotion perf pass killed idle
  animation for good reason).
- **Grouping:** project lanes with `DS.title2` headers and the project tint as a leading
  rule — Mission Control groups by app; we group by project. Unassigned thinkspaces
  gather in a trailing "Open ground" lane. Lanes scroll vertically; masonry within.
- **Search:** a floating `dsGlassInput` top-center (the only chrome on screen); typing
  filters live — non-matching cards sink to 30% opacity and 0.97 scale (`.gentle`), never
  unmount (no layout jumps). Return dives into the top match.
- **Drag-to-file:** dragging a canvas block (carried from Stage 1 — you can start the
  pinch *while* dragging a block) and dropping it on a card calls
  `SpatialEngine.moveBlockToThinkspace` (Canvas/SpatialEngine.swift:377 — already exists).
  Drop target shows an `DS.accentSoft` ring. This makes the Constellation a *workspace*,
  not just a switcher.

### Acceptance
- Pinch out/in 10× rapidly: no hitch, no thumbnail pop (dissolve alignment exact).
- 60 thinkspaces: scroll and search at 120Hz; memory stable (bitmaps evict via cache).
- Exposé side-by-side test: motion quality indistinguishable.

---

## Phase 4 — Portals

### Vision
A portal is a block on canvas A that is a *live window into* a region of canvas B — a
cluster, or any framed region. Glance at it to see the real state of that other space;
double-click to travel; drop a block into it to send it there. Cross-thinkspace work
stops meaning duplication.

### Architecture
- New block entity type `portal` carried through `CanvasBlock` / `CanvasBlockRecord`
  (metadata: `targetThinkspaceId`, `targetClusterId?` or `targetRect?`, `displayName`).
- Renders the target region via `ThinkspaceThumbnailService` (region-cropped) — cached
  bitmap, refreshed when the *target* thinkspace flushes a save. Never a live canvas.
- Travel = trail push + the Phase 0b camera flight into the target region.
- Drop-to-send = existing `moveBlockToThinkspace` with position mapped into the target
  region's coordinate space.

### UI spec
Deliberately *content*, not chrome — a window, not a wormhole:
- Frame: `DS.surfaceElevated` fill, 14pt continuous radius, hairline in the **target
  thinkspace's accent**, and a 1pt inner shadow at 6% along the top edge — the one place
  we use an inset cue, because a portal is conceptually *recessed* (a window into
  elsewhere). No glow, no vortex, no animated shimmer.
- Header strip (24pt): target accent dot, target name in `DS.subheadline`, region label
  (cluster name) in `DS.caption`/`DS.textMuted`, and a `arrow.up.right` glyph that
  appears on hover (travel affordance). `.help("Open Pricing psychology in Marketing
  (⏎)")`.
- Body: the region thumbnail. If the target changed since last view, a 6pt accent dot on
  the header (same "unseen activity" language as pane spines — one dialect everywhere).
- Hover: standard card lift. Drag-over with a block: `DS.accentSoft` ring + the
  thumbnail brightens 4% (`.hover`); drop animates the block shrinking *into* the portal
  (scale to thumbnail-space position, 350ms `.gentle`) — the single moment of theater,
  and it's informative: it shows you *where* in B the block landed.
- Creation: cluster context menu "Create portal to this cluster…" (picks a destination
  thinkspace via a small searchable popover), dragging a thinkspace from the sidebar onto
  a canvas, or Cmd+K "Portal to…".

### Acceptance
- Portal thumbnail reflects target edits within one save-debounce cycle.
- Travel → Cmd+[ round-trips exactly. Deleting the target turns the portal into a quiet
  "Lost destination" empty state with a relink action (teach the next action — never a
  dead grey box).

---

## Phase 5 — The Spokes Compiler

### Vision
One finished pillar asset in, a complete platform package out: newsletter, X thread, reel
script, carousel — each draft built by the writing engine *with your learned per-format
rules and the client's brand profile*, each shown as a true-to-format preview, each one
acceptance away from entering the pipeline as a linked content atom. The "one source →
every format" step the 2026 creator stack is still missing.

### Architecture
- **New:** `AI/SpokesCompilerEngine.swift` — orchestrates `UnifiedWritingEngine` once per
  selected format, injecting: pillar body, format rules (the learned slide-density rules:
  ~1 sentence/reel slide, ~4/carousel slide — these live as rules, not hardcoded), client
  profile context, and matched swipes for hook patterns. Concurrency: 2 at a time,
  streaming progress per spoke. Every spoke writes a receipt.
- Output: one content atom per accepted spoke, linked `contentToIdea`-style via a new
  `spokeOfContent` AtomLink type to the pillar; enters the pipeline at Draft phase.
- **New:** `UI/FocusMode/Content/SpokesCompilerView.swift` (+ spoke card subviews).
- Entry: a "Compile spokes" action in the Content focus mode pipeline bar, enabled from
  phase 4 (Polish) onward; also a Cmd+K verb on content atoms.

### UI spec — the staging board
A full-width sheet over the content focus mode (`cosmoGlassPanel`, 24pt, `.modal`
entrance from the pipeline bar button):
- **Left rail (320pt):** the pillar — title, excerpt in `DS.body` with a proper reading
  measure, source idea + client chips. Read-only; this is the anchor.
- **Right field:** format cards in a 2-col grid. Each card (`.glassCard`, format icon,
  title `DS.headline`):
  - *Queued:* toggle on/off (which formats to compile), estimated length chip.
  - *Drafting:* skeleton bars in `DS.glassSectionFill` with gated shimmer + streaming
    text arriving — never a spinner.
  - *Ready:* a **true-to-format preview** (non-negotiable, per the full-previews rule):
    thread = stacked mini tweet cells; carousel = swipeable mini slides with the real
    slide text; reel = script with timecode gutters; newsletter = subject line + lede.
  - Footer per card: word/slide count `.monospacedDigit()`, "Open diff" ghost button
    (full review in the editor with the existing inline-diff system), and Accept
    (`DS.accent` capsule) / Regenerate (ghost).
- Cards cascade in on open (`cascade`, cap 6). Accepting a card: it compresses 0.97 →
  flies toward the pipeline bar (scale + opacity along a 400ms `.gentle` path) — the
  pipeline phase dot ticks up. Tangible "it entered the system".
- Receipts: a final summary row — "4 spokes created and linked to *How pricing anchors
  work*" with jump links.

### Acceptance
- Spokes carry client voice (verify profile injection) and respect format rules without
  manual cleanup. Rejecting a spoke leaves zero orphan atoms. Pillar ↔ spokes links
  visible in both directions in inspectors.

---

## Phase 6 — Living Workflows ("Flows")

### The pitch, properly

Today the canvas *stores* your thinking. Flows make it *work* for you. A Flow is a drawn,
visible piece of behavior: an ink line from a place where knowledge arrives to a place
where something should happen, with one verb chip in the middle. The canvas becomes the
only automation surface that already contains your knowledge — tldraw.computer has
executable nodes but no knowledge underneath; Heptabase has knowledge but nothing moves.
You have both halves; Flows is just the visible skin over the `AutomationRule` engine
that already ships in this codebase (Automation/AutomationRule.swift — triggers,
conditions, cluster scoping, cooldowns, all built).

**A creator's actual week with Flows:**

1. **The morning router.** Telegram captures land in an "Inbox tray" zone on your main
   canvas. One Flow: *tray → Route → by type* — research drifts to the topic cluster it
   matches, ideas land on the idea board, tasks file to Command Center. You arrive at
   9am to a canvas that triaged itself overnight — every move logged in the ledger,
   every wrong call draggable back. (Trigger: `addedToThinkspace`; action: route. The
   engine does this today; Flows makes it drawable and visible.)
2. **The hook harvester.** Your "Hooks I love" cluster has a Flow: *cluster → Extract →
   Hook Library*. Every swipe you toss in gets its hook pattern pulled and appended to a
   living Hook Library note — with a link back to the swipe. After a month you have a
   personal, sourced pattern book you never sat down to write. (`movedToCluster` →
   extraction action.)
3. **The newsletter assembly line.** A "Newsletter #42" cluster with *cluster → Draft →
   Content pipeline*, set to fire "when I run it" plus a gentle nudge at 5 blocks. Friday
   morning: the chip shows a quiet badge — enough material. You hit Run; a draft built
   from exactly those blocks (with citations) lands in the pipeline and opens in a pane.
   Synthesis pressure, made physical. (`linkCountReaches`/manual → writing engine.)
4. **The client factory.** Drop anything into the "Acme" cluster: a Flow tags it to the
   client profile and a second Flow drafts hooks in Acme's voice for anything marked
   idea. Two drawn lines replace a checklist you currently hold in your head.
   (`clientAssigned` + `atomTypeCreated` triggers — both already exist.)
5. **The Friday distiller.** A schedule Flow (small clock badge on its chip): every
   Friday 4pm, *this thinkspace → Distill → Weekly review note*, placed in the corner,
   linking everything it summarized. Your week, pre-read. (`schedule` cron trigger —
   already in the engine.)

None of these are new engine capabilities. **Every one is an existing trigger/action pair
that is currently invisible and unauthorable.** That's the entire bet: the engine is
built; what's missing is a way to *see* and *draw* it.

### Design language — premium, not game (the explicit answer)

The metaphor is **a diagram in a field notebook that occasionally carries light** —
never a factory, never a node graph:

- **Lines are ink.** 1.5pt bezier in `DS.textMuted` at 35%, drawn with the same curve
  family as `KnowledgePulseLineView` / `SanctuaryConnectionThread`. A small chevron
  arrowhead. Propose-mode flows are dashed. **Idle flows are completely static** — zero
  ambient animation (the perf pass killed idle animation; Flows honors that). At rest, a
  canvas full of Flows looks like a beautifully annotated diagram, not a machine.
- **One chip per flow, not nodes.** The verb lives in a single capsule chip at the line's
  midpoint: `.glassEffect(.regular.interactive(), in: .capsule)`, SF symbol + verb in
  `DS.caption` semibold, tinted by *output* entity type (Draft → content blue, Distill →
  note ochre). No boxes-and-wires graph. Two sizes: full (icon+label) above 0.6× zoom,
  icon-only dot below.
- **Firing is one bead of light.** When a Flow runs: a 4pt `DS.accent` bead travels the
  line once (~600ms, `TimelineView`-driven like the existing pulse lines), the chip
  scales 1.04 → 1.0 (`.snappy`), and a ledger entry appears. That's the entire show.
  Reduce Motion: chip tick only. If five flows fire at once, beads stagger 80ms — never
  a light show.
- **Trust chrome is quiet.** No toasts by default. The cluster inspector and Command
  Center carry the **Flow Ledger**: "Distilled 4 research blocks → updated *Pricing
  psychology* · 9:14 · view · undo" in `DS.subheadline` rows. Every firing is undoable
  from the ledger. Destructive verbs (Route/move) default to **propose mode**: instead of
  acting, they stage a ghost suggestion (the dashed-line + ghost-block language), and
  you accept/reject — proactive-but-suggestive, preserved.

### Authoring — intuitive in three gestures

1. **Hover a cluster edge** → three 6pt port dots fade in on the border (`.hover`), the
   same affordance grammar as Figma connectors and your DragToConnect manager.
2. **Drag from a port** → a ghost ink line follows the cursor with magnetic snap to
   valid targets (clusters, note blocks, the Command Center masthead block, a portal —
   snap = the target gets the `DS.accentSoft` ring). Invalid targets simply don't snap;
   nothing shakes or flashes red.
3. **Release → the verb picker** blooms at the drop point (`.bouncy`, same component
   family as AnnotationTypePickerPopover): a vertical glass list of 6 verbs, each with
   icon, name, and a one-line plain-language description. Pick one; the line inks itself
   in (a 300ms draw-on of the bezier path — the one entrance flourish), chip settles at
   the midpoint. Done — the Flow is live with smart defaults.

**Verbs v1** (each compiles to an `AutomationRule` — the "verb → rule compiler" is the
core new engine code):

| Verb | Plain sentence (shown in inspector) | Engine mapping |
|---|---|---|
| Distill | "…summarize what's here into a note" | trigger per config → writing engine summarize |
| Draft | "…turn this into a content draft" | → UnifiedWritingEngine, pipeline insertion |
| Route | "…move matching items to {target}" | → move/copy action (defaults to propose mode) |
| Extract | "…pull {hooks/claims/quotes} into {note}" | → extraction prompt + append |
| Ask | "…have Cosmo pose an inquiry question here" | → inquiry question card (exists) |
| Digest | "…on a schedule, compile a review" | `schedule` trigger + distill |

- **When does it fire?** Default: "when something new arrives" (`movedToCluster` /
  `addedToThinkspace`). Click the chip → inspector (mirror of `ClusterInspectorPanel`:
  360pt, `cortexInspectorPanel`, 24pt radius) where the rule reads as **one editable
  natural-language sentence**: "When *research* arrives in *Pricing psychology*, distill
  it into *Topic page*." Underlined segments are menus (the Things 3 natural-language
  trick). Below: run-mode (on arrival / at N items / on schedule / manual), propose
  toggle, cooldown, and the per-flow ledger. A Run button always exists — every Flow is
  also manually invokable, which is how users learn to trust them.
- Tearing a line (drag chip away from line, or Delete) removes the Flow — rule disabled,
  ledger retained 30 days.

### Architecture
- **New:** `Automation/FlowCompiler.swift` (verb+ports+config → `AutomationRule` CRUD;
  rules get `metadata.flowUUID` so the canvas and engine stay 1:1),
  `Canvas/FlowLineLayer.swift` (render layer beside `CanvasConnectionLinesLayer`, reusing
  its bezier + Metal-friendly batching), `Canvas/FlowChipView.swift`,
  `Canvas/FlowVerbPicker.swift`, `Canvas/FlowInspectorPanel.swift`,
  `UI/Automation/FlowLedgerView.swift`.
- Flow geometry persists in `ThinkspaceMetadata` (alongside `clusters`); the *behavior*
  lives only in `AutomationRule` — single source of truth, no parallel engine.
- Action executions route through the existing `AutomationRuleEvaluator` → executor path;
  new actions (distill/draft/extract) call the same engines the agent tools already use
  (Agent/Core/AgentToolExecutor.swift) — no duplicate writing paths.
- Ledger = a GRDB `flow_firing` table: ruleUUID, inputs, outputAtomUUIDs, timestamp,
  undo payload.

### Phasing inside Phase 6
- **6a:** Flow drawing + chips + manual Run + Distill/Draft verbs + ledger. (Manual-only
  flows are already magical and build trust.)
- **6b:** Arrival triggers + propose mode + Route/Extract/Ask.
- **6c:** Schedule flows + Digest + the threshold nudge badges.

### Acceptance
- A canvas with 30 idle flows renders identically in performance to one with none
  (static layer, zero timers).
- Draw → fire → undo round-trips losslessly. Killing the app mid-fire leaves a coherent
  ledger entry (fired or not — never half).
- The "game test": screenshot a canvas with 5 flows at rest — a designer should read it
  as an annotated diagram, not an automation tool.

---

## The polish gates (every phase, before merge)

1. peakui audit checklist top to bottom (hierarchy, material, motion, manners, truth).
2. Reduce Motion + Reduce Transparency full pass.
3. 120Hz check with the performance overlay during: pane swaps, peeks, constellation
   dive, flow firing, camera flights.
4. The look test: new surface side-by-side with Cmd+K, the sidebar, and the cluster
   inspector — same glass family, same title voice, same motion dialect.
5. Keyboard-only walkthrough: every feature reachable and dismissible without a mouse.

## Keyboard map (new bindings introduced by this plan)

| Binding | Action |
|---|---|
| `⌘[` / `⌘]` | Back / Forward |
| `⌘D` (canvas) | Save Place |
| `⌘⌥1…9` | Jump to Place |
| `Space` | Peek selection · again to close |
| `⌘⏎` (in peek) | Promote peek to pane |
| `⌘1…6` | Focus pane N |
| `⌘⇧[` / `⌘⇧]` | Cycle pane focus |
| `⌘⇧P` | Pin focused pane |
| `Ctrl+1…9` | Apply Workbench |
| `⌘⇧Space` | Constellation (binding TBD vs global map) |
| `⏎` (portal selected) | Travel through portal |

All bindings verified against the existing shortcut map before implementation; conflicts
resolved in favor of existing muscle memory.
