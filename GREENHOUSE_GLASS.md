# Greenhouse Glass — The CosmoOS Polish Spec

> ⚠️ **Superseded (June 2026): use the `peakui` skill instead** (`.claude/skills/peakui/`).
> peakui is the maintained, current version of this language — updated for the native
> macOS 26 Liquid Glass migration. Known-stale content below: the scene-signal API (§2,
> §7.2) was **deleted**; `CosmoGlassPanel` no longer takes `sceneTint`/`sceneMaterial`;
> §9's macOS 15 fallback guidance no longer applies (the app is macOS 26-only and native
> glass is the foundation, not an enhancement).

> Apple's Liquid Glass discipline, expressed in CosmoOS's warm materiality.
> This is the design language distilled from the SwipeFile **Discover** and **Creators**
> redesign. Apply it to any page and it will feel like a first‑party Apple app that is
> unmistakably *this* app.

This document is **prescriptive and copy‑pasteable**. Every token, modifier, and spring
named here exists in the codebase (`Core/DesignSystem.swift`, `Core/Theme.swift`,
`Core/Components/CosmoGlassPanel.swift`). Don't invent new ones — compose these.

---

## 0. The one‑paragraph philosophy

Content is the hero; chrome is glass that floats above it and gets out of the way. Surfaces
are **warm** (parchment + forest, never cool grey frost). Depth comes from soft layered
shadows, hairline specular borders, and a faint content‑adaptive tint — not from heavy
fills or borders. Motion is a spring, never a fade‑and‑slide, and it always *means*
something (this appeared, this lifted, this was selected). Accent green is punctuation, not
wallpaper. Everything honors Reduce Motion and Reduce Transparency. The result reads calm,
deliberate, and expensive.

---

## 1. The five prime directives (read these every time)

1. **Defer to content.** Chrome is translucent and quiet. If a panel competes with the
   content behind it, lower its opacity or remove a border before you add one.
2. **One hero per screen.** Exactly one element is the largest, boldest, most saturated
   thing. Everything else steps down in a clear hierarchy. Ambiguous hierarchy = amateur.
3. **Depth, not weight.** Separation comes from shadow + hairline + a 6–10% tint wash —
   never from a thick stroke or a dark fill.
4. **Motion with meaning.** Springs only (`ProMotionSprings.*`). Entrance = appear,
   hover = lift, tap = press, select = snap. No decorative animation.
