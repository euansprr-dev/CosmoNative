# COSMO OS — PLANERIUM TEMPORAL SYSTEM
## Master UI/UX Specification v1.0
### Lead Architect: Claude | December 2025

---

# PART I: DESIGN PHILOSOPHY & SYSTEM ARCHITECTURE

## 1.1 Core Vision Statement

PLANERIUM is the **Temporal Realm of COSMO** — the dimension responsible for time, scheduling, planning, execution, and the critical bridge between intention and XP-generating action.

Planerium is NOT a calendar. It is a **living temporal interface** where time becomes tangible, where tasks transform into progress, and where your schedule breathes with the rhythm of your life.

The experience must feel like:
- **Apple** designed your day's command center
- **SpaceX** mission control built the timeline
- **Destiny** crafted the progression feedback
- **Stripe** engineered the data precision

Every scheduled block serves purpose. Every XP tracer communicates achievement. Every interaction reveals hidden potential.

---

## 1.2 The Planerium Metaphor

Planerium is a **temporal command chamber** — a place where you orchestrate the flow of time across days, weeks, and months.

**Spatial Model:**
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  ┌──────────────┐                                                           │
│  │   HEADER     │  Title, XP Module, View Switcher, Return to Sanctuary    │
│  └──────────────┘                                                           │
│                                                                             │
│  ┌─────────┬───────────────────────────────────────────────────────────┐   │
│  │         │                                                           │   │
│  │  INBOX  │                  TEMPORAL CANVAS                          │   │
│  │  RAIL   │                                                           │   │
│  │         │   ┌─────────────────────────────────────────────────┐    │   │
│  │ Projects│   │                                                 │    │   │
│  │ Ideas   │   │              NOW BAR (glowing)                  │    │   │
│  │ Tasks   │   │              ═══════════════                    │    │   │
│  │         │   │                                                 │    │   │
│  │ Filters │   │   ┌─────────┐  ┌─────────────────┐             │    │   │
│  │ [All]   │   │   │ BLOCK 1 │  │    BLOCK 2      │             │    │   │
│  │ [Tasks] │   │   │ Deep    │  │    Creative     │             │    │   │
│  │ [Ideas] │   │   │ Work    │  │    Output       │             │    │   │
│  │         │   │   └─────────┘  └─────────────────┘             │    │   │
│  │         │   │                                                 │    │   │
│  │ ─────── │   │   DAY / WEEK / MONTH / QUARTER                 │    │   │
│  │ Overdue │   │                                                 │    │   │
│  │         │   └─────────────────────────────────────────────────┘    │   │
│  │         │                                                           │   │
│  └─────────┴───────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │   ACTIVE FOCUS BAR  |  Current Block  |  Timer  |  XP Preview       │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 1.3 Relationship to Other Dimensions

Planerium integrates deeply with:

| System | Integration |
|--------|-------------|
| **Sanctuary** | XP flows from Planerium → Sanctuary. Level, CI, dimensions updated in real-time |
| **ThinkSpace** | Ideas can be dragged from ThinkSpace to Planerium inboxes |
| **Knowledge Graph** | Tasks/ideas have embeddings for semantic linking and auto-categorization |
| **Voice System** | Full voice control for scheduling, block creation, task management |
| **HRV/Cognitive Models** | XP multipliers based on physiological state, optimal window predictions |
| **Causality Engine** | Historical correlations inform scheduling recommendations |

---

## 1.4 Apple Silicon Rendering Pipeline

### Metal 3.1 Architecture (Shared with Sanctuary)

```
┌────────────────────────────────────────────────────────────────┐
│                  PLANERIUM RENDER PIPELINE                      │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐ │
│  │   LAYER 0   │    │   LAYER 1   │    │      LAYER 2        │ │
│  │  Background │───▶│  Now Bar    │───▶│   UI Components     │ │
│  │   (Metal)   │    │  Particles  │    │   (Core Animation)  │ │
│  └─────────────┘    └─────────────┘    └─────────────────────┘ │
│         │                  │                      │             │
│         ▼                  ▼                      ▼             │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              GPU COMPOSITOR (ProMotion 120Hz)               ││
│  │   • XP Tracer Particles via Metal Compute                   ││
│  │   • Now Bar Light Refraction Shader                         ││
│  │   • Glass Blur Surfaces (Variable Radius)                   ││
│  │   • Drag Ghost Rendering with Physics                       ││
│  └─────────────────────────────────────────────────────────────┘│
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              NEURAL ENGINE INTEGRATION                       ││
│  │   • Predictive Scroll Pre-rendering                         ││
│  │   • Optimal Window Computation (HRV + History)              ││
│  │   • XP Forecast Calculation                                 ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
└────────────────────────────────────────────────────────────────┘
```

### Performance Targets

| Metric | Target | Implementation |
|--------|--------|----------------|
| Frame Rate | 120fps sustained | Metal 3.1 + ProMotion sync |
| Scroll Latency | <8ms response | Virtualized timeline rendering |
| XP Tracer Count | 500+ simultaneous | GPU instanced particles |
| Blur Layers | 4 simultaneous | Variable radius Gaussian |
| Memory Footprint | <150MB active | Timeline windowing |
| Battery Impact | <4% per hour active | Idle state coalescing |

---

## 1.5 Global Material Language

### Surface Types (Extends Sanctuary Materials)

```
┌─────────────────────────────────────────────────────────────┐
│                  PLANERIUM MATERIAL SYSTEM                   │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  GLASS-TIMELINE                                              │
│  ├── Background: rgba(12, 12, 18, 0.9)                      │
│  ├── Blur: 32px Gaussian                                     │
│  ├── Border: 1px rgba(255, 255, 255, 0.06)                  │
│  └── Corner Radius: 16px                                     │
│                                                              │
│  BLOCK-SURFACE (Time Blocks)                                 │
│  ├── Background: dimension_color @ 15% opacity               │
│  ├── Blur: 24px Gaussian                                     │
│  ├── Border: 1px dimension_color @ 30%                       │
│  ├── Glow: 0 0 20px dimension_color @ 15%                   │
│  └── Corner Radius: 10px                                     │
│                                                              │
│  NOW-BAR (Current Time Marker)                               │
│  ├── Core: Linear gradient (white → green → transparent)    │
│  ├── Glow: 0 0 40px #22C55E @ 60%                           │
│  ├── Refraction: Metal shader (light bending effect)        │
│  ├── Particle Trail: 20-30 particles following bar          │
│  └── Height: 2px core, 40px glow radius                     │
│                                                              │
│  INBOX-ITEM                                                  │
│  ├── Background: rgba(20, 20, 30, 0.8)                      │
│  ├── Blur: 16px Gaussian                                     │
│  ├── Border: 1px type_color @ 20%                           │
│  └── Corner Radius: 8px                                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Planerium Color System

```
PLANERIUM PRIMARY     #8B5CF6 (Violet)      → Time, Planning, Strategy
NOW MARKER            #22C55E (Green)       → Present, Action, Live
OVERDUE               #EF4444 (Red)         → Urgent, Past Due, Warning

BLOCK TYPES (from Dimensions):
DEEP WORK             #6366F1 (Indigo)      → Cognitive work
CREATIVE              #F59E0B (Amber)       → Creative output
ADMINISTRATIVE        #3B82F6 (Blue)        → Admin, meetings
REST                  #10B981 (Emerald)     → Recovery, breaks
PLANNING              #8B5CF6 (Violet)      → Strategic planning
TRAINING              #EC4899 (Pink)        → Learning, development

