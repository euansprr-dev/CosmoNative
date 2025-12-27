# COSMO OS — SANCTUARY DIMENSION SYSTEM
## Master UI/UX Specification v2.0
### Lead Architect: Claude | December 2025

---

# PART I: DESIGN PHILOSOPHY & SYSTEM ARCHITECTURE

## 1.1 Core Vision Statement

COSMO OS Sanctuary is not a dashboard. It is a **neural interface for self-understanding** — a real-time operating system that renders the invisible architecture of your life visible, measurable, and actionable.

The experience must feel like:
- **Apple** designed your life's control center
- **Bungie** crafted the progression systems
- **Porsche** engineered the motion design
- **NASA** built the data visualization

Every pixel serves purpose. Every animation communicates state. Every interaction reveals hidden causality.

---

## 1.2 The Sanctuary Metaphor

The Sanctuary is not a "menu" or "settings screen." It is a **sanctum** — a place where you commune with the data-soul of your existence.

**Spatial Model:**
```
                    ┌─────────────────────────────────────┐
                    │                                     │
                    │         VOID SPACE (Canvas)         │
                    │                                     │
                    │    ┌───────────────────────────┐    │
                    │    │                           │    │
                    │    │   DIMENSION CONSTELLATION │    │
                    │    │                           │    │
                    │    │      ◇───────────◇        │    │
                    │    │     ╱             ╲       │    │
                    │    │    ◇───[ CORE ]───◇      │    │
                    │    │     ╲             ╱       │    │
                    │    │      ◇───────────◇        │    │
                    │    │                           │    │
                    │    └───────────────────────────┘    │
                    │                                     │
                    │         INSIGHT STREAM (Bottom)     │
                    └─────────────────────────────────────┘
```

When a dimension is selected, the entire spatial model **transforms** — the constellation doesn't "open a panel," it **becomes** the dimension's world.

---

## 1.3 Apple Silicon Rendering Pipeline (M4/M5 Optimized)

### Metal 3.1 Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                    COSMO RENDER PIPELINE                        │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐ │
│  │   LAYER 0   │    │   LAYER 1   │    │      LAYER 2        │ │
│  │  Background │───▶│  Particles  │───▶│   UI Components     │ │
│  │   (Metal)   │    │   (Metal)   │    │   (Core Animation)  │ │
│  └─────────────┘    └─────────────┘    └─────────────────────┘ │
│         │                  │                      │             │
│         ▼                  ▼                      ▼             │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              GPU COMPOSITOR (ProMotion 120Hz)            │   │
│  │   • Mesh Gradients via Metal Compute Shaders             │   │
│  │   • Real-time Gaussian Blur (Variable Radius)            │   │
│  │   • Signed Distance Field Rendering for Glows            │   │
│  │   • Instanced Particle Systems (100k+ particles)         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  NEURAL ENGINE INTEGRATION               │   │
│  │   • Predictive Pre-rendering of Likely Transitions       │   │
│  │   • ML-driven Animation Curve Optimization               │   │
│  │   • Anomaly Detection Highlighting (Real-time)           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
```

### Performance Targets

| Metric | Target | Implementation |
|--------|--------|----------------|
| Frame Rate | 120fps sustained | Metal 3.1 + ProMotion sync |
| Transition Latency | <16ms response | Predictive pre-loading |
| Particle Count | 50,000+ simultaneous | GPU instancing |
| Blur Layers | 6 simultaneous | Variable radius Gaussian |
| Memory Footprint | <200MB active | Texture streaming |
| Battery Impact | <5% per hour active | Dynamic quality scaling |

### Apple Silicon Feature Utilization

**M4/M5 Specific:**
- **Ray Tracing Cores**: Ambient occlusion on 3D elements (body silhouette, orbs)
- **Neural Engine (38 TOPS+)**: Real-time insight correlation highlighting
- **Unified Memory (32GB+)**: Full constellation graph in memory
- **ProMotion 120Hz**: True 120fps animations with dynamic refresh
- **HDR Display Engine**: 1600 nits peak for glow effects

---

## 1.4 Global Material Language

### Surface Types

```
┌─────────────────────────────────────────────────────────────┐
│                    COSMO MATERIAL SYSTEM                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  GLASS-PRIMARY                                               │
│  ├── Background: rgba(15, 15, 20, 0.85)                     │
│  ├── Blur: 40px Gaussian                                     │
│  ├── Border: 1px rgba(255, 255, 255, 0.08)                  │
│  ├── Inner Shadow: inset 0 1px 0 rgba(255,255,255,0.05)     │
│  └── Corner Radius: 24px                                     │
│                                                              │
│  GLASS-SECONDARY                                             │
│  ├── Background: rgba(25, 25, 35, 0.7)                      │
│  ├── Blur: 24px Gaussian                                     │
│  ├── Border: 1px rgba(255, 255, 255, 0.05)                  │
│  └── Corner Radius: 16px                                     │
│                                                              │
│  GLASS-ACCENT (Dimension-Colored)                            │
│  ├── Background: dimension_color @ 12% opacity               │
│  ├── Blur: 32px Gaussian                                     │
│  ├── Border: 1px dimension_color @ 25% opacity               │
│  ├── Glow: 0 0 40px dimension_color @ 20%                   │
│  └── Corner Radius: 20px                                     │
│                                                              │
│  VOID-SURFACE                                                │
│  ├── Background: radial-gradient(ellipse at center,         │
│  │               rgba(20,20,30,1) 0%,                        │
│  │               rgba(8,8,12,1) 100%)                        │
│  ├── Noise Overlay: 2% monochrome grain                      │
│  └── Vignette: radial 40% fade to black at edges            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Dimension Color System

```
COGNITIVE      #6366F1 (Indigo)      → Mind, Focus, Depth
CREATIVE       #F59E0B (Amber)       → Energy, Expression, Fire
PHYSIOLOGICAL  #10B981 (Emerald)     → Life, Vitality, Growth
BEHAVIORAL     #3B82F6 (Blue)        → Structure, Discipline, Flow
KNOWLEDGE      #8B5CF6 (Violet)      → Wisdom, Connection, Expansion
REFLECTION     #EC4899 (Pink)        → Heart, Introspection, Soul
```

Each color has 5 variants:
- **Primary**: Base color (100%)
- **Muted**: 60% saturation
- **Glow**: 120% brightness, 40% opacity (for halos)
- **Deep**: 70% brightness (for backgrounds)
- **Accent**: 110% saturation (for highlights)

---

## 1.5 Typography System

```
DISPLAY LARGE    SF Pro Display    48pt   Bold      -0.02em   Titles
DISPLAY MEDIUM   SF Pro Display    32pt   Semibold  -0.01em   Section Headers
HEADLINE         SF Pro Display    24pt   Semibold   0.00em   Card Titles
BODY LARGE       SF Pro Text       17pt   Regular    0.00em   Primary Content
BODY             SF Pro Text       15pt   Regular    0.01em   Secondary Content
CAPTION          SF Pro Text       13pt   Medium     0.02em   Labels, Metadata
MONO SMALL       SF Mono           12pt   Medium     0.04em   Data Values, Stats
MONO LARGE       SF Mono           20pt   Bold       0.02em   Hero Metrics
```

### Numeric Display Rules
- **All metrics** use SF Mono for alignment
- **Percentages** always show 1 decimal (e.g., "78.4%")
- **Large numbers** use locale-appropriate separators
- **Time values** use 24h format internally, user-preference display
- **Trend indicators** use ▲ ▼ ─ symbols with color coding

---

## 1.6 Motion Design Language

### Timing Functions (Core Animation)

```swift
// COSMO Standard Curves
static let cosmoPrimary = CAMediaTimingFunction(controlPoints: 0.2, 0.0, 0.0, 1.0)
static let cosmoSecondary = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)
static let cosmoSpring = CASpringAnimation(mass: 1.0, stiffness: 300, damping: 25)
static let cosmoBounce = CASpringAnimation(mass: 0.8, stiffness: 400, damping: 18)
static let cosmoGentle = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.1, 1.0)
```

### Duration Standards

| Transition Type | Duration | Curve |
|-----------------|----------|-------|
| Micro (hover, press) | 120ms | cosmoPrimary |
| Small (card expand) | 200ms | cosmoPrimary |
| Medium (panel slide) | 350ms | cosmoSecondary |
| Large (view transition) | 500ms | cosmoSpring |
| Cinematic (dimension zoom) | 800ms | cosmoGentle |
| Ambient (background loops) | 3000-8000ms | linear |

### Stagger Patterns

When multiple elements animate:
```
Element 1: delay 0ms
Element 2: delay 50ms
Element 3: delay 100ms
Element 4: delay 150ms
...
Max stagger: 400ms total
```

---

## 1.7 Constellation Interaction System

This is the **signature interaction** of COSMO — when a user taps any data point, correlation lines animate outward to connected nodes.

### Line Rendering Spec

```
┌─────────────────────────────────────────────────────────────┐
│                 CONSTELLATION LINE SYSTEM                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  SOURCE NODE                                                 │
│       ●──────────────────────────────────────●              │
│       │           Animated Path               │              │
│       │                                       │              │
│  Line Properties:                                            │
│  ├── Stroke: 1.5px                                          │
│  ├── Color: gradient from source_color → target_color       │
│  ├── Opacity: 0.6 base, 0.9 on hover                        │
│  ├── Dash Pattern: none (solid)                             │
│  ├── Glow: 0 0 8px source_color @ 40%                       │
│  └── Animation: stroke-dashoffset reveal over 400ms         │
│                                                              │
│  Correlation Strength Encoding:                              │
│  ├── Strong (r > 0.7): 2px stroke, bright glow              │
│  ├── Medium (r 0.4-0.7): 1.5px stroke, subtle glow          │
│  ├── Weak (r < 0.4): 1px stroke, no glow, 40% opacity       │
│  └── Negative: dashed pattern, red tint                      │
│                                                              │
│  Info Card (appears at midpoint):                            │
│  ┌──────────────────────────────┐                           │
│  │  "HRV ↔ Deep Work Quality"   │                           │
│  │  r = 0.73 (Strong)           │                           │
│  │  ▲ When HRV > 45ms,          │                           │
│  │    focus duration +23%       │                           │
│  └──────────────────────────────┘                           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

# PART II: SANCTUARY HOME (MAIN HUB)

## 2.1 Spatial Layout — SANCTUARY HOME

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ │
│                                                                                         │
│   ◀ Back    S A N C T U A R Y                                                          │
│             ═══════════════════                                                         │
│                                                            ┌─────────────────────────┐  │
│             Level 24 • Pathfinder                          │  ● LIVE   HRV: 48ms     │  │
│             ████████████████████░░░░░  78.4%               │  Focus: 82%  Energy: 71%│  │
│             XP: 12,847 / 16,000 to Level 25                └─────────────────────────┘  │
│                                                                                         │
│ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ │
│                                                                                         │
│                                                                                         │
│                              ┌───────────────────┐                                      │
│                              │    ◇ COGNITIVE    │                                      │
│                              │    Level 18       │                                      │
│                              │  ████████░░ 82%   │                                      │
│                              └─────────┬─────────┘                                      │
│                                   ╱    │    ╲                                           │
│                                  ╱     │     ╲                                          │
│         ┌──────────────────┐   ╱      │      ╲   ┌──────────────────┐                  │
│         │   ◇ CREATIVE     │  ╱       │       ╲  │   ◇ KNOWLEDGE    │                  │
│         │   Level 21       │╱─────────│─────────╲│   Level 22       │                  │
│         │ ██████████░ 91%  │          │          │ ███████░░░ 74%   │                  │
│         └────────┬─────────┘          │          └─────────┬────────┘                  │
│                  │                    │                    │                            │
│                  │       ┌────────────┴────────────┐       │                            │
│                  │       │                         │       │                            │
│                  │       │    ╭─────────────────╮  │       │                            │
│                  │       │   ╱  ╭─────────────╮  ╲ │       │                            │
│                  │       │  │  ╱  ╭─────────╮  ╲  ││       │                            │
│                  │       │  │ │  │   HERO   │  │ ││       │                            │
│                  ├───────┼──┤ │  │   CORE   │  │ ├┼───────┤                            │
│                  │       │  │ │  │    24    │  │ ││       │                            │
│                  │       │  │  ╲  ╰─────────╯  ╱  ││       │                            │
│                  │       │   ╲  ╰─────────────╯  ╱ │       │                            │
│                  │       │    ╰─────────────────╯  │       │                            │
│                  │       │         CI: 78.4        │       │                            │
│                  │       └────────────┬────────────┘       │                            │
│                  │                    │                    │                            │
│         ┌────────┴─────────┐          │          ┌────────┴─────────┐                  │
│         │ ◇ PHYSIOLOGICAL  │╲─────────│─────────╱│   ◇ BEHAVIORAL   │                  │
│         │   Level 19       │ ╲        │        ╱ │   Level 17       │                  │
│         │ ████████░░░ 78%  │  ╲       │       ╱  │ ██████████░ 88%  │                  │
│         └──────────────────┘   ╲      │      ╱   └──────────────────┘                  │
│                                 ╲     │     ╱                                           │
│                                  ╲    │    ╱                                            │
│                              ┌─────────┴─────────┐                                      │
│                              │   ◇ REFLECTION    │                                      │
│                              │   Level 15        │                                      │
│                              │ ██████░░░░░ 62%   │                                      │
│                              └───────────────────┘                                      │
│                                                                                         │
│ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ │
│                                                                                         │
│   I N S I G H T   S T R E A M                                                          │
│   ════════════════════════════                                                          │
│                                                                                         │
│  ┌─────────────────────────┐ ┌─────────────────────────┐ ┌─────────────────────────┐   │
│  │ ◆ PREDICTION            │ │ ⚡ CORRELATION          │ │ ★ ACHIEVEMENT           │   │
│  │                         │ │                         │ │                         │   │
│  │ Sleep before 11pm to    │ │ HRV ↔ Deep Work        │ │ 7-Day Deep Work Streak  │   │
│  │ boost Cognitive +13%    │ │ r = 0.73 (Strong)      │ │ Unlocked!               │   │
│  │                         │ │                         │ │                         │   │
│  │ ─────────────────────── │ │ ─────────────────────── │ │ ─────────────────────── │   │
│  │ Confidence: 87%  +340XP │ │ Tap to explore →       │ │ +500 XP  •  New Badge   │   │
│  └─────────────────────────┘ └─────────────────────────┘ └─────────────────────────┘   │
│                                                                                         │
│  ◀ ═══════════════════════════════════════════════════════════════════════════════ ▶   │
│                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### Home View Component Breakdown

```
HEADER ZONE (Top 120pt)
├── Back navigation (if entered from canvas)
├── "SANCTUARY" title — SF Pro Display 32pt Bold
├── Level badge: "Level 24 • Pathfinder"
├── XP Progress bar with current/target
└── Live metrics panel (top-right floating)
    ├── Live indicator (pulsing green dot)
    ├── Current HRV
    ├── Focus Score
    └── Energy Level

CONSTELLATION ZONE (Center 480pt)
├── Hero Core Orb (160pt diameter, center)
│   ├── 3 rotating energy rings
│   ├── Cosmo Index display
│   └── XP progress ring
├── 6 Dimension Orbs (72pt each, 190pt from center)
│   ├── Each shows: icon, level, health bar
│   └── Connection lines between adjacent orbs
└── Ambient particle field (subtle, 20-30 particles)

