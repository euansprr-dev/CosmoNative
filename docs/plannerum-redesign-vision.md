# Plannerum Redesign: The Time Realm

## Overview

Transform the Plannerum from a flat, utilitarian interface into an immersive "Time Realm" that matches the Sanctuary's aesthetic quality. The Plannerum should feel like stepping into a cosmic space where time flows visually, tasks exist as constellations, and the user is the master of their temporal domain.

---

## Current State vs. Vision

### Current Problems
```
┌─────────────────────────────────────────────────────────────────────┐
│ [Sanctuary]  P L A N E R I U M                  [Day|Week|Month]    │  ← Flat header, no XP
│              Shape your next chapter                      Level 1   │  ← Disconnected level badge
├──────────┬──────────────────────────────────────────────────────────┤
│ INBOXES  │                                                          │
│ ────────  │                    12                                   │  ← No hour dividers
│[All][Tasks]│                   13                                   │  ← Flat gray background
│           │                    14                                   │  ← Hard vertical cut
│ Ideas   0 │                    15                                   │
│ Tasks   0 │               NOW 17                                    │  ← Generic now marker
│ Content 0 │                    18                                   │
│           │                    19                                   │
│           │                    20                                   │
│ ✓ All clear│                                                        │  ← Unnecessary message
│ Nothing...│                                                         │
├──────────┴──────────────────────────────────────────────────────────┤
│ ● NO ACTIVE BLOCK   Schedule or start a block to begin      +0 XP  │  ← Flat bar, not immersive
└─────────────────────────────────────────────────────────────────────┘
```

### Target Vision
```
╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                            ║
║  ◈ PLANNERUM                                              ● LIVE          ║
║  Level 24  •  Pathfinder                                 Focus    78%     ║
║  ████████████████░░░░ 78%  ·  XP: 12.8K / 16K           Energy   85%     ║
║                                                                            ║
╠════════════════════════════════════════════════════════════════════════════╣
║         ╭──────────╮                                                       ║
║         │  INBOXES │                ⟨ Day ⟩  Week   Month   Quarter       ║
║         │ ┈┈┈┈┈┈┈┈ │                                                       ║
║         │          │          SUNDAY, DECEMBER 22                          ║
║         │ ◈ Ideas  │          ═══════════════════                          ║
║         │   ⌄ [3]  │                                                       ║
║         │          │     ┊                                                 ║
║         │ ◇ Tasks  │  05 ┊ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─                          ║
║         │   ⌄ [7]  │     ┊                                                 ║
║         │          │  06 ┊ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─                          ║
║         │          │     ┊                                                 ║
║         │ ─────────│  09 ┊ ╭────────────────────────╮                      ║
║         │ PROJECTS │     ┊ │  ◆ DEEP WORK          │                      ║
║         │          │  10 ┊ │  Cosmo Development     │                      ║
║         │ ⬡ Cosmo  │     ┊ │  ✦ Core  ·  +125 XP   │                      ║
║         │   [5]    │  11 ┊ ╰────────────────────────╯                      ║
║         │          │     ┊                                                 ║
║         │ ⬡ Client │  12 ┊ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─                          ║
║         │   [2]    │     ┊                                                 ║
║         ╰──────────╯  13 ┊ ════════════════════════════════►              ║
║                          ┊  ● NOW 13:24      ✧ ✧ ✧                        ║
║                       14 ┊ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─                          ║
║                          ┊                                                 ║
║                       15 ┊ ╭────────────────────────╮                      ║
║                          ┊ │  ◈ CREATIVE           │                      ║
║                       16 ┊ │  Content Writing      │                      ║
║                          ┊ │  +95 XP               │                      ║
║                          ┊ ╰────────────────────────╯                      ║
║                                                                            ║
║         ╭───────────────────────────────────────────────────────╮          ║
║         │         ╭─────╮                                       │          ║
║         │    ╭────┤ 🎯  ├────╮       FOCUS NODE                │          ║
║         │    │    ╰─────╯    │       Deep Work: Cosmo          │          ║
║         │ ╭──┴──╮         ╭──┴──╮    ══════════════════        │          ║
║         │ │ ⏱  │         │ ⭐  │    2:45:30 remaining          │          ║
║         │ ╰─────╯         ╰─────╯    +285 XP projected         │          ║
║         │  Skip           Complete                              │          ║
║         ╰───────────────────────────────────────────────────────╯          ║
║                                                                            ║
╚═══════════════════════════════════════════════════════════════════════════╝

        ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
        ░░  Ambient gradient background - void with subtle   ░░
        ░░  violet/indigo nebula glow behind timeline        ░░
        ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
```

