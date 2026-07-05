# Inquiry v2 — "The Study"

Full implementation plan for rebuilding the Inquiry workspace (Deep Dive study session)
to Apple-level quality under the peakui system. July 5 2026.

**One sentence:** the workspace becomes one continuous parchment manuscript (content
layer, zero boxes) with exactly four pieces of real Liquid Glass floating above it
(chrome layer) — toolbar islands, two quiet side panels, one morphing thinking bar.

**Scope guard:** this is a **view-layer rebuild**. `InquiryWorkspaceViewModel` — the
routing brain (dock parser, live classifier, Deep Scout, receipts, persistence) — is not
touched except where a view needs a tiny new accessor. Everything shipped July 5
(LLM scout, taste store, topic-inbox trust, question delete) rides underneath unchanged.

---

## 0. Design contract (the laws this screen must pass)

1. **Two layers, strictly.** Content (question, understanding, notes, sources) never gets
   glass; chrome (toolbar, panels, thinking bar, receipts) is only glass. No opaque
   `DS.surface` rails, no full-height `Divider()`s — both are deleted concepts here.
2. **One hero.** The serif question + forming understanding. Nothing else may be
   largest/boldest. Crystallize is the one *tinted* glass element (tint = primary action).
3. **One container grammar.** Inside panels: the Files grammar (one list, hairline
   separators inset to the text column, rows never individual cards). On the page:
   spacing-as-grouping (Things 3) — no bordered sections at all.
4. **One header voice.** `SMALL-CAPS LABEL …… live count` (monospaced, `.numericText()`).
   Page title word never repeated by a section label.
5. **Concentric geometry.** Panels 22pt continuous; islands are capsules (40pt height);
   controls inside panels 14pt; inner radius = outer − inset everywhere.
6. **Springs only**, named from `ProMotionSprings`, explicit `value:`. Reduce Motion
   gates every decorative move. One earned delight: crystallization.
7. **Keyboard path for everything**; every icon control has `.help()` with the shortcut
   spelled in it; Esc walks back (reader → map → workspace → close).

Anti-goals: no new tokens unless added to both repos; no `.ultraThinMaterial`; no
scrims; no glass-on-glass except siblings in one `GlassEffectContainer`; no
`.font(.system(size:))` in new code (DS scale only — current files violate this; v2 fixes
it wholesale for this surface).

---

## 1. File architecture

New directory `UI/FocusMode/Inquiry/Study/` (a PostToolUse hook auto-registers new files
in pbxproj — never register manually):

| File | Role |
|---|---|
| `StudyShellView.swift` | Layout host: content page + floating chrome, breakpoints, keyboard shortcuts, overlays (map, crystallize sheet, receipts). Replaces the body of `InquiryWorkspaceView`. |
| `StudyChromeRow.swift` | Top chrome via `CosmoChromeRow`/`CosmoChromeIsland`: navigate island · question island · actions island. |
| `StudyPageView.swift` | The manuscript: question, understanding, counts line, threads, worth-a-look. De-boxed successor of `InquirySteleView`. |
| `StudyTrailPanel.swift` | Left glass panel (`.focusSidebar`): the capture trail in Files grammar. Successor of `InquiryNotesRail`. |
| `StudyReadingPanel.swift` | Right glass panel (`.focusSidebar`): sources + scouted candidates. Successor of `InquirySourcesRail`. |
| `StudyThinkingBar.swift` | Bottom glass instrument: rest capsule ⇄ focused panel morph (`glassEffectID`). Successor of `InquiryAssistantDock`. |
| `StudyReceiptCapsule.swift` | Transient glass capsules for routing receipts + ephemeral AI replies. Successor of `InquiryRoutingReceiptView` visuals + `InquiryEphemeralAICardsStack`. |
| `StudyBreakpoint.swift` | Width classes (mirrors `ConnectionWorkspaceBreakpoint` thresholds). |

**Edited:** `InquiryWorkspaceView.swift` becomes a ~40-line host (state
`InquiryWorkspaceViewModel` + `StudyShellView`). `InquiryReaderView` keeps its center
role but its chrome is re-skinned (§3.8). `InquiryMapOverlay` gets the materialize
treatment + "Session map" naming.