INBOX TYPES:
IDEAS                 #8B5CF6 (Violet)      → Knowledge dimension
TASKS                 #6366F1 (Indigo)      → Cognitive dimension
CONTENT               #F59E0B (Amber)       → Creative dimension
PROJECT               #F59E0B (Amber)       → Project-specific
```

---

## 1.6 Typography System

```
HEADER               SF Pro Display    24pt   Bold       0.16em   "PLANERIUM"
SUBHEADER            SF Pro Display    14pt   Medium     0.00em   "Shape your next chapter"
DAY LABEL            SF Pro Display    16pt   Semibold   0.00em   "SUNDAY, DECEMBER 22"
HOUR LABEL           SF Mono           11pt   Medium     0.04em   "14:00"
BLOCK TITLE          SF Pro Text       14pt   Medium     0.00em   Block names
BLOCK DETAIL         SF Pro Text       12pt   Regular    0.01em   Duration, project
INBOX TITLE          SF Pro Text       13pt   Semibold   0.00em   "Ideas", "Tasks"
INBOX COUNT          SF Pro Text       11pt   Bold       0.00em   Badge counts
XP DISPLAY           SF Mono           18pt   Bold       0.02em   "+125 XP"
TIMER                SF Mono           24pt   Bold       0.02em   "01:23:45"
FORECAST             SF Pro Text       12pt   Medium     0.00em   "Projected: 847 XP"
```

---

## 1.7 Motion Design Language

### Timing Functions

```swift
// PLANERIUM Animation Curves (extends Sanctuary)
static let planneriumPrimary = CAMediaTimingFunction(controlPoints: 0.2, 0.0, 0.0, 1.0)
static let planneriumSpring = CASpringAnimation(mass: 1.0, stiffness: 300, damping: 25)
static let planneriumDrag = CASpringAnimation(mass: 0.6, stiffness: 400, damping: 22)
static let planneriumXPTracer = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.2, 1.0)
static let planneriumNowPulse = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.6, 1.0)
```

### Duration Standards

| Transition Type | Duration | Curve |
|-----------------|----------|-------|
| Block hover | 120ms | planneriumPrimary |
| Block drag start | 150ms | planneriumDrag |
| Block drop | 300ms | planneriumSpring |
| View mode switch | 400ms | planneriumSpring |
| XP tracer flight | 800ms | planneriumXPTracer |
| Now bar pulse | 2000ms | planneriumNowPulse |
| Scroll momentum | physics-based | spring damping |
| Inbox expand | 250ms | planneriumPrimary |

---

# PART II: TODAY VIEW (PRIMARY TEMPORAL INTERFACE)

## 2.1 Today View — Full Layout Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ │
│                                                                                             │
│  ◀ Sanctuary          P L A N E R I U M                                   ┌──────────────┐ │
│                       ═════════════════                                   │ XP MODULE    │ │
│                       Shape your next chapter                             │              │ │
│                                                                           │ Level 24     │ │
│                                                          [Day][Week][Month]│ ████████░░░ │ │
│                                                                           │ 78.4%        │ │
│ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄│ 12,847 XP    │ │
│                                                                           └──────────────┘ │
│  ┌──────────────────────────┬──────────────────────────────────────────────────────────────┐│
│  │                          │                                                              ││
│  │  I N B O X E S           │  S U N D A Y ,  D E C E M B E R  2 2                        ││
│  │  ═══════════════         │  ════════════════════════════════════                        ││
│  │                          │  [TODAY] ← →                           5 blocks · 6h 30m    ││
│  │  ┌────────────────────┐  │                                                              ││
│  │  │ ◆ Ideas        (12)│  │  05 ─────────────────────────────────────────────────────   ││
│  │  │   └ New landing... │  │      │                                                       ││
│  │  │   └ Thread about...│  │  06 ─────────────────────────────────────────────────────   ││
│  │  │   └ Research ML... │  │      │                                                       ││
│  │  └────────────────────┘  │  07 ─────────────────────────────────────────────────────   ││
│  │                          │      │                                                       ││
│  │  ┌────────────────────┐  │  08 ─────────────────────────────────────────────────────   ││
│  │  │ ◇ Tasks         (8)│  │      │                                                       ││
│  │  │   └ Fix auth bug   │  │  09 ──┬───────────────────────────────────────────────────   ││
│  │  │   └ Review PR #42  │  │      │ ┌─────────────────────────────────────────────────┐  ││
│  │  │   └ Deploy staging │  │      │ │  ◆ DEEP WORK                                    │  ││
│  │  └────────────────────┘  │      │ │  Cosmo Development                              │  ││
│  │                          │  10 ──┤ │  09:00 - 11:30 (2h 30m)                         │  ││
│  │  ┌────────────────────┐  │      │ │  ● In Progress                                  │  ││
│  │  │ ◇ Content       (3)│  │      │ │  Tasks: Fix auth bug, Review PR                 │  ││
│  │  │   └ Newsletter #24 │  │  11 ──┤ │  ────────────────────────────────────────────  │  ││
│  │  │   └ Thread draft   │  │      │ │  Est. XP: +125                                  │  ││
│  │  └────────────────────┘  │      │ └─────────────────────────────────────────────────┘  ││
│  │                          │      │                                                       ││
│  │  ─────── PROJECTS ────── │  12 ─────────────────────────────────────────────────────   ││
│  │                          │      │                                                       ││
│  │  ┌────────────────────┐  │  13 ═══════════════════════════════════════════════════════ ││
│  │  │ ⬡ Cosmo         (5)│  │      │ ● NOW 13:24                                          ││
│  │  │   └ Planerium spec │  │      │ ═══════════════════════════════════════════════════ ││
│  │  │   └ Voice router   │  │      │                                                       ││
│  │  └────────────────────┘  │  14 ──┬───────────────────────────────────────────────────   ││
│  │                          │      │ ┌─────────────────────────────────────────────────┐  ││
│  │  ┌────────────────────┐  │      │ │  ◆ CREATIVE                                     │  ││
│  │  │ ⬡ Michael       (4)│  │      │ │  Content Writing                                │  ││
│  │  │   └ Monthly report │  │  15 ──┤ │  14:00 - 16:00 (2h)                             │  ││
│  │  │   └ Strategy deck  │  │      │ │  ○ Upcoming                                     │  ││
│  │  └────────────────────┘  │      │ │  Tasks: Newsletter #24, Thread draft            │  ││
│  │                          │  16 ──┤ │  ────────────────────────────────────────────  │  ││
│  │  ─────── OVERDUE ─────── │      │ │  Est. XP: +95                                   │  ││
│  │                          │      │ └─────────────────────────────────────────────────┘  ││
│  │  ┌────────────────────┐  │      │                                                       ││
│  │  │ ⚠ Overdue       (2)│  │  17 ─────────────────────────────────────────────────────   ││
│  │  │   └ Client call    │  │      │                                                       ││
│  │  │   └ Invoice #891   │  │  18 ──┬───────────────────────────────────────────────────   ││
│  │  └────────────────────┘  │      │ ┌─────────────────────────────────────────────────┐  ││
│  │                          │      │ │  ◆ REST                                         │  ││
│  │  ┌────────────────────┐  │      │ │  Dinner Break                                   │  ││
│  │  │ Filter: [All ▾]    │  │  19 ──┤ │  18:00 - 19:00 (1h)                             │  ││
│  │  │ [All][Tasks][Ideas]│  │      │ └─────────────────────────────────────────────────┘  ││
│  │  └────────────────────┘  │      │                                                       ││
│  │                          │  20 ─────────────────────────────────────────────────────   ││
│  │                          │      │                                                       ││
│  │  ────────────────────    │  21 ──┬───────────────────────────────────────────────────   ││
│  │  23 items total          │      │ ┌─────────────────────────────────────────────────┐  ││
│  │  Drag to schedule →      │      │ │  ◆ DEEP WORK                                    │  ││
│  │                          │      │ │  Evening Session                                │  ││
│  │                          │  22 ──┤ │  21:00 - 23:00 (2h)                             │  ││
│  │                          │      │ │  ○ Upcoming                                     │  ││
│  │                          │      │ │  Est. XP: +100                                  │  ││
│  │                          │  23 ──┤ └─────────────────────────────────────────────────┘  ││
│  │                          │      │                                                       ││
│  │                          │  00 ─────────────────────────────────────────────────────   ││
│  └──────────────────────────┴──────────────────────────────────────────────────────────────┘│
│                                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────────────────────┐  │
│  │  ● ACTIVE   │  Deep Work: Cosmo Development   │  01:23:45   │  +125 XP (projected)   │  │
│  │  ─────────────────────────────────────────────────────────────────────────────────────│  │
│  │  [Pause]  [Complete Block +125 XP]  [Extend 30m]                                      │  │
│  └───────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                             │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

## 2.2 Now Bar Specification

The Now Bar is the **signature visual element** of Planerium — a glowing, animated temporal marker.

### Visual Specification

```
┌─────────────────────────────────────────────────────────────┐
│                        NOW BAR                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Structure (left to right):                                  │
│                                                              │
│  TIME LABEL                                                  │
│  ├── Position: Left of timeline, aligned with time column   │
│  ├── Font: SF Mono 10pt Bold                                │
│  ├── Color: #22C55E (now marker green)                      │
│  └── Updates: Every second                                   │
│                                                              │
│  MARKER DOT                                                  │
│  ├── Size: 8×8pt circle                                     │
│  ├── Fill: #22C55E solid                                    │
│  ├── Glow: 0 0 8px #22C55E @ 50%                           │
│  └── Animation: Pulse scale 0.9-1.1 over 2s                 │
│                                                              │
│  LIGHT BAR                                                   │
│  ├── Height: 2px core line                                  │
│  ├── Width: Extends to right edge of timeline               │
│  ├── Gradient: #22C55E → transparent (over 100% width)      │
│  ├── Glow: 0 0 40px #22C55E @ 40%                          │
│  └── Light Refraction: Metal shader bends nearby content    │
│                                                              │
│  PARTICLE TRAIL                                              │
│  ├── Count: 15-25 particles                                 │
│  ├── Size: 2-4pt each                                       │
│  ├── Color: #22C55E @ 20-60% opacity (random)              │
│  ├── Behavior: Drift slowly upward, fade out               │
│  ├── Spawn Rate: 3 particles per second                     │
│  └── Lifetime: 2-4 seconds per particle                     │
│                                                              │
│  SHIMMER EFFECT (Optional, when hovering)                   │
│  ├── Light sweep: white highlight moves left-to-right       │
│  ├── Duration: 1.5s per sweep                               │
│  └── Opacity: 15% peak                                       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Now Bar Animation Sequence