---

## Component Redesign Specifications

### 1. Header (Match Sanctuary Exactly)

**Before:**
```
┌─────────────────────────────────────────────────────────────────┐
│ [◀ Sanctuary]  P L A N E R I U M        [Day|Week|Month|Qtr]   │
│                Shape your next chapter            LEVEL 1  0%  │
└─────────────────────────────────────────────────────────────────┘
```

**After:**
```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  PLANNERUM                                         ● LIVE       │
│  Level 24  ·  Pathfinder                          Focus   78%   │
│  ████████████████░░░░░░░░ 78%                     Energy  85%   │
│  XP: 12,840 / 16,000 to Level 25                                │
│                                                                 │
│           ⟨◈ Day ⟩    Week    Month    Quarter                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Specifications:**
- Title: "PLANNERUM" - 28pt bold rounded, 4pt letter tracking
- Level: "Level 24 · Pathfinder" - 14pt medium, Plannerum violet accent for rank
- XP Bar: 8pt height, shimmer animation, violet gradient fill
- XP Text: "XP: current / total to Level X" - 11pt monospace
- Live Panel: Same as Sanctuary (Focus %, Energy %, pulsing green dot)
- View Toggle: Pill-style tabs, glass background, centered below XP bar
- **Remove**: Back button (navigation via satellite nodes), separate level badge top-right

---

### 2. Background: The Time Realm

**Current:** Flat `#12121A` solid fill

**Target:** Layered ambient atmosphere

```
┌─────────────────────────────────────────────────────────────────┐
│  Layer 1: Base Void (#0A0A0F)                                   │
│                                                                 │
│  Layer 2: Radial gradient from center                           │
│           - Center: #6366F1 @ 5% (indigo glow)                  │
│           - Edge: transparent                                   │
│           - Radius: 60% of viewport                             │
│                                                                 │
│  Layer 3: Subtle horizontal flow lines                          │
│           - white @ 2% opacity                                  │
│           - Animate slowly left-to-right (time flowing)         │
│           - Speed: 60s full cycle                               │
│                                                                 │
│  Layer 4: Particle field (optional, very subtle)                │
│           - 15-20 tiny dots                                     │
│           - Drift slowly                                        │
│           - white @ 10% opacity                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

### 3. Inbox Sidebar: Floating Glass Panel

**Before:**
```
┌───────────────┐
│ INBOXES    ↻  │  ← Hard edge, flat background
│ ──────────    │
│[All][Tasks]...│  ← Global filters
│               │
│ ◈ Ideas    0  │
│ ◇ Tasks    0  │
│ ◇ Content  0  │  ← Remove this
│               │
│               │
│    ✓          │
│  All clear    │  ← Remove this
│  Nothing...   │
└───────────────┘
```

**After:**
```
        ╭─────────────────────────╮
        │                         │
        │       I N B O X E S     │
        │       ═════════════     │
        │                         │
        │  ╭───────────────────╮  │
        │  │ ◈ Ideas        [3] │  │
        │  │  ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈  │  │
        │  │  [New] [Archive]   │  │  ← Per-inbox filters
        │  │                    │  │
        │  │  • Landing page    │  │
        │  │  • Newsletter      │  │
        │  │  • Feature ideas   │  │
        │  ╰───────────────────╯  │
        │                         │
        │  ╭───────────────────╮  │
        │  │ ◇ Tasks        [7] │  │
        │  │  ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈  │  │
        │  │  [Due] [Priority]  │  │  ← Per-inbox filters
        │  │                    │  │
        │  │  • Review PR       │  │
        │  │  • Client call     │  │
        │  ╰───────────────────╯  │
        │                         │
        │  ─ ─ ─ PROJECTS ─ ─ ─   │
        │                         │
        │  ╭───────────────────╮  │
        │  │ ⬡ Cosmo        [5] │  │
        │  ╰───────────────────╯  │
        │                         │
        │  ╭───────────────────╮  │
        │  │ ⬡ Client       [2] │  │
        │  ╰───────────────────╯  │
        │                         │
        ╰─────────────────────────╯

         ↑
         Glass panel with:
         - 20pt corner radius
         - white @ 6% fill
         - white @ 12% border (1pt)
         - 8pt blur
         - Soft shadow (black @ 15%, 16pt spread)
         - Floats 24pt from left edge
         - 48pt top margin (below header)