**Deleted after cutover:** `InquirySteleView.swift`, `InquiryNotesRail.swift`,
`InquirySourcesRail.swift`, `Dock/InquiryAssistantDock.swift`,
`Dock/InquiryRoutingReceiptView.swift` (visual parts), `InquiryDockView.swift` (legacy),
plus their pbxproj entries. `InquiryKindBadgeMenu` and `InquiryExtractCorrectionMenu`
survive (re-styled, reused in the trail rows).

**View model additions (only these):**
- `isTrailShowing: Bool` / `isReadingShowing: Bool` (+ persisted in
  `structured.uiState`), `toggleTrail()` / `toggleReading()`.
- `dockFocusTick: Int` (drive `@FocusState` from shortcuts, the `searchFocusTick`
  pattern).
- No other VM changes.

---

## 2. Layout spec (StudyShellView)

```
ZStack {                                    // one ZStack, no VStack shell
  content layer:
    StudyPageView (ScrollView, full-bleed)  // .filmGrain(), DS.bg behind
      .scrollEdgeEffectStyle(.soft, for: .all)
      horizontal content insets reserve panel gutters at .regular
  chrome layer:
    StudyChromeRow            → top, CosmoChromeMetrics baseline (top 10, sides 16)
    StudyTrailPanel           → leading, top 66, bottom 96, leading 16, width 300
    StudyReadingPanel         → trailing, same verticals, width 300
    StudyThinkingBar          → bottom center, bottom 16, maxWidth 720
    receipts stack            → bottom center, above the bar (bottom 76)
  overlays:
    InquiryMapOverlay (⌘M), toasts, crystallize sheet (existing)
}
```

- Panels are **inset floating shapes** — 16pt from window edges, 22pt continuous
  corners, `cosmoGlassPanel(role: .focusSidebar)`. The page shows through around them.
  Full-height dividers cease to exist.
