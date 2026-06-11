# Inbox Revamp — The Capture System, Closed-Loop Edition

> Status: IMPLEMENTED (June 11 2026). All phases shipped — ingestion contract
> (`InboxIngestService`), routing v2 (`InboxRoutingEngine` actor + `InboxRoutingConfig`),
> triage-queue UI (`InboxView`/`InboxQueueRow`/`InboxInspector`), closed-loop verbs,
> Command Center chip, ⌥⌘N capture, lanes grid. Build + inbox test suites green.
> Sources of truth verified against code on June 11 2026.
> Design system: peakui (Greenhouse Liquid Glass). Reference surfaces: Command Center
> masthead/ledger, Connection workspace toolbar + inspector, ThinkspaceLibrary Finder grammar.

---

## 0. Diagnosis — why the inbox feels broken (all confirmed in code)

The current inbox conflates **three different jobs** in one surface, and two of them
don't belong there:

1. **Capture intake** — things you explicitly threw at the system (Telegram, capture
   bar, voice). *This is the inbox.*
2. **Database hygiene** — `loadUnplacedDatabaseItems()` (`UI/Inbox/InboxViewModel.swift:827-869`)
   scans GRDB for up to **80 atoms** of types note/task/content/research/connection/
   clientProfile/image that have no thinkspace membership and injects them as an
   "Unplaced database" cluster. This is why "115 thoughts waiting for a home" and
   "80 unplaced" — most of it is not captures at all, it's your existing database
   being re-litigated.
3. **AI second-guessing** — items that already have homes being re-triaged.

### Confirmed root causes, one per complaint

| Complaint | Root cause | Where |
|---|---|---|
| "Agent Conversation: inApp" merge suggestions | Agent chats are persisted as `.systemEvent` atoms titled "Agent Conversation: …" with the **full transcript as body** (`Agent/Memory/ConversationMemoryService.swift:77-84`). They're indexed for hybrid search, and `bestMergeRecommendation()` only excludes `.thinkspace` (`AI/InboxRoutingEngine.swift:357`). A transcript containing everything you've ever discussed semantically matches *every* capture — so it wins every merge. | `InboxRoutingEngine.swift:342-393` |
| Everything routes to Philosophy | Cluster score = `memberScore*0.40 + lexical*0.27 + …` with pass threshold **0.22** and a recency boost up to **+0.20** (`InboxRoutingEngine.swift:299-333, 640-646`). The biggest, most-recently-opened cluster wins by mass, not by meaning. No abstain state — a 0.24 match is still "recommended". | `InboxRoutingEngine.swift` |
| Items stuck in "Needs your judgment" / "28 classifying" | `TelegramCaptureRouter.saveToGlobalInbox()` creates InboxItems and **never classifies them** (`Agent/Bridges/TelegramCaptureRouter.swift:344-361`); classification is call-site-dependent, so fallback items sit at `classification == nil` forever and render as "Needs your judgment". | `TelegramCaptureRouter.swift:344` |
| Client ideas appear in inbox | Ideas created through agent/Telegram flows double-enter: the idea atom is created AND the raw message falls through capture routing into the global inbox (`saveToGlobalInbox` fires on "Unprefixed media capture", "No active inquiry session", "Unknown capture destination" — lines 64, 161, 196). Nothing marks a capture as *consumed* once another system has acted on it. | `TelegramCaptureRouter.swift` |
| Notes/things I never captured appear | The unplaced-database scan (job 2 above). | `InboxViewModel.swift:827-869` |
| Lag | Classification runs on `@MainActor` including the XPC embedding call (`InboxRoutingEngine.swift` is `@MainActor`; `DaemonXPCClient.shared.embed` on the hot path), plus the 80-item GRDB scan + membership join on visibility, plus soft-cluster rebuilds on every Combine emission. | `InboxRoutingEngine.swift`, `InboxViewModel.swift` |
| UI feels long/broken | `InboxItemCard` stacks up to **10 vertical rows** (badge row, title, preview, confidence meter, suggestion, rationale, alternatives, insight, stale nudge, action row — `UI/Inbox/InboxItemCard.swift`, 496 lines). Three view modes (Lanes/Canvas/List), two filter-chip rows, a stats row, a zoom slider — chrome with no hero. | `UI/Inbox/` |