```

**Changes:**
- Remove "Content" inbox (Ideas encompasses content)
- Remove global filter chips (All/Tasks/Ideas/Content)
- Add per-inbox filter chips (contextual to each inbox type)
- Remove "All clear" empty state message
- Floating glass aesthetic with rounded corners
- More breathing room and polish

**Per-Inbox Filters:**
- **Ideas:** `[All] [New] [Archive] [Content]`
- **Tasks:** `[All] [Due] [Priority] [Project]`
- **Projects:** `[All] [Active] [Archive]`

---

### 4. Timeline: The Temporal Canvas

**Before:**
```
TODAY  MONDAY, DECEMBER 22                    [Today] < >

       12

       13

       14

NOW    17
17:46  ●═══════════════════════════════════════►

       18
```

**After:**
```
                  MONDAY, DECEMBER 22
                  ═══════════════════
                  5 blocks · 6h 30m · +450 XP


        05  ┊ · · · · · · · · · · · · · · · · ·
            ┊
        06  ┊ · · · · · · · · · · · · · · · · ·
            ┊
        09  ┊ ╭──────────────────────────────╮
            ┊ │  ◆ DEEP WORK                │
        10  ┊ │  Cosmo Development          │
            ┊ │  ──────────────────         │
        11  ┊ │  09:00 → 11:30  •  2h 30m   │
            ┊ │  ✦ Core Objective           │
            ┊ │  ✨ +125 XP                  │
            ┊ ╰──────────────────────────────╯
            ┊
        12  ┊ · · · · · · · · · · · · · · · · ·
            ┊
        13  ┊ ════════════════════════════════►
            ┊  ● NOW 13:24    ✧ ✧ ✧ (particles)
            ┊
        14  ┊ · · · · · · · · · · · · · · · · ·


        ↑
        Vertical time spine:
        - 1pt white @ 8% opacity
        - Subtle glow at now position
        - Hour labels: 12pt monospace, white @ 50%

        Hour dividers:
        - Dotted line: 1pt dots, white @ 6%
        - Spans full width of timeline
        - Creates gentle rhythm without harshness
```

**Timeline Specifications:**
- **Width:** Reduce from current ~70% to ~55% of viewport
- **Hour Height:** 64pt (unchanged)
- **Time Spine:** 1pt vertical line, white @ 8%, slight indigo glow
- **Hour Labels:** 12pt monospace, white @ 50%, right-aligned to spine
- **Hour Dividers:** Dotted line (2pt dots, 8pt gap), white @ 6%
- **Blocks:** Floating glass cards, offset 16pt from spine
- **Now Bar:** Enhanced glow (24pt blur radius), particle trail

**Block Cards (Glass Morphism):**
```
╭────────────────────────────────────╮
│  ◆ DEEP WORK                       │  ← Type icon + title (15pt semibold)
│  Cosmo Development                 │  ← Project name (13pt, dimmer)
│  ─────────────────────────────     │
│  09:00 → 11:30  ·  2h 30m          │  ← Time range (11pt monospace)
│                                    │
│  ✦ Core    🔥 High    ✨ +125 XP   │  ← Badges row
╰────────────────────────────────────╯

Background: white @ 6%
Border: block-color @ 20% (left edge 4pt accent bar)
Hover: Scale 1.02, border brightens to 40%
Active: Constellation expands from card
```

---

### 5. Focus Node Constellation (Replaces Active Focus Bar)

**Before:**
```
┌─────────────────────────────────────────────────────────────────┐
│ ● NO ACTIVE BLOCK   Schedule or start a block to begin   +0 XP │
└─────────────────────────────────────────────────────────────────┘
```

**After (No Active Block):**
```
        The void is calm. No active focus.
        Tap a block to begin your session.

                    ○ ─ ─ ─ ○
                       ╲   ╱
                        ╲ ╱
                         ○
                    (dormant nodes)