INSIGHT STREAM (Bottom 140pt)
├── Horizontal scroll carousel
├── Card types: Prediction, Correlation, Achievement, Warning, Insight
├── Snap-to-card scrolling
└── 24pt peek of adjacent cards
```

## 2.2 Hero Core Orb

The central element — represents the unified Cosmo Index.

### Visual Specification

```
┌─────────────────────────────────────────────────────────────┐
│                      HERO CORE ORB                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Size: 160×160pt                                             │
│                                                              │
│  Layers (back to front):                                     │
│                                                              │
│  1. OUTER HALO                                               │
│     ├── Radial gradient: transparent → dimension_blend       │
│     ├── Size: 280×280pt                                      │
│     ├── Blur: 60px                                           │
│     ├── Opacity: 0.3                                         │
│     └── Animation: slow pulse (4s cycle, 0.95-1.05 scale)   │
│                                                              │
│  2. ENERGY RINGS (3 concentric)                              │
│     ├── Ring 1: r=90pt, 2px stroke, rotating CW @ 20s       │
│     ├── Ring 2: r=100pt, 1.5px stroke, rotating CCW @ 30s   │
│     ├── Ring 3: r=110pt, 1px stroke, rotating CW @ 45s      │
│     ├── Each ring: angular gradient with gaps                │
│     └── Glow: dimension_color @ 40%                          │
│                                                              │
│  3. CORE SPHERE                                              │
│     ├── Base: radial gradient (white center → indigo edge)  │
│     ├── Size: 120×120pt                                      │
│     ├── Inner glow: white @ 50%, 20px radius                │
│     ├── Surface: animated noise texture (Metal shader)       │
│     └── Shadow: 0 20px 60px rgba(0,0,0,0.4)                 │
│                                                              │
│  4. LEVEL DISPLAY                                            │
│     ├── "CI" label: 10pt, white @ 70%                        │
│     ├── Level number: 36pt SF Mono Bold, white               │
│     └── XP ring: circular progress, 2pt stroke, green        │
│                                                              │
│  5. LIVE METRICS ORBIT                                       │
│     ├── 3-4 small indicators orbiting core                   │
│     ├── Each: 8pt circle with value                          │
│     ├── HRV, Focus Score, Energy Level                       │
│     └── Animation: orbit at different speeds                 │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Hero Orb Interaction

```
STATE: Idle
├── Rings rotating slowly
├── Gentle pulse (breathing)
└── Live metrics orbiting

STATE: Hover
├── Scale to 1.05
├── Rings speed up 2x
├── Glow intensifies
└── Cursor: pointer

STATE: Pressed
├── Scale to 0.95
├── Rings pause briefly
├── Haptic feedback (if available)
└── Glow pulses outward

STATE: Tap Complete
├── Trigger "Cosmo Index Detail" overlay
├── Expanding ripple effect
└── All dimension orbs pulse in sync
```

## 2.3 Dimension Orbs

Each of the 6 orbs surrounding the hero core.

### Base Specification (Shared)

```
┌─────────────────────────────────────────────────────────────┐
│                    DIMENSION ORB (Base)                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Size: 72×72pt (tappable area: 88×88pt)                     │
│  Position: 190pt from center, hexagonal arrangement          │
│                                                              │
│  Layers:                                                     │
│                                                              │
│  1. AMBIENT GLOW                                             │
│     ├── Radial: dimension_color → transparent                │
│     ├── Size: 120×120pt                                      │
│     ├── Blur: 30px                                           │
│     └── Opacity: health_score * 0.4 (brighter = healthier)  │
│                                                              │
│  2. ORB BODY                                                 │
│     ├── Circle: 72×72pt                                      │
│     ├── Fill: radial gradient                                │
│     │   └── white@15% center → dimension_color@90% edge     │
│     ├── Border: 1.5px dimension_color @ 50%                  │
│     └── Shadow: 0 8px 24px rgba(0,0,0,0.3)                  │
│                                                              │
│  3. INNER ICON                                               │
│     ├── SF Symbol: dimension-specific                        │
│     ├── Size: 28pt                                           │
│     ├── Color: white                                         │
│     └── Weight: medium                                       │
│                                                              │
│  4. STATUS RING                                              │
│     ├── Circular progress indicator                          │
│     ├── Shows dimension "health" (0-100%)                    │
│     ├── Stroke: 3pt                                          │
│     └── Cap: round                                           │
│                                                              │
│  5. LABEL                                                    │
│     ├── Position: below orb, 8pt gap                         │
│     ├── Text: dimension name                                 │
│     ├── Font: 11pt SF Pro Text Medium                        │
│     └── Color: white @ 80%                                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Dimension Icons

```
COGNITIVE      brain.head.profile
CREATIVE       paintbrush.pointed
PHYSIOLOGICAL  heart.text.square
BEHAVIORAL     chart.bar.doc.horizontal
KNOWLEDGE      books.vertical
REFLECTION     brain
```

## 2.4 Connection Lines

Lines connecting dimension orbs in hexagonal pattern.

```
Line Properties:
├── Stroke: 1px
├── Color: gradient between connected dimension colors
├── Opacity: 0.25 (idle), 0.5 (when either orb hovered)
├── Style: solid
└── Animation: subtle pulse traveling along line (8s cycle)
```

## 2.5 Insight Stream

Horizontal scrolling carousel at bottom.

```
┌─────────────────────────────────────────────────────────────┐
│                     INSIGHT STREAM                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Position: bottom, 48pt from edge                            │
│  Height: 100pt                                               │
│  Width: 100% - 64pt margins                                  │
│                                                              │
│  Card Specifications:                                        │
│                                                              │
│  ┌────────────────────────────────────┐                     │
│  │ ◆ PREDICTION                        │  Card Type Badge   │
│  │                                      │                    │
│  │ "Sleep before 11pm tonight to       │  Main Text         │
│  │  boost Cognitive +13% tomorrow"     │                    │
│  │                                      │                    │
│  │ ───────────────────────────────     │  Separator         │
│  │ Confidence: 87%  •  +340 XP         │  Metadata          │
│  └────────────────────────────────────┘                     │
│                                                              │
│  Card Dimensions: 320×88pt                                   │
│  Gap: 16pt                                                   │
│  Scroll: horizontal, snap to card                            │
│  Peek: 24pt of adjacent cards visible                        │
│                                                              │
│  Card Types:                                                 │
│  ├── PREDICTION (amber icon)                                 │
│  ├── CORRELATION (blue icon)                                 │
│  ├── ACHIEVEMENT (green icon)                                │
│  ├── WARNING (red icon)                                      │
│  └── INSIGHT (purple icon)                                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## 2.6 Dimension Zoom Transition

When user taps a dimension orb, this cinematic transition occurs:

### Transition Sequence (800ms total)

```
T=0ms     User taps dimension orb
          ├── Haptic feedback
          └── Orb scales to 1.15

T=50ms    Other orbs begin fading
          ├── Opacity: 1.0 → 0.0 over 300ms
          └── Scale: 1.0 → 0.9 over 300ms

T=100ms   Tapped orb begins expansion
          ├── Scale: 1.15 → fills viewport
          ├── Position: moves to center
          └── Hero core fades (opacity → 0)

T=200ms   Background shift begins
          ├── Void darkens slightly
          └── Dimension color tints edges

T=350ms   Connection lines fade completely
          └── Insight stream slides down (out of view)

T=500ms   Dimension HUD begins rendering
          ├── Elements fade in with stagger
          └── Charts begin animating

T=700ms   Header transitions
          ├── "Sanctuary" → Dimension name
          └── Back button appears

T=800ms   Transition complete
          └── Full dimension view interactive
```

### Reverse Transition (600ms)

```
T=0ms     User taps back or swipes right
          └── Dimension content begins fading

T=100ms   Hero core begins appearing at center
          └── Opacity: 0 → 1

T=200ms   Dimension orb contracts
          ├── Scale: full → 72pt
          └── Position: center → hex position

T=300ms   Other orbs fade in
          └── Connection lines appear

T=500ms   Insight stream slides up
          └── Header reverts to "Sanctuary"

T=600ms   Transition complete
          └── Home view interactive
```

---

# PART III: DIMENSION-SPECIFIC DESIGNS

---

## 3.1 COGNITIVE DIMENSION

### Concept: "The Mind Core"

A layered visualization of mental energy, focus patterns, and cognitive performance — rendered as concentric rings of data surrounding a pulsing "consciousness nucleus." The entire interface pulses with your mental state.

### Full Layout Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ │
│                                                                                             │
│  ◀ Sanctuary          C O G N I T I V E                                                    │
│                       ═══════════════════                                                   │
│                       Mind Core • Level 18                              ┌────────────────┐  │
│                       ████████████████░░░░  82%                         │ ● LIVE         │  │
│                                                                         │ NELO: 42.3    │  │
│ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄│ ● Balanced     │  │
│                                                                         └────────────────┘  │
│  ┌───────────────────────────────────────────────────────────────────────────────────────┐  │
│  │  D E E P   W O R K   T I M E L I N E                                                  │  │
│  │  ════════════════════════════════════                                                 │  │
│  │                                                                                        │  │
│  │       6am     8am     10am    12pm    2pm     4pm     6pm     8pm     10pm           │  │
│  │        │       │       │       │       │       │       │       │       │             │  │
│  │  ──────┼───────┼───────┼───────┼───────┼───────┼───────┼───────┼───────┼──────       │  │
│  │        │       │  ┌────┴────┐  │  ┌────┴────────┴────┐  │       │       │             │  │
│  │        │       │  │ CODING  │  │  │  WRITING SESSION │  │       │       │             │  │
│  │        │       │  │ 2h 15m  │  │  │     3h 42m       │  │       │       │             │  │
│  │        │       │  │ Q: 87%  │  │  │     Q: 92%       │  │       │       │             │  │
│  │        │       │  └─────────┘  │  └──────────────────┘  │       │       │             │  │
│  │        │       │       │       │          │             │       │       │             │  │
│  │        ▼       │       │       │          ▼ NOW         │       │       │             │  │
│  │     ┌──────┐   │       │       │       ┌──────┐        │       │       │             │  │
│  │     │SLEEP │   │       │       │       │◆PRED │ ← 2pm-4pm optimal                    │  │
│  │     └──────┘   │       │       │       └──────┘        │       │       │             │  │
│  │                                                                                        │  │
│  │  Today: 5h 57m deep work  •  Quality avg: 89%  •  Predicted remaining capacity: 2h   │  │
│  └───────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                             │
│  ┌─────────────────────────────────────────────────┐  ┌──────────────────────────────────┐  │
│  │                                                  │  │                                  │  │
│  │            M E N T A L   E N E R G Y             │  │   H O U R L Y   F O R E C A S T  │  │
│  │            ═══════════════════════════           │  │   ═════════════════════════════  │  │
│  │                                                  │  │                                  │  │
│  │            ╭────────────────────────╮           │  │   PREDICTED PERFORMANCE WINDOWS  │  │
│  │           ╱   ╭────────────────╮     ╲          │  │                                  │  │
│  │          │   ╱  ╭────────────╮  ╲     │         │  │   ★ 2:00pm - 4:00pm  89% conf   │  │
│  │          │  │  ╱ ╭────────╮  ╲  │     │         │  │     Primary window              │  │
│  │          │  │ │ ╱ NUCLEUS ╲ │  │     │         │  │     Recommended: Complex tasks   │  │
│  │          │  │ │ │    ██    │ │  │     │         │  │                                  │  │
│  │          │  │ │ │  78.4    │ │  │     │         │  │   ○ 9:30am - 11:00am  72% conf  │  │
│  │          │  │ │ ╲   CI    ╱ │  │     │         │  │     Secondary window             │  │
│  │          │  │  ╲ ╰────────╯ ╱  │     │         │  │     Recommended: Planning        │  │
│  │          │   ╲  ╰────────────╯ ╱      │         │  │                                  │  │
│  │           ╲   ╰────────────────╯     ╱          │  │   ✕ 12:00pm - 1:30pm  Low       │  │
│  │            ╰────────────────────────╯           │  │     Post-lunch dip expected     │  │
│  │                                                  │  │                                  │  │
│  │     ┌─── FOCUS STABILITY RING (outer)           │  │   Based on: HRV pattern, sleep, │  │
│  │     │    24 segments = 24 hours                 │  │   historical performance, meals  │  │
│  │     │    Color: green=stable, red=unstable     │  │                                  │  │
│  │     │                                           │  └──────────────────────────────────┘  │
│  │     └─── COGNITIVE LOAD RING (inner)            │                                        │
│  │          Particle flow speed = current load     │  ┌──────────────────────────────────┐  │
│  │                                                  │  │                                  │  │
│  │   ┌──────────────┐       ┌──────────────┐       │  │   J O U R N A L   D E N S I T Y  │  │
│  │   │ NELO SCORE   │       │ FOCUS INDEX  │       │  │   ═════════════════════════════  │  │
│  │   │              │       │              │       │  │                                  │  │
│  │   │ ~~~╱╲~~~     │       │   ████████   │       │  │   Insight markers today: 7      │  │
│  │   │    42.3      │       │     91%      │       │  │   Reflection depth: 8.2/10      │  │
│  │   │ ● Balanced   │       │   ● Peak     │       │  │   Themes detected: 3            │  │
│  │   └──────────────┘       └──────────────┘       │  │   ─────────────────────────     │  │
│  │                                                  │  │   "Recurring focus on           │  │
│  └─────────────────────────────────────────────────┘  │    delegation patterns..."       │  │
│                                                        └──────────────────────────────────┘  │
│                                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────────────────────┐  │
│  │  C O R R E L A T I O N   M A P                                                        │  │
│  │  ═════════════════════════════                                                        │  │
│  │                                                                                        │  │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │  │
│  │  │ HRV → Focus     │  │ Sleep → Clarity │  │ Caffeine →      │  │ Breaks →        │  │  │
│  │  │                 │  │                 │  │ Alertness       │  │ Sustainability  │  │  │
│  │  │ ┌─────────────┐ │  │ ┌─────────────┐ │  │ ┌─────────────┐ │  │ ┌─────────────┐ │  │  │
│  │  │ │ ╱╲  ╱╲     │ │  │ │    ╱╲  ╱╲   │ │  │ │╱╲          │ │  │ │   ╱╲   ╱╲   │ │  │  │
│  │  │ │╱  ╲╱  ╲╱╲  │ │  │ │╱╲ ╱  ╲╱  ╲  │ │  │ │  ╲╱╲  ╱╲  │ │  │ │╱╲╱  ╲ ╱  ╲  │ │  │  │
│  │  │ └─────────────┘ │  │ └─────────────┘ │  │ └─────────────┘ │  │ └─────────────┘ │  │  │
│  │  │                 │  │                 │  │                 │  │                 │  │  │
│  │  │   r = 0.73      │  │   r = 0.68      │  │   r = 0.45      │  │   r = 0.61      │  │  │
│  │  │  ● Strong ▲     │  │  ● Strong ▲     │  │  ○ Moderate     │  │  ● Strong ▲     │  │  │
│  │  │                 │  │                 │  │                 │  │                 │  │  │
│  │  │  When HRV >45ms │  │  When sleep >7h │  │  Optimal: 2pm   │  │  Every 90min    │  │  │
│  │  │  focus +23%     │  │  clarity +31%   │  │  caffeine       │  │  sustain +18%   │  │  │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘  └─────────────────┘  │  │
│  │                                                                                        │  │
│  │  Tap any correlation to see full causal analysis →                                    │  │
│  └───────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────────────────────┐  │
│  │  I N T E R R U P T I O N   T I M E L I N E                                            │  │
│  │  ═════════════════════════════════════════                                            │  │
│  │                                                                                        │  │
│  │      6am      8am      10am     12pm     2pm      4pm      6pm      8pm              │  │
│  │       │        │        │        │        │        │        │        │               │  │
│  │  ─────┼────────┼────────┼────────┼────────┼────────┼────────┼────────┼───────        │  │
│  │       │        │   ●●   │   ●    │        │  ●●●   │   ●    │        │               │  │
│  │       │        │  Slack │  Meet  │        │ Slack  │  Notif │        │               │  │
│  │       │        │   (2)  │  (1)   │        │  (3)   │   (1)  │        │               │  │
│  │                                                                                        │  │
│  │  Total interruptions: 8  •  Avg recovery time: 4.2min  •  Focus cost: ~34min lost    │  │
│  │                                                                                        │  │
│  │  Top disruptors: Slack (5) • Meetings (2) • Notifications (1)                        │  │
│  └───────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────────────────────┐  │
│  │  ◆ PREDICTION                                                              87% conf   │  │
│  │                                                                                        │  │
│  │  "If you take a 15-minute break now, your 2pm-4pm deep work session is predicted     │  │
│  │   to be 23% more productive. Current cognitive load is elevated."                     │  │
│  │                                                                                        │  │
│  │  ──────────────────────────────────────────────────────────────────────────────────   │  │
│  │  Based on: NELO score, time since last break, historical patterns     [ 🔔 Remind ]  │  │
│  └───────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                             │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Component Specifications

