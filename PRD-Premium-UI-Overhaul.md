# CosmoOS Premium UI Overhaul
## Product Requirements Document

**Version:** 1.0
**Date:** February 15, 2026
**Status:** Draft for Review

---

## 1. Executive Summary

CosmoOS aspires to be the definitive cognitive operating system — the place where thinking, creating, planning, and self-optimization converge. The app currently has strong bones: a rich feature set, a dark spatial theme, and a unique orbital metaphor. But it reads as "sophisticated game" rather than "instrument of mastery."

This PRD defines a systematic elevation from **gaming dashboard** to **cognitive atelier** — the feeling of stepping into a space that was *crafted* for you, not *assigned* to you. Think: the difference between a gaming headset's RGB software and the Porsche Taycan's instrument cluster. Both show metrics. One makes you feel like a player. The other makes you feel like someone who commands precision.

**The north star:** Every screen should feel like opening a $300 leather notebook that happens to be alive with intelligence.

---

## 2. The Problem — Diagnosed Against Research

### 2.1 What "Gamey" Actually Means (And Why It Matters)

Looking at the current Behavioral Dimension view and Sanctuary hub, several specific patterns trigger the "gamey" perception:

| Current Pattern | Why It Feels Gamey | Premium Reference |
|---|---|---|
| **Gray bordered cards** (`#1C1C2E` with `white.opacity(0.08)` border) | Uniform, flat, identical weight — like inventory slots in an RPG | Apple Health: borderless cards with subtle elevation differences |
| **ALL CAPS section headers** ("DISCIPLINE INDEX", "ROUTINE CONSISTENCY") | Aggressive, loud, like HUD labels | Linear: sentence case, Inter Display, lighter weight |
| **Colored progress bars** (red/orange/green bars under metrics) | Direct gaming health-bar association | Porsche dashboard: thin, monochrome arcs with color reserved for alerts |
| **XP/Level prominent display** ("Level 1 · Transcendent", "XP: 0 / 182") | Explicit gamification mechanics front-and-center | Oura Ring: "Readiness 85" — same concept, zero game language |
| **Ring indicators for week days** | Fitness tracker / Apple Watch ring aesthetic | Premium: small dots or subtle filled squares |
| **Multiple competing accent colors** per screen | Visual noise, carnival feel | Aesop website: one or two tones per viewport |
| **Dashed borders, dotted grids, visible strokes** | Construction/prototype feel | Stripe Dashboard: invisible structure, content-first |

### 2.2 The Science of Premium Perception

**Research finding 1 — Color Saturation and Status (Journal of Consumer Research, 2025):**
> "Low (vs. high) color saturation increases a luxury brand's perceived brand status." Through 7 experimental studies, researchers found that desaturated colors signal heritage, timelessness, and elevated status. Customers carrying bags with low saturation were treated more respectfully in luxury stores. *However*, this effect reverses for brands positioning as innovative — which is relevant for CosmoOS.

**Implication for CosmoOS:** We sit at the intersection. CosmoOS is innovative *and* should feel timeless. The solution: **desaturate the ambient environment** (backgrounds, cards, chrome) while keeping **controlled, precise saturation** for data accents — like how a Porsche interior is all muted leather and aluminum, but the tachometer needle is *exactly* the right red.

**Research finding 2 — Dark Mode and Cognitive Performance:**
Dark mode reduces eye strain during extended sessions (validated for sustained focus work) and creates an inherent sense of depth and premium-ness when executed well. The key differentiator between "premium dark" and "cheap dark" is **contrast management** — premium dark interfaces use more elevation layers (not just one shade of dark) and restrict high-contrast elements to focal points.

**Implication:** Stay dark. But evolve from a 2-layer system (void + cards) to a **5-layer elevation system** that creates genuine spatial depth.

**Research finding 3 — Typography and Luxury:**
Serif accents within sans-serif interfaces signal craftsmanship and heritage. Linear uses Inter Display for headings to add "expression." Luxury brands use dramatic contrast between thick and thin strokes. The key principle: **font mixing creates hierarchy that feels curated, not systematic.**

**Implication:** Introduce a serif accent font (New York / SF Serif) for specific hero moments — the Cosmo Index number, dimension names, section titles in focus modes. Keep SF Pro / system rounded for UI controls and body text.