```

**After (Active Block - Expanded from clicked task):**
```

         ╭─────────────────────────────────────────────────╮
         │                                                 │
         │              ╭─────────╮                        │
         │         ╭────┤   🎯    ├────╮                   │
         │         │    │ ACTIVE  │    │                   │
         │         │    ╰─────────╯    │                   │
         │         │         │         │                   │
         │    ╭────┴────╮    │    ╭────┴────╮             │
         │    │    ⏱    │    │    │    ⭐    │             │
         │    │  TIMER  │    │    │ COMPLETE│             │
         │    ╰─────────╯    │    ╰─────────╯             │
         │                   │                             │
         │              ╭────┴────╮                        │
         │              │    ⏭    │                        │
         │              │  SKIP   │                        │
         │              ╰─────────╯                        │
         │                                                 │
         │    ════════════════════════════════════         │
         │                                                 │
         │    DEEP WORK: Cosmo Development                 │
         │    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░ 62%                 │
         │    2:45:30 remaining  ·  +285 XP projected      │
         │                                                 │
         ╰─────────────────────────────────────────────────╯


Animation: When user clicks a time block:
1. Block pulses (0.15s)
2. Constellation nodes fly out from block center (0.4s spring)
3. Connection lines draw in (0.2s each, staggered)
4. Info panel fades up (0.3s)

Node Specifications:
- Size: 56pt diameter
- Background: white @ 8%
- Border: 2pt white @ 20%
- Icon: 24pt SF Symbol
- Glow on hover: block-color @ 30%, 16pt blur
- Connection lines: 2pt, white @ 15%, animated dash
```

**Node Actions:**
- **Center (ACTIVE):** Shows current block icon, pulses when running
- **Left (TIMER):** Shows elapsed/remaining, tap to toggle format
- **Right (COMPLETE):** Mark block as done, triggers XP tracer
- **Bottom (SKIP):** Skip to next block or end session

---

### 6. Quarter View (Wire Up)

**Current:** Placeholder with "coming soon" text

**Target Design:**
```
╔═══════════════════════════════════════════════════════════════════════╗
║                                                                        ║
║                    Q 4   2 0 2 4                                       ║
║                    ═══════════════                                     ║
║                                                                        ║
║     ╭─────────────────────────────────────────────────────────╮        ║
║     │                    CORE OBJECTIVES                      │        ║
║     │                    ════════════════                     │        ║
║     │                                                         │        ║
║     │    ╭──────────────────────────────────────────────╮    │        ║
║     │    │  ◈  Launch CosmoOS Beta                      │    │        ║
║     │    │     ▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░ 58%            │    │        ║
║     │    │     12 blocks completed · 45h invested       │    │        ║
║     │    ╰──────────────────────────────────────────────╯    │        ║
║     │                                                         │        ║
║     │    ╭──────────────────────────────────────────────╮    │        ║
║     │    │  ◇  Complete 100 Deep Work Sessions          │    │        ║
║     │    │     ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░ 78/100            │    │        ║
║     │    │     78 sessions · 156h total                 │    │        ║
║     │    ╰──────────────────────────────────────────────╯    │        ║
║     │                                                         │        ║
║     │    ╭──────────────────────────────────────────────╮    │        ║
║     │    │  ⬡  Reach Level 30                           │    │        ║
║     │    │     ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░ Level 24         │    │        ║
║     │    │     +12,840 XP this quarter                  │    │        ║
║     │    ╰──────────────────────────────────────────────╯    │        ║
║     │                                                         │        ║
║     ╰─────────────────────────────────────────────────────────╯        ║
║                                                                        ║
║                 ─────────────────────────────────────                  ║
║                                                                        ║
║     QUARTER TRAJECTORY                                                 ║
║     ──────────────────                                                 ║
║                                                                        ║
║         Oct        Nov        Dec        Jan                           ║
║          │          │          │          │                            ║
║          ●──────────●──────────●                                       ║
║         12K       24K        42K        60K (target)                   ║
║          └──────────┴──────────┴──────────┘                            ║
║                    XP Trajectory                                       ║
║                                                                        ║
╚═══════════════════════════════════════════════════════════════════════╝
```

**Quarter View Components:**
1. **Quarter Selector:** Q1/Q2/Q3/Q4 tabs with year
2. **Core Objectives Grid:** 3-5 major goals with progress
3. **Trajectory Chart:** XP/completion over time
4. **Floating glass containers** for each section

---

### 7. View Mode Transitions

**Smooth morphing between Day/Week/Month/Quarter:**

```
Day → Week:
- Timeline shrinks horizontally
- Hour rows collapse into day summaries
- Day summaries rise into arc formation
- 0.5s spring animation