```
MENTAL ENERGY NUCLEUS (Central Visualization)
├── Size: 280×280pt total area
├── Core sphere: 120pt diameter
│   ├── Radial gradient: white center → indigo edge
│   ├── Metal shader: animated plasma/noise
│   ├── Brightness: correlates to focus score
│   └── Pulse: synced to NELO rhythm
├── Focus Stability Ring (outer, r=120pt)
│   ├── 24 segments representing hours
│   ├── Color per segment: stability score
│   │   ├── Green (#10B981): >80% stable
│   │   ├── Yellow (#F59E0B): 50-80%
│   │   ├── Red (#EF4444): <50%
│   │   └── Gray: no data / sleep
│   └── Current hour: pulsing indicator
└── Cognitive Load Ring (inner, r=80pt)
    ├── Particle stream flowing clockwise
    ├── Speed: proportional to load level
    └── Color: cyan (low) → red (high)

NELO SCORE CARD
├── Waveform visualization (real-time)
├── Numeric value: 42.3
├── Status: Balanced / Elevated / Depleted
└── Optimal range indicator

CORRELATION CARDS (Horizontal scroll)
├── Each card: 160×140pt
├── Sparkline graph (7-day data)
├── Correlation coefficient (r value)
├── Strength indicator: Strong/Moderate/Weak
└── Action insight: "When X, then Y"
```

### Data Requirements (Extended)

```swift
struct CognitiveDimensionData {
    // Core Metrics
    var cognitiveIndex: Double              // 0-100
    var neloScore: Double                   // Neuro-Energetic Load Oscillation
    var neloWaveform: [Double]              // Real-time waveform data
    var neloStatus: NELOStatus              // balanced, elevated, depleted
    var focusIndex: Double                  // 0-100 current focus quality

    // Focus Stability (24-hour breakdown)
    var focusStabilityByHour: [Int: Double] // Hour -> stability percentage
    var cognitiveLoadCurrent: Double        // Current load 0-100
    var cognitiveLoadHistory: [Double]      // Last 60 minutes

    // Deep Work Sessions
    var deepWorkSessions: [DeepWorkSession]
    var totalDeepWorkToday: TimeInterval
    var averageQualityToday: Double
    var predictedCapacityRemaining: TimeInterval

    // Predictions
    var predictedOptimalWindows: [CognitiveWindow]
    var currentWindowStatus: WindowStatus   // in_window, approaching, passed

    // Interruptions
    var interruptions: [Interruption]
    var totalInterruptionsToday: Int
    var averageRecoveryTime: TimeInterval
    var focusCostMinutes: Int               // Estimated lost productivity
    var topDisruptors: [(source: String, count: Int)]

    // Correlations
    var topCorrelations: [CognitiveCorrelation]

    // Journal Integration
    var journalInsightMarkersToday: Int
    var reflectionDepthScore: Double        // 0-10
    var detectedThemes: [String]
    var journalExcerpt: String?
}

struct DeepWorkSession {
    var id: UUID
    var startTime: Date
    var endTime: Date?
    var taskType: TaskType                  // coding, writing, research, planning
    var qualityScore: Double                // 0-100
    var flowMinutes: Int                    // Time in flow state
    var interruptionCount: Int
    var notes: String?
}

struct CognitiveWindow {
    var startTime: DateComponents
    var endTime: DateComponents
    var confidence: Double                  // 0-100
    var isPrimary: Bool
    var recommendedTaskTypes: [TaskType]
    var basedOn: [String]                   // Contributing factors
}

struct Interruption {
    var timestamp: Date
    var source: InterruptionSource          // slack, meeting, notification, self
    var app: String?
    var recoveryMinutes: Double
    var severityScore: Double               // 0-1
}

struct CognitiveCorrelation {
    var sourceMetric: String
    var targetMetric: String
    var coefficient: Double                 // -1 to 1
    var strength: CorrelationStrength       // strong, moderate, weak
    var trend: TrendDirection               // up, down, stable
    var sparklineData: [Double]             // Last 7 days
    var actionInsight: String               // "When X > Y, then Z"
    var sampleSize: Int
}
```

### Animation Sequences

```
ENTRY TRANSITION (800ms):
├── T=0ms: Background dims, indigo tint appears at edges
├── T=100ms: Nucleus fades in at center (scale 0.3 → 1.0)
├── T=200ms: Focus Stability Ring draws clockwise
├── T=300ms: Cognitive Load particles start flowing
├── T=400ms: Deep Work Timeline slides down from top
├── T=500ms: Side panels (Forecast, Journal) fade in
├── T=600ms: Correlation cards stagger in left-to-right
├── T=700ms: Interruption Timeline slides up from bottom
└── T=800ms: Prediction card fades in, all interactive

NUCLEUS IDLE STATE:
├── Plasma texture: continuous animation (Metal shader)
├── Pulse: 3s cycle, scale 0.98-1.02, synced to NELO
├── Rings: slow rotation (outer CW 30s, inner CCW 45s)
├── Particles: continuous flow, speed = cognitive load
└── Glow: intensity = focus score

CORRELATION TAP INTERACTION:
├── T=0ms: Card lifts (shadow increases, scale 1.05)
├── T=100ms: HUD lines begin drawing to connected metrics
├── T=300ms: Info overlay fades in at midpoint of lines
├── T=400ms: Other cards dim to 50% opacity
└── Dismiss: tap elsewhere, lines retract, cards restore

DEEP WORK SESSION START:
├── Notification: subtle pulse on timeline
├── New block appears with "ACTIVE" badge
├── Nucleus glow intensifies
└── Focus ring segment begins filling
```

---

## 3.2 CREATIVE DIMENSION

### Concept: "The Creator's Console"

A professional-grade analytics HUD for content performance — feels like Bloomberg Terminal meets NASA Mission Control, designed by Apple. This is the most data-heavy dashboard, optimized for creators who want deep insights into their content performance.

### Full Layout Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ │
│                                                                                             │
│  ◀ Sanctuary          C R E A T I V E                                                      │
│                       ═══════════════════                                                   │
│                       Creator's Console • Level 21                     ┌────────────────┐  │
│                       ██████████████████░░  91%                        │ ● LIVE         │  │
│                                                                        │ Posting in 2h  │  │
│ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄│ Best: 3:15pm   │  │
│                                                                        └────────────────┘  │
│  ┌───────────────────────────────────────────────────────────────────────────────────────┐  │
│  │  H E R O   M E T R I C S                                                              │  │
│  │  ═══════════════════════                                                              │  │
│  │                                                                                        │  │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │  │
│  │  │ │ TOTAL REACH   │  │ │ ENGAGEMENT    │  │ │ FOLLOWERS     │  │ │ GROWTH RATE   │  │  │
│  │  │ │               │  │ │               │  │ │               │  │ │               │  │  │
│  │  │ │   847.2K      │  │ │    4.7%       │  │ │   23,418      │  │ │  +2.1%/wk     │  │  │
│  │  │ │               │  │ │               │  │ │               │  │ │               │  │  │
│  │  │ │   ▲ +12.3%    │  │ │   ▲ +0.3%     │  │ │   ▲ +847      │  │ │   ● Strong    │  │  │
│  │  │ │   vs last 30d │  │ │   vs last 30d │  │ │   this week   │  │ │   trajectory  │  │  │
│  │  │ └───────────────│  │ └───────────────│  │ └───────────────│  │ └───────────────│  │  │
│  │  │    ╱╲ ╱╲╱╲__    │  │    __╱╲ ╱╲___  │  │    ___╱╱╱╱     │  │    ╱╱╱╱╱        │  │  │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘  └─────────────────┘  │  │
│  │                                                                                        │  │
│  └───────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                             │
│  ┌─────────────────────────────────────────────────────┐  ┌──────────────────────────────┐  │
│  │  P E R F O R M A N C E   G R A P H                  │  │  P O S T I N G   C A L E N D AR│  │
│  │  ═══════════════════════════════════                │  │  ════════════════════════════  │  │
│  │                                                      │  │                                │  │
│  │  [ 7d ] [ 14d ] [●30d ] [ 60d ] [ 90d ] [ 1Y ]     │  │   Dec 2025                     │  │
│  │                                                      │  │   M  T  W  T  F  S  S         │  │
│  │      120K ┤                                         │  │   ■  □  ■  ■  □  ■  □         │  │
│  │           │              ╱╲                         │  │   ■  ■  □  ■  ■  □  ■         │  │
│  │       90K ┤         ╱╲  ╱  ╲                       │  │   ■  □  ■  □  ■  ■  □         │  │
│  │           │    ╱╲  ╱  ╲╱    ╲   ╱╲                 │  │   □  ★  ■  ■  ◐  ·  ·         │  │
│  │       60K ┤  ╱   ╲╱          ╲ ╱  ╲                │  │                                │  │
│  │           │ ╱                  ╲    ╲___           │  │   ■ Posted  □ Skipped         │  │
│  │       30K ┤╱                                        │  │   ★ Viral   ◐ Today           │  │
│  │           │                                         │  │                                │  │
│  │         0 ┴──────────────────────────────────────  │  │   Streak: 12 days 🔥           │  │
│  │           Dec 1                        Dec 21      │  │   Best posting time: 3:15pm   │  │
│  │                                                      │  │   Most active: Wednesday      │  │
│  │   ── Reach (primary)  ╌╌ Engagement  ·· Followers  │  │   Avg posts/week: 4.2         │  │
│  │                                                      │  │                                │  │
│  └─────────────────────────────────────────────────────┘  └──────────────────────────────┘  │
│                                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────────────────────┐  │
│  │  R E C E N T   P O S T S                                              [See All →]     │  │
│  │  ═══════════════════════                                                              │  │
│  │                                                                                        │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │  │
│  │  │ ┌─────────┐ │  │ ┌─────────┐ │  │ ┌─────────┐ │  │ ┌─────────┐ │  │ ┌─────────┐ │  │  │
│  │  │ │ ◆ VIRAL │ │  │ │         │ │  │ │         │ │  │ │         │ │  │ │         │ │  │  │
│  │  │ │ ┌─────┐ │ │  │ │ ┌─────┐ │ │  │ │ ┌─────┐ │ │  │ │ ┌─────┐ │ │  │ │ ┌─────┐ │ │  │  │
│  │  │ │ │     │ │ │  │ │ │     │ │ │  │ │ │     │ │ │  │ │ │     │ │ │  │ │ │     │ │ │  │  │
│  │  │ │ │THUMB│ │ │  │ │ │THUMB│ │ │  │ │ │THUMB│ │ │  │ │ │THUMB│ │ │  │ │ │THUMB│ │ │  │  │
│  │  │ │ │     │ │ │  │ │ │     │ │ │  │ │ │     │ │ │  │ │ │     │ │ │  │ │ │     │ │ │  │  │
│  │  │ │ └─────┘ │ │  │ │ └─────┘ │ │  │ │ └─────┘ │ │  │ │ └─────┘ │ │  │ │ └─────┘ │ │  │  │
│  │  │ └─────────┘ │  │ └─────────┘ │  │ └─────────┘ │  │ └─────────┘ │  │ └─────────┘ │  │  │
│  │  │             │  │             │  │             │  │             │  │             │  │  │
│  │  │   45.2K     │  │   32.1K     │  │   28.7K     │  │   15.3K     │  │   12.8K     │  │  │
│  │  │   reach     │  │   reach     │  │   reach     │  │   reach     │  │   reach     │  │  │
│  │  │             │  │             │  │             │  │             │  │             │  │  │
│  │  │  ▲ +156%    │  │  ▲ +42%     │  │  ─ Avg      │  │  ▼ -23%     │  │  ▼ -31%     │  │  │
│  │  │  Dec 18     │  │  Dec 16     │  │  Dec 14     │  │  Dec 12     │  │  Dec 10     │  │  │
│  │  │  🔗 IG      │  │  🔗 IG      │  │  🔗 YT      │  │  🔗 IG      │  │  🔗 TT      │  │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘  │  │
│  │                                                                                        │  │
│  │  ◀ ═══════════════════════════════════════════════════════════════════════════════ ▶  │  │
│  │                                                                                        │  │
│  └───────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                             │
│  ┌────────────────────────────────────────┐  ┌────────────────────────────────────────────┐ │
│  │  P L A T F O R M   B R E A K D O W N   │  │  R E T E N T I O N   A N A L Y S I S       │ │
│  │  ═══════════════════════════════════   │  │  ═════════════════════════════════════     │ │
│  │                                         │  │                                            │ │
│  │  Instagram                              │  │  Audience retention (avg across posts)     │ │
│  │  ████████████████████████░░░░  67%     │  │                                            │ │
│  │  23.4K followers • 4.8% engage         │  │  100% ┤█                                   │ │
│  │                                         │  │       │█                                   │ │
│  │  YouTube                                │  │   75% ┤██                                  │ │
│  │  ██████████████░░░░░░░░░░░░░  24%     │  │       │███                                 │ │
│  │  12.1K subs • 6.2% engage              │  │   50% ┤█████                               │ │
│  │                                         │  │       │████████                            │ │
│  │  TikTok                                 │  │   25% ┤████████████                        │ │
│  │  █████░░░░░░░░░░░░░░░░░░░░░░░   9%     │  │       │████████████████____               │ │
│  │  8.2K followers • 8.1% engage          │  │    0% ┴──────────────────────────────     │ │
│  │                                         │  │       0%   25%   50%   75%   100%         │ │
│  │  ─────────────────────────────────     │  │                     Video duration         │ │
│  │  ⊕ Connect more platforms              │  │                                            │ │
│  │                                         │  │  Avg watch time: 68%  •  Drop-off: 32%   │ │
│  └────────────────────────────────────────┘  └────────────────────────────────────────────┘ │
│                                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────────────────────┐  │
│  │  ◆ P R E D I C T I O N                                                    91% conf    │  │
│  │  ═════════════════════                                                                │  │
│  │                                                                                        │  │
│  │  "Your optimal posting window tomorrow is 3:15pm - 4:40pm. Posts in this window      │  │
│  │   historically receive +34% higher reach. Your audience is most active on Wednesdays."│  │
│  │                                                                                        │  │
│  │  ┌───────────────────────────────────────────────────────────────────────────────┐   │  │
│  │  │  Tomorrow's posting schedule:                                                  │   │  │
│  │  │  ├── 3:15pm  Instagram Reel  (Primary window)                                 │   │  │
│  │  │  ├── 5:00pm  YouTube Short   (Secondary window)                               │   │  │
│  │  │  └── 7:30pm  TikTok          (Evening engagement peak)                        │   │  │
│  │  └───────────────────────────────────────────────────────────────────────────────┘   │  │
│  │                                                                                        │  │
│  │  Based on: follower activity, historical performance, trending topics                 │  │
│  │                                                           [ 🔔 Schedule ] [ 📊 Data ] │  │
│  └───────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                             │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Post Detail Overlay (When tapping a post)

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────────────────────┐  │
│  │  ✕ Close                                                        Dec 18, 2025  3:42pm │  │
│  │                                                                                        │  │
│  │  ┌──────────────────────┐  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │                      │  │  P E R F O R M A N C E   M E T R I C S               │  │  │
│  │  │                      │  │  ═══════════════════════════════════════              │  │  │
│  │  │    POST THUMBNAIL    │  │                                                       │  │  │
│  │  │       (Large)        │  │  Reach          45,247    ▲ +156% vs avg             │  │  │
│  │  │                      │  │  Impressions    67,892    ▲ +142% vs avg             │  │  │
│  │  │      ★ VIRAL         │  │  Engagement      4.8%     ▲ +0.5% vs avg             │  │  │
│  │  │                      │  │  Likes           2,147                                │  │  │
│  │  │                      │  │  Comments          234                                │  │  │
│  │  │  🔗 Instagram Reel   │  │  Saves             189                                │  │  │
│  │  │                      │  │  Shares             89                                │  │  │
│  │  └──────────────────────┘  └──────────────────────────────────────────────────────┘  │  │
│  │                                                                                        │  │
│  │  ┌────────────────────────────────────────────────────────────────────────────────┐  │  │
│  │  │  P E R F O R M A N C E   O V E R   T I M E                                     │  │  │
│  │  │  ══════════════════════════════════════════                                    │  │  │
│  │  │                                                                                 │  │  │
│  │  │       │          ╱╲                                                            │  │  │
│  │  │  40K ─┤        ╱    ╲                                                          │  │  │
│  │  │       │      ╱        ╲____                                                    │  │  │
│  │  │  20K ─┤   ╱                 ╲___________________________________________       │  │  │
│  │  │       │╱                                                                        │  │  │
│  │  │     0 ┴─────────────────────────────────────────────────────────────────       │  │  │
│  │  │       0h     1h     6h     12h    24h    48h    72h    7d                      │  │  │
│  │  │                                                                                 │  │  │
│  │  │  Peak: 1h after posting  •  Viral threshold: 6h mark  •  Steady state: 48h    │  │  │
│  │  └────────────────────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                                        │  │
│  │  ┌────────────────────────────────────────────────────────────────────────────────┐  │  │
│  │  │  C A U S A L   F A C T O R S   (Why this post performed well)                  │  │  │
│  │  │  ═════════════════════════════════════════════════════════════                 │  │  │
│  │  │                                                                                 │  │  │
│  │  │  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐               │  │  │
│  │  │  │ POST TIME  │  │ CONTENT    │  │ TRENDING   │  │ YOUR       │               │  │  │
│  │  │  │            │  │ LENGTH     │  │ AUDIO      │  │ ENERGY     │               │  │  │
│  │  │  │   ★★★★★    │  │   ★★★★☆    │  │   ★★★☆☆    │  │   ★★★★☆    │               │  │  │
│  │  │  │            │  │            │  │            │  │            │               │  │  │
│  │  │  │  3:42pm    │  │  32 sec    │  │  +12%      │  │  HRV: 52ms │               │  │  │
│  │  │  │  Optimal   │  │  Ideal     │  │  boost     │  │  Good mood │               │  │  │
│  │  │  └────────────┘  └────────────┘  └────────────┘  └────────────┘               │  │  │
│  │  │                                                                                 │  │  │
│  │  │  Key insight: "Posted during peak follower activity window with trending       │  │  │
│  │  │  audio. Your HRV was elevated, correlating with higher creative output."       │  │  │
│  │  └────────────────────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                                        │  │
│  └───────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                             │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Data Requirements (Extended)

