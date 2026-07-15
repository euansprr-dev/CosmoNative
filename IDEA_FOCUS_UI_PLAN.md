# Idea Focus Mode — UI Overhaul Plan (macOS)

*July 15, 2026 — research + design plan. PeakUI is the governing system;
every decision below cites the law or first-party pattern it comes from.*

> **STATUS (July 15, evening): BUILT.** Phases 1–4 and 6–7 shipped in
> `IdeaFocusModeView/Toolbar/InspectorView/ManuscriptEditors.swift` (+
> `CodexOutlineEditing.moveSlide`, shared `atelierStaggerIn` Reduce-Motion gate,
> `IdeaInspirationThumb` extraction). Phase 5 shipped as the lighter variant
> (sheets keep the AtelierSheetHeader register on the focus paper ground).
> Deliberate deltas from the plan: reorder is ⌥↑/⌥↓ keyboard-first (no drag
> handles on NSTextView rows); card→page morph deferred (existing
> `focusImmersiveEntryTransition` kept). Build green; all idea-pinned test
> suites pass. Details: memory `idea_focus_v3_development_bench.md`.

---

## 1. What Idea Focus is FOR

An idea in CosmoOS is a **content seed**: an angle (the body), hooks that test the angle,
an outline of slides, inspiration (linked swipes), a structure (framework/arc), a proven
model (blueprint), research, a client, a format — ripening through statuses
(spark → developing → ready → in production → published) until **Begin Writing** promotes
it to Content.

So Idea Focus is not a reading room (Notes) and not a browse surface (Ideas home). It is
a **development bench**: the room where a spark becomes a script. Its five jobs:

1. Hold the angle in front of you (the manuscript).
2. Let you test hooks fast (the lab).
3. Shape the outline against a chosen structure (the blueprint table).
4. Keep inspiration in the periphery, ready to steal from (the studio wall).
5. Make ripeness legible, and hand off to writing with ceremony.

Everything in the redesign serves one of those five jobs. Anything that doesn't, goes.

---

## 2. Diagnosis — why it reads bare-bones today

Current anatomy: floating chrome-island toolbar → centered 680pt column on bare `DS.bg`
(kicker, serif title, meta line, context editor, hooks as bare lines, outline as bare
lines) → 280pt flat inspector on `DS.surface` → three plain 720×640 sheets.

The bones are right (island toolbar, serif manuscript voice, teaching empty states,
breakpoint model). What's wrong, audited against the peakui laws:

| # | Finding | Law violated |
|---|---------|--------------|
| D1 | The manuscript floats on naked `DS.bg` — no sheet, no vignette, no object identity. A 680pt column in a 1600pt window surrounded by void reads *unfinished*; the same column on a page reads *margins*. Notes solved this exact problem with per-note paper + vignette. | Material pass; Craft's "documents feel like objects" |
| D2 | **The intelligence is invisible.** `generatedHooks` (AI hook suggestions, produced whenever swipes are linked) render NOWHERE — they're silently consumed at promotion. `IdeaInsight` (matching swipes, format scores + rationale, emotional arc) feeds only the assistant context. The app is thinking and the UI never shows it. | Content is the hero — and here content is missing |
| D3 | No hero. Serif title, accent Begin Writing button, and section labels all compete at similar visual weight. | Law 2: one hero per screen |
| D4 | Linked swipes — the *visual* medium of inspiration — render as two lines of grey text in the inspector. The Ideas home card shows a 44×56 thumbnail; the focus mode drops it. | Full-previews feedback rule; identity outranks type |
| D5 | Inspector uses stock `.bordered` `.controlSize(.small)` AppKit buttons — straight system default, the fastest "template app" tell in the whole surface. | One grammar per screen |
| D6 | Section headers have no live counts ("HOOKS", "OUTLINE" — dead labels). Ripeness (status) is a tiny toolbar menu; the IdeaCard's five development ticks vanish in the very room where development happens. | Header voice + live counts; Law 12 |
| D7 | No arrival choreography — the page pops fully formed. No chrome recede while typing (Notes has it at 1.4s). No earned delight anywhere; Begin Writing — the whole point of the room — is a plain capsule that swaps to a spinner. | Motion pass; Things' earned-delight law |
| D8 | Scrolling kills orientation: title rides off, toolbar shows only status + client. | Law 12: never lose orientation |
| D9 | The three sheets (Blueprint / Research / Framework) are plain rectangles on `DS.bg` with an ad-hoc header — none follow the ⌘K one-surface anatomy. | Anti-pattern: nested/naked panel anatomy |
| D10 | Selection affordance gap: `selectedHookIndex` exists in the VM but no hook can be starred/picked in the UI; no reorder on hooks or slides. | Progressive disclosure; the lab has no verdict |

