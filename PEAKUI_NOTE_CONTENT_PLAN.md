# Note & Content Focus Modes — peakui Polish Plan

> Produced with the `peakui` skill (.claude/skills/peakui/). Goal: bring both writing
> surfaces up to the bar Command-K, the sidebar, and the Connection workspace now set —
> same glass family, same motion dialect, zero regressions to what already works.

## The audit (peakui five-pass)

Both modes have **excellent bones** — Note's three-rail reading room
([NoteFocusModeView.swift](UI/FocusMode/Notes/NoteFocusModeView.swift): outline rail 208 ·
measured center column · carrel rail 272, ⌘G graph, typewriter) and Content's scriptorium
([ContentFocusModeView.swift](UI/FocusMode/Content/ContentFocusModeView.swift): pinned
marginalia · manuscript column · zen mode · focus band · roman-numeral step ledger · XP
moment). The plan polishes; it does not restructure.

What fails the audit today:

1. **Material (the big one).** Neither surface has any Liquid Glass. Note's top bar is a
   full-width gradient wash (`topBarBackground`, NoteFocusModeView:686); Content's header
   is a bare HStack (scriptoriumHeader:905). Next to the Connection toolbar they read as a
   different, older app — the "final look test" fails.
2. **Chrome voice violations.** Content's back button is *italic serif* ("back",
   :930-932) — serif is for content, never chrome (Law 7). Both files carry
   `.font(.system(size: 11…))` literals and `foregroundColor` (9 Content files + Notes).
3. **No scroll-edge treatment** — content hard-clips at the top instead of softening
   under chrome.
4. **Missed invisibility wins** — Content already tracks `isActivelyTyping` but chrome
   doesn't recede while writing; Note has no recede at all. This is the single biggest
   "pro writing app" signal (iA law, craft.md).
5. **Motion dialect drift** — easeOut entrances in Content (:399-405), opacity+scale
   overlay pops in Note instead of glass materialize/morphs.

What we deliberately do **not** touch: the manuscript column and marginalia stay paper
(content layer — glass is for chrome only); the roman-numeral step ledger stays (it's the
surface's editorial signature — refine, don't genericize); zen/typewriter/focus-band
behavior unchanged.

---

## Phase 1 — Floating glass toolbars (both modes)

Port the Connection toolbar anatomy (peakui recipes §2) — one glass shape, flat controls
inside, center-weighted hierarchy.

**Note** (`topBar`, NoteFocusModeView:558-692):
- Replace the full-width gradient bar with a floating
  `.cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 22)` toolbar inset from the
  edges: leading = back chevron + NOTE badge (badge keeps its entity tint capsule);
  trailing = graph / panels / typewriter / close via the shared 28pt
  `toolbarButton(icon:help:isActive:)` factory; save badge becomes a quiet trailing dot
  that morphs (`contentTransition(.opacity)`), not a popping capsule.
- Delete `topBarBackground` gradient; add `.scrollEdgeEffectStyle(.soft, for: .top)` to
  `centerColumn`'s ScrollView so the manuscript softens under the floating bar.

**Content** (`scriptoriumHeader`, :905-971):
- Same treatment: leading sidebar-toggle + back (sans `DS.callout`, not serif italic);
  center stays empty (the title hero below is this surface's hero — Law 2); trailing =
  writing-surface controls + ZenOrnament.
- **Zen morph:** entering zen, the glass toolbar *dematerializes* (free via
  `glassEffectTransition(.materialize)`) leaving only the ZenOrnament floating — instead
  of today's opacity toggles per button.

## Phase 2 — Chrome that recedes while you write

- Content: when `isActivelyTyping` (:129 already tracked), fade the toolbar to ~0.25
  opacity with `ProMotionSprings.gentle`; restore on mouse movement or hover. Marginalia
  rails already dim via `sideRailOpacity` — align the curves so chrome breathes as one.
- Note: add the same recede using its editor activity (typewriter mode infrastructure,
  :2326 area). Result: full chrome on intent, paper while writing.

## Phase 3 — Note-specific

1. **Rails become glass.** `outlineRail` + `carrelRail` are navigation chrome → wrap in
   `.cosmoGlassPanel(role: .focusSidebar, cornerRadius: 22)` (quieter tint, built for
   exactly this), keep `.move + .opacity` transitions on `focusTransition`.
2. **Graph overlay** (⌘G, :2201+): back the overlay chrome with `cosmoGlassPanel`
   (`floatingAssistant`) and let it materialize instead of `.scale(0.98)` popping; its
   `graphTopBar` adopts the toolbar factory.
3. **Focus ring**: any focused-field stroke → `DS.focusRing`.
4. **Empty state** already guides title-first — give it teaching copy per recipes §10
   ("Name it, then just write — ⌘\\ opens your outline.").

## Phase 4 — Content-specific

1. **Step ledger refined** (:1110-1152): keep numerals + labels; make the gilt diamond
   *travel* between steps with `matchedGeometryEffect`; add ⌘1/⌘2 + `.help("Draft (⌘1)")`;
   replace the `.font(.system(size: 13, monospaced))` literal with a DS token.
2. **Inline AI popover + Writing AI card** (:719-741): back with
   `cosmoGlassPanel(role: .floatingAssistant)`, morph in with `ProMotionSprings.bouncy`
   from the selection anchor — the element lifts out of the page (recipes §5 spirit).
3. **Manuscript scroller**: `.scrollEdgeEffectStyle(.soft, for: .vertical)`; keep
   `PremiumManuscriptScrollbar`.
4. **Marginalia typography pass** (no glass): consistent `DS.smallCaps` section labels,
   `.monospacedDigit()` on counts, hairline `DS.glassBorder` separators only where spacing
   can't do the job.
5. **PostCreationPhaseView / ContentPipelineBar**: adopt the same toolbar factory + DS
   type tokens so phases 5–8 speak the same dialect as the scriptorium.
6. **The earned delight stays singular**: the gilt XP serif moment (:352-365) is this
   surface's one reward — don't add others; tighten its spring (`cardEntrance` in,
   gentle out) so it lands softly instead of easing.

## Phase 5 — Hygiene sweep (both)

- `foregroundColor` → `foregroundStyle`: Notes (1 hit) + 9 Content files.
- `.font(.system(size:))` literals → DS scale (11pt chrome glyphs → `DS.caption`-family
  weights; 13pt mono → token).
- Serif in chrome → sans (`DS.callout`); serif stays on manuscript titles and the XP
  moment (content/editorial — sanctioned).
- State-driven easeOuts → named springs; keep the continuation cross-fade (:397-406) —
  it's intentional choreography.

## Verification

1. `xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build`
   after each phase.
2. Open a note and a content draft side-by-side with the Connection workspace: one glass
   family, one title voice, one motion dialect.
3. Type in both — chrome recedes; move the mouse — it returns. Zen in/out morphs.
4. ⌘G, ⌘\\, ⌘1/⌘2, Esc all work; tooltips name their shortcuts.
5. Reduce Motion + Reduce Transparency; 120Hz scroll with rails open; no hitches.

**Order:** 1 → 2 ship together (the visible leap), then 3 and 4 in parallel, 5 rides
along per-file as each is touched.