Week → Month:
- Arc flattens into grid
- Day orbs shrink to 40pt cells
- Grid arranges in calendar layout
- 0.5s spring animation

Month → Quarter:
- Calendar grid fades
- Core objectives rise from center
- Trajectory chart draws in
- 0.6s cinematic animation
```

---

## Color & Material System

### Plannerum Accent Palette
```
Primary:        #8B5CF6 (Violet)
Primary Light:  #A78BFA
Primary Dark:   #7C3AED
Glow:           #8B5CF6 @ 20%

Block Type Colors (aligned with Sanctuary dimensions):
- Deep Work:    #6366F1 (Cognitive Indigo)
- Creative:     #F59E0B (Creative Amber)
- Output:       #14B8A6 (Teal)
- Planning:     #8B5CF6 (Violet)
- Training:     #EC4899 (Reflection Pink)
- Rest:         #10B981 (Physiological Green)
- Admin:        #3B82F6 (Behavioral Blue)
- Meeting:      #0EA5E9 (Sky)
- Review:       #64748B (Slate)
```

### Glass Materials
```
Panel Glass:
- Fill: white @ 6%
- Border: white @ 12%
- Blur: 8pt
- Corner radius: 20pt

Card Glass:
- Fill: white @ 8%
- Border: white @ 15%
- Blur: 4pt
- Corner radius: 12pt

Button Glass:
- Fill: white @ 10%
- Border: white @ 20%
- Blur: 2pt
- Corner radius: 8pt
- Hover: Fill brightens to 15%
```

---

## Animation Specifications

### Entry Animation (Plannerum loads)
```
1. Background gradient fades in (0.3s)
2. Header slides down from top (0.4s spring)
3. Sidebar floats in from left (0.5s spring, 0.1s delay)
4. Timeline fades up (0.4s, 0.2s delay)
5. Now bar draws in (0.3s, 0.4s delay)
6. Blocks stagger in from now position (40ms between each)
```

### Block Interaction
```
Hover:
- Scale: 1.02
- Shadow: Expands 4pt
- Border: Brightens 10%
- Duration: 0.15s

Press:
- Scale: 0.98
- Duration: 0.08s

Focus (constellation deploy):
- Block pulses once
- Nodes fly out with spring (0.4s, damping 0.7)
- Lines draw between nodes (0.2s each)
- Info panel fades up (0.3s)
```

### Now Bar
```
Pulse cycle: 2.0s
- Dot diameter: 10pt → 14pt → 10pt (sine wave)
- Glow radius: 16pt → 24pt → 16pt
- Particle spawn: Every 150ms
- Particle drift: 30pt over 1.2s, then fade
```

---

## Implementation Priority

### Phase 1: Foundation (Critical Path)
1. ✦ Match header to Sanctuary style
2. ✦ Add realm background (gradient + subtle animation)
3. ✦ Add hour divider lines to timeline
4. ✦ Remove "Content" inbox
5. ✦ Remove "All clear" message
6. ✦ Remove top-right level badge

### Phase 2: Polish
1. ◇ Convert sidebar to floating glass panel
2. ◇ Add per-inbox filters
3. ◇ Reduce timeline width
4. ◇ Enhance block card glass effects

### Phase 3: Constellation
1. ○ Replace ActiveFocusBar with FocusConstellation
2. ○ Add node expansion animation
3. ○ Implement constellation interactions

### Phase 4: Quarter View
1. ○ Create QuarterView component
2. ○ Wire up to view mode switcher
3. ○ Add core objectives UI
4. ○ Add trajectory visualization

---

## Summary

The redesigned Plannerum transforms from a flat utility interface into an immersive "Time Realm" that:

1. **Feels unified** with Sanctuary through shared header style and glass aesthetics
2. **Flows naturally** with ambient background and time visualization
3. **Elevates interactions** through constellation-style focus system
4. **Removes clutter** (no "Content" inbox, no "All clear" message, no redundant level badge)
5. **Adds context** with per-inbox filters instead of global ones
6. **Completes features** by wiring up the Quarter view

The user should feel like they're stepping into a cosmic command center where they are the master of their time, not looking at a flat to-do list.