```swift
struct CreativeDimensionData {
    // Hero Metrics
    var totalReach: Int
    var reachTrend: Double                      // % change vs period
    var reachSparkline: [Int]                   // Last 30 days
    var engagementRate: Double
    var engagementTrend: Double
    var engagementSparkline: [Double]
    var followerCount: Int
    var followerGrowth: Int                     // This period
    var followerSparkline: [Int]
    var growthRate: Double                      // % per week
    var growthStatus: GrowthStatus              // strong, moderate, weak, declining

    // Performance Graph
    var performanceTimeSeries: [PerformanceDataPoint]
    var selectedTimeRange: TimeRange            // 7d, 14d, 30d, 60d, 90d, 1y

    // Posting Calendar
    var postingCalendar: [Date: PostingDay]
    var postingStreak: Int
    var bestPostingTime: DateComponents
    var mostActiveDay: Weekday
    var averagePostsPerWeek: Double

    // Posts
    var recentPosts: [ContentPost]
    var viralPosts: [ContentPost]               // Top performers
    var underperformingPosts: [ContentPost]

    // Platform Breakdown
    var platformMetrics: [PlatformMetrics]

    // Retention Analysis
    var averageRetentionCurve: [Double]         // % at each quartile
    var averageWatchTime: Double                // Percentage
    var dropOffPoint: Double                    // Percentage

    // Predictions
    var predictedWindows: [ContentWindow]
    var suggestedSchedule: [ScheduledPost]
    var trendingTopics: [String]
}

struct ContentPost {
    var id: String
    var platform: Platform
    var type: ContentType                       // reel, video, image, story
    var thumbnailURL: URL?
    var postedAt: Date
    var caption: String?

    // Metrics
    var reach: Int
    var impressions: Int
    var likes: Int
    var comments: Int
    var shares: Int
    var saves: Int
    var engagementRate: Double

    // Performance
    var performanceVsAverage: Double            // % above/below avg
    var isViral: Bool                           // Top 10%
    var viralThresholdTime: TimeInterval?       // When it went viral

    // Time series
    var hourlyPerformance: [Int]                // Reach by hour since posting
    var peakTime: TimeInterval                  // Hours after posting

    // Causal Analysis
    var causalFactors: [CausalFactor]
    var keyInsight: String?

    // Correlations with your state
    var hrvAtPosting: Double?
    var moodAtPosting: String?
    var energyAtPosting: Double?
}

struct CausalFactor {
    var name: String
    var category: FactorCategory                // timing, content, trend, creator_state
    var rating: Int                             // 1-5 stars
    var value: String                           // Display value
    var contribution: Double                    // % contribution to performance
    var explanation: String
}

struct PlatformMetrics {
    var platform: Platform
    var followerCount: Int
    var engagementRate: Double
    var reachPercentage: Double                 // % of total reach
    var color: Color
    var isConnected: Bool
}

struct ContentWindow {
    var date: Date
    var startTime: DateComponents
    var endTime: DateComponents
    var platform: Platform
    var confidence: Double
    var predictedReachBoost: Double
    var predictedEngagementBoost: Double
    var reason: String
}
```

### Animation Sequences

```
ENTRY TRANSITION (800ms):
├── T=0ms: Background shifts to amber-tinted void
├── T=100ms: Hero metric cards slide down from top (staggered 50ms each)
├── T=250ms: Sparklines in hero cards animate left-to-right
├── T=350ms: Performance graph draws line left-to-right
├── T=450ms: Calendar heatmap cells fade in (staggered by week)
├── T=500ms: Post carousel slides in from right
├── T=600ms: Platform bars animate width
├── T=700ms: Retention graph draws
└── T=800ms: Prediction card fades up from bottom

POST TAP INTERACTION:
├── T=0ms: Card lifts, scales to 1.05
├── T=100ms: Other cards dim to 30%
├── T=200ms: Card expands to overlay (spring animation)
├── T=400ms: Overlay content fades in (staggered)
├── T=500ms: Performance graph in overlay draws
└── T=600ms: Causal factor cards slide up

VIRAL POST INDICATOR:
├── Gold border pulse (2s cycle)
├── ★ badge with subtle glow
├── Particle burst on first view
└── Confetti micro-animation (first time only)

DATA UPDATE ANIMATIONS:
├── New post: slides into carousel from left with glow
├── Reach milestone: number counter animation + particles
├── Viral detection: card border transitions to gold, celebration
├── Follower milestone: celebratory pulse
└── Engagement spike: metric card pulses green
```

---

## 3.3 PHYSIOLOGICAL DIMENSION

### Concept: "The Body Interface"

A holographic body visualization with real-time biometric overlays — medical-grade data presentation meets sci-fi body scanner. Think Jarvis scanning Tony Stark's vital signs with layered data projections.

### Layout Diagram

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════╗
║  ◀ Sanctuary            PHYSIOLOGICAL  •  THE BODY INTERFACE                                     ║
║  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  ║
║                                        Level 19 • Rank: PRIMAL                                   ║
╠══════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                  ║
║  ┌──────────────────────────────────────────────┐   ┌────────────────────────────────────────┐  ║
║  │            HOLOGRAPHIC BODY SCANNER           │   │         VITAL SIGNS PANEL              │  ║
║  │            ═════════════════════              │   │         ═════════════════              │  ║
║  │                                               │   │                                        │  ║
║  │     ┌─────────STRESS ZONE─────────┐           │   │   ┌───────────────────────────────┐   │  ║
║  │     │   ╭───────────────────╮     │           │   │   │  HRV           48ms           │   │  ║
║  │     │   │ ░░░ STRESS: 34% ░░│     │           │   │   │  ████████████████░░░░░░░░ ● ● │   │  ║
║  │     │   │   ◉ CORTISOL:LOW  │     │           │   │   │  vs avg: +12%  ↗ GOOD         │   │  ║
║  │     │   ╰───────────────────╯     │           │   │   └───────────────────────────────┘   │  ║
║  │     └─────────────────────────────┘           │   │                                        │  ║
║  │                    │                          │   │   ┌───────────────────────────────┐   │  ║
║  │              ╭─────┴─────╮                    │   │   │  RHR          54 bpm          │   │  ║
║  │             ╱             ╲                   │   │   │  █████████████████████░░░ ● ● │   │  ║
║  │  ┌─────────╱ BREATHING ────╲─────────┐       │   │   │  Zone: Athletic  ↗ EXCELLENT  │   │  ║
║  │  │  ╭────╮  ╱╲  ╱╲  ╱╲  ╱╲   ╭────╮  │       │   │   └───────────────────────────────┘   │  ║
║  │  │  │ARM │ ╱  ╲╱  ╲╱  ╲╱  ╲  │ARM │  │       │   │                                        │  ║
║  │  │  │87% │ │  HRV WAVE  │     │91% │  │       │   │   ┌───────────────────────────────┐   │  ║
║  │  │  ╰────╯ ╲  48ms LIVE  ╱   ╰────╯  │       │   │   │  RECOVERY       78%           │   │  ║
║  │  └──────────╲─────────────╱──────────┘       │   │   │  ██████████████████░░░░░ ● ●  │   │  ║
║  │               ╲         ╱                     │   │   │  Workout OK   → STRONG        │   │  ║
║  │                │  CORE  │                     │   │   └───────────────────────────────┘   │  ║
║  │        ┌───────│  94%   │───────┐             │   │                                        │  ║
║  │        │       ╰────────╯       │             │   │   ┌───────────────────────────────┐   │  ║
║  │   ╭────┴────╮           ╭────┴────╮           │   │   │  READINESS      82%           │   │  ║
║  │   │  QUAD   │           │  QUAD   │           │   │   │  █████████████████████░░░ ● ● │   │  ║
║  │   │ ████ 72%│           │████ 68% │           │   │   │  Peak window: 10am-2pm → HIGH│   │  ║
║  │   ╰─────────╯           ╰─────────╯           │   │   └───────────────────────────────┘   │  ║
║  │        │                     │                │   │                                        │  ║
║  │   ╭────┴────╮           ╭────┴────╮           │   │   ┌────────────────────────────────┐  │  ║
║  │   │  CALF   │           │  CALF   │           │   │   │  ● Live   ⟳ 2s ago            │  │  ║
║  │   │ ░░░░ 45%│           │░░░░ 52% │           │   │   └────────────────────────────────┘  │  ║
║  │   ╰─────────╯           ╰─────────╯           │   │                                        │  ║
║  │                                               │   └────────────────────────────────────────┘  ║
║  │   ═══════════════════════════════════════     │                                               ║
║  │   MUSCLE RECOVERY HEATMAP LEGEND:             │   ┌────────────────────────────────────────┐  ║
║  │   ████ 80%+ Ready   ░░░░ 40-60% Moderate      │   │          HRV TREND (7 DAYS)            │  ║
║  │   ▓▓▓▓ 60-80% Good  ░░░░ <40% Fatigued        │   │          ═══════════════════           │  ║
║  │                                               │   │   52│       ╱╲                         │  ║
║  │   [◀ ROTATE]  [⟳ 360°]  [⊕ ZOOM]  [▼ RESET]   │   │   48│    ╱╲╱  ╲    ╱╲                 │  ║
║  └──────────────────────────────────────────────┘   │   44│ ╲╱        ╲╱  ╲╱ ●TODAY          │  ║
║                                                      │   40│                                   │  ║
║                                                      │     └───────────────────────────        │  ║
║                                                      │      M   T   W   T   F   S   S          │  ║
║                                                      │   avg: 47ms • peak: 52ms (Thu)          │  ║
║                                                      └────────────────────────────────────────┘  ║
║                                                                                                  ║
║  ┌───────────────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                              SLEEP ANALYSIS (LAST NIGHT)                                   │  ║
║  │                              ═══════════════════════════                                   │  ║
║  │                                                                                            │  ║
║  │   TIME IN BED                    SLEEP STAGES                           EFFICIENCY        │  ║
║  │   ┌─────────────┐   ╔════╤════════════════╤═════╤══════════════╤═══╗   ┌───────────┐     │  ║
║  │   │  11:24pm    │   ║DEEP│▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│CORE │░░░░░░░░░░░░░░│REM║   │    91%    │     │  ║
║  │   │     ▼       │   ╠════╪════════════════╪═════╪══════════════╪═══╣   │  ████████ │     │  ║
║  │   │  6:48am     │   ║1h48│   3h 12m       │LIGHT│   1h 42m     │42m║   │ Excellent │     │  ║
║  │   │  ═══════    │   ╚════╧════════════════╧═════╧══════════════╧═══╝   └───────────┘     │  ║
║  │   │  7h 24m     │                                                                         │  ║
║  │   │  TOTAL      │   SLEEP SCORE: 87/100 ●●●●○                                            │  ║
║  │   └─────────────┘   Deep: 24% ↗ │ REM: 9% ↘ │ Disturbances: 2                            │  ║
║  │                                                                                            │  ║
║  └───────────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                                  ║
║  ┌──────────────────────────────────────┐  ┌──────────────────────────────────────────────────┐ ║
║  │       WORKOUT LOG (THIS WEEK)         │  │              DAILY ACTIVITY RINGS               │ ║
║  │       ═════════════════════           │  │              ════════════════════               │ ║
║  │                                       │  │                                                  │ ║
║  │   THU  Strength   65min   ●●●●○       │  │    ╭───────────────────────────────────╮        │ ║
║  │   ──────────────────────────────      │  │    │      MOVE           EXERCISE      │        │ ║
║  │   TUE  HIIT       42min   ●●●●●       │  │    │   ╭─────────╮    ╭─────────╮      │        │ ║
║  │   ──────────────────────────────      │  │    │   │ ◉ 78%   │    │ ◉ 92%   │      │        │ ║
║  │   SUN  Zone 2 Run 55min   ●●●●○       │  │    │   │  482cal │    │  47min  │      │        │ ║
║  │   ──────────────────────────────      │  │    │   ╰─────────╯    ╰─────────╯      │        │ ║
║  │                                       │  │    │                                    │        │ ║
║  │   Volume Load: 12,450 lbs            │  │    │      STAND          STEPS          │        │ ║
║  │   Recovery Debt: LOW                  │  │    │   ╭─────────╮    ╭─────────╮      │        │ ║
║  │                                       │  │    │   │ ◉ 100%  │    │  8,247  │      │        │ ║
║  │   [View All Workouts →]               │  │    │   │  12/12  │    │  Goal✓  │      │        │ ║
║  │                                       │  │    │   ╰─────────╯    ╰─────────╯      │        │ ║
║  └──────────────────────────────────────┘  │    ╰───────────────────────────────────╯        │ ║
║                                             │                                                  │ ║
║                                             └──────────────────────────────────────────────────┘ ║
║                                                                                                  ║
║  ╔═══════════════════════════════════════════════════════════════════════════════════════════╗  ║
║  ║                              CORRELATION MAP                                               ║  ║
║  ║  ─────────────────────────────────────────────────────────────────────────────────────    ║  ║
║  ║                                                                                            ║  ║
║  ║   ┌─────────────┐        ┌─────────────┐        ┌─────────────┐        ┌─────────────┐    ║  ║
║  ║   │   HRV →     │   ══►  │   FOCUS     │        │   SLEEP →   │   ══►  │   RECOVERY  │    ║  ║
║  ║   │   FOCUS     │        │   +18%      │        │   RECOVERY  │        │   +23%      │    ║  ║
║  ║   │   r = 0.72  │        │   tomorrow  │        │   r = 0.84  │        │   next day  │    ║  ║
║  ║   └─────────────┘        └─────────────┘        └─────────────┘        └─────────────┘    ║  ║
║  ║        ●━━━━━━━━━━━━━━━━━━●                          ●━━━━━━━━━━━━━━━━━━●                 ║  ║
║  ║                                                                                            ║  ║
║  ║   ┌─────────────┐        ┌─────────────┐        ┌─────────────┐        ┌─────────────┐    ║  ║
║  ║   │  WORKOUT →  │   ══►  │  NEXT DAY   │        │   STRESS →  │   ══►  │  SLEEP      │    ║  ║
║  ║   │  NEXT DAY   │        │  HRV -8%    │        │  QUALITY    │        │  QUALITY    │    ║  ║
║  ║   │  r = -0.45  │        │  recovery   │        │  r = -0.67  │        │  -15%       │    ║  ║
║  ║   └─────────────┘        └─────────────┘        └─────────────┘        └─────────────┘    ║  ║
║  ║        ●━━━━━━━━━━━━━━━━━━●                          ●━━━━━━━━━━━━━━━━━━●                 ║  ║
║  ║                                                                                            ║  ║
║  ╠═══════════════════════════════════════════════════════════════════════════════════════════╣  ║
║  ║  ◆ PREDICTION                                                            CONFIDENCE: 87%  ║  ║
║  ║  ────────────────────────────────────────────────────────────────────────────────────────  ║  ║
║  ║  IF: You complete tomorrow's planned Zone 2 run (55min)                                    ║  ║
║  ║  THEN: Saturday HRV projected to reach 54ms (+12%), optimal for cognitive work            ║  ║
║  ║                                                                                            ║  ║
║  ║  Based on: 23 similar training cycles, your personal recovery pattern (1.2 days avg)      ║  ║
║  ║                                                                                            ║  ║
║  ║  ┌───────────────────────────────────────────────────────────────────────────────────┐    ║  ║
║  ║  │   [📅 Schedule Zone 2]       [📊 See Analysis]       [🔔 Remind Before Bed]       │    ║  ║
║  ║  └───────────────────────────────────────────────────────────────────────────────────┘    ║  ║
║  ╚═══════════════════════════════════════════════════════════════════════════════════════════╝  ║
║                                                                                                  ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### Camera Rotation Interaction