```
IDLE STATE (continuous):
├── Time label updates every second
├── Dot pulses: scale 0.95 → 1.05 → 0.95 (2s cycle)
├── Particles spawn and drift upward
├── Glow intensity oscillates: 30% → 50% → 30% (3s cycle)
└── Bar position updates based on current time

SCROLL-TO-NOW (when "Today" button pressed):
├── T=0ms: Button pressed
├── T=100ms: Timeline begins smooth scroll
├── T=400ms: Now bar reaches center of viewport
├── T=500ms: Brief glow intensification (50% → 80% → 50%)
└── T=600ms: Settle to idle state

BLOCK INTERSECTION (when block touches Now bar):
├── Block border pulses green briefly
├── Block gains "In Progress" badge
├── XP preview appears on block
└── Active Focus Bar activates (if not already)
```

---

## 2.3 Time Block Card Specification

### Visual Specification

```
┌─────────────────────────────────────────────────────────────┐
│                    TIME BLOCK CARD                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  SIZE & POSITION                                             │
│  ├── Width: Timeline width - 16pt padding                   │
│  ├── Height: (duration_hours × 60pt) minimum 40pt           │
│  ├── Y Position: (start_hour - 5) × 60pt + (minutes × 1pt) │
│  └── Corner Radius: 10pt                                     │
│                                                              │
│  BACKGROUND                                                  │
│  ├── Base: block_type_color @ 15% opacity                   │
│  ├── Blur: 24px Gaussian                                     │
│  ├── Border: 1px block_type_color @ 30%                     │
│  ├── Glow (if active): 0 0 20px block_type_color @ 25%     │
│  └── Shadow: 0 4px 12px rgba(0,0,0,0.2)                    │
│                                                              │
│  CONTENT LAYOUT                                              │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ ◆ DEEP WORK                           ● In Progress │   │
│  │ ─────────────────────────────────────────────────── │   │
│  │ Cosmo Development                                   │   │
│  │ 09:00 - 11:30 (2h 30m)                             │   │
│  │                                                     │   │
│  │ Tasks:                                              │   │
│  │ ☐ Fix auth bug                                     │   │
│  │ ☐ Review PR #42                                    │   │
│  │ ─────────────────────────────────────────────────── │   │
│  │ Est. XP: +125                    [Michael Project] │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  HEADER ROW                                                  │
│  ├── Block type icon + name (left)                          │
│  │   └── ◆ = Deep Work, ◇ = Creative, ○ = Rest, etc.       │
│  └── Status badge (right)                                   │
│      ├── ● In Progress (green, pulsing)                     │
│      ├── ○ Upcoming (gray)                                  │
│      ├── ✓ Completed (green, static)                       │
│      └── ✕ Skipped (red, static)                           │
│                                                              │
│  BODY                                                        │
│  ├── Title: Block name (14pt Medium)                        │
│  ├── Time: Start - End (Duration) (12pt Regular)            │
│  └── Tasks (if any): Checkbox list, max 3 visible           │
│                                                              │
│  FOOTER ROW                                                  │
│  ├── XP Estimate (left): "+125 XP" or "XP: calculating..."  │
│  └── Project badge (right): Capsule with project name       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Block Type Visual Mapping

| Block Type | Icon | Color | Dimension | XP Multiplier Source |
|------------|------|-------|-----------|---------------------|
| Deep Work | ◆ brain.head.profile | #6366F1 | Cognitive | Focus score, HRV |
| Creative | ◆ paintbrush.pointed | #F59E0B | Creative | Content performance |
| Administrative | ◆ tray.full | #3B82F6 | Behavioral | Routine adherence |
| Rest | ◆ leaf | #10B981 | Physiological | Recovery metrics |
| Planning | ◆ chart.bar | #8B5CF6 | Knowledge | Strategic output |
| Meeting | ◆ person.2 | #3B82F6 | Behavioral | - |
| Training | ◆ book | #EC4899 | Knowledge | Learning metrics |

### Block State Transitions

```
STATE: Idle (default)
├── Background: block_color @ 15%
├── Border: block_color @ 30%
├── Shadow: subtle (4px blur)
└── Cursor: pointer on hover

STATE: Hover
├── Scale: 1.02
├── Background: block_color @ 20%
├── Border: block_color @ 50%
├── Shadow: elevated (8px blur)
├── Transition: 120ms planneriumPrimary
└── Show tooltip with full details (if truncated)

STATE: Pressed
├── Scale: 0.98
├── Background: block_color @ 25%
└── Transition: 80ms

STATE: In Progress (touched by Now bar)
├── Border: pulsing glow animation
├── Status badge: ● In Progress (green, pulsing)
├── XP preview: visible and updating
└── Connected to Active Focus Bar

STATE: Completed
├── Background: subtle green tint overlay
├── Status badge: ✓ Completed (green checkmark)
├── Opacity: 0.8 (slightly faded)
├── XP: Finalized, tracer animation triggered
└── Strikethrough on completed tasks

STATE: Overdue (past but incomplete)
├── Border: #EF4444 @ 30%
├── Background: subtle red tint
├── Status badge: ⚠ Overdue (red)
└── Subtle shake animation (every 30s)
```

---

## 2.4 Hour Grid Specification

```
┌─────────────────────────────────────────────────────────────┐
│                       HOUR GRID                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  TIMELINE RANGE                                              │
│  ├── Start: 05:00 (5 AM)                                    │
│  ├── End: 00:00 (Midnight)                                  │
│  └── Total: 19 hours displayed                              │
│                                                              │
│  HOUR ROW                                                    │
│  ├── Height: 60pt per hour                                  │
│  ├── Total scrollable height: 19 × 60pt = 1140pt           │
│  │                                                          │
│  ├── TIME LABEL (left column)                               │
│  │   ├── Width: 48pt                                        │
│  │   ├── Alignment: right                                   │
│  │   ├── Font: SF Mono 11pt Medium                         │
│  │   ├── Format: "HH" (24-hour, no minutes)                │
│  │   ├── Color (past): white @ 30%                         │
│  │   ├── Color (current): #22C55E (now marker)             │
│  │   └── Color (future): white @ 50%                       │
│  │                                                          │
│  ├── HOUR LINE                                              │
│  │   ├── Height: 1px                                        │
│  │   ├── Color (past): white @ 10%                         │
│  │   └── Color (future): white @ 20%                       │
│  │                                                          │
│  └── OPEN ZONE (droppable area)                             │
│      ├── Height: 59pt (hour height - line)                  │
│      ├── Background (past): white @ 2%                     │
│      ├── Background (future): white @ 3%                   │
│      └── Drop highlight: block_color @ 10% when hovering   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 2.5 Active Focus Bar Specification

The bottom bar that appears when a block is in progress.

```
┌─────────────────────────────────────────────────────────────┐
│                   ACTIVE FOCUS BAR                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  POSITION & SIZE                                             │
│  ├── Position: Fixed at bottom of Planerium                 │
│  ├── Height: 64pt                                           │
│  ├── Width: 100%                                            │
│  └── Z-index: Above all other content                       │
│                                                              │
│  BACKGROUND                                                  │
│  ├── Fill: rgba(15, 15, 20, 0.95)                          │
│  ├── Blur: 40px Gaussian backdrop                           │
│  ├── Top border: 1px rgba(255,255,255,0.08)                │
│  └── Glow: subtle block_color @ 10% at top edge            │
│                                                              │
│  LAYOUT                                                      │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ ● ACTIVE │ Deep Work: Cosmo │ 01:23:45 │ +125 XP (est)│ │
│  │──────────────────────────────────────────────────────── │ │
│  │ [Pause]      [Complete Block +125 XP]      [Extend 30m] │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  TOP ROW                                                     │
│  ├── Status indicator: ● pulsing green dot                  │
│  ├── "ACTIVE" label: 10pt Bold, green                       │
│  ├── Block info: "Deep Work: [Title]" (15pt Semibold)       │
│  ├── Timer: "HH:MM:SS" (24pt Mono Bold)                     │
│  └── XP Preview: "+125 XP (projected)" (14pt Mono)          │
│                                                              │
│  BOTTOM ROW (Action buttons)                                 │
│  ├── [Pause]: Pauses timer, dims bar                        │
│  ├── [Complete Block +XP]: Ends block, triggers XP award   │
│  └── [Extend 30m]: Adds 30 minutes to block                 │
│                                                              │
│  BUTTON STYLES                                               │
│  ├── Pause: Glass secondary, gray text                      │
│  ├── Complete: Solid green background, white text           │
│  └── Extend: Glass secondary, violet text                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

# PART III: WEEK VIEW (CORRELATION & FORECAST INTERFACE)

## 3.1 Week View Overview

The Week view shows the **entire upcoming week** with:
- Projected XP (NOT earned XP)
- Correlation-based recommendations from historical data
- Task distribution and bottlenecks
- Energy window predictions based on HRV patterns

## 3.2 Week Arc View Specification

```
WEEK ARC LAYOUT
├── Shape: Semi-circular arc of 7 day orbs
├── Center: Current week's midpoint (Wednesday/Thursday)
├── Arc radius: 160pt from center
└── Orb spacing: ~51.4° between adjacent orbs

DAY ORB
├── Size: 56x56pt
├── Fill: Gradient based on block density
│   └── 0 blocks: white @ 10% (outline only)
│   └── 1-2 blocks: white @ 30%
│   └── 3-4 blocks: white @ 50%
│   └── 5+ blocks: white @ 70%
├── Border: 2px white @ 40%
├── Glow (today): 0 0 20px #22C55E @ 40%
└── Label: Day abbreviation inside (Mon, Tue, etc.)