**Research finding 4 — NN/G Luxury Design Principles:**
Nielsen Norman Group identifies that luxury digital experiences must "spark interest" while "avoiding interruptions." The balance is: **show less, mean more.** Every element visible should earn its place. Whitespace (or in dark mode, "dark space") is the primary luxury signal.

---

## 3. Design Philosophy — "The Cognitive Atelier"

### 3.1 Core Principles

**Principle 1: Earned Saturation**
Color is not decoration — it's information. The environment is near-monochrome (warm charcoal tones). Color appears *only* to communicate state, and its intensity maps to significance. A 30% sleep score doesn't get the same visual weight as a 95% score. Color must be earned.

**Principle 2: Depth Through Elevation, Not Borders**
Remove visible borders from cards. Instead, use a 5-tier elevation system where depth is communicated through subtle background shade differences and shadow. This mirrors how physical luxury works — a Rolex dial doesn't have visible outlines around each complication; depth is created through material layers.

**Principle 3: Typographic Authority**
Premium interfaces let typography do the heavy lifting. Large, confident numbers in a lighter weight feel more authoritative than bold numbers with colored backgrounds. A 48pt light-weight "73" communicates mastery; a 48pt bold "73%" in a colored box communicates a game score.

**Principle 4: Restraint as Identity**
The current design uses ~16 distinct accent colors across dimensions, block types, and status indicators. Premium means choosing 3-4 core tones and deriving everything else. The Sanctuary's orbital metaphor already provides visual richness — the chrome around it should recede.

**Principle 5: Motion as Material**
Animations should feel like the interface has *weight* and *material properties*. A card shouldn't just appear — it should settle into place like it has mass. Current springs are well-tuned but applied uniformly. Premium motion means different elements have different material qualities: glass panels glide, data values count up, focus transitions breathe.

### 3.2 Staying Dark — The Verdict

Based on the research:
- **Dark mode wins for CosmoOS.** Extended cognitive work sessions, data visualization depth, premium perception, and the spatial/orbital metaphor all favor dark.
- A light mode could exist as an option, but should not be the default. The void/space metaphor IS the brand.
- The fix isn't going light — it's going **warmer and more layered** within dark.

---

## 4. The New Design System — "Onyx"

### 4.1 Color Architecture

#### Background Elevation Layers (The "Onyx Stack")