When user taps **[⟳ 360°]** or drags on body silhouette:

```
ROTATION MODE ACTIVE
─────────────────────────────────────────────────────
              FRONT              SIDE              BACK
           ╭───────╮          ╭───────╮          ╭───────╮
           │       │          │   │   │          │       │
           │ ◉ ◉   │          │   │░░░│          │░░░░░░░│
           │  ───  │          │   │░░░│          │░░░░░░░│
           │ │   │ │          │   │░░░│          │░░░░░░░│
           │ │ ● │ │          │   │░░░│          │░░░░░░░│
           │ │   │ │          │   │░░░│          │░░░░░░░│
           │ ╱   ╲ │          │   ╱   │          │   ╲   │
           ╰───────╯          ╰───────╯          ╰───────╯
              ◉                                      ○

Gesture: Drag horizontally to rotate • Pinch to zoom
Highlights: Tap any muscle group for isolation view
─────────────────────────────────────────────────────
```

### Extended Data Requirements

```swift
struct PhysiologicalDimensionData {
    // Core Vitals
    var currentHRV: Double                      // Real-time from Apple Watch
    var hrvVariabilityMs: Double                // Standard deviation
    var hrvTrend: [HRVDataPoint]                // 7-day history with timestamps
    var restingHeartRate: Int                   // Morning baseline
    var rhrZone: HeartRateZone                  // Athletic, Average, Elevated

    // Recovery Metrics
    var recoveryScore: Double                   // 0-100 composite
    var recoveryFactors: RecoveryBreakdown      // Sleep, HRV, strain contributions
    var readinessScore: Double                  // 0-100 for today
    var peakPerformanceWindow: DateInterval     // Predicted optimal hours
    var workoutRecommendation: WorkoutType?     // Based on recovery

    // Sleep Analysis
    var lastNightSleep: SleepSession            // Full breakdown
    var sleepStages: [SleepStage]               // Deep, Core, REM, Awake
    var sleepEfficiency: Double                 // Time asleep / time in bed
    var sleepScore: Int                         // 0-100 composite
    var sleepDebt: TimeInterval                 // Accumulated deficit
    var disturbanceCount: Int                   // Wake events

    // Body Scanner
    var muscleRecoveryMap: [MuscleGroup: MuscleStatus]  // Per-muscle recovery %
    var bodyZoneStatus: [BodyZone: ZoneStatus]          // Head, Chest, Arms, Core, Legs
    var stressLevel: Double                             // 0-100 from HRV analysis
    var cortisolEstimate: CortisolLevel                 // Low, Normal, Elevated
    var breathingRatePerMin: Double                     // Respiratory rate

    // Activity
    var hourlyActivity: [HourlyActivity]        // Steps, movement per hour
    var dailyRings: ActivityRings               // Move, Exercise, Stand
    var stepCount: Int                          // Today's total
    var activeCalories: Int                     // Today's burn
    var workouts: [WorkoutSession]              // Week's workout log
    var weeklyVolumeLoad: Double                // Total training volume
    var recoveryDebt: RecoveryDebtLevel         // Low, Moderate, High

    // Correlations
    var correlations: [PhysiologicalCorrelation]  // Discovered patterns
    var predictions: [HealthPrediction]           // AI-generated forecasts
}

struct MuscleStatus {
    var muscleGroup: MuscleGroup        // Quads, Calves, Arms, Core, etc.
    var recoveryPercent: Double         // 0-100
    var lastWorked: Date?               // When last trained
    var strain: StrainLevel             // Low, Moderate, High
    var color: Color                    // Heatmap color
}

struct SleepSession {
    var bedTime: Date
    var wakeTime: Date
    var totalDuration: TimeInterval
    var deepSleep: TimeInterval
    var coreSleep: TimeInterval
    var remSleep: TimeInterval
    var awakeTime: TimeInterval
    var efficiency: Double
    var score: Int
    var stages: [SleepStageEvent]       // Timeline of stage transitions
}

struct RecoveryBreakdown {
    var sleepContribution: Double       // % from sleep quality
    var hrvContribution: Double         // % from HRV
    var strainContribution: Double      // % from previous day strain
    var consistencyBonus: Double        // Bonus for streak
}

struct ActivityRings {
    var moveCalories: Int
    var moveGoal: Int
    var exerciseMinutes: Int
    var exerciseGoal: Int
    var standHours: Int
    var standGoal: Int
}
```

### Animation Sequences

**Body Scanner Entry (800ms)**:
1. 0-200ms: Body silhouette fades in from center outward
2. 200-400ms: Muscle heatmap colors pulse on from core
3. 400-600ms: Breathing wave animation begins around chest
4. 600-800ms: HRV wave overlays chest with live pulse sync
5. Continuous: Subtle glow pulses synced to heart rate data

**Muscle Group Tap (400ms)**:
1. 0-100ms: Selected muscle group highlights with glow
2. 100-250ms: Other areas dim to 40% opacity
3. 250-400ms: Detail panel slides in from edge with muscle stats
4. Continuous: Selected muscle pulses subtly

**Sleep Stage Bar Interaction (300ms)**:
1. Tap any stage: Segment expands, shows detailed breakdown
2. Swipe through: Animated transition between nights
3. Long press: Full sleep timeline with heart rate overlay

---

## 3.4 BEHAVIORAL DIMENSION

### Concept: "The Operator's Dashboard"

A disciplined, military-grade command interface showing behavioral consistency metrics — like a spec-ops mission control. Think tactical HUD with precision timing and streak mechanics.

### Layout Diagram

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════╗
║  ◀ Sanctuary            BEHAVIORAL  •  OPERATOR STATUS                                           ║
║  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  ║
║                                        Level 17 • Rank: TACTICIAN                                ║
╠══════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                  ║
║  ╔═══════════════════════════════════════════════════════════════════════════════════════════╗  ║
║  ║                                   DISCIPLINE INDEX                                         ║  ║
║  ║  ═════════════════════════════════════════════════════════════════════════════════════    ║  ║
║  ║                                                                                            ║  ║
║  ║         ┌───────────────────────────────────────────────────────────────────────┐         ║  ║
║  ║         │  ████████████████████████████████████████████████████░░░░░░░░░░░░░░░░ │         ║  ║
║  ║         │                                                                        │         ║  ║
║  ║         │                           78.4%                                        │         ║  ║
║  ║         │                    ╱╲  +2.3% vs last week                              │         ║  ║
║  ║         └───────────────────────────────────────────────────────────────────────┘         ║  ║
║  ║                                                                                            ║  ║
║  ║   ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌─────┐ ║  ║
║  ║   │  MORNING   │  │ DEEP WORK  │  │   SLEEP    │  │  MOVEMENT  │  │   SCREEN   │  │TASKS│ ║  ║
║  ║   │  ════════  │  │  ════════  │  │  ════════  │  │  ════════  │  │  ════════  │  │═════│ ║  ║
║  ║   │            │  │            │  │            │  │            │  │            │  │     │ ║  ║
║  ║   │   ◉ 92%    │  │   ◉ 84%    │  │   ◎ 73%    │  │   ◉ 81%    │  │   ○ 62%    │  │◉ 88%│ ║  ║
║  ║   │  ████████  │  │  ███████   │  │  ██████    │  │  ███████   │  │  █████     │  │█████│ ║  ║
║  ║   │  ░░░░░░░░  │  │  ░░░░░░░   │  │  ░░░░░░    │  │  ░░░░░░░   │  │  ░░░░░     │  │░░░░░│ ║  ║
║  ║   │            │  │            │  │            │  │            │  │            │  │     │ ║  ║
║  ║   │   ↗ +5%    │  │   → +0%    │  │   ↘ -4%    │  │   ↗ +3%    │  │   ↘ -8%    │  │↗ +2%│ ║  ║
║  ║   └────────────┘  └────────────┘  └────────────┘  └────────────┘  └────────────┘  └─────┘ ║  ║
║  ║        ●●             ●●             ●○             ●●             ○○             ●●      ║  ║
║  ╚═══════════════════════════════════════════════════════════════════════════════════════════╝  ║
║                                                                                                  ║
║  ┌───────────────────────────────────────────┐  ┌────────────────────────────────────────────┐  ║
║  │         ROUTINE CONSISTENCY                │  │           STREAK TRACKER                   │  ║
║  │         ═══════════════════                │  │           ══════════════                   │  ║
║  │                                            │  │                                            │  ║
║  │   MORNING ROUTINE                          │  │   ┌─────────────────────────────────────┐ │  ║
║  │   Target: 6:30am ± 15min                   │  │   │  🔥 DEEP WORK             12 days   │ │  ║
║  │   ┌────────────────────────────────────┐   │  │   │     ████████████████████████████    │ │  ║
║  │   │  M    T    W    T    F    S    S   │   │  │   │     Best: 18 days • To beat: 6     │ │  ║
║  │   │  ●    ●    ○    ●    ●    ●    ◐   │   │  │   └─────────────────────────────────────┘ │  ║
║  │   │ 6:22 6:31 7:45 6:28 6:15 6:41  --  │   │  │                                            │  ║
║  │   └────────────────────────────────────┘   │  │   ┌─────────────────────────────────────┐ │  ║
║  │   Consistency: 71% • Avg: 6:34am          │  │   │  🏆 TASK ZERO              21 days   │ │  ║
║  │                                            │  │   │     ████████████████████████████    │ │  ║
║  │   ───────────────────────────────────────  │  │   │     PERSONAL BEST! 🎉               │ │  ║
║  │                                            │  │   └─────────────────────────────────────┘ │  ║
║  │   SLEEP SCHEDULE                           │  │                                            │  ║
║  │   Target: Before 11:00pm                   │  │   ┌─────────────────────────────────────┐ │  ║
║  │   ┌────────────────────────────────────┐   │  │   │     SLEEP BEFORE 11PM       8 days  │ │  ║
║  │   │  M    T    W    T    F    S    S   │   │  │   │     ██████████████████░░░░░░░░░░   │ │  ║
║  │   │  ●    ○    ●    ●    ●    ○    ◐   │   │  │   │     Best: 14 days • Risk: 2 late  │ │  ║
║  │   │10:42 11:23 10:51 10:38 10:55 11:47  -- │   │  │   └─────────────────────────────────────┘ │  ║
║  │   └────────────────────────────────────┘   │  │                                            │  ║
║  │   Consistency: 67% • Avg: 10:56pm         │  │   ┌─────────────────────────────────────┐ │  ║
║  │                                            │  │   │     MORNING ROUTINE          5 days │ │  ║
║  │   ───────────────────────────────────────  │  │   │     ██████████░░░░░░░░░░░░░░░░░░░  │ │  ║
║  │                                            │  │   │     Best: 23 days • Building...    │ │  ║
║  │   WAKE SCHEDULE                            │  │   └─────────────────────────────────────┘ │  ║
║  │   Target: 6:30am ± 30min                   │  │                                            │  ║
║  │   ┌────────────────────────────────────┐   │  │   ENDANGERED STREAKS:                     │  ║
║  │   │  [● ● ○ ● ● ● ◐] 71% on target    │   │  │   ⚠ Screen Limit at risk (2 violations)  │  ║
║  │   └────────────────────────────────────┘   │  │   ⚠ Exercise needs 1 more session today  │  ║
║  │                                            │  │                                            │  ║
║  └───────────────────────────────────────────┘  └────────────────────────────────────────────┘  ║
║                                                                                                  ║
║  ╔═══════════════════════════════════════════════════════════════════════════════════════════╗  ║
║  ║                                  DAILY OPERATIONS                                          ║  ║
║  ║  ─────────────────────────────────────────────────────────────────────────────────────    ║  ║
║  ║                                                                                            ║  ║
║  ║   ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  ║  ║
║  ║   │   DOPAMINE       │  │   WALKS          │  │   SCREEN AFTER   │  │   TASK           │  ║  ║
║  ║   │   DELAY          │  │   TODAY          │  │   10PM           │  │   COMPLETION     │  ║  ║
║  ║   │   ══════════     │  │   ══════════     │  │   ══════════     │  │   ══════════     │  ║  ║
║  ║   │                  │  │                  │  │                  │  │                  │  ║  ║
║  ║   │    ╭──────╮      │  │    ╭──────╮      │  │    ╭──────╮      │  │    ╭──────╮      │  ║  ║
║  ║   │    │ 47   │      │  │    │ 2/3  │      │  │    │ 32   │      │  │    │ 6/8  │      │  ║  ║
║  ║   │    │ min  │      │  │    │ walks│      │  │    │ min  │      │  │    │tasks │      │  ║  ║
║  ║   │    ╰──────╯      │  │    ╰──────╯      │  │    ╰──────╯      │  │    ╰──────╯      │  ║  ║
║  ║   │                  │  │                  │  │                  │  │                  │  ║  ║
║  ║   │   Target: 30min  │  │   Goal: 3/day    │  │   Limit: 20min   │  │   Goal: 100%     │  ║  ║
║  ║   │       ●●●        │  │       ●●○        │  │       ⚠○○        │  │       ●●○        │  ║  ║
║  ║   │   ↗ Exceeding    │  │   → 1 remaining  │  │   ↘ OVER LIMIT   │  │   → 2 remaining  │  ║  ║
║  ║   └──────────────────┘  └──────────────────┘  └──────────────────┘  └──────────────────┘  ║  ║
║  ║                                                                                            ║  ║
║  ║   TODAY'S TIMELINE                                                                        ║  ║
║  ║   ═══════════════════════════════════════════════════════════════════════════════════    ║  ║
║  ║   6am     8am     10am    12pm    2pm     4pm     6pm     8pm     10pm    12am           ║  ║
║  ║   │       │       │       │       │       │       │       │       │       │              ║  ║
║  ║   ├──●────┼───────┼──●────┼───────┼──●────┼───────┼──●────┼───────┼──⚠────┤              ║  ║
║  ║   │ Wake  │       │ DW    │       │ Walk  │       │ Walk  │       │ Screen│              ║  ║
║  ║   │ 6:22  │       │ Start │       │ #1    │       │ #2    │       │ Over  │              ║  ║
║  ║   └───────┴───────┴───────┴───────┴───────┴───────┴───────┴───────┴───────┘              ║  ║
║  ║                                                                                            ║  ║
║  ╠═══════════════════════════════════════════════════════════════════════════════════════════╣  ║
║  ║  ◆ PREDICTION                                                            CONFIDENCE: 82%  ║  ║
║  ║  ────────────────────────────────────────────────────────────────────────────────────────  ║  ║
║  ║  IF: You sleep before 11pm for 3 more consecutive nights                                  ║  ║
║  ║  THEN: Sleep streak reaches 11 days, unlocking "Night Owl Reformed" badge (+150 XP)       ║  ║
║  ║                                                                                            ║  ║
║  ║  Based on: Current streak momentum, your historical pattern shows 89% success at this pt  ║  ║
║  ║                                                                                            ║  ║
║  ║  LEVEL UP PATH:                                                                           ║  ║
║  ║  ┌───────────────────────────────────────────────────────────────────────────────────┐    ║  ║
║  ║  │  Current: 17  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━○━━━━━━━━  Next: 18 (340 XP needed)  │    ║  ║
║  ║  │                                                                                    │    ║  ║
║  ║  │  FASTEST PATH: Complete Task Zero streak (7 more days = 350 XP)                   │    ║  ║
║  ║  └───────────────────────────────────────────────────────────────────────────────────┘    ║  ║
║  ║                                                                                            ║  ║
║  ║  ┌───────────────────────────────────────────────────────────────────────────────────┐    ║  ║
║  ║  │   [⏰ Set 10:30pm Reminder]      [📊 Streak Analytics]      [🎯 Adjust Goals]      │    ║  ║
║  ║  └───────────────────────────────────────────────────────────────────────────────────┘    ║  ║
║  ╚═══════════════════════════════════════════════════════════════════════════════════════════╝  ║
║                                                                                                  ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### Extended Data Requirements