ORB INTERACTION
├── Hover: Scale 1.1, glow intensifies
├── Tap: Selects day, updates Day Detail panel
├── Double-tap: Switches to Day view for that day
└── Long-press: Quick-add block modal

BLOCK INDICATORS (orbiting day orbs)
├── Small dots orbiting each day orb
├── Size: 8pt each
├── Color: Block type color
├── Position: Orbit at 36pt radius from orb center
└── Count: Up to 6 visible, "..." for overflow
```

## 3.3 Correlation Insights Panel

```
DATA SOURCES
├── HRV measurements (90-day rolling window)
├── Sleep records (90-day rolling window)
├── Deep work sessions (historical performance)
├── Task completion patterns (by time of day)
├── Content performance (posting time correlations)
└── Focus scores (environmental factors)

INSIGHT TYPES

★ OPTIMAL WINDOWS
├── Computed from: HRV patterns + historical performance
├── Primary window: Highest confidence prediction
├── Secondary windows: Alternative good times
└── Confidence: 0-100% based on data points

⚠ CAUTION PERIODS
├── Post-lunch dip detection
├── Low HRV prediction windows
└── Historical low-performance periods

PERFORMANCE CORRELATIONS
├── Format: "[Factor] → [Effect]"
├── Examples:
│   └── "Sleep >7h → +23% focus"
│   └── "HRV >45ms → +31% deep work quality"
│   └── "Morning routine → +18% task completion"
└── Only show correlations with r > 0.4 (moderate+)

SCHEDULING RECOMMENDATIONS
├── "Move creative work to 10am for +15% output"
├── "Schedule deep work before lunch"
└── Based on personal historical data
```

## 3.4 XP Forecast Model

```
INPUTS
├── Planned blocks (count, type, duration)
├── Tasks assigned to blocks
├── Historical completion rate for similar blocks
├── Predicted HRV (from sleep/health patterns)
├── Day-of-week performance multipliers
└── Streak status (current streak days)

FORMULA

projected_xp = Σ (for each block):
  base_xp(block_type, duration)
  × completion_probability
  × hrv_multiplier(predicted_hrv)
  × day_multiplier(day_of_week)
  × streak_multiplier(streak_days)
  × task_xp(assigned_tasks)

COMPLETION PROBABILITY
├── Based on historical completion rate
├── Adjusted for block type
├── Adjusted for time of day
└── Range: 0.5 - 1.0 (pessimistic to optimistic)

HRV MULTIPLIER
├── predicted_hrv < 30ms: 0.8x
├── predicted_hrv 30-45ms: 1.0x
├── predicted_hrv 45-60ms: 1.1x
└── predicted_hrv > 60ms: 1.2x

DAY MULTIPLIER (from historical data)
├── Weekdays: 1.0x - 1.1x (based on personal patterns)
└── Weekends: 0.8x - 1.0x (typically lower productivity)

DISPLAY
├── Header: "Projected: +2,847 XP"
├── Comparison: "▲ +12% vs last week"
└── Breakdown: Per-day XP estimates in summary

CONFIDENCE INDICATOR
├── High (>30 days data): Show solid number
├── Medium (10-30 days): Show with "~" prefix
└── Low (<10 days): Show as range "800-1200 XP"
```

---

# PART IV: MONTH & QUARTER VIEW (STRATEGIC INTERFACE)

## 4.1 Month Density View

```
GRID LAYOUT
├── Cell size: 40x40pt
├── Spacing: 4pt between cells
├── Grid: 7 columns × 4-6 rows
└── Header row: Day abbreviations (M T W T F S S)

CELL VISUAL STATES

PAST (completed):
├── Background: Heatmap based on XP earned
│   └── Low XP: dim gray
│   └── Medium XP: soft violet
│   └── High XP: bright violet with glow
├── Density bars: Reflect actual completed hours
└── XP label: Actual XP earned

TODAY:
├── Border: 2px #22C55E (glowing)
├── Marker: ◆ indicator
├── Density bars: Current scheduled
└── XP label: Current + projected

FUTURE (scheduled):
├── Background: Based on scheduled density
├── Density bars: Scheduled hours indicator
└── XP label: Projected XP

FUTURE (unplanned):
├── Background: transparent
├── Indicator: · (small dot)
└── XP label: — (dash)

INTERACTION
├── Hover: Tooltip with day details
├── Tap: Select day, show summary
└── Double-tap: Switch to Day view
```

## 4.2 Core Objectives System

Core Objectives are **major quarterly/monthly goals** that provide massive XP rewards.

```
OBJECTIVE STRUCTURE
├── title: String (e.g., "Scale Michael to $300K")
├── description: String (optional details)
├── targetDate: Date (deadline)
├── progress: Double (0.0 - 1.0)
├── completionXP: Int (bonus XP on completion)
├── linkedAtoms: [UUID] (tasks, blocks, content)
├── metrics: [ObjectiveMetric] (tracked KPIs)
└── status: pending | in_progress | completed | failed

PROGRESS CALCULATION
├── Manual: User updates percentage
├── Auto (linked tasks): % of linked tasks completed
├── Auto (metrics): Based on defined KPIs
└── Hybrid: Weighted combination

XP REWARDS
├── Small objective (monthly): 1,000 - 2,000 XP
├── Medium objective (quarterly): 2,500 - 5,000 XP
├── Large objective (yearly): 5,000 - 15,000 XP
├── Multiplied by: Streak multiplier at completion
└── Split across: Relevant dimensions

BEFORE/AFTER COMPARISON
├── Shows metrics at objective start vs now
│   └── HRV average
│   └── Focus hours per week
│   └── Creative output (content pieces)
│   └── Tasks completed per week
│   └── Skill improvements
└── Displayed on completion celebration

VISUAL DESIGN
├── Card style: Glass surface with progress ring
├── Star rating: ★ active, ◆ in progress, ○ pending
├── Progress bar: Horizontal, dimension-colored
└── XP preview: "+5,000 XP on completion"
```

---

# PART V: INBOX SYSTEM & DRAG LOGIC

## 5.1 Project Inboxes (Left Sidebar)

### Inbox Structure

```
INBOX TYPES

CORE INBOXES (always visible)
├── Ideas Inbox: All uncommitted ideas
│   └── Color: #8B5CF6 (Knowledge/Violet)
│   └── Icon: lightbulb
├── Tasks Inbox: All uncommitted tasks
│   └── Color: #6366F1 (Cognitive/Indigo)
│   └── Icon: checkmark.circle
└── Content Inbox: Content in pipeline
    └── Color: #F59E0B (Creative/Amber)
    └── Icon: doc.text

PROJECT INBOXES (dynamic, per active project)
├── Generated from: Active projects in system
├── Contains: Items linked to that project
├── Color: #F59E0B (Project/Amber)
├── Icon: folder
└── Examples:
    └── "Cosmo" project inbox
    └── "Michael" client inbox
    └── "Personal" inbox

OVERDUE INBOX (special)
├── Contains: Past-due tasks not completed
├── Color: #EF4444 (Warning/Red)
├── Icon: exclamationmark.triangle
└── Auto-populated: End of each day
```

### Inbox Visual Specification

```
INBOX ROW (collapsed)
├── Height: 44pt
├── Padding: 12pt horizontal
├── Icon: 18pt, left-aligned
├── Title: 13pt Semibold
├── Count badge: 11pt Bold, right-aligned
│   └── Background: inbox_color @ 20%
│   └── Text: inbox_color
└── Chevron: Expand/collapse indicator

INBOX ROW (expanded)
├── Reveals list of items below
├── Items animate in with stagger (50ms each)
├── Max visible: 5 items, then "Show all..."
└── Each item: 36pt height

INBOX ITEM
├── Height: 36pt
├── Indent: 24pt from parent
├── Icon: 14pt, type-specific
├── Title: 12pt Regular, truncated
├── Time badge: "2h ago" format
└── Drag handle: visible on hover
```

### Filter System

```
FILTER CHIPS
├── Position: Bottom of inbox rail
├── Options: [All] [Tasks] [Ideas]
├── Style: Capsule buttons, single-select
└── Effect: Filters all inboxes simultaneously

FILTER BEHAVIOR
├── All: Shows everything
├── Tasks: Only shows task-type items
├── Ideas: Only shows idea-type items
└── Persists across sessions
```

## 5.2 Drag & Drop Logic

### Fundamental Rules

```
RULE 1: SOURCE CONSTRAINT
├── Tasks and ideas can ONLY be dragged from Project Inboxes
├── Cmd-K is NOT a drag source (navigation/preview only)
├── ThinkSpace items must first be added to inbox
└── Voice-created items appear in correct inbox first

RULE 2: NO OVERLAPS
├── Multiple tasks CANNOT occupy the same time slot
├── System auto-adjusts when conflicts arise
├── No visual overlap allowed
└── Magnetic snapping prevents gaps

RULE 3: FLUID RESCHEDULING
├── When task drops on existing task → goes after it
├── All subsequent tasks reschedule fluidly
├── Animation shows cascade effect
└── User sees immediate visual feedback
```

### Drag Scenarios

```
SCENARIO A: Drag to Empty Time Slot
├── User drags task from inbox
├── Hovers over empty hour zone
├── Drop zone highlights (block_color @ 10%)
├── On drop:
│   └── Creates new block at that time
│   └── Duration: Default 1h (adjustable)
│   └── Task linked to block
│   └── Inbox item removed/marked scheduled
└── Animation: Item flies to position (300ms spring)