Replace the current 2-layer system (`thinkspaceVoid` #0A0A0F + `thinkspaceTertiary` #1A1A25) with 5 distinct layers:

| Layer | Name | Value | Usage |
|---|---|---|---|
| L0 | `onyx.void` | `#08080C` | True background, infinite canvas, behind everything |
| L1 | `onyx.base` | `#0F0F14` | Primary surface — the "floor" of each view |
| L2 | `onyx.raised` | `#16161E` | Card backgrounds, primary containers |
| L3 | `onyx.elevated` | `#1E1E28` | Hover states, active cards, modal backgrounds |
| L4 | `onyx.floating` | `#262632` | Popovers, tooltips, dropdown menus, toolbar |

Each step is a **deliberate** 7-8 lightness increase in LCH color space with a slight blue-violet undertone (preserving the cosmic feel without being cold).

**Key change:** Cards no longer need visible borders. The elevation difference between L1 and L2 creates implicit containment. Borders become optional accents, not structural requirements.

#### Accent Color Reduction — The "Tonal Palette"

**Current state:** 16+ distinct hue-based accent colors across the app.

**New approach:** 3 primary tones + 1 accent + contextual dimension colors (desaturated).

| Role | Name | Value | Usage |
|---|---|---|---|
| Primary | `onyx.iris` | `#8B8FE8` (desaturated indigo) | Primary actions, AI elements, links |
| Warm | `onyx.amber` | `#C4A87A` (muted gold) | XP, achievements, progress — replaces #FFD700 |
| Signal | `onyx.sage` | `#7BAF8E` (muted green) | Success, health, positive trends |
| Alert | `onyx.rose` | `#C48B8B` (muted rose) | Warnings, attention, declining trends |

**Dimension Colors — Desaturated Set:**
Each dimension retains its identity but shifted to ~40% saturation (from current ~70-80%):

| Dimension | Current | New (Desaturated) |
|---|---|---|
| Cognitive | `#6366F1` (vivid indigo) | `#7B7EC0` (dusty indigo) |
| Creative | `#F59E0B` (vivid amber) | `#C4A870` (antique gold) |
| Physiological | `#10B981` (vivid emerald) | `#6BAF8E` (sage) |
| Behavioral | `#3B82F6` (vivid blue) | `#7199C4` (steel blue) |
| Knowledge | `#8B5CF6` (vivid purple) | `#9585C0` (lavender gray) |
| Reflection | `#EC4899` (vivid pink) | `#C07B9E` (dusty rose) |

**Rule:** Dimension colors at full (current) saturation are ONLY used inside that dimension's detail view, for the primary metric and active data. In the Sanctuary overview and in other contexts, the desaturated versions are used. This creates a "lights come on" effect when you enter a dimension — it feels alive, the ambient view feels composed.

#### Text Hierarchy

| Role | Current | New |
|---|---|---|
| Primary text | `white` | `#E8E8EC` (slightly warm, not pure white — reduces glare) |
| Secondary | `white.opacity(0.7)` | `#9898A8` (fixed color, not opacity-based — more predictable) |
| Tertiary | `white.opacity(0.5)` | `#5C5C6E` (deliberate, not transparent) |
| Muted | `white.opacity(0.35)` | `#3E3E4E` (barely there, for timestamps and fine print) |

**Why fixed colors over opacity?** Opacity-based text shifts appearance over different backgrounds. Fixed colors maintain consistent contrast ratios regardless of what's beneath them — a hallmark of Apple's design system and essential for accessibility.

### 4.2 Typography Overhaul

#### The Pairing: SF Pro Display + New York (Serif Accent)

| Context | Font | Weight | Size | Tracking |
|---|---|---|---|---|
| **Hero metrics** (Cosmo Index, dimension scores) | SF Pro Display | Ultralight | 56pt | -0.5pt |
| **Section titles** (in Sanctuary, dimension views) | New York (serif) | Regular | 15pt | +0.3pt |
| **View titles** ("Sanctuary", "Plannerum") | SF Pro Display | Semibold | 24pt | +1.5pt |
| **Card titles** | SF Pro Display | Medium | 13pt | +0.2pt |
| **Body text** | SF Pro Text | Regular | 14pt | 0 |
| **Labels / metadata** | SF Pro Text | Medium | 11pt | +0.5pt |
| **Micro text** (timestamps) | SF Mono | Regular | 10pt | 0 |

**Key changes:**
1. **Hero metrics go ultralight** at large sizes. A thin "73" at 56pt feels like a precision instrument. A bold "73%" at 36pt feels like a score. This single change has the largest impact on premium perception.
2. **New York serif for section titles** — introduces the "leather notebook" feel for headers like "Recovery" or "Focus Quality" within dimension views. Used sparingly (3-5 instances per screen max).
3. **Remove ALL CAPS from section headers.** Use sentence case with slightly increased tracking (+0.3pt) instead. "Routine Consistency" reads as refined; "ROUTINE CONSISTENCY" reads as a HUD callout.
4. **Remove the % symbol from hero metrics** where context makes it obvious. Display "73" not "73%". The unit can appear as a tiny suffix or be implied by the label. This is how Oura, Whoop, and high-end car dashboards present data.

### 4.3 Card System — "Borderless Elevation"

#### Before (Current SanctuaryCard):
```
Background: #1C1C2E
Border: white.opacity(0.08), 1pt
Corner radius: 16pt
Padding: 20pt
Title: 11pt SEMIBOLD UPPERCASE, #8888AA
```

#### After (New OnyxCard):
```
Background: onyx.raised (#16161E)
Border: NONE (elevation creates containment)
Corner radius: 14pt (slightly tighter — feels more precise)
Padding: 20pt (unchanged)
Shadow:
  - Layer 1: black.opacity(0.25), radius 1, y 1 (contact)
  - Layer 2: black.opacity(0.12), radius 8, y 4 (ambient)
Title: 13pt New York Regular, #9898A8, tracking +0.3pt (serif, sentence case)
```

**Optional accent border:** A 1pt border in the dimension's desaturated color appears ONLY on the card being hovered or the card containing the most important metric. Not on every card.

#### Card Size Variants:

| Variant | Height | Usage |
|---|---|---|
| `metric` | 88pt (compact) | Single stat with label |
| `standard` | 140pt | Chart or multi-stat |
| `expanded` | 200pt+ | Full data visualization |
| `hero` | Full width, 120pt | Primary view metric (e.g., Discipline Index) |

### 4.4 Data Visualization — From Gaming HUD to Instrument Cluster

#### Progress Bars → Thin Arcs/Lines

**Current:** Thick colored bars (6-8pt height) with hard edges under metrics — direct gaming health bar visual.

**New:** Thin (2-3pt), rounded-cap progress lines with these rules:
- **Track:** `onyx.raised` (barely visible against `onyx.base`)
- **Fill:** Dimension color at 60% opacity, with a subtle gradient (lighter at the leading edge)
- **No background pill** behind the progress indicator
- For circular metrics: thin-stroke arc (2pt) rather than thick ring (6pt+)

#### Metric Display Pattern

**Current (Behavioral Dimension):**
```
┌─────────────────────────────────┐
│ MORNING                    ··   │
│ 30 %                            │
│ ████████░░░░░░░░░░░░░░░░  →    │
└─────────────────────────────────┘
```

**New:**
```
  Morning
  30
  ──────░░░░░░░░░░░░░░░░░░░░
  Target: 90  ·  Last 7 days
```

Changes:
1. Remove the card border entirely — the metric group is separated by spacing
2. "Morning" in 13pt New York serif, sentence case, secondary color
3. "30" in 32pt SF Pro Display Ultralight, primary text color
4. Thin 2pt progress line, no background track visible
5. Contextual subtitle in tertiary text
6. Remove the `→` arrow and `··` menu dots from default state (appear on hover)

#### Week-Day Indicators

**Current:** Colored rings (fitness tracker style).

**New:** Small 6x6pt rounded squares:
- Empty: `onyx.elevated` fill (barely visible)
- Partial: Dimension color at 40% opacity
- Complete: Dimension color at 80% opacity
- Missed: `onyx.rose` at 40% opacity

This is how premium habit trackers (Streaks, GitHub contribution graph) display consistency — subtle grid, not workout rings.

### 4.5 The XP/Level System — Reframing Without Removing

The XP system is core to CosmoOS's value proposition. Removing it would gut the motivation loop. But it needs to be **reframed from game mechanic to mastery signal.**

#### Current Language → New Language

| Current | New | Rationale |
|---|---|---|
| "Level 1" | "Tier I" | Tiers feel like expertise levels (like Michelin stars), not game levels |
| "Transcendent" (rank) | Keep, but styled differently | Move from badge to subtle text |
| "XP: 0 / 182 to Level 2" | "182 to next tier" | Remove "XP" abbreviation, focus on the journey |
| "+10 XP/day" | "+10/day" | Remove the XP suffix entirely |
| Gold XP animations | `onyx.amber` subtle count-up | Muted gold, no particle effects |

#### Sanctuary Header — Redesigned

**Current:**
```
SANCTUARY
Level 1  ·  Transcendent
XP: 0 / 182 to Level 2    0%
████░░░░░░░░░░░░░░░░░░░░░░
```

**New:**
```
Sanctuary                                          ⚙
Tier I  ·  Transcendent

── 182 to Tier II ──────────────░░░░░░░░░░░░░░░░
```

Changes:
1. "Sanctuary" in 24pt SF Pro Display Semibold, NOT all caps (sentence case with tracking)
2. "Tier I · Transcendent" in 13pt SF Pro Text Regular, secondary color
3. Progress bar: thin 2pt line, `onyx.iris` fill (primary accent), no percentage displayed (the line IS the percentage)
4. "182 to Tier II" as inline label on the progress bar, in micro text

### 4.6 Shadow System — Apple-Grade Depth

The current shadow system is already multi-layered but uses purple tint (`thinkspacePurple`), which adds a "glow" quality that reads more magical/gaming than premium.

**New shadow approach:** Neutral-only shadows. Color glow reserved for ONE element per screen — the primary interactive element.

| Elevation | Shadow Spec |
|---|---|
| **L2 on L1** (card resting) | `black.opacity(0.2)`, blur 6, y 2 + `black.opacity(0.08)`, blur 1, y 1 |
| **L3 on L1** (card hovered) | `black.opacity(0.28)`, blur 10, y 4 + `black.opacity(0.1)`, blur 2, y 1 |
| **L4 on L1** (floating) | `black.opacity(0.35)`, blur 16, y 6 + `black.opacity(0.12)`, blur 3, y 2 |
| **Focused element** | Above shadow + single accent glow: `dimensionColor.opacity(0.12)`, blur 20 |

### 4.7 Animation Refinements

The current `ProMotionSprings` system is solid. Refinements for premium feel:

**Metric value transitions:** When a metric changes, the number should count up/down with an easeOut curve over 600ms — like a precision instrument settling to a reading. Not an instant switch.

**Card entrance stagger:** Increase stagger delay from 30ms to 50ms. Slower cascades feel more deliberate, like a concierge walking you through a hotel suite.

**Remove bouncy springs from data views.** Bouncy (overshoot) springs feel playful/gamey. For Sanctuary and dimension views, use critically-damped springs (damping ratio 0.9-1.0). Reserve bouncy springs for Thinkspace canvas interactions where playfulness is appropriate.

**View transitions:** When entering a dimension from Sanctuary, the current view should *exhale* — scale slightly (0.98) and blur, while the dimension view emerges from the orb's position with a 400ms spring. This creates a spatial relationship that feels architectural, not teleporting.

---

## 5. Screen-by-Screen Redesign

### 5.1 Sanctuary (Hub View)

**Current issues:**
- "SANCTUARY" all caps feels like a game title screen
- Level/XP bar is prominently gamey
- Orbs have visible level numbers that look like RPG character levels
- Connection lines between orbs are visible and structural-looking
- "Hover for correlations" instruction text feels like a tutorial prompt

**Redesign:**

**Header:**
- "Sanctuary" 24pt SF Pro Display Semibold, tracking +1.5pt, sentence case
- "Tier I · Transcendent" below in 13pt secondary color
- Thin progress line (2pt) that's part of the background, not a prominent UI element
- Settings gear: smaller (18pt), tertiary color, top-right

**Orb Redesign:**
- **Remove the level numbers from inside dimension orbs.** Instead, the orb's fill opacity and glow intensity communicate level (higher level = more luminous). This transforms orbs from "game character icons with numbers" to "living indicators of development."
- **Center Cosmo Index orb:** Display just the number (no "CI" label) in 32pt SF Pro Display Ultralight. The label "Cosmo Index" appears only on hover, in a small tooltip.
- **Dimension labels** ("Cognitive", "Creative") in 11pt New York (serif), positioned below orbs. Remove from being inside or adjacent to the orb badge.
- **Connection lines:** Reduce opacity from current 0.15-0.4 to 0.06-0.15. They should be *barely* perceptible — felt rather than seen. On hover of an orb, its connections brighten to 0.25. This creates the "alive" feeling without the "game map" visual.

**Satellite Orbs (Plannerum, Thinkspace):**
- Smaller, more distant-feeling (reduce from 72pt to 56pt)
- Label below in 10pt, tertiary color
- Connection line to main hub: even more subtle (0.04 opacity)

**Background atmosphere:**
- Keep the aurora gradient but reduce opacity from current 20% to 8-10%
- Add a very subtle radial vignette (black, 5% opacity) at edges to create focus on center
- The void should feel like depth, not just darkness

### 5.2 Dimension Views (Primary Redesign Target)

This is where the "gamey" problem is most acute. Taking Behavioral Dimension as the exemplar:

#### 5.2.1 Dimension Header

**Current:**
```
DISCIPLINE INDEX
100.0%
████████████████████████████████████████ ↗ +0.0% vs last week
```

**New:**
```
Discipline Index                        ↗ Stable
72                                      vs last week
───────────────────────────────░░░░░░░
```

- "Discipline Index" in 15pt New York serif, secondary color
- "72" in 56pt SF Pro Display Ultralight, primary text color (NO % symbol)
- Thin 2pt progress line, dimension color fill
- "↗ Stable" as inline trend indicator, tertiary color
- "vs last week" in 10pt micro text

#### 5.2.2 Metric Cards Grid

**Current:** 3x2 grid of identical gray bordered cards, each with ALL CAPS label, bold number, colored progress bar, arrow, and dots menu.

**New:** Metrics displayed as a clean vertical list or 2-column grid WITHOUT card containers:

```
  Morning            Deep Work           Sleep
  30                 30                   50
  ──────             ──────              ──────────────

  Movement           Screen              Tasks
  50                 65                   0
  ──────────────     ─────────────────
```

- Each metric is a **borderless group** — label, number, thin progress line
- Separated by generous spacing (32pt between groups)
- Numbers: 28pt SF Pro Display Light
- Labels: 13pt New York serif, secondary color
- Progress line: 2pt, dimension color at 60% opacity
- On hover: the metric group gains a subtle background (L3 elevation, no border) and shows the `→` detail arrow and contextual info
- **Only the lowest-performing metric** has its number in the dimension's full-saturation color (drawing attention to where action is needed)

#### 5.2.3 Routine Consistency Section

**Current:** Cards with "MORNING ROUTINE" in bold caps, week-day ring indicators, percentage.

**New:**
```
  Routine Consistency

  Morning Routine                              12%
  Target: 7:00am  ±30min
  M   T   W   T   F   S   S
  ·   ·   ·   ·   ·   ■   ■

  Sleep Schedule                               50%
  Target: 11:00pm  ±30min
  S   M   T   W   T   F   S
  ■   ■   ■   ■   ■   ■   ■
```

- Section title "Routine Consistency" in 15pt New York serif
- Routine name in 14pt SF Pro Medium, primary color
- Percentage as inline right-aligned value, not a separate badge
- Week-day indicators: 6x6pt rounded squares (not rings)
- Time data in 10pt mono, tertiary color
- No card wrapper — grouped by spacing and subtle section dividers (1pt line, 4% opacity)

#### 5.2.4 Active Streaks Section

**Current:** "AT RISK" badge with orange, streak cards with progress bars, "+10 XP/day" badges.

**New:**
```
  Active Streaks                          +10/day

  Deep Work                               2 days
  at risk                                ───░░░░░
  7 days to milestone

  Task Zero                               0 days
  ───░░░░░░░░░░░░░░░
  Best: 7 days
```

- Remove colored "AT RISK" badge. Instead: the text "at risk" appears in `onyx.rose` below the streak name in 11pt
- Remove "+10 XP/day" in gold badge → "+10/day" in 11pt `onyx.amber`, right-aligned on section header
- Streak progress: thin line, same pattern as other metrics
- Milestone countdown as tertiary text underneath

### 5.3 Thinkspace (Canvas)

The canvas is already the strongest part of the design — the infinite dark void with floating blocks feels appropriately premium. Refinements:

**Grid dots:** Reduce opacity from 0.4 to 0.15. They should be barely perceptible — guiding alignment without being a visible grid.

**Block wrapper (`CosmoBlockWrapper`):**
- Remove the purple-tinted shadow. Use neutral shadows from the new system.
- Remove the aurora gradient overlay on blocks. Use flat `onyx.raised` background.
- On selection: use the block type's desaturated color as a 1pt border (not 2pt) and a subtle glow
- Toolbar: appears ABOVE the block with a 4pt gap. Background: `onyx.floating`. No accent bar at bottom.

**Connection lines (Knowledge Pulse Lines):**
- Keep the animated pulse concept but reduce the glow radius from current to 50% of current
- Use `onyx.iris` (primary accent) instead of per-dimension colors for connections
- Pulse animation: slow down by 30% — unhurried feels premium

### 5.4 Focus Modes

Focus modes already feel more premium because they're full-screen and purpose-built. Key adjustments:

**Top bar gradient:** Keep the gradient fade but make it more gradual (extend from 80pt to 120pt fade distance). Abrupt gradients feel cheap.

**Research Focus Mode:**
- Annotation cards: remove visible borders, use elevation system
- Transcript text: increase line spacing by 2pt for a more book-like feel
- Type badges: smaller (10pt), more muted colors

**Content Focus Mode:**
- Pipeline bar: reduce height, use dots instead of labeled phases (labels on hover)
- Draft editor: wider max-width (720pt → 680pt optimal reading width already defined in tokens)
- Context panel: softer divider (reduce from `white.opacity(0.08)` to `white.opacity(0.04)`)

**Idea Focus Mode:**
- Intelligence panel background: use `onyx.base` instead of hardcoded `#12121A`
- Confidence bars in framework recommendations: thin (2pt) instead of full bars
- "Activate" CTA: less saturated, use `onyx.iris` instead of full indigo

### 5.5 Plannerum

**Header:**
- "Plannerum" in 24pt SF Pro Display Semibold (not 28pt bold rounded with 4pt tracking — that feels like a game logo)
- Reduce the live metrics panel size and visual weight
- Pulsing live dot: keep but reduce scale animation from 2x to 1.3x (subtle, not throbbing)

**View Mode Switcher:**
- Reduce visual weight of the pill bar
- Active tab: `onyx.iris` at 12% opacity background (not 20%)
- Text: 12pt, not 13pt

**Time Block Cards:**
- Keep the left accent bar (4pt width) — it's a good pattern
- Remove the hover scale animation (1.05x) — at most 1.01x. Blocks shouldn't bounce.
- Complete button: appears on hover as a small checkmark circle, no fill until clicked

**Day Timeline:**
- Hour grid: reduce dotted divider opacity to barely visible
- Now bar: thin 1pt line with small time pill, not animated pulsing glow
- External calendar events: reduce border and increase blend with background

### 5.6 Command-K Overlay

The Command-K overlay is well-designed. Adjustments:

- **Aurora glow** around the modal: reduce intensity by 60%. It currently looks like a gaming power-up.
- **Search bar:** increase height to 56pt (from 72pt), reduce icon size
- **Constellation visualization:** beautiful concept, but reduce node glow intensity by 50%
- **Tab underline indicator:** use a 2pt pill indicator (not full underline)

---

## 6. Component Library — New Shared Components

### 6.1 `OnyxCard`
Replaces `SanctuaryCard` and all gray-bordered card containers.

**Properties:**
- `elevation: OnyxElevation` (.raised, .elevated, .floating)
- `accentEdge: Edge?` (optional thin color accent on one edge)
- `accentColor: Color?`
- `hoverBehavior: OnyxHoverBehavior` (.lift, .glow, .none)

### 6.2 `OnyxMetric`
Standardized metric display replacing ad-hoc number + progress bar patterns.

**Properties:**
- `label: String` (displayed in New York serif, secondary color)
- `value: Double`
- `displayStyle: MetricStyle` (.hero56pt, .large32pt, .compact22pt, .inline14pt)
- `unit: String?` (optional, displayed as tiny suffix)
- `progress: Double?` (0-1, displayed as thin line below value)
- `trend: Trend?` (.up, .down, .stable)
- `trendLabel: String?` ("vs last week")

### 6.3 `OnyxProgressLine`
Replaces all progress bars, health bars, and thick indicators.

**Properties:**
- `progress: Double` (0-1)
- `height: CGFloat` (default 2pt)
- `color: Color`
- `trackColor: Color` (default: `onyx.raised`)
- `animated: Bool`

### 6.4 `OnyxWeekGrid`
Replaces ring-based week indicators.

**Properties:**
- `days: [DayStatus]` (.empty, .partial, .complete, .missed)
- `color: Color`
- `squareSize: CGFloat` (default 6pt)

### 6.5 `OnyxSectionHeader`
Replaces ALL CAPS section titles.

**Properties:**
- `title: String` (rendered in New York serif, 15pt)
- `trailing: String?` (right-aligned metadata)
- `divider: Bool` (subtle 1pt line below)

---

## 7. Implementation Phases

### Phase 1: Foundation — Design Tokens & Core Components (1 week)
**Scope:** Ship the new design system without changing any views.

- [ ] Create `OnyxColors.swift` with the 5-layer elevation system and new accent palette
- [ ] Create `OnyxTypography.swift` with the SF Pro Display + New York pairing
- [ ] Create `OnyxShadows.swift` with neutral shadow system
- [ ] Build `OnyxCard`, `OnyxMetric`, `OnyxProgressLine`, `OnyxWeekGrid`, `OnyxSectionHeader` components
- [ ] Create `OnyxSpring` animation set (critically-damped variants for data views)

### Phase 2: Sanctuary & Dimensions — The Core Experience (1-2 weeks)
**Scope:** The views with the highest "gamey" perception.

- [ ] Redesign `SanctuaryView` header (sentence case, tier language, thin progress)
- [ ] Redesign Sanctuary orbs (remove numbers, luminosity-based levels)
- [ ] Reduce connection line opacity and rework hover behavior
- [ ] Redesign all 6 dimension views using `OnyxMetric` and `OnyxCard`
- [ ] Replace ALL CAPS headers with `OnyxSectionHeader` across all dimension views
- [ ] Replace progress bars with `OnyxProgressLine` (2pt, thin)
- [ ] Replace week-day rings with `OnyxWeekGrid` (small squares)
- [ ] Rework XP display language (Level → Tier, remove "XP" suffix)
- [ ] Remove/reduce PlaceholderCard gray boxes — use inline empty states

### Phase 3: Thinkspace & Focus Modes (1 week)
**Scope:** Adapt the creation/work surfaces.

- [ ] Update `CosmoBlockWrapper` shadows to neutral system
- [ ] Reduce grid dot opacity
- [ ] Update focus mode top bar gradients
- [ ] Apply `OnyxCard` to annotation cards, intelligence panels
- [ ] Reduce connection line glow in canvas

### Phase 4: Plannerum & Command-K (1 week)
**Scope:** Operational views.

- [ ] Update Plannerum header and view switcher
- [ ] Refine time block cards (reduce hover animation)
- [ ] Reduce Command-K aurora glow
- [ ] Apply `OnyxMetric` to Plannerum stats
- [ ] Refine Now view session card with muted palette

### Phase 5: Polish Pass (3-5 days)
**Scope:** Cross-cutting refinements.

- [ ] Audit every view for remaining ALL CAPS headers
- [ ] Audit for gray borders that should be elevation-based
- [ ] Audit for over-saturated colors in non-focal contexts
- [ ] Test animation timing refinements (stagger delays, spring dampening)
- [ ] Verify text contrast ratios meet WCAG AA on all elevation layers
- [ ] Test metric number transitions (count-up animations)

---

## 8. What We're NOT Changing

Equally important is what stays:

1. **The dark void theme.** Research supports it for cognitive tools.
2. **The orbital Sanctuary metaphor.** It's unique and beautiful — it just needs refinement, not replacement.
3. **The XP/progression system.** It's reframed, not removed. The underlying mechanics are unchanged.
4. **Dimension-specific colors.** They're desaturated and given rules about when to appear at full intensity, but each dimension retains its identity.
5. **The spatial canvas (Thinkspace).** It's the strongest design element. Minor tweaks only.
6. **Focus mode layouts.** The 2-column architecture works. Components within are updated.
7. **Animation system.** Springs are re-tuned, not rebuilt. The infrastructure is sound.
8. **Glass morphism in functional overlays.** Command-K, popovers — the frosted glass effect works well when used for transient UI. It's reduced in persistent surfaces.

---

## 9. Success Criteria

After implementation, the UI should pass these gut-check tests:

1. **The Hotel Test:** A first-time user should feel a moment of "oh, this is premium" within 3 seconds of seeing the Sanctuary.
2. **The Screenshot Test:** Any screenshot from the app should look like it could be in a design portfolio — not a tutorial for a fitness tracker.
3. **The Squint Test:** When you squint at the screen, you should see clean, structured regions of light and dark — not a mosaic of colored rectangles.
4. **The Age Test:** The UI should look just as appropriate in 3 years as it does today. Trends like heavy glass morphism and neon glows age fast. Spatial depth, restrained color, and typographic hierarchy are timeless.
5. **The Peer Test:** Show it to someone who uses Linear, Raycast, or Apple's pro tools. They should say "this feels like those" rather than "this looks like a game."

---

## 10. Research References

- Arbuthnot et al. (2025). "The Color of Status: Color Saturation, Brand Heritage, and Perceived Status of Luxury Brands." *Journal of Consumer Research*, Oxford Academic.
- Nielsen Norman Group. "Applying Luxury Principles to Ecommerce Design." nngroup.com.
- Linear. "How We Redesigned the Linear UI (Part II)." linear.app/now.
- Wang (2022). "What is the glamor of black-and-white? The effect of color design on evaluations of luxury brand ads." *Journal of Consumer Behaviour*, Wiley.
- ScienceDirect. "The effect of interior color on customers' aesthetic perception, emotion, and behavior in the luxury service."
- Interaction Design Foundation. "The Role of Micro-interactions in Modern UX."

---

*This document should be treated as a living spec. As implementation begins, individual component decisions may evolve — but the principles (earned saturation, borderless elevation, typographic authority, restraint as identity, motion as material) are the constants.*