```swift
struct BehavioralDimensionData {
    // Discipline Index
    var disciplineIndex: Double                      // Overall score 0-100
    var disciplineChange: Double                     // vs last week
    var disciplineComponents: [DisciplineComponent]  // Breakdown by category

    // Component Scores
    var morningScore: ComponentScore                 // Wake time consistency
    var deepWorkScore: ComponentScore                // Focus session completion
    var sleepScore: ComponentScore                   // Bedtime adherence
    var movementScore: ComponentScore                // Daily movement goals
    var screenScore: ComponentScore                  // Screen time limits
    var taskScore: ComponentScore                    // Task completion rate

    // Routine Tracking
    var morningRoutine: RoutineTracker               // Wake times this week
    var sleepSchedule: ScheduleTracker               // Sleep times this week
    var wakeSchedule: ScheduleTracker                // Wake times this week
    var routineConsistency: Double                   // % on target

    // Streaks
    var activeStreaks: [Streak]                      // All current streaks
    var endangeredStreaks: [Streak]                  // At risk of breaking
    var personalBests: [StreakRecord]                // Historical bests
    var upcomingMilestones: [StreakMilestone]        // Next achievements

    // Daily Operations
    var dopamineDelay: TimeInterval                  // Minutes before first dopamine hit
    var dopamineTarget: TimeInterval                 // Goal (e.g., 30 min)
    var walksCompleted: Int                          // Today's walks
    var walksGoal: Int                               // Daily target
    var screenTimeAfter10pm: TimeInterval            // Night screen usage
    var screenLimit: TimeInterval                    // Allowed limit
    var tasksCompleted: Int                          // Tasks done today
    var tasksTotal: Int                              // Total planned tasks

    // Timeline
    var todayEvents: [BehavioralEvent]               // Day's behavioral events
    var violations: [BehaviorViolation]              // Limit breaches

    // Progression
    var currentLevel: Int
    var xpToNextLevel: Int
    var fastestLevelPath: LevelUpPath                // Recommended actions
    var predictions: [BehavioralPrediction]          // AI forecasts
}

struct ComponentScore {
    var name: String
    var currentScore: Double                         // 0-100
    var trend: ScoreTrend                            // Up, Down, Stable
    var changePercent: Double                        // vs previous period
    var status: ComponentStatus                      // Excellent, Good, Needs Work, At Risk
}

struct Streak {
    var id: UUID
    var name: String
    var category: StreakCategory                     // Sleep, Focus, Exercise, etc.
    var currentDays: Int
    var personalBest: Int
    var daysToNextMilestone: Int
    var isEndangered: Bool
    var lastCompletedDate: Date
    var xpPerDay: Int                                // XP earned per day
    var milestoneXP: Int                             // Bonus XP at milestone
}

struct RoutineTracker {
    var targetTime: Date                             // Target wake/sleep time
    var tolerance: TimeInterval                      // Allowed variance (± minutes)
    var weekData: [DayRoutineData]                   // Each day's actual time
    var consistency: Double                          // % within tolerance
    var averageTime: Date                            // Actual average
    var trend: RoutineTrend                          // Improving, Stable, Declining
}

struct BehavioralEvent {
    var timestamp: Date
    var eventType: BehavioralEventType               // Wake, Sleep, Walk, Task, Screen, etc.
    var status: EventStatus                          // Success, Partial, Violation
    var details: String?
}

struct LevelUpPath {
    var currentLevel: Int
    var nextLevel: Int
    var xpNeeded: Int
    var xpProgress: Int
    var fastestActions: [LevelUpAction]              // Recommended path
    var estimatedDays: Int                           // To level up
}
```

### Animation Sequences

**Discipline Index Entry (600ms)**:
1. 0-150ms: Main progress bar fills from left with pulse effect
2. 150-400ms: Component cards animate in with stagger (50ms each)
3. 400-600ms: Trend arrows animate up/down with color flash
4. Continuous: Active components have subtle breathing glow

**Streak Counter Animation (400ms)**:
1. On streak increment: Number counts up with particle burst
2. Milestone reached: Golden flash, badge animation, XP particle rain
3. Streak at risk: Red pulse warning around streak card
4. Streak broken: Shatter effect, number resets to 0

**Timeline Scrubbing (Continuous)**:
1. Drag along timeline: Events highlight as cursor passes
2. Tap event: Expands with detail card, related metrics highlight
3. Violation marker: Pulses with warning glow, tap for explanation

---

## 3.5 KNOWLEDGE DIMENSION

### Concept: "The Semantic Constellation"

A floating 3D knowledge graph showing the structure of your mind's captured information — like a neuron network visualization. Think Minority Report data visualization meets academic knowledge management.

### Layout Diagram

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════╗
║  ◀ Sanctuary            KNOWLEDGE  •  SEMANTIC CONSTELLATION                                     ║
║  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  ║
║                                        Level 22 • Rank: SCHOLAR                                  ║
╠══════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                  ║
║  ╔═══════════════════════════════════════════════════════════════════════════════════════════╗  ║
║  ║                                   TODAY'S KNOWLEDGE FLOW                                   ║  ║
║  ║  ═════════════════════════════════════════════════════════════════════════════════════    ║  ║
║  ║                                                                                            ║  ║
║  ║   ┌────────────────┐       ┌────────────────┐       ┌────────────────┐       ┌─────────┐  ║  ║
║  ║   │   CAPTURED     │  ══►  │   PROCESSED    │  ══►  │   CONNECTED    │   ●   │ DENSITY │  ║  ║
║  ║   │   ══════════   │       │   ══════════   │       │   ══════════   │       │ ═══════ │  ║  ║
║  ║   │                │       │                │       │                │       │         │  ║  ║
║  ║   │      47        │       │      23        │       │      12        │       │  0.78   │  ║  ║
║  ║   │    ideas       │       │   embeddings   │       │     links      │       │  HIGH   │  ║  ║
║  ║   │                │       │                │       │                │       │         │  ║  ║
║  ║   │   ↗ +12 today  │       │   ↗ +8 today   │       │   ↗ +5 today   │       │ ████░░  │  ║  ║
║  ║   └────────────────┘       └────────────────┘       └────────────────┘       └─────────┘  ║  ║
║  ║                                                                                            ║  ║
║  ╚═══════════════════════════════════════════════════════════════════════════════════════════╝  ║
║                                                                                                  ║
║  ┌───────────────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                           3D KNOWLEDGE CONSTELLATION                                       │  ║
║  │                           ══════════════════════════                                       │  ║
║  │                                                                                            │  ║
║  │                              [MACHINE LEARNING]                                            │  ║
║  │                                   ╭─────╮                                                  │  ║
║  │            ╭──────────────────────│ ●ML │──────────────────────╮                          │  ║
║  │            │                      ╰──┬──╯                      │                          │  ║
║  │            │                         │                         │                          │  ║
║  │       ╭────┴────╮               ╭────┴────╮               ╭────┴────╮                     │  ║
║  │       │●Neural  │───────────────│●Deep    │───────────────│●Trans-  │                     │  ║
║  │       │ Nets    │               │ Learn   │               │ formers │                     │  ║
║  │       ╰────┬────╯               ╰────┬────╯               ╰────┬────╯                     │  ║
║  │            │                         │                         │                          │  ║
║  │   ╭────────┼────────╮       ╭────────┼────────╮       ╭────────┼────────╮                 │  ║
║  │   │        │        │       │        │        │       │        │        │                 │  ║
║  │ ╭─┴─╮   ╭──┴──╮  ╭──┴─╮  ╭──┴─╮   ╭──┴──╮  ╭──┴─╮  ╭──┴─╮   ╭──┴──╮  ╭──┴─╮              │  ║
║  │ │CNN│   │ RNN │  │LSTM│  │ VAE│   │ GAN │  │Diff│  │BERT│   │ GPT │  │LLaMA│              │  ║
║  │ │ ○ │   │  ○  │  │ ○  │  │ ○  │   │  ○  │  │ ○  │  │ ○  │   │  ●  │  │ ○  │              │  ║
║  │ ╰───╯   ╰─────╯  ╰────╯  ╰────╯   ╰─────╯  ╰────╯  ╰────╯   ╰─────╯  ╰────╯              │  ║
║  │                                                                                            │  ║
║  │   ════════════════════════════════════════════════════════════════════════════════════    │  ║
║  │   [SWIFT/iOS]                        [PRODUCTIVITY]                        [RESEARCH]      │  ║
║  │        ●──────────────────────────────────●──────────────────────────────────●            │  ║
║  │       ╱│╲                                ╱│╲                                ╱│╲           │  ║
║  │      ╱ │ ╲                              ╱ │ ╲                              ╱ │ ╲          │  ║
║  │     ○  ○  ○                            ○  ○  ○                            ○  ○  ○         │  ║
║  │  SwiftUI Metal Combine            GTD Atomic Deep               Papers Methods Data       │  ║
║  │                                       Habits Work                                          │  ║
║  │                                                                                            │  ║
║  │   NODE LEGEND:                                                                             │  ║
║  │   ● = Active cluster (recently accessed)   ○ = Dormant node (7+ days)                     │  ║
║  │   Line thickness = Connection strength     Glow intensity = Access frequency              │  ║
║  │                                                                                            │  ║
║  │   ┌────────────────────────────────────────────────────────────────────────────────────┐  │  ║
║  │   │  [◀ ROTATE]   [⟳ AUTO-ORBIT]   [⊕ ZOOM]   [🔍 SEARCH]   [📍 FOCUS NODE]   [▼ RESET] │  │  ║
║  │   └────────────────────────────────────────────────────────────────────────────────────┘  │  ║
║  │                                                                                            │  ║
║  └───────────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                                  ║
║  ┌──────────────────────────────────────┐  ┌──────────────────────────────────────────────────┐ ║
║  │       RESEARCH TIMELINE               │  │           KNOWLEDGE STAMINA                      │ ║
║  │       ══════════════════              │  │           ══════════════════                     │ ║
║  │                                       │  │                                                  │ ║
║  │   ▓▓▓░░░░░░░▓▓▓▓▓▓▓▓░░░░░░▓▓▓░░░     │  │   ┌─────────────────────────────────────────┐   │ ║
║  │   6am      10am      2pm      6pm     │  │   │          CURRENT: 72%                   │   │ ║
║  │                                       │  │   │  ████████████████████████░░░░░░░░░░░░   │   │ ║
║  │   Peak: 2pm-4pm (42 min focused)      │  │   └─────────────────────────────────────────┘   │ ║
║  │   Total Today: 2h 15m                 │  │                                                  │ ║
║  │   vs Avg: +18%                        │  │   Optimal Window: 2pm - 4pm                     │ ║
║  │                                       │  │   Recharge needed: ~45 min break                │ ║
║  │   ───────────────────────────────     │  │                                                  │ ║
║  │   THIS WEEK:                          │  │   STAMINA FACTORS:                              │ ║
║  │   M: 1h52 | T: 2h18 | W: 1h45        │  │   ● Sleep Quality: +15%                         │ ║
║  │   T: 2h31 | F: 2h15 (today)          │  │   ● Caffeine: +8%                               │ ║
║  │   Total: 10h 41m                      │  │   ○ Afternoon Slump: -12%                       │ ║
║  │                                       │  │                                                  │ ║
║  └──────────────────────────────────────┘  └──────────────────────────────────────────────────┘ ║
║                                                                                                  ║
║  ┌───────────────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                                   RECENT CAPTURES                                          │  ║
║  │  ═════════════════════════════════════════════════════════════════════════════════════    │  ║
║  │                                                                                            │  ║
║  │   ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────┐  │  ║
║  │   │ 📄 PAPER            │  │ 💡 IDEA             │  │ 🔗 BOOKMARK         │  │ + MORE  │  │  ║
║  │   │ ─────────────────   │  │ ─────────────────   │  │ ─────────────────   │  │ ─────── │  │  ║
║  │   │                     │  │                     │  │                     │  │         │  │  ║
║  │   │ "Attention Is All   │  │ "Connect deep work  │  │ "SwiftUI Navigation │  │  View   │  │  ║
║  │   │ You Need" - Vaswani │  │ sessions to HRV     │  │ Stack Best Practices│  │   47    │  │  ║
║  │   │                     │  │ recovery patterns"  │  │                     │  │captures │  │  ║
║  │   │ 🏷 ML, Transformers │  │ 🏷 Productivity     │  │ 🏷 iOS, Swift       │  │         │  │  ║
║  │   │ 📊 12 connections   │  │ 📊 3 connections    │  │ 📊 7 connections    │  │    →    │  │  ║
║  │   │ ⏱ 2 hours ago       │  │ ⏱ 45 min ago       │  │ ⏱ 15 min ago       │  │         │  │  ║
║  │   └─────────────────────┘  └─────────────────────┘  └─────────────────────┘  └─────────┘  │  ║
║  │                                                                                            │  ║
║  │   ◀ ═══════════════════════════════════════════════════════════════════════════════ ▶     │  ║
║  │                                                                                            │  ║
║  └───────────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                                  ║
║  ╔═══════════════════════════════════════════════════════════════════════════════════════════╗  ║
║  ║                                   CLUSTER INSIGHTS                                         ║  ║
║  ║  ─────────────────────────────────────────────────────────────────────────────────────    ║  ║
║  ║                                                                                            ║  ║
║  ║   ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐               ║  ║
║  ║   │  GROWING CLUSTER    │  │  DORMANT CLUSTER    │  │  EMERGING LINK      │               ║  ║
║  ║   │  ═══════════════    │  │  ═══════════════    │  │  ═══════════════    │               ║  ║
║  ║   │                     │  │                     │  │                     │               ║  ║
║  ║   │  Machine Learning   │  │  Cooking Recipes    │  │  ML ↔ Productivity  │               ║  ║
║  ║   │  +8 nodes this week │  │  No access: 23 days │  │  Strength: 0.67     │               ║  ║
║  ║   │  Density: 0.89      │  │  Consider archiving?│  │  "Focus optimization│               ║  ║
║  ║   │                     │  │                     │  │  via attention..."  │               ║  ║
║  ║   └─────────────────────┘  └─────────────────────┘  └─────────────────────┘               ║  ║
║  ║                                                                                            ║  ║
║  ╠═══════════════════════════════════════════════════════════════════════════════════════════╣  ║
║  ║  ◆ PREDICTION                                                            CONFIDENCE: 79%  ║  ║
║  ║  ────────────────────────────────────────────────────────────────────────────────────────  ║  ║
║  ║  IF: You continue current research velocity in "Transformers" cluster                     ║  ║
║  ║  THEN: Knowledge Dimension will level up in ~4 days (currently 340/500 XP)                ║  ║
║  ║                                                                                            ║  ║
║  ║  SUGGESTED EXPLORATION: "Mixture of Experts" paper would bridge 3 existing clusters       ║  ║
║  ║                                                                                            ║  ║
║  ║  ┌───────────────────────────────────────────────────────────────────────────────────┐    ║  ║
║  ║  │   [📖 Read Suggestion]       [🔍 Find Gaps]       [📊 Cluster Analytics]          │    ║  ║
║  ║  └───────────────────────────────────────────────────────────────────────────────────┘    ║  ║
║  ╚═══════════════════════════════════════════════════════════════════════════════════════════╝  ║
║                                                                                                  ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### Node Detail Overlay