SCENARIO B: Drag onto Existing Block
├── User drags task from inbox
├── Hovers over existing block
├── Block highlights, shows "+ Add Task" indicator
├── On drop:
│   └── Task added to block's task list
│   └── Block expands slightly if needed
│   └── XP estimate updates
└── Animation: Item merges into block (250ms)

SCENARIO C: Drag Between Existing Blocks
├── User drags task from inbox
├── Hovers between two blocks
├── Gap expands to show insertion point
├── On drop:
│   └── New block created in gap
│   └── If gap too small, subsequent blocks shift
│   └── Fluid cascade animation
└── Animation: Blocks smoothly rearrange (400ms spring)

SCENARIO D: Drag Task Immediately After Another
├── User drags task onto edge of existing block
├── "After this block" indicator appears
├── On drop:
│   └── New block starts immediately after
│   └── No gap between blocks
│   └── Subsequent blocks shift if needed
└── Animation: Magnetic snap + cascade (350ms)
```

### Drag Visual Feedback

```
DRAG GHOST
├── Semi-transparent copy of item (70% opacity)
├── Scale: 1.05x (slightly larger)
├── Shadow: Elevated (16px blur)
├── Follows cursor with 8px offset
└── Rotates slightly based on velocity

DRAG SOURCE (inbox item)
├── Dims to 30% opacity
├── Placeholder shows "Scheduling..."
└── Returns if drag cancelled

DROP ZONE INDICATORS
├── Valid zone: Soft glow of block type color
├── Invalid zone: Red tint, cursor changes
├── Insertion line: 2px violet line between items
└── Merge indicator: Block pulses

CANCEL BEHAVIOR
├── Drop outside valid zone: Animate back to inbox
├── ESC key: Cancel drag, animate back
├── Right-click: Cancel drag
└── Animation: Spring back (400ms)
```

## 5.3 Block Types (Deep Work, Creative, Rest, etc.)

### Block Type Definitions

```
DEEP WORK
├── Purpose: Focused cognitive work (coding, analysis)
├── Color: #6366F1 (Indigo)
├── Dimension: Cognitive
├── Default duration: 2h
├── XP calculation: deepWorkHour × hours × multipliers
└── Icon: brain.head.profile

CREATIVE
├── Purpose: Content creation, writing, design
├── Color: #F59E0B (Amber)
├── Dimension: Creative
├── Default duration: 1.5h
├── XP calculation: Based on content output
└── Icon: paintbrush.pointed

OUTPUT
├── Purpose: Publishing, shipping, delivering
├── Color: #F59E0B (Amber)
├── Dimension: Creative
├── Default duration: 1h
├── XP calculation: contentPublished + performance
└── Icon: paperplane

PLANNING
├── Purpose: Strategic thinking, goal-setting
├── Color: #8B5CF6 (Violet)
├── Dimension: Knowledge
├── Default duration: 1h
├── XP calculation: Based on insights generated
└── Icon: chart.bar

TRAINING
├── Purpose: Learning, skill development
├── Color: #EC4899 (Pink)
├── Dimension: Knowledge
├── Default duration: 1h
├── XP calculation: researchAdded + connections
└── Icon: book

REST
├── Purpose: Recovery, breaks, meals
├── Color: #10B981 (Emerald)
├── Dimension: Physiological
├── Default duration: 30m-1h
├── XP calculation: None directly (enables multipliers)
└── Icon: leaf

ADMIN
├── Purpose: Email, meetings, logistics
├── Color: #3B82F6 (Blue)
├── Dimension: Behavioral
├── Default duration: 30m
├── XP calculation: routineAdherence
└── Icon: tray.full

MEETING
├── Purpose: Calls, video meetings
├── Color: #3B82F6 (Blue)
├── Dimension: Behavioral
├── Default duration: 30m-1h
├── XP calculation: None (behavioral adherence)
└── Icon: person.2
```

### Block XP Influence

```
BLOCKS DO NOT GENERATE XP DIRECTLY

XP comes from:
├── Tasks completed within blocks
├── Content published/created
├── Time logged (deep work hours)
├── Focus scores achieved
└── Routine adherence patterns

BLOCKS INFLUENCE XP MULTIPLIERS
├── Historical correlation data
├── Proper block type → higher success rate
├── Scheduled rest → better subsequent performance
└── Block adherence → behavioral XP bonus
```

---

# PART VI: XP SYSTEM & TASK COMPLETION

## 6.1 XP Calculation Overview

XP is generated ONLY from **real measurable signals**, never random or arbitrary.

### XP Formula (Full)

```
TASK COMPLETION XP

final_xp = base_xp
  × difficulty_multiplier
  × category_multiplier
  × hrv_multiplier
  × focus_multiplier
  × consistency_multiplier
  × streak_multiplier
  × core_objective_bonus

WHERE:

base_xp = XPCalculationEngine.xpForAction(action)
  └── Reference: XPCalculationEngine.swift:BaseXP enum

difficulty_multiplier = 0.5 (trivial) to 2.0 (very hard)
  └── Based on: Estimated effort, complexity flags

category_multiplier = Maps task to dimension weight
  └── Cognitive tasks: 1.0-1.2x
  └── Creative tasks: 1.0-1.3x (viral potential)
  └── Behavioral tasks: 0.8-1.0x

hrv_multiplier = Based on current HRV reading
  └── HRV < 30ms: 0.8x (stressed/depleted)
  └── HRV 30-45ms: 1.0x (baseline)
  └── HRV 45-60ms: 1.1x (recovered)
  └── HRV > 60ms: 1.2x (peak state)

focus_multiplier = Based on focus score during block
  └── Focus < 60: 0.9x
  └── Focus 60-80: 1.0x
  └── Focus 80-90: 1.1x
  └── Focus > 90: 1.2x

consistency_multiplier = Based on routine adherence
  └── < 50% adherence: 0.9x
  └── 50-80% adherence: 1.0x
  └── > 80% adherence: 1.1x

streak_multiplier = From StreakMultipliers.forStreak()
  └── 0 days: 1.0x
  └── 3 days: 1.05x
  └── 7 days: 1.1x
  └── 14 days: 1.15x
  └── 30 days: 1.25x
  └── 60 days: 1.35x
  └── 90 days: 1.5x

core_objective_bonus = If task supports Core Objective
  └── Normal task: 1.0x
  └── Supports objective: 1.2x
  └── Critical path: 1.5x
```

## 6.2 XP Distribution Across Dimensions

```
XP SPLIT LOGIC

When task completes, XP is distributed:

1. PRIMARY DIMENSION (60% of XP)
   └── Determined by task category/block type
   └── e.g., Deep Work → Cognitive

2. SECONDARY DIMENSIONS (30% split)
   └── Based on task attributes
   └── e.g., Writing task → Creative + Knowledge

3. BEHAVIORAL (10% always)
   └── Completing tasks = behavioral discipline
   └── Always contributes to Behavioral dimension

EXAMPLE: Complete "Write thread" task (+100 XP base)

After multipliers: 120 XP final
├── Creative (primary): 72 XP (60%)
├── Cognitive: 24 XP (20%)
├── Knowledge: 12 XP (10%)
└── Behavioral: 12 XP (10%)

All dimensions update simultaneously
Sanctuary orbs reflect new XP immediately
```

## 6.3 XP Tracer Animation

```
XP TRACER VISUAL SEQUENCE

T=0ms     Task marked complete
          └── Checkbox animates to filled
          └── Block border flashes green

T=100ms   XP number appears on block
          └── "+120 XP" text fades in
          └── Font: SF Mono 14pt Bold
          └── Color: White with green glow

T=200ms   XP particles spawn
          └── Count: 8-15 particles
          └── Size: 4-8pt circles
          └── Color: Dimension colors (split by %)
          └── Initial position: Block center

T=300ms   Particles begin flight
          └── Path: Bezier curve toward XP bar
          └── Stagger: 30ms between particles
          └── Speed: Fast at start, ease out
          └── Trail: Subtle glow trail

T=600ms   First particles reach XP bar
          └── Bar location: Top-left header
          └── Impact: Soft pulse effect
          └── Sound: Subtle "ding" (if enabled)

T=900ms   All particles absorbed
          └── XP bar updates numerically
          └── Progress ring fills
          └── Glow intensifies briefly

T=1200ms  Settle
          └── XP bar returns to idle
          └── Block shows completed state
          └── Ready for next action

PARTICLE PHYSICS
├── Gravity: Slight upward bias
├── Wind: Gentle rightward drift
├── Collision: None (pass through UI)
├── Fade: Last 30% of journey
└── Easing: planneriumXPTracer curve
```

## 6.4 Overdue Task Logic

```
OVERDUE DEFINITION
├── Task becomes "Overdue" ONLY when:
│   └── The day ends (midnight)
│   └── AND task is not completed
│   └── AND user has not checked it off
└── NOT overdue while day is still active