- The page's reading column: `maxWidth: 680`, centered **on the true page axis** at
  `.regular` (ghost-flank technique from `DeepDiveOverviewView.dossierLayout` — the
  column centers between the panels' inner edges, not the window).
- Panel show/hide: `.transition(.move(edge:).combined(with: .opacity))` on
  `ProMotionSprings.focusTransition`; the page column re-centers with the same spring
  (one animation driver — the focus-transition invariant).

**Breakpoints** (`StudyBreakpoint(width:)`, resolved once in a top-level
`GeometryReader`, passed down):
- `.regular` ≥ 1180: both panels visible by default.
- `.compact` 760–1180: panels default hidden; toggling one slides it **over** the page
  (page doesn't re-center); opening one closes the other.
- `.narrow` < 760: islands collapse to icons; panels are full-height overlays with a
  tap-outside scrim of `Color.black.opacity(0.10)` (light enough to keep glass alive).

---

## 3. Region specifications

### 3.1 Top chrome — three islands (StudyChromeRow)

`CosmoChromeRow` with `recede: true` islands (they quiet to 60% while typing in the
thinking bar or reader — the "disappear" law; wake on hover).

- **Navigate island (leading):** back chevron (`Back (Esc)`) · trail toggle
  (`sidebar.left`, `Hide trail (⌘0)`, `isActive` bound).
- **Question island (center, the orientation pill):** `questionmark.bubble` glyph in
  `DS.accent` · question title `DS.buttonText` semibold, lineLimit 1, maxWidth 380 ·
  muted chevron. Tap = the existing question `Menu` (switch/pin/status). Below it **no
  breadcrumb line** — the breadcrumb ("Self-Improvement › …") moves into the menu's
  header row; the island stays one line tall. Subtitle state lives in the menu, not the
  chrome (duplicate-information law).
- **Actions island (trailing):** session-map toggle (`circle.hexagongrid`, help
  "Session map — this session's question tree (⌘M)") · reading toggle (`sidebar.right`,
  `⌘⌥I`) · **Crystallize**: `sparkles` + label, `glassEffect(.regular.tint(DS.accent.opacity(0.35)).interactive(), in: .capsule)`
  — the screen's only tinted glass, `⌘⏎`. At `.narrow` the label drops, tint stays.

All buttons via one `toolbarButton(icon:help:isActive:action:)` factory (28×28 glyph,
`DS.textSecondary → DS.text` active, accessibility labels).

### 3.2 The manuscript page (StudyPageView)

Vertical rhythm on the 8pt grid, one column, generous top inset (76 under the islands):

1. **Question** — `DS.displaySerif`-class serif (~30pt regular), `DS.text`,
   lineSpacing 4. It IS the page title; nothing frames it.
2. **UNDERSTANDING** header — the one header voice; trailing side: forming pulse dot
   (existing) or hover-revealed regenerate glyph. 20pt below the question.
3. **Understanding body** — serif `DS.body`-scale, `DS.text.opacity(0.88)`,
   lineSpacing 5. Directly on the page. Placeholder (teaching voice): "Think out loud
   below — every thought gets typed, routed, and kept."
4. **Counts line** — one row of `n claims · n notes · n sources · n branches`,
   `DS.caption` + `.monospacedDigit()` + `.numericText()` ticking, `DS.textMuted`;
   values in their existing semantic colors at 100% but at caption size they read as
   punctuation, not decoration.
5. **THREADS** (only when content exists) — header voice with live count; rows are
   **plain lines** (glyph 18pt column · title `DS.body` · muted trailing count/action),
   8pt vertical padding, NO container: hover = `DS.surfaceElevated.opacity(0.5)` wash on
   the row's own 10pt-radius shape. Branch proposals italic serif with quiet
   `Branch` / `xmark` affordances (existing actions).
6. **WORTH A LOOK** — same grammar; judge-reason as muted second line; import on click,
   `arrow.down.circle` revealed on hover only. Rows monochrome; no accent at rest.
7. Bottom spacer ≥ 140 so the last line clears the thinking bar.

Empty page = items 1 + 2 + 3-placeholder only. The panels and bar frame the emptiness
as a fresh sheet, which is the design.

### 3.3 Trail panel (left, StudyTrailPanel)

`cosmoGlassPanel(role: .focusSidebar, cornerRadius: 22)`, width 300. Inside — flat warm
fills only (glass cannot sample glass):

- **Header row** (pinned, flat `DS.glassSectionFill` ramp — never new glass):
  `TRAIL …… 6` in the header voice. The count is the live extract count.
- **Body:** ONE `ScrollView` + `LazyVStack(spacing: 0)`, `.scrollEdgeEffectStyle(.soft)`.
  Question groups: tinted small-caps subheader (question title, active = `DS.accent`
  dot) then rows with hairline separators **inset to the text column** (leading 40).
- **Row anatomy** (`StudyTrailRow`): kind glyph (16pt, semantic tint at 70%) · body
  `DS.callout` lineLimit 3 · footer `time · kind` in `DS.caption` `DS.textMuted`.
  NO card, NO stroke, NO background at rest. Hover: row wash + reveal of the kind-badge
  menu (existing `InquiryKindBadgeMenu`). Provisional = existing pulse dot + 0.62
  opacity; crystallized = tiny `diamond.fill` in the footer. Context menu unchanged.
- **Teaching state:** "Notes you route to this question land here." as a quiet row in
  the same grammar (never centered art).
- New captures enter with `.transition(.opacity.combined(with: .move(edge: .top)))` on
  `ProMotionSprings.gentle` — unchanged behavior, calmer chrome.

### 3.4 Reading panel (right, StudyReadingPanel)

Same shell as 3.3. Header: `READING …… n` + the rescout refresh glyph (existing
behavior; spins while scouting).

- Sections in the one voice: `ADDED BY YOU n`, then scouted candidates grouped by lane
  (`LECTURE n`, `BOOKS n`, …). All rows in one list, separators inset.
- **Source row:** favicon-slot glyph · title `DS.callout` 2 lines · `domain · n notes`
  muted. Open = click anywhere.
- **Candidate row:** lane glyph · title · judge-reason (muted, italic-free) ·
  hover-revealed import affordance. Monochrome until hover.
- **Scout status:** while running, the existing per-provider progress list renders as a
  flat footer section (`DS.glassSectionFill`), not a bordered box; the activity line
  becomes the READING header's detail slot ("scouting…" replaces the count while live —
  counts return and tick up when done).

### 3.5 The thinking bar (StudyThinkingBar) — the instrument

One `GlassEffectContainer` + `@Namespace`; both states share
`glassID: "study-dock"` so the **glass itself morphs** (Command-K pattern).

- **Rest** (unfocused, empty): capsule, height 52, maxWidth 640. Anatomy:
  `sparkle.magnifyingglass` in `DS.accent` · placeholder "Think out loud, paste a URL,
  or type / for commands" · trailing scope chip — flat wash capsule
  (`DS.accentSoft` fill, `DS.accent` hairline): `→ {question, truncated 24ch}`. The
  scope chip replaces the "Saving to" caption row — scope lives *inside* the instrument.
- **Focused / has draft:** morphs to cornerRadius 24, maxWidth 720, and grows a
  **footer row inside the same glass**: flat vibrant text actions with taught shortcuts,
  Raycast-style —
  `Summarize ⌘⇧1 · Challenge ⌘⇧2 · Branch ⌘⇧3 · Scout ⌘⇧4` (`DS.footnote`,
  `DS.textSecondary`, hover → `DS.text`; separated by interpuncts, not chips — zero
  inner containers). Existing slash-suggestion popover keeps its logic, re-skinned as a
  small `.floatingAssistant` panel floating above the bar.
- Send affordance: `arrow.up` circle, `DS.accent` fill when non-empty (unchanged logic).
- While `aiBusy`: thinking shimmer replaces the send glyph, never a modal state.
- **Never** `matchedGeometryEffect` + `glassEffectID` on the same node; if the 120Hz
  morph hitches on target hardware, drop the IDs and keep container + frame springs
  (the documented fallback).

### 3.6 Receipts & ephemeral replies (StudyReceiptCapsule)

Routing receipts and ephemeral AI cards unify into one transient voice: small
`.floatingAssistant` glass capsules (cornerRadius 18, maxWidth 560) stacked above the
bar, newest at bottom. Anatomy: kind glyph · one-line headline · destination chip
(existing tap-to-correct menus preserved). Materialize in, fade at their existing
lifetimes. Max 2 visible (existing cap). AI replies that exceed two lines get
`Show more` expanding the capsule in place (spring, same glass).

### 3.7 Session map overlay

Rename everywhere user-facing: **Session map** (tooltip "Session map — this session's
question tree (⌘M)"). Presentation: dim the page 8%, panel materializes via
`.glassEffectTransition(.materialize)` as a centered `.floatingAssistant` panel. Content
(existing `InquiryMapOverlay` guts) unchanged. Esc closes.

### 3.8 Reader morph (center source reading)

When `activeReaderSourceId` is set, the page column cross-fades to the reader
(existing morph). v2 change: reader chrome (title bar, close, extract mini-menu)
adopts the island grammar — one small floating capsule top-center of the column
("‹ Back to study · {source title}") instead of the current full-width header. Islands
recede while text is selected.

---

## 4. Motion choreography (master table)

| Moment | Spring | Spec |
|---|---|---|
| Arrival | `gentle` staggered | Chrome is present from frame one (never cascades). Page assembles: question → understanding → counts → threads → worth-a-look, `.cascadeIn`-equivalent (opacity + 6pt rise, 0.06 stagger, cap 8), flag flipped one frame **after** `loadDeepDiveAndRoot()` lands. Panels materialize (glass transition), bar last. Once per session open. |
| Panel toggle | `focusTransition` | `.move(edge:) + .opacity`; page re-centers same beat. |
| Question switch | `focusTransition` | Page content cross-fades (`.opacity`), counts tick via `.numericText()` — layout never jumps. Trail regroups with `gentle`. |
| Capture saved | `gentle` | Row enters trail from top; receipt capsule materializes; counts tick. |
| Dock morph | `focusTransition` | Glass morph rest ⇄ focused (§3.5). |
| Hover | `hover` | Rows: wash + 1.0→1.0 (no scale on text rows). Islands/cards: lift −1pt. Press: 0.97. |
| Crystallize (the one delight) | custom, once | On promote-success: review sheet's accepted cards condense toward the Crystallize island (scale 0.9 + opacity), the island's tint flares once (`DS.gilt` shimmer ~400ms), concept count in the trail ticks up. Reduce Motion: cross-fade only. |
| Reduce Motion | — | Cascade → plain fade; morphs → cross-fade; shimmer/pulse off. |

---

## 5. Keyboard map (single source in StudyShellView)

| Key | Action |
|---|---|
| Esc | reader → map → close workspace (existing walk-back, kept) |
| ⌘⏎ | Crystallize |
| ⌘M | Session map |
| ⌘0 | Trail panel |
| ⌘⌥I | Reading panel |
| ⌘K | Focus thinking bar (`dockFocusTick += 1`) |
| ⌘[ / ⌘] | Parent question / cycle questions (existing) |
| ⌘⇧1…4 | Summarize / Challenge / Branch / Scout (the taught footer actions) |

Remove: ⌘1/⌘2 phase shortcuts (phase toggle is dead).

---

## 6. States matrix

| State | Treatment |
|---|---|
| Fresh question (0 everything) | §3.2 empty page; trail/reading teaching rows; bar at rest with scope chip. |
| Scout running | READING header detail = activity line; provider list as flat footer; refresh glyph spins. |
| Scout failed / offline | Teaching row in READING: "Scout couldn't reach its sources — check the connection and press ↻." |
| Classifier pending | Existing pulse-dot rows (unchanged). |
| Long understanding | Page scrolls; islands recede on scroll-down, wake on scroll-up/hover. |
| Crystallize with no material | Existing teaching state inside the sheet (kept from today's redesign). |
| Reduce Transparency | Native glass frosts itself — zero hand-rolled fallbacks (audit only). |

---

## 7. Implementation phases

**Phase A — Shell & chrome (the transformation).**
`StudyShellView`, `StudyChromeRow`, `StudyBreakpoint`; gut `InquiryWorkspaceView` to a
host; panels mounted with current rail *contents* temporarily inside the new glass
shells; keyboard map moved; dividers deleted.
*Accept:* zero full-height lines; page scrolls under floating chrome; both panels
toggle and persist; side-by-side with the Connection workspace reads as one family.

**Phase B — The manuscript page.**
`StudyPageView` replaces `InquirySteleView` (delete after): de-boxed hero, header
voice, spacing-grouped threads/worth-a-look, cascade with one-frame rule, film grain.
*Accept:* no rectangles on the page; one hero at first glance; counts tick without
layout shift; empty state reads as fresh paper.

**Phase C — Panels' Files grammar.**
`StudyTrailPanel` / `StudyReadingPanel` replace the rails (delete after): one list per
panel, inset separators, monochrome rows, hover reveals, pinned flat headers, teaching
states, scout-status-in-header.
*Accept:* zero per-row cards/strokes; kind-correction + context menus intact; live
counts; candidate import works from panel and page.

**Phase D — The instrument.**
`StudyThinkingBar` + `StudyReceiptCapsule` replace dock + receipt visuals (delete
after): glass morph, in-glass scope chip, taught footer actions (⌘⇧1–4 wired),
suggestion popover re-skin, receipts unified.
*Accept:* one glass shape at rest, zero nested containers; morph at 120Hz or fallback
engaged; every dock command (`/prefixes`, URLs, plain thoughts) behaves identically.

**Phase E — Map, reader, delight, sweep.**
Session-map rename + materialize; reader island chrome; crystallize delight; then the
five peakui passes as an explicit audit (hierarchy, material, surface, motion,
manners), Reduce Motion/Transparency sweep, `.help()` + accessibility audit, DS-token
sweep (kill every `.font(.system(size:))` this surface still carries).
*Accept:* the audit checklist in the skill passes line by line.

**Phase F — Verification.**
`xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build`;
`swift test --filter Inquiry --filter DeepScout --filter TopicInbox`; manual script —
open a rich session and a fresh session; screenshot: arrival, panels hidden, dock
focused, scout running, reader open, map, crystallize flow; compare against Command-K
and the Connection workspace (the family test); then a real study session dogfood.

Estimated: A+B ≈ half day (the visible transformation), C+D ≈ half day, E+F ≈ 2–3 h.

---

## 8. Risks & invariants

- **Do not touch the routing brain.** `submitDockText`, the classifier queue, receipts
  data, persistence, and Deep Scout stay byte-identical; only their clothes change.
- **120fps law:** panels/page must not re-enter heavy bodies on scroll — keep rows
  `Equatable`-friendly, `LazyVStack`, no `GeometryReader` sprinkled in rows (one at the
  shell top for breakpoints).
- **Glass economics:** 4 glass surfaces + transient capsules is the ceiling. The
  suggestion popover and receipts are `.floatingAssistant` but short-lived; if GPU cost
  shows on Intel-era hardware paths, receipts drop to warm-fill cards (they sit above
  the bar's glass — flat is also the *correct* material there; decide in Phase D).
- **State persistence:** panel visibility + last layout live in `structured.uiState`
  (existing save pipeline) so a session reopens the way it was left.
- **pbxproj:** the hook registers new files; deletions must strip all 4 entry types
  (learned July 5 — see memory).
- **Cutover discipline:** each phase deletes what it replaces in the same PR-sized
  change — no two grammars coexisting on the shipped screen between phases (the old
  view stays only as uncommitted reference, never compiled in).