When user taps a node in the constellation:

```
NODE DETAIL PANEL
═══════════════════════════════════════════════════════════════════
┌─────────────────────────────────────────────────────────────────┐
│  GPT (Large Language Model)                              [✕]    │
│  ═══════════════════════════                                    │
│                                                                  │
│  CLUSTER: Transformers                                          │
│  CREATED: Nov 15, 2024                                          │
│  LAST ACCESSED: 2 hours ago                                     │
│  ACCESS COUNT: 47                                               │
│                                                                  │
│  ─────────────────────────────────────────────────────────────  │
│                                                                  │
│  CONNECTED TO:                                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  ● BERT (0.89) ────── Same architecture family            │  │
│  │  ● LLaMA (0.82) ───── Open source alternative             │  │
│  │  ● Attention (0.94) ─ Core mechanism                      │  │
│  │  ● Tokenizers (0.71) ─ Preprocessing                      │  │
│  │  ○ RLHF (0.45) ────── Training method                     │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  RECENT NOTES:                                                   │
│  • "GPT-4 shows emergent reasoning capabilities at scale"       │
│  • "Context window expansion via sparse attention"              │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  [📝 Add Note]    [🔗 Link Node]    [🗑 Archive]           │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Extended Data Requirements

```swift
struct KnowledgeDimensionData {
    // Flow Metrics
    var capturesToday: Int                          // Ideas/notes captured
    var capturesChange: Int                         // vs yesterday
    var processedToday: Int                         // Embeddings generated
    var connectionsToday: Int                       // Links discovered
    var semanticDensity: Double                     // Graph connectivity 0-1

    // Constellation Graph
    var nodes: [KnowledgeNode]                      // All knowledge nodes
    var edges: [KnowledgeEdge]                      // Connections between nodes
    var clusters: [KnowledgeCluster]                // Topic groupings
    var activeNodes: Set<UUID>                      // Recently accessed
    var dormantNodes: Set<UUID>                     // 7+ days untouched

    // Research Activity
    var researchTimeline: [HourlyResearch]          // Activity per hour
    var peakResearchWindow: DateInterval            // Most productive hours
    var totalResearchToday: TimeInterval            // Total focused time
    var weeklyResearchData: [DailyResearch]         // Week breakdown

    // Knowledge Stamina
    var knowledgeStamina: Double                    // Current capacity 0-100
    var optimalWindow: DateInterval                 // Best learning time
    var rechargeNeeded: TimeInterval                // Suggested break
    var staminaFactors: [StaminaFactor]             // Contributing elements

    // Recent Captures
    var recentCaptures: [KnowledgeCapture]          // Latest additions
    var capturesByType: [CaptureType: Int]          // Paper, Idea, Bookmark, etc.

    // Cluster Insights
    var growingClusters: [KnowledgeCluster]         // Expanding topics
    var dormantClusters: [KnowledgeCluster]         // Inactive topics
    var emergingLinks: [EmergingConnection]         // New relationships

    // Predictions
    var predictions: [KnowledgePrediction]          // AI suggestions
    var suggestedExplorations: [ExplorationSuggestion]  // Gap-filling recs
}

struct KnowledgeNode {
    var id: UUID
    var title: String
    var type: NodeType                              // Concept, Paper, Idea, Bookmark
    var cluster: UUID?                              // Parent cluster
    var createdDate: Date
    var lastAccessedDate: Date
    var accessCount: Int
    var embedding: [Float]                          // Semantic vector
    var notes: [String]                             // Associated notes
    var tags: [String]                              // Manual labels
    var isActive: Bool                              // Accessed in last 7 days
}

struct KnowledgeEdge {
    var id: UUID
    var sourceNode: UUID
    var targetNode: UUID
    var strength: Double                            // Connection strength 0-1
    var edgeType: EdgeType                          // Semantic, Manual, Citation
    var createdDate: Date
    var description: String?                        // Why connected
}

struct KnowledgeCluster {
    var id: UUID
    var name: String
    var nodes: [UUID]                               // Member node IDs
    var density: Double                             // Internal connectivity
    var color: Color                                // Display color
    var lastActivityDate: Date
    var growthRate: Double                          // Nodes added per week
    var isDormant: Bool                             // No activity 14+ days
}

struct KnowledgeCapture {
    var id: UUID
    var title: String
    var type: CaptureType                           // Paper, Idea, Bookmark, Note
    var timestamp: Date
    var tags: [String]
    var connectionCount: Int                        // Links discovered
    var sourceURL: URL?                             // If external
    var preview: String                             // First 100 chars
}

struct StaminaFactor {
    var name: String                                // Sleep Quality, Caffeine, etc.
    var impact: Double                              // +/- percentage
    var isPositive: Bool
}

