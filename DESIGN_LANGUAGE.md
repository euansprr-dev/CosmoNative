# CosmoOS Design Language — Greenhouse

> Your workspace should feel like a sunlit greenhouse — warm, natural, alive with
> ideas growing. Clean surfaces, generous breathing room, organic green accents, and
> the subtle texture of aged paper. Every pixel exists to make your mind feel at peace.

This document is the single source of truth for all visual decisions in CosmoOS.
Every screen, every component, every interaction must trace back to these tokens.
No inline colors. No magic numbers. No exceptions.

---

## 1. Philosophy

**Five principles that govern every design decision:**

1. **Content is the hero.** Chrome disappears. Surfaces are clean white or warm
   off-white. The user's ideas, notes, research, and connections are the most
   colorful things on screen.

2. **Breathing room.** Generous padding (16-20px inside cards, 40px page margins),
   comfortable line height (1.5 body, 1.2 headings), generous spacing between
   sections (36px). Nothing feels cramped. Your eye can rest between elements.

3. **Warmth over sterility.** Not clinical white (#FFFFFF everywhere) — warm
   parchment whites (#F8F7F4) and natural greens (#2D6A4F). The app feels like a
   well-lit studio, not a hospital.

4. **Quiet depth.** Shadows are soft and natural (never harsh or colored). Borders
   are neutral gray, not warm or cold. Elevation comes from subtle shadow
   differences, not background color changes. One shadow system, applied
   consistently.

5. **Earned color.** Color is used sparingly and with purpose: entity type
   identification, status indicators, the primary green accent. Everything else is
   grayscale. When color appears, it means something.

6. **System-native behavior.** Respect macOS accessibility settings: reduce motion,
   reduce transparency, increase contrast. Use semantic system colors for chrome
   where possible. The app should feel like it belongs on the platform.

**Reference points:** Apple Notes, Craft, Apple Freeform (clean white workspace),
Eden (green accent + film grain texture), macOS system preferences (hierarchy,
spacing, typography).

---

## 2. Color System

### 2.1 Surfaces

Every surface in the app uses one of these five fills. No other background colors
exist.

| Token              | Hex       | Usage                                           |
|--------------------|-----------|------------------------------------------------|
| `bg`               | `#F8F7F4` | Page background, window background              |
| `canvas`           | `#F2F1ED` | Thinkspace canvas, workspace areas              |
| `surface`          | `#FFFFFF` | Cards, editors, inputs, modals, panels          |
| `surfaceSecondary` | `#F5F4F0` | Sidebar backgrounds, section groupings          |
| `surfaceHover`     | `#F0EFEB` | Hover states on interactive surfaces            |

**Rules:**
- Cards sit on `bg` → use `surface` (#FFFFFF) for the card
- Inputs sit inside cards → use `surface` (#FFFFFF) with border
- Sidebar sits next to content → use `surfaceSecondary`
- Canvas is the spatial workspace → use `canvas` with film grain overlay
- Never use opacity-based surfaces (no `Color.black.opacity(0.05)`)

### 2.2 Text

Three levels. Never more. Hierarchy comes from weight and size, not color
proliferation. All text colors pass WCAG AA contrast ratio (4.5:1 minimum for
body text, 3:1 for large text) against `bg` (#F8F7F4).

| Token           | Hex       | Contrast vs bg | Usage                                   |
|-----------------|-----------|----------------|-----------------------------------------|
| `text`          | `#1A1A1F` | 15.8:1         | Headings, body text, editor content     |
| `textSecondary` | `#6B6B78` | 5.2:1          | Descriptions, subtitles, metadata       |
| `textMuted`     | `#767685` | 4.5:1          | Placeholders, timestamps, disabled, hints |

**Rules:**
- Primary text is near-black with slight warmth — never pure `#000000`
- On green accent backgrounds, use `#FFFFFF` (white)
- On colored entity backgrounds, use the entity's dark variant
- Never use `.foregroundColor(.white)` directly — use `DS.textOnAccent`
- `textMuted` MUST pass 4.5:1 contrast. The previous #767685 (3.0:1) failed
  WCAG AA. #767685 passes.

### 2.3 Accent — Cosmo Green

The signature color of CosmoOS. Represents growth, knowledge, sanctuary.
Inspired by Eden's deep forest aesthetic.

| Token          | Value                           | Usage                               |
|----------------|---------------------------------|-------------------------------------|
| `accent`       | `#2D6A4F`                       | Primary buttons, selected states, active indicators |
| `accentHover`  | `#245943`                       | Button hover, pressed states        |
| `accentSoft`   | `#E8F5EC`                       | Selected row bg, tag bg, light tint |
| `accentMuted`  | `#D1E8D5`                       | Progress bars, active section bg    |
| `accentGlow`   | `rgba(45, 106, 79, 0.10)`      | Focus ring shadow, button shadow    |
| `textOnAccent` | `#FFFFFF`                       | Text on green backgrounds           |

**Rules:**
- Green is the ONLY brand accent. No purple, no blue as primary.
- Use `accent` for primary actions: main CTA, toggle ON, selected tab
- Use `accentSoft` for background tinting: selected sidebar item, active filter chip
- Use `accentGlow` for focus rings and button shadows (never colored shadows elsewhere)

### 2.4 Status Colors

Used exclusively for status indication. Never decorative.

| Token     | Hex       | Usage                               |
|-----------|-----------|-------------------------------------|
| `success` | `#38B764` | Completed tasks, success messages   |
| `warning` | `#D97706` | In-progress, attention needed       |
| `error`   | `#DC3545` | Errors, destructive actions, urgent |
| `info`    | `#3B82F6` | Informational, links, external      |

Each status color has a soft background variant:
- `successSoft` = `#ECFDF5`
- `warningSoft` = `#FEF3C7`
- `errorSoft`   = `#FEE2E2`
- `infoSoft`    = `#EFF6FF`

### 2.5 Entity Type Colors

Each atom type has a distinct color for canvas blocks, sidebar indicators, and
badges. These are a bespoke, harmonized palette — NOT Tailwind defaults. All colors
sit at consistent saturation (~35-45%) and lightness (~40-50%) so they feel like a
cohesive family, like a set of natural pigments. When multiple block types sit
side-by-side on canvas, they should feel unified, not chaotic.

| Entity     | Icon/Text Color | Soft Background | Usage Metaphor           |
|------------|-----------------|-----------------|--------------------------|
| Ideas      | `#6B6EA8`       | `#EDEDF5`       | Muted indigo (starlight) |
| Research   | `#4A8B72`       | `#E5F0EB`       | Sage green (discovery)   |
| Content    | `#5B84B0`       | `#E8EFF5`       | Steel blue (craft)       |
| Notes      | `#9B8A6E`       | `#F2EDE5`       | Warm taupe (paper, ink)  |
| Connections| `#8B6BAB`       | `#EDE8F2`       | Muted violet (weaving)   |
| Swipe File | `#B08C5A`       | `#F2EBE0`       | Burnished gold (archive) |
| Cosmo AI   | `#2D6A4F`       | `#E8F5EC`       | Forest green (the brand) |
| Tasks      | `#B06B6B`       | `#F5E8E8`       | Muted rose (urgency)     |

**Design rationale:** Every entity color is desaturated enough to read as
"category tint" rather than "color shouting." On a white card with a 3px left
bar, these register as gentle identification marks. Side-by-side on canvas, they
create a calm, varied but harmonious landscape — like looking at a bookshelf
with different-colored spines.

**Rules:**
- Entity color appears as: 3px left bar on canvas blocks, small dot/badge in lists,
  icon tint in sidebar, tag background
- Entity color NEVER fills an entire card or section background
- On canvas blocks, use `surface` (#FFFFFF) bg + entity left bar + entity icon tint
- In sidebars, selected entity row gets `entitySoft` bg + `entity` text
- Canvas left bar uses the same color as icon/text (no separate column needed)

### 2.6 Dimension Colors (Sanctuary)

Used only in the Sanctuary hub for the six life dimensions. These are the vivid
versions — they provide the only "colorful" area in the app.

| Dimension      | Base Color | Light Variant | Soft Background |
|----------------|------------|---------------|-----------------|
| Cognitive      | `#6366F1`  | `#818CF8`     | `#EEF2FF`       |
| Creative       | `#D97706`  | `#FBBF24`     | `#FEF3C7`       |
| Physiological  | `#059669`  | `#34D399`     | `#ECFDF5`       |
| Behavioral     | `#2563EB`  | `#60A5FA`     | `#EFF6FF`       |
| Knowledge      | `#7C3AED`  | `#A78BFA`     | `#F5F3FF`       |
| Reflection     | `#DB2777`  | `#F472B6`     | `#FDF2F8`       |

### 2.7 Borders

Borders are neutral gray — not warm (which would clash with the cool green accent)
and not cold blue. Temperature-neutral so they pair with any accent or entity color.

| Token          | Value                     | Usage                                   |
|----------------|---------------------------|-----------------------------------------|
| `border`       | `#DCDCE0`                 | Card borders, input borders, dividers   |
| `borderSubtle` | `#E8E8EC`                 | Section dividers, faint separations     |
| `borderActive` | `#C8C8CC`                 | Focused inputs, active states           |
| `focusRing`    | `accent` at 0.25 opacity  | Keyboard focus indicator (3px ring)     |

**Semantic color alternative:** Where possible, prefer `Color(nsColor: .separatorColor)`
for standard dividers and `Color(nsColor: .gridColor)` for grid lines. These
automatically adapt to accessibility settings (Increase Contrast), display color
profiles, and vibrancy states. Use fixed hex tokens only when the semantic color
doesn't match the design intent.

**Rules:**
- All borders are 1px. Never 0.5px (invisible on non-retina), never 2px (too heavy)
- Cards: 1px `border` on all sides
- Inputs: 1px `border`, transitions to 1px `accent` at 0.3 opacity on focus
- Section dividers: 1px `borderSubtle`, horizontal only
- NO gradient borders in light mode — those were a dark-mode technique that
  simulated light reflection. In light mode, a simple 1px neutral gray border is
  cleaner and more Apple-like

### 2.8 Shadows

Two-layer system: contact shadow (tight, close) + ambient shadow (soft, large).
Apple's shadow philosophy — natural, as if light comes from directly above.

| Token     | Contact Layer                    | Ambient Layer                     | Usage        |
|-----------|----------------------------------|-----------------------------------|--------------|
| `resting` | 0 1px 2px rgba(0,0,0,0.04)      | 0 4px 8px rgba(0,0,0,0.02)       | Cards at rest |
| `hover`   | 0 2px 4px rgba(0,0,0,0.05)      | 0 8px 16px rgba(0,0,0,0.04)      | Card hover    |
| `floating`| 0 4px 8px rgba(0,0,0,0.06)      | 0 16px 32px rgba(0,0,0,0.05)     | Modals, menus |
| `toolbar` | 0 1px 3px rgba(0,0,0,0.06)      | —                                 | Toolbars      |

**In SwiftUI:**
```swift
// Resting shadow
.shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
.shadow(color: .black.opacity(0.02), radius: 8, x: 0, y: 4)

// Hover shadow
.shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
.shadow(color: .black.opacity(0.04), radius: 16, x: 0, y: 8)

// Floating shadow (modals, popovers)
.shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
.shadow(color: .black.opacity(0.05), radius: 32, x: 0, y: 16)
```

**Rules:**
- Shadows are ALWAYS neutral black. Never colored shadows (no green glows).
  Exception: focus ring uses `accentGlow`
- All shadows use y-offset only (light from above). No x-offset.
- Shadow intensity is very low — barely visible at rest, slightly more on hover.
  The Apple approach: you FEEL the depth more than you SEE it.
- Cards that are ON `bg` get `resting` shadow
- Floating UI (modals, menus, popovers) gets `floating` shadow
- Toolbars get `toolbar` shadow (single layer, very subtle)

---

## 3. Typography

All text uses SF Pro (the macOS system font). No custom fonts. Apple's font is
designed for this exact use case — reading, note-taking, creative work.

### 3.1 Type Scale

SF Pro automatically activates optical sizes — at small sizes the letterforms
open up for legibility, at large sizes they tighten for elegance. Tracking values
below are ADDITIONAL adjustments on top of SF Pro's built-in optical sizing.

| Token         | Size | Weight    | Color          | Tracking  | Usage                   |
|---------------|------|-----------|----------------|-----------|-------------------------|
| `heroMetric`  | 48px | Ultralight| `text`         | -0.03em   | Sanctuary hero numbers  |
| `pageTitle`   | 28px | Semibold  | `text`         | -0.02em   | Page/view titles        |
| `navTitle`    | 14px | Medium    | `text`         | 0         | Nav bar titles          |
| `cardTitle`   | 15px | Medium    | `text`         | -0.005em  | Card headings           |
| `body`        | 15px | Regular   | `text`         | 0         | Editor text, body copy  |
| `sectionDesc` | 13px | Regular   | `textSecondary`| 0         | Section descriptions    |
| `buttonText`  | 13px | Medium    | varies         | 0.01em    | Button labels           |
| `cardMeta`    | 12px | Regular   | `textSecondary`| 0         | Card metadata, dates    |
| `sectionLabel`| 11px | Semibold  | `textMuted`    | 0.08em    | Section headers (UPPER) |
| `caption`     | 11px | Regular   | `textMuted`    | 0.01em    | Timestamps, counts      |
| `navBadge`    | 10px | Medium    | `textSecondary`| 0.02em    | Badge counts            |

**Tracking rationale:** Large sizes (28px+) use negative tracking to feel tighter
and more editorial. Small sizes (11px) use positive tracking for legibility. Medium
sizes (13-15px) use near-zero tracking — SF Pro's defaults are already optimized.

### 3.2 Line Height

- Body text: 1.5 (professional tool density — Craft-like, not blog-like)
- Card content: 1.4
- Headings: 1.2
- Single-line labels: 1.0
- Editor text (content/notes): 1.55 (slightly more generous for sustained writing)

### 3.3 Typography Rules

- **Minimum readable font size: 11px.** Nothing smaller. Ever.
- Section labels are ALWAYS uppercase with 0.08em tracking
- No italic text for emphasis — use weight change (regular → medium).
  Exception: ghost suggestions in connection sections use italic for "suggested" feel.
- Body text in editors uses 15px for optimal reading on macOS
- Monospaced text (code, tokens, counts): SF Mono 12px
- Leverage SF Pro's optical sizes feature — use `.font(.system(size:weight:design:))`
  which automatically activates optical sizing at 20px+

---

## 4. Spacing & Layout

Based on a 4px base grid, with an 8px system for most spacing decisions.

### 4.1 Spacing Scale

| Token  | Value | Usage                                           |
|--------|-------|-------------------------------------------------|
| `xs`   | 4px   | Icon-to-label gap, inline element spacing        |
| `sm`   | 8px   | Between related items in a group                 |
| `md`   | 12px  | Between items in a list, inner card padding      |
| `lg`   | 16px  | Standard section inner padding                   |
| `xl`   | 24px  | Between sections within a view                   |
| `2xl`  | 32px  | Major section breaks                             |
| `3xl`  | 48px  | Page section breaks, between major groups        |

### 4.2 Layout Constants

| Constant        | Value  | Usage                                     |
|-----------------|--------|-------------------------------------------|
| `pageMargin`    | 40px   | Left/right margins on full-width views    |
| `cardPadding`   | 18px   | Inner padding of cards                    |
| `sectionSpacing`| 36px   | Vertical space between major sections     |
| `sidebarWidth`  | 280px  | Standard sidebar width (focus modes)      |
| `sidebarMinWidth`| 260px | Minimum sidebar width                     |
| `sidebarMaxWidth`| 360px | Maximum sidebar width (if resizable)      |

### 4.3 Spacing Rules

- Between a section label and its content: 12px
- Between items in a vertical list: 8px
- Between a card's title and its body: 8px
- Between a card's body and its footer/metadata: 12px
- Inside buttons: 7px vertical, 14px horizontal (small), 10px / 20px (large)
- Icon-to-text inside buttons: 6px
- Page content top padding: 24px (below nav bar)

---

## 5. Corner Radii

Three values. Consistency over creativity.

| Token    | Value | Usage                                           |
|----------|-------|-------------------------------------------------|
| `small`  | 8px   | Buttons, inputs, tags, badges, chips            |
| `medium` | 12px  | Cards, canvas blocks, sidebar sections          |
| `large`  | 16px  | Modals, floating panels, sidebars, sheets       |

**Rules:**
- Nested elements reduce radius: card (12px) contains button (8px)
- Canvas blocks: 12px
- Modals/sheets: 16px
- Tooltips: 6px
- Full-round: Capsule() for badges and pills

---

## 6. Materials & Surfaces

Light mode materials are beautiful and should be used where appropriate.

| Material              | Usage                                               |
|-----------------------|-----------------------------------------------------|
| `.regularMaterial`    | Sidebars that overlay content, floating panels       |
| `.thinMaterial`       | Popovers, floating toolbars                          |
| `.bar`                | Navigation bars, toolbars at edges                   |
| Solid `surface`       | Cards, editors, content areas (readability first)    |
| Solid `bg`            | Page backgrounds, workspace areas                    |
| Solid `surfaceSecondary`| Sidebar backgrounds when not using material         |

**Rules:**
- Use materials ONLY on surfaces that float OVER other content (sidebars,
  overlays, popovers). Material looks gorgeous in light mode because it blurs the
  colorful content behind it.
- Content areas (editors, text fields) are ALWAYS solid white. No material.
  Reading text through frosted glass is terrible.
- The canvas background is solid `canvas` (#F2F1ED). Canvas blocks are solid
  `surface` (#FFFFFF) with shadow. No material on the canvas.

---

## 7. Film Grain Texture

Inspired by Eden's organic aesthetic. A subtle noise overlay that gives surfaces
warmth and character — like the texture of quality paper.

**Implementation:** Pre-rendered static noise image, tiled, overlaid at low opacity.

| Surface              | Grain Opacity | Notes                           |
|----------------------|---------------|---------------------------------|
| Canvas background    | 0.025         | Subtle paper-like texture       |
| Sanctuary hero area  | 0.03          | Slightly stronger, atmospheric  |
| Card surfaces        | 0             | Cards are clean, no grain       |
| Editors/inputs       | 0             | Content areas always pristine   |
| Sidebars             | 0             | Clean chrome, no texture        |

**Grain characteristics:**
- Monochromatic (black dots on transparent)
- Very fine (1px dots)
- Static (not animated — that would be distracting)
- Density: approximately 1 dot per 100 square pixels
- Applied via `.overlay()` with `.allowsHitTesting(false)`

---

## 8. Animation & Motion

All animations use ProMotion-optimized springs. These values are already defined
and should NOT change — they're physics-based and feel natural at both 60Hz and
120Hz.

### 8.1 Spring Tokens (keep existing)

| Token             | Response | Damping | Usage                           |
|-------------------|----------|---------|----------------------------------|
| `snappy`          | 0.12s    | 0.82    | Taps, toggles, instant feedback  |
| `bouncy`          | 0.25s    | 0.68    | Playful emphasis, celebrations   |
| `gentle`          | 0.35s    | 0.85    | Ambient changes, background      |
| `hover`           | 0.15s    | 0.78    | Mouse hover responses            |
| `press`           | 0.08s    | 0.92    | Button press                     |
| `cardEntrance`    | 0.40s    | 0.75    | Cards appearing in lists         |
| `focusTransition` | 0.30s    | 0.82    | Focus mode entry/exit            |
| `modal`           | 0.35s    | 0.80    | Modal/sheet presentation         |

### 8.2 Motion Rules

- **Card hover:** Shadow lift (resting → hover shadow) + subtle `surfaceHover`
  background tint. NO scale — at typical card sizes (320px), scale values below
  1.02 are subpixel and imperceptible. Apple uses shadow lift, not scale.
- **Button hover:** Background tint change (transparent → surfaceHover).
  For primary buttons: bg darkens (accent → accentHover).
- **Press scale:** 0.97 (quick bounce-in, perceptible)
- **Card entrance:** Fade in + slide up 8px, staggered by 30ms per item
- **Sidebar reveal:** Slide from edge, `focusTransition` spring
- **Modal:** Fade in + scale from 0.95, `modal` spring
- **Page transitions:** Cross-fade, 0.2s ease-out
- **NEVER:** Rotation for UI elements, parallax effects, continuous animation
  (except loading states), scale-on-hover for cards

### 8.3 Accessibility Motion

When `accessibilityReduceMotion` is enabled:
- All springs → instant (no animation), or `easeOut(duration: 0.15)` for essential
  transitions (modal open/close, sidebar reveal) where removing animation entirely
  would be disorienting
- No stagger delays
- No scale effects
- No slide-up entrances — use fade only
- Film grain is static (already non-animated, but confirm)

When `accessibilityReduceTransparency` is enabled:
- `.regularMaterial` → solid `DS.surfaceSecondary` (#F5F4F0)
- `.thinMaterial` → solid `DS.surface` (#FFFFFF)
- All material-based surfaces fall back to their solid equivalent
- No visual quality loss — the solid fills match the design intent

```swift
// Pattern for material fallback:
@Environment(\.accessibilityReduceTransparency) private var reduceTransparency

.background(
    reduceTransparency
        ? AnyShapeStyle(DS.surfaceSecondary)
        : AnyShapeStyle(.regularMaterial)
)
```

### 8.3 Dynamic Type

Body text respects Dynamic Type — when a user increases their system font size,
paragraph body text, card descriptions, and editor content scale accordingly.
Fixed sizes are used only for chrome elements (buttons, labels, badges, tab
titles, toolbar icons, timestamps) where layout stability matters more than
scalability. This keeps the UI structurally stable while ensuring reading
comfort scales with user preference.

---

## 9. Component Library

### 9.1 Buttons

**Primary Button (main CTA):**
```
Background: accent (#2D6A4F)
Text: textOnAccent (#FFFFFF), 13px medium
Padding: 10px vertical, 20px horizontal
Radius: 8px
Shadow: 0 2px 4px accentGlow
Hover: accentHover (#245943) bg
Press: scale 0.97
```

**Secondary Button:**
```
Background: surfaceHover (#F0EFEB)
Text: accent (#2D6A4F), 13px medium
Padding: 7px vertical, 14px horizontal
Radius: 8px
Border: none
Hover: border 1px borderActive (#C8C8CC)
```

**Ghost Button:**
```
Background: transparent
Text: textSecondary (#6B6B78), 13px medium
Padding: 7px vertical, 14px horizontal
Radius: 8px
Border: 1px border (#DCDCE0)
Hover: surfaceHover bg, text → text color
```

**Destructive Button:**
```
Background: errorSoft (#FEE2E2)
Text: error (#DC3545), 13px medium
Padding: 7px vertical, 14px horizontal
Radius: 8px
Hover: error bg, textOnAccent text
```

**Icon Button (toolbar/nav):**
```
Background: transparent
Icon: textSecondary (#6B6B78), 14px
Frame: 28x28
Hover: surfaceHover bg, 6px radius
Active: accent (#2D6A4F) icon color
```

### 9.2 Cards

**Standard Card:**
```
Background: surface (#FFFFFF)
Border: 1px border (#DCDCE0)
Radius: 12px
Padding: 18px
Shadow: resting
Hover: hover shadow
```

**Entity Card (canvas block, sidebar card):**
```
Same as Standard Card, plus:
Left bar: 3px wide, entity color, inside border radius, 8px inset from top/bottom
```

**Interactive Card (clickable):**
```
Same as Standard Card, plus:
Hover: hover shadow, surfaceHover very subtle background tint
Cursor: pointer
Active: scale 0.995
```

**Selected Card:**
```
Same as Standard Card, plus:
Border: 2px accent at 0.3 opacity (replaces standard border)
Background: accentSoft (#E8F5EC) very subtle tint
```

### 9.3 Inputs

**Text Field:**
```
Background: surface (#FFFFFF)
Border: 1px border (#DCDCE0)
Radius: 8px
Padding: 10px horizontal, 8px vertical
Text: text (#1A1A1F), 14px regular
Placeholder: textMuted (#767685)
Focused: border → 2px accent at 0.3 opacity, shadow → 0 0 0 3px accentGlow
```

**TextEditor (multi-line):**
```
Same as Text Field, plus:
Min height: 80px
Line height: 1.6
Scrollable: vertical
```

**Search Field:**
```
Same as Text Field, plus:
Leading icon: magnifyingglass, textMuted, 14px
Padding-left: 36px (icon space)
Radius: 10px (slightly larger for standalone search)
```

### 9.4 Tags & Badges

**Tag (entity type, filter chip):**
```
Background: entity soft color
Text: entity color, 11px medium
Padding: 4px vertical, 8px horizontal
Radius: capsule (full round)
Border: none
```

**Badge (count):**
```
Background: accent (#2D6A4F)
Text: textOnAccent (#FFFFFF), 10px bold
Min width: 18px
Height: 18px
Radius: capsule
```

**Status Badge:**
```
Background: status soft color
Text: status color, 10px medium
Padding: 3px vertical, 8px horizontal
Radius: capsule
```

### 9.5 Menus & Dropdowns

**Context Menu / Dropdown:**
```
Background: surface (#FFFFFF)
Border: 1px border (#DCDCE0)
Radius: 10px
Shadow: floating
Padding: 4px
Min width: 200px
```

**Menu Item:**
```
Text: text (#1A1A1F), 13px regular
Icon: textSecondary, 13px
Padding: 8px vertical, 12px horizontal
Radius: 6px (for hover highlight)
Hover: surfaceHover (#F0EFEB) bg
Destructive item: error (#DC3545) text and icon
```

**Menu Divider:**
```
Height: 1px
Color: borderSubtle (#EEEDE9)
Margin: 4px vertical
```

### 9.6 Tooltips

```
Background: #1A1A1F (dark, inverted)
Text: #FFFFFF, 11px regular
Padding: 6px vertical, 10px horizontal
Radius: 6px
Shadow: floating
Max width: 240px
Delay: 500ms
```

### 9.7 Progress Indicators

**Linear Progress Bar:**
```
Track: borderSubtle (#EEEDE9), 4px height, capsule
Fill: accent (#2D6A4F), capsule
Animated: spring gentle
```

**Circular Progress:**
```
Track: borderSubtle (#EEEDE9), 3px stroke
Fill: accent (#2D6A4F), 3px stroke, rounded cap
```

**Shimmer Loading:**
```
Base: surfaceHover (#F0EFEB)
Shimmer: gradient white at 0.3 → 0 → 0.3 opacity
Animation: linear 1.5s repeat, left-to-right
Radius: 6px
```

### 9.8 Empty States

```
Icon: textMuted (#767685), 32px
Title: textSecondary (#6B6B78), 15px medium
Description: textMuted (#767685), 13px regular, centered
CTA button: ghost style
Vertical padding: 48px
Max width: 280px
```

### 9.9 Dividers

**Section Divider:**
```
Height: 1px
Color: borderSubtle (#EEEDE9)
Full width (edge to edge within parent padding)
```

**Sidebar Divider:**
```
Height: 1px
Color: borderSubtle (#EEEDE9)
Horizontal padding: 16px each side (inset from edges)
```

### 9.10 Toggles & Switches

Use macOS system toggle with accent tint:
```
Toggle("Label", isOn: $value)
    .tint(DS.accent)
```
Do NOT build custom toggles. The system toggle responds to accessibility settings,
accent color preferences, and keyboard focus automatically.

### 9.11 Segmented Controls

```
Background: surfaceHover (#F0EFEB), capsule shape
Selected segment: surface (#FFFFFF), resting shadow, capsule
Text: textSecondary (inactive), text (active), 12px medium
Padding: 2px outer, 6px vertical / 12px horizontal per segment
Animation: snappy spring
```

Use SwiftUI `Picker` with `.segmented` style where possible. For custom
segmented controls, match this spec exactly.

### 9.12 Sheets & Modals

**Full Sheet:**
```
Background: bg (#F8F7F4)
Radius: 16px top corners
Shadow: floating
Drag indicator: borderActive, 36px wide, 4px tall, capsule, centered
Animation: modal spring
```

**Partial Sheet (Inspector):**
```
Background: surface (#FFFFFF)
Width: 320-400px
Border-left: 1px borderSubtle
Shadow: toolbar
No radius (flush with window edge)
```

### 9.13 Error States

**Input Error:**
```
Border: 1px error (#DC3545) at 0.5 opacity (replaces normal border)
Error message: error color, 11px regular, 4px below input
Icon: exclamationmark.circle, error color, 12px, inside input trailing edge
```

**Inline Error Banner:**
```
Background: errorSoft (#FEE2E2)
Text: error (#DC3545), 13px regular
Icon: exclamationmark.triangle, error color, 14px
Padding: 12px
Radius: 8px
Border: 1px error at 0.2 opacity
```

### 9.14 Scrollbars

Use system default scrollbar styling. Do not customize. macOS scrollbars are
already beautiful and users expect standard behavior.

---

## 10. Surface Specifications

### 10.1 Thinkspace Canvas

The spatial workspace where blocks float. Should feel like a clean, warm desk.

```
Background: canvas (#F2F1ED)
Grid dots: #D8D7D3 (barely visible, every 20px)
Film grain: 0.025 opacity overlay
Zoom range: 25% - 400%
```

**Canvas Blocks:**
```
Background: surface (#FFFFFF)
Border: 1px border (#DCDCE0)
Radius: 12px
Shadow: resting (at rest), hover (on hover), floating (while dragging)
Left accent bar: 3px, entity color, 8px inset from top/bottom
Selected: 2px entity color at 0.35 opacity border
Corner resize handle: textMuted icon, appears on hover
```

**Connection Lines (Knowledge Pulse):**
```
Stroke: textMuted (#767685) at 0.4 opacity (inactive)
Stroke: accent (#2D6A4F) at 0.6 opacity (active/pulsing)
Width: 1.5px
Style: bezier curve with control points
Pulse: subtle opacity oscillation 0.4-0.7
Arrow: small triangle at target end
```

**Canvas Minimap:**
```
Background: surface (#FFFFFF) at 0.95 opacity
Border: 1px border (#DCDCE0)
Radius: 12px
Shadow: floating
Block dots: entity colors, 4px diameter
Viewport rect: accent (#2D6A4F), 1.5px stroke
```

**Cluster Zones:**
```
Background: cluster color at 0.06 opacity
Border: cluster color at 0.15 opacity, 1.5px, dashed (4, 4)
Radius: 16px
Label: cluster color, 11px medium, capsule badge
```

**Block Context Menu:**
```
Standard menu styling (section 9.5)
Header: entity dot + title, textSecondary, 11px medium
Width: 200px
```

**Canvas Toolbar (top-right):**
```
Background: surface (#FFFFFF)
Border: 1px border (#DCDCE0)
Radius: 10px
Shadow: toolbar
Padding: 4px
Button size: 28x28
Button hover: surfaceHover bg, 6px radius
```

**Drawing Tools:**
```
Toolbar: same as canvas toolbar
Color palette: system colors (#FF3B30, #FF9500, #FFCC00, #34C759, etc.)
  plus black (#1A1A1F) and gray (#767685)
Active tool: accent (#2D6A4F) icon color
Inactive: textMuted icon color
Width selector: simple dots (3px, 5px, 8px stroke width indicators)
```

### 10.2 Focus Modes

Deep work spaces. Maximum calm, minimum chrome.

**Shared Layout:**
```
Background: bg (#F8F7F4)
Content area: surface (#FFFFFF) — full editor region
Top bar: surface (#FFFFFF), 1px borderSubtle bottom border, 48px height
Bottom bar (if used): surface (#FFFFFF), 1px borderSubtle top border
```

**Sidebar (UniversalFocusSidebar):**
```
Background: .regularMaterial (frosted glass — content shows through beautifully)
Width: 280px
Radius: 16px (inner edge only, via leading clip)
Shadow: floating
Close on click-outside (standalone), button toggle (pane mode)
```

**Sidebar Inner Content:**
```
Section labels: sectionLabel style (11px, uppercase, textMuted)
Section spacing: 24px between sections
Inner cards: surfaceSecondary (#F5F4F0) bg, 1px borderSubtle, 8px radius
Inner inputs: surface (#FFFFFF) bg, 1px border, 8px radius
Focused input: 2px accent at 0.3 opacity border
Minimum font: 11px — nothing smaller
Card padding: 12px
Item spacing: 8px
```

**Floating Overlays (action bars, AI panels, query inputs):**
```
Background: .thinMaterial (floats over content)
Border: 1px border (#DCDCE0)
Radius: 10px
Shadow: floating
```

**Content Focus Mode specifics:**
```
Editor: surface (#FFFFFF), full height, 15px body text, line-height 1.55
Pipeline bar: surface bg, entity phase dots, bottom bar
Outline sidebar content: standard sidebar inner content rules
Polish sidebar: standard sidebar inner content rules
Context panel: standard sidebar inner content rules
AI action bar: floating overlay rules
```

**Research Focus Mode specifics:**
```
Video/transcript area: surface bg
Annotation cards: standard card rules
Tab bar: surface bg, accent underline on active, 13px medium labels
Query input panel: floating overlay rules
```

**Connection Focus Mode specifics:**
```
Section cards (Goal, Problems, Benefits, etc.):
  Background: surface (#FFFFFF)
  Border: 1px border (#DCDCE0)
  Radius: 12px
  Shadow: resting
  Top highlight: none (light mode doesn't need fake light simulation)
  Header: entity accent icon, 14px semibold title
  Items: 13px body, 6px bullet in accent color
  Ghost suggestions: textSecondary, italic, dashed 1px border
Relation overlay: floating overlay rules
```

**Idea Focus Mode specifics:**
```
Editable idea area: standard editor (surface bg, body text)
Status pipeline: accent bg for active phase, borderSubtle for inactive
Intelligence panel: standard sidebar inner content rules
```

**Notes Focus Mode specifics:**
```
Full editor: surface bg, body text, minimal chrome
Formatting toolbar: surface bg, icon buttons
```

**Swipe Study Focus Mode specifics:**
```
No sidebar. Full-width teardown.
Teardown cards: standard card rules
Gold accent for swipe-specific elements: #B45309
Analysis sections: standard card rules
```

**CosmoAI Focus Mode specifics:**
```
Conversation area: bg (#F8F7F4) background
User messages: accent (#2D6A4F) bg, textOnAccent text, 12px radius
AI messages: surface (#FFFFFF) bg, 1px border, 12px radius
Input bar: surface bg, 1px border, bottom of view
Context chips: accentSoft bg, accent text, capsule
```

### 10.3 Sanctuary Hub

The home screen. The one area where the app can be more expressive.

```
Background: bg (#F8F7F4)
Hero section: subtle green gradient (#E8F5EC → bg) with film grain (0.03)
Hero metric (Cosmo Index): heroMetric typography, accent color
Dimension cards: standard card rules, with dimension color left bar
Satellite nodes: dimension base color, soft glow
Connection threads: textMuted at 0.2 opacity → accent at 0.4 (active)
Greeting text: pageTitle typography
Subtitle: sectionDesc typography, textSecondary
```

### 10.4 Plannerum

Task management and time blocking. Clean and functional.

```
Background: bg (#F8F7F4)
Day timeline: surface (#FFFFFF) bg
Hour lines: borderSubtle
Half-hour lines: borderSubtle at 0.5 opacity
Now marker: success (#38B764), 2px horizontal line, circle dot
Time blocks: surface (#FFFFFF), dimension color left bar, resting shadow
Quarter view: standard card rules for objective cards
```

**Session Timer Bar:**
```
Background: surface (#FFFFFF)
Border: 1px border
Radius: 16px
Shadow: floating
Height: 56px
Timer text: 20px bold monospaced, text color
Status: success dot when running, warning dot when paused
Fixed to bottom of screen, centered
```

**Quest Panel:**
```
Standard card rules
Quest rows: standard list item rules
Streak badge: warningSoft bg, warning text
Progress: linear progress bar (accent fill)
```

### 10.5 Command-K Modal

```
Backdrop: Color.black.opacity(0.3) fullscreen overlay
Container: surface (#FFFFFF), 20px radius, floating shadow
Size: 680px wide, max 70% viewport height
Search bar: 56px height, 16px text, textMuted icon
Divider: 1px borderSubtle below search
Results: scrollable list, standard list item styling
Tab bar: 13px medium, accent underline on active tab
Gallery cards: standard card rules with entity colors
```

### 10.6 Cosmo AI Window (floating panel)

```
Background: surface (#FFFFFF)
Width: 400px
Border: 1px border
Shadow: floating
Radius: 16px (both edges)
Header: surface bg, "Cosmo" 16px semibold, accent icon
Messages: same as CosmoAI focus mode
Input: surface bg, 1px border, 10px radius
Send button: accent icon when text present, textMuted when empty
```

### 10.7 Settings / Preferences

```
Follow macOS system settings style:
Background: bg (#F8F7F4)
Sections: standard card rules
Labels: 13px medium, text color
Values: 13px regular, textSecondary
Toggle: system toggle style (accent tint)
Picker: system picker style
```

### 10.8 Window Chrome (canvas block as window)

For blocks rendered in "window mode" with traffic light buttons:

```
Title bar: surface (#FFFFFF), 1px borderSubtle bottom border, 36px height
Traffic lights: system standard (#FF5F57, #FFBD2E, #28C840), 12px circles
Title: 13px medium, text color
Background: surface (#FFFFFF)
Border: 1px border
Radius: 10px
Shadow: floating
Resize handle: textMuted, appears on hover
```

---

## 11. Iconography

- **System:** SF Symbols exclusively. No custom icon sets.
- **Size:** 14px for toolbar/nav icons, 12px for inline icons, 16-20px for feature icons
- **Weight:** Regular for most, Medium for active/selected states
- **Color:** `textSecondary` at rest, `accent` when active, `textMuted` when disabled
- **Rendering:** `.symbolRenderingMode(.hierarchical)` for multi-color SF Symbols

---

## 12. Interaction States

Every interactive element has exactly four states:

| State    | Visual Change                                          |
|----------|--------------------------------------------------------|
| Rest     | Default appearance                                      |
| Hover    | Subtle bg change (surfaceHover), slight shadow lift     |
| Active   | Scale 0.97, accent color where appropriate              |
| Disabled | 0.4 opacity, no hover response, cursor default          |

**Keyboard focus:**
```
Focus ring: 3px accent at 0.25 opacity outline
Offset: 2px from element edge
Radius: element radius + 2px
Only visible when using keyboard navigation (not mouse clicks)
```

---

## 13. What Stays from Dark Mode

These elements are color-mode agnostic and transfer directly:

- All ProMotionSprings animation values (physics don't change with color)
- All spacing and layout constants
- All corner radii
- All typography sizes and weights
- The 3D tilt hover effect on canvas blocks
- The crystallization glow effect (adjust color to green)
- Canvas zoom and pan mechanics
- Drag-to-connect interaction patterns
- Focus mode layout structures (sidebar + content)
- Pane system architecture

---

## 14. What Changes

| Dark Mode                                | Light Mode                               |
|------------------------------------------|------------------------------------------|
| `#0A0A0F` backgrounds                    | `#F8F7F4` backgrounds                    |
| `#16161F` cards                          | `#FFFFFF` cards                           |
| White text on dark                       | Near-black text on light                  |
| `Color.white.opacity(0.06)` borders      | `#DCDCE0` solid borders                   |
| `Color.white.opacity(0.04)` dividers     | `#EEEDE9` solid dividers                  |
| Gradient borders (fake light reflection) | Simple 1px solid borders                  |
| Top-edge highlight (fake overhead light) | Removed — natural light handles this      |
| `.ultraThinMaterial` on dark = plastic   | `.regularMaterial` on light = gorgeous    |
| Heavy shadows (invisible on dark anyway) | Subtle shadows (visible and effective)    |
| Purple accent (#7C6AFF)                  | Green accent (#2D6A4F)                    |
| Colored glows behind elements            | Clean shadows, no color                   |
| `.foregroundColor(.white)` everywhere    | `DS.text` or `DS.textOnAccent`            |
| Entity colors tuned for dark bg          | Entity colors tuned for light bg          |

---

## 15. Migration Checklist for Agents

When converting any file from dark to light mode:

1. **Replace DS token values** — The DS enum itself will be updated with light
   values. Most files that use DS tokens will automatically look right.

2. **Find `.foregroundColor(.white)`** — Replace with `DS.text` (for general text)
   or `DS.textOnAccent` (for text on green/colored backgrounds).

3. **Find `Color.white.opacity()`** — These were used for borders and glass effects
   on dark backgrounds. Replace with appropriate DS border token or remove.

4. **Find `Color.black.opacity()`** — For shadows, keep but may need opacity
   adjustment. For overlays/scrims, keep. For other uses, evaluate.

5. **Find `.ultraThinMaterial`** — Evaluate each usage:
   - On sidebar/floating panel? → Change to `.regularMaterial` or `.thinMaterial`
   - On card/block? → Change to solid `DS.surface` (#FFFFFF)
   - On overlay/scrim? → Keep or use `Color.black.opacity(0.3)`

6. **Find gradient borders** (`.dsGradientBorder`) — Remove and replace with
   simple `1px DS.border`. Gradient borders were a dark-mode technique.

7. **Find top-edge highlights** (`.dsTopHighlight`) — Remove entirely. Not needed
   in light mode — natural light and shadows provide depth.

8. **Find `.dsPremiumCard()` / `.dsPremiumSection()`** — Replace with standard
   card/section styling (surface bg + 1px border + resting shadow).

9. **Find `.dsPremiumShadow()`** — Replace with `.dsRestingShadow()` or
   `.dsFloatingShadow()` depending on context.

10. **Find OnyxColors references** — Replace with DS equivalents:
    - `OnyxColors.Elevation.void/base/raised` → `DS.bg` or `DS.canvas`
    - `OnyxColors.Elevation.elevated/floating` → `DS.surface` or `DS.surfaceSecondary`
    - `OnyxColors.Text.primary/secondary/tertiary` → `DS.text/textSecondary/textMuted`
    - `OnyxColors.Accent.iris` → `DS.accent`

11. **Find CosmoColors references** — Replace with DS equivalents:
    - `CosmoColors.thinkspaceVoid/Secondary/Tertiary` → `DS.canvas` / `DS.surfaceSecondary`
    - `CosmoColors.textPrimary/Secondary/Tertiary` → `DS.text/textSecondary/textMuted`
    - `CosmoColors.lavender` → `DS.accent` (where used as primary accent)

12. **Verify dark-on-light contrast** — Ensure all text passes WCAG AA contrast
    ratio (4.5:1 for normal text, 3:1 for large text).

13. **Test hover states** — Ensure hover is visible (subtle bg change, not just
    color shift that might be invisible on light backgrounds).

14. **Film grain** — Add film grain overlay ONLY to canvas background and sanctuary
    hero area. Nowhere else.

---

## Quick Reference Card

```
BACKGROUNDS     bg #F8F7F4 | canvas #F2F1ED | surface #FFFFFF
TEXT            text #1A1A1F | secondary #6B6B78 | muted #767685
ACCENT          green #2D6A4F | hover #245943 | soft #E8F5EC
BORDERS         border #DCDCE0 | subtle #EEEDE9 | active #C8C8CC
STATUS          success #38B764 | warning #D97706 | error #DC3545
SHADOW          resting 0.04/0.02 | hover 0.05/0.04 | floating 0.06/0.05
RADIUS          small 8 | medium 12 | large 16
SPACING         xs 4 | sm 8 | md 12 | lg 16 | xl 24 | 2xl 32 | 3xl 48
FONT            body 15 | card 15med | meta 12 | button 13med | caption 11
```