**The single most important decision in this plan:** the inbox shows *only explicit
captures awaiting a decision*. Database hygiene and second-guessing are evicted.

---

## 1. The contract — what the inbox IS

### Membership rule (hard invariant)

An item appears in the Inbox **iff**:

1. It was **explicitly captured** — Telegram capture, `inbox:` prefix, in-app capture
   bar, voice capture; AND
2. **No other system consumed it** — if the agent (or a capture lane, or an inquiry
   route) already created an atom from the message, the capture is marked *consumed*
   and never becomes an inbox item; AND
3. It hasn't been actioned or dismissed.

Corollaries:

- **Ideas**: a loose idea captured without a home enters the inbox *already typed as
  an idea* — it needs only a placement decision, one keystroke. An idea created **for
  a client** (or via Command-K / agent tooling) is fully homed at birth → it never
  enters triage. "It's already an idea" — exactly: type decisions made at capture
  time are never re-asked.
- **The "Unplaced database" cluster is deleted from the inbox.** If database hygiene
  is wanted later, it becomes a Library smart collection ("No home yet"), where
  browsing existing objects belongs. Nothing in the inbox that the user didn't throw
  there.
- **Triage state lives on `InboxItem` only** — never inferred from database scans.

### One ingestion choke point: `InboxIngestService`

Today, InboxItems are created from 5 call sites with inconsistent behavior
(`InboxViewModel.swift:255`, `TelegramCaptureRouter.swift:350`,
`TelegramTopicAliasParser.swift:120`, `FlashLiteRouter.swift:348`,
`InboxCaptureConverter.swift:83,248`). All of them get replaced by one service:

```swift
// Data/Services/InboxIngestService.swift (new)
@MainActor final class InboxIngestService {
    enum IngestOutcome { case consumed(atomUUID: String)   // another system owns it
                         case enqueued(InboxItem) }         // awaiting triage

    func ingest(_ capture: RawCapture) async -> IngestOutcome
}
```

- Dedup by `sourceAtomUuid` / `capturedItemUuid` (exists today, keep).
- If the originating flow already produced an atom (agent created an idea, inquiry
  route created an extract), the ingest call records `consumed` — no inbox item.
- Every enqueued item is handed to the **classification queue** (below). No call
  site classifies on its own ever again — that's the bug class that produced
  stuck-forever "classifying" items.

### Classification lifecycle (owned by the service, off the main thread)

```
captured ──> pending ──[classifier queue]──> suggested (has a confident suggestion)
                                        └──> unsorted  (honest "no idea" state)
suggested/unsorted ──[user verb]──> actioned | dismissed
```

- A background queue (actor, not `@MainActor`) drains all `pending` items: embedding
  (cached per item), routing, write-back. Survives app restarts — on launch, any
  `pending` item re-enqueues. *"Classifying" can no longer be a permanent state.*
- **`unsorted` is a first-class honest state.** No fake suggestions below the
  confidence bar. An unsorted item just shows the capture, beautifully, and waits
  for you.

---

## 2. Routing engine v2 — meaning over mass

Replace the additive-weights heuristic with a staged router that **abstains by
default**. (Per project memory: systemic, state-based — no keyword bandaids; and
LLM prompts must teach, not tell.)

### Stage 0 — Intent gate (fast, local)
What *kind* of thing is this? `task | question | idea | quote/excerpt | link | note`.
Lightweight heuristics + existing Flash-lite path. Output determines which **verbs**
the UI offers (see §4) — it never forces a folder.