struct EmergingConnection {
    var cluster1: KnowledgeCluster
    var cluster2: KnowledgeCluster
    var strength: Double
    var bridgingConcept: String                     // What links them
    var potentialInsight: String                    // AI-generated description
}
```

### Animation Sequences

**Constellation Entry (1200ms)**:
1. 0-300ms: Core cluster nodes fade in with scale-up
2. 300-600ms: Secondary nodes appear with staggered timing
3. 600-900ms: Edges draw outward from center nodes with glow trail
4. 900-1200ms: Auto-orbit begins with slow rotation
5. Continuous: Active nodes pulse subtly, edges shimmer

**Node Selection (400ms)**:
1. 0-100ms: Selected node scales up 1.3x with glow intensify
2. 100-200ms: Connected nodes highlight, others dim to 30%
3. 200-300ms: Connection lines brighten with flowing particles
4. 300-400ms: Detail panel slides in from right
5. Continuous: Selected node has breathing glow

**Cluster Focus (600ms)**:
1. 0-200ms: Camera zooms to selected cluster
2. 200-400ms: Other clusters fade to 20% opacity
3. 400-600ms: Cluster nodes spread slightly for visibility
4. Gesture: Pinch out to return to full view

**New Capture Animation (800ms)**:
1. 0-200ms: New node appears with expanding ring effect
2. 200-400ms: AI-discovered edges draw to related nodes
3. 400-600ms: Node settles into cluster position via physics
4. 600-800ms: +XP particle burst from node center

---

## 3.6 REFLECTION DIMENSION

### Concept: "The Inner Sanctum"

A meditative, softer interface for introspection — emotional patterns, journaling insights, and inner growth. Think Headspace meets personal analytics with serene visualization.

### Layout Diagram

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════╗
║  ◀ Sanctuary            REFLECTION  •  INNER SANCTUM                                             ║
║  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  ║
║                                        Level 15 • Rank: SAGE                                     ║
╠══════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                  ║
║  ╔═══════════════════════════════════════════════════════════════════════════════════════════╗  ║
║  ║                                 EMOTIONAL LANDSCAPE                                        ║  ║
║  ║  ═════════════════════════════════════════════════════════════════════════════════════    ║  ║
║  ║                                                                                            ║  ║
║  ║   HIGH ENERGY                                                                              ║  ║
║  ║        │                                                                                   ║  ║
║  ║     +1 │              😤                         😄  ●                                    ║  ║
║  ║        │                    😊                              😆                            ║  ║
║  ║        │         😠                    😌                                                 ║  ║
║  ║      0 ├──────────────────────●───────────────────────────────────────────                ║  ║
║  ║        │                   😐       😊                                                    ║  ║
║  ║        │      😔                         😌   ●TODAY                                      ║  ║
║  ║     -1 │  😢                                      😴                                      ║  ║
║  ║        │                                                                                   ║  ║
║  ║   LOW ENERGY                                                                               ║  ║
║  ║        └────────────────────────────────────────────────────────────────────────          ║  ║
║  ║     NEGATIVE                         NEUTRAL                         POSITIVE             ║  ║
║  ║        -1                              0                               +1                  ║  ║
║  ║                                                                                            ║  ║
║  ║   ─────────────────────────────────────────────────────────────────────────────────────   ║  ║
║  ║                                                                                            ║  ║
║  ║   TODAY'S MOOD:  ● Positive (+0.6)  • Moderate Energy (0.5)                               ║  ║
║  ║   WEEK AVG:      ○ Slightly Positive (+0.4) • Variable Energy                             ║  ║
║  ║   TREND:         ↗ Valence improving over past 7 days                                     ║  ║
║  ║                                                                                            ║  ║
║  ║   MOOD TIMELINE (Today)                                                                   ║  ║
║  ║   ┌───────────────────────────────────────────────────────────────────────────────────┐   ║  ║
║  ║   │  6am    8am    10am   12pm    2pm    4pm    6pm    8pm    10pm                    │   ║  ║
║  ║   │   │      │       │      │      │      │      │      │       │                     │   ║  ║
║  ║   │   😴─────😐──────😊─────😄─────😌─────😊─────😌─────●──────                      │   ║  ║
║  ║   │   low   rising  good   peak   calm   good   relax  now                            │   ║  ║
║  ║   └───────────────────────────────────────────────────────────────────────────────────┘   ║  ║
║  ║                                                                                            ║  ║
║  ╚═══════════════════════════════════════════════════════════════════════════════════════════╝  ║
║                                                                                                  ║
║  ┌───────────────────────────────────────────┐  ┌────────────────────────────────────────────┐  ║
║  │         JOURNALING RHYTHM                  │  │        MEDITATION & STILLNESS              │  ║
║  │         ═════════════════                  │  │        ═════════════════════               │  ║
║  │                                            │  │                                            │  ║
║  │   ┌─────────────────────────────────────┐ │  │   ┌─────────────────────────────────────┐ │  ║
║  │   │  🔥 STREAK: 18 DAYS                  │ │  │   │  TODAY                              │ │  ║
║  │   │     ████████████████████████████     │ │  │   │  ════════════════════════════════  │ │  ║
║  │   │     Personal Best: 23 days           │ │  │   │                                     │ │  ║
║  │   └─────────────────────────────────────┘ │  │   │         ╭─────────────╮              │ │  ║
║  │                                            │  │   │         │     12      │              │ │  ║
║  │   TODAY'S ENTRY                           │  │   │         │   minutes   │              │ │  ║
║  │   ═══════════════                         │  │   │         │   ◉ ◉ ◉ ○   │              │ │  ║
║  │   ┌───────────────────────────────────┐   │  │   │         ╰─────────────╯              │ │  ║
║  │   │  Words: 847                        │   │  │   │                                     │ │  ║
║  │   │  ████████████████████████████████░│   │  │   │  Goal: 15 min  •  80% complete      │ │  ║
║  │   │  vs avg: +34%                      │   │  │   └─────────────────────────────────────┘ │  ║
║  │   └───────────────────────────────────┘   │  │                                            │  ║
║  │                                            │  │   THIS WEEK                               │  ║
║  │   ┌───────────────────────────────────┐   │  │   ═══════════════════════════════════════ │  ║
║  │   │  Depth Score: 7.8/10              │   │  │   ┌───────────────────────────────────┐   │  ║
║  │   │  ████████████████████████████░░░░ │   │  │   │  M    T    W    T    F    S    S  │   │  ║
║  │   │  Deep introspection detected      │   │  │   │  ▓▓▓  ▓▓   ▓▓▓  ▓▓▓▓ ▓▓   ░░   ░░ │   │  ║
║  │   └───────────────────────────────────┘   │  │   │  15   10   18   22   12   --   -- │   │  ║
║  │                                            │  │   └───────────────────────────────────┘   │  ║
║  │   ENTRY PREVIEW                           │  │                                            │  ║
║  │   "Today I felt a shift in my approach    │  │   Total: 84 min                           │  ║
║  │   to creative work. Instead of forcing    │  │   Avg: 14 min/day                         │  ║
║  │   output, I..."         [Continue →]      │  │   Best: Thu (22 min)                      │  ║
║  │                                            │  │                                            │  ║
║  └───────────────────────────────────────────┘  └────────────────────────────────────────────┘  ║
║                                                                                                  ║
║  ╔═══════════════════════════════════════════════════════════════════════════════════════════╗  ║
║  ║                                  RECURRING THEMES                                          ║  ║
║  ║  ─────────────────────────────────────────────────────────────────────────────────────    ║  ║
║  ║                                                                                            ║  ║
║  ║   ┌────────────────┐  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐          ║  ║
║  ║   │    PURPOSE     │  │    GROWTH      │  │    BALANCE     │  │   CREATION     │          ║  ║
║  ║   │    ════════    │  │    ════════    │  │    ════════    │  │   ════════     │          ║  ║
║  ║   │                │  │                │  │                │  │                │          ║  ║
║  ║   │  ██████████████│  │  ████████████░░│  │  ██████████░░░░│  │  ████████░░░░░░│          ║  ║
║  ║   │                │  │                │  │                │  │                │          ║  ║
║  ║   │   47 mentions  │  │   38 mentions  │  │   31 mentions  │  │   24 mentions  │          ║  ║
║  ║   │   ↗ +12 this   │  │   → stable     │  │   ↗ +8 this    │  │   ↘ -5 this    │          ║  ║
║  ║   │      week      │  │                │  │      week      │  │      week      │          ║  ║
║  ║   └────────────────┘  └────────────────┘  └────────────────┘  └────────────────┘          ║  ║
║  ║                                                                                            ║  ║
║  ║   THEME EVOLUTION (30 DAYS)                                                               ║  ║
║  ║   ┌───────────────────────────────────────────────────────────────────────────────────┐   ║  ║
║  ║   │         PURPOSE ═══════════════════════════════════════╗                          │   ║  ║
║  ║   │          GROWTH ═══════════════════════════════════════╝                          │   ║  ║
║  ║   │         BALANCE ════════════════════════╗                                         │   ║  ║
║  ║   │        CREATION ════════════════════════╝                                         │   ║  ║
║  ║   │                                                                                    │   ║  ║
║  ║   │   Week 1          Week 2          Week 3          Week 4                          │   ║  ║
║  ║   └───────────────────────────────────────────────────────────────────────────────────┘   ║  ║
║  ║                                                                                            ║  ║
║  ║   EMERGING THEME: "Intentional Rest" mentioned 6x this week (new pattern detected)       ║  ║
║  ║                                                                                            ║  ║
║  ╚═══════════════════════════════════════════════════════════════════════════════════════════╝  ║
║                                                                                                  ║
║  ╔═══════════════════════════════════════════════════════════════════════════════════════════╗  ║
║  ║                                    ★ GRAIL INSIGHTS                                        ║  ║
║  ║  ─────────────────────────────────────────────────────────────────────────────────────    ║  ║
║  ║                                                                                            ║  ║
║  ║   These are your deepest realizations — breakthrough moments extracted from journaling    ║  ║
║  ║                                                                                            ║  ║
║  ║   ┌─────────────────────────────────────────────────────────────────────────────────────┐ ║  ║
║  ║   │  ★ LATEST GRAIL                                                      Dec 18, 2024   │ ║  ║
║  ║   │  ════════════════════════════════════════════════════════════════════════════════   │ ║  ║
║  ║   │                                                                                      │ ║  ║
║  ║   │  "I realized my resistance to delegation stems from a fear of losing control,       │ ║  ║
║  ║   │  not from distrust of others. The control itself is an illusion I use to           │ ║  ║
║  ║   │  manage anxiety about outcomes I can't predict."                                    │ ║  ║
║  ║   │                                                                                      │ ║  ║
║  ║   │  SOURCE: Journal entry, after 3 consecutive days reflecting on work stress         │ ║  ║
║  ║   │  LINKED TO: Behavioral patterns, Cognitive load correlation                        │ ║  ║
║  ║   │                                                                                      │ ║  ║
║  ║   │  ┌─────────────────────────────────────────────────────────────────────────────┐   │ ║  ║
║  ║   │  │  [📖 Read Full Entry]     [🔗 View Related Patterns]     [📌 Pin to Home]   │   │ ║  ║
║  ║   │  └─────────────────────────────────────────────────────────────────────────────┘   │ ║  ║
║  ║   └─────────────────────────────────────────────────────────────────────────────────────┘ ║  ║
║  ║                                                                                            ║  ║
║  ║   PREVIOUS GRAILS                                                                         ║  ║
║  ║   ┌─────────────────────────────────┐  ┌─────────────────────────────────┐               ║  ║
║  ║   │  ★ Dec 12: "Purpose isn't      │  │  ★ Nov 28: "My creative blocks  │               ║  ║
║  ║   │     found, it's cultivated..."  │  │     mirror my sleep patterns..."│               ║  ║
║  ║   │     [Read →]                    │  │     [Read →]                    │               ║  ║
║  ║   └─────────────────────────────────┘  └─────────────────────────────────┘               ║  ║
║  ║                                                                                            ║  ║
║  ║   Total Grails Discovered: 12  •  This Month: 3                                           ║  ║
║  ║                                                                                            ║  ║
║  ╠═══════════════════════════════════════════════════════════════════════════════════════════╣  ║
║  ║  ◆ PREDICTION                                                            CONFIDENCE: 74%  ║  ║
║  ║  ────────────────────────────────────────────────────────────────────────────────────────  ║  ║
║  ║  IF: You maintain journaling streak for 5 more days                                       ║  ║
║  ║  THEN: Journal Streak badge "Deep Diver" unlocks (+200 XP), depth score projected +0.5   ║  ║
║  ║                                                                                            ║  ║
║  ║  PATTERN EMERGING: Your most insightful entries happen on mornings after 7+ hours sleep  ║  ║
║  ║                                                                                            ║  ║
║  ║  ┌───────────────────────────────────────────────────────────────────────────────────┐    ║  ║
║  ║  │   [✍️ Open Journal]       [🧘 Start Meditation]       [📊 Emotional Analytics]    │    ║  ║
║  ║  └───────────────────────────────────────────────────────────────────────────────────┘    ║  ║
║  ╚═══════════════════════════════════════════════════════════════════════════════════════════╝  ║
║                                                                                                  ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### Grail Insight Detail Overlay

When user taps a Grail Insight:

```
GRAIL INSIGHT DETAIL
═══════════════════════════════════════════════════════════════════════════════════
┌───────────────────────────────────────────────────────────────────────────────────┐
│  ★ GRAIL INSIGHT                                                            [✕]  │
│  ═══════════════                                                                  │
│                                                                                    │
│  "I realized my resistance to delegation stems from a fear of losing control,    │
│  not from distrust of others. The control itself is an illusion I use to         │
│  manage anxiety about outcomes I can't predict."                                  │
│                                                                                    │
│  ─────────────────────────────────────────────────────────────────────────────   │
│                                                                                    │
│  DISCOVERED: December 18, 2024 at 8:42am                                         │
│  SOURCE ENTRY: "Morning Reflection - Work Anxiety"                               │
│  WORD COUNT: 1,247 words in source entry                                         │
│                                                                                    │
│  JOURNEY TO THIS INSIGHT:                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────┐ │
│  │  Dec 15: Noticed frustration when team missed deadline                       │ │
│  │      ↓                                                                        │ │
│  │  Dec 16: Journaled about "needing to do everything myself"                   │ │
│  │      ↓                                                                        │ │
│  │  Dec 17: Connected this to childhood responsibility patterns                 │ │
│  │      ↓                                                                        │ │
│  │  Dec 18: ★ BREAKTHROUGH - Realized control = anxiety management             │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                    │
│  CROSS-DIMENSION CORRELATIONS:                                                    │
│  • Behavioral: Delegation tasks avoided (pattern detected)                       │
│  • Cognitive: Focus drops when team tasks pending                                │
│  • Physiological: HRV lower on days with pending delegations                     │
│                                                                                    │
│  ┌───────────────────────────────────────────────────────────────────────────┐   │
│  │  [📖 Read Full Entry]   [📤 Export]   [🔗 Link to Action]   [📌 Pin]      │   │
│  └───────────────────────────────────────────────────────────────────────────┘   │
│                                                                                    │
└───────────────────────────────────────────────────────────────────────────────────┘
```

### Extended Data Requirements

```swift
struct ReflectionDimensionData {
    // Emotional Landscape
    var emotionalDataPoints: [EmotionalDataPoint]   // All mood data points
    var todayMood: EmotionalState                   // Current state
    var averageValence: Double                      // -1 to +1 scale
    var averageEnergy: Double                       // -1 to +1 scale
    var valenceTrend: TrendDirection                // Improving, Stable, Declining
    var moodTimeline: [HourlyMood]                  // Today's mood journey
    var weeklyMoodData: [DailyMood]                 // 7-day history

    // Journaling
    var journalStreak: Int                          // Consecutive days
    var journalPersonalBest: Int                    // Longest streak
    var wordsToday: Int                             // Today's word count
    var wordsAverage: Int                           // Typical daily count
    var depthScore: Double                          // 0-10 introspection depth
    var todayEntryPreview: String                   // First ~100 chars
    var todayEntryWordCount: Int

    // Meditation
    var meditationToday: TimeInterval               // Minutes today
    var meditationGoal: TimeInterval                // Daily target
    var meditationThisWeek: TimeInterval            // Weekly total
    var meditationWeekData: [DailyMeditation]       // Per-day breakdown
    var meditationStreak: Int                       // Consecutive days
    var averageSessionLength: TimeInterval          // Typical session

    // Themes
    var recurringThemes: [ReflectionTheme]          // Detected patterns
    var themeEvolution: [ThemeHistory]              // 30-day theme tracking
    var emergingThemes: [EmergingTheme]             // Newly detected patterns
    var themeMentionCounts: [String: Int]           // Theme frequency

    // Grail Insights
    var grailInsights: [GrailInsight]               // Breakthrough moments
    var latestGrail: GrailInsight?                  // Most recent
    var totalGrails: Int                            // All-time count
    var grailsThisMonth: Int                        // Recent discoveries
    var pinnedGrails: [GrailInsight]                // User-highlighted

    // Predictions
    var predictions: [ReflectionPrediction]         // AI forecasts
    var insightPatterns: [InsightPattern]           // When breakthroughs happen
}

struct EmotionalDataPoint {
    var timestamp: Date
    var valence: Double                             // -1 (negative) to +1 (positive)
    var energy: Double                              // -1 (low) to +1 (high)
    var emoji: String                               // Representative emoji
    var note: String?                               // Optional context
    var source: MoodSource                          // Manual, Journal, Inferred
}

struct EmotionalState {
    var valence: Double
    var energy: Double
    var description: String                         // "Positive & Calm"
    var emoji: String
    var comparedToAverage: String                   // "Better than usual"
}

struct ReflectionTheme {
    var id: UUID
    var name: String                                // "Purpose", "Growth", etc.
    var mentionCount: Int                           // Total occurrences
    var weeklyChange: Int                           // +/- vs last week
    var trend: TrendDirection
    var color: Color
    var relatedKeywords: [String]                   // Terms that map to this theme
    var lastMentioned: Date
}

struct GrailInsight {
    var id: UUID
    var content: String                             // The insight text
    var discoveredDate: Date
    var sourceEntryId: UUID                         // Link to journal entry
    var sourceEntryTitle: String
    var sourceWordCount: Int
    var journey: [InsightJourneyStep]               // How insight was reached
    var crossDimensionLinks: [DimensionLink]        // Related patterns
    var isPinned: Bool
    var tags: [String]
}

struct InsightJourneyStep {
    var date: Date
    var description: String                         // What happened
    var entryId: UUID?                              // Related journal entry
    var isBreakthrough: Bool                        // The "aha" moment
}

struct DimensionLink {
    var dimension: LevelDimension
    var description: String                         // How it connects
    var strength: Double                            // Correlation strength
}

struct HourlyMood {
    var hour: Int                                   // 0-23
    var state: EmotionalState
    var label: String                               // "rising", "peak", etc.
}

struct InsightPattern {
    var description: String                         // When insights happen
    var conditions: [String]                        // Contributing factors
    var confidence: Double
}
```

### Animation Sequences

**Emotional Landscape Entry (800ms)**:
1. 0-200ms: Axis lines draw in from center
2. 200-500ms: Mood dots fade in with stagger, newest first
3. 500-700ms: Today's position highlights with pulse
4. 700-800ms: Trend line draws connecting recent points
5. Continuous: Today's dot has gentle breathing glow

**Grail Insight Reveal (1200ms)**:
1. 0-300ms: Golden star icon expands with burst
2. 300-600ms: Insight text types in character by character
3. 600-900ms: Connection lines draw to related dimensions
4. 900-1200ms: XP particles cascade down
5. Sound: Soft chime plays at 300ms

**Theme Bar Animation (500ms)**:
1. 0-200ms: Bar fills from left with theme color
2. 200-400ms: Count number animates up
3. 400-500ms: Trend arrow slides in with color flash
4. Hover: Bar glows, shows related keywords tooltip

**Meditation Timer Complete (600ms)**:
1. 0-200ms: Circle fills with calming green
2. 200-400ms: Checkmark draws in center
3. 400-600ms: "Complete" text fades in below
4. Sound: Gentle bell at completion

---

# PART IV: GLOBAL SYSTEMS

## 4.1 Predictions Module

Every dimension includes prediction capabilities with unified design.

```
PREDICTION CARD:
├── Icon: ◆ (diamond) in amber
├── Confidence badge: top-right
├── "If... then..." format
├── "Based on:" explanation
├── Action buttons: Remind Me, See Data
└── Material: Glass-Accent with amber tint
```

## 4.2 Real-Time RPG Feel

### XP Particle System
- Gold particles burst on achievements
- GPU-instanced, <0.1ms render time
- 10-50 particles based on XP amount

### Level Up Sequence (2500ms)
1. Build-up: screen dims, rings accelerate
2. Flash: brief white flash, number transforms
3. Celebration: "LEVEL UP" text, particles
4. Settle: returns to normal

### Stat Change Animations
- Number count-up/down over 400ms
- Color flash for direction
- Progress bars with spring overshoot

### Constellation Line Animations
- Lines draw outward from tapped node
- 400ms per connection level
- Glow follows drawing line
- Info cards appear at endpoints

---

# PART V: APPLE SILICON OPTIMIZATION

## Metal 3.1 Shader Pipeline

```
VERTEX SHADERS:
├── orb_vertex: Transform orb geometry
├── particle_vertex: Instanced positioning
├── line_vertex: Bezier tessellation
└── body_vertex: Skeletal animation

FRAGMENT SHADERS:
├── orb_fragment: Gradients, glow, noise
├── glass_fragment: Blur, refraction
├── particle_fragment: Additive blend
├── heatmap_fragment: Color mapping
└── aurora_fragment: Procedural background

COMPUTE SHADERS:
├── particle_physics: Position updates
├── blur_compute: Variable radius Gaussian
├── graph_layout: Force-directed physics
└── noise_generate: Perlin/simplex
```

## Performance Targets

| Metric | Target |
|--------|--------|
| Frame Rate | 120fps sustained |
| Transition Latency | <16ms |
| Particle Count | 50,000+ |
| Memory Footprint | <200MB |
| Battery Impact | <5%/hour |

## Neural Engine Integration

- Insight correlation highlighting
- Predictive pre-rendering
- Animation curve optimization
- Semantic theme detection

---

# PART VI: DESIGN TOKENS

```swift
enum CosmoTokens {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Duration {
        static let instant: Double = 0.1
        static let fast: Double = 0.2
        static let normal: Double = 0.35
        static let slow: Double = 0.5
        static let cinematic: Double = 0.8
    }
}
```

---

# PART VII: IMPLEMENTATION ROADMAP

## Phases

1. **Foundation**: Metal pipeline, design tokens, animation choreographer
2. **Home Sanctuary**: Hero orb, dimension ring, insight stream
3. **Cognitive**: Mind core, focus rings, correlation system
4. **Creative**: Analytics HUD, post carousel, predictions
5. **Physiological**: 3D body mesh, heatmaps, vitals panel
6. **Behavioral**: Discipline index, streaks, routines
7. **Knowledge**: 3D constellation, force physics, captures
8. **Reflection**: Emotional landscape, journaling, themes
9. **Polish**: Particles, level-ups, haptics, sounds
10. **Neural Engine**: ML models, predictive loading

---

**Document Version**: 2.0
**Last Updated**: December 2025
**Author**: Lead UI/UX Architect