DURING THE DAY (before midnight)
├── Overdue tasks remain visible in Today view
├── Visual: Red-tinted border, subtle shake
├── Status badge: ⚠ Overdue
├── Pulse animation: Every 30 seconds
└── User can still complete for full XP

AFTER DAY ENDS (midnight transition)
├── Uncompleted tasks move to Overdue Inbox
├── Animation: Fly to Overdue section in sidebar
├── Do NOT auto-clutter next day
├── User must manually reschedule
└── XP penalty: None (just no XP earned)

OVERDUE INBOX BEHAVIOR
├── Shows all overdue items across all projects
├── Sorted by: Original due date (oldest first)
├── Actions:
│   └── Drag to reschedule
│   └── Mark as done (reduced XP)
│   └── Delete (acknowledge skip)
└── Badge count shows total overdue
```

---

# PART VII: VOICE INTEGRATION

## 7.1 Voice Command Architecture

Planerium integrates with the existing 3-tier Voice Command Pipeline:

```
TIER 0: PATTERN MATCHING (<50ms)
├── Handles: ~60% of Planerium commands
├── Regex-based instant recognition
├── Examples:
│   └── "Schedule this at 9" → createScheduleBlock
│   └── "Add to Cosmo project" → assignToProject
│   └── "Complete task" → markComplete
└── File: PatternMatcher.swift

TIER 1: FUNCTIONGEMMA 270M (<300ms)
├── Handles: ~39% of Planerium commands
├── Local model, semantic understanding
├── Examples:
│   └── "Put the auth bug fix tomorrow morning"
│   └── "Move my creative block to after lunch"
│   └── "Block out 2 hours for deep work"
└── File: VoiceCommandPipeline.swift

TIER 2: CLAUDE SONNET 4.5 (1-5s)
├── Handles: ~1% of Planerium commands
├── Complex reasoning, multi-step scheduling
├── Examples:
│   └── "Reorganize my week to prioritize the launch"
│   └── "What's the best time for deep work tomorrow?"
│   └── "Analyze my scheduling patterns"
└── Used for: Synthesis, correlation queries
```

## 7.2 Planerium Voice Intents

```
CREATION INTENTS

createScheduleBlock
├── Trigger: "schedule", "block out", "add block"
├── Parameters:
│   └── blockType: deep_work | creative | rest | etc.
│   └── startTime: Time or relative ("tomorrow 9am")
│   └── duration: Optional (default by type)
│   └── title: Optional block name
├── Example: "Block out 2 hours of deep work at 9am"
└── Result: Creates scheduleBlock atom, updates timeline

createTaskTimed
├── Trigger: "schedule task", "add task at"
├── Parameters:
│   └── title: Task description
│   └── scheduledTime: When to do it
│   └── projectUuid: Optional project assignment
├── Example: "Schedule fix auth bug for tomorrow at 10"
└── Result: Creates task + scheduleBlock, links them

assignToProject
├── Trigger: "add to [project]", "for [project]"
├── Parameters:
│   └── itemTitle: What to assign
│   └── projectName: Target project
├── Example: "Add this to the Cosmo project"
└── Result: Links item to project, moves to inbox

MODIFICATION INTENTS

rescheduleBlock
├── Trigger: "move", "reschedule", "push"
├── Parameters:
│   └── blockIdentifier: Which block
│   └── newTime: New scheduled time
├── Example: "Move my 2pm block to 4pm"
└── Result: Updates block time, cascades if needed

extendBlock
├── Trigger: "extend", "add time", "make longer"
├── Parameters:
│   └── blockIdentifier: Which block
│   └── additionalTime: How much to add
├── Example: "Extend this block by 30 minutes"
└── Result: Updates endTime, shifts subsequent

markComplete
├── Trigger: "complete", "done", "finish"
├── Parameters:
│   └── itemIdentifier: Task or block
├── Example: "Mark the auth bug as done"
└── Result: Marks complete, triggers XP award

deleteBlock
├── Trigger: "delete", "remove", "cancel"
├── Parameters:
│   └── blockIdentifier: Which block
├── Example: "Cancel my 4pm meeting"
└── Result: Removes block, tasks return to inbox

QUERY INTENTS

querySchedule
├── Trigger: "what's scheduled", "show me", "my day"
├── Parameters:
│   └── timeRange: today | tomorrow | this week
├── Example: "What's on my schedule tomorrow?"
└── Result: Speaks schedule summary

queryFreeTime
├── Trigger: "when am I free", "open slots"
├── Parameters:
│   └── duration: Minimum free time needed
│   └── timeRange: When to look
├── Example: "When do I have 2 hours free this week?"
└── Result: Lists available slots

queryOptimalTime
├── Trigger: "best time for", "when should I"
├── Parameters:
│   └── taskType: deep_work | creative | meeting
├── Example: "When's the best time for deep work?"
└── Result: Returns correlation-based recommendation
```

## 7.3 Voice-Created Item Flow

```
VOICE CAPTURE → PLANERIUM FLOW

1. User speaks: "Add a task to fix the login bug for Cosmo"

2. Tier 0/1 parses intent:
   └── Intent: createTask
   └── Title: "Fix the login bug"
   └── Project: "Cosmo" (matched)

3. Atom created:
   └── Type: uncommittedItem
   └── inferredType: "task"
   └── projectUuid: [Cosmo UUID]
   └── assignmentStatus: "assigned"

4. Item appears in:
   └── Cosmo Project Inbox (primary)
   └── Tasks Inbox (if filter shows all)

5. User can then:
   └── Drag to schedule
   └── Voice: "Schedule this at 9 tomorrow"
   └── Edit details
```

## 7.4 Scheduling via Voice

```
VOICE SCHEDULING FLOW

1. User speaks: "Schedule this at 9 tomorrow"

2. Context detection:
   └── "this" → Most recent item OR selected item
   └── If ambiguous → "Which task? The login bug or..."

3. Time parsing:
   └── "9" → 09:00 (assumes morning for work)
   └── "tomorrow" → Next calendar day
   └── "9pm" → 21:00 explicit

4. Block creation:
   └── Creates scheduleBlock at target time
   └── Links task to block
   └── Default duration: 1h (or inferred)

5. Confirmation:
   └── Audio: "Scheduled for tomorrow at 9am"
   └── Visual: Block appears on timeline
   └── XP preview shown
```

---

# PART VIII: EMBEDDING & SEMANTIC LAYER

## 8.1 Embedding Model

```
MODEL: nomic-embed-text-v1.5
├── Dimensions: 768
├── Context window: 8192 tokens
├── Runtime: MLX-Swift (local, on-device)
└── Purpose: Semantic search, categorization, linking

USAGE IN PLANERIUM
├── Task categorization (infer block type)
├── Project assignment suggestions
├── Semantic search in Cmd-K
├── Duplicate detection
├── Priority inference
└── Block type recommendations
```

## 8.2 Anti-Duplication System

```
DUPLICATION PREVENTION

When new item created:

1. NORMALIZE INPUT
   └── Lowercase
   └── Remove extra whitespace
   └── Strip common prefixes ("add", "create", etc.)

2. COMPUTE EMBEDDING
   └── nomic-embed-text-v1.5(normalized_text)
   └── Cache result for reuse

3. SIMILARITY SEARCH
   └── Query existing items in same project
   └── Threshold: cosine_similarity > 0.85

4. METADATA COMPARISON
   └── Same project?
   └── Similar timestamps (within 1 hour)?
   └── Same inferred type?

5. DECISION
   └── If duplicate detected:
       └── Show "Similar item exists: [title]"
       └── Options: [Merge] [Create Anyway] [Cancel]
   └── If unique:
       └── Create normally

PERIODIC DEDUPLICATION
├── Runs: Nightly during idle
├── Scans: All uncommitted items
├── Action: Suggests merges, doesn't auto-delete
└── UI: "3 potential duplicates found" badge
```

## 8.3 Smart Categorization

```
TASK → BLOCK TYPE INFERENCE

Input: Task title + description
Output: Recommended block type

MODEL: FunctionGemma 270M

RULES:
├── Contains "write", "draft", "content" → Creative
├── Contains "code", "fix", "build", "debug" → Deep Work
├── Contains "call", "meet", "sync" → Meeting
├── Contains "email", "reply", "review PR" → Admin
├── Contains "learn", "read", "research" → Training
├── Contains "plan", "strategy", "roadmap" → Planning
└── Default: Deep Work (most common)

CONFIDENCE:
├── High (>0.8): Auto-assign type
├── Medium (0.5-0.8): Suggest with option to change
└── Low (<0.5): Ask user to select
```

## 8.4 Semantic Search (Cmd-K Context)

```
CMD-K SEMANTIC SEARCH

Query: User typed search string
Scope: All atoms (tasks, ideas, blocks, content, etc.)

SEARCH PIPELINE:

1. KEYWORD MATCH (fast path)
   └── If query matches title exactly → return immediately
   └── Fuzzy match on titles → rank by similarity

2. SEMANTIC SEARCH (if <10 keyword results)
   └── Embed query with nomic-embed-text-v1.5
   └── Vector search against atom embeddings
   └── Top 20 results by cosine similarity

3. MERGE & RANK
   └── Combine keyword + semantic results
   └── Boost recent items (decay factor)
   └── Boost items in current project context
   └── Deduplicate

4. RETURN
   └── Top 10 results for display
   └── Each with: title, type, preview, relevance score