### Stage 1 — Merge check (high precision, rare by design)
- Candidate pool: **user-content types only**. Central definition:
  ```swift
  extension AtomType {
      /// Types a capture may merge into or be filed alongside.
      static let triageable: Set<AtomType> = [.note, .idea, .research, .content, .connection]
  }
  ```
  `.systemEvent` (agent conversations), `.thinkspace`, `.clientProfile`, `.task`,
  images, swipe files: **never merge targets**. Additionally exclude
  `metadata.subtype == "agent_conversation"` defensively, and exclude `.systemEvent`
  from the hybrid-search index for inbox queries at the source.
- Bar: near-duplicate territory only — combined score ≥ 0.80 **with** title-token
  overlap, or exact-title match. A merge suggestion should feel like the system
  caught a duplicate, not like it's inventing relationships.

### Stage 2 — Placement suggestion (centroids + margins, not membership mass)
- Score against **cluster/thinkspace centroids**: mean embedding of member atoms,
  cached in GRDB, invalidated on placement events. Kill `memberScore * 0.40`
  (rewards big clusters), kill the recency boost (rewards whatever you opened
  yesterday — this is the Philosophy magnet).
- Suggest only when: top-1 ≥ **0.55** AND margin over top-2 ≥ **0.08**. Otherwise →
  `unsorted`. Tiered confidence drives UI tint only (no percentages anywhere).
- Keep lexical title overlap as a *bonus*, never a substitute.

### Stage 3 — Lazy LLM batch pass (when the inbox is opened)
For `unsorted` items only, one batched Flash call with the **actual folder taxonomy**
in the prompt — names, descriptions, 3 example member titles per cluster — taught
with explicit decision criteria and an explicit "none of these" option. Runs only
when the inbox is visible, batched, never per-item. This replaces the re-rank path
whose old 0.08-gap trigger multiplied LLM cost 88× (`InboxRoutingEngine.swift:409-420`).

### Engineering
- `InboxRoutingEngine` loses `@MainActor`; becomes an actor. Embeddings cached
  (`captureUUID → vector`). Centroid cache keyed by cluster id.
- All thresholds in one `InboxRoutingConfig` struct — no magic numbers scattered
  across 660 lines.

---

## 3. The UI — one calm surface

### The moment
*You open the inbox with 14 captures and feel calm. Two minutes of single keystrokes
later it's empty, and everything is exactly where it belongs.* The inbox is a
**triage queue** (Things 3 / Apple Mail energy), not a dashboard, not a canvas.

### What dies
- The Canvas/List mode toggle, the zoom slider, the soft-cluster grid
  (`InboxSpatialCanvasView.swift`, `InboxSpatialCardView.swift`).
- The stats badge row and double filter-chip row (`InboxStatsBar.swift`).
- The 10-row mega-card (`InboxItemCard.swift` in its current form).
- "Possible merges / Ready to place / New patterns forming / Needs your judgment /
  Unplaced database" cluster headings — the queue is grouped by *time*, suggestions
  live *on the row*.

The spatial-placement *capability* is preserved and promoted — it moves into the
inspector's minimap (your favorite part), where it's an action, not a browsing mode.