5. **Restraint with accent.** `DS.accent` (#2D6A4F) is for the single most important
   affordance and for selection. If two greens are fighting, you've used one too many.

> **The Apple test:** put your screen side‑by‑side with the Command‑K palette and the
> sidebar. It must read as the *same material family*. If it looks like a different app,
> it's wrong — fix the material before anything else.

---

## 2. Liquid Glass → CosmoOS primitive (the mapping)

| Apple Liquid Glass principle | Use this CosmoOS primitive | Source |
|---|---|---|
| Floating translucent surface (chrome) | `CosmoGlassPanel(sceneMaterial: .neutral, role: .globalSidebar/.focusSidebar/.floatingAssistant, cornerRadius:)` | `CosmoGlassPanel.swift` |
| Floating translucent surface (card) | `.dsGlassCard(cornerRadius:)` or the `swipeGlassCard` recipe (§5.1) | `DesignSystem.swift:1045` |
| Input / search field | `.dsGlassInput(isFocused:cornerRadius:)` | `DesignSystem.swift:1055` |
| Quiet grouping container | `.dsGlassSection(cornerRadius:)` | `DesignSystem.swift:1071` |
| Content‑adaptive tint ("lensing") | tint wash `tint.opacity(0.06→0.10)` under the fill (§5.1); or `.cosmoGlassSceneSignal(…)` **only inside a CosmoGlassPanel** (§7.2) | `CosmoGlassPanel.swift:177` |
| Depth / specular edge | `.dsRestingShadow()` → `.dsHoverShadow()` on hover; `.dsFloatingShadow()` for overlays; hairline `DS.glassBorder` → `DS.glassBorderFocused` | `DesignSystem.swift:1017–1037` |
| Warm materiality (brand signature) | `DS.glassCardFill / glassInputFill / glassSectionFill`, `DS.vellum`, `DS.sepiaBorder` — **never `.regularMaterial`/`.ultraThinMaterial` for cards** | `DesignSystem.swift:469–484` |
| Motion | `ProMotionSprings.*` (§6) | `Theme.swift:386–494` |
| Typography | `DS` type scale only (§4) | `DesignSystem.swift:647–693` |
| Accent restraint | `DS.accent` punctuation, `DS.accentSoft` selection fills, `DS.gilt` rare ornament | `DesignSystem.swift` |
| Identity / brand color | tiny platform/entity badge only; all other chrome is warm `DS` | §5.6 |
| Atmosphere | `.filmGrain()` behind glass on hero surfaces | `FilmGrainOverlay.swift:93` |

---

## 3. Foundations — color & materiality

**Warm base (the canvas):** `DS.bg` (#F8F7F4 parchment) → `DS.surface` → `DS.surfaceElevated`
→ `DS.surfaceCard`. Pages start on `DS.bg`. Optional `.filmGrain()` behind the glass for
hero surfaces (Discover feed, canvas, sanctuary).

**Glass layer (the chrome):**

| Token | Use |
|---|---|
| `DS.glassCardFill` | card / panel fill on a material |
| `DS.glassInputFill` / `DS.glassInputFillFocused` | inputs, chips (rest / focus) |
| `DS.glassSectionFill` | quiet grouping, skeleton placeholder bars |
| `DS.glassBorder` / `DS.glassBorderFocused` | hairline edge (0.5pt rest → 1pt focus) |

**Text:** `DS.text` (primary) → `DS.textSecondary` → `DS.textMuted`. On accent fills use
`DS.textOnAccent`. Muted secondary text is *the mechanism that makes primary text read* —
use it generously.

**Accent & selection:** `DS.accent` for the hero affordance; `DS.accentSoft` as the
selected‑state fill; `DS.gilt` for rare ornament only.

**Entity tints (for lensing washes & category color):** use these instead of raw hex.

| Token | Hex | Conventional meaning |
|---|---|---|
| `DS.entityResearch` | #4A8B72 | research / sources |
| `DS.entityIdea` | #6B6EA8 | ideas |
| `DS.entityContent` | #5B84B0 | content / drafts |
| `DS.entityConnection` | #8B6BAB | connections |
| `DS.entitySwipe` | #B08C5A | swipes |
| `DS.entityNote` · `DS.entityTask` · `DS.entityImage` | #9B8A6E · #B06B6B · #5A9BA0 | notes · tasks · media |

**The single sanctioned hex exception:** external *platform brand* color, and only on a
tiny badge (§5.6). Instagram/YouTube/etc. brand identity can't map to a Greenhouse token;
everything else on the card stays warm `DS`.

**Radius scale:** `radiusXSmall 4` · `radiusSmall 8` · `radiusMedium 12` · `radiusLarge 16`
· `radiusFull 9999`. Cards use **14**, chips/inputs use **continuous capsule or 14–18**,
floating panels use **22–24**. Always `clipShape(.rect(cornerRadius:))` or a
`RoundedRectangle(style: .continuous)` — never `.cornerRadius()`.

---

## 4. Foundations — typography

Use the `DS` scale **only**. Zero `.font(.system(size:))` in views.

| Token | Spec | Use |
|---|---|---|
| `DS.display` | 32 bold | hero number / splash |
| `DS.displaySerif` · `DS.spaceTitleSerif` | 32 light / 21 reg, **serif (New York)** | editorial/reading‑content display & deliberate accents (dates, Sanctuary) **only** — never chrome, nav, or page titles |
| `DS.pageTitle` | 28 semibold | **every** surface masthead / page title (the chrome voice) |
| `DS.title1` / `DS.title2` | 22 / 18 semibold | section headers |
| `DS.title3` | 15 medium | sub‑section |
| `DS.headline` | 15 semibold | card title / emphasized line |
| `DS.body` | 15 regular | reading text |
| `DS.callout` | 13 regular | subtitles, secondary |
| `DS.subheadline` | 12 regular | metadata, captions‑with‑weight |
| `DS.footnote` / `DS.caption` / `DS.caption2` | 11 reg / 11 med / 10 reg | chips, counts, fine print |

**Sans for chrome, serif for reading content** — Apple's single most‑enforced type rule, and
the one that makes separate surfaces read as *one app*. SF Pro (`DS.pageTitle` and the rest of
the scale) is the voice of *chrome*: every page masthead, nav title, section header, and
control. New York serif (`DS.displaySerif` / `DS.spaceTitleSerif`) is reserved for *content you
read* and deliberate editorial accents — Sanctuary display moments, a date ornament, a splash —
**never** a navigation or page title. A light serif title sitting beside a bold sans title on
the next surface is the "two different apps" smell; cross‑surface title consistency is the
whole game, so **every surface masthead uses `DS.pageTitle`** (Command Center "Today" matches
Discover, matches Reminders). Light weights are only ever for giant display *numerals* (clock,
timer, rings) — never word titles. Use weight as a tool (`DS.callout.weight(.semibold)`). Counts
and metrics get `.monospacedDigit()` so they don't jitter. Section labels are
`DS.subheadline`/`DS.caption` in `DS.textSecondary` — never a title size.

---

## 5. The component recipes (what we built — reuse verbatim)

### 5.1 The Glass Card — the workhorse

Anatomy:

```
┌───────────────────────────┐  ← clipShape(.rect(cornerRadius: 14))
│ ▣ media          ⌄ badge  │  ← tiny platform badge (§5.6), topLeading
│                           │
│ ⬤ Creator   @handle       │  ← DS.callout.weight(.bold) + DS.subheadline/textMuted
│ Hook line that wraps to   │  ← DS.headline, lineLimit(4)  ← the hero line
│ about four lines max…     │
│ ◉ 24k  ♥ 1.2k  💬 88   +  │  ← DS.subheadline/textMuted metrics · 32pt add button
└───────────────────────────┘
   fill: tint wash 6→10% · DS.glassCardFill · hairline border · resting→hover shadow
```

The reusable chrome (shipped as `swipeGlassCard` in `SwipeFileHomeView.swift`; **promote to
a shared `GlassCard` modifier when you reuse it on a second screen**):

```swift
struct GlassCardModifier: ViewModifier {
    var isHovered: Bool = false
    var tint: Color = DS.accent          // entity or platform tint for the lensing wash
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(tint.opacity(isHovered ? 0.10 : 0.06), in: shape)  // lensing wash
            .background(DS.glassCardFill, in: shape)                       // warm glass
            .overlay(shape.strokeBorder(
                isHovered ? DS.glassBorderFocused : DS.glassBorder,
                lineWidth: isHovered ? 1 : 0.5))                           // specular edge
            .clipShape(shape)
    }
}
```

Apply motion at the **call site**, not in the modifier (keeps it usable for static
skeletons/previews):

```swift
content
    .glassCard(isHovered: isHovered, tint: entityTint)
    .modifier(CardShadow(isHovered: isHovered))   // resting → hover lift, see §7.1
    .scaleEffect(isHovered ? 1.01 : 1)            // a *whisper* of lift, not 1.05
    .animation(ProMotionSprings.hover, value: isHovered)
    .opacity(hasAppeared || reduceMotion ? 1 : 0) // entrance
    .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.96)
    .onHover { isHovered = $0 }
    .onAppear(perform: animateEntrance)           // cascade, see §6
```

**Do:** 1.01 hover scale, 6→10% tint wash, hairline that thickens on focus.
**Don't:** drop‑shadow heavier than `dsHoverShadow`, scale past ~1.02, or tint past ~12%.

### 5.2 Glass header + search

Title `DS.pageTitle` (bold sans — the chrome voice; **never** a serif page title, see §4) +
one `DS.callout`/`textSecondary` subtitle. Search is
`.dsGlassInput(isFocused: searchFocused, cornerRadius: 14)` with
`.animation(ProMotionSprings.gentle, value: searchFocused)`. Wrap the bar in a
`CosmoGlassPanel` only if it needs to float over scrolling content.

### 5.3 Glass chips (filter / segment)

Resting = `DS.glassInputFill` + `DS.glassBorder`. Hovered = `DS.glassInputFillFocused`.
**Selected = `tint.opacity(0.14→0.22)` fill + `tint.opacity(0.42)` border** (or `DS.accentSoft`
+ `DS.accent` hairline for the primary segment). Animate `isSelected` with
`ProMotionSprings.snappy`, `isHovered` with `ProMotionSprings.hover`. Height 32, font
`DS.footnote.weight(.semibold)`. Always add
`.accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)`.

### 5.4 Glass icon button (44pt)

A 36pt glass circle inside a 44pt hit frame:

```swift
Button(action: …) { Image(systemName: …).font(DS.callout.weight(.semibold))
    .foregroundStyle(DS.text) }
    .dsGlassInput(cornerRadius: 18)
    .frame(width: 44, height: 44)            // 44pt touch target, non‑negotiable
    .contentShape(Circle())
    .accessibilityLabel("…")                 // icon‑only → label required
// primary actions on macOS also get .keyboardShortcut(…)
```

### 5.5 Floating panels & overlays (dropdowns, detail modals, inspectors)

Back with `CosmoGlassPanel(sceneMaterial: .neutral, role: .floatingAssistant, cornerRadius: 22)`
+ `.dsFloatingShadow()`. Scrim = blurred backdrop (see `FloatingOverlayBackdrop` /
`CortexOverlayBackdrop` in `FloatingOverlayChrome.swift`) with tap‑to‑close. The panel
**morphs in from its trigger** with `ProMotionSprings.bouncy` so it reads as the element
lifting out of the page, not a generic sheet. Reuse `FloatingOverlayCloseButton` for the
28×28 close affordance.

### 5.6 The tiny platform badge (the only brand‑color moment)

20pt circle, brand color, white glyph, faint ring + drop shadow, on the media corner:

```swift
Image(systemName: platform.iconName)
    .font(DS.caption.weight(.bold)).foregroundStyle(DS.textOnAccent)
    .frame(width: 20, height: 20)
    .background(platform.badgeColor, in: Circle())                 // ← only sanctioned hex
    .overlay(Circle().strokeBorder(DS.textOnAccent.opacity(0.3), lineWidth: 0.5))
    .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
    .accessibilityLabel("\(platform.displayName) post")
```

### 5.7 Skeleton & empty states (never a spinner in a content area)

**Skeleton:** the *same* glass card, with `DS.glassSectionFill` placeholder bars and a
reduce‑motion‑gated shimmer:

```swift
.opacity(reduceMotion ? 1 : (shimmer ? 0.55 : 1))
.animation(reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
           value: shimmer)
// mark the whole skeleton .accessibilityHidden(true)
```

**Empty:** icon in a glass well (`DS.pageTitle`, `DS.textMuted`) · title `DS.headline` ·
subtitle `DS.callout`/`textSecondary` that **teaches the next action** ("Import a creator's
catalog to start the cross‑platform feed.") — never "No items yet."

### 5.8 Count / metadata pill

`DS.glassInputFill` capsule + `DS.glassBorder`, text `DS.caption.weight(.semibold)` +
`.monospacedDigit()`. Sits next to a `DS.title2` section header.

---

## 6. The motion system

Springs only — all from `ProMotionSprings`. The vocabulary and when to reach for each:

| Spring | Feel (response / damping) | Use for |
|---|---|---|
| `.hover` | 0.15 / 0.78 — quick, settled | card/control hover lift |
| `.press` | 0.08 / 0.92 — instant, no overshoot | tap‑down |
| `.snappy` | 0.12 / 0.82 — crisp | selection, chip toggle |
| `.bouncy` | 0.25 / 0.68 — lively overshoot | morph‑in (dropdowns, detail) |
| `.gentle` | 0.35 / 0.85 — calm | focus transitions, search expand |
| `.selection` | 0.2 / 0.85 | selection highlight |
| `.cascade(index:)` | staggered entrance | grid/list item appearance |
| `.staggered(index:baseDelay:)` | staggered entrance (tunable) | longer lists |

**Entrance pattern** (grid cards): start `opacity 0` + `scaleEffect 0.96`, then on appear
animate to 1/1 with `ProMotionSprings.cascade(index: min(itemIndex, 8))` — **cap the index
(~8)** so a long feed doesn't crawl in. Guard against re‑running and Reduce Motion:

```swift
private func animateEntrance() {
    guard !reduceMotion else { hasAppeared = true; return }
    guard !hasAppeared else { return }
    withAnimation(ProMotionSprings.cascade(index: min(appearIndex, 8))) { hasAppeared = true }
}
```

**Hover** = `scaleEffect(1.01)` + shadow lift. **Tap** = `scaleEffect(0.97)` with `.press`.
Always `.animation(_:value:)` with an explicit value, or `withAnimation` for event‑driven
changes. Prefer transform animations (`scale`, `offset`) over layout animations (`frame`).

---

## 7. The two laws that separate "polished" from "Apple" (learned the hard way)

### 7.1 Never branch structure on animated state inside a `ViewModifier`

A `ViewModifier` whose `body` does `if state { content.a() } else { content.b() }` compiles
to `_ConditionalContent`. When `state` flips, SwiftUI **moves `content` between branches and
rebuilds the entire wrapped subtree** — destroying child identity, restarting any
`AsyncImage`, dropping hover tracking, and tanking the frame rate when many cells flip at
once. (This was a real Discover bug: hovering a card reloaded its thumbnail and killed
hover.)

```swift
// ❌ WRONG — rebuilds the subtree on every hover
func body(content: Content) -> some View {
    if isHovered { content.dsHoverShadow() } else { content.dsRestingShadow() }
}

// ✅ RIGHT — constant structure, parameters interpolate (and animate for free)
func body(content: Content) -> some View {
    let isDark = DS.palette.isDark
    return content
        .shadow(color: .black.opacity(isHovered ? (isDark ? 0.4 : 0.06) : (isDark ? 0.3 : 0.04)),
                radius: isHovered ? (isDark ? 8 : 16) : (isDark ? 4 : 8),
                x: 0, y: isHovered ? (isDark ? 2 : 4) : (isDark ? 1 : 2))
        .shadow(color: .black.opacity(isHovered ? (isDark ? 0.25 : 0.03) : (isDark ? 0.2 : 0.02)),
                radius: isHovered ? (isDark ? 2 : 4) : (isDark ? 1 : 2),
                x: 0, y: isHovered ? (isDark ? 1 : 2) : (isDark ? 0 : 1))
}
```

**General rule:** drive *values* with state (ternaries on color/opacity/radius/lineWidth),
never *structure*. Keep `ForEach` identity stable (`id: \.element.id`, never `.indices`).

### 7.2 `cosmoGlassSceneSignal` only works *inside* a `CosmoGlassPanel`

The scene‑signal lensing API (`CosmoGlassPanel.swift:177`) is a **no‑op** unless the content
sits inside a `CosmoGlassPanel` that samples its preference. For plain content (feed cards,
list rows) it does nothing — use the **direct tint wash** from §5.1 instead
(`.background(tint.opacity(0.06→0.10), in: shape)`). Reach for `cosmoGlassSceneSignal` only
when you're already rendering chrome through `CosmoGlassPanel`.

### 7.3 Remote images must be cached

`AsyncImage` has no cache: it reloads on every view re‑creation (e.g. `LazyVStack`
recycling) and flickers. Use the shared **`CachedAsyncImage`** (`ThumbnailCacheService.swift`)
— memory + disk cache, synchronous cache hit on init (no flicker), deduplicated in‑flight
fetches. Pass a restart‑safe `stableKey` (e.g. `"\(platform.rawValue)-\(providerPostID)"`)
so thumbnails survive CDN URL rotation.

---

## 8. Accessibility (part of the spec, not an afterthought)

- **Reduce Motion:** gate every entrance/shimmer/decorative animation on
  `@Environment(\.accessibilityReduceMotion)` (pattern in §5.7 / §6).
- **Reduce Transparency:** the glass primitives already honor it — so *use the primitives*
  rather than hand‑rolling `.opacity` frost that won't adapt.
- **Touch targets:** 44×44pt minimum for every control (icon buttons wrap a small glyph in
  a 44pt hit frame).
- **Labels:** every icon‑only control gets `.accessibilityLabel`; group card content with
  `.accessibilityElement(children: .combine)` + `.accessibilityAddTraits(.isButton)`.
- **Dynamic Type:** use `DS` fonts (they scale); use `@ScaledMetric` for custom numeric
  sizing.
- **Keyboard (macOS):** primary actions get a `.keyboardShortcut`.

---

## 9. macOS 26 Liquid Glass — progressive enhancement (optional, last)

CosmoOS ships on macOS 15, so warm glass is the **foundation**; native glass is a bonus.
Centralize it in **one** place — an `#available(macOS 26, *)` branch *inside* the glass
primitive (`CosmoGlassPanel` / a `.glassEffectWithFallback` helper) that calls native
`.glassEffect(.regular[.interactive()], in:)` with the current `NSVisualEffectView`/material
as the ≤15 fallback. Wrap grouped chips/buttons in `GlassEffectContainer` (glass can't
sample glass). Keep it toggleable so it never blocks the core look on an older toolchain.

---

## 10. ✅ Apply‑to‑any‑page checklist

Bring up any new page against this list:

**Material & color**
- [ ] Page on `DS.bg`; chrome via `CosmoGlassPanel` / `.dsGlassCard` / `.dsGlassInput` —
      **zero `.regularMaterial`/`.ultraThinMaterial`** for cards.
- [ ] All color through `DS` tokens; **zero raw `Color(hex:)`** except a tiny platform badge.
- [ ] Tint washes (6–10%) and selection fills use entity tokens / `DS.accentSoft`.
- [ ] Accent appears on ≤1 hero affordance + selection. Not as fill everywhere.

**Type & rhythm**
- [ ] `DS` type scale only; **zero `.font(.system(size:))`**. Mastheads/page titles use
      `DS.pageTitle` (sans); serif only for reading content / accents (§4).
- [ ] One clear hero element; secondary text is `DS.textSecondary/Muted`.
- [ ] 8pt spacing grid; corner radii from the scale (cards 14, panels 22–24).
- [ ] `clipShape(.rect(cornerRadius:))` — **zero `.cornerRadius()`**.

**Depth & motion**
- [ ] Cards: `dsRestingShadow` → `dsHoverShadow`, hairline `glassBorder` → `glassBorderFocused`.
- [ ] Hover = 1.01 + lift; tap = 0.97 + `.press`; entrance = `cascade(index:)` capped ~8.
- [ ] Springs only (`ProMotionSprings.*`); every `.animation` has a `value:`.
- [ ] **No structural `if/else` on animated state inside a `ViewModifier`** (§7.1).

**Data & a11y**
- [ ] Remote images via `CachedAsyncImage` with a `stableKey` (§7.3).
- [ ] Entrance/shimmer gated on Reduce Motion; glass primitives used (Reduce Transparency).
- [ ] Icon controls: 44pt target + `accessibilityLabel`; cards combined + `.isButton`.
- [ ] macOS primary actions have a `.keyboardShortcut`.

**Architecture (CosmoOS conventions)**
- [ ] `@Observable` state (no `ObservableObject`/`@StateObject`); `@State` is `private`.
- [ ] `NavigationSplitView`/`NavigationStack` (no `NavigationView`).
- [ ] `body` < 30 lines — extract subviews; no `AnyView` in rows; stable `ForEach` identity.
- [ ] `foregroundStyle()` (no `foregroundColor()`).

**The final look test**
- [ ] Side‑by‑side with Command‑K + the sidebar: same warm‑glass material family.
- [ ] Toggle Reduce Transparency + Reduce Motion: graceful, nothing breaks.

---

## 11. Anti‑patterns (these instantly break the feeling)

- Cool grey frost (`.regularMaterial`) on a card — reads as a different app.
- Raw Tailwind/hex tints for categories instead of entity tokens.
- `.font(.system(size:))` anywhere in a view.
- A serif (`DS.displaySerif`) page or nav title — serif is for reading content, not chrome (§4).
- Accent green as a background fill or on more than the hero affordance.
- Linear/`easeInOut` animation, or a fade‑and‑slide entrance (too "web").
- Hover scale ≥ 1.05, or a shadow heavier than `dsFloatingShadow`.
- A spinner centered in a content area instead of a glass skeleton.
- Emoji or exclamation marks in chrome; "No items yet" empty states.
- Structural `if/else` on animated state (rebuilds subtrees, reloads images — §7.1).
- `AsyncImage` for remote thumbnails (no cache — §7.3).

---

*Source of truth for tokens: `Core/DesignSystem.swift`, `Core/Theme.swift`,
`Core/Components/CosmoGlassPanel.swift`, `Core/FilmGrainOverlay.swift`. Reference
implementation: SwipeFile Discover/Creators in `UI/SwipeFile/SwipeFileHomeView.swift`.*