```

---

# PART IX: CMD-K NODE SYSTEM INTEGRATION

## 9.1 Cmd-K Overview (NOT for Drag-Drop)

```
CMD-K IS FOR:
├── Navigation (jump to any view, project, item)
├── Previewing nodes (hover cards)
├── Opening workspaces
├── Semantic search across all atoms
├── Quick actions (create, navigate, open)
└── Viewing radial semantic maps

CMD-K IS NOT FOR:
├── Dragging items to Planerium
├── Scheduling tasks (use inbox drag or voice)
├── Direct manipulation of timeline
└── Replacing inbox workflow
```

## 9.2 Cmd-K Visual Specification

```
CMD-K OVERLAY
├── Position: Centered, 70% screen width
├── Height: Dynamic, max 60% screen height
├── Background: Dark glass (rgba(10,10,15,0.95))
├── Blur: 40px backdrop
├── Border: 1px rgba(255,255,255,0.08)
├── Corner radius: 20px
└── Animation: Fade in + scale (0.95 → 1.0) 200ms

SEARCH INPUT
├── Position: Top of overlay
├── Height: 56pt
├── Font: SF Pro Text 17pt
├── Placeholder: "Search anything..."
├── Icon: magnifyingglass (left)
└── Clear button: xmark.circle (right, when text)

RESULTS LIST
├── Max items: 10 visible
├── Item height: 48pt
├── Sections: Recent, Tasks, Ideas, Projects, Content
├── Keyboard navigation: Up/Down arrows
└── Selection highlight: violet @ 10%

RESULT ITEM
├── Icon: Type-specific (24pt)
├── Title: Primary text (15pt Medium)
├── Subtitle: Project/context (12pt, muted)
├── Right badge: Type label or date
└── Hover: Show preview card after 300ms

PREVIEW CARD (on hover)
├── Position: Right of selected item
├── Size: 300×200pt
├── Content: Title, body preview, metadata
├── Actions: [Open] [Schedule] [Edit]
└── Animation: Fade in 150ms
```

## 9.3 Cmd-K Actions for Planerium

```
CMD-K PLANERIUM ACTIONS

"schedule [task name]"
├── Opens scheduling modal for that task
├── Shows timeline mini-view
└── User picks time, creates block

"go to planerium"
├── Closes Cmd-K
└── Navigates to Planerium view

"show today" / "show week" / "show month"
├── Closes Cmd-K
├── Opens Planerium in that view
└── Scrolls to today

"create block [type] at [time]"
├── Creates schedule block directly
├── Opens Planerium if not there
└── Scrolls to new block

"what's scheduled [timeframe]"
├── Shows schedule summary in results
├── No navigation needed
└── Quick glance at day/week
```

---

# PART X: PERFORMANCE & CACHING

## 10.1 Performance Constraints

```
TARGET METRICS

Frame Rate: 120fps sustained
├── All animations must hit 120fps on M1+
├── Use Metal for particle systems
└── Offload heavy computation to background

Response Time:
├── Tap/click: <16ms visual response
├── Drag start: <50ms ghost appears
├── View switch: <100ms begins transition
└── Data load: <200ms initial render

Memory:
├── Active view: <150MB
├── Background: <50MB
├── No memory leaks on navigation
└── Aggressive cache eviction

Battery:
├── Active use: <5% per hour
├── Idle (visible): <2% per hour
└── Background: <0.5% per hour
```

## 10.2 Caching Architecture

```
CACHE LAYERS

L1: IN-MEMORY (instant access)
├── Current day blocks: Always loaded
├── Current week blocks: Loaded on week view
├── Recent 50 inbox items: Pre-fetched
├── User preferences: Cached on launch
└── Eviction: LRU, max 100 items

L2: SQLITE (GRDB, <10ms access)
├── All atoms: Full database
├── Indexes: uuid, type, createdAt, projectUuid
├── Queries: Prepared statements, reused
└── Eviction: None (persistent)

L3: NETWORK (Supabase, 100ms-2s)
├── Sync on app launch
├── Sync on significant changes
├── Conflict resolution: Last-write-wins with merge
└── Offline: Full local-first operation

CACHE INVALIDATION
├── On atom change: Invalidate affected views
├── On sync complete: Refresh visible data
├── On day change: Clear old day from L1
└── On memory pressure: Evict L1 aggressively
```

## 10.3 Timeline Virtualization

```
RENDER WINDOW

Visible hours: ~8-10 hours on screen
Buffer: ±4 hours pre-rendered
Total rendered: ~16-18 hours max

VIRTUALIZATION RULES:
├── Only render visible hour rows
├── Recycle row views on scroll
├── Lazy-load block details on hover
├── Defer non-critical animations when scrolling fast
└── Pause particles during rapid scroll

SCROLL OPTIMIZATION:
├── Use CADisplayLink for smooth 120Hz
├── Predictive pre-rendering based on velocity
├── Coalesce rapid scroll events
└── Skip intermediate frames if behind
```

## 10.4 Animation Batching

```
PARTICLE SYSTEM OPTIMIZATION