### Layout

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  Inbox                                                    [Lanes]  [⌥⌘N]    │ ← masthead: DS.pageTitle (28 semibold)
│  14 captures · 9 with suggested homes                                        │ ← DS.callout, DS.textSecondary
│  ──────────────────────────────────────────────────────── hairline           │
│                                                                              │
│   ⊕  Capture a thought…                                              ⏎      │ ← hero: dsGlassInput, full width
│                                                                              │
│   TODAY ────────────────────────────────────── small-caps, DS.caption        │
│  ┌────────────────────────────────────────────────────┐  ┌────────────────┐ │
│  │ ●  do or do not, there is no « try »               │  │   INSPECTOR    │ │
│  │    Telegram · 2:14 PM            ⟶ Stoicism  ⏎    │  │  (on select)   │ │
│  ├────────────────────────────────────────────────────┤  │                │ │
│  │ ●  a Jedi must focus less on his eyes…             │  │  essence       │ │
│  │    Telegram · 1:48 PM            ⟶ Stoicism  ⏎    │  │  suggestion +  │ │
│  ├────────────────────────────────────────────────────┤  │  one-line why  │ │
│  │ ○  remix feature inside of swipe file (hook &…     │  │                │ │
│  │    Capture · 1:02 PM                Unsorted       │  │  ┌──────────┐  │ │
│  └────────────────────────────────────────────────────┘  │  │ MINIMAP  │  │ │
│   YESTERDAY ──────────────────────────────────            │  │ ▣ ·  ░░  │  │ │
│  ┌────────────────────────────────────────────────────┐  │  │  · ✦ ·   │  │ │
│  │ …                                                  │  │  └──────────┘  │ │
│  └────────────────────────────────────────────────────┘  │  [Place ⏎]     │ │
│                                                           │  Task· Ask· …  │ │
│                                                           └────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Hierarchy:** the hero is the *capture text itself* — `DS.body`, full ink. The
suggestion is a single trailing pill. Everything else (source, timestamp) is
`DS.caption` muted metadata. One hero per row, one hero per screen (the queue).

### Row grammar (`InboxQueueRow`, replaces `InboxItemCard`)

- **~56pt collapsed**, two lines max:
  - Line 1: status dot (6pt: `DS.accent` = suggested, `DS.textMuted` ring = unsorted)
    + capture title, `DS.body`, lineLimit 1.
  - Line 2: `Telegram · 2:14 PM` in `DS.caption`/`DS.textMuted` + spacer + the
    **suggestion pill**.
- **The suggestion pill is the only AI presence in the row**: `⟶ Stoicism ·
  Philosophy` — capsule, `DS.accentSoft` fill when confident, `DS.glassSectionFill`
  neutral when tentative, **absent** when unsorted (shows quiet "Unsorted" text).
  No percentage meters, no rationale, no alternatives, no insight lines, no stale
  nudges in the row. All of that demotes to the inspector.
- Hover: `commandCenterCardLift`-style hairline + lift (`ProMotionSprings.hover`),
  reveals ghost verb buttons trailing (✓ place · ✕ dismiss).
- Click/→: opens inspector. Background: rows sit directly on `DS.bg` separated by
  hairlines (ledger style, like Command Center tasks) — **not** floating cards;
  cards-in-a-list is what made the old UI read heavy.
- Sections: `Today / Yesterday / This Week / Older`, pinned small-caps headers
  (`DS.caption`, `.tracking(1.4)`), exactly like Command Center ledger sections.

### Inspector (rework of `InboxSpatialInspector` → `InboxInspector`)

340pt right panel, `cosmoGlassPanel(role: .focusSidebar, cornerRadius: 22)`, slides
in with `ProMotionSprings.gentle` like the Connection workspace inspector:

1. **Essence** — the full capture text, serif display if long-form quote
   (`DS.displaySerif` is allowed here: it's *content you read*).
2. **Suggestion** — destination name + *one sentence* of why, `DS.subheadline`.
3. **Minimap** — the signature move. Live miniature of the target thinkspace with
   the proposed block position glowing (`DS.accent` pulse). `⏎` confirms; drag the
   ghost block to adjust before committing; `⌘⏎` = Place & Go (navigates to canvas,
   existing flow at `InboxViewModel.placeAndGo`, keep).
4. **Alternates** — up to 2 alternate destinations as quiet rows (only if they
   cleared the margin bar).
5. **Verb grid** — Place / Merge (when offered) / Task / Ask / Idea / Dismiss.

### Keyboard model (the Raycast law — clearable without a mouse)

| Key | Action |
|---|---|
| `↑/↓` | Move focus through the queue |
| `⏎` | Accept suggestion (place/merge) |
| `⌘⏎` | Place & Go (navigate to the canvas spot) |
| `⌫` | Dismiss |
| `T` | Make task → Command Center |
| `A` | Ask — spin into Deep Dive inquiry question |
| `I` | File as idea |
| `M` | Open merge picker (when a merge is offered) |
| `Space` | Quick-look the full capture |
| `⌥⌘N` | Focus the capture field from anywhere in the app |

`.help()` tooltips with shortcut hints on every verb; focus ring via `DS.focusRing`.

### Empty state
Teaches, then celebrates: *"Captures from Telegram, ⌥⌘N, and voice land here."*
After a triage session: *"Inbox zero — 14 captures placed today"* with a quiet
`DS.gilt` flourish (this is the rare ornament moment).

### Capture Lanes (`CaptureLanesView`, 598 lines — restyle, not rebuild)
Lanes become a **destinations grid** in ThinkspaceLibrary Finder grammar: adaptive
148–178pt tiles, 14pt gutters, folder iconography, member counts, drag a queue row
onto a lane tile to route it. Reached via the masthead `Lanes` button (existing
`SidebarInboxRoute.captureLanes` routing, keep).

### Motion
- Queue entrance: `ProMotionSprings.cascade(index:)` capped at 8.
- Row accept: row compresses 0.97, pill morphs to checkmark, row slides out
  trailing-edge with `.snappy`; remaining rows close ranks via the same spring.
- Inspector: slide + materialize (`glassEffectTransition(.materialize)`).
- Undo toast (keep existing): bottom glass capsule, 6s, `⌘Z` works.
- All gated on Reduce Motion.

---

## 4. The closed loop — every capture has somewhere real to go

The triage verbs are the seams that stitch the app's systems together:

| Verb | Destination | Mechanism |
|---|---|---|
| **Place** | Thinkspace canvas | Existing `InboxActionExecutor.executePlace` + `SpatialPlacementPlanner` + minimap confirm. |
| **Merge** | Existing user-content atom | Existing `executeMerge` blend; now rare/high-precision. |
| **Task** | Command Center | Creates task atom (existing `routesToTask` intent path); lands in today/unscheduled tray. |
| **Ask** | Deep Dive / Inquiry | `InquiryRepository.createQuestion` against the active (or chosen) Deep Dive — the Telegram `question` subroute already does this (`TelegramCaptureRouter.swift:285-295`); surface it as a first-class in-app verb. |
| **Idea** | Ideas pipeline | Types the atom `.idea`, optional client tag, triggers `IdeaInsightEngine.quickEnrich`. Never re-enters the inbox. |
| **Connect** | Connection system | When a capture strongly matches **2+** atoms, offer "Connect" instead of merge: creates the AtomLinks and (optionally) seeds a Connection atom. A capture that bridges two things is a connection, not a duplicate. |
| **Dismiss** | — | Existing, with undo. |

**Command Center module:** a quiet inbox chip on the Today page —
*"Inbox · 5 to triage"* — in the context rail; click navigates to the inbox. At
inbox zero it disappears (no nagging chrome). This makes morning triage part of the
daily ritual loop: Capture (anywhere) → Triage (inbox) → Work (command center /
focus modes) → Connect (thinkspace) → back around.

---

## 5. Implementation phases

### Phase 0 — Stop the bleeding (small diffs, immediate relief)
1. **Evict the unplaced-database cluster**: delete `loadUnplacedDatabaseItems()`,
   `unplacedDatabaseItems`, the `database` soft-cluster kind and
   `InboxSpatialDatabaseCard` usage (`InboxViewModel.swift:827+`,
   `InboxSpatialModels.swift`, `InboxSpatialCanvasView.swift`).
2. **Merge-target allowlist**: add `AtomType.triageable`; filter in
   `bestMergeRecommendation` and in the hybrid-search query for inbox routing
   (`InboxRoutingEngine.swift:353-358`). Kills "Agent Conversation: inApp" spam.
3. **Unstick pending items**: on launch, re-enqueue `pending` items through
   classification; items older than N days with no classification auto-mark
   `unsorted` (visible, honest), never silently dropped.
4. **One-time cleanup migration**: dismiss inbox items whose `sourceAtomUuid` /
   `capturedItemUuid` corresponds to an atom another system already created
   (consumed captures — the client-idea double-entries).
5. **Off the main thread**: drop `@MainActor` from `InboxRoutingEngine` /
   classification path; write-back hops to MainActor only for repo publish.

*Exit criteria: inbox count = real captures only; no systemEvent merge targets; no
permanent "classifying"; no scroll stutter.*

### Phase 1 — Ingestion contract
1. New `Data/Services/InboxIngestService.swift` with `IngestOutcome`
   (consumed/enqueued) + classification queue (actor).
2. Route all five creation call sites through it (`InboxViewModel`,
   `TelegramCaptureRouter`, `TelegramTopicAliasParser`, `FlashLiteRouter`,
   `InboxCaptureConverter`).
3. Consumed-capture rule: agent/lane/inquiry flows report their created atom to the
   ingest service; ideas-for-client never double-enter.
4. Tests: ingest outcomes, dedup, queue drain on launch, consumed exclusion.

### Phase 2 — Routing engine v2
1. `InboxRoutingConfig` (all thresholds in one place).
2. Centroid cache (GRDB table: cluster id → vector, invalidate on placement).
3. Staged router: intent gate → merge check (≥0.80 + title overlap) → centroid
   placement (top-1 ≥ 0.55, margin ≥ 0.08) → abstain to `unsorted`.
4. Lazy batched LLM pass for unsorted, taxonomy-teaching prompt, visibility-gated.
5. Remove recency boost & membership-mass scoring; embedding cache.
6. Tests: routing fixtures — "short quote routes nowhere without evidence",
   "near-duplicate merges", "agent conversation never a candidate", margin abstain.

### Phase 3 — UI rebuild (peakui pass)
1. `InboxView` rebuilt: masthead (Command Center grammar) + hero capture field
   (`dsGlassInput`) + sectioned `LazyVStack` ledger + inspector slot. One mode.
2. New `InboxQueueRow` (~56pt, suggestion pill, hover verbs).
3. `InboxInspector` (from `InboxSpatialInspector`): essence / suggestion / minimap /
   alternates / verb grid, `cosmoGlassPanel(.focusSidebar)`.
4. Minimap placement component: live thinkspace miniature + ghost block + drag
   adjust (reuse `SpatialPlacementPlanner` output; existing Place & Go flow).
5. Keyboard model + `.help()` tooltips + focus ring + 44pt targets.
6. Delete: `InboxSpatialCanvasView.swift`, `InboxSpatialCardView.swift`,
   `InboxStatsBar.swift`, `InboxGroupSuggestionCard.swift`; slim
   `InboxSpatialModels.swift` to what the inspector needs; `InboxItemCard.swift`
   replaced by `InboxQueueRow`. (pbxproj: manual file registration — see
   deep_dive_revamp memory.)
7. Empty state + inbox-zero state; entrance cascade; Reduce Motion gates.

### Phase 4 — Closed loop
1. Verb wiring: Task (exists), Ask → `InquiryRepository.createQuestion`, Idea →
   type + optional client + `quickEnrich`, Connect → AtomLinks on 2+ strong matches.
2. Command Center "Inbox · N to triage" chip in the context rail; disappears at zero.
3. `⌥⌘N` global capture shortcut focusing the inbox capture field.

### Phase 5 — Lanes restyle + final polish
1. `CaptureLanesView` → destinations grid (Finder grammar, adaptive tiles,
   drag-to-route from queue rows).
2. Full peakui audit checklist pass on every new surface; side-by-side look test
   with Command-K, Command Center, Connection workspace.
3. Build + test: `xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS
   -configuration Debug build` / `test`. Manual QA with Reduce Motion + Reduce
   Transparency.

---

## 6. What is explicitly preserved

- Visual placement into Thinkspace (minimap) — promoted, not removed.
- Place & Go navigation flow (`InboxViewModel.placeAndGo`).
- Undo toast + `CosmoUndoManager` integration.
- Capture lanes as a concept and `SidebarInboxRoute` routing.
- Telegram capture pipeline + dedup via `sourceAtomUuid`.
- `InboxActionExecutor` merge/place mechanics (filtered, not rewritten).
- Agent conversation memory itself (`ConversationMemoryService`) — it just stops
  leaking into search-driven suggestions.