---

## 3. The reference teardown

### 3a. iOS Today page — part by part, and the Apple language each part speaks

This is the app's best surface. Every part of it maps to a first-party Apple pattern,
re-expressed in Greenhouse. The same method drives the Idea Focus redesign.

| Today part | Apple design language it speaks | Translation to Idea Focus |
|---|---|---|
| **Masthead** — 34pt bold title, serif gilt date line, companion mark alive to streak | Large-title register + editorial marginalia; identity mark with *state* (watch-complication thinking); Books' one-move blur-out exit | The idea head: kicker + serif hook title as hero + a status control that is *alive* (ripening ticks), not a dead menu label |
| **Context pill** on scroll | The large-title → inline-title collapse, re-expressed as a glass capsule | Mac-native equivalent: the idea's title + status surfaces in the toolbar's center island once the title hero scrolls off |
| **FocusGaugeCard** hero | Activity-ring emotional status; monospaced numerals; one hero card | Idea Focus's hero is the manuscript itself — but ripeness gets the same "state at a glance" treatment in the head |
| **CalendarStrip** (the givens) before tasks (the chosen) | Fixed-before-flexible ordering (Things/Fantastical) | The angle (what the idea IS) reads before hooks/outline (what you're still choosing) — current order is right, keep it |
| **Overdue** with Reschedule docked in header | Debt separated, one trailing slot per header | One trailing slot per section header: count OR action, never both |
| **Tasks ledger** — one grouped container, small-caps header, count ticks down, monochrome rows, accent only on the live row | The Files grammar + accent-as-punctuation | Hooks and outline become ledgers with live counts; accent only on the *chosen* hook |
| **Habit rows** — emoji identity, ramped haptic ticks | Earned delight, identity over type-glyphs | Swipe thumbnails carry identity in the rail; delight is spent on exactly one moment (promotion) |
| **Empty state** — "A clear day" + teaching line | Absence teaches the fix | Every empty section teaches ("Add a hook to test the angle" already exists — extend to all) |
| **Cascade arrival** + status-bar apron + FAB tail clearance | Pages assemble; edges are events | First-load cascade for the manuscript sections; scroll-edge treatment under the floating toolbar (already present — keep) |

### 3b. What the other loved surfaces teach

- **⌘K** — the one-surface anatomy for panels: near-opaque paper ground, hero bleeds
  edge-to-edge to ONE closing hairline, metadata as a flat label/value hairline ledger.
  This is the template for the three sheets (D9). Also: footers that teach shortcuts.
- **Notes focus mode** — the page ground doctrine: paper replaces the theme surface
  *wholesale* so margins read as page, not void; radial vignette pulls the eye to the
  column; chrome fades to 0.25 while typing and wakes on hover; word-count vitals live
  quietly in the identity badge; ONE earned delight (paper bloom). Idea Focus should
  inherit the ground, the recede, and the vitals verbatim — they're already proven here.
- **Sidebar / Connection workspace** — the island toolbar grammar Idea Focus already
  uses. Keep it; it passes the look test.
- **Ideas home (July 11)** — the IdeaCard is paper (`documentSurface` + sepia hairline +
  serif hook + inspiration thumb + dev ticks). **Opening a card should feel like the card
  becoming the page** — same paper, same serif, same ticks, grown up. That continuity is
  the identity move that makes the focus mode unmistakably part of the app.

---

## 4. The redesign — part by part

### 4.1 The stage (page ground) — kills the white-space problem at the root

Adopt the Notes page-ground doctrine:

- The whole page becomes **one warm sheet**: `DS.documentSurface` ground paired with
  `DS.documentText` ink (the paper doctrine — deliberate white-in-dark, like Notes
  paper), with the Notes-style radial vignette (`DS.inkWash.opacity(0.04)`, multiply)
  centering the eye on the column. Margins now read as *page*, not dead air.
- Manuscript column keeps its ~680pt measure, centered inside the sheet
  (`.frame(maxWidth: 680).frame(maxWidth: .infinity)` — the round-2 centering law).
- `.filmGrain()` is allowed here if Notes uses it on paper — hero content surface, not chrome.
- **Fallback position** (if the full sheet feels too heavy in review): keep `DS.bg` and
  float a single elevated sheet card behind the manuscript. Try the full ground first —
  it's what Notes shipped and what iA Writer does; the floating-card version reads more
  "web app".
- Update `FocusModeAppearanceTests` (it currently pins Idea as a Greenhouse-clean
  `DS.bg` mode) — this is a deliberate reversal of the June decision, driven by the
  white-space complaint.

### 4.2 The head (title hero) — one hero, alive to ripeness

- **Kicker row becomes the ripening control.** Replace the dead "IDEA · SPARK" caption
  with: `IDEA` small-caps + **five development ticks** (the IdeaCard's ticks, larger —
  filled per stage, `DS.entityIdea`) + the stage name. The whole cluster is one
  `Menu` (same status-change behavior as today's toolbar menu) with hover lift and a
  `.help()` naming the stage. Status changes tick the fill with
  `ProMotionSprings.snappy` + `.contentTransition(.numericText())` where numeric.
  The toolbar's duplicate status menu **goes away** — the head owns status now
  (duplicate-word law: the same control twice, 40pt apart).
- **Title** stays the hero: `DS.displaySerif`, the single largest element on the page.
  Everything else demotes one step.
- **Meta line** grows honest identity: client **color dot** (`DS.clientColor`) + name ·
  format mark + word · platform glyph + word · created date — the IdeaCard meta-line
  grammar exactly (`CollectionEmoji.formatMark`, `SwipePlatformGlyph`), muted caption.
  Client/format/platform each open their pickers on click (the meta line becomes the
  editing surface; the toolbar client menu can then also retire — chrome thins).

### 4.3 The angle (context editor) — mostly right, small moves

- Keep: serif 17pt voice, the sliding accent focus rule, mention chips, @-mention flow.
- Add: quiet vitals in the toolbar identity badge, Notes-style ("IDEA · 84 words") —
  the writing-app signal, nearly free.
- Placeholder stays "What's the angle?" — it's already teaching.
- Chrome recede: port Notes' `registerTypingActivity` (toolbar → 0.25 opacity while
  typing, wake on hover). The single biggest "pro writing app" signal (iA law), already
  proven in this codebase.

### 4.4 Hooks — from bare lines to the lab

The hooks section is where the idea is *tested*; it deserves the most new design.

- **Header**: `HOOKS · 4` — live count, `.numericText()` tick (Law: counts are alive).
- **The verdict affordance**: hover reveals a star/pick control per hook; picking sets
  `selectedHookIndex` (already in the VM, currently orphaned). The chosen hook gets the
  accent treatment — `DS.entityIdea` roman numeral + a hair of tint wash — and is the
  hook promotion carries forward as the working title. Accent discipline: exactly one
  hook can be "on".
- **AI suggestions surface at last (D2)**: when `generatedHooks` arrive, render up to
  3 as **ghost rows** below the user's hooks — muted italic serif, a small
  `sparkle` glyph in the numeral gutter, hover reveals Accept (promotes to a real hook
  row with a spring) / Dismiss. This is the board-native staged-ghost-row pattern the
  concept collaborator already shipped — same grammar, zero new vocabulary. While
  `isGeneratingHooks`: one skeleton ghost row (bars, gated shimmer), never a spinner.
- **Reorder**: drag handle on hover in the numeral gutter; roman numerals renumber with
  a spring. (Same interaction budget as Today's task reorder, vastly simpler — no
  scroll arbitration needed at this scale.)
- Keep the roman-numeral manuscript voice — it's charming, content-honest, and ours.

### 4.5 Outline — bind it to the framework

- **Header**: `OUTLINE · 6` live count; the `+ Slide` control stays docked in the header
  (one trailing slot — move the count into the label: "OUTLINE · 6").
- **Framework beats as ghost structure**: when a framework/arc is selected, each slide
  row gets a muted micro-kicker naming its beat (e.g. "HOOK", "TENSION", "PAYOFF" —
  from the arc definition), and empty slides' placeholders teach the beat ("what breaks
  the pattern here?"). The framework stops being inspector trivia and becomes the
  outline's skeleton — this is the "blueprint table" job of the room.
- Reorder + renumber with the same gutter-handle grammar as hooks.

### 4.6 The studio rail (inspector) — visual objects, app grammar

Same 280–320pt column, `DS.surface`, but every row becomes honest:

- **Swipes**: rows gain the 44×56 thumbnail via `IdeaInspirationThumb` (already walks
  the mirror→CDN fallback chain) + title + hook line. Hover lift, open-in-pane on click
  (all current behavior). The section header carries the live count.
- **Framework**: chosen state renders as a quiet card — name, match % (monospaced),
  a one-line why (from `ArcRecommendation.explanation`). Change = plain text button.
- **Blueprint**: renders as a **file object** — paper micro-preview chip + title
  (the Files-grammar object law: a proven post is a document, show it as one).
- **Research**: count + last-source line, open panel action.
- **Insight strip (new, quiet)**: when `IdeaInsight.recommendedFormat` exists, a single
  label/value row — "Suggested · Reel (87%)" with `.help(formatRationale)`. One row, not
  a dashboard; the insight earns more space only when acted on.
- **Kill every `.bordered` button** → the app's text-button / capsule grammar
  (teaching rows keep sentence + action, restyled).
- All teaching states stay — they're already correct peakui grammar.

### 4.7 Sheets → the ⌘K one-surface anatomy

Blueprint / Research / Framework sheets get the ⌘K register: near-opaque paper ground,
title in the chrome voice, hero content bleeding to ONE closing hairline, metadata as a
label/value hairline ledger, Esc affordance. Framework selection rows keep their
confidence % monospaced. (Alternatively the framework picker could become a popover from
the inspector card — decide in build; the sheet-restyle is the safe default.)

### 4.8 Motion & the one earned delight

- **Arrival cascade**: head → angle → hooks → outline rise in once
  (opacity + ~6pt, staggered, capped, Reduce Motion → fade only). Toolbar never cascades.
- **Card → page continuity** (stretch goal, Craft law): opening from Ideas home morphs
  the IdeaCard into the sheet (zoom transition). If the plumbing fights back, ship the
  existing `focusImmersiveEntryTransition` — don't spend a week here.
- **The ONE delight = Begin Writing.** Promotion is the room's whole purpose and today
  it's a spinner. Design: press → button morphs to progress state → on success the sheet
  lifts slightly and *blooms* (the Notes `PaperToneBloomPulse` pattern, entityIdea-warm)
  as the workspace hands off to Content focus. One moment, spent well. Reduce Motion:
  crossfade.
- Status ticks, hook accept, count changes: `ProMotionSprings.snappy`, explicit `value:`.

### 4.9 Manners (the Mac citizenship pass)

- Toolbar center island shows the idea's title (muted, truncating) once the title hero
  scrolls off — the Mac-native context pill (D8).
- Hover states on every hook/slide/inspector row (some exist — complete the sweep).
- `.help()` everywhere, with shortcuts named: Begin Writing (⌘↩) has one; add
  ⌘⇧L "Link swipes", ⌘⌥I inspector (exists), Esc (exists).
- New-hook fast path: ⌘⇧H focuses the draft hook row.
- Focus rings via `DS.focusRing` on all text fields; `.isSelected` on the chosen hook;
  `accessibilityLabel` sweep on the new icon-only controls (star, drag, accept/dismiss).

---

## 5. Build phases (each independently shippable)

| Phase | Scope | Files touched |
|---|---|---|
| **1. The stage** | Paper ground + vignette + test repoint; chrome recede port; toolbar title-on-scroll | `IdeaFocusModeView`, `IdeaWorkspaceToolbar`, `FocusModeAppearanceTests` |
| **2. The head** | Ripening ticks control (status menu moves in), identity meta line (client dot, format/platform marks, click-to-edit), toolbar thinning | `IdeaFocusModeView`, `IdeaWorkspaceToolbar` |
| **3. The lab** | Hooks: live count, star/pick wiring to `selectedHookIndex`, ghost AI-suggestion rows + skeleton, reorder; Outline: live count, framework beats, reorder | `IdeaFocusModeView`, `IdeaManuscriptEditors`, VM (render-side only) |
| **4. The studio rail** | Swipe thumbnails, blueprint file-object, insight strip, de-`.bordered` sweep | `IdeaInspectorView` |
| **5. The panels** | Three sheets → ⌘K one-surface anatomy | `IdeaFocusModeView` (sheet builders), possibly shared `AtelierSheetHeader` retirement |
| **6. Ceremony** | Arrival cascade; Begin Writing bloom + handoff; (stretch) card→page morph | `IdeaFocusModeView`, `IdeasHomePage` (morph only) |
| **7. Audit** | Full peakui checklist, Reduce Motion/Transparency sweep, look test | — |

Phases 1–2 alone fix "too much white space / not Apple". Phase 3 fixes "the app is
thinking but not showing it". 4–6 take it to production-feel.

---

## 6. Engineering invariants (do not violate while building)

- **NEVER remove** the `IdeaContextTextEditor` cursor guards or the
  `IdeaContextTextView.setFrameSize` floor — test-pinned, four failed fixes behind them.
- `IdeaContextProvider` stays byte-compatible (surfaceID `idea:<uuid>`, `hook-N`
  anchors) — the inline assistant depends on it. Rendering ghost hooks must not change
  the anchor scheme.
- `promoteToContent()` flow untouched — this plan changes its *ceremony*, not its logic.
- **Dark-mode paper gotcha**: `DS.documentSurface` is paper-doctrine (#FFFFFF even in
  dark). Pair it ONLY with `DS.documentText` (+ `DS.sepiaBorder` on true paper).
  Adaptive fills elsewhere use `DS.surfaceElevated` + `DS.palette.sepiaBorder`.
- `.bordered`→custom buttons: watch the repo's top-level `Configuration` type collision
  in `ButtonStyle` conformances (`ButtonStyleConfiguration` explicitly).
- New files (if any) register via `ruby scripts/add_files_to_target.rb` — Mac pbxproj is
  hand-managed (except UI/CommandK which is filesystem-synced).
- Build: `xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build`.
- Autosave choke points (`scheduleAutoSave`, merge-not-replace metadata writes) stay as-is.

## 7. Verification

- Build headless, launch, then the **look test**: Idea Focus beside ⌘K, the sidebar,
  Notes focus, and Ideas home — same glass family, same title voice, same motion
  dialect, and the IdeaCard should visibly be the page's seed.
- Sweep: Greenhouse light + Greenhouse Night (paper doctrine check), Reduce Motion,
  Reduce Transparency, pane-width (compact breakpoint) + Atom-window chrome contexts.
- Euan reviews screenshots himself — build, relaunch, and hand over.

---
---

# PART II — The Workbench Shell

> **STATUS (July 15, night): Idea bench SHIPPED.** `WorkbenchShell` lives in
> `UI/FocusMode/Shared/AtelierPrimitives.swift` (no new file — the pbxproj was
> carrying another session's uncommitted edits); the Idea bench is live in
> `IdeaFocusModeView` / `IdeaWorkspaceToolbar` / `IdeaInspectorView`
> (conversation | manuscript | swipe wall, ⌘0 / ⌘⌥I, Begin Writing as the one
> tinted island, panels on `studyPanelSurface`).
>
> **UPDATE (later that evening): Study REBASED onto `WorkbenchShell`** — its
> `workspaceSheet` is now one shell call; the displace/overlay panel builders
> collapsed to `leadingPanel/trailingPanel(isOverlay:)` keeping the
> concept-desk pivot; the local scrim deleted (the shell owns it). Zero visual
> change; build green; FocusModeAppearanceTests passing.
>
> **UPDATE (night): Swipe bench SHIPPED (§II.3) — the bench family is
> complete.** Swipe Study runs on `WorkbenchShell`: chrome band (navigate ⌘0 ·
> swipe pill with the platform glyph, studied seal, and queue position ·
> session arrows + overflow · **Use in Idea** as the one tinted island, ⌘⏎ —
> creates an idea with the swipe linked and its format/platform inherited so
> the Idea bench's recommended shelf wakes up matched), worksheet = ANALYSIS
> panel (the full insight rail on the study panel surface, leading edge) |
> hero → media stage → transcript at the reading measure. The three bespoke
> width tiers died (the shell owns displace/overlay/scrim via
> `StudyBreakpoint`); `SwipePageBackground` stays under the bench so the
> library zoom lands on the same paper; `SwipeStudyCompactHeader` deleted
> (dead). Tests repointed: two new bench-anatomy tests replace the three
> tier pins, and the stale auto-transcription pin now reads
> `SwipeStudyModel.swift` where the code actually lives. Rooms (Notes,
> Content) and benches (Study, Idea, Swipe) are now the complete taxonomy —
> one shell implementation across all three benches.

*Euan's question: should the Study/Concept-Desk anatomy (chrome band on top, one
rounded worksheet below, rails inside it) extend to Idea Focus and Swipe Study?
Verdict first, then the plan. Nothing in Part II is coded yet.*

## II.1 Verdict: yes for Idea and Swipe Study — because of a taxonomy, not taste

The app already has two window species, and naming them is what makes this one
design language instead of many:

- **Rooms** — immersive paper, chrome that recedes, nothing between you and the
  text: **Notes, Content**. You go there to *read and write*. (Idea v3's paper
  stage borrowed room language — correct for the manuscript, but the mode as a
  whole is not a room.)
- **Benches** — a dedicated navigation band up top (glass islands: navigate ·
  orientation object · actions + ONE tinted primary), and beneath it the whole
  working area clipped into ONE rounded sheet whose columns are welded by
  hairlines: **Study/Inquiry, Concept Desk** today. You go there to *work on a
  thing with instruments around it*.

Idea Focus is a bench by its own definition (this document called it "the
development bench" in §1). Swipe Study — post + transcript with an analysis
rail — is also a bench. Converting both is not "making pages look the same";
it completes a two-species system: rooms for prose, benches for work. Notes and
Content must NOT convert — that would collapse the distinction that makes both
feel intentional. End state: benches = Study, Idea, Swipe (Connection later, it
already has the 3-pane bones), rooms = Notes, Content.

## II.2 The Idea bench

- **Chrome band** (`CosmoChromeRow`, Study grammar):
  - Leading: NavigationTrailIsland + navigate island (left-panel toggle, ⌘0).
  - Center: the **idea pill** — ripening ticks + title (the orientation object,
    replacing the scrolled-title island; the serif head stays in the manuscript
    as the hero).
  - Trailing: tools island (word count vitals, inspector toggle ⌘⌥I, close) +
    **Begin Writing as the screen's ONE tinted island** (exactly Crystallize's
    role in the Study).
- **Worksheet columns**: conversation | manuscript | swipe wall.
  - **Left = the resident assistant conversation** (reuse
    `StudyConversationPanel`, bound to the idea surface). This is the "genuinely
    useful left rail": /Research (§ the ported skill), idea strategy, riffs —
    captures stage into the manuscript as reviewed diffs through the existing
    `IdeaContextProvider`. The Concept Desk already proves this exact posture
    (conversation | board | evidence); the idea bench is its sibling
    (conversation | manuscript | swipes). Off by default at narrow widths,
    remembered per user otherwise.
  - **Center**: the v3 manuscript unchanged (head, angle, hooks lab, outline) on
    its focus-paper column INSIDE the sheet; vignette retires (the sheet
    provides the framing that the vignette was simulating).
  - **Right**: the swipe wall (linked + recommended) as built today.
- **Breakpoints**: extract the Study's displace/overlay logic into a shared
  `FocusMode/Shared/WorkbenchShell` primitive (sheet + column welding + overlay
  panels + scrim) rather than copying it — Study adopts the primitive in the
  same change so there is exactly one implementation.
- **Keyboard**: ⌘0 conversation, ⌘⌥I swipe wall, Esc = panel → mode close, ⌘↩
  Begin Writing (unchanged).

## II.3 The Swipe bench (phase 2)

- **Chrome band**: navigate island · center = swipe pill (platform glyph +
  title — the orientation object) · trailing actions + ONE tinted primary
  ("Use in Idea" — creates/links an idea from this swipe; today's closest
  verb to crystallize).
- **Worksheet**: left = the insight rail (insight / structure / patterns /
  details move from right to left — instruments read before the object in the
  Study too), center = media hero + transcript (the thing being studied owns
  the center), right = none initially (the shell legally runs 1–2 panels).
- **Cost note**: several `FocusModeAppearanceTests` +
  `SidebarLayoutPolicyTests` pins encode the current stage/rail/manuscript
  order and `SwipePageBackground` — they get repointed in the same change,
  deliberately.

## II.4 Build order & estimate

1. Extract `WorkbenchShell` from `StudyShellView` (Study re-adopts it; zero
   visual change to the Study — that's the acceptance test). ~half session.
2. Idea bench on the shell (rewire v3 pieces; conversation panel binding).
   ~half–1 session.
3. Swipe bench + test repoints. ~1 session.

Ship 1+2 together; 3 separately. If review of the Idea bench changes the shell,
Swipe inherits the fix for free.