XP Tracers:
├── Max concurrent: 500 particles
├── If exceeded: Coalesce into fewer, larger particles
├── GPU instanced rendering (Metal)
└── Shared particle pool (reuse, don't allocate)

Now Bar Particles:
├── Max concurrent: 30 particles
├── Simple shader, minimal computation
└── Pause when off-screen

ANIMATION COALESCING:
├── Multiple XP awards in <500ms: Batch into single animation
├── Rapid block updates: Debounce re-render (100ms)
├── View mode switch during animation: Cancel in-flight
└── Priority: User interaction > ambient > decorative
```

## 10.5 Idle-Time Processing

```
BACKGROUND TASKS (when idle >5 seconds)

1. Embedding computation
   └── Pre-compute embeddings for new items
   └── Max 5 per idle session

2. Deduplication scan
   └── Check for similar items
   └── Lightweight, non-blocking

3. Correlation update
   └── Update XP forecast models
   └── Only if data changed

4. Cache warming
   └── Pre-fetch tomorrow's blocks
   └── Pre-fetch next week on Friday

5. Sync check
   └── Silent sync if network available
   └── No UI interruption

IDLE DETECTION:
├── No user input for 5 seconds
├── No animations in progress
├── App in foreground
└── Battery >20% OR plugged in
```

---

# PART XI: DATA MODELS

## 11.1 ScheduleBlock Atom

```swift
// AtomType: .scheduleBlock

struct ScheduleBlockMetadata: Codable {
    // Core scheduling
    var startTime: String          // ISO8601 format
    var endTime: String            // ISO8601 format
    var blockType: String          // "deep_work", "creative", etc.

    // Status
    var status: String?            // "scheduled", "in_progress", "completed", "skipped"
    var isCompleted: Bool?         // Convenience flag
    var completedAt: String?       // When completed

    // XP tracking
    var estimatedXP: Int?          // Projected XP
    var actualXP: Int?             // Earned XP (after completion)
    var xpMultipliers: [String: Double]?  // Applied multipliers

    // Focus metrics (populated during/after)
    var focusScore: Double?        // 0-100
    var interruptionCount: Int?
    var hrvAverage: Double?        // During block

    // Recurrence (future)
    var recurrenceRule: String?    // "daily", "weekly", etc.
    var recurrenceEndDate: String?
}

// Links
├── "project": Project atom UUID
├── "tasks": Array of task atom UUIDs
├── "coreObjective": Objective UUID (if supports one)
└── "sourceIdea": Original idea (if promoted)
```

## 11.2 UncommittedItem Atom

```swift
// AtomType: .uncommittedItem

struct UncommittedItemMetadata: Codable {
    // Classification
    var inferredType: String?      // "idea", "task", "content"
    var confidence: Double?        // 0-1, classification confidence

    // Capture info
    var captureMethod: String?     // "voice", "keyboard", "import"
    var captureContext: String?    // Where captured

    // Assignment
    var assignmentStatus: String?  // "unassigned", "suggested", "assigned"
    var suggestedProjectUuid: String?  // AI-suggested project

    // Priority (inferred)
    var priority: String?          // "low", "medium", "high", "urgent"
    var dueDate: String?           // If has deadline

    // Scheduling
    var scheduledBlockUuid: String?  // If scheduled
    var estimatedDuration: Int?      // Minutes
}

// Links
├── "project": Assigned project UUID
├── "scheduledBlock": ScheduleBlock UUID (if scheduled)
└── "embedding": Cached embedding vector
```

## 11.3 CoreObjective Atom

```swift
// AtomType: .coreObjective (new type to add)

struct CoreObjectiveMetadata: Codable {
    // Definition
    var title: String
    var description: String?
    var targetDate: String          // ISO8601
    var createdDate: String

    // Progress
    var progress: Double            // 0.0 - 1.0
    var progressType: String        // "manual", "auto_tasks", "auto_metrics", "hybrid"
    var status: String              // "pending", "in_progress", "completed", "failed"

    // XP
    var completionXP: Int           // Bonus XP on completion
    var xpAwarded: Bool             // Already awarded?

    // Metrics (for before/after)
    var startMetrics: ObjectiveMetrics?
    var currentMetrics: ObjectiveMetrics?

    // Timeline
    var timelineScope: String       // "monthly", "quarterly", "yearly"
}

struct ObjectiveMetrics: Codable {
    var hrvAverage: Double?
    var focusHoursPerWeek: Double?
    var contentPiecesCreated: Int?
    var tasksCompletedPerWeek: Double?
    var dimensionLevels: [String: Int]?
}

// Links
├── "linkedTasks": Task UUIDs that contribute
├── "linkedBlocks": Block UUIDs that contribute
├── "project": Primary project (if applicable)
```

## 11.4 XPEvent Atom (existing, reference)

```swift
// AtomType: .xpEvent

struct XPEventMetadata: Codable {
    var dimension: LevelDimension
    var xpAmount: Int               // Final amount
    var baseXP: Int                 // Before multipliers
    var source: String              // Action that triggered
    var sourceAtomUUID: String?     // Related atom
    var multiplier: Double          // Total multiplier applied
    var bonusType: XPBonusType?     // streak, lucky, event
    var timestamp: Date
}

// Used to track all XP awards
// Queried for: Daily summaries, dimension breakdowns, streak tracking
```

---

# PART XII: ACCESSIBILITY & EDGE CASES

## 12.1 Accessibility Requirements

```
VOICEOVER SUPPORT

Labels:
├── All blocks: "[Type] block, [Title], [Time range], [Status]"
├── Inbox items: "[Type], [Title], [Time ago], [Project]"
├── Now bar: "Current time: [HH:MM], [N] blocks remaining today"
├── XP display: "Level [N], [X] XP, [Y] percent to next level"
└── Actions: "Complete block, plus [X] XP"

Navigation:
├── Left/right arrow: Navigate between days
├── Up/down arrow: Navigate between blocks
├── Enter: Select/activate block
├── Escape: Close modals, cancel drag
└── Tab: Move through inbox items

Announcements:
├── On block complete: "Block completed, plus [X] XP awarded"
├── On XP milestone: "Level up! Now level [N]"
├── On overdue: "[N] tasks overdue"
└── On schedule change: "Block moved to [new time]"

REDUCE MOTION

When enabled:
├── Disable particle systems
├── Disable XP tracer flight (instant update instead)
├── Disable Now bar glow animation
├── Disable block hover scale
├── Use fade instead of spring animations
└── Skip cinematic transitions

DYNAMIC TYPE

Support sizes:
├── xSmall to AX5
├── Scale all text proportionally
├── Increase touch targets at larger sizes
├── Stack horizontal layouts vertically if needed
└── Test at accessibility sizes
```

## 12.2 Edge Cases

```
EDGE CASE: No blocks scheduled
├── Show: Empty state with helpful message
├── Message: "No blocks today. Drag from inbox to schedule."
├── Action: Highlight inbox rail
└── Don't show: Blank void (feels broken)

EDGE CASE: Block overlaps midnight
├── Split: Block appears on both days
├── Visual: Connects across day boundary
├── XP: Awarded when entire block completes
└── Overdue: Only if end time passes

EDGE CASE: Very long block (>6 hours)
├── Visual: Full height, scrollable within
├── Tasks: Collapsed list, "Show all" button
├── XP estimate: Sum of all tasks
└── Warning: "Long block detected, consider breaking up"

EDGE CASE: 50+ tasks in inbox
├── Virtual scroll: Only render visible items
├── Search: Emphasize filter/search UI
├── Performance: Lazy load item details
└── UX: "Lots of items! Consider scheduling some."

EDGE CASE: Rapid task completion (gaming)
├── XP still awarded: No punitive measures
├── Animation: Batch multiple completions
├── Audit: Log for potential review
└── Philosophy: Trust user, reward action

EDGE CASE: No network
├── Full offline operation
├── Visual: Subtle "Offline" badge
├── Sync: Queue changes for later
└── XP: Still awarded, syncs when online

EDGE CASE: Day changes while viewing
├── Detect: Midnight transition
├── Action: Soft refresh, don't interrupt
├── Overdue: Process incomplete tasks
├── Now bar: Jump to 00:00 position
└── Notification: Optional "New day!" celebration

EDGE CASE: Conflicting sync
├── Resolution: Last-write-wins with merge
├── Conflicts: Preserve both if truly different
├── UI: "Sync conflict resolved" toast
└── Audit: Log for debugging
```

## 12.3 Error Prevention

```
PREVENT: Scheduling in the past
├── Visual: Past hours dimmed, show "Past" label
├── Interaction: Drop zone inactive
├── Voice: "Cannot schedule in the past. Try tomorrow?"
└── Exception: Allow if within 30 minutes (just started)

PREVENT: Overlapping blocks
├── Visual: Conflict indicator appears
├── Resolution: Auto-cascade subsequent blocks
├── Confirmation: "Move following blocks by [N] minutes?"
└── Undo: Available for 10 seconds

PREVENT: Empty block titles
├── Default: Use block type as title ("Deep Work")
├── Prompt: If user clears, suggest restoring
└── Save: Always save even if empty (prevent data loss)

PREVENT: Accidental deletion
├── Confirmation: "Delete this block? Tasks return to inbox."
├── Undo: Available for 10 seconds
├── Trash: Soft delete, recoverable for 30 days
└── XP: No penalty for deletion

PREVENT: XP manipulation
├── Server validation: Verify XP claims match actions
├── Rate limiting: Max 1000 XP per hour (sanity check)
├── Audit log: All XP events recorded
└── Philosophy: Assume good faith, detect anomalies
```

---

# PART XIII: IMPLEMENTATION NOTES

## 13.1 Files to Modify (Existing)

```
UI/Plannerum/PlannerumView.swift
├── Add XP module to header
├── Integrate with level system
└── Add Quarter view mode

UI/Plannerum/DayTimelineView.swift
├── Enhance Now Bar with particles
├── Add XP preview to blocks
└── Implement drag-to-schedule

UI/Plannerum/InboxRailView.swift
├── Add Overdue section
├── Implement drag source
└── Add filter persistence

UI/Plannerum/PlannerumTokens.swift
├── Add new block types
├── Add XP animation curves
└── Add accessibility tokens
```

## 13.2 Files to Create (New)

```
UI/Plannerum/NowBarView.swift
├── Particle system
├── Light refraction shader
└── Time label updater

UI/Plannerum/XPTracerView.swift
├── Particle flight animation
├── Bar impact effect
└── Sound trigger

UI/Plannerum/QuarterView.swift
├── Core Objectives display
├── Monthly density grid
└── Before/after comparisons

UI/Plannerum/BlockEditorModal.swift
├── Edit block details
├── Assign tasks
└── Set block type

Data/Models/CoreObjective.swift
├── ObjectiveMetadata struct
├── Progress calculation
└── XP distribution

Voice/Pipeline/PlanneriumVoicePatterns.swift
├── Scheduling patterns
├── Block management patterns
└── Query patterns
```

## 13.3 Integration Points

```
SANCTUARY INTEGRATION
├── XP flows to Sanctuary level system
├── Dimension orbs reflect Planerium activity
├── Insight stream shows scheduling recommendations
└── CI updates in real-time

CAUSALITY ENGINE INTEGRATION
├── Correlation data informs scheduling suggestions
├── HRV predictions feed XP multipliers
├── Historical patterns drive optimal windows
└── Performance metrics update correlations

VOICE SYSTEM INTEGRATION
├── New intents for scheduling
├── Context awareness (current view, selection)
├── Confirmation audio for actions
└── Query responses for schedule

SYNC ENGINE INTEGRATION
├── Real-time sync of schedule changes
├── Conflict resolution for blocks
├── Offline queue for actions
└── Background sync optimization
```

---

# APPENDIX A: REFERENCE TABLES

## A.1 Block Type Quick Reference

| Type | Color | Icon | Dimension | Default Duration |
|------|-------|------|-----------|-----------------|
| Deep Work | #6366F1 | brain.head.profile | Cognitive | 2h |
| Creative | #F59E0B | paintbrush.pointed | Creative | 1.5h |
| Output | #F59E0B | paperplane | Creative | 1h |
| Planning | #8B5CF6 | chart.bar | Knowledge | 1h |
| Training | #EC4899 | book | Knowledge | 1h |
| Rest | #10B981 | leaf | Physiological | 30m |
| Admin | #3B82F6 | tray.full | Behavioral | 30m |
| Meeting | #3B82F6 | person.2 | Behavioral | 30m |

## A.2 XP Base Values (Planerium-Specific)

| Action | Base XP | Dimension |
|--------|---------|-----------|
| Deep Work Hour | 25 | Cognitive |
| Task Completed | 10 | Primary + Behavioral |
| Block Completed | 15 | Block type dimension |
| Schedule Adherence (>80%) | 25 | Behavioral |
| Core Objective Complete | 1000-5000 | All relevant |

## A.3 Animation Timing Quick Reference

| Animation | Duration | Curve |
|-----------|----------|-------|
| Block hover | 120ms | planneriumPrimary |
| Drag start | 150ms | planneriumDrag |
| Block drop | 300ms | planneriumSpring |
| XP tracer flight | 800ms | planneriumXPTracer |
| View switch | 400ms | planneriumSpring |
| Now bar pulse | 2000ms | planneriumNowPulse |

---

*Document Version: 1.0*
*Last Updated: December 2025*
*Architect: Claude*
